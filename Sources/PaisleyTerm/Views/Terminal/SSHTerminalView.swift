import SwiftUI
import SwiftTerm
import AppKit
import Combine
import os

// MARK: - Translucent TerminalView

/// SwiftTerm's setupOptions() stamps an opaque default onto layer.backgroundColor
/// after makeBackingLayer() runs, so the makeBackingLayer override alone isn't
/// enough. viewDidMoveToWindow fires after all init is complete and gets the
/// final word on the layer state.
private final class TranslucentTerminalView: TerminalView {
    override var isOpaque: Bool { false }

    override func makeBackingLayer() -> CALayer {
        let layer = super.makeBackingLayer()
        layer.isOpaque = false
        layer.backgroundColor = CGColor.clear
        return layer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.isOpaque = false
        layer?.backgroundColor = CGColor.clear
        registerForDraggedTypes([.fileURL])
    }

    // Hide SwiftTerm's NSScroller the moment it is added as a subview (during
    // SwiftTerm's own init). This fires synchronously before any window
    // attachment, so there is no race with viewDidMoveToWindow.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if subview is NSScroller { subview.isHidden = true }
    }
}

// MARK: - Alternate-scroll forwarding

/// SwiftTerm's `scrollWheel` unconditionally scrolls the local scrollback buffer, and it's
/// declared `public` (not `open`), so it can't be overridden from a subclass in this module.
/// Full-screen TUIs (OpenCode, vim, less, Claude Code) run in the alternate screen buffer, which
/// has no scrollback — so the wheel becomes a no-op, and SwiftTerm never forwards wheel events to
/// the app (no DECSET 1007). We bridge that gap with a single app-wide local event monitor that
/// intercepts scroll events landing on a `TerminalView` and forwards them, the way xterm/iTerm2
/// do ("alternate scroll mode"):
///   1. App requested mouse tracking → send real SGR/X10 wheel events.
///   2. Alternate buffer active     → translate to arrow keys.
///   3. Normal buffer (shell)       → let SwiftTerm scroll its local scrollback (pass through).
enum TerminalScrollForwarder {
    private static var monitor: Any?
    // Weak registry of live terminal views. Used instead of hitTest(_:) — which expects a point
    // in the view's *superview* coordinates and mis-targets across the title-bar offset — so we
    // can locate the scrolled terminal via each view's own coordinate conversion.
    private static let terminals = NSHashTable<TerminalView>.weakObjects()

    // Precise (trackpad) deltas arrive in points; ~15pt of finger travel maps to one line.
    private static let preciseDeltaPointsPerLine: CGFloat = 15
    private static let maxLinesPerEvent = 3
    // Fractional line remainder per view: slow trackpad gestures accumulate across events
    // instead of being floored away, and momentum floods no longer inflate to ≥1 line each.
    private static let accumulators = NSMapTable<TerminalView, NSNumber>.weakToStrongObjects()

    #if DEBUG
    private static let log = Logger(subsystem: "com.paisley.PaisleyTerm", category: "scroll")
    #endif

