# AirTerm 实现规划

## 项目状态

- 架构文档：完整（8 份文档，~2800 行）
- UI 设计：完整（20 页 Pencil 设计稿，浅色/深色双主题）
- 源代码：零（全部从零开始）
- 安全审计：已完成，发现 2 CRITICAL + 5 HIGH 级别问题

---

## MVP 策略

**核心功能验证优先，加密后补，LAN 留到原生壳阶段。**

- MVP 阶段手机端为 Web（非原生 App），全走 WAN 公共中继
- LAN 直连受 Mixed Content 限制（https 页面无法连 ws://），留到原生壳阶段
- 先跑通核心链路（Mac 读终端 → 服务器转发 → 手机展示 → 手机操控），再补 E2EE
- 加密模块（Phase 0）推迟到核心链路验证完成后

## 阶段总览

```
MVP 核心验证:
  Phase 1 (服务器) ──┐
                      ├─→ Phase 3 (集成联调)
  Phase 2 (Web)  ────┘         ↑
                               │
  Phase 3A (Mac 子进程) ────────┘
  Phase 3B (Mac AX API) ───────┘

核心验证完成后:
  Phase 4 (加密模块 E2EE)
  Phase 5 (Mac AX API 完善)

原生壳阶段 (后续):
  Phase 6 (原生移动壳 + LAN 直连 + 推送通知)
```

Phase 1 和 Phase 2 可并行推进（用 mock 数据），Phase 3A 依赖更少可先完成。

---

## Phase 0: 项目初始化

**复杂度: 低 | 依赖: 无 | 预估: 1 天**

> 注：加密模块（E2EE）推迟到 Phase 4，MVP 核心验证阶段先用明文 WebSocket 跑通链路。

### 0.1 项目初始化

- `pnpm install` 初始化 monorepo
- 配置 ESLint、Prettier
- 配置 vitest 全局设置

### 0.2 消息协议定义 (`packages/protocol`)

定义 Mac ↔ 服务器 ↔ 手机之间的明文消息格式（E2EE 后续叠加，不影响协议结构）：

```
packages/protocol/src/
├── messages.ts       # 消息类型定义（sessions, output, input, approval, shortcut 等）
├── envelope.ts       # 信封格式（type, from, to, ts, payload）
└── index.ts          # 统一导出
```

### ~~0.3 加密模块~~ (推迟到 Phase 4)

> 加密模块完整设计保留，在核心链路验证后实现。详见 Phase 4。

---

## Phase 1: 中继服务器 (`apps/server`)

**复杂度: 中 | 依赖: Phase 0 | 预估: 3-5 天**

> MVP 简化：先用简单 token 认证 + SQLite（非 SQLCipher），E2EE / JWT 短期化 / 数据库加密在 Phase 4 补齐。

### 1.1 HTTP 框架

```
apps/server/src/
├── index.ts              # 入口，Hono app 挂载
├── config.ts             # 环境变量加载
├── routes/
│   ├── health.ts         # GET /health
│   └── pair.ts           # POST /api/pair/init, POST /api/pair/complete
├── ws/
│   ├── manager.ts        # WebSocket 连接管理器
│   ├── relay.ts          # 消息转发逻辑
│   └── heartbeat.ts      # 心跳检测
├── auth/
│   └── token.ts          # 简单 token 签发/验证（MVP，后续升级为 JWT）
├── db/
│   ├── init.ts           # SQLite 初始化（MVP，后续升级为 SQLCipher）
│   ├── devices.ts        # 设备 CRUD
│   └── pairs.ts          # 配对关系 CRUD
└── utils/
    └── pair-code.ts      # 配对码生成
```

### 1.2 WebSocket 消息转发

- 连接建立时验证 token + 检查配对关系
- 纯转发模式：收到消息原样转发给对端
- 心跳检测：30 秒间隔，3 次未响应断开

### 1.3 配对服务（MVP 简化版）

