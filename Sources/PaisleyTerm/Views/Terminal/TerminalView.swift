import SwiftUI
import SwiftTerm
import AppKit
import Combine

// MARK: - Session-aware local process terminal

/// Subclass of LocalProcessTerminalView that:
/// 1. Keeps the CALayer transparent so the visual-effect + tint container shows through.
/// 2. Forwards every chunk of process output to session.outputSubject so AgentMonitor
///    can parse it for agent status — identical to how SSHService feeds the SSH data path.
final class PaisleyLocalTerminalView: LocalProcessTerminalView {
    weak var session: SSHSession?

    // MARK: Transparency (mirrors TranslucentTerminalView in SSHTerminalView.swift)

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

    // Mirror of TranslucentTerminalView: hide the NSScroller the instant
    // SwiftTerm adds it during init, before any window attachment.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if subview is NSScroller { subview.isHidden = true }
    }

    // MARK: Output fan-out

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        let bytes = Data(slice)
        // LocalProcess delivers on the main queue, so send synchronously — spawning a
        // Task per chunk gives no ordering guarantee and can reorder chunks for
        // AgentMonitor (whose alt-screen detection relies on chunk order).
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                session?.outputSubject.send(bytes)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.session?.outputSubject.send(bytes)
            }
        }
    }
}

extension PaisleyLocalTerminalView {
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

// MARK: - Local terminal view

struct LocalTerminalView: NSViewRepresentable {
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

        let termView = PaisleyLocalTerminalView(frame: .zero)
        termView.translatesAutoresizingMaskIntoConstraints = false
        termView.session               = session
        termView.font                  = NSFont.firaCode(size: fontSize)
        termView.nativeForegroundColor = NSColor(hex: "f8f8f2")
        termView.nativeBackgroundColor = .clear
        termView.caretColor            = NSColor(hex: "bd93f9")
        termView.installColors(draculaANSI)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        termView.startProcess(executable: shell, args: [], environment: nil, execName: nil)

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

        context.coordinator.attach(to: termView)
        TerminalScrollForwarder.register(termView)
        return fx
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let termView = nsView.subviews.first(where: { $0 is PaisleyLocalTerminalView })
                                             as? PaisleyLocalTerminalView else { return }
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

// MARK: - Coordinator

extension LocalTerminalView {
    @MainActor
    final class Coordinator {
        private let session: SSHSession
        private var cancellable: AnyCancellable?
        private weak var termView: PaisleyLocalTerminalView?

        init(session: SSHSession) {
            self.session = session
        }

        func attach(to view: PaisleyLocalTerminalView) {
            termView = view
            // Forward inputSubject → PTY so AppState can send commands (agent launch/stop).
            // DispatchQueue.main, not RunLoop.main: the RunLoop scheduler only delivers in
            // .default mode and would stall these commands during scroll gestures.
            cancellable = session.inputSubject
                .receive(on: DispatchQueue.main)
                .sink { [weak view] data in
                    if let text = String(data: data, encoding: .utf8) {
                        view?.send(txt: text)
                    }
                }
        }
    }
}
