import Foundation

public final class CodexAppServerQuotaProvider: QuotaProvider, @unchecked Sendable {
    private let client: CodexAppServerClient
    private let timeout: TimeInterval

    public init(client: CodexAppServerClient = CodexAppServerClient(), timeout: TimeInterval = 15) {
        self.client = client
        self.timeout = timeout
    }

    deinit {
        client.stop()
    }

    public func fetch() async throws -> QuotaSnapshot {
        try await readSnapshot()
    }

    public func readSnapshot() async throws -> QuotaSnapshot {
        do {
            let data = try await client.request(
                method: "account/rateLimits/read",
                params: NSNull(),
                timeout: timeout
            )
            return try Self.snapshot(fromAppServerResultData: data)
        } catch let error as QuotaProviderError {
            throw error
        } catch {
            throw QuotaProviderError.codexCLIFailed(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    public func setRateLimitsUpdatedHandler(_ handler: (() -> Void)?) {
        client.setRateLimitsUpdatedHandler(handler)
    }

    public func stop() {
        client.stop()
    }

    public static func snapshot(fromAppServerResultData data: Data, capturedAt: Date = Date()) throws -> QuotaSnapshot {
        let response = try JSONDecoder().decode(AppServerRateLimitsResponse.self, from: data)
        let snapshot = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
        return try quotaSnapshot(from: snapshot, capturedAt: capturedAt)
    }

    private static func quotaSnapshot(from snapshot: AppServerRateLimitSnapshot, capturedAt: Date) throws -> QuotaSnapshot {
        guard let primary = snapshot.primary?.quotaWindow,
              let secondary = snapshot.secondary?.quotaWindow else {
            throw QuotaProviderError.noQuotaData
        }

        return QuotaSnapshot(
            primary: primary,
            secondary: secondary,
            capturedAt: capturedAt,
            planType: snapshot.planType,
            limitId: snapshot.limitId,
            limitName: snapshot.limitName,
            rateLimitReachedType: snapshot.rateLimitReachedType,
            credits: snapshot.credits?.quotaCredits,
            individualLimit: snapshot.individualLimit?.quotaIndividualLimit,
            source: "Codex app-server 实时读取",
            sourceKind: .codexAppServer
        )
    }
}

private struct AppServerRateLimitsResponse: Decodable {
    let rateLimits: AppServerRateLimitSnapshot
    let rateLimitsByLimitId: [String: AppServerRateLimitSnapshot]?
}

private struct AppServerRateLimitSnapshot: Decodable {
    let credits: AppServerCreditsSnapshot?
    let individualLimit: AppServerIndividualLimitSnapshot?
    let limitId: String?
    let limitName: String?
    let planType: String?
    let primary: AppServerRateLimitWindow?
    let rateLimitReachedType: String?
    let secondary: AppServerRateLimitWindow?
}

private struct AppServerCreditsSnapshot: Decodable {
    let balance: String?
    let hasCredits: Bool
    let unlimited: Bool

    var quotaCredits: QuotaCredits {
        QuotaCredits(balance: balance, hasCredits: hasCredits, unlimited: unlimited)
    }
}

private struct AppServerIndividualLimitSnapshot: Decodable {
    let limit: String
    let remainingPercent: Double
    let resetsAt: Double
    let used: String

    var quotaIndividualLimit: QuotaIndividualLimit {
        QuotaIndividualLimit(
            limit: limit,
            used: used,
            remainingPercent: max(0, min(100, remainingPercent)),
            resetsAt: Date(timeIntervalSince1970: resetsAt)
        )
    }
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
