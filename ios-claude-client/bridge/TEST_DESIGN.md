# Go Bridge MVP - Phase 1 测试设计文档

## 概述

本文档定义 Phase 1 (Bridge MVP) 的测试策略。Go Bridge 是一个轻量级 WebSocket ↔ PTY 桥接服务。

### 架构组件

```
┌──────────────┐   WebSocket    ┌──────────────┐   PTY   ┌──────────────┐
│  iOS App     │ ◄─────────────►│  Bridge      │◄──────►│  Claude Code │
│  (SwiftUI)   │   JSON-framed  │  (Go 程序)    │        │  (tmux)      │
└──────────────┘                └──────┬───────┘        └──────────────┘
                                       │ Bonjour
                                       ▼
                               ┌──────────────┐
                               │  mDNS 广播    │
                               └──────────────┘
```

### 消息协议

- 上行 (iOS → Bridge): `{"type":"input","data":"<keystrokes>"}`
- 下行 (Bridge → iOS): `{"type":"output","data":"<ansi>"}`, `{"type":"resize","cols":N,"rows":M}`
- 控制: `{"type":"signal","name":"int"|"eof"}`, `{"type":"ping"}`

---

## 1. PTY 管理组件 (`pty.go`)

### 测试范围
Go 标准库 + `github.com/creack/pty` 创建和管理 PTY

| # | 场景 | 输入 | 预期输出 | 优先级 | 类型 | 工作量 |
|---|------|------|----------|--------|------|--------|
| P1 | 创建 PTY 并运行命令 | `startWithCommand("tmux", "new-session", ...)` | PTY fd != nil, no error | P0 | 单元 | S |
| P2 | PTY 读取输出 | PTY 写入 `echo hello` | `stdout` 包含 `hello` | P0 | 单元 | S |
| P3 | PTY 写入输入 | 向 PTY 写入 `ls\n` | 从 PTY 读取到目录列表 | P0 | 单元 | S |
| P4 | PTY resize | `Resize(rows=40, cols=120)` | PTY 窗口大小实际变更 | P0 | 单元 | S |
| P5 | 启动 tmux session | `startTmuxSession("claude-code")` | tmux session 存在, attachable | P0 | 集成 | M |
| P6 | 在 tmux 中启动 Claude Code | tmux send-keys `claude` | 进程启动, PTY 有输出 | P1 | 集成 | M |
| P7 | 断开后 session 持久 | 结束子进程, tmux detach | tmux session 仍存活 | P0 | 集成 | M |
| P8 | 重新 attach 到已有 session | tmux attach 到之前 session | 可继续交互 | P1 | 集成 | M |
| P9 | 子进程异常退出处理 | PTY 子进程收到 SIGKILL | 错误被捕获, 资源清理 | P1 | 单元 | S |
| P10 | 并发 PTY 访问 | 同时读写 PTY | 数据不混乱, 无竞争条件 | P1 | 单元 | S |

### 关键依赖
- `github.com/creack/pty` - PTY 创建
- `os/exec` + `os` - 子进程管理
- `github.com/kr/pty` (备选) - 如果 creack/pty 不可用

---

## 2. WebSocket 服务组件 (`server.go`)

### 测试范围
基于 `net/http` + `gorilla/websocket` 的 WebSocket 端点

| # | 场景 | 输入 | 预期输出 | 优先级 | 类型 | 工作量 |
|---|------|------|----------|--------|------|--------|
| W1 | 启动 WS 服务器 | `Start(":9090")` | 端口监听成功 | P0 | 集成 | S |
| W2 | 客户端成功连接 | `ws://localhost:9090/ws` 发起连接 | 握手成功, 连接建立 | P0 | 集成 | M |
| W3 | 接收 JSON 消息 (input) | `{"type":"input","data":"hello"}` | 解析为 InputMessage | P0 | 单元 | S |
| W4 | 接收 JSON 消息 (signal) | `{"type":"signal","name":"int"}` | 解析为 SignalMessage | P0 | 单元 | S |
| W5 | 接收 JSON 消息 (ping) | `{"type":"ping"}` | 解析为 PingMessage | P0 | 单元 | S |
| W6 | 发送 JSON 消息 (output) | 发送 OutputMessage | WS 收到 `{"type":"output","data":"..."}` | P0 | 集成 | M |
| W7 | 发送 JSON 消息 (resize) | 发送 ResizeMessage | WS 收到 `{"type":"resize","cols":40,"rows":120}` | P0 | 集成 | M |
| W8 | 非法 JSON 消息 | `{"type":"invalid"}` | 返回错误, 不断开连接 | P1 | 集成 | S |
| W9 | 非 JSON 数据 | `纯文本数据` | 返回错误 | P1 | 集成 | S |
| W10 | 大消息 (>1MB) | 发送 2MB 数据 | 正常处理或优雅拒绝 | P2 | 集成 | M |
| W11 | 同时多个客户端连接 | 5 个客户端同时连接 | 所有客户端正常交互 | P1 | 集成 | L |
| W12 | 端口冲突 | 端口已被占用 | 返回错误, 不崩溃 | P1 | 集成 | S |
| W13 | WebSocket Clean Close | 客户端发送 close frame | 连接正常关闭 | P1 | 集成 | S |
| W14 | 心跳/Pong 响应 | 周期性 ping | 连接保持, 无超时断开 | P1 | 集成 | M |

