import Foundation
import CryptoKit
import NIOCore
import NIOSSH
import os

enum HostKeyError: Error, LocalizedError {
    case mismatch(host: String, trustedFingerprint: String, presentedFingerprint: String)

    var errorDescription: String? {
        switch self {
        case .mismatch(let host, let trusted, let presented):
            return """
            Host key for \(host) has changed. Trusted: \(trusted), presented: \(presented). \
            This may indicate a man-in-the-middle attack. If the server's key legitimately \
            changed, remove the entry for \(host) from known_hosts.json in \
            ~/Library/Application Support/PaisleyTerm and reconnect.
            """
        }
    }
}

/// Persists trusted SSH host keys as `host:port → OpenSSH public key string` in
/// Application Support, alongside profiles.json.
final class KnownHostsStore {
    static let shared = KnownHostsStore()

    private let fileURL: URL
    private let lock = OSAllocatedUnfairLock()

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("PaisleyTerm")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("known_hosts.json")
    }

    func trustedKey(for hostPort: String) -> String? {
        lock.withLock { loadEntries()[hostPort] }
    }

    func record(_ openSSHKey: String, for hostPort: String) {
        lock.withLock {
            var entries = loadEntries()
            entries[hostPort] = openSSHKey
            save(entries)
        }
    }

    func removeKey(for hostPort: String) {
        lock.withLock {
            var entries = loadEntries()
            entries.removeValue(forKey: hostPort)
            save(entries)
        }
    }

    private func loadEntries() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return entries
    }

    private func save(_ entries: [String: String]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Trust-on-first-use host key validator for a single connection. NIOSSH's delegate
/// callback doesn't receive the host, so each connection gets a validator with its
/// host:port baked in.
final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate {
    private let hostPort: String
    private let store: KnownHostsStore

    init(host: String, port: Int, store: KnownHostsStore = .shared) {
        self.hostPort = "\(host):\(port)"
        self.store = store
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presented = String(openSSHPublicKey: hostKey)

        guard let trusted = store.trustedKey(for: hostPort) else {
            // First contact: trust and record.
            store.record(presented, for: hostPort)
            validationCompletePromise.succeed(())
            return
        }

        if trusted == presented {
            validationCompletePromise.succeed(())
        } else {
            validationCompletePromise.fail(HostKeyError.mismatch(
                host: hostPort,
                trustedFingerprint: Self.fingerprint(ofOpenSSHKey: trusted),
                presentedFingerprint: Self.fingerprint(ofOpenSSHKey: presented)
            ))
        }
    }

    /// OpenSSH-style SHA256 fingerprint ("SHA256:base64-without-padding") of an
    /// "algorithm-id base64-blob" public key string.
    static func fingerprint(ofOpenSSHKey key: String) -> String {
        let parts = key.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else {
            return "unknown"
        }
        let digest = SHA256.hash(data: blob)
        let base64 = Data(digest).base64EncodedString()
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "SHA256:\(base64)"
    }
}
