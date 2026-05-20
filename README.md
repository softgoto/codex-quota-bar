# CodexQuotaBar

原生 macOS 菜单栏小工具，用 SwiftUI + AppKit 展示 Codex 额度余量。

## Build

```bash
scripts/test.sh
swift build
scripts/build-app.sh
```

打包后的应用位于：

```text
.build/CodexQuotaBar.app
```

## Behavior

- 菜单栏显示 `Cx <剩余百分比>%`，取 5 小时和 7 天窗口中较低的余量。
- 点击菜单栏项打开黑色圆角 popover。
- 每 5 分钟扫描最近修改的 `~/.codex/sessions/**/rollout-*.jsonl`。
- 只解析 `event_msg.payload.type == "token_count"` 且包含 `rate_limits` 的 JSONL 行。
- 没有找到额度数据时显示 `Cx --`，不会根据 token 用量猜测剩余额度。
