import AppKit
import CodexQuotaCore
import Foundation

@MainActor
final class QuotaStore: ObservableObject {
    static let refreshInterval: TimeInterval = 300

    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLiveRefreshing = false
    @Published private(set) var lastRefreshAttempt: Date?
    @Published private(set) var statusTitle = "Cx --"

    private let provider: QuotaProvider
    private let liveProvider: QuotaProvider
    private var timer: Timer?

    init(provider: QuotaProvider, liveProvider: QuotaProvider? = nil) {
        self.provider = provider
        self.liveProvider = liveProvider ?? CompatibleLiveQuotaProvider(
            primary: CodexAppServerQuotaProvider(),
            fallback: provider
        )
    }

    deinit {
        timer?.invalidate()
    }

    func startPolling() {
        refresh()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        lastRefreshAttempt = Date()

        Task {
            do {
                let snapshot = try await provider.fetch()
                self.snapshot = snapshot
                errorMessage = nil
                statusTitle = "Cx \(Int(snapshot.tightestRemainingPercent.rounded()))%"
            } catch {
                self.snapshot = nil
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                statusTitle = "Cx --"
            }

            isRefreshing = false
        }
    }

    func refreshLive() {
        guard !isLiveRefreshing else {
            return
        }

        isLiveRefreshing = true
        lastRefreshAttempt = Date()

        Task {
            do {
                let snapshot = try await liveProvider.fetch()
                self.snapshot = snapshot
                errorMessage = nil
                statusTitle = "Cx \(Int(snapshot.tightestRemainingPercent.rounded()))%"
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }

            isLiveRefreshing = false
        }
    }
}

private struct CompatibleLiveQuotaProvider: QuotaProvider {
    let primary: QuotaProvider
    let fallback: QuotaProvider

    func fetch() async throws -> QuotaSnapshot {
        do {
            return try await primary.fetch()
        } catch {
            return try await fallback.fetch()
        }
    }
}
