import Foundation
import Darwin

/// A connection to our bundled helper. Protocol state stays on the main actor;
/// FileHandle callbacks only move bytes onto it, without blocking the UI on reads.
@MainActor
final class CodexClient {
    enum ClientError: LocalizedError {
        case missingHelper, disconnected, timeout, invalidResponse, rejected(Int)

        var errorDescription: String? {
            switch self {
            case .missingHelper: "The bundled Codex helper is missing. Prepare the helper and rebuild the app."
            case .disconnected: "The Codex helper stopped. Try connecting again."
            case .timeout: "Codex took too long to respond. Please try again."
            case .invalidResponse: "Codex returned an unexpected response."
            case .rejected(let code): "Codex could not complete the request (error \(code)). Please try again."
            }
        }
    }

    var onNotification: ((String, [String: Any]) -> Void)?
    var onDisconnect: (() -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private(set) var isConnected = false

    struct Configuration {
        let executable: URL
        let workingDirectory: URL
        let arguments: [String]
        let environment: [String: String]
    }

    func start(configuration: Configuration) async throws {
        guard process == nil else { return }
        guard FileManager.default.isExecutableFile(atPath: configuration.executable.path) else {
            throw ClientError.missingHelper
        }
        let child = Process()
        child.executableURL = configuration.executable
        child.arguments = configuration.arguments
        child.environment = configuration.environment
        child.currentDirectoryURL = configuration.workingDirectory
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = stderr
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        errors = stderr.fileHandleForReading
        buffer.removeAll()

        output?.readabilityHandler = { @Sendable [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            Task { @MainActor [weak self] in self?.receive(data) }
        }
        // Drain stderr so the helper cannot block. Never log authentication data.
        errors?.readabilityHandler = { @Sendable handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        child.terminationHandler = { @Sendable [weak self] child in
            Task { @MainActor [weak self] in
                guard let self, self.process === child else { return }
                self.disconnected()
            }
        }
        process = child
        do {
            try child.run()
            _ = try await request("initialize", params: [
                "clientInfo": ["name": "use_your_tokens", "title": "Use Your Tokens", "version": "0.1.0"]
            ])
            try send(["method": "initialized", "params": [:]])
            isConnected = true
        } catch {
            await stop()
            throw error
        }
    }

    func request(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard process?.isRunning == true else { throw ClientError.disconnected }
        nextID += 1
        let id = nextID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                timeouts[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    self?.finish(id, result: .failure(ClientError.timeout))
                }
                do {
                    try send(["id": id, "method": method, "params": params])
                } catch {
                    finish(id, result: .failure(error))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(id, result: .failure(CancellationError()))
            }
        }
    }

    private func send(_ message: [String: Any]) throws {
        guard let input else { throw ClientError.disconnected }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        guard buffer.count <= 1_048_576 else {
            process?.terminate()
            disconnected()
            return
        }
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if message["method"] != nil, let id = message["id"] {
                // Server request IDs are independent of our request IDs.
                // This client never executes tools or answers approval prompts.
                try? send(["id": id, "error": ["code": -32601, "message": "Unsupported method"]])
                continue
            }
            if let id = message["id"] as? Int {
                if let error = message["error"] as? [String: Any] {
                    finish(id, result: .failure(ClientError.rejected(error["code"] as? Int ?? -1)))
                } else if let result = message["result"] as? [String: Any] {
                    finish(id, result: .success(result))
                } else {
                    finish(id, result: .failure(ClientError.invalidResponse))
                }
            } else if let method = message["method"] as? String {
                onNotification?(method, message["params"] as? [String: Any] ?? [:])
            }
        }
    }

    private func finish(_ id: Int, result: Result<[String: Any], Error>) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func disconnected() {
        isConnected = false
        for id in Array(pending.keys) { finish(id, result: .failure(ClientError.disconnected)) }
        onDisconnect?()
    }

    func stop() async {
        let child = process
        process = nil
        output?.readabilityHandler = nil
        errors?.readabilityHandler = nil
        try? input?.close()
        input = nil
        if let child, child.isRunning {
            child.terminate()
            // Give the helper a bounded chance to exit, then ensure no orphan.
            for _ in 0..<20 where child.isRunning {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
        }
        try? output?.close()
        try? errors?.close()
        output = nil
        errors = nil
        buffer.removeAll()
        isConnected = false
        for id in Array(pending.keys) { finish(id, result: .failure(ClientError.disconnected)) }
    }
}
