# AirTerm Roadmap

> 本文档是 AirTerm 的产品定位、技术选型和分阶段实施计划。进度状态见 `docs/PROGRESS.md`。

## 一、产品定义

> **AirTerm 是一款原生 macOS 终端，可以在任何带浏览器的设备（手机/平板/另一台电脑）上实时接管。**

**差异化核心**：手机接管。你在办公室写了一半的命令，路上在手机上接着看输出、发指令。

**设计原则**：
- 终端体验媲美 Ghostty / iTerm2（性能 + 视觉）
- 手机接管延迟体感接近本地（P2P 优先）
- 极简配置、零 Dashboard（unix 气质）

## 二、成功标准

| 维度 | v1 目标 |
|---|---|
| Mac 本地渲染 | 120fps 滚动 · 输入延迟 <16ms · `cat 100MB` 不卡 |
| 手机接管延迟 | 同 WiFi <40ms · 跨省 4G <120ms |
| Mac App 启动 | 冷启动 <300ms 到可输入 |
| Web 端首屏 | <1.5s，gzip <300KB |
| 稳定性 | 24h 持续运行无泄漏，断网自动重连 |

## 三、关键决策（已锁定）

| 决策 | 结论 | 理由 |
|---|---|---|
| 产品定位 | 原生终端 + 手机接管，**不再是 Claude Code 专用** | 用户明确转向 |
| Mac 渲染 | **Metal GPU**，字符网格 + 字形图集 | 120fps 前提；TextKit / WebView 拒绝 |
| UI 框架 | **AppKit 主 + SwiftUI 辅**（设置窗口） | SwiftUI 下 tab/split 帧率不够 |
| 终端仿真 | **自研 VT100/xterm**（扩展现有 `ANSIParser`/`TerminalScreen`） | SwiftTerm 历史包袱重 |
| 手机端 | **PWA 先行**（React + Vite + xterm.js），iOS 原生 v2 再说 | 零安装、免审核、一套代码跨平台 |
| 传输 | **WebRTC P2P DataChannel + TURN fallback** | 纯中继在跨省场景物理上达不到延迟目标 |
| 信令 | 现有 `apps/server` 改造，只转发 SDP/ICE，不碰业务数据 | 服务器成本降 90%+ |
| E2E 加密 | **Noise Protocol IK** | 信令服务器零知识 |
| 配置 | TOML + 热重载 | 对齐 Ghostty 的 geek 风味 |
| tmux 体验 | **层次 A：原生分屏 + 兼容 tmux 运行** | 不做 daemon，复杂度可控 |
| 分发 | Mac: DMG 直下 · Web: Cloudflare Pages (airterm.ai) | 不走 App Store |
| 仓库分支 | `master` = v0 归档（tag `v0-airclaude`）· `redesign` = 主开发分支 · `main` 未来由 `redesign` 改名 | 用户明确指示 |
| 品牌 | AirTerm 保留 | — |

## 四、技术栈

### Mac App
- 语言: Swift 5.9+，目标 macOS 14+
- UI: AppKit（主）+ SwiftUI（设置/配对窗口）
- 渲染: Metal + CoreText + HarfBuzz（连字/Nerd Font/Emoji）
- 终端仿真: 自研（现有 `ANSIParser` + `TerminalScreen` 扩展）
- PTY: 自研（现有 `PTY.swift` 扩展）
- WebRTC: Google libwebrtc xcframework
- 配置: TOML
- 打包: Swift Package + 自研 `bundle.sh` + ad-hoc sign（v1）→ notarization（v1.1）

### 中继服务器
- 语言: TypeScript (Hono) — 保留
- 职责: 仅信令 + TURN fallback
- DB: SQLite + SQLCipher（设备注册、配对、长期 token）
- TURN: 独立部署 coturn
- 部署: Fly.io 或 Railway

