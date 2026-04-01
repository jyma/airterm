# 架构设计

## 系统总览

AirTerm 由三个组件构成：

```
┌──────────────────────────────────────────────────────────────┐
│                       MVP 架构                                │
│                                                              │
│  手机浏览器              公共中继                  Mac         │
│  ┌──────────┐  WSS    ┌──────────┐    WSS    ┌──────────┐  │
│  │ Web UI   │◄───────►│ 消息转发   │◄─────────►│ 菜单栏App │  │
│  │ (React)  │         │ (Hono)   │           │          │  │
│  └──────────┘  relay  └──────────┘           │ Agent    │  │
│                .airterm                       │ Adapter  │  │
│                .dev                           │ ├─ pty   │  │
│                                               │ └─ AX API│  │
│                                               └──────────┘  │
└──────────────────────────────────────────────────────────────┘
```

> **MVP 阶段全走 WAN 中继（公共实例 `relay.airterm.dev`）。**
> LAN 直连受浏览器 Mixed Content 限制（https 页面无法连 ws://），留到原生移动壳阶段实现。
> E2EE 加密在核心链路验证后叠加，MVP 先用明文 WebSocket 跑通。

### 后续演进：混合连接架构（原生壳阶段）

```
手机 App (原生壳)                                  Mac
┌───────────────┐  LAN ws:// (优先)              ┌──────────┐
│ WKWebView      │◄──────── 内网直连 ───────────►│ LANServer │
│  └─ React UI   │  E2EE                        │          │
│ Native Bridge  │  WAN wss:// (回退)             │          │
│  ├─ APNs 推送  │◄─── E2EE ──► 公共中继 ◄──────►│ Relay    │
│  └─ 后台保活    │                               └──────────┘
└───────────────┘
```

## 组件职责

### Mac 菜单栏应用 (`apps/mac`)

核心组件，运行在用户的 Mac 上：

```
┌───────────────────────────────────────────────────┐
│                Mac App 内部架构                      │
│                                                    │
│  ┌──────────────────────────────────┐              │
│  │ AgentAdapter (协议)               │              │
│  │                                  │              │
│  │  ┌────────────────────────────┐  │              │
│  │  │ SubprocessAdapter (主要)    │  │              │
│  │  │  TerminalEmulator (pty)    │  │ 内置终端      │
│  │  │  StreamParser (JSON 事件流) │  │ 用户体验同终端 │
│  │  └────────────────────────────┘  │              │
│  │                                  │              │
│  │  ┌────────────────────────────┐  │              │
│  │  │ AccessibilityAdapter (增强) │  │              │
│  │  │  ProcessMonitor            │  │ 接管外部终端   │
│  │  │  WindowMapper              │  │ 需辅助功能权限 │
│  │  │  TerminalReader            │  │              │
│  │  │  OutputParser              │  │              │
│  │  └────────────────────────────┘  │              │
│  └──────────┬───────────────────────┘              │
│             │ 结构化事件 (统一接口)                   │
│  ┌──────────▼───────────────┐                      │
│  │ RelayClient              │ WSS 连接中继服务器     │
│  │  (MVP: 仅 WAN 中继)       │ 默认 relay.airterm.dev│
│  └──────────────────────────┘                      │
│                                                    │
│  ┌───────────────┐                                 │
│  │ InputHandler  │ 远程指令 → 写入终端               │
│  └───────────────┘                                 │
└───────────────────────────────────────────────────┘
```

#### AgentAdapter：双模 CLI 集成

AirTerm 通过 `AgentAdapter` 协议支持两种 CLI 集成模式，**两种模式同等重要，并列提供**：

**模式 1: 子进程模式（SubprocessAdapter）**

从 AirTerm 内置终端启动 CLI，用户体验与在 iTerm2/Terminal.app 中完全一致：

```
用户在 AirTerm 终端面板输入 claude
    ↓
TerminalEmulator 通过 pty 启动进程
    ↓
用户正常使用终端（与普通终端无差异）
    ↓
同时 StreamParser 通过 --input-format stream-json 接收结构化事件
    ↓
结构化事件（diff、工具调用、确认请求等）推送到手机
```

优势：
- 无需辅助功能权限
- CPU 近零（事件驱动，非轮询）
- 结构化 JSON 输出，无需正则解析终端文本
- 兼容性好（不依赖各终端 App 的 AX API 实现）
- 未来可扩展到其他 CLI Agent（Codex、Gemini CLI 等）

**模式 2: Accessibility 模式（AccessibilityAdapter）**

