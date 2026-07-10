# PaisleyTerm Regression Checklist

The platform-agnostic engine now has automated coverage. The `PaisleyCore` library
target (agent-output parsers, the pure text-analysis helpers, `ConnectionProfile`,
`ProfileStore`) is unit-tested under `Tests/PaisleyCoreTests`; run it with `swift test`.
These tests run on Linux with the open-source swift.org toolchain, which bundles XCTest —
so the earlier "unworkable" note (an Xcode Command Line Tools limitation, where the
`xctest` runner lives only inside Xcode.app) no longer applies. Add to that suite whenever
you touch parsing or profile logic.

What automated tests do **not** cover is the macOS SwiftUI/AppKit UI and the live terminal
behavior — SwiftTerm rendering, scroll forwarding, alt-screen mouse reporting. Those need
either XCUITest on a Mac with full Xcode (a possible future track) or manual verification.
Until that exists, this checklist is the safety net for the UI and
must be walked manually after any change that touches the areas below.

Walk every relevant section after any change to `Services/AgentMonitor.swift`,
`Views/Terminal/SSHTerminalView.swift`, or `Views/Terminal/TerminalView.swift` — these
files have regressed repeatedly and their UI/terminal behavior cannot be exercised by a
compiler or type checker. (The parsing logic `AgentMonitor` used to own now lives in
`PaisleyCore` and *is* unit-tested — extend those tests rather than relying on this walk
for parser changes.)

## Scroll forwarding (regressed previously: "Fix TUI scroll forwarding")
- [ ] Connect to a session, run `ls` repeatedly to fill scrollback.
- [ ] Scroll up with trackpad/mouse wheel in the terminal pane — output scrolls smoothly, no jump-to-bottom.
- [ ] Scroll back down — reaches live output cleanly.

## Scroll sensitivity (regressed previously: "Tune scroll sensitivity")
- [ ] A single trackpad scroll gesture moves a reasonable number of lines (not 1 line, not the entire screen).
- [ ] Fast flick scroll doesn't overshoot wildly past intended content.

## Full-screen TUI scroll (regressed previously: "Corrected scroll behavior in full-screen TUIs")
- [ ] Launch a full-screen TUI over SSH (e.g. `top`, `htop`, or an agent's alt-screen mode).
- [ ] Scroll while the TUI is in the alternate screen buffer — the gesture is either correctly forwarded to the TUI's own scroll handling or correctly suppressed (no corrupted redraw).
- [ ] Exit the TUI — normal scrollback scrolling resumes correctly.

## Scrollbar hiding (regressed previously: "Remove SwiftTerm legacy scrollbar")
- [ ] No native NSScroller/legacy scrollbar is visible in any terminal pane, local or SSH.

## Sidebar status dot updates
- [ ] Launch Claude Code in a connected session — dot transitions gray → green → yellow (thinking) → orange (executing) as expected.
- [ ] Trigger a permission prompt — dot turns blue.
- [ ] Stop the agent (Ctrl-C via context menu) — dot returns to inactive/idle correctly.

## Agent launch/stop
- [ ] Right-click → Install / Add to PATH / Launch for both Claude Code and OpenCode completes without leaving a stuck status.
- [ ] "Stop Agent" reliably interrupts a running agent and status resets.

---

When you fix a bug in this subsystem, add a new checklist entry above describing the
symptom, the minimal repro steps, and the expected (fixed) behavior — this file only
stays useful if it accumulates.