### Web (PWA)
- React 19 + Vite + TypeScript
- 终端: xterm.js + xterm-addon-webgl
- 状态: Zustand（轻量）
- WebRTC: 浏览器原生 `RTCPeerConnection`
- 样式: Tailwind v4
- PWA: `vite-plugin-pwa` + 自定义 Service Worker
- 部署: Cloudflare Pages (`airterm.ai`)

### 协议
| 通道 | 协议 |
|---|---|
| HTTP 配对 | JSON over HTTPS |
| 信令 | JSON over WSS |
| 数据通道 | 二进制帧 over WebRTC DataChannel（ScreenDelta / InputEvent / Control） |
| E2E 加密 | Noise IK |

## 五、目标目录结构

```
airterm/
├── apps/
│   ├── mac/
│   │   ├── AirTerm/
│   │   │   ├── App/                ← 已建（AirTermApp, AppDelegate）
│   │   │   ├── Core/               ← 计划：PTY, VTParser, TerminalScreen, Session, PaneNode
│   │   │   ├── Render/             ← 已建（MetalRenderer stub）；后加 GlyphAtlas, GridLayout, Shaders
│   │   │   ├── UI/                 ← 已建（TerminalWindow, TerminalView）；后加 TabBar, Settings
│   │   │   ├── Config/             ← 计划：TOML loader, Theme
│   │   │   ├── Takeover/           ← 计划：SignalingClient, WebRTCPeer, FrameEncoder, InputDecoder
│   │   │   ├── Pairing/            ← 现有 PairingService + NoiseHandshake
│   │   │   ├── Models/             ← 现有 PairInfo
│   │   │   ├── Services/           ← 现有（待归位）ANSIParser, PTY, TerminalScreen, RelayClient, PairingService
│   │   │   └── Utils/              ← 现有 DebugLog, DangerousCommandFilter
│   │   ├── Tests/
│   │   └── Package.swift
│   │
│   ├── web/                        ← 待重建（仅保留 lib/ 和 styles/）
│   │   └── src/
│   │       ├── app/
│   │       ├── pages/              ← 计划：Pair, Takeover, Settings
│   │       ├── components/         ← 计划：Terminal, Keyboard, StatusBar
│   │       ├── lib/                ← 现有 crypto-layer, key-store, ws-client, storage, theme, time
│   │       ├── hooks/              ← 计划
│   │       └── styles/globals.css  ← 现有
│   │
│   └── server/                     ← 保留，改造为信令
│       └── src/
│           ├── routes/pair.ts
│           ├── signaling/          ← 计划
│           ├── auth/db/utils/      ← 现有
│
├── packages/
│   ├── protocol/                   ← 三端共用类型
│   │   └── src/
│   │       ├── pairing.ts          ← 现有
│   │       ├── signaling.ts        ← 计划
│   │       ├── frames/             ← 计划（二进制帧 schema）
│   │       └── index.ts
│   └── turn-deploy/                ← 计划：coturn docker-compose
│
├── docs/
│   ├── ROADMAP.md                  ← 本文件
│   ├── PROGRESS.md                 ← 实时进度
│   ├── ARCHITECTURE.md             ← 计划
│   ├── PROTOCOL.md                 ← 计划
│   └── DEPLOYMENT.md               ← 计划
│
└── docker-compose.yml              ← 现有；后加 coturn
```

## 六、分阶段 Roadmap

> 每个阶段结束都有**可演示的里程碑**。

### Phase 1 · Mac 终端引擎 MVP（~3.5 周）
打开窗口，能跑 `vim`、`htop`、`tmux`。包含原生分屏（tmux 层次 A）。

1. ✅ App 入口 + Metal 视图骨架
2. ⬜ Metal 文本渲染 + 字形图集（CoreText + HarfBuzz）
3. ⬜ 连接 PTY → VTParser → TerminalScreen → Renderer，键盘输入通路
4. ⬜ 滚动回溯、选区复制粘贴
5. ⬜ Pane 树数据模型（leaf/split 递归）
6. ⬜ NSSplitView 渲染 pane 树，⌘D/⌘⇧D 切分，⌘[/⌘] 聚焦切换
7. ⬜ Tab 系统（⌘T 新 tab、⌘1-9 切换）

