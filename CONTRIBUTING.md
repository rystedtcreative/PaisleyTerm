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

## Testing: read this before writing tests

**There is no automated test suite, deliberately.** Both swift-testing and XCTest were evaluated and found unworkable on a Command Line Tools–only toolchain: XCTest ships no framework there at all, and swift-testing compiles but fails to discover/run any tests. Don't reintroduce a test target without first confirming `swift test` actually reports results in your environment — and note CI runs CLT-style builds too.

Instead, **[REGRESSION_CHECKLIST.md](REGRESSION_CHECKLIST.md) is the regression safety net.** It covers the areas that have regressed repeatedly and that the compiler can't check: the terminal/scroll subsystem (`Views/Terminal/SSHTerminalView.swift`, `Views/Terminal/TerminalView.swift`) and `Services/AgentMonitor.swift`.

The rules:

1. **If your change touches those files, walk the relevant checklist sections manually before opening a PR**, and say so in the PR description.
2. **If you fix a bug in that subsystem, add a checklist entry** — symptom, minimal repro, expected behavior. The checklist only stays useful if it accumulates.

## Pull request expectations

- `swift build` must complete with **zero warnings** — that's the project's quality bar in place of tests.
- Match the surrounding code's style; the codebase favors small, single-purpose files.
- Keep PRs focused — one behavior change per PR.
- Never store secrets outside the Keychain, and never read SSH key material into app state (see [SECURITY.md](SECURITY.md)).

## Good first issues

The issue tracker mirrors the roadmap: SSH key auth, auto-reconnect, dynamic initial PTY size, session-cycling keyboard shortcuts, OpenCode parser calibration, and a host-key fingerprint confirmation UI. Comment on an issue before starting significant work so effort isn't duplicated.
