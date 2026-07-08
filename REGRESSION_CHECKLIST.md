# PaisleyTerm Regression Checklist

PaisleyTerm has no automated test suite. (Both swift-testing and XCTest were evaluated
for this project and found unworkable in the current development environment — Xcode
Command Line Tools without a full Xcode.app install. XCTest has no framework present at
all on this toolchain, and swift-testing compiles but fails to discover/run any tests.
If a full Xcode install is ever added, revisit automated coverage for `AgentMonitor`'s
parsers and `ConnectionProfile`/`ProfileStore`.) Until then, this checklist is the only
regression safety net and
must be walked manually after any change that touches the areas below.

Walk every relevant section after any change to `Services/AgentMonitor.swift`,
`Views/Terminal/SSHTerminalView.swift`, or `Views/Terminal/TerminalView.swift` — these
files have regressed repeatedly and cannot be exercised by a compiler or type checker.

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