```
配对流程：
1. Mac → POST /api/pair/init → 返回 pair_code + pair_id
2. Mac 生成二维码: { server, pair_code, mac_device_id }
3. Phone 扫码 → POST /api/pair/complete { pair_code, phone_device_id }
4. Server 验证 pair_code → 绑定设备 → 返回 { token, mac_device_id }
5. Server 通知 Mac 配对成功 → 返回 { phone_device_id }
6. 双方建立 WebSocket 连接，开始通信
```

> E2EE 密钥交换、SAS 安全码验证在 Phase 4 加入。

### 1.4 部署

- 公共实例 `relay.airterm.dev` 部署
- Docker 多阶段构建
- 健康检查 `/health`

### 1.5 测试

- 单元测试: token 签发/验证、配对码生成/校验
- 集成测试: 配对流程、WebSocket 连接/转发/断线重连
- **覆盖率目标: >80%**

---

## Phase 2: Web 前端 (`apps/web`)

**复杂度: 中 | 依赖: Phase 1 | 预估: 7-10 天**

> MVP 简化：不集成 E2EE 加密层，WebSocket 直接收发明文 JSON。加密层在 Phase 4 叠加。

### 2.1 项目搭建

```
apps/web/src/
├── main.tsx
├── App.tsx
├── pages/
│   ├── PairPage.tsx          # 扫码配对
│   ├── SessionsPage.tsx      # tmux 分屏多会话
│   ├── SessionDetailPage.tsx # 单会话全屏终端
│   └── SettingsPage.tsx      # 设置
├── components/
│   ├── terminal/
│   │   ├── TerminalPane.tsx  # 终端面板（原生 CLI 风格渲染）
│   │   ├── PaneHeader.tsx    # 面板标题栏（状态点+会话名+路径）
│   │   ├── TmuxLayout.tsx    # tmux 分屏布局管理器
│   │   └── DiffBlock.tsx     # diff 高亮块
│   ├── approval/
│   │   └── ApprovalBar.tsx   # 确认操作栏 (Deny/Allow)
│   ├── shortcuts/
│   │   └── QuickPanel.tsx    # 快捷指令面板
│   └── ui/
│       ├── TopBar.tsx        # 顶栏
│       └── ThemeToggle.tsx   # 主题切换
├── hooks/
│   ├── useWebSocket.ts       # WebSocket 连接管理
│   ├── useCrypto.ts          # 加解密 hook
│   └── useSessions.ts        # 会话状态管理
├── lib/
│   ├── ws-client.ts          # WebSocket 客户端 + 自动重连
│   ├── crypto-layer.ts       # E2E 加密层（调用 @airterm/crypto）
│   ├── key-store.ts          # IndexedDB 密钥存储（non-extractable）
│   └── theme.ts              # 浅色/深色主题系统
└── styles/
    └── globals.css           # Tailwind + CSS 变量（设计稿色板）
```

**安全修复集成：**

| 修复项 | 实现位置 | 说明 |
|--------|----------|------|
| ★ 独立部署 | 部署配置 | 前端部署到 Cloudflare Pages / Vercel，**不在中继服务器上托管** |
| 前端代码验证 | `PairPage.tsx` | 扫码时校验二维码中的 `frontend_hash` 与当前加载的 JS 哈希一致 |
| SAS 验证 | `PairPage.tsx` | 配对完成后显示 4 位安全码，要求用户与 Mac 屏幕核对 |
| 序列号验证 | `lib/crypto-layer.ts` | 接收消息时检查序列号递增，拒绝重放 |
| CSP 严格化 | `index.html` / 服务器头 | `script-src 'self'; style-src 'self' 'unsafe-inline'; object-src 'none'` |
| SRI | 构建输出 | 所有 JS/CSS 资源带 integrity 属性 |

### 2.2 核心页面

**tmux 分屏视图 (SessionsPage)**
- 垂直分割面板（手机 2-3 个，平板可更多）
- 每个面板: PaneHeader + TerminalPane
- 点击面板标题可展开为全屏

**终端渲染 (TerminalPane)**
- CLI 原生风格: `╭─ Claude` / `► Bash` / `► Edit`
- diff 块用圆角深色/浅色背景 + 红绿色文字
- 确认请求自动弹出 ApprovalBar
- 等宽字体 Geist Mono

