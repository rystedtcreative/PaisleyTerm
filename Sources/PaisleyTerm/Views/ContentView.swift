import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 250)
        } detail: {
            TerminalContainerView()
        }
        .sheet(isPresented: $appState.showingAddConnection) {
            AddConnectionSheet()
                .environmentObject(appState)
        }
        .background(WindowTransparencyConfigurator())
    }
}

// MARK: - Window transparency

private class _TransparentWindowAnchor: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let w = window else { return }
        w.isOpaque = false
        w.backgroundColor = .clear
    }
}

private struct WindowTransparencyConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> _TransparentWindowAnchor { _TransparentWindowAnchor() }
    func updateNSView(_ nsView: _TransparentWindowAnchor, context: Context) {}
}
