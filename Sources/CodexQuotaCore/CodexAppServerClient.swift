import Foundation

public final class CodexAppServerClient: @unchecked Sendable {
    private final class PendingRequest {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>?
    }

    private let executableURL: URL
    private let arguments: [String]
    private let environment: [String: String]?
    private let defaultTimeout: TimeInterval
    private let stateLock = NSLock()
    private let lifecycleLock = NSLock()
    private let writeLock = NSLock()

    private var process: Process?
    private var stdin: Pipe?
    private var stdout: Pipe?
    private var stderr: Pipe?
    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    private var nextRequestId = 1
    private var initialized = false
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var rateLimitsUpdatedHandler: (() -> Void)?

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        arguments: [String] = ["codex", "app-server", "--stdio"],
        environment: [String: String]? = CodexAppServerClient.defaultEnvironment(),
        defaultTimeout: TimeInterval = 15
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.defaultTimeout = defaultTimeout
    }

    deinit {
        stop()
    }

    public func setRateLimitsUpdatedHandler(_ handler: (() -> Void)?) {
        stateLock.lock()
        rateLimitsUpdatedHandler = handler
        stateLock.unlock()
    }

    public func request(method: String, params: Any? = NSNull(), timeout: TimeInterval? = nil) async throws -> Data {
        let effectiveTimeout = timeout ?? defaultTimeout

        return try await Task.detached(priority: .userInitiated) {
            try self.requestSync(method: method, params: params ?? NSNull(), timeout: effectiveTimeout)
        }.value
    }

    public func stop() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        stopCurrentProcess(failingPendingWith: CodexAppServerClientError.stopped)
    }

    private func requestSync(method: String, params: Any, timeout: TimeInterval) throws -> Data {
        try ensureStarted()
        return try performRequestSync(method: method, params: params, timeout: timeout)
    }

    private func ensureStarted() throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        if isReady {
            return
        }

        stopCurrentProcess(failingPendingWith: CodexAppServerClientError.restarting)
        try startProcess()
        try initializeConnection()
    }

    private var isReady: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return process?.isRunning == true && initialized && stdin != nil
    }

    private func startProcess() throws {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = environment

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleStdoutData(handle.availableData)
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleStderrData(handle.availableData)
        }

        process.terminationHandler = { [weak self] _ in
            self?.handleProcessTermination()
        }

        stateLock.lock()
        self.process = process
        self.stdin = stdin
        self.stdout = stdout
        self.stderr = stderr
        stdoutBuffer = ""
        stderrBuffer = ""
        initialized = false
        stateLock.unlock()

        do {
            try process.run()
        } catch {
            stopCurrentProcess(failingPendingWith: CodexAppServerClientError.unavailable)
            throw CodexAppServerClientError.unavailable
        }
    }

    private func initializeConnection() throws {
        _ = try performRequestSync(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "CodexQuotaBar",
                    "title": "CodexQuotaBar",
                    "version": "0.4.0"
                ],
                "capabilities": [
                    "experimentalApi": true
                ]
            ],
            timeout: defaultTimeout
        )

        try sendNotification(method: "initialized", params: [:])

        stateLock.lock()
        initialized = true
        stateLock.unlock()
    }

    private func performRequestSync(method: String, params: Any, timeout: TimeInterval) throws -> Data {
        let requestId = nextId()
        let pending = PendingRequest()

        stateLock.lock()
        pendingRequests[requestId] = pending
        stateLock.unlock()

        do {
            try writeJSONObject([
                "jsonrpc": "2.0",
                "id": requestId,
                "method": method,
                "params": params
            ])
        } catch {
            removePendingRequest(id: requestId)
            throw error
        }

        let timeoutMilliseconds = max(1, Int(timeout * 1000))
        if pending.semaphore.wait(timeout: .now() + .milliseconds(timeoutMilliseconds)) == .timedOut {
            removePendingRequest(id: requestId)
            throw CodexAppServerClientError.timedOut
        }

        stateLock.lock()
        let result = pending.result
        pendingRequests.removeValue(forKey: requestId)
        stateLock.unlock()

        if let result {
            return try result.get()
        }

        throw CodexAppServerClientError.noResponse
    }

    private func sendNotification(method: String, params: Any) throws {
        try writeJSONObject([
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ])
    }

    private func nextId() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        let id = nextRequestId
        nextRequestId += 1
        return id
    }

    private func removePendingRequest(id: Int) {
        stateLock.lock()
        pendingRequests.removeValue(forKey: id)
        stateLock.unlock()
    }

    private func writeJSONObject(_ object: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            throw CodexAppServerClientError.invalidRequest
        }

        var line = data
        line.append(0x0A)
        debug("send \(String(data: data, encoding: .utf8) ?? "")")

        stateLock.lock()
        let writer = stdin?.fileHandleForWriting
        stateLock.unlock()

        guard let writer else {
            throw CodexAppServerClientError.notRunning
        }

        writeLock.lock()
        defer { writeLock.unlock() }

        do {
            try writer.write(contentsOf: line)
        } catch {
            throw CodexAppServerClientError.writeFailed
        }
    }

    private func handleStdoutData(_ data: Data) {
        guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else {
            return
        }

        stateLock.lock()
        stdoutBuffer.append(chunk)
        let lines = stdoutBuffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        stdoutBuffer = lines.last ?? ""
        let completeLines = Array(lines.dropLast())
        stateLock.unlock()

        for line in completeLines {
            debug("recv \(line)")
            handleMessageLine(line)
        }
    }

    private func handleStderrData(_ data: Data) {
        guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else {
            return
        }

        stateLock.lock()
        stderrBuffer.append(chunk)
        stateLock.unlock()
    }

    private func handleMessageLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let message = object as? [String: Any] else {
            debug("ignored non-json line \(line)")
            return
        }

        if let id = responseId(from: message["id"]) {
            handleResponse(id: id, message: message)
            return
        }

        if message["method"] as? String == "account/rateLimits/updated" {
            stateLock.lock()
            let handler = rateLimitsUpdatedHandler
            stateLock.unlock()
            handler?()
        }
    }

    private func debug(_ message: String) {
        guard ProcessInfo.processInfo.environment["CODEX_QUOTA_APP_SERVER_DEBUG"] == "1" else {
            return
        }

        FileHandle.standardError.write(Data("CodexAppServerClient: \(message)\n".utf8))
    }

    private func responseId(from value: Any?) -> Int? {
        if let id = value as? Int {
            return id
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        if let string = value as? String {
            return Int(string)
        }

        return nil
    }

    private func handleResponse(id: Int, message: [String: Any]) {
        let result: Result<Data, Error>

        if let error = message["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "app-server request failed"
            result = .failure(CodexAppServerClientError.requestFailed(message))
        } else if let payload = message["result"] {
            do {
                result = .success(try JSONSerialization.data(withJSONObject: payload))
            } catch {
                result = .failure(error)
            }
        } else {
            result = .failure(CodexAppServerClientError.noResponse)
        }

        stateLock.lock()
        let pending = pendingRequests[id]
        pending?.result = result
        stateLock.unlock()

        pending?.semaphore.signal()
    }

    private func handleProcessTermination() {
        stateLock.lock()
        initialized = false
        process = nil
        stdin = nil
        stdout = nil
        stderr = nil
        let message = lastLine(from: stderrBuffer) ?? "app-server exited"
        let pending = Array(pendingRequests.values)
        pendingRequests.removeAll()
        stateLock.unlock()

        for request in pending {
            request.result = .failure(CodexAppServerClientError.requestFailed(message))
            request.semaphore.signal()
        }
    }

    private func stopCurrentProcess(failingPendingWith error: Error) {
        stateLock.lock()
        let process = process
        let stdout = stdout
        let stderr = stderr
        let stdin = stdin
        let pending = Array(pendingRequests.values)

        self.process = nil
        self.stdin = nil
        self.stdout = nil
        self.stderr = nil
        stdoutBuffer = ""
        stderrBuffer = ""
        initialized = false
        pendingRequests.removeAll()
        stateLock.unlock()

        stdout?.fileHandleForReading.readabilityHandler = nil
        stderr?.fileHandleForReading.readabilityHandler = nil
        try? stdin?.fileHandleForWriting.close()

        if process?.isRunning == true {
            process?.terminate()
        }

        for request in pending {
            request.result = .failure(error)
            request.semaphore.signal()
        }
    }

    private func lastLine(from output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .last
            .map(String.init)
    }

    public static func defaultEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let launchServicesSafePath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

        if let path = environment["PATH"], !path.isEmpty {
            environment["PATH"] = "\(launchServicesSafePath):\(path)"
        } else {
            environment["PATH"] = launchServicesSafePath
        }

        return environment
    }
}

private enum CodexAppServerClientError: Error, LocalizedError {
    case invalidRequest
    case noResponse
    case notRunning
    case requestFailed(String)
    case restarting
    case stopped
    case timedOut
    case unavailable
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "app-server request is invalid"
        case .noResponse:
            return "app-server returned no response"
        case .notRunning:
            return "app-server is not running"
        case let .requestFailed(message):
            return message
        case .restarting:
            return "app-server is restarting"
        case .stopped:
            return "app-server stopped"
        case .timedOut:
            return "app-server request timed out"
        case .unavailable:
            return "Codex app-server is unavailable"
        case .writeFailed:
            return "failed to write to app-server"
        }
    }
}