**设置页 (SettingsPage)**
- iOS 分组风格
- 主题切换（系统/浅色/深色）
- 已配对设备管理（查看/撤销）
- 安全选项（高危命令确认/操作日志/自动锁定）

### 2.3 浅色/深色主题

```css
:root {
  /* 浅色 (Apple Light) */
  --bg-primary: #F5F5F7;
  --bg-card: #FFFFFF;
  --bg-terminal: #FAFAFA;
  --text-primary: #1D1D1F;
  --text-secondary: #86868B;
  --accent: #0A84FF;
  --green: #30D158;
  --red: #FF453A;
  --yellow: #FF9F0A;
}

[data-theme="dark"] {
  /* 深色 (Apple Dark) */
  --bg-primary: #1C1C1E;
  --bg-card: #2C2C2E;
  --bg-terminal: #000000;
  --text-primary: #FFFFFF;
  --text-secondary: #98989D;
  --accent: #0A84FF;
  --green: #30D158;
  --red: #FF453A;
  --yellow: #FFD60A;
}
```

### 2.4 测试

- 组件测试: TerminalPane 渲染、ApprovalBar 交互、TmuxLayout 分屏
- Hook 测试: useWebSocket 连接/重连、useCrypto 加解密
- E2E 测试: 配对流程、消息收发
- **覆盖率目标: >80%**

---

## Phase 3: Mac 菜单栏应用 (`apps/mac`)

**复杂度: 高 | 依赖: Phase 0 + Phase 1 | 预估: 15-20 天**

Phase 3 拆分为两个并行阶段：**3A（子进程模式）** 和 **3B（AX API 模式）**。两种模式同等重要，但 3A 依赖更少可先完成，更早出可联调的 demo。3B 可随后跟进或并行开发。

### 3.1 项目结构

```
apps/mac/AirTerm/
├── AirTermApp.swift               # 入口
├── AppDelegate.swift              # 菜单栏 + 生命周期
├── Views/
│   ├── Onboarding/
│   │   └── OnboardingView.swift   # 首次启动引导（配对，不强制 AX 权限）
│   ├── MenuBar/
│   │   └── MenuBarView.swift      # 菜单栏下拉面板
│   ├── Main/
│   │   ├── MainWindow.swift       # 主窗口
│   │   ├── SidebarView.swift      # 侧栏（可折叠）
│   │   ├── TmuxView.swift         # tmux 分屏管理
│   │   ├── TerminalPaneView.swift # 单个终端面板
│   │   └── PaneHeaderView.swift   # 面板标题栏
│   ├── Settings/
│   │   └── SettingsView.swift     # 设置偏好窗口
│   └── Pairing/
│       ├── PairingView.swift      # 配对窗口（二维码+SAS验证码）
│       └── QRCodeGenerator.swift  # 二维码生成
├── Agent/
│   ├── AgentAdapter.swift         # ★ 统一协议: send(input), onEvent(callback)
│   ├── SubprocessAdapter.swift    # ★ 子进程模式: pty + stream-json
│   └── AccessibilityAdapter.swift # ★ AX API 模式: 进程监控+终端读取+输出解析
├── Services/
│   ├── TerminalEmulator.swift     # 内置终端（pty + Process）
│   ├── StreamParser.swift         # ★ 解析 --input-format stream-json
│   ├── ProcessMonitor.swift       # claude 进程扫描（AX 模式用）
│   ├── WindowMapper.swift         # PID → 终端窗口映射（AX 模式用）
│   ├── TerminalReader.swift       # AX API 读取终端文本（AX 模式用）
│   ├── OutputParser.swift         # 终端文本 → 结构化事件（AX 模式用）
│   ├── InputHandler.swift         # 远程指令写入终端
│   └── RelayClient.swift         # WebSocket + E2E 加密
├── Crypto/
│   ├── CryptoKit+X25519.swift    # 密钥交换
│   ├── ChaCha20Poly1305.swift    # 加解密
│   ├── KeychainManager.swift     # Keychain 存取
│   └── SASGenerator.swift        # SAS 安全码生成
├── Models/
│   ├── Session.swift              # 会话模型
│   ├── TerminalEvent.swift        # 终端事件类型
│   └── PairInfo.swift             # 配对信息
└── Utils/
    ├── BundleIDValidator.swift    # ★ 终端应用白名单验证（AX 模式用）
    └── DangerousCommandFilter.swift # 危险命令拦截
```

