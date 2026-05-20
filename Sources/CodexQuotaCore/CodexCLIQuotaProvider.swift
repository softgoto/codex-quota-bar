import Foundation

public final class CodexCLIQuotaProvider: QuotaProvider {
    private let prompt: String
    private let timeout: TimeInterval

    public init(prompt: String = "只返回 OK", timeout: TimeInterval = 90) {
        self.prompt = prompt
        self.timeout = timeout
    }

    public func fetch() async throws -> QuotaSnapshot {
        let prompt = prompt
        let timeout = timeout

        return try await Task.detached(priority: .userInitiated) {
            try Self.fetchWithCodexCLI(prompt: prompt, timeout: timeout)
        }.value
    }

    private static func fetchWithCodexCLI(prompt: String, timeout: TimeInterval) throws -> QuotaSnapshot {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "codex",
            "exec",
            "--json",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            prompt
        ]
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = environmentWithCodexPath()

        do {
            try process.run()
        } catch {
            throw QuotaProviderError.codexCLIUnavailable
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                throw QuotaProviderError.codexCLITimedOut
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = errorOutput
                .split(whereSeparator: \.isNewline)
                .last
                .map(String.init) ?? "exit \(process.terminationStatus)"
            throw QuotaProviderError.codexCLIFailed(message)
        }

        guard let snapshot = latestSnapshot(from: output) else {
            throw QuotaProviderError.noQuotaData
        }

        return snapshot
    }

    private static func latestSnapshot(from output: String) -> QuotaSnapshot? {
        var latest: ParsedCLIQuotaEvent?

        for line in output.split(whereSeparator: \.isNewline) {
            guard let event = parseLine(String(line)) else {
                continue
            }

            if latest == nil || event.capturedAt > latest!.capturedAt {
                latest = event
            }
        }

        guard let latest else {
            return nil
        }

        return QuotaSnapshot(
            primary: latest.primary,
            secondary: latest.secondary,
            capturedAt: latest.capturedAt,
            planType: latest.planType,
            source: "Codex CLI 实时刷新",
            sourceKind: .codexCLI
        )
    }

    private static func parseLine(_ line: String) -> ParsedCLIQuotaEvent? {
        guard let data = line.data(using: .utf8),
              let event = try? JSONDecoder.codexCLIQuota.decode(CLIEvent.self, from: data),
              event.type == "event_msg",
              event.payload.type == "token_count",
              let primaryLimit = event.payload.rateLimits.primary,
              let secondaryLimit = event.payload.rateLimits.secondary else {
            return nil
        }

        return ParsedCLIQuotaEvent(
            primary: primaryLimit.quotaWindow,
            secondary: secondaryLimit.quotaWindow,
            capturedAt: event.timestamp,
            planType: event.payload.rateLimits.planType
        )
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

private struct ParsedCLIQuotaEvent {
    let primary: QuotaWindow
    let secondary: QuotaWindow
    let capturedAt: Date
    let planType: String?
}

private struct CLIEvent: Decodable {
    let timestamp: Date
    let type: String
    let payload: Payload

    struct Payload: Decodable {
        let type: String
        let rateLimits: RateLimits

        enum CodingKeys: String, CodingKey {
            case type
            case rateLimits = "rate_limits"
        }
    }
}

private struct RateLimits: Decodable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case planType = "plan_type"
    }
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date

    var quotaWindow: QuotaWindow {
        QuotaWindow(
            label: QuotaWindow.label(for: windowMinutes),
            windowMinutes: windowMinutes,
            usedPercent: usedPercent,
            remainingPercent: max(0, min(100, 100 - usedPercent)),
            resetsAt: resetsAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}

private extension JSONDecoder {
    static var codexCLIQuota: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }

            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if let date = formatter.date(from: value) {
                return date
            }

            formatter.formatOptions = [.withInternetDateTime]

            if let date = formatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported Codex timestamp: \(value)"
            )
        }
        return decoder
    }
}