    /// Idempotent — safe to call from every `makeNSView`.
    static func installIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let term = terminalView(under: event) else { return event }
            // Returning nil swallows the event so SwiftTerm doesn't also scroll; returning the
            // event lets SwiftTerm handle it normally.
            return forward(event, to: term) ? nil : event
        }
    }

    /// Register a terminal view so scroll events over it can be forwarded.
    static func register(_ view: TerminalView) {
        terminals.add(view)
    }

    private static func terminalView(under event: NSEvent) -> TerminalView? {
        guard let window = event.window else { return nil }
        for term in terminals.allObjects where term.window === window {
            let pointInView = term.convert(event.locationInWindow, from: nil)
            if term.bounds.contains(pointInView) { return term }
        }
        return nil
    }

    /// Returns true if the scroll was forwarded to the running program (and should be swallowed).
    private static func forward(_ event: NSEvent, to view: TerminalView) -> Bool {
        // On modern trackpads deltaY is the line-scaled delta; for precise (pixel)
        // scroll gestures it can round to exactly 0.0 even when the finger is
        // moving (scrollingDeltaY will be non-zero). Fall back to scrollingDeltaY
        // so those events are never silently dropped to SwiftTerm's no-op handler.
        let dy: CGFloat = event.deltaY != 0 ? event.deltaY : event.scrollingDeltaY
        guard dy != 0 else { return false }

        let terminal = view.getTerminal()
        let forwardAsMouse = terminal.mouseMode != .off && view.allowMouseReporting
        let forwardAsArrows = !forwardAsMouse && terminal.isCurrentBufferAlternate
        guard forwardAsMouse || forwardAsArrows else { return false }

        // Signed line delta: precise (trackpad) deltas arrive in points and accumulate
        // quickly, so scale them down; classic wheel notches are ~1 each.
        let rawLines: CGFloat = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY / preciseDeltaPointsPerLine
            : dy

        var acc: CGFloat = event.phase == .began
            ? 0
            : CGFloat(accumulators.object(forKey: view)?.doubleValue ?? 0)
        if acc != 0, rawLines != 0, (acc > 0) != (rawLines > 0) { acc = 0 }
        acc += rawLines
        let whole = Int(acc) // truncation toward zero keeps the fractional remainder
        accumulators.setObject(NSNumber(value: Double(acc - CGFloat(whole))), forKey: view)

        let lines = min(maxLinesPerEvent, abs(whole))
        let up = whole > 0

        #if DEBUG
        log.debug("branch=\(forwardAsMouse ? "mouse" : "arrows", privacy: .public) mouseMode=\(String(describing: terminal.mouseMode), privacy: .public) phase=\(event.phase.rawValue) momentum=\(event.momentumPhase.rawValue) rawLines=\(rawLines) emit=\(up ? lines : -lines)")
        #endif

        // Sub-line delta this event: emit nothing, but still swallow the event so
        // SwiftTerm's scrollback handler doesn't consume it.
        guard lines > 0 else { return true }

        if forwardAsMouse {
            // Wheel up = button 4, wheel down = button 5.
            let flags = terminal.encodeButton(button: up ? 4 : 5,
                                               release: false,
                                               shift: false, meta: false, control: false)
            // Report the cell under the pointer so the app routes the wheel to the right region.
            let (col, row) = cell(of: event, in: view, terminal: terminal)
            for _ in 0..<lines { terminal.sendEvent(buttonFlags: flags, x: col, y: row) }
        } else {
            let seq: [UInt8] = up
                ? (terminal.applicationCursor ? EscapeSequences.moveUpApp   : EscapeSequences.moveUpNormal)
                : (terminal.applicationCursor ? EscapeSequences.moveDownApp : EscapeSequences.moveDownNormal)
            for _ in 0..<lines { view.send(seq) }
        }
        return true
    }

    /// Zero-based (col, row) of the pointer in terminal-cell space, clamped to the grid. AppKit's
    /// view origin is bottom-left, so the y axis is flipped to terminal row order (0 = top).
    private static func cell(of event: NSEvent, in view: TerminalView, terminal: Terminal) -> (Int, Int) {
        let p = view.convert(event.locationInWindow, from: nil)
        let cols = terminal.cols, rows = terminal.rows
        guard view.bounds.width > 0, view.bounds.height > 0, cols > 0, rows > 0 else { return (0, 0) }
        // SwiftTerm 1.13 sizes its grid against (bounds.width - scrollerWidth) with the scroller
        // style hardcoded to .legacy — even though we hide the scroller — so dividing raw bounds
        // by cols overestimates the cell width. getOptimalFrameSize() returns
        // (cellW * cols + scrollerWidth, cellH * rows), which recovers the true cell geometry
        // from public API. Re-check this coupling on any SwiftTerm version bump.
        let scrollerW = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        let optimal = view.getOptimalFrameSize()
        let cellW = (optimal.width - scrollerW) / CGFloat(cols)
        let cellH = optimal.height / CGFloat(rows)
        guard cellW > 0, cellH > 0 else { return (0, 0) }
        let col = min(cols - 1, max(0, Int(p.x / cellW)))
        let row = min(rows - 1, max(0, Int((view.bounds.height - p.y) / cellH)))
        return (col, row)
    }
}