### 3A: 子进程模式（预估 8-10 天）

子进程模式不需要辅助功能权限，依赖更少，可更早完成联调。

**Step 1: 骨架 + 引导 (2 天)**
- SwiftUI 菜单栏应用骨架
- 首次启动引导: 直接进入配对流程（不强制 AX 权限）
- 设置偏好窗口（含服务器地址高级选项，默认 `relay.airterm.dev`）

**Step 2: AgentAdapter 协议 + 内置终端 (3 天)**

```swift
// AgentAdapter.swift — 统一接口，不绑定特定 CLI
protocol AgentAdapter {
    var sessions: [Session] { get }
    func createSession(cwd: URL?) -> Session
    func send(input: String, to session: Session)
    func onEvent(_ handler: @escaping (Session, TerminalEvent) -> Void)
}
```

- TerminalEmulator: pty + Process，完整终端体验
- SubprocessAdapter: 实现 AgentAdapter，管理 pty 会话
- 用户在终端面板中输入任意命令，体验与 iTerm2 一致

**Step 3: StreamParser + 结构化事件 (2 天)**
- 检测用户启动了 `claude` CLI
- 通过 `--input-format stream-json` 获取结构化 JSON 事件流
- 解析事件类型: message、diff、tool_call、approval、completion
- 将结构化事件通过 AgentAdapter.onEvent 推送

**Step 4: tmux 窗口管理 (3 天)**
- TmuxView: 多面板分屏管理
- 拖拽分割线调整面板大小
- 侧栏展开/折叠
- Tab 标签页切换

**Step 5: 网络通信 + 配对 (3 天)**
- RelayClient: URLSessionWebSocketTask + E2E 加密
- 默认连接 `relay.airterm.dev`
- 二维码生成 + SAS 安全码验证
- InputHandler: 远程指令通过 pty 直接写入（无需 CGEvent）
- Keychain 集成

### 3B: Accessibility 模式（预估 5-7 天）

可在 3A 完成后顺序开发，或与 3A 并行推进。

**Step 6: AccessibilityAdapter (3 天)**
- 实现 AgentAdapter 协议
- ProcessMonitor: 扫描外部终端中的 `claude` 进程
- WindowMapper: PID → AXUIElement
- TerminalReader: AX API 读取 + 变化检测
- OutputParser: 正则 + 状态机解析终端文本
- ★ BundleIDValidator: 白名单验证

**Step 7: AX 权限引导 + 集成 (2 天)**
- 首次启动引导中包含辅助功能权限请求（可跳过）
- 设置页中提供"外部终端监控"开关 + 分步截图指引
- 会话列表中统一展示内置终端会话和外部终端会话，不区分来源

### 3.3 安全修复集成

| 修复项 | 实现位置 | 说明 |
|--------|----------|------|
| ★ Accessibility 白名单 | `BundleIDValidator.swift` | AX 模式: 读写前验证目标窗口 bundle ID |
| ★ SAS 验证 | `PairingView.swift` | 配对完成后显示 4 位安全码 |
| ★ 前端哈希 | `QRCodeGenerator.swift` | 二维码包含前端 JS 的 SHA-256 哈希 |
| ★ Certificate Pinning | `RelayClient.swift` | 首次连接记住证书，后续验证一致性 |
| 危险命令增强 | `DangerousCommandFilter.swift` | 所有远程输入必须经 Mac 端弹窗确认 |
| 序列号 | `Crypto/` | 消息收发维护递增序列号 |

### 3.4 测试

- 单元测试: AgentAdapter 协议一致性、StreamParser 解析、OutputParser 解析、加密模块
- UI 测试: 引导流程、设置窗口
- 集成测试:
  - 子进程: 启动 claude → 结构化事件 → 推送全链路
  - AX API: 进程发现 → 终端读取 → 事件推送全链路
- **覆盖率目标: >70%**（Swift UI 测试限制）

