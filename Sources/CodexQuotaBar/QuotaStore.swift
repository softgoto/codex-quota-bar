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
    private let appServerProvider: CodexAppServerQuotaProvider?
    private var timer: Timer?
    private var liveRefreshDebounceTask: Task<Void, Never>?

    init(provider: QuotaProvider, liveProvider: QuotaProvider? = nil) {
        let appServerProvider: CodexAppServerQuotaProvider?
        let resolvedLiveProvider: QuotaProvider

        if let liveProvider {
            appServerProvider = liveProvider as? CodexAppServerQuotaProvider
            resolvedLiveProvider = liveProvider
        } else {
            let appServer = CodexAppServerQuotaProvider()
            appServerProvider = appServer
            resolvedLiveProvider = FallbackQuotaProvider(
                primary: appServer,
                fallback: provider
            )
        }

        self.provider = provider
        self.liveProvider = resolvedLiveProvider
        self.appServerProvider = appServerProvider

        appServerProvider?.setRateLimitsUpdatedHandler { [weak self] in
            Task { @MainActor in
                self?.scheduleLiveRefreshFromNotification()
            }
        }
    }

    deinit {
        timer?.invalidate()
        liveRefreshDebounceTask?.cancel()
        appServerProvider?.stop()
    }

    func startPolling() {
        refreshLive()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLive()
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

    private func scheduleLiveRefreshFromNotification() {
        liveRefreshDebounceTask?.cancel()
        liveRefreshDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self?.refreshLive()
            }
        }
    }
}
