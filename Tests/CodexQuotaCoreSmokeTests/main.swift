import CodexQuotaCore
import Foundation

@main
enum CodexQuotaCoreSmokeTests {
    static func main() async throws {
        log("Running testParsesLatestTokenCountRateLimits")
        try await testParsesLatestTokenCountRateLimits()
        log("Running testIgnoresTokenCountWithoutRateLimits")
        try await testIgnoresTokenCountWithoutRateLimits()
        log("Running testChoosesNewestEventAcrossFiles")
        try await testChoosesNewestEventAcrossFiles()
        log("Running testClampsRemainingPercent")
        try await testClampsRemainingPercent()
        log("Running testParsesAppServerRateLimits")
        try testParsesAppServerRateLimits()
        log("Running testFallbackProviderUsesJSONLWhenAppServerFails")
        try await testFallbackProviderUsesJSONLWhenAppServerFails()
        log("Running testPersistentAppServerClientReceivesSparseUpdate")
        try await testPersistentAppServerClientReceivesSparseUpdate()
        log("CodexQuotaCoreSmokeTests passed")
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
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
            expect(snapshot.limitId == "codex", "limit id should be codex")
            expect(snapshot.sourceKind == .offlineSnapshot, "JSONL source should be offline")
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

    private static func testParsesAppServerRateLimits() throws {
        let data = """
        {
          "rateLimits": {
            "limitId": "legacy",
            "limitName": null,
            "primary": {
              "usedPercent": 80,
              "windowDurationMins": 300,
              "resetsAt": 1779199104
            },
            "secondary": {
              "usedPercent": 70,
              "windowDurationMins": 10080,
              "resetsAt": 1779785904
            },
            "planType": "pro"
          },
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "limitName": null,
              "credits": {
                "balance": "10",
                "hasCredits": true,
                "unlimited": false
              },
              "primary": {
                "usedPercent": 3,
                "windowDurationMins": 300,
                "resetsAt": 1779429665
              },
              "secondary": {
                "usedPercent": 34,
                "windowDurationMins": 10080,
                "resetsAt": 1779836113
              },
              "planType": "prolite",
              "rateLimitReachedType": "workspace_member_usage_limit_reached",
              "individualLimit": {
                "limit": "100",
                "used": "12",
                "remainingPercent": 88,
                "resetsAt": 1779836113
              }
            }
          }
        }
        """.data(using: .utf8)!

        let snapshot = try CodexAppServerQuotaProvider.snapshot(
            fromAppServerResultData: data,
            capturedAt: Date(timeIntervalSince1970: 1)
        )

        expect(snapshot.sourceKind == .codexAppServer, "source kind should be app-server realtime")
        expect(snapshot.primary.windowMinutes == 300, "primary app-server window should be 300 minutes")
        expect(snapshot.primary.remainingPercent == 97, "primary app-server remaining should be 97")
        expect(snapshot.secondary.windowMinutes == 10080, "secondary app-server window should be 10080 minutes")
        expect(snapshot.secondary.remainingPercent == 66, "secondary app-server remaining should be 66")
        expect(snapshot.planType == "prolite", "app-server codex limit should win over legacy root limit")
        expect(snapshot.limitId == "codex", "app-server limit id should be codex")
        expect(snapshot.credits?.hasCredits == true, "app-server credits should parse")
        expect(snapshot.individualLimit?.remainingPercent == 88, "individual limit should parse")
        expect(snapshot.rateLimitReachedType == "workspace_member_usage_limit_reached", "reached type should parse")
    }

    private static func testFallbackProviderUsesJSONLWhenAppServerFails() async throws {
        try await withTemporaryCodexHome { codexHome in
            try writeRollout(
                codexHome: codexHome,
                relativePath: "sessions/2026/05/20/rollout-fallback.jsonl",
                lines: [
                    tokenCountLine(timestamp: "2026-05-20T13:31:22.239Z", primaryUsed: 41, secondaryUsed: 22)
                ]
            )

            let provider = FallbackQuotaProvider(
                primary: FailingQuotaProvider(error: QuotaProviderError.codexCLIUnavailable),
                fallback: CodexJSONLQuotaProvider(codexHome: codexHome)
            )
            let snapshot = try await provider.fetch()

            expect(snapshot.primary.remainingPercent == 59, "fallback primary remaining should come from JSONL")
            expect(snapshot.secondary.remainingPercent == 78, "fallback secondary remaining should come from JSONL")
            expect(snapshot.sourceKind == .offlineSnapshot, "fallback source should be offline")
        }
    }

    private static func testPersistentAppServerClientReceivesSparseUpdate() async throws {
        let scriptURL = try writeFakeAppServerScript()
        let client = CodexAppServerClient(
            executableURL: scriptURL,
            arguments: [],
            environment: ProcessInfo.processInfo.environment,
            defaultTimeout: 3
        )
        let provider = CodexAppServerQuotaProvider(client: client, timeout: 3)
        let counter = LockedCounter()

        provider.setRateLimitsUpdatedHandler {
            counter.increment()
        }

        let first = try await provider.fetch()
        try await waitUntil(timeout: 2) {
            counter.value > 0
        }
        let second = try await provider.fetch()
        provider.stop()

        expect(first.primary.remainingPercent == 91, "first fake app-server snapshot should parse")
        expect(second.primary.remainingPercent == 83, "second fake app-server snapshot should parse")
        expect(second.limitName == "Codex", "second read should keep full limit metadata")
        expect(counter.value == 1, "sparse rate limit update should trigger notification once")
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

    private static func writeFakeAppServerScript() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-codex-app-server-\(UUID().uuidString).zsh")
        let script = """
        #!/bin/zsh
        count=0
        while IFS= read -r line; do
          if [[ "$line" == *initialize* && "$line" == *id* ]]; then
            echo '{"id":1,"result":{}}'
          elif [[ "$line" == *rateLimits*read* ]]; then
            if [[ "$count" == "0" ]]; then
              echo '{"id":2,"result":{"rateLimits":{"limitId":"legacy","primary":{"usedPercent":99,"windowDurationMins":300,"resetsAt":1779199104},"secondary":{"usedPercent":99,"windowDurationMins":10080,"resetsAt":1779785904},"planType":"pro"},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":"Codex","primary":{"usedPercent":9,"windowDurationMins":300,"resetsAt":1779429665},"secondary":{"usedPercent":11,"windowDurationMins":10080,"resetsAt":1779836113},"planType":"prolite"}}}}'
              echo '{"method":"account/rateLimits/updated","params":{"rateLimits":{"primary":{"usedPercent":77}}}}'
              count=1
            else
              echo '{"id":3,"result":{"rateLimits":{"limitId":"codex","limitName":"Codex","primary":{"usedPercent":17,"windowDurationMins":300,"resetsAt":1779429665},"secondary":{"usedPercent":19,"windowDurationMins":10080,"resetsAt":1779836113},"planType":"prolite"}}}'
            fi
          fi
        done
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private static func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        throw SmokeTestError.failed("condition was not met before timeout")
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

private struct FailingQuotaProvider: QuotaProvider {
    let error: Error

    func fetch() async throws -> QuotaSnapshot {
        throw error
    }
}

private final class LockedCounter {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
