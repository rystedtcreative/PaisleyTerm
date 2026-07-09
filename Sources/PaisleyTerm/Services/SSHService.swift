import Foundation
import Combine
import PaisleyCore
import Citadel
import NIOCore
import NIOSSH
import os

enum SSHServiceError: Error, LocalizedError {
    case keyAuthNotSupported
    case noActiveWriter
    case requiresMacOS15

    var errorDescription: String? {
        switch self {
        case .keyAuthNotSupported: return "SSH key auth is not yet implemented"
        case .noActiveWriter:      return "No active PTY for this session"
        case .requiresMacOS15:     return "SSH PTY requires macOS 15 or later"
        }
    }
}

/// Manages SSH connections and PTY sessions for all open sessions.
/// Each connect() call opens a PTY via Citadel's withPTY and fans SSH output
/// to SSHSession.outputSubject for both the terminal view and the agent monitor.
actor SSHService {
    static let shared = SSHService()

    // Active PTY write handles, keyed by session UUID.
    private var writers: [UUID: TTYStdinWriter] = [:]
    // Background tasks running the read loop for each session.
    private var tasks: [UUID: Task<Void, Never>] = [:]
    // SSHClient instances (kept alive so the connection stays open).
    private var clients: [UUID: SSHClient] = [:]
    // Single sequential consumer per session draining the input queue — guarantees
    // PTY writes reach the channel in enqueue order.
    private var writeTasks: [UUID: Task<Void, Never>] = [:]
    // Input queue heads. Nonisolated + lock-protected so producers (key strokes, mouse
    // wheel reports) can enqueue synchronously from the main thread: spawning a Task per
    // chunk instead would give no ordering guarantee across chunks.
    private let inputContinuations = OSAllocatedUnfairLock(initialState: [UUID: AsyncStream<Data>.Continuation]())

    private let credentialStore = CredentialStore()

    // MARK: - Connect

    func connect(session: SSHSession) async throws {
        guard #available(macOS 15.0, *) else {
            throw SSHServiceError.requiresMacOS15
        }

        await MainActor.run { session.connectionStatus = .connecting }

        let profile = session.profile
        let auth: SSHAuthenticationMethod

        switch profile.authMethod {
        case .password(let keychainID):
            let password = try credentialStore.loadPassword(id: keychainID)
            auth = .passwordBased(username: profile.username, password: password)
        case .sshKey:
            throw SSHServiceError.keyAuthNotSupported
        case .local:
            return
        }

        let client = try await SSHClient.connect(
            host: profile.host,
            port: profile.port,
            authenticationMethod: auth,
            hostKeyValidator: .custom(TOFUHostKeyValidator(host: profile.host, port: profile.port)),
            reconnect: .never
        )
        clients[session.id] = client

        // Bridge the closure-based withPTY API to async/await.
        // The continuation resumes with the writer once the PTY channel opens.
        // The reading loop then runs in a background task (task keeps the closure alive).
        let writer = try await openPTY(client: client, session: session)
        writers[session.id] = writer
        startWriteQueue(for: session.id)
        await MainActor.run { session.connectionStatus = .connected }
    }

    // MARK: - Input queue

    /// Enqueue bytes for the session's PTY. Synchronous and FIFO: chunks are written to
    /// the channel in the exact order they were enqueued.
    nonisolated func enqueueWrite(_ data: Data, to sessionID: UUID) {
        inputContinuations.withLock { _ = $0[sessionID]?.yield(data) }
    }

    private func startWriteQueue(for sessionID: UUID) {
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        inputContinuations.withLock { $0[sessionID] = continuation }
        writeTasks[sessionID]?.cancel()
        writeTasks[sessionID] = Task {
            for await chunk in stream {
                try? await self.write(chunk, to: sessionID)
            }
        }
    }

    @available(macOS 15.0, *)
    private func openPTY(client: SSHClient, session: SSHSession) async throws -> TTYStdinWriter {
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: 220,
            terminalRowHeight: 50,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )

        var closureWasCalled = false
        var capturedTask: Task<Void, Never>?

        let writer: TTYStdinWriter = try await withCheckedThrowingContinuation { cont in
            capturedTask = Task {
                do {
                    try await client.withPTY(ptyRequest) { inbound, outbound in
                        closureWasCalled = true
                        cont.resume(returning: outbound)

                        // Read SSH output until the channel closes or the task is cancelled.
                        for try await output in inbound {
                            if Task.isCancelled { return }
                            let bytes: [UInt8]
                            switch output {
                            case .stdout(var buf): bytes = buf.readBytes(length: buf.readableBytes) ?? []
                            case .stderr(var buf): bytes = buf.readBytes(length: buf.readableBytes) ?? []
                            }
                            guard !bytes.isEmpty else { continue }
                            await MainActor.run { session.outputSubject.send(Data(bytes)) }
                        }
                    }
                } catch is CancellationError {
                    // Normal path: disconnect() cancelled the task.
                } catch {
                    // Only resume continuation if the PTY open itself failed.
                    if !closureWasCalled {
                        cont.resume(throwing: error)
                    }
                    await MainActor.run { session.connectionStatus = .error(error.localizedDescription) }
                }
                await MainActor.run {
                    if case .connected = session.connectionStatus {
                        session.connectionStatus = .disconnected
                    }
                }
            }
        }

        if let t = capturedTask { tasks[session.id] = t }
        return writer
    }

    // MARK: - Write

    func write(_ data: Data, to sessionID: UUID) async throws {
        guard let writer = writers[sessionID] else { throw SSHServiceError.noActiveWriter }
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        try await writer.write(buffer)
    }

    // MARK: - Resize

    func resize(cols: Int, rows: Int, for sessionID: UUID) async {
        guard cols > 0, rows > 0 else { return }
        try? await writers[sessionID]?.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
    }

    // MARK: - Disconnect

    func disconnect(sessionID: UUID) async {
        inputContinuations.withLock { $0.removeValue(forKey: sessionID) }?.finish()
        writeTasks[sessionID]?.cancel()
        writeTasks[sessionID] = nil
        tasks[sessionID]?.cancel()
        tasks[sessionID] = nil
        writers[sessionID] = nil
        clients[sessionID] = nil
    }
}
