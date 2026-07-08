# PaisleyTerm Architecture

Native Swift/SwiftUI macOS app. SSH via [Citadel](https://github.com/orlandos-nl/Citadel) (SwiftNIO), terminal emulation via [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), Swift Package Manager build.

## Project structure

```
PaisleyTerm/
├── Package.swift
├── REGRESSION_CHECKLIST.md          Manual regression suite (see CONTRIBUTING.md)
└── Sources/PaisleyTerm/
    ├── PaisleyTermApp.swift         @main App scene, ⌘N shortcut
    ├── AppState.swift               ObservableObject: sessions, SSH lifecycle, agent lifecycle
    ├── DraculaTheme.swift           Color palette
    ├── Models/
    │   ├── ConnectionProfile.swift  Codable SSH config (no secrets)
    │   ├── SSHSession.swift         Active session state + outputSubject fan-out
    │   └── AgentStatus.swift        AgentStatus enum + AgentType enum
    ├── Services/
    │   ├── SSHService.swift         Citadel actor: connect/write/resize/disconnect
    │   ├── HostKeyStore.swift       TOFU host key validator + known-hosts persistence
    │   ├── CredentialStore.swift    Keychain read/write wrapper (Security framework)
    │   ├── ProfileStore.swift       JSON persistence for ConnectionProfiles
    │   └── AgentMonitor.swift       Stdout stream parser → AgentStatus updates
    └── Views/
        ├── ContentView.swift        NavigationSplitView: sidebar | terminal
        ├── Sidebar/
        │   ├── SidebarView.swift    Session list + toolbar + right-click context menus
        │   ├── SessionRowView.swift Status dot (pulsing when active) + labels
        │   └── AddConnectionSheet.swift  Form: host/port/user/auth
        ├── Terminal/
        │   ├── TerminalContainerView.swift  Switches views by connection state
        │   ├── TerminalView.swift           LocalProcessTerminalView (local shell)
        │   └── SSHTerminalView.swift        NSViewRepresentable wiring SwiftTerm ↔ SSHSession
        └── AgentControls/
            └── AgentContextMenu.swift  Right-click: Install / Add to PATH / Launch / Stop per agent
```

## Data flow (SSH sessions)

```
SSH channel → SSHService read loop
                    ↓
           session.outputSubject (PassthroughSubject<Data, Never>)
              ↙               ↘
  SSHTerminalView          AgentMonitor
  (feeds SwiftTerm)        (parses stdout → AgentStatus)
```

Each session's raw output is published once and fanned out: the terminal view renders it, and `AgentMonitor` independently parses the same bytes for agent-state signals. Neither consumer affects the other.

## SSHService PTY design

Citadel's interactive shell API (`withPTY`) is closure-based and `@available(macOS 15.0, *)`. It's bridged to async/await with `withCheckedThrowingContinuation`: the continuation resumes (returning a `TTYStdinWriter`) when the PTY channel opens, while the closure stays alive in a background `Task` reading output. Cancelling the task closes the channel. On macOS 14, `connect()` throws `SSHServiceError.requiresMacOS15`.

Input is funneled through a per-session `AsyncStream` queue with a single sequential consumer, so PTY writes reach the channel in enqueue order even when producers (keystrokes, mouse-wheel reports) fire synchronously from the main thread.

## Host key validation

`TOFUHostKeyValidator` (in `Services/HostKeyStore.swift`) implements trust-on-first-use: the first connection to a `host:port` records the server's public key in `~/Library/Application Support/PaisleyTerm/known_hosts.json`; every later connection requires an exact match, and a mismatch fails the connection with both fingerprints in the error. NIOSSH's validation callback doesn't receive the host, so each connection constructs a validator with its `host:port` baked in, passed to Citadel via `SSHHostKeyValidator.custom(_:)`.

## Key models

```swift
enum AgentStatus: Equatable {
    case inactive, idle, thinking, executing, waiting, complete, error(String)
}

enum AgentType: String, CaseIterable {
    case claudeCode = "claude"
    case openCode   = "opencode"
}

enum ConnectionStatus {
    case disconnected, connecting, connected, error(String)
}
```

## Agent status detection

Status is inferred by parsing terminal stdout — no per-server config required. Each agent type conforms to `AgentOutputParser` in `AgentMonitor.swift`.

**Claude Code patterns:**
- Spinner chars `·✢✳✶✽` → `.thinking`
- `Tool:` / `Bash(` / `Running:` / `Write(` / `Read(` / `Edit(` / `Glob(` / `Grep(` / `WebFetch(` → `.executing`
- `Do you want to proceed?` / `[y/N]` / `[Y/n]` → `.waiting`
- `Error:` / `✗` → `.error(message)`

**OpenCode patterns:**
- Full Braille Patterns block (U+2800–U+28FF) + common spinner glyphs → `.thinking` (Unicode.Scalar set, robust to chunking)
- Case-insensitive labels (`thinking`, `working`, `generating`, `esc to interrupt`, …) → `.thinking`
- Real tool tokens only (`Bash(`, `Edit(`, `Tool:`, `Running:`, …) → `.executing`; box-drawing chrome (`╭─`) is deliberately ignored
- Permission/confirmation prompts → `.waiting`

### Agent launch

Right-clicking a connected session row opens per-agent submenus with Install / Add to PATH / Launch. The app writes the CLI command + newline to that session's stdin; `AgentMonitor` subscribes to `outputSubject` and starts parsing. "Stop Agent" sends Ctrl-C (`0x03`).

### Status dot colors

| Status | Color |
|---|---|
| inactive / disconnected | gray |
| connecting | yellow |
| idle / connected (no agent) | green |
| thinking | yellow |
| executing | orange |
| waiting for input | blue |
| complete | teal |
| error | red |

`SessionRowView` applies a pulsing ring animation whenever status is `.thinking` or `.executing`.

## Persistence & credentials

- **Profiles:** secret-free JSON at `~/Library/Application Support/PaisleyTerm/profiles.json` (`ProfileStore`)
- **Passwords:** macOS Keychain only, via `CredentialStore` (Security framework); profiles hold a Keychain ID, never the secret
- **SSH keys:** file *paths* only are stored — key material is never read into app state
- **Known hosts:** `known_hosts.json` next to profiles (see Host key validation)
