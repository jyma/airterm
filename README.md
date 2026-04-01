# Herald

远程指挥你的 Claude Code 会话。

Herald 是一个 macOS 菜单栏应用，可以自动发现本机运行的 Claude Code CLI 会话，通过中继服务器将终端内容安全地推送到手机浏览器，让你随时随地监控任务进度、发送指令、确认操作。

## 核心特性

- **自动发现** — 检测 Mac 上所有运行中的 Claude Code CLI 进程
- **无侵入接管** — 通过 macOS Accessibility API 读写终端窗口，无需以特殊方式启动 CLI
- **远程控制** — 手机浏览器即可查看输出、发送指令、点击确认
- **端到端加密** — X25519 密钥交换 + ChaCha20-Poly1305 加密，中继服务器无法读取内容
- **多会话管理** — 同时监控多个 Claude Code 会话，Tab 切换
- **智能解析** — 解析 CLI 输出为结构化视图（diff、工具调用、确认请求）
- **推送通知** — 任务完成或需要确认时推送到手机

## 架构

```
手机浏览器              中继服务器             Mac 菜单栏 App
┌──────────┐  WSS   ┌────────────┐  WSS   ┌──────────────┐
│ Web UI   │◄──────►│  消息转发    │◄──────►│ Accessibility │
│ (React)  │  E2EE  │  (Hono)    │  E2EE  │ API + 进程管理 │
└──────────┘        └────────────┘        └──────────────┘
```

详见 [docs/architecture.md](docs/architecture.md)。

## 项目结构

```
herald/
├── apps/
│   ├── mac/          # macOS 菜单栏应用 (Swift + SwiftUI)
│   ├── server/       # 中继服务器 (TypeScript + Hono)
│   └── web/          # 手机端 Web UI (React + Tailwind)
├── packages/
│   └── crypto/       # 共享加密模块 (TypeScript)
└── docs/             # 文档
```

## 快速开始

### 前置条件

- macOS 14.0+
- Xcode 15+
- Node.js 20+
- pnpm 9+
- 一台有公网 IP 的服务器（用于中继）

### 1. 部署中继服务器

```bash
cd apps/server
pnpm install
cp .env.example .env  # 编辑配置
pnpm build
docker compose up -d
```

### 2. 安装 Mac 应用

```bash
cd apps/mac
open Herald.xcodeproj
# Xcode 中 Build & Run
```

首次启动需授予 **辅助功能权限**（系统设置 → 隐私与安全 → 辅助功能）。

### 3. 手机访问

1. Mac 应用菜单栏点击 Herald 图标
2. 选择「配对新设备」→ 显示二维码
3. 手机扫码 → 自动打开 Web 控制台
4. 完成配对，开始使用

## 技术栈

| 组件 | 技术 |
|------|------|
| Mac 应用 | Swift, SwiftUI, Accessibility API |
| 中继服务器 | TypeScript, Hono, WebSocket |
| Web 前端 | React, Tailwind CSS |
| 加密 | X25519, ChaCha20-Poly1305 |
| 部署 | Docker, Let's Encrypt |

## 文档

- [架构设计](docs/architecture.md)
- [安全方案](docs/security.md)
- [开发指南](docs/development.md)
- [部署指南](docs/deployment.md)
- [通信协议](docs/protocol.md)

## License

MIT
