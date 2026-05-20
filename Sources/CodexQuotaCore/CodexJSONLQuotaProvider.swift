import Foundation

public final class CodexJSONLQuotaProvider: QuotaProvider {
    private let codexHome: URL
    private let maxFilesToScan: Int
    private let fileManager: FileManager

    public init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
        maxFilesToScan: Int = 32,
        fileManager: FileManager = .default
    ) {
        self.codexHome = codexHome
        self.maxFilesToScan = maxFilesToScan
        self.fileManager = fileManager
    }

    public func fetch() async throws -> QuotaSnapshot {
        let codexHome = codexHome
        let maxFilesToScan = maxFilesToScan
        let fileManager = fileManager

        return try await Task.detached(priority: .utility) {
            let reader = JSONLQuotaReader(
                codexHome: codexHome,
                maxFilesToScan: maxFilesToScan,
                fileManager: fileManager
            )
            return try reader.fetch()
        }.value
    }
}

struct JSONLQuotaReader {
    let codexHome: URL
    let maxFilesToScan: Int
    let fileManager: FileManager

    func fetch() throws -> QuotaSnapshot {
        let files = recentRolloutFiles()

        guard !files.isEmpty else {
            throw QuotaProviderError.noQuotaData
        }

        var latest: ParsedQuotaEvent?

        for file in files {
            guard let contents = try? String(contentsOf: file.url, encoding: .utf8) else {
                continue
            }

            for line in contents.split(whereSeparator: \.isNewline) {
                guard let event = parseLine(String(line), source: file.url.path) else {
                    continue
                }

                if latest == nil || event.capturedAt > latest!.capturedAt {
                    latest = event
                }
            }
        }

        guard let latest else {
            throw QuotaProviderError.noQuotaData
        }

        return QuotaSnapshot(
            primary: latest.primary,
            secondary: latest.secondary,
            capturedAt: latest.capturedAt,
            planType: latest.planType,
            source: latest.source
        )
    }

    private func recentRolloutFiles() -> [RolloutFile] {
        let sessionsDirectory = codexHome.appendingPathComponent("sessions", isDirectory: true)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]

        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [RolloutFile] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  url.lastPathComponent.hasPrefix("rollout-") else {
                continue
            }

            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                continue
            }

            files.append(
                RolloutFile(
                    url: url,
                    modifiedAt: values.contentModificationDate ?? .distantPast
                )
            )
        }

        return files
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(maxFilesToScan)
            .map { $0 }
    }

    private func parseLine(_ line: String, source: String) -> ParsedQuotaEvent? {
        guard let data = line.data(using: .utf8),
              let event = try? JSONDecoder.codexQuota.decode(RolloutEvent.self, from: data),
              event.type == "event_msg",
              event.payload.type == "token_count",
              let primaryLimit = event.payload.rateLimits.primary,
              let secondaryLimit = event.payload.rateLimits.secondary else {
            return nil
        }

        return ParsedQuotaEvent(
            primary: primaryLimit.quotaWindow,
            secondary: secondaryLimit.quotaWindow,
            capturedAt: event.timestamp,
            planType: event.payload.rateLimits.planType,
            source: source
        )
    }
}

private struct RolloutFile {
    let url: URL
    let modifiedAt: Date
}

private struct ParsedQuotaEvent {
    let primary: QuotaWindow
    let secondary: QuotaWindow
    let capturedAt: Date
    let planType: String?
    let source: String
}

private struct RolloutEvent: Decodable {
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
    static var codexQuota: JSONDecoder {
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
