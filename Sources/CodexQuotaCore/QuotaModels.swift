import Foundation

public struct QuotaWindow: Equatable, Sendable {
    public let label: String
    public let windowMinutes: Int
    public let usedPercent: Double
    public let remainingPercent: Double
    public let resetsAt: Date

    public init(
        label: String,
        windowMinutes: Int,
        usedPercent: Double,
        remainingPercent: Double,
        resetsAt: Date
    ) {
        self.label = label
        self.windowMinutes = windowMinutes
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }

    public static func label(for windowMinutes: Int) -> String {
        if windowMinutes >= 1440, windowMinutes % 1440 == 0 {
            return "\(windowMinutes / 1440) 天"
        }

        if windowMinutes >= 60, windowMinutes % 60 == 0 {
            return "\(windowMinutes / 60) 小时"
        }

        return "\(windowMinutes) 分钟"
    }
}

public struct QuotaSnapshot: Equatable, Sendable {
    public enum SourceKind: String, Equatable, Sendable {
        case localSnapshot
        case codexCLI

        public var displayName: String {
            switch self {
            case .localSnapshot:
                return "快照"
            case .codexCLI:
                return "实时"
            }
        }
    }

    public let primary: QuotaWindow
    public let secondary: QuotaWindow
    public let capturedAt: Date
    public let planType: String?
    public let source: String
    public let sourceKind: SourceKind

    public init(
        primary: QuotaWindow,
        secondary: QuotaWindow,
        capturedAt: Date,
        planType: String?,
        source: String,
        sourceKind: SourceKind = .localSnapshot
    ) {
        self.primary = primary
        self.secondary = secondary
        self.capturedAt = capturedAt
        self.planType = planType
        self.source = source
        self.sourceKind = sourceKind
    }

    public var tightestRemainingPercent: Double {
        min(primary.remainingPercent, secondary.remainingPercent)
    }
}

public protocol QuotaProvider {
    func fetch() async throws -> QuotaSnapshot
}

public enum QuotaProviderError: Error, Equatable, LocalizedError {
    case noQuotaData
    case codexCLIUnavailable
    case codexCLIFailed(String)
    case codexCLITimedOut

    public var errorDescription: String? {
        switch self {
        case .noQuotaData:
            return "暂无额度数据"
        case .codexCLIUnavailable:
            return "找不到 Codex CLI"
        case let .codexCLIFailed(message):
            return "Codex CLI 实时刷新失败：\(message)"
        case .codexCLITimedOut:
            return "Codex CLI 实时刷新超时"
        }
    }
}
