# iOS Claude Remote — 安装指南

## 概述

iOS SwiftUI 原生 App + Mac Go Bridge，通过 WebSocket 远程操作 Claude Code。

```
iOS App (SwiftUI + SwiftTerm) ←WebSocket→ Go Bridge ←PTY→ Claude Code (tmux)
```

---

## 第一部分：Mac Bridge 安装

### 前置条件

```bash
# 确保安装了以下工具
which go      # Go 1.21+
which tmux    # tmux (macOS 自带)
which claude  # Claude Code CLI
```

### 编译 & 启动

```bash
# 1. 进入 bridge 目录
cd /Users/deejay/codes/ios-claude-client/bridge

# 2. 编译
go build -o bridge .

# 3. 启动 (默认端口 9090, session 名 claude-code)
./bridge -port :9090 -session claude-code

# 自定义端口:
./bridge -port :8080 -session my-project
```

启动后日志输出：
```
Starting Claude Code Bridge...
Session: claude-code
Port: :9090
mDNS service registered
Server listening on :9090/ws
```

### 自动启动 (可选)

创建 LaunchAgent 实现开机自启：

```bash
# 编辑 ~/Library/LaunchAgents/com.clauderemote.bridge.plist
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.clauderemote.bridge</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/deejay/codes/ios-claude-client/bridge/bridge</string>
        <string>-port</string>
        <string>:9090</string>
        <string>-session</string>
        <string>claude-code</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>/Users/deejay/codes/ios-claude-client/bridge</string>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.clauderemote.bridge.plist
```

### 验证 Bridge

```bash
# 安装 websocat
brew install websocat

# 连接测试
websocat ws://localhost:9090/ws

# 输入 {"type":"input","data":"ls\n"} 应该收到 PTY 回显
```

---

## 第二部分：iOS App 安装（免费侧载，无需开发者账号）

> **无需付费开发者账号** — 免费 Apple ID 即可。

### 选哪个？

| | AltStore | SideStore |
|------|----------|-----------|
| 签名刷新方式 | iPhone ↔ Mac (mDNS) | iPhone 直接连 Apple 服务器 |
| Mac 需要在线 | ✅ 需要（同一 WiFi） | ❌ 不需要 |
| 跨网络使用 | ❌ Tailscale 无效 | ✅ 蜂窝/WiFi/Tailscale 均可 |
| 初始安装 | USB 连接 Mac 一次 | 需先装 AltServer 装一次 SideStore |
| 推荐场景 | Mac 长期在家 | 移动办公、纯 Tailscale 环境 |

**推荐**：先用 AltServer 装 SideStore，后续完全脱离 Mac。

---

### 方案 A：SideStore（推荐 — 跨网络自动续签）

#### A1. 一次性预装