---

## Phase 4: 传输层抽象 + 消息确认机制

**复杂度: 高 | 依赖: Phase 0 + Phase 1/2 | 预估: 8-11 天**

这是混合连接的核心阶段，建立传输层抽象和消息可靠性机制。

### 4.1 Web 端传输层重构

```
apps/web/src/lib/
├── transport-types.ts      # Transport 接口定义
├── wan-transport.ts        # WAN 中继传输（重构自 ws-client.ts）
├── lan-transport.ts        # LAN 直连传输 + Challenge-Response 认证
├── transport-manager.ts    # 双通道状态机 + 自动选路
├── message-queue.ts        # 发送队列 + ACK 追踪 + 超时重传
└── lan-discovery.ts        # LAN 地址缓存 (IndexedDB) + 连通性探测
```

**Transport 接口：**

```typescript
interface Transport {
  readonly type: 'lan' | 'wan'
  readonly state: 'connecting' | 'connected' | 'disconnected'
  readonly latency: number  // 最近 RTT (ms)

  connect(): Promise<void>
  disconnect(): void
  send(data: Uint8Array): void
  onMessage: (handler: (data: Uint8Array) => void) => void
  onStateChange: (handler: (state: TransportState) => void) => void
}
```

**TransportManager 状态机：**

| 当前状态 | 事件 | 动作 | 新状态 |
|---------|------|------|-------|
| LAN active + WAN standby | LAN 心跳超时 | 切到 WAN，重传未 ack 消息 | WAN active + LAN reconnecting |
| WAN active + LAN reconnecting | LAN 探测成功 | 认证 + 序列号同步 | LAN active + WAN standby |
| 双通道 disconnected | 任一通道恢复 | 切到已恢复通道 | 单通道 active |

**消息队列：**
- 发送时分配 seq，消息入队
- 收到 ack >= seq 时从队列移除
- 超时 3 秒未 ack → 重发（最多 3 次）
- 通道切换 → 队列中未 ack 消息通过新通道重发
- 队列上限 100 条

### 4.2 Mac 端传输层重构

```
apps/mac/AirTerm/Network/
├── TransportProtocol.swift     # Transport 协议定义
├── WANTransport.swift          # 重构自 RelayClient.swift
├── LANServer.swift             # NWListener WebSocket 服务器
├── LANAuthenticator.swift      # Challenge-Response 认证
├── LANAdvertiser.swift         # Bonjour 服务广播（可选）
└── TransportManager.swift      # 双通道管理（Mac 侧）
```

**LANServer 关键参数：**
- 监听: `0.0.0.0:<random-port>`
- 协议: WebSocket over TCP（无 TLS）
- 最大连接数: 5（含未认证）
- 认证超时: 3 秒
- 失败封禁: 5 次/10 分钟/IP

**IP 变化检测：**
- 监听 `NWPathMonitor` 网络变化事件
- IP 变化时通过 WAN E2EE 信道推送 `lan_info` 给所有已配对手机

### 4.3 配对流程扩展

二维码内容增加 LAN 信息：

```json
{
  "server": "https://your-server.com",
  "pairCode": "A3X92K",
  "macPubKey": "base64...",
  "macDeviceId": "uuid",
  "frontend_hash": "sha256...",
  "lan": {
    "addresses": ["192.168.1.100", "10.0.0.5"],
    "port": 48921
  }
}
```

配对完成后，Mac 通过 WAN E2EE 信道发送 `lan_info`，手机缓存后尝试 LAN 直连。

### 4.4 修改现有模块

| 模块 | 修改内容 |
|------|---------|
| `apps/web/hooks/useWebSocket.ts` | 改为使用 TransportManager |
| `apps/web/lib/crypto-layer.ts` | 消息结构增加 seq/ack |
| `apps/web/lib/key-store.ts` | 增加 LAN 地址缓存 |
| `packages/crypto/envelope.ts` | 信封增加 seq/ack 字段 |
| `packages/crypto/sequence.ts` | 增加 ACK 窗口管理 |

### 4.5 测试