**验收**：打开 AirTerm → `vim README.md` 正常；`cat /dev/urandom | head -c 10M | hexdump` 帧率稳定 120fps；竖切屏幕、左 `vim` 右 `npm run dev` 同时运行。

### Phase 2 · 配置 + 主题 + 字体（~1 周）
`~/.config/airterm/config.toml` 热重载；内置 Catppuccin、Tokyo Night、Dracula、Solarized；字体/字号/光标/padding/透明度均可配。

**验收**：改配置不重启立即生效。

### Phase 3 · 信令 + 配对重建（~1 周）
Mac 出二维码 → 手机扫码 → Noise 握手完成 → 配对 token 持久化。此阶段尚无屏幕数据传输。

**验收**：Mac 菜单"配对新设备" → 手机 PWA 提示"已连接"。

### Phase 4 · WebRTC 数据通道 + 屏幕镜像（~2 周）
Mac 编码屏幕状态 delta → 手机 xterm.js 增量渲染。

**验收**：Mac 上 `ls` / `vim` → 手机同步显示，同 WiFi 延迟 <40ms。

### Phase 5 · 手机接管输入（~1.5 周）
手机键盘 → InputEvent 帧 → Mac PTY。iOS 虚拟键盘工具条（Ctrl/Esc/Tab/方向键）。"谁在输入"指示器。

**验收**：手机 `npm run dev`，Mac 窗口同步出现命令和输出；手机 vim 能用。

### Phase 6 · PWA 优化（~1 周）
manifest、Service Worker、加主屏引导、虚拟键盘遮挡适配、横竖屏、触觉反馈。

**验收**：iPhone Safari 加主屏后像原生 App。

### Phase 7 · 稳定性 + 分发（~1 周）
重连策略、内存审计、Mac 代码签名 + 公证、DMG 制作、Cloudflare Pages 部署、崩溃上报。

**验收**：5 个朋友内测 24h 无严重问题。

### 总时间线

```
Phase 1  Mac 终端 MVP (含分屏)    ████████████████████ 3.5w
Phase 2  配置/主题                       ██████ 1w
Phase 3  信令 + 配对                     ██████ 1w
Phase 4  WebRTC + 镜像                    ████████████ 2w
Phase 5  手机接管输入                      █████████ 1.5w
Phase 6  PWA 优化                           ██████ 1w
Phase 7  稳定性 + 分发                       ██████ 1w
                                              ≈ 11 周 (~2.75 月)
```

## 七、主要风险

| 风险 | 可能性 | 影响 | 缓解 |
|---|---|---|---|
| Metal 渲染器复杂度高 | 高 | 高 | Phase 1 若拖超 4 周，降级为 CoreText 60fps，Metal 放 v2 |
| libwebrtc Swift 集成复杂 | 中 | 中 | Phase 4 预留 3 天 spike 验证，失败则临时走 server relay |
| iOS PWA 后台被杀 | 高 | 低 | 文档说明 + 点回自动重连 |
| 企业 NAT 穿透失败 | 中 | 中 | coturn TURN 兜底 |
| 字形图集内存膨胀（CJK） | 中 | 低 | LRU + 冷启动预热限制 |
| vttest 兼容度差 | 中 | 高 | 每 phase 回归 + 累积测试用例 |

## 八、归档说明

- 原 Claude Code 聚焦的 "AirClaude" 版本快照在 `master` 分支 + tag `v0-airclaude`（远程 GitHub 已推）
- 本次重设计在 `redesign` 分支进行，v1 GA 时改名为 `main`
- Phase 1 首个骨架 commit：`c0d980c`