Mac 上：
1. 下载 [AltServer](https://altstore.io) → 安装到 /Applications
2. 启动 AltServer（菜单栏出现菱形图标）

iPhone 上：
1. USB 线连接 iPhone 到 Mac
2. 打开 [sidestore.io](https://sidestore.io) → 下载 SideStore.ipa 到 Mac
3. 菜单栏 AltServer → Install AltStore → 选你的 iPhone，但**按住 Option 键点击** → 选择刚下载的 SideStore.ipa
4. 输入 Apple ID 和密码
5. iPhone 上出现 SideStore 图标
6. 设置 → 通用 → VPN 与设备管理 → 信任

> 至此 Mac 的任务完成，后续不再需要 Mac。

#### A2. SideStore 初始配置

在 iPhone 上打开 SideStore：
1. 用同一 Apple ID 登录
2. 设置 → 开启 "Use WireGuard"（可选，增强跨网络能力）
3. 等 30 秒完成首次签名

#### A3. 构建 IPA（在 Mac 上一次）

```bash
cd /Users/deejay/codes/ios-claude-client/ios

# 生成 Xcode 项目（只需一次）
python3 gen-xcode.py

# 首次必须在 Xcode 中打开项目以创建 scheme:
open ClaudeRemote.xcodeproj
# → 选择 target: ClaudeRemote
# → Signing & Capabilities → Team → 选你的 Apple ID
# → 关闭 Xcode

# 构建 .ipa:
./build-for-altstore.sh
```

构建成功后 `.ipa` 在 `./build/ClaudeRemote.ipa`

#### A4. 安装到 iPhone

1. 把 `.ipa` 传到 iPhone（AirDrop 最方便）
2. iPhone → 文件 App → `ClaudeRemote.ipa`
3. 点击 → 分享 → **SideStore**
4. SideStore 自动重签并安装（~30 秒）
5. 首次打开：设置 → 通用 → VPN 与设备管理 → 信任

#### A5. 续签

- SideStore **在手机上自主刷新签名**，不需要 Mac 在线
- Tailscale / 蜂窝网络 / 任意 WiFi 均可
- 证书到期前 24 小时自动续签
- 或手动：SideStore → My Apps → Refresh All

---

### 方案 B：AltStore（Mac 长期在家场景）

> ⚠️ **限制**：签名刷新依赖 iPhone 和 Mac 在同一 WiFi 下的 Bonjour/mDNS。
> **Tailscale 不转发 mDNS**，所以证书 7 天后会过期，只能手动 USB 续签。

#### B1. 安装 AltServer + AltStore

**Mac 端**：
1. 下载 [AltServer](https://altstore.io) → 安装到 /Applications
2. 启动 AltServer（菜单栏出现菱形图标）

**iPhone 端**：
1. USB 线连接 iPhone 到 Mac
2. 菜单栏 AltServer → Install AltStore → 选择你的 iPhone
3. 输入你的 Apple ID 和密码（仅用于签名，不会上传）
4. iPhone 上出现 AltStore 图标
5. 设置 → 通用 → VPN 与设备管理 → 信任

#### B2. 构建 IPA

同方案 A3。

#### B3. 安装到 iPhone

同方案 A4，把 ".ipa → 分享 → SideStore" 换成 **".ipa → 分享 → AltStore"**。

#### B4. 续签

- Mac 和 iPhone **必须在同一 WiFi**（Bonjour/mDNS）
- 自动后台续签，证书 7 天
- 若过期：USB 连接 Mac → AltStore → Refresh All

### 首次使用

1. 确保 Mac Bridge 已启动 (`./bridge -port :9090`)
2. 打开 iPhone 上的 Claude Remote
3. **方式 A — Bonjour 自动发现**:
   - App 自动搜索局域网内的 Bridge
   - 在终端页的"Discovered Services"中点击 Bridge
4. **方式 B — 手动连接**:
   - 输入 Mac 的局域网 IP 和端口 (如 `192.168.1.100:9090`)
   - 点击 Connect
5. 连接成功后看到 Claude Code 终端输出

### 网络要求

- iPhone 和 Mac 必须在**同一局域网** (WiFi)
- Mac 防火墙需要允许端口 9090 的入站连接:
  系统设置 → 网络 → 防火墙 → 选项 → 允许 `/bridge` 二进制

### 防火墙配置 (如遇连接问题)

```bash
# 临时允许 (开发调试用)
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /Users/deejay/codes/ios-claude-client/bridge/bridge
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /Users/deejay/codes/ios-claude-client/bridge/bridge
```

---

## 第三部分：架构概览

```
┌─────────────────────┐
│  iOS App (SwiftUI)  │
│  ┌─────────────────┐│
│  │ TerminalTabView ││  ← SwiftTerm ANSI 渲染
│  │ ┌─────────────┐ ││
│  │ │ SwiftTerm    │ ││  ← UIViewRepresentable
│  │ │ (UIKit)      │ ││
│  │ └─────────────┘ ││
│  │ [Ctrl-C] [Esc]  ││  ← 键盘 accessory
│  │ [▲] [▼] [Tab]   ││
│  ├─────────────────┤│
│  │ ConnectionManager││  ← URLSessionWebSocketTask
│  │ BonjourDiscovery ││  ← NSNetServiceBrowser
│  │ SessionStore     ││  ← UserDefaults
│  └─────────────────┘│
└─────────┬───────────┘
          │ WebSocket (ws://mac-ip:9090/ws)
          │ JSON messages
┌─────────▼───────────┐
│  Go Bridge (Mac)    │
│  ┌─────────────────┐│
│  │ server.go       ││  ← gorilla/websocket
│  │ types.go        ││  ← JSON 消息协议
│  ├─────────────────┤│
│  │ bridge.go       ││  ← WS ↔ PTY 双向桥接
│  │ pty.go          ││  ← creack/pty
│  │ session.go      ││  ← Session CRUD
│  │ mdns.go         ││  ← Bonjour 广播
│  └─────────────────┘│
└─────────┬───────────┘
          │ PTY (pseudo-terminal)
┌─────────▼───────────┐
│  tmux session       │
│  ┌─────────────────┐│
│  │ Claude Code CLI ││
│  └─────────────────┘│
└─────────────────────┘
```

### 消息协议

```json
// iOS → Bridge
{"type":"input","data":"ls\n"}
{"type":"signal","name":"int"}        // Ctrl-C
{"type":"signal","name":"eof"}        // Ctrl-D
{"type":"resize","cols":80,"rows":24}
{"type":"ping"}

// Bridge → iOS  
{"type":"output","data":"<ANSI escaped text>"}
```

---

## 第四部分：项目结构

```
/Users/deejay/codes/ios-claude-client/
├── bridge/                          # Go Bridge (Mac 端)
│   ├── main.go                      # 程序入口 + CLI 参数
│   ├── types.go                     # JSON 消息协议定义
│   ├── server.go                    # WebSocket HTTP 服务器
│   ├── bridge.go                    # WS ↔ PTY 桥接状态机
│   ├── pty.go                       # PTY/tmux 管理
│   ├── session.go                   # Session CRUD + 持久化
│   ├── mdns.go                      # Bonjour/mDNS 注册
│   ├── go.mod / go.sum
│   ├── bridge                       # 编译产物 (二进制)
│   ├── TEST_DESIGN.md               # 测试设计文档
│   ├── *_test.go                    # 49 个测试用例
│   └── *_test.go                    # 
└── ios/                             # iOS App
    ├── Package.swift                # SPM 清单
    ├── TEST_DESIGN.md               # 测试设计文档
    ├── ClaudeRemote/
    │   ├── ClaudeRemoteApp.swift    # @main App 入口
    │   ├── Models/
    │   │   ├── Message.swift        # 消息编解码
    │   │   └── SessionInfo.swift    # Session 数据模型
    │   ├── Services/
    │   │   ├── ConnectionManager.swift   # WS + 重连 + 心跳
    │   │   ├── BonjourDiscovery.swift    # mDNS 发现
    │   │   └── SessionStore.swift        # UserDefaults 持久化
    │   ├── ViewModels/
    │   │   └── TerminalViewModel.swift   # 状态协调
    │   └── Views/
    │       ├── ContentView.swift         # TabView
    │       ├── TerminalTabView.swift     # 终端主界面
    │       ├── SessionListView.swift     # 历史列表
    │       └── SettingsView.swift        # 设置页
    └── Tests/
        └── ClaudeRemoteTests.swift  # 12 个单元测试
```

---

## 测试

### Go Bridge 测试

```bash
cd /Users/deejay/codes/ios-claude-client/bridge

# 单元测试 (快速)
go test ./... -v -short

# 含竞态检测
go test ./... -short -race

# 全部测试 (含集成/E2E, 需要 tmux)
go test ./... -v
```

当前结果: **25 PASS, 24 SKIP (集成测试需 tmux), 0 FAIL, race clean**

### iOS 测试

在 Xcode 中: Product → Test (Cmd+U)

测试覆盖: 消息编解码、SessionStore CRUD、连接状态转换、Bonjour 生命周期

---

## 常见问题

**Q: iOS 连接不上 Bridge**
- 确认 iPhone 和 Mac 在同一 WiFi
- 检查 Mac 防火墙 (系统设置 → 网络 → 防火墙)
- 用 `websocat ws://localhost:9090/ws` 确认 Bridge 正常运行

**Q: 终端渲染异常**
- SwiftTerm 覆盖了 95% ANSI 序列
- 少数特殊字符可能渲染不正确，属于已知限制

**Q: App 进入后台断连**
- 设计如此: 断连后 tmux session 继续运行
- App 回到前台自动重连并 attach

**Q: 如何更新 Bridge 端口**
- 启动参数: `./bridge -port :8080`
- iOS 端手动输入新地址即可
