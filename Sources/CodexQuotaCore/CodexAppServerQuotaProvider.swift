import Foundation

public final class CodexAppServerQuotaProvider: QuotaProvider {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    public func fetch() async throws -> QuotaSnapshot {
        let timeout = timeout

        return try await Task.detached(priority: .userInitiated) {
            try Self.fetchWithAppServer(timeout: timeout)
        }.value
    }

    public static func snapshot(fromAppServerResultData data: Data, capturedAt: Date = Date()) throws -> QuotaSnapshot {
        let response = try JSONDecoder().decode(AppServerRateLimitsResponse.self, from: data)
        let snapshot = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits

        guard let primary = snapshot.primary?.quotaWindow,
              let secondary = snapshot.secondary?.quotaWindow else {
            throw QuotaProviderError.noQuotaData
        }

        return QuotaSnapshot(
            primary: primary,
            secondary: secondary,
            capturedAt: capturedAt,
            planType: snapshot.planType,
            source: "Codex app-server 实时读取",
            sourceKind: .codexAppServer
        )
    }

    private static func fetchWithAppServer(timeout: TimeInterval) throws -> QuotaSnapshot {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        let lock = NSLock()
        let responseSemaphore = DispatchSemaphore(value: 0)

        var stdoutBuffer = ""
        var stderrBuffer = ""
        var response: Result<QuotaSnapshot, Error>?

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--listen", "stdio://"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = environmentWithCodexPath()
        process.terminationHandler = { _ in
            lock.lock()
            if response == nil {
                response = .failure(
                    QuotaProviderError.codexCLIFailed(
                        lastLine(from: stderrBuffer) ?? "app-server exited without quota response"
                    )
                )
                responseSemaphore.signal()
            }
            lock.unlock()
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else {
                return
            }

            lock.lock()
            stdoutBuffer.append(chunk)
            let lines = stdoutBuffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            stdoutBuffer = lines.last ?? ""
            let completeLines = lines.dropLast()
            lock.unlock()

            for line in completeLines {
                guard let result = parseResponseLine(line) else {
                    continue
                }

                lock.lock()
                if response == nil {
                    response = result
                    responseSemaphore.signal()
                }
                lock.unlock()
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else {
                return
            }

            lock.lock()
            stderrBuffer.append(chunk)
            lock.unlock()
        }

        do {
            try process.run()
        } catch {
            throw QuotaProviderError.codexCLIUnavailable
        }

        guard writeJSONLine(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"CodexQuotaBar","version":"1"},"capabilities":{"experimentalApi":true}}}"#,
            to: stdin
        ),
        writeJSONLine(#"{"method":"initialized"}"#, to: stdin),
        writeJSONLine(#"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":null}"#, to: stdin) else {
            cleanup(process: process, stdout: stdout, stderr: stderr)
            throw QuotaProviderError.codexCLIFailed("app-server stdin is not writable")
        }

        let timeoutMilliseconds = max(1, Int(timeout * 1000))
        let deadline = DispatchTime.now() + .milliseconds(timeoutMilliseconds)
        if responseSemaphore.wait(timeout: deadline) == .timedOut {
            cleanup(process: process, stdout: stdout, stderr: stderr)
            throw QuotaProviderError.codexCLITimedOut
        }

        cleanup(process: process, stdout: stdout, stderr: stderr)

        lock.lock()
        let result = response
        let errorOutput = stderrBuffer
        lock.unlock()

        if let result {
            return try result.get()
        }

        throw QuotaProviderError.codexCLIFailed(lastLine(from: errorOutput) ?? "app-server returned no quota response")
    }

    private static func writeJSONLine(_ line: String, to pipe: Pipe) -> Bool {
        guard let data = "\(line)\n".data(using: .utf8) else {
            return false
        }

        do {
            try pipe.fileHandleForWriting.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    private static func parseResponseLine(_ line: String) -> Result<QuotaSnapshot, Error>? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              (dictionary["id"] as? Int) == 2 else {
            return nil
        }

        if let error = dictionary["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "app-server rate limit read failed"
            return .failure(QuotaProviderError.codexCLIFailed(message))
        }

        guard dictionary["result"] != nil || dictionary["error"] != nil else {
            return nil
        }

        guard let result = dictionary["result"] else {
            return .failure(QuotaProviderError.noQuotaData)
        }

        do {
            let resultData = try JSONSerialization.data(withJSONObject: result)
            return .success(try snapshot(fromAppServerResultData: resultData))
        } catch {
            return .failure(error)
        }
    }

    private static func cleanup(process: Process, stdout: Pipe, stderr: Pipe) {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil

        if process.isRunning {
            process.terminate()
        }
    }

    private static func lastLine(from output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .last
            .map(String.init)
    }

    private static func environmentWithCodexPath() -> [String: String] {
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

private struct AppServerRateLimitsResponse: Decodable {
    let rateLimits: AppServerRateLimitSnapshot
    let rateLimitsByLimitId: [String: AppServerRateLimitSnapshot]?
}

private struct AppServerRateLimitSnapshot: Decodable {
    let primary: AppServerRateLimitWindow?
    let secondary: AppServerRateLimitWindow?
    let planType: String?
}

private struct AppServerRateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?

    var quotaWindow: QuotaWindow? {
        guard let windowDurationMins, let resetsAt else {
            return nil
        }

        return QuotaWindow(
            label: QuotaWindow.label(for: windowDurationMins),
            windowMinutes: windowDurationMins,
            usedPercent: usedPercent,
            remainingPercent: max(0, min(100, 100 - usedPercent)),
            resetsAt: Date(timeIntervalSince1970: resetsAt)
        )
    }
}