### 关键依赖
- `github.com/gorilla/websocket` - WebSocket 实现
- `net/http` - HTTP 服务器

---

## 3. WebSocket ↔ PTY 桥接组件 (`bridge.go`)

### 测试范围
核心业务逻辑: 在 WebSocket 和 PTY 之间双向数据转发

| # | 场景 | 输入 | 预期输出 | 优先级 | 类型 | 工作量 |
|---|------|------|----------|--------|------|--------|
| B1 | 输入转发: WS → PTY | WS 发送 `{"type":"input","data":"ls\n"}` | PTY 收到 `ls\n` 并执行 | P0 | 集成 | M |
| B2 | 输出转发: PTY → WS | PTY 进程输出文本 | WS 收到 `{"type":"output","data":"..."}` | P0 | 集成 | M |
| B3 | Signal: Ctrl-C (INT) | WS 发送 `{"type":"signal","name":"int"}` | PTY 收到 SIGINT | P0 | 集成 | M |
| B4 | Signal: EOF | WS 发送 `{"type":"signal","name":"eof"}` | PTY 收到 EOF (Ctrl-D) | P0 | 集成 | M |
| B5 | PTY Resize 转发 | WS 发送 `{"type":"resize","cols":80,"rows":24}` | PTY 实际 resize | P0 | 集成 | M |
| B6 | 响应 Ping | WS 发送 `{"type":"ping"}` | WS 收到 `{"type":"pong"}` 或等价响应 | P0 | 单元 | S |
| B7 | 客户端断连 | WebSocket 意外断开 | PTY 进程不终止 | P0 | 集成 | M |
| B8 | 客户端重连 | 新 WS 连接, 目标同一 session | attach 到同一 tmux session | P1 | 集成 | L |
| B9 | 大流量吞吐 | 持续发送 1000 条消息/s | 不丢消息, 延迟 < 100ms | P1 | 集成 | L |
| B10 | 桥接启动顺序 | WS 连接建立后才启动 PTY | 先建 WS 连接, 再启动 PTY | P1 | 集成 | M |
| B11 | 并发读写安全 | 多 goroutine 同时读写 PTY | 数据不混乱, 无竞态 | P1 | 单元 | S |

### 桥接状态机

```
DISCONNECTED → CONNECTED → BRIDGING → DISCONNECTED
    ↑                                            │
    └────────────────────────────────────────────┘
```

- CONNECTED: WebSocket 已连接, 准备桥接
- BRIDGING: PTY 已启动, 双向转发进行中
- DISCONNECTED: 任何一方断开

---

## 4. Session 持久化组件 (`session.go`)

### 测试范围
Session 的创建、存储、查找和生命周期管理

| # | 场景 | 输入 | 预期输出 | 优先级 | 类型 | 工作量 |
|---|------|------|----------|--------|------|--------|
| S1 | 创建新 session | `NewSession("main")` | session 对象创建成功 | P0 | 单元 | S |
| S2 | 查找 session by ID | `GetSession("id-123")` | 返回 session 对象 | P0 | 单元 | S |
| S3 | 查找不存在的 session | `GetSession("nonexistent")` | 返回 nil/error | P1 | 单元 | S |
| S4 | 列出所有 sessions | `ListSessions()` | 返回 session 列表 | P1 | 单元 | S |
| S5 | 删除 session | `DeleteSession("id-123")` | session 被移除 | P1 | 单元 | S |
| S6 | 检测 session 存活 | `IsSessionAlive("id-123")` | tmux session 确实存在 | P0 | 集成 | M |
| S7 | session 超时清理 | 长时间无活动的 session | 自动清理 | P2 | 集成 | L |
| S8 | session ID 生成 | 多次创建 session | ID 唯一, 不重复 | P1 | 单元 | S |

### Session 数据结构

```go
type Session struct {
    ID        string
    Name      string
    TmuxName  string
    PTY       *os.File
    Cmd       *exec.Cmd
    CreatedAt time.Time
    LastUsed  time.Time
    Active    bool
}
```

---

## 5. Bonjour/mDNS 广播组件 (`mdns.go`)

### 测试范围
基于 `github.com/hashicorp/mdns` 的零配置网络发现

