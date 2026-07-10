import SwiftUI
import AppKit
import PaisleyCore

struct AddConnectionSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var sessionType = SessionType.ssh
    @State private var nickname = ""
    @State private var host = ""
    @State private var portText = "22"
    @State private var username = ""
    @State private var authChoice = AuthChoice.password
    @State private var password = ""
    @State private var sshKeyPath = ""
    @State private var errorMessage: String?

    enum SessionType: String, CaseIterable {
        case ssh   = "SSH"
        case local = "Local"
    }

    enum AuthChoice: String, CaseIterable {
        case password = "Password"
        case sshKey   = "SSH Key"
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Type", selection: $sessionType) {
                        ForEach(SessionType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("Nickname", text: $nickname)
                }

                if sessionType == .ssh {
                    Section("Connection") {
                        TextField("Host or IP", text: $host)
                            .textContentType(.URL)
                        TextField("Port", text: $portText)
                        TextField("Username", text: $username)
                    }

                    Section("Authentication") {
                        Picker("Method", selection: $authChoice) {
                            ForEach(AuthChoice.allCases, id: \.self) { c in
                                Text(c.rawValue).tag(c)
                            }
                        }
                        .pickerStyle(.segmented)

                        if authChoice == .password {
                            SecureField("Password", text: $password)
                        } else {
                            HStack {
                                TextField("~/.ssh/id_ed25519", text: $sshKeyPath)
                                Button("Browse…") { pickKey() }
                            }
                        }
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button(sessionType == .local ? "Add Local Terminal" : "Add Connection") { save() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 420)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var isValid: Bool {
        guard !nickname.isEmpty else { return false }
        if sessionType == .ssh {
            return !host.isEmpty && !username.isEmpty
        }
        return true
    }

    private func pickKey() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your SSH private key"
        if panel.runModal() == .OK, let url = panel.url {
            sshKeyPath = url.path
        }
    }

    private func save() {
        if sessionType == .local {
            appState.addLocalSession(nickname: nickname)
            dismiss()
            return
        }

        let port = Int(portText) ?? 22
        let authMethod: ConnectionProfile.AuthMethod
        let credentialStore = CredentialStore()

        if authChoice == .password {
            let keychainID = UUID().uuidString
            do {
                try credentialStore.savePassword(password, id: keychainID)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            authMethod = .password(keychainID: keychainID)
        } else {
            guard !sshKeyPath.isEmpty else {
                errorMessage = "Please select an SSH key file."
                return
            }
            authMethod = .sshKey(path: sshKeyPath)
        }

        let profile = ConnectionProfile(
            nickname: nickname,
            host: host,
            port: port,
            username: username,
            authMethod: authMethod
        )

        appState.addProfile(profile)
        dismiss()
    }
}
