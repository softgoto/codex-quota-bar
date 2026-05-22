import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView()
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "CodexQuotaBar 设置"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 480, height: 292))
        window.minSize = NSSize(width: 480, height: 292)
        window.maxSize = NSSize(width: 480, height: 292)
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsView: View {
    private let codexHome = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            settingsGroup
            footer
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(width: 480, height: 292, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var settingsGroup: some View {
        VStack(spacing: 0) {
            settingsRow(
                title: "数据源",
                value: codexHome.path,
                monospace: true
            ) {
                Button("打开") {
                    NSWorkspace.shared.open(codexHome)
                }
            }

            rowSeparator
            settingsRow(title: "自动检查", value: "每 5 分钟")
            rowSeparator
            settingsRow(title: "读取内容", value: "app-server rate_limits；旧版回退 JSONL")
            rowSeparator
            settingsRow(title: "本机刷新", value: "重扫本机日志，零额度消耗")
            rowSeparator
            settingsRow(title: "实时刷新", value: "零模型请求；旧版回退本机快照")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
    }

    private var rowSeparator: some View {
        Divider()
            .padding(.leading, 82)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("作者")
                .font(.system(size: 11, weight: .semibold))

            Text("softgoto + Codex")
                .font(.system(size: 11, weight: .medium))

            Spacer()

            Text("无数据时显示 Cx --，不猜测")
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.teal, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("CodexQuotaBar")
                    .font(.system(size: 19, weight: .bold))

                Text("Codex 额度菜单栏组件")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(appVersion)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(.secondary)
                .background(Color.secondary.opacity(0.10), in: Capsule())
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let version, let build {
            return "v\(version) (\(build))"
        }

        if let version {
            return "v\(version)"
        }

        return "v0.1.0"
    }

    private func settingsRow<Trailing: View>(
        title: String,
        value: String,
        monospace: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)

            Text(value)
                .font(monospace ? .system(size: 12, design: .monospaced) : .system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            trailing()
                .controlSize(.small)
        }
        .frame(height: 30)
    }

    private func settingsRow(title: String, value: String) -> some View {
        settingsRow(title: title, value: value) {
            EmptyView()
        }
    }
}
