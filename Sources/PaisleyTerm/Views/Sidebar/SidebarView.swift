import SwiftUI
import PaisleyCore

// MARK: - Sort order

enum SidebarSortOrder: String, CaseIterable {
    case name   = "Name"
    case status = "Status"
}

// MARK: - SidebarView

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    @State private var liveSortOrder: SidebarSortOrder  = .name
    @State private var savedSortOrder: SidebarSortOrder = .name

    // MARK: Sorted session buckets

    /// Sessions that are connected or currently connecting.
    private var liveSessions: [SSHSession] {
        let live = appState.sessions.filter {
            switch $0.connectionStatus {
            case .connected, .connecting: return true
            default: return false
            }
        }
        return sort(live, by: liveSortOrder, isLive: true)
    }

    /// Sessions that are disconnected or in an error state.
    private var savedSessions: [SSHSession] {
        let saved = appState.sessions.filter {
            switch $0.connectionStatus {
            case .disconnected, .error: return true
            default: return false
            }
        }
        return sort(saved, by: savedSortOrder, isLive: false)
    }

    private func sort(_ sessions: [SSHSession], by order: SidebarSortOrder, isLive: Bool) -> [SSHSession] {
        switch order {
        case .name:
            return sessions.sorted(by: { (a: SSHSession, b: SSHSession) in
                a.profile.nickname.localizedCaseInsensitiveCompare(b.profile.nickname) == .orderedAscending
            })
        case .status:
            if isLive {
                return sessions.sorted(by: { (a: SSHSession, b: SSHSession) in
                    a.agentStatus.sortPriority < b.agentStatus.sortPriority
                })
            } else {
                return sessions.sorted(by: { (a: SSHSession, b: SSHSession) in
                    a.profile.nickname.localizedCaseInsensitiveCompare(b.profile.nickname) == .orderedAscending
                })
            }
        }
    }

    // MARK: Body

    var body: some View {
        List(selection: $appState.selectedSessionID) {
            if appState.sessions.isEmpty {
                noConnectionsPlaceholder
            } else {
                if !liveSessions.isEmpty {
                    Section {
                        ForEach(liveSessions) { session in
                            let selected = appState.selectedSessionID == session.id
                            SessionRowView(session: session, isSelected: selected)
                                .tag(session.id)
                                .listRowBackground(
                                    selected ? Color.draculaCurrentLine : Color.clear
                                )
                                .contextMenu {
                                    AgentContextMenu(session: session)
                                        .environmentObject(appState)
                                }
                        }
                    } header: {
                        sectionHeader(title: "LIVE", sortOrder: $liveSortOrder)
                    }
                }

                if !savedSessions.isEmpty {
                    Section {
                        ForEach(savedSessions) { session in
                            let selected = appState.selectedSessionID == session.id
                            SessionRowView(session: session, isSelected: selected)
                                .tag(session.id)
                                .listRowBackground(
                                    selected ? Color.draculaCurrentLine : Color.clear
                                )
                                .onTapGesture(count: 2) {
                                    appState.connect(session: session)
                                }
                                .contextMenu {
                                    AgentContextMenu(session: session)
                                        .environmentObject(appState)
                                }
                        }
                    } header: {
                        sectionHeader(title: "SAVED", sortOrder: $savedSortOrder)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background { DraculaVibrancyBackground() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.showingAddConnection = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Connection (⌘N)")
            }
        }
        .navigationTitle("PaisleyTerm")
        // Bottom safe-area "Add Connection" button — discoverable even when toolbar is hidden.
        .safeAreaInset(edge: .bottom) {
            addConnectionFooter
        }
    }

    // MARK: - Section header

    @ViewBuilder
    private func sectionHeader(title: String, sortOrder: Binding<SidebarSortOrder>) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(Font.firaCode(10))
                .fontWeight(.semibold)
                .tracking(1.2)
                .foregroundColor(Color.draculaComment)

            Spacer()

            Menu {
                ForEach(SidebarSortOrder.allCases, id: \.self) { order in
                    Button {
                        sortOrder.wrappedValue = order
                    } label: {
                        HStack {
                            Text(order.rawValue)
                            if sortOrder.wrappedValue == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.draculaComment)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Empty state placeholder

    private var noConnectionsPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 22))
                .foregroundColor(Color.draculaPurple)
            Text("No connections yet")
                .font(Font.firaCode(12))
                .foregroundColor(Color.draculaComment)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Footer

    private var addConnectionFooter: some View {
        Button {
            appState.showingAddConnection = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                Text("Add Connection")
                    .font(Font.firaCode(12))
            }
            .foregroundColor(Color.draculaPurple)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color.draculaCurrentLine),
                alignment: .top
            )
        }
        .buttonStyle(.plain)
    }
}