extension TranslucentTerminalView {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        guard pb.canReadObject(forClasses: [NSURL.self],
                               options: [.urlReadingFileURLsOnly: true]) else { return [] }
        return .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        guard let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }

        let escaped = urls.map { shellEscapePath($0.path) }.joined(separator: " ")
        send(txt: escaped)
        window?.makeFirstResponder(self)
        return true
    }
}

func shellEscapePath(_ path: String) -> String {
    let safe = CharacterSet.alphanumerics.union(.init(charactersIn: "/_.-"))
    if path.unicodeScalars.allSatisfy({ safe.contains($0) }) { return path }
    return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// MARK: - SSH terminal view

/// Layer stack (bottom → top):
///   1. NSVisualEffectView  — blurs content behind the window
///   2. Tint overlay        — Dracula #282a36 at 82% alpha
///   3. TranslucentTerminalView — transparent canvas; only text + ANSI cells painted
struct SSHTerminalView: NSViewRepresentable {
    typealias NSViewType = NSView

    let session: SSHSession
    var fontSize: CGFloat = 13
    var isSelected: Bool = false

    private static let padding: CGFloat = 8

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> NSView {
        TerminalScrollForwarder.installIfNeeded()

        let fx = NSVisualEffectView(frame: .zero)
        fx.blendingMode = .behindWindow
        fx.material     = .underWindowBackground
        fx.state        = .active
        fx.wantsLayer   = true
        roundCardCorners(of: fx)

        let tint = NSView(frame: .zero)
        tint.translatesAutoresizingMaskIntoConstraints = false
        tint.wantsLayer = true
        tint.layer?.isOpaque = false
        tint.layer?.backgroundColor = NSColor.draculaBg.withAlphaComponent(cardTintOpacity).cgColor

        let termView = TranslucentTerminalView(frame: .zero)
        termView.translatesAutoresizingMaskIntoConstraints = false

        termView.font                  = NSFont.firaCode(size: fontSize)
        termView.nativeForegroundColor = NSColor(hex: "f8f8f2")
        termView.nativeBackgroundColor = .clear
        termView.caretColor            = NSColor(hex: "bd93f9")
        termView.installColors(draculaANSI)

        fx.addSubview(tint)
        fx.addSubview(termView)

        let p = Self.padding
        NSLayoutConstraint.activate([
            tint.topAnchor.constraint(equalTo: fx.topAnchor),
            tint.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: fx.bottomAnchor),

            termView.topAnchor.constraint(equalTo: fx.topAnchor,          constant:  p),
            termView.leadingAnchor.constraint(equalTo: fx.leadingAnchor,   constant:  p),
            termView.trailingAnchor.constraint(equalTo: fx.trailingAnchor, constant: -p),
            termView.bottomAnchor.constraint(equalTo: fx.bottomAnchor,     constant: -p),
        ])

        termView.terminalDelegate = context.coordinator
        context.coordinator.attach(to: termView)
        TerminalScrollForwarder.register(termView)

        return fx
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let termView = nsView.subviews.first(where: { $0 is TerminalView }) as? TerminalView {
            if termView.font.pointSize != fontSize {
                termView.font = NSFont.firaCode(size: fontSize)
            }
            if isSelected {
                DispatchQueue.main.async {
                    termView.window?.makeFirstResponder(termView)
                }
            }
        }
    }
}

// MARK: - Dracula ANSI palette (16-bit, 0-65535 per channel)
// Each 8-bit hex byte 0xNN maps to 16-bit 0xNNNN (byte repeated).

