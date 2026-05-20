import AppKit
import CodexQuotaCore
import SwiftUI

struct QuotaPanelView: View {
    @ObservedObject var store: QuotaStore
    @State private var showLiveRefreshWarning = false

    var body: some View {
        ZStack {
            AnimatedGlassBackground()

            VStack(spacing: 0) {
                if let snapshot = store.snapshot {
                    Spacer(minLength: 6)

                    HStack(spacing: 24) {
                        QuotaWindowView(window: snapshot.primary)
                        Divider()
                            .frame(height: 108)
                            .overlay(Color.white.opacity(0.16))
                        QuotaWindowView(window: snapshot.secondary)
                    }

                    Spacer(minLength: 12)

                    footer(snapshot: snapshot)
                } else {
                    EmptyQuotaView(
                        message: store.errorMessage ?? "暂无额度数据",
                        isRefreshing: store.isRefreshing,
                        isLiveRefreshing: store.isLiveRefreshing,
                        refresh: store.refresh,
                        liveRefresh: { showLiveRefreshWarning = true }
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 500, height: 200)
        .alert("实时刷新会消耗少量 Codex 额度", isPresented: $showLiveRefreshWarning) {
            Button("取消", role: .cancel) {}
            Button("继续实时刷新") {
                store.refreshLive()
            }
        } message: {
            Text("普通刷新只重扫本机日志，零消耗。实时刷新会调用 Codex CLI 发起一次极小请求，用来获取服务端最新 rate_limits。")
        }
    }

    private func footer(snapshot: QuotaSnapshot) -> some View {
        HStack(spacing: 8) {
            if let planType = snapshot.planType, !planType.isEmpty {
                Text(planType.uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .foregroundStyle(.white.opacity(0.74))
                    .background(Color.white.opacity(0.10), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }
            }

            Text(snapshot.sourceKind.displayName)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .foregroundStyle(.white.opacity(0.72))
                .background(Color.black.opacity(0.16), in: Capsule())
                .help(snapshot.source)

            Spacer()

            Button(action: store.refresh) {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 24)
                }
            }
            .buttonStyle(IconButtonStyle())
            .help("本机刷新：重扫本机 Codex 日志，零消耗；自动每 5 分钟检查一次")

            Button(action: { showLiveRefreshWarning = true }) {
                if store.isLiveRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 24)
                } else {
                    Text("实时")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .frame(width: 34, height: 24)
                }
            }
            .buttonStyle(LiveRefreshButtonStyle())
            .disabled(store.isLiveRefreshing)
            .help("实时刷新：调用 Codex CLI 获取服务端最新额度，会消耗少量额度")

            Button(action: SettingsWindowController.shared.show) {
                Image(systemName: "gearshape")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(IconButtonStyle())
            .help("设置")

            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(IconButtonStyle())
            .help("退出")
        }
    }
}

private struct AnimatedGlassBackground: View {
    @State private var drifting = false

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .popover)

            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.50, blue: 0.47).opacity(0.36),
                    Color(red: 0.84, green: 0.38, blue: 0.31).opacity(0.28),
                    Color(red: 0.16, green: 0.21, blue: 0.26).opacity(0.58)
                ],
                startPoint: drifting ? .topTrailing : .topLeading,
                endPoint: drifting ? .bottomLeading : .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.28, green: 0.92, blue: 0.82).opacity(0.26),
                    Color.clear
                ],
                center: .center,
                startRadius: 8,
                endRadius: 190
            )
            .scaleEffect(drifting ? 1.18 : 0.92)
            .offset(x: drifting ? 118 : -88, y: drifting ? -48 : 44)

            RadialGradient(
                colors: [
                    Color(red: 1.00, green: 0.50, blue: 0.35).opacity(0.20),
                    Color.clear
                ],
                center: .center,
                startRadius: 6,
                endRadius: 170
            )
            .scaleEffect(drifting ? 0.94 : 1.20)
            .offset(x: drifting ? -112 : 96, y: drifting ? 58 : -44)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.09),
                    Color.clear,
                    Color.black.opacity(0.24)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Color.black.opacity(0.40)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                drifting = true
            }
        }
        .onDisappear {
            drifting = false
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
    }
}

private struct QuotaWindowView: View {
    let window: QuotaWindow

    var body: some View {
        VStack(spacing: 8) {
            Text("\(window.label)余量")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))

            HStack(spacing: 14) {
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(width: 38)

                QuotaRing(percent: window.remainingPercent)
                    .frame(width: 68, height: 68)

                Text(window.resetsAt.relativeResetText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(width: 38)
            }

            Text("重置 \(window.resetsAt.formattedDateTime)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct QuotaRing: View {
    let percent: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 7)

            Circle()
                .trim(from: 0, to: percent / 100)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int(percent.rounded()))%")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
        .accessibilityLabel("剩余 \(Int(percent.rounded()))%")
    }

    private var color: Color {
        switch percent {
        case 50...:
            return .white.opacity(0.82)
        case 20..<50:
            return .yellow
        default:
            return .red
        }
    }
}

private struct EmptyQuotaView: View {
    let message: String
    let isRefreshing: Bool
    let isLiveRefreshing: Bool
    let refresh: () -> Void
    let liveRefresh: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.pie")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))

            Text(message)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))

            Text("等待 Codex 会话写入 token_count / rate_limits 后自动显示")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))

            HStack(spacing: 10) {
                Button(action: refresh) {
                    Label(isRefreshing ? "刷新中" : "本机刷新", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)

                Button(action: liveRefresh) {
                    Label(isLiveRefreshing ? "实时中" : "实时刷新", systemImage: "bolt.fill")
                }
                .disabled(isLiveRefreshing)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.56 : 0.86))
            .background(Color.white.opacity(configuration.isPressed ? 0.18 : 0.10), in: Circle())
    }
}

private struct LiveRefreshButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.62 : 0.88))
            .background(Color.orange.opacity(configuration.isPressed ? 0.30 : 0.20), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.orange.opacity(0.28), lineWidth: 1)
            }
    }
}

private extension Date {
    var formattedTime: String {
        formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    var formattedDateTime: String {
        formatted(
            .dateTime
                .month(.twoDigits)
                .day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }

    var relativeResetText: String {
        let seconds = timeIntervalSinceNow

        if seconds <= 0 {
            return "现在"
        }

        let hours = Int(seconds / 3600)

        if hours >= 24 {
            return "\(hours / 24)天"
        }

        if hours >= 1 {
            return "\(hours)时"
        }

        return "\(max(1, Int(seconds / 60)))分"
    }
}