在后台静默监控用户已经在外部终端（Terminal.app / iTerm2）中运行的 CLI 会话：

```
用户在 iTerm2 中已经启动了 claude
    ↓
ProcessMonitor 扫描发现 claude 进程
    ↓
WindowMapper 将 PID 映射到终端窗口
    ↓
TerminalReader 通过 AX API 读取窗口文本
    ↓
OutputParser 正则解析为结构化事件
    ↓
结构化事件推送到手机
```

优势：
- 无需从 AirTerm 启动，接管已有会话
- 对用户现有工作流零侵入

**模块说明：**

| 模块 | 所属模式 | 职责 | 关键 API |
|------|---------|------|----------|
| AgentAdapter | 协议 | 统一接口：send(input)、onEvent(callback) | Swift Protocol |
| TerminalEmulator | 子进程 | 内置终端，pty + Process 管理 | `Process`, `posix_openpt` |
| StreamParser | 子进程 | 解析 `--input-format stream-json` 事件流 | JSON Decoder |
| ProcessMonitor | AX API | 定时扫描 CLI 进程 | `NSRunningApplication` |
| WindowMapper | AX API | PID → 终端窗口映射 | `AXUIElementCreateApplication` |
| TerminalReader | AX API | 读取终端窗口文本 | `AXUIElementCopyAttributeValue` |
| OutputParser | AX API | 终端文本 → 结构化事件 | 正则 + 状态机 |
| RelayClient | 通用 | 与中继服务器的 WSS 连接（MVP 仅此通道） | `URLSessionWebSocketTask` |
| InputHandler | 通用 | 远程指令写入终端 | pty write / `CGEvent` |

#### RelayClient（Mac 侧网络通信）

MVP 阶段 Mac 端通过 `RelayClient` 与公共中继服务器（默认 `relay.airterm.dev`）建立 WSS 连接。

上层的 `AgentAdapter`（无论子进程模式还是 AX API 模式）只调用 `RelayClient.send(data)` 和接收 `RelayClient.onReceive(data)`。

> 后续原生壳阶段将引入 `TransportManager`，管理 LAN 直连 + WAN 中继双通道，对上层接口不变。

### 中继服务器 (`apps/server`)

极简的消息转发层，不处理业务逻辑。默认使用官方公共实例 `relay.airterm.dev`，用户也可自部署：

```
┌─────────────────────────────────┐
│        中继服务器内部架构          │
│                                 │
│  ┌─────────────┐               │
│  │ HTTP Server │ 静态页面托管    │
│  │ (Hono)      │ 健康检查       │
│  └─────────────┘               │
│                                 │
│  ┌─────────────┐               │
│  │ WS Manager  │ 管理连接       │
│  │ 连接管理     │ Mac ↔ Phone   │
│  └──────┬──────┘               │
│         │                      │
│  ┌──────▼──────┐               │
│  │ PairService │ 配对码生成     │
│  │ 配对服务     │ 设备绑定       │
│  └──────┬──────┘               │
│         │                      │
│  ┌──────▼──────┐               │
│  │ AuthMiddle  │ JWT 验证       │
│  │ 认证中间件   │ 设备鉴权       │
│  └─────────────┘               │
└─────────────────────────────────┘
```

**设计原则：**

- 服务器只做转发，不解密、不存储消息内容
- 仅存储：设备 ID、公钥、配对关系
- 无状态设计，可水平扩展

### Web 前端 (`apps/web`)

手机端响应式 Web 应用：

```
┌────────────────────────────────────┐
│          Web 前端架构                │
│                                    │
│  ┌─────────────┐                  │
│  │ SessionList │ 会话列表页         │
│  └──────┬──────┘                  │
│         │                         │
│  ┌──────▼──────┐                  │
│  │ SessionView │ 单会话详情         │
│  └──────┬──────┘                  │
│         │                         │
│  ┌──────▼──────────────┐          │
│  │ 渲染组件              │          │
│  │ ChatBubble  消息气泡  │          │
│  │ DiffViewer  代码差异  │          │
│  │ ToolCard    工具调用  │          │
│  │ ApprovalBar 确认按钮  │          │
│  │ QuickPanel  快捷指令  │          │
│  └─────────────────────┘          │
│                                    │
│  ┌─────────────┐                  │
│  │ CryptoLayer │ 端到端加解密       │
│  └──────┬──────┘                  │
│         │                         │
│  ┌──────▼──────────────────┐      │
│  │ TransportManager        │      │
│  │  ├─ LANTransport        │ LAN  │
│  │  ├─ WANTransport        │ WAN  │
│  │  ├─ MessageQueue        │ 重传  │
│  │  └─ LANDiscovery        │ 发现  │
│  └─────────────────────────┘      │
└────────────────────────────────────┘
```