let draculaANSI: [SwiftTerm.Color] = [
    // Normal (0-7)
    SwiftTerm.Color(red: 0x2121, green: 0x2222, blue: 0x2c2c), // 0  Black    #21222c
    SwiftTerm.Color(red: 0xffff, green: 0x5555, blue: 0x5555), // 1  Red      #ff5555
    SwiftTerm.Color(red: 0x5050, green: 0xfafa, blue: 0x7b7b), // 2  Green    #50fa7b
    SwiftTerm.Color(red: 0xf1f1, green: 0xfafa, blue: 0x8c8c), // 3  Yellow   #f1fa8c
    SwiftTerm.Color(red: 0xbdbd, green: 0x9393, blue: 0xf9f9), // 4  Blue     #bd93f9
    SwiftTerm.Color(red: 0xffff, green: 0x7979, blue: 0xc6c6), // 5  Magenta  #ff79c6
    SwiftTerm.Color(red: 0x8b8b, green: 0xe9e9, blue: 0xfdfd), // 6  Cyan     #8be9fd
    SwiftTerm.Color(red: 0xf8f8, green: 0xf8f8, blue: 0xf2f2), // 7  White    #f8f8f2
    // Bright (8-15)
    SwiftTerm.Color(red: 0x6262, green: 0x7272, blue: 0xa4a4), // 8  Br Black  #6272a4
    SwiftTerm.Color(red: 0xffff, green: 0x6e6e, blue: 0x6e6e), // 9  Br Red    #ff6e6e
    SwiftTerm.Color(red: 0x6969, green: 0xffff, blue: 0x9494), // 10 Br Green  #69ff94
    SwiftTerm.Color(red: 0xffff, green: 0xffff, blue: 0xa5a5), // 11 Br Yellow #ffffa5
    SwiftTerm.Color(red: 0xd6d6, green: 0xacac, blue: 0xffff), // 12 Br Blue   #d6acff
    SwiftTerm.Color(red: 0xffff, green: 0x9292, blue: 0xdfdf), // 13 Br Magenta#ff92df
    SwiftTerm.Color(red: 0xa4a4, green: 0xffff, blue: 0xffff), // 14 Br Cyan   #a4ffff
    SwiftTerm.Color(red: 0xffff, green: 0xffff, blue: 0xffff), // 15 Br White  #ffffff
]

// MARK: - Coordinator

extension SSHTerminalView {
    // Not isolated to @MainActor so TerminalViewDelegate conformance doesn't
    // cross actor boundaries. UI-touching calls use explicit MainActor dispatch.
    final class Coordinator: NSObject, TerminalViewDelegate {
        private let session: SSHSession
        private var cancellable: AnyCancellable?
        private weak var terminalView: TerminalView?

        init(session: SSHSession) {
            self.session = session
        }

        @MainActor
        func attach(to view: TerminalView) {
            terminalView = view

            // DispatchQueue.main, not RunLoop.main: the RunLoop scheduler only delivers
            // in .default mode, so it stalls all terminal rendering for the duration of
            // scroll gestures (.eventTracking mode). The GCD main queue drains in common
            // modes, so TUI redraws keep painting while the user scrolls.
            cancellable = session.outputSubject
                .receive(on: DispatchQueue.main)
                .sink { [weak view] data in
                    let bytes = [UInt8](data)
                    view?.feed(byteArray: bytes[bytes.startIndex...])
                }
        }

        // MARK: TerminalViewDelegate

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            // Synchronous enqueue: spawning a Task per chunk gives no ordering guarantee,
            // which can interleave bursts of mouse wheel reports with keystrokes.
            SSHService.shared.enqueueWrite(Data(data), to: session.id)
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            Task { await SSHService.shared.resize(cols: newCols, rows: newRows, for: session.id) }
        }

        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}

        func clipboardCopy(source: TerminalView, content: Data) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(content, forType: .string)
        }

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
