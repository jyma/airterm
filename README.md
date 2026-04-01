# AirTerm

隔空指挥你的 Claude Code 会话。

AirTerm 是一个 macOS 菜单栏应用，可以自动发现本机运行的 Claude Code CLI 会话，通过中继服务器将终端内容安全地推送到手机浏览器，让你随时随地监控任务进度、发送指令、确认操作。

## 核心特性

- **自动发现** — 检测 Mac 上所有运行中的 Claude Code CLI 进程
- **无侵入接管** — 通过 macOS Accessibility API 读写终端窗口，无需以特殊方式启动 CLI
- **远程控制** — 手机浏览器即可查看输出、发送指令、点击确认
- **零知识架构** — 端到端加密 (X25519 + ChaCha20-Poly1305)，中继服务器无法读取任何内容
- **数据库加密** — SQLCipher (AES-256) 加密存储，密钥托管 macOS Keychain
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
airterm/
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
open AirTerm.xcodeproj
# Xcode 中 Build & Run
```

首次启动需授予 **辅助功能权限**（系统设置 → 隐私与安全 → 辅助功能）。

### 3. 手机访问

1. Mac 应用菜单栏点击 AirTerm 图标
2. 选择「配对新设备」→ 显示二维码
3. 手机扫码 → 自动打开 Web 控制台
4. 完成配对，开始使用

## 技术栈

| 组件       | 技术                              |
| ---------- | --------------------------------- |
| Mac 应用   | Swift, SwiftUI, Accessibility API |
| 中继服务器 | TypeScript, Hono, WebSocket       |
| Web 前端   | React, Tailwind CSS               |
| 加密       | X25519, ChaCha20-Poly1305         |
| 部署       | Docker, Let's Encrypt             |

## 文档

- [产品需求文档](docs/prd.md) — 用户角色、功能需求、MVP 定义、用户流程
- [架构设计](docs/architecture.md) — 系统组件、数据流、生命周期
- [安全方案](docs/security.md) — 六层安全防护体系
- [隐私与数据安全](docs/privacy.md) — 零知识架构、数据库加密、数据生命周期
- [UI 设计规范](docs/ui-design.md) — 色彩体系、组件样式、动画、响应式布局
- [通信协议](docs/protocol.md) — WebSocket 消息格式、错误码
- [开发指南](docs/development.md) — 目录结构、调试、测试
- [部署指南](docs/deployment.md) — Docker、HTTPS、监控

## License

MIT