#### TransportManager（Web 侧）

Web 端 TransportManager 对上层 CryptoLayer 提供统一的 `send()` / `onMessage()` 接口，内部管理两个传输通道：

- **LANTransport**: `ws://<mac-lan-ip>:<port>/ws`，通过 Challenge-Response 认证
- **WANTransport**: `wss://<relay-server>/ws/phone`，通过 JWT 认证

工作流程：
1. 打开页面时并行尝试 LAN 和 WAN（Happy Eyeballs）
2. LAN 先通则标记 active，WAN 保持 standby
3. LAN 断开（心跳超时 10 秒）→ 自动切到 WAN，重传未确认消息
4. 后台持续探测 LAN，恢复后切回

## 数据流

### 1. Mac → 手机（查看输出）

```
TerminalReader 检测到文本变化
    ↓
OutputParser 解析为结构化事件
    ↓
CryptoLayer 端到端加密 (附带 seq/ack)
    ↓
TransportManager 选择 active 通道发送
    ├─ LAN 可用: ws:// 直连手机
    └─ LAN 不可用: wss:// → 中继服务器 → 手机
    ↓
Web TransportManager 接收
    ↓
CryptoLayer 解密 + 序列号校验
    ↓
对应渲染组件展示
```

### 2. 手机 → Mac（发送指令）

```
用户在 Web UI 输入文字或点击按钮
    ↓
CryptoLayer 端到端加密 (附带 seq/ack)
    ↓
TransportManager 选择 active 通道发送
    ├─ LAN 可用: ws:// 直连 Mac
    └─ LAN 不可用: wss:// → 中继服务器 → Mac
    ↓
Mac TransportManager 接收
    ↓
CryptoLayer 解密 + 序列号校验
    ↓
安全检查（危险命令拦截）
    ↓
Mac 端确认弹窗（可选，高危指令必弹）
    ↓
InputHandler 通过 Accessibility API 写入终端
```

### 3. 通道切换（LAN ↔ WAN）

```
场景 A: LAN 断开 → 故障转移到 WAN
───────────────────────────────────
LAN 心跳超时 (连续 2 次, ~10 秒)
    ↓
TransportManager 将 active 切到 WAN (已 standby 保活)
    ↓
发送队列中未确认消息 (seq 未 ack) 通过 WAN 重发
    ↓
业务恢复，用户无感知 (切换 < 1 秒)
    ↓
后台持续探测 LAN (退避: 5s, 10s, 30s, 60s)

场景 B: LAN 恢复 → 升级回 LAN
───────────────────────────────────
后台探测发现 Mac LAN 可达
    ↓
建立 LAN WebSocket + Challenge-Response 认证
    ↓
序列号同步确认
    ↓
active 切回 LAN，WAN 降为 standby
```

## 会话生命周期

```
        ┌─────────┐
        │ 已发现   │  ProcessMonitor 检测到新 claude 进程
        └────┬────┘
             │ 自动关联终端窗口
        ┌────▼────┐
        │ 已连接   │  WindowMapper 成功映射
        └────┬────┘
             │ 开始推送输出
        ┌────▼────┐
        │ 活跃中   │  正常运行，双向通信
        └────┬────┘
             │ 进程退出或窗口关闭
        ┌────▼────┐
        │ 已结束   │  保留最后输出快照
        └─────────┘
```

## 通信协议

详见 [protocol.md](protocol.md)。

## 性能考量

| 指标 | 目标 | 实现方式 |
|------|------|----------|
| 终端扫描频率 | 2 秒 | ProcessMonitor 定时器 |
| 内容变化检测 | 500ms | TerminalReader diff 比对 |
| LAN 端到端延迟 | < 50ms | 内网直连，无中继 |
| WAN 端到端延迟 | < 200ms | WSS 长连接，无轮询 |
| 通道切换延迟 | < 1 秒 | 双通道热备，无需重新握手 |
| Mac 端 CPU | < 3% | 仅在内容变化时处理 |
| LAN 心跳开销 | 极低 | 每 5 秒 1 条加密心跳 |
| WAN standby 开销 | 极低 | 每 60 秒 1 条保活心跳 |
| 服务器内存 | < 50MB | 无状态转发，不缓存消息 |