- **TransportManager 状态机测试** (TDD，最关键)：所有 state × event 组合、竞争条件
- **MessageQueue 测试**：入队/出队、ACK 清理、超时重传、队列满策略
- **LANTransport 测试**：连接、认证、断线、重连
- **切换场景测试**：LAN→WAN 故障转移、WAN→LAN 升级、双通道同时断开
- **消息不丢失测试**：大量消息 + 频繁切换下的 seq/ack 正确性
- **覆盖率目标: >80%**

---

## Phase 5: 混合连接集成 + 联调

**复杂度: 中 | 依赖: Phase 1-4 | 预估: 5-8 天**

### 5.1 三端联调（LAN 模式）

| 测试场景 | 验证内容 |
|----------|----------|
| LAN 配对 | 扫码 → 配对完成 → 自动发现 LAN → 直连 |
| LAN 消息收发 | Mac 终端输出 → E2EE → LAN 直连 → 手机渲染 |
| LAN 远程输入 | 手机输入 → E2EE → LAN 直连 → Mac 终端 |
| LAN 延迟 | 端到端延迟 < 50ms |

### 5.2 通道切换联调

| 测试场景 | 验证内容 |
|----------|----------|
| LAN → WAN 故障转移 | 断开 WiFi → < 1 秒切到 WAN → 消息无丢失 |
| WAN → LAN 升级 | 重新连 WiFi → 自动切回 LAN → 消息无丢失 |
| 双通道同时断开 | WiFi 断 + 服务器断 → 两者都重连 → 恢复后消息重发 |
| IP 地址变化 | Mac 换网络 → 推送新 lan_info → 手机重连 |
| 频繁切换 | 反复开关 WiFi → 消息序列完整无重复 |

### 5.3 安全验证

| 测试场景 | 验证内容 |
|----------|----------|
| LAN 未配对设备 | 未配对设备连 LAN WS → challenge-response 失败 → 断开 |
| LAN 认证封禁 | 连续 5 次认证失败 → IP 封禁 10 分钟 |
| LAN 认证超时 | 连接后不回复 challenge → 3 秒后断开 |
| ★ 服务器无法解密 | 在服务器日志中搜索明文内容 → 不应存在 |
| ★ SAS 不一致拒绝 | 模拟 MITM 替换公钥 → SAS 码不一致 → 配对失败 |
| ★ 重放攻击 | 截获加密消息重发 → 序列号校验失败 → 被拒绝 |
| ★ JWT 吊销 | 撤销设备后使用旧 JWT → 认证失败 |
| ★ 非终端窗口保护 | 尝试向非终端应用写入 → bundle ID 校验失败 → 被拒绝 |
| ★ 前端代码篡改 | 修改前端 JS → 哈希校验失败 → 配对中止 |
| 配对码暴力破解 | 连续错误尝试 → 第 3 次后配对码作废 |

---

## Phase 6: 性能优化 + 内测

**复杂度: 中 | 依赖: Phase 5 | 预估: 3-5 天**

### 6.1 性能验证

| 指标 | 目标 |
|------|------|
| LAN 端到端延迟 | < 50ms |
| WAN 端到端延迟 | < 200ms |
| 通道切换延迟 | < 1 秒 |
| 终端内容同步延迟 | < 1 秒 |
| 远程输入到达延迟 | < 500ms |
| Mac 端 CPU 占用 | < 3% |
| Mac 端内存占用 | < 50MB |
| 手机 Web 首次加载 | < 2 秒 |

### 6.2 内测

- 真实网络环境下的稳定性测试
- 不同 WiFi 环境切换（家庭/办公室/咖啡馆）
- 长时间运行稳定性（24 小时）
- 多会话并发下的资源占用

---

## 安全审计修复清单

### P0 — 发布前必修

