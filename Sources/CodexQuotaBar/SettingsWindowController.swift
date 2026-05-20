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
        window.setContentSize(NSSize(width: 440, height: 250))
        window.minSize = NSSize(width: 440, height: 250)
        window.maxSize = NSSize(width: 440, height: 250)
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
        VStack(alignment: .leading, spacing: 16) {
            header

            VStack(spacing: 10) {
                settingsRow(
                    title: "数据源",
                    value: codexHome.path,
                    monospace: true
                ) {
                    Button("打开") {
                        NSWorkspace.shared.open(codexHome)
                    }
                }

                settingsRow(title: "自动检查", value: "每 5 分钟")
                settingsRow(title: "读取内容", value: "token_count 事件里的 rate_limits")
            }

            HStack(spacing: 6) {
                Text("作者")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("softgoto + Codex")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.82))
            }

            Text("没有找到额度事件时，菜单栏会显示 Cx --，不会根据 token 用量猜测剩余额度。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(width: 440, height: 250, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.teal)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("CodexQuotaBar")
                        .font(.system(size: 18, weight: .bold))

                    Text(appVersion)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(.secondary)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                }

                Text("Codex 额度菜单栏组件")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
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
    }

    private func settingsRow(title: String, value: String) -> some View {
        settingsRow(title: title, value: value) {
            EmptyView()
        }
    }
}
