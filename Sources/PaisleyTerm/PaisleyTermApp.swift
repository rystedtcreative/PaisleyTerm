import SwiftUI

@main
struct PaisleyTermApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 600)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Connection…") {
                    appState.showingAddConnection = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Terminal") {
                Button("Increase Font Size") { appState.increaseFontSize() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Decrease Font Size") { appState.decreaseFontSize() }
                    .keyboardShortcut("-", modifiers: .command)
                Divider()
                Button("Reset Font Size") { appState.resetFontSize() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
