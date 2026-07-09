# Contributing to PaisleyTerm

Thanks for your interest! PaisleyTerm is a small, focused codebase — a good afternoon read. Start with [ARCHITECTURE.md](ARCHITECTURE.md).

## Building

Xcode Command Line Tools are sufficient; full Xcode is not required.

```bash
swift build
# run with proper window focus:
cp .build/debug/PaisleyTerm PaisleyTerm.app/Contents/MacOS/PaisleyTerm
open PaisleyTerm.app
```

SSH sessions require macOS 15+; the local terminal works on macOS 14.

## Linting & the pre-commit hook

The project lints with [SwiftLint](https://github.com/realm/SwiftLint) (config in
`.swiftlint.yml`). Install it:

```bash
# macOS
brew install swiftlint

# Linux (prebuilt static binary from the SwiftLint releases)
curl -sSL https://github.com/realm/SwiftLint/releases/latest/download/swiftlint_linux_amd64.zip -o /tmp/sl.zip
unzip -o /tmp/sl.zip -d /tmp/sl && install -m0755 /tmp/sl/swiftlint-static ~/.local/bin/swiftlint
```

A pre-commit hook in `.githooks/` runs SwiftLint on staged Swift files and blocks the
commit on error-severity violations. Enable it once per clone:

```bash
git config core.hooksPath .githooks
```

Most style issues are warnings (they won't block) and are auto-fixable with
`swiftlint --fix <files>`. CI also runs SwiftLint on every push/PR.

### Zero-warning builds & a known follow-up

`Package.swift` compiles with `-warnings-as-errors`, but **only on `PaisleyCore`**
for now. The macOS `PaisleyTerm` app target has pre-existing Swift-6 concurrency
warnings that newer toolchains surface — e.g. cross-actor access of `@MainActor`
`SSHSession` state from the `SSHService` actor (`let profile = session.profile`
should be `await`ed, and `ConnectionProfile`/`AgentStatus` want `Sendable`
conformance). Cleaning those up (and then re-adding `swiftSettings: strictWarnings`
to the `PaisleyTerm` target) is a good follow-up — do it on a Mac where the app
target actually compiles, since it can't be built on Linux.

## Testing: read this before writing tests

**The `PaisleyCore` engine is unit-tested; the macOS UI is not.** Run the suite with
`swift test` — it exercises the agent-output parsers, the pure text-analysis helpers,
`ConnectionProfile`, and `ProfileStore` (`Tests/PaisleyCoreTests`). It runs on Linux with
the swift.org toolchain and on GitHub's macOS runners, both of which ship XCTest. The old
"testing is unworkable" note was a Command Line Tools limitation only (the `xctest` runner
lives inside Xcode.app); it does not apply to a full toolchain. **When you change parsing
or profile logic, add or update tests there** rather than relying on the manual checklist.

What tests do *not* cover is the SwiftUI/AppKit UI and live terminal behavior. For that,
**[REGRESSION_CHECKLIST.md](REGRESSION_CHECKLIST.md) is the safety net.** It covers the
areas that have regressed repeatedly and that neither the compiler nor unit tests can
check: the terminal/scroll subsystem (`Views/Terminal/SSHTerminalView.swift`,
`Views/Terminal/TerminalView.swift`) and `Services/AgentMonitor.swift`'s orchestration.

The rules:

1. **If your change touches those files, walk the relevant checklist sections manually before opening a PR**, and say so in the PR description.
2. **If you fix a bug in that subsystem, add a checklist entry** — symptom, minimal repro, expected behavior. The checklist only stays useful if it accumulates.

## Pull request expectations

- `swift build` must complete with **zero warnings**, and `swift test` must pass — both are enforced by CI (macOS and Linux).
- Match the surrounding code's style; the codebase favors small, single-purpose files.
- Keep PRs focused — one behavior change per PR.
- Never store secrets outside the Keychain, and never read SSH key material into app state (see [SECURITY.md](SECURITY.md)).

## Good first issues

The issue tracker mirrors the roadmap: SSH key auth, auto-reconnect, dynamic initial PTY size, session-cycling keyboard shortcuts, OpenCode parser calibration, and a host-key fingerprint confirmation UI. Comment on an issue before starting significant work so effort isn't duplicated.
