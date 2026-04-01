# 开发指南

## 环境准备

### 必需工具

```bash
# Xcode (Mac App 开发)
xcode-select --install

# Node.js 20+ (服务器 + Web 前端)
brew install node

# pnpm (包管理)
npm install -g pnpm

# 可选: 本地开发时模拟公网
brew install cloudflared
```

### 克隆与安装

```bash
git clone https://github.com/your-org/herald.git
cd herald
pnpm install
```

## 项目结构详解

```
herald/
├── apps/
│   ├── mac/                    # macOS 菜单栏应用
│   │   └── Herald/
│   │       ├── HeraldApp.swift           # 应用入口
│   │       ├── MenuBar/
│   │       │   ├── MenuBarView.swift     # 菜单栏 UI
│   │       │   └── PanelView.swift       # 展开面板 UI
│   │       ├── Session/
│   │       │   ├── ProcessMonitor.swift  # 进程发现
│   │       │   ├── WindowMapper.swift    # 进程→窗口映射
│   │       │   ├── TerminalReader.swift  # 终端内容读取
│   │       │   └── OutputParser.swift    # 输出解析
│   │       ├── Network/
│   │       │   ├── RelayClient.swift     # WebSocket 客户端
│   │       │   └── PairManager.swift     # 配对管理
│   │       ├── Crypto/
│   │       │   └── E2ECrypto.swift       # 端到端加密
│   │       ├── Security/
│   │       │   ├── CommandFilter.swift   # 危险命令过滤
│   │       │   └── AuditLog.swift        # 操作日志
│   │       └── Input/
│   │           └── InputHandler.swift    # 远程输入处理
│   │
│   ├── server/                 # 中继服务器
│   │   ├── src/
│   │   │   ├── index.ts              # 入口
│   │   │   ├── ws/
│   │   │   │   ├── handler.ts        # WebSocket 连接管理
│   │   │   │   └── relay.ts          # 消息转发逻辑
│   │   │   ├── api/
│   │   │   │   ├── pair.ts           # 配对 API
│   │   │   │   └── devices.ts        # 设备管理 API
│   │   │   ├── auth/
│   │   │   │   └── jwt.ts            # JWT 签发与验证
│   │   │   └── store/
│   │   │       └── device-store.ts   # 设备存储 (SQLite)
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   ├── Dockerfile
│   │   └── docker-compose.yml
│   │
│   └── web/                    # 手机端 Web UI
│       ├── src/
│       │   ├── App.tsx
│       │   ├── pages/
│       │   │   ├── SessionList.tsx    # 会话列表
│       │   │   └── SessionView.tsx    # 会话详情
│       │   ├── components/
│       │   │   ├── ChatBubble.tsx     # 消息气泡
│       │   │   ├── DiffViewer.tsx     # 代码差异
│       │   │   ├── ToolCard.tsx       # 工具调用卡片
│       │   │   ├── ApprovalBar.tsx    # 确认操作栏
│       │   │   └── QuickPanel.tsx     # 快捷指令面板
│       │   ├── hooks/
│       │   │   ├── useWebSocket.ts    # WebSocket 连接
│       │   │   └── useCrypto.ts       # 端到端加密
│       │   └── crypto/
│       │       └── e2e.ts            # 加密/解密实现
│       ├── package.json
│       └── vite.config.ts
│
├── packages/
│   └── crypto/                 # 共享加密模块
│       ├── src/
│       │   ├── index.ts
│       │   ├── x25519.ts            # 密钥交换
│       │   └── chacha20.ts          # 加密/解密
│       ├── package.json
│       └── tsconfig.json
│
├── docs/
├── package.json                # workspace root
├── pnpm-workspace.yaml
└── .gitignore
```

## 开发流程

### 1. Mac App 开发

```bash
cd apps/mac
open Herald.xcodeproj

# Xcode 中:
# - 选择 Herald scheme
# - 选择 My Mac 作为目标
# - Cmd+R 运行
```

首次运行需要在系统设置中授予辅助功能权限。

调试技巧：

```swift
// 在 ProcessMonitor 中查看发现的进程
ProcessMonitor.shared.sessions.forEach { session in
    print("Found: \(session.pid) at \(session.cwd)")
}

// 在 TerminalReader 中查看读取到的内容
let content = TerminalReader.readContent(from: windowElement)
print("Terminal content: \(content)")
```

### 2. 中继服务器开发

```bash
cd apps/server

# 安装依赖
pnpm install

# 开发模式 (热重载)
pnpm dev

# 服务器默认运行在 http://localhost:3000
```

本地开发时，用 cloudflared 暴露到公网方便手机测试：

```bash
cloudflared tunnel --url http://localhost:3000
# 会生成一个临时公网 URL
```

### 3. Web 前端开发

```bash
cd apps/web

pnpm install
pnpm dev

# 开发服务器运行在 http://localhost:5173
# 手机和电脑在同一网络时可直接访问
```

### 4. 共享加密模块

```bash
cd packages/crypto

pnpm install
pnpm test    # 运行加密/解密单元测试
pnpm build   # 构建供其他包引用
```

## 测试

### 单元测试

```bash
# 服务器
cd apps/server && pnpm test

# Web 前端
cd apps/web && pnpm test

# 加密模块
cd packages/crypto && pnpm test
```

### 集成测试

```bash
# 启动服务器 + Web，模拟完整通信流程
pnpm test:integration
```

### Mac App 测试

在 Xcode 中运行 Test Navigator (Cmd+6)。

重点测试：
- ProcessMonitor: 能否正确发现 claude 进程
- OutputParser: 各种输出格式的解析
- CommandFilter: 危险命令识别
- E2ECrypto: 加密/解密正确性

## 常见问题

### 辅助功能权限

Mac App 需要辅助功能权限才能读写终端窗口。如果权限被拒绝：

```
系统设置 → 隐私与安全性 → 辅助功能 → 添加 Herald
```

开发时每次重新编译可能需要重新授权。

### 进程发现找不到 claude

确认 `claude` 命令在 PATH 中：

```bash
which claude
# 应该输出路径，如 /usr/local/bin/claude
```

ProcessMonitor 通过进程名匹配，确保搜索的进程名正确。