| # | 场景 | 输入 | 预期输出 | 优先级 | 类型 | 工作量 |
|---|------|------|----------|--------|------|--------|
| M1 | 注册 Bonjour 服务 | `Register("Claude Bridge", 9090)` | 服务在局域网可见 | P0 | 集成 | M |
| M2 | 服务类型正确 | `_claudebridge._tcp` | 符合预期类型 | P1 | 单元 | S |
| M3 | 取消注册 | `Deregister()` | 服务不再可见 | P1 | 集成 | M |
| M4 | 服务元数据 | instance 包含版本信息 | 客户端可获取版本 | P1 | 集成 | S |
| M5 | Wi-Fi 断开/重连 | 网络变化后 | 服务自动重新注册 | P2 | 集成 | L |
| M6 | IPv4 + IPv6 双栈 | 双栈网络环境 | 两种地址都可发现 | P2 | 集成 | L |

### 关键依赖
- `github.com/hashicorp/mdns` - mDNS/Bonjour 库

---

## 6. 集成测试 (端到端)

| # | 场景 | 步骤 | 预期结果 | 优先级 | 工作量 |
|---|------|------|----------|--------|--------|
| E2E1 | 完整启动流程 | 1) 启动 Bridge<br>2) 启动 websocat 连接<br>3) 发送输入消息 | 收到 PTY 输出回显 | P0 | M |
| E2E2 | PTY resize + 验证 | 1) 连接 WS<br>2) 发送 resize 消息<br>3) 查询终端尺寸 | 终端尺寸已变更 | P1 | M |
| E2E3 | 断开重连 | 1) 连接 WS<br>2) 断开 WS<br>3) 等待 5s<br>4) 重新连接<br>5) 发送输入 | 同一 tmux session, 历史输出可见 | P1 | L |
| E2E4 | Bonjour 发现 | 1) 启动 Bridge<br>2) Mac 上 dns-sd -B | 服务可被发现 | P1 | M |
| E2E5 | 多次断开重连 | 重复 E2E3 3 次 | session 始终存活 | P2 | L |

---

## 7. 边界 & 异常场景

| # | 场景 | 输入/条件 | 预期行为 | 优先级 | 工作量 |
|---|------|-----------|----------|--------|--------|
| E1 | Bridge 启动时 tmux 未安装 | 环境无 tmux | 报告清晰错误, 优雅退出 | P1 | S |
| E2 | Bridge 启动时 claude 命令不存在 | PATH 中无 claude | 报告警告, 仍启动 WS 服务 | P2 | S |
| E3 | PTY 写入速度 > 读取速度 | 高速写入 | 内部缓冲区正确处理, 不 OOM | P1 | M |
| E4 | WebSocket 消息乱序 | 消息顺序到达 | 按序处理 | P1 | S |
| E5 | 多个客户端操作同一 session | 2 个 WS 连接同一 session | 输入合并, 输出都可见 | P2 | L |

---

## 8. 测试策略总结

### 分层测试

| 层 | 测试数量 | 类型 | 职责 |
|----|---------|------|------|
| 单元测试 | ~15 个 | Go `testing` + testify | 消息解析, 数据结构, 错误处理 |
| 集成测试 | ~15 个 | Go `testing` + testutil | PTY+WS 交互, 桥接逻辑 |
| E2E 测试 | ~5 个 | shell script + websocat | 完整功能验证 |

### 测试工具
- Go `testing` 标准库
- `github.com/stretchr/testify/assert` - 断言
- `github.com/gorilla/websocket` (test server) - WS 测试
- `websocat` (CLI) - E2E 验证
- `dns-sd` (macOS) - Bonjour 验证

### 测试架构

```
bridge/
├── pty.go
├── pty_test.go         # PTY 单元/集成测试
├── server.go
├── server_test.go      # WebSocket 服务测试
├── bridge.go
├── bridge_test.go      # 桥接核心逻辑测试
├── session.go
├── session_test.go     # Session 管理测试
├── mdns.go
├── mdns_test.go        # Bonjour 测试
├── main.go
└── main_test.go        # E2E/集成测试
```

### 运行方式

```bash
# 所有测试
go test ./... -v

# 仅单元测试 (跳过需要外部依赖的测试)
go test ./... -v -short

# 特定包测试
go test ./bridge/... -v -run TestPTY

# E2E 测试 (需要启动 Bridge)
cd bridge && go build -o bridge . && ./bridge &
websocat ws://localhost:9090/ws
```

---

## 总结

- **P0 测试**: 14 个 (必须通过才能发布)
- **P1 测试**: 16 个 (重要功能点)
- **P2 测试**: 7 个 (增强功能)
- **总测试用例**: ~37 个
- **单元测试占比**: ~40%
- **集成测试占比**: ~45%
- **E2E 测试占比**: ~15%

文档结束。
