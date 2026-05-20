import CodexQuotaCore
import Foundation

@main
enum CodexQuotaCoreSmokeTests {
    static func main() async throws {
        try await testParsesLatestTokenCountRateLimits()
        try await testIgnoresTokenCountWithoutRateLimits()
        try await testChoosesNewestEventAcrossFiles()
        try await testClampsRemainingPercent()
        print("CodexQuotaCoreSmokeTests passed")
    }

    private static func testParsesLatestTokenCountRateLimits() async throws {
        try await withTemporaryCodexHome { codexHome in
            try writeRollout(
                codexHome: codexHome,
                relativePath: "sessions/2026/05/19/rollout-new.jsonl",
                lines: [
                    brokenJSONLine,
                    tokenCountLine(timestamp: "2026-05-19T13:31:22.239Z", primaryUsed: 39, secondaryUsed: 6)
                ]
            )

            let provider = CodexJSONLQuotaProvider(codexHome: codexHome)
            let snapshot = try await provider.fetch()

            expect(snapshot.primary.windowMinutes == 300, "primary window should be 300 minutes")
            expect(snapshot.primary.label == "5 小时", "primary label should be 5 小时")
            expect(snapshot.primary.usedPercent == 39, "primary used percent should be 39")
            expect(snapshot.primary.remainingPercent == 61, "primary remaining percent should be 61")
            expect(snapshot.secondary.windowMinutes == 10080, "secondary window should be 10080 minutes")
            expect(snapshot.secondary.label == "7 天", "secondary label should be 7 天")
            expect(snapshot.secondary.remainingPercent == 94, "secondary remaining percent should be 94")
            expect(snapshot.planType == "prolite", "plan type should be prolite")
            expect(snapshot.source.hasSuffix("rollout-new.jsonl"), "source should point at newest rollout")
        }
    }

    private static func testIgnoresTokenCountWithoutRateLimits() async throws {
        try await withTemporaryCodexHome { codexHome in
            try writeRollout(
                codexHome: codexHome,
                relativePath: "sessions/2026/05/19/rollout-empty.jsonl",
                lines: [
                    #"{"timestamp":"2026-05-19T13:31:22.239Z","type":"event_msg","payload":{"type":"token_count"}}"#
                ]
            )

            let provider = CodexJSONLQuotaProvider(codexHome: codexHome)

            do {
                _ = try await provider.fetch()
                throw SmokeTestError.failed("expected no quota data error")
            } catch let error as QuotaProviderError {
                expect(error == .noQuotaData, "missing rate limits should throw noQuotaData")
            }
        }
    }

    private static func testChoosesNewestEventAcrossFiles() async throws {
        try await withTemporaryCodexHome { codexHome in
            try writeRollout(
                codexHome: codexHome,
                relativePath: "sessions/2026/05/19/rollout-old.jsonl",
                lines: [
                    tokenCountLine(timestamp: "2026-05-19T13:31:22.239Z", primaryUsed: 80, secondaryUsed: 30)
                ]
            )

            try writeRollout(
                codexHome: codexHome,
                relativePath: "sessions/2026/05/20/rollout-new.jsonl",
                lines: [
                    tokenCountLine(timestamp: "2026-05-20T13:31:22.239Z", primaryUsed: 12, secondaryUsed: 44)
                ]
            )

            let provider = CodexJSONLQuotaProvider(codexHome: codexHome)
            let snapshot = try await provider.fetch()

            expect(snapshot.primary.remainingPercent == 88, "newest primary remaining should be 88")
            expect(snapshot.secondary.remainingPercent == 56, "newest secondary remaining should be 56")
            expect(snapshot.source.hasSuffix("rollout-new.jsonl"), "newest event source should win")
        }
    }

    private static func testClampsRemainingPercent() async throws {
        try await withTemporaryCodexHome { codexHome in
            try writeRollout(
                codexHome: codexHome,
                relativePath: "sessions/2026/05/20/rollout-clamp.jsonl",
                lines: [
                    tokenCountLine(timestamp: "2026-05-20T13:31:22.239Z", primaryUsed: 125, secondaryUsed: -5)
                ]
            )

            let provider = CodexJSONLQuotaProvider(codexHome: codexHome)
            let snapshot = try await provider.fetch()

            expect(snapshot.primary.remainingPercent == 0, "remaining percent should clamp to 0")
            expect(snapshot.secondary.remainingPercent == 100, "remaining percent should clamp to 100")
        }
    }

    private static func withTemporaryCodexHome(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(codexHome)
    }

    private static func writeRollout(codexHome: URL, relativePath: String, lines: [String]) throws {
        let url = codexHome.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static var brokenJSONLine: String {
        #"{"timestamp": "not valid""#
    }

    private static func tokenCountLine(timestamp: String, primaryUsed: Double, secondaryUsed: Double) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":\(primaryUsed),"window_minutes":300,"resets_at":1779199104},"secondary":{"used_percent":\(secondaryUsed),"window_minutes":10080,"resets_at":1779785904},"credits":null,"plan_type":"prolite","rate_limit_reached_type":null}}}
        """
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}

private enum SmokeTestError: Error {
    case failed(String)
}