| # | 问题 | 严重程度 | 修复方案 | Phase |
|---|------|----------|----------|-------|
| S1 | 前端与中继服务器同域托管，恶意服务器可注入后门 JS | CRITICAL | 前端独立部署（Cloudflare Pages），二维码包含 JS 哈希，手机端校验 | 1, 2 |
| S2 | 配对阶段手机公钥经服务器中转，可被 MITM | CRITICAL | 配对完成后双方显示 SAS 安全码（4 位数字），用户目视确认一致 | 0, 2, 3 |
| S3 | 无消息重放防护 | HIGH | 每个方向维护递增序列号，纳入 AEAD 的 AAD | 0 |
| S4 | Accessibility API 权限无边界限制 | HIGH | InputHandler 操作前验证目标窗口 bundle ID 白名单 | 3 |
| S5 | JWT 30 天有效期 + 无吊销机制 | HIGH | access token 15 分钟 + refresh token + 服务器端黑名单 | 1 |

### P1 — V1.0 前修复

| # | 问题 | 严重程度 | 修复方案 | Phase |
|---|------|----------|----------|-------|
| S6 | .env.example 缺少 DB_ENCRYPTION_KEY | HIGH | 补全变量 + 启动时校验 | 0 |
| S7 | SQLCipher pragma 字符串拼接注入 | HIGH | 参数化 pragma 调用 + key 格式校验 | 1 |
| S8 | 危险命令拦截可被绕过 | MEDIUM | 所有远程输入必须 Mac 弹窗确认，不依赖字符串匹配 | 3 |
| S9 | 心跳消息未加密 | MEDIUM | 心跳也走 E2E 加密信封 | 0, 1 |
| S10 | 消息大小侧信道 | MEDIUM | 消息 padding 到 1KB 倍数 | 0 |

### P2 — 后续迭代

| # | 问题 | 严重程度 | 修复方案 | Phase |
|---|------|----------|----------|-------|
| S11 | 配对码熵不足 (36^6) | MEDIUM | 8 位 alphanumeric (62^8) + 3 次失败作废 | 1 |
| S12 | Web 端密钥存储依赖浏览器 | MEDIUM | 严格 CSP + SRI + derived key 使用限制 | 2 |
| S13 | 无前向保密 | LOW | 定期密钥轮换（每 24h）或 Double Ratchet | 后续 |
| S14 | 审计日志无防篡改 | LOW | append-only hash chain | 后续 |
| S15 | 重连无 certificate pinning | LOW | 首次连接记住证书指纹 | 3 |

---

## 技术栈确认

| 组件 | 技术 | 版本 |
|------|------|------|
| 加密 | @noble/curves + @noble/ciphers | ^1.0 |
| 服务器 | Hono + ws + better-sqlite3 + SQLCipher | Hono 4, ws 8 |
| Web 前端 | React 19 + Vite 6 + Tailwind 4 | 最新 |
| Mac 应用 | Swift + SwiftUI + pty + Accessibility API | Swift 5.9+ |
| 测试 | vitest (TS) + XCTest (Swift) | 最新 |
| 部署 | Docker (服务器) + Cloudflare Pages (前端) | - |
| CI/CD | GitHub Actions | - |

---

## 里程碑

### MVP 核心验证（明文通信，跑通链路）

| 里程碑 | 内容 | 预估 |
|--------|------|------|
| M0 | 项目初始化 + 消息协议定义 | 第 1 周 |
| M1 | 服务器可运行 + 配对流程 + 公共实例部署 | 第 1-2 周 |
| M2 | Web 前端可配对 + 查看终端输出 | 第 2-3 周 |
| M3a | Mac 子进程模式可用（内置终端 + stream-json） | 第 3-4 周 |
| M3b | Mac AX API 模式可用（外部终端监控） | 第 4-5 周 |
| **M3c** | **三端联调：Mac → 服务器 → 手机 完整链路跑通** | **第 5-6 周** |

### 安全加固

| 里程碑 | 内容 | 预估 |
|--------|------|------|
| M4 | E2EE 加密模块 + 集成到全链路 | 第 6-8 周 |
| M5 | 安全修复（JWT 短期化、SQLCipher、SAS 验证等） | 第 8-9 周 |

### 后续阶段

| 里程碑 | 内容 | 预估 |
|--------|------|------|
| M6 | 原生移动壳 + LAN 直连 + 推送通知 | 待定 |

**关键路径:** M0 → M1 → M2 并行 M3a → M3c 联调。M3b 可与 M3a 并行推进。核心链路跑通后再叠加安全层。
