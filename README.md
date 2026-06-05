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
- 点击菜单栏项打开带浅色渐变和毛玻璃效果的圆角 popover。
- 启动后持有一个 `codex app-server --stdio` JSON-RPC 连接，读取 `account/rateLimits/read`。
- 监听 `account/rateLimits/updated` 后 debounce，再重新读取完整 `rateLimits` 快照。
- 每 5 分钟执行一次兜底同步；app-server 不可用时回退扫描 `~/.codex/sessions/**/rollout-*.jsonl`。
- “本机刷新”只重扫本机 Codex 日志，作为离线快照；“实时刷新”读取 app-server，零模型请求。
- `/status` 是 Codex 交互式 slash command，不作为本工具的数据接口。
- 没有找到额度数据时显示 `Cx --`，不会根据 token 用量猜测剩余额度。
