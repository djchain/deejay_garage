# Bark Notifier

Claude Code 完成响应时向 iPhone 发送包含**完整输出**的推送通知。无论通过桌面 CLI、Claude Remote iOS App 还是任意 Channel，Claude 停下时都会通知。

## 架构

```
┌─ 桌面 CLI ─────────────────────────┐    ┌─ Claude Remote (iOS) ──────┐
│  Claude Code CLI                     │    │  iPhone → Bridge → tmux     │
│    ↓ Stop / StopFailure /            │    │    ↓ Claude Code CLI        │
│      PermissionRequest hook          │    │  Stop hook → 同一脚本       │
│  bark-notify.sh (thin dispatcher)    │    │                             │
└────────┬─────────────────────────────┘    └────────┬────────────────────┘
         │                                           │
         └──────────────────┬────────────────────────┘
                            ↓
              ┌─────────────────────────┐
              │  bark-smart-notify.sh    │
              │  (intelligence script)   │
              │  ① Parse stdin JSON     │
              │     or -t/-b args       │
              │  ② Extract last         │
              │     assistant from       │
              │     JSONL transcript     │
              │  ③ Categorize content   │
              │     per trigger type    │
              │  ④ Generate title       │
              │     (~60 chars)          │
              │  ⑤ Send via Bridge or   │
              │     direct curl to API  │
              └───────────┬─────────────┘
                          │
              ┌───────────┴───────────┐
              │                       │
        Bridge /bark            api.day.app
        (localhost:8080)         (direct, no Tailscale)
              │                       │
              └───────────┬───────────┘
                          ↓
                    iPhone 通知
```

## 通知内容示例

不再发送无意义的"响应完成"。每条通知都包含 Claude 的实际输出：

```
Title:  "❓ 你希望我立即开始实现吗？"
Body:   "我找到了问题。Hook 脚本确实存在，但它发送的 body 是静态文本，
        完全没有读 Claude 的实际输出。需要修改两个地方..."

Title:  "✅ 所有测试通过，无需额外操作"
Body:   "已完成 Bark 通知系统全部修复。修改清单：1. bark-smart-notify.sh — 
        统一智能通知脚本 2. Hook 脚本 — delegate 调用 3. Bridge /bark 端点..."
```

## 网络要求

Bark 通知**不依赖 Tailscale**。推送链路是：

```
Mac → curl → https://api.day.app → Apple APNs → iPhone
```

纯公网 HTTP API，Mac 只要能上网就能推送，与 Tailscale / VPN / 局域网无关。

Tailscale 仅用于 Claude Remote iOS App 的 WebSocket 连接（让 iPhone 跨网络连到 Mac Bridge）。

## 文件清单

| 文件 | 用途 |
|------|------|
| `bark-smart-notify.sh` | **核心** — 统一智能通知脚本 |
| `notify.sh` | 可复用的 shell 函数组件（`bark_notify` / `bark_notify_success` / `bark_notify_run`） |
| `README.md` | 本文档 |

### 外部依赖

| 文件 | 用途 |
|------|------|
| `~/.claude/hooks/bark-notify.sh` | Hook 入口 — 委派给 `bark-smart-notify.sh` |
| `~/.config/bark/bark.env` | 私密配置（device key），不入仓库 |
| `~/.local/bin/bark` | Bark CLI 命令（手动使用） |
| Bridge `/bark` 端点 | Go Bridge 提供的 HTTP 通知网关（冗余通道） |

## 直接使用

```sh
# 通过 Hook 自动调用（从 stdin 读取 Claude Code 事件 JSON）
./bark-smart-notify.sh

# 直接发送通知
./bark-smart-notify.sh -t "标题" -b "正文" -l active -g Mac

# 调用方式二（位置参数）
./bark-smart-notify.sh "标题" "正文"
```

## 通知分类

Hook 仅响应三种事件。Stop 的图标和级别由 `bark-smart-notify.sh`
根据 transcript 中的最后一条 assistant 内容动态分类：

| 事件 | 图标 | 级别 | 触发场景 |
|------|------|------|---------|
| Stop（含"?"） | ❓ | `active` | 首句含问号 → 需要用户决策 |
| Stop（权限相关） | 🔐 | `timeSensitive` | 文本含 approve/permit 等关键词 |
| Stop（默认） | 🤖 | `passive` | 其他一般就绪 |
| StopFailure | ❌ | `timeSensitive` | API 错误 / 响应失败（Hook 直接构造） |
| PermissionRequest | 🔐 | `timeSensitive` | Claude 请求工具权限（Hook 直接构造） |

## Shell 函数组件

`notify.sh` 提供可在其他脚本中复用的函数：

```sh
. /path/to/notify.sh

bark_notify "任务完成" "部署已成功"
bark_notify_failure "构建失败" "查看错误日志"
bark_notify_run sleep 10
```

可选默认值：

```sh
export BARK_NOTIFY_DEFAULT_LEVEL=timeSensitive
export BARK_NOTIFY_DEFAULT_GROUP=Garage
```

## Bridge `/bark` 端点

```
POST /bark
Content-Type: application/json

{"title": "标题", "body": "正文", "level": "active", "group": "Mac"}

GET /bark/health
→ {"status": "ok"} 或 {"status": "unconfigured"}
```
