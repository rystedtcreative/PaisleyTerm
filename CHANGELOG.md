# Changelog

All notable changes to PaisleyTerm are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-07-08

Initial public release.

### Added
- SSH session manager with sidebar navigation; each session gets a full SwiftTerm terminal over a Citadel PTY (macOS 15+)
- Local terminal sessions (macOS 14+)
- Connection profiles persisted as secret-free JSON; passwords stored exclusively in the macOS Keychain
- Live AI-agent status dashboard: per-session color-coded status dots driven by parsing terminal output for Claude Code and OpenCode (thinking / executing / waiting / complete / error)
- Right-click agent controls per session: Install, Add to PATH, Launch, Stop
- Trust-on-first-use SSH host key validation with persistent known-hosts pinning and mismatch refusal
- Drag-and-drop file path insertion into terminal panes
- Dracula-themed UI with frosted-glass detail pane

### Known limitations
- Password authentication only (SSH key auth planned)
- No automatic reconnect on dropped connections
- Initial PTY size fixed at 220×50 (live resize after connect works)
- OpenCode status patterns need calibration against more real-world output
