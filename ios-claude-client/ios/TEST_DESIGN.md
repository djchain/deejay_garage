# iOS App - Phase 2 & 3 测试设计文档

## 概述

iOS SwiftUI 原生 App，通过 WebSocket 连接 Go Bridge 来远程操作 Claude Code。

## 架构

```
ClaudeRemote/
├── ClaudeRemoteApp.swift
├── Models/
│   ├── Message.swift
│   └── SessionInfo.swift
├── Services/
│   ├── ConnectionManager.swift
│   ├── BonjourDiscovery.swift
│   └── SessionStore.swift
├── Views/
│   ├── ContentView.swift
│   ├── TerminalTabView.swift
│   ├── SessionListView.swift
│   └── SettingsView.swift
└── ViewModels/
    └── TerminalViewModel.swift
```

## 测试场景

### 1. 消息模型 (`Message.swift`) — 单元测试

| # | 场景 | 输入 | 预期 | 优先级 |
|---|------|------|------|--------|
| M1 | InputMessage 编码 | InputMessage(data: "ls\n") | JSON: {"type":"input","data":"ls\n"} | P0 |
| M2 | OutputMessage 解码 | {"type":"output","data":"hello"} | OutputMessage(data: "hello") | P0 |
| M3 | SignalMessage INT | SignalMessage(name: "int") | JSON: {"type":"signal","name":"int"} | P0 |
| M4 | ResizeMessage 编码 | ResizeMessage(cols: 80, rows: 24) | JSON 包含 cols:80, rows:24 | P0 |
| M5 | PingMessage 编解码 | 空消息 | type 为 "ping" | P1 |
| M6 | 非法 JSON 解码 | {"type":"unknown"} | 返回 nil 或抛错 | P1 |

### 2. ConnectionManager (`ConnectionManager.swift`) — 集成测试

| # | 场景 | 输入 | 预期 | 优先级 |
|---|------|------|------|--------|
| C1 | 成功连接 | ws://localhost:9090/ws | 状态变为 .connected | P0 |
| C2 | 发送 input 消息 | send(.input("ls\n")) | 消息通过 WS 发送 | P0 |
| C3 | 接收 output 消息 | 服务器发送 output | onReceive 回调被调用 | P0 |
| C4 | 连接失败处理 | ws://invalid:9999 | 状态为 .disconnected, 触发重连 | P0 |
| C5 | 自动重连 | 断开连接 | 指数退避重连 (1s→2s→4s→30s) | P0 |
| C6 | 心跳保活 | 连接空闲 | 周期性发送 ping | P1 |
| C7 | 手动断开 | disconnect() | 停止重连, 状态变为 .disconnected | P1 |
| C8 | 发送 resize 消息 | send(.resize(cols:80, rows:24)) | 服务器收到 resize | P1 |
| C9 | 发送 signal 消息 | send(.signal("int")) | 服务器收到 SIGINT | P1 |
| C10 | 网络恢复重连 | NWPathMonitor 检测网络恢复 | 自动触发重连 | P2 |

### 3. Bonjour 发现 (`BonjourDiscovery.swift`) — 集成测试

| # | 场景 | 输入 | 预期 | 优先级 |
|---|------|------|------|--------|
| D1 | 开始浏览 | startBrowsing() | NSNetServiceBrowser 启动 | P0 |
| D2 | 发现服务 | _claudebridge._tcp 存在 | 解析出 host:port | P0 |
| D3 | 停止浏览 | stopBrowsing() | browser 停止 | P1 |
| D4 | 解析超时 | 服务不可解析 | 超时处理, 不崩溃 | P1 |

### 4. 终端视图 (`TerminalTabView.swift`) — UI 测试

| # | 场景 | 输入 | 预期 | 优先级 |
|---|------|------|------|--------|
| T1 | 键盘输入转发 | 用户键入文字 | 文字发送到 ConnectionManager | P0 |
| T2 | ANSI 输出渲染 | 收到 output 消息 | SwiftTerm 渲染 ANSI | P0 |
| T3 | Ctrl-C 按钮 | 点击 Ctrl-C 快捷按钮 | 发送 signal("int") | P0 |
| T4 | 粘贴功能 | 粘贴剪贴板内容 | 文本发送到连接 | P1 |
| T5 | 终端 resize | 旋转屏幕/分屏 | 发送 resize 消息 | P1 |
| T6 | 深色/浅色模式 | 切换外观 | 终端主题跟随 | P2 |

### 5. Session 管理 (`SessionStore.swift`) — 单元测试

| # | 场景 | 输入 | 预期 | 优先级 |
|---|------|------|------|--------|
| S1 | 保存连接信息 | 保存 {host, port, name} | UserDefaults 持久化 | P0 |
| S2 | 列出历史 | 多个 session | 按最近使用排序 | P1 |
| S3 | 删除 session | 删除一个 | 列表更新 | P1 |

### 6. E2E 场景

| # | 场景 | 步骤 | 预期 | 优先级 |
|---|------|------|------|--------|
| E1 | 完整连接流程 | 1) 启动 Bridge<br>2) 输入 URL<br>3) 连接 | 终端显示输出 | P0 |
| E2 | Bonjour 自动发现 | 1) 启动 Bridge<br>2) 打开 App | 自动发现服务, 一键连接 | P0 |
| E3 | 断连重连 | 1) 连接<br>2) 杀掉 Bridge<br>3) 重启 Bridge | 自动重连成功 | P1 |

## 测试工具

- **XCTest**: 单元 + UI 测试
- **SwiftTerm**: ANSI 终端渲染 (https://github.com/migueldeicaza/SwiftTerm)
- **URLSessionWebSocketTask**: 原生 WebSocket (iOS 13+)
- **NWPathMonitor**: 网络变化监听
- **NSNetServiceBrowser**: Bonjour 发现

## 总结

| 优先级 | 数量 |
|--------|------|
| P0 | 15 |
| P1 | 11 |
| P2 | 3 |
| **总计** | **~29** |
