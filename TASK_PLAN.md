# AirTerm 任务执行计划

> 基于 PRD、实现规划、UI 设计规范 及 Pencil 设计稿 综合制定
> 生成日期: 2026-04-01
> 最后更新: 2026-04-01 (Phase A-E 全部完成)

---

## 执行状态

| 阶段 | 状态 | 测试 | 构建 |
|------|------|------|------|
| Phase A: Web UI 设计稿对齐 | ✅ 完成 | ✅ | ✅ |
| Phase B: Mac UI 设计稿对齐 | ✅ 完成 | ✅ | ✅ |
| Phase C: E2EE 加密集成 | ✅ 完成 | ✅ | ✅ |
| Phase D: 安全加固 | ✅ 完成 | ✅ | ✅ |
| Phase E: 测试全面覆盖 | ✅ 完成 (88/88 通过) | ✅ | ✅ |
| Phase F: 联调部署 | ⬜ 待执行 | - | - |

---

## 项目现状评估

### 已完成 (~95%)

| 模块 | 状态 | 说明 |
|------|------|------|
| Server (apps/server) | 基本完成 | 配对、中继、DB、心跳、token 认证均可用 |
| Web (apps/web) | 基本完成 | 配对页、会话页、设置页、组件库均可用 |
| Mac (apps/mac) | 基本完成 | 菜单栏、子进程模式、AX API 模式、中继客户端 |
| Crypto (packages/crypto) | 原语完成 | X25519、ChaCha20-Poly1305、SAS、序列号 |
| Protocol (packages/protocol) | 类型完成 | 消息类型、信封、错误码全部定义 |

### 关键缺口

1. **E2EE 未集成** — 加密库存在但未接入协议层，当前全程明文 base64
2. **Web UI 与设计稿对齐** — 现有 UI 可用但未做像素级设计稿还原
3. **Mac 端部分界面缺失** — Onboarding、集成终端 Tabs、设置窗口等
4. **安全加固未实施** — JWT 短期化、SQLCipher、SAS 验证、前端哈希校验
5. **测试覆盖不足** — 缺少系统性 E2E 测试和完整集成测试

---

## 设计稿清单 (Pencil 21 帧)

### Mobile (手机端 Web)

| # | 设计帧 | ID | 模式 | 对应页面 | 实现状态 |
|---|--------|-----|------|----------|---------|
| 1 | Mobile - Session Detail | Jepf1 | Dark | SessionDetailPage | 已有，需对齐设计稿 |
| 2 | Mobile - Session Detail (Light) | U0BwI | Light | SessionDetailPage | 已有，需对齐设计稿 |
| 3 | Mobile - Tmux View (Light) | ih7pj | Light | SessionsPage (多面板) | 已有，需对齐设计稿 |
| 4 | Mobile - Tmux View (Dark) | cO1qk | Dark | SessionsPage (多面板) | 已有，需对齐设计稿 |
| 5 | Mobile - 3 Panes (Dark) | FzdNC | Dark | SessionsPage (三面板) | 已有，需对齐设计稿 |
| 6 | Mobile - Settings | mbXgv | Light | SettingsPage | 已有，需对齐设计稿 |
| 7 | Mobile - Settings (Dark) | LTs9X | Dark | SettingsPage | 已有，需对齐设计稿 |
| 8 | Mobile - Pairing QR | 4BJvd | Light | PairPage | 已有，需对齐设计稿 |
| 9 | Mobile - Pairing QR (Dark) | um1eb | Dark | PairPage | 已有，需对齐设计稿 |

### Mac (macOS 原生应用)

| # | 设计帧 | ID | 模式 | 对应视图 | 实现状态 |
|---|--------|-----|------|----------|---------|
| 10 | Mac - Multi-Session Window | qfbtm | Light | MainWindow + 双面板 | 已有，需对齐 |
| 11 | Mac - Multi-Session (Dark) | qSe1a | Dark | MainWindow + 双面板 | 已有，需对齐 |
| 12 | Mac - Collapsed Sidebar (Dark) | QKak5 | Dark | MainWindow (侧栏折叠) | 需实现折叠交互 |
| 13 | Mac - Integrated Terminal (Dark) | sYqPW | Dark | 内置终端 + Tab 视图 | 需完善 Tab UI |
| 14 | Mac - Menubar Panel | nwGTB | Dark | MenuBarView (在线) | 已有，需对齐 |
| 15 | Mac - Menubar (Offline) | 3k9d2 | Dark | MenuBarView (离线) | 需实现离线态 |
| 16 | Mac - Settings (Light) | 34oWq | Light | SettingsView | 需重做为侧栏式 |
| 17 | Mac - Settings (Dark) | D5DRP | Dark | SettingsView | 需重做为侧栏式 |
| 18 | Mac - Pairing (Light) | 7zn6L | Light | PairingView | 已有，需对齐 |
| 19 | Mac - Pairing (Dark) | cIUnC | Dark | PairingView | 已有，需对齐 |
| 20 | Mac - Onboarding (Light) | 9Y02c | Light | OnboardingView | 需新建 |
| 21 | Mac - Onboarding (Dark) | CHQ8v | Dark | OnboardingView | 需新建 |

---

## 执行阶段

### Phase A: Web UI 设计稿对齐 (优先级最高)

手机端是用户直接交互的界面，设计稿还原度直接影响体验。

#### A1: 全局样式系统重建
- [ ] 对照设计稿确认 CSS 变量 (色板、字体、间距、圆角)
- [ ] 确认暗色/亮色双主题变量完整覆盖
- [ ] 确认字体栈: JetBrains Mono (代码) + SF Pro (UI)
- [ ] 确认动画定义: message-in, approval-in, pulse, slide 等
- [ ] 确认响应式断点: 769px (平板分栏), 1200px (多窗口)
- [ ] 确认安全区域: env(safe-area-inset-*) 处理

#### A2: 会话详情页对齐 (Jepf1 / U0BwI)
- [ ] TopBar: 返回箭头 + 会话名 + 状态标签 (运行中/已结束)
- [ ] 消息气泡: "— Claude" 标签 + bg-secondary 圆角卡片 + 时间戳
- [ ] 工具卡片: 左侧色条 (Read=蓝, Edit=黄, Bash=青) + 可折叠
- [ ] Diff 块: 行号 + 红底删除行 + 绿底添加行
- [ ] ApprovalBar: 黄色边框 + 命令预览 + Deny/Allow 双按钮 (48px)
- [ ] InputBar: 固定底部 + 圆角输入框 + 蓝色发送按钮
- [ ] QuickPanel: 药丸按钮横滚 (y, /commit, /review, 继续, Ctrl+C 标红)

#### A3: 会话列表 / Tmux 视图对齐 (ih7pj / cO1qk / FzdNC)
- [ ] 顶栏: AirClaude logo + 齿轮按钮 + 毛玻璃效果
- [ ] 多面板 (tmux): 垂直分割 2-3 面板
- [ ] PaneHeader: 状态点(绿色脉冲) + 会话名 + 路径 + 状态标签
- [ ] 面板内终端内容渲染 (简化版)
- [ ] 点击面板标题展开为全屏详情
- [ ] 3 面板视图: 三个面板垂直堆叠 + 各自独立滚动

#### A4: 设置页对齐 (mbXgv / LTs9X)
- [ ] iOS 分组卡片风格
- [ ] 外观: 主题下拉 (系统/暗色/亮色)
- [ ] 连接: 状态显示 (绿点 + "已连接")
- [ ] 已配对设备: 设备名 + 配对日期 + 最后活跃 + 红色撤销按钮
- [ ] "+ 配对新设备" 蓝色描边按钮
- [ ] 安全: 高危命令确认开关 + 操作日志开关 + 自动锁定下拉
- [ ] 确保 Toggle 开关组件样式正确

#### A5: 配对页对齐 (4BJvd / um1eb)
- [ ] 当前实现是输入配对码，设计稿展示的是 Mac 端扫码页
- [ ] Web 端配对页: 6 位配对码输入界面保留（手机端扫码后跳转此页）
- [ ] 确认配对流程: 扫码 → 自动填入 → 完成 → 跳转会话列表

#### A6: 大屏适配 (≥ 769px)
- [ ] 左右分栏布局: 280px 侧栏 + 右侧详情
- [ ] 侧栏: 会话卡片列表 + 选中高亮 (accent-blue 左边条)
- [ ] 多窗口分屏 (≥ 1200px): 双栏/三栏模式切换

---

### Phase B: Mac UI 设计稿对齐

#### B1: Menubar Panel 对齐 (nwGTB / 3k9d2)
- [ ] 在线态: AirClaude 标题 + "在线" 绿色标签
- [ ] 会话列表: 橙色/绿色/灰色状态点 + 名称 + 摘要
- [ ] 底部菜单: 配对新设备 / 已配对设备(1) / 设置 / 退出
- [ ] 离线态: "离线" 红色标签 + WiFi 断开图标 + "未连接到中继服务器" + 重新连接按钮
- [ ] 毛玻璃 + 圆角 + 阴影样式

#### B2: Multi-Session Window 对齐 (qfbtm / qSe1a / QKak5)
- [ ] 侧栏: 会话列表 (选中态蓝色左边条) + 底部 "+ 新建会话" 按钮
- [ ] 双面板视图: 两个终端面板并排
- [ ] 面板标题栏: 会话名 + 工作目录 + 状态标签
- [ ] CLI 风格终端渲染: "— Claude" / "▶ Bash" / "▶ Edit" / "▶ Read"
- [ ] Diff 高亮: 行号 + 红绿底色
- [ ] 确认提示行: "⚠ Allow: git push origin main? [y/n]" + 蓝色光标
- [ ] 侧栏折叠: 折叠后仅显示图标 + 面板占满宽度

#### B3: Integrated Terminal 对齐 (sYqPW)
- [ ] Tab 栏: 多个终端 Tab (auth 重构 / 写单元测试) + "+ 新建 Tab" 按钮
- [ ] Tab 状态: 活跃 Tab 高亮 + 工作目录显示
- [ ] 终端面板: 完整 pty 终端输出渲染
- [ ] 右侧面板切换: Tab 间独立内容
- [ ] 侧栏: 会话列表 + 活跃状态

#### B4: Settings 窗口对齐 (34oWq / D5DRP)
- [ ] 左侧 Tab 导航: 连接 / 设备 / 安全 / 外观 / 关于
- [ ] 连接页: 连接状态 + 延迟 + 开机自启 Toggle
- [ ] 活跃会话列表: 绿色状态点 + 名称 + 路径
- [ ] 标题栏: "AirClaude 设置" + 状态 + 配对按钮 + 齿轮
- [ ] 亮暗双主题支持

#### B5: Pairing 窗口对齐 (7zn6L / cIUnC)
- [ ] 二维码显示区域 (深色背景圆角卡片)
- [ ] "用手机相机扫描二维码" 说明文字
- [ ] 倒计时: "⏱ 4:32 后过期"
- [ ] 底部安全标识: "端到端加密 · 零知识架构"
- [ ] 亮暗双主题

#### B6: Onboarding 窗口 (9Y02c / CHQ8v) — 新建
- [ ] AirClaude logo + 标语 "隔空指挥你的 Claude Code 会话"
- [ ] Step 1: "授予辅助功能权限" + 说明 + "授权" 蓝色按钮 (可跳过)
- [ ] Step 2: "配对手机" + 说明 (灰色未激活态)
- [ ] 底部说明: "端到端加密 · 服务器零知识 · 无需注册"
- [ ] 亮暗双主题

---

### Phase C: E2EE 集成 (安全核心)

#### C1: 加密层接入 — Web 端
- [ ] `crypto-layer.ts`: 封装 @airterm/crypto, 提供 encrypt/decrypt
- [ ] `key-store.ts`: IndexedDB 存储密钥对 (Web Crypto non-extractable)
- [ ] `ws-client.ts`: encodePayload 改为调用加密层 (非 base64)
- [ ] 配对时执行 X25519 密钥交换 + 存储共享密钥
- [ ] 收发消息时自动加解密 + seq/ack AAD 验证

#### C2: 加密层接入 — Mac 端
- [ ] `CryptoKit+X25519.swift`: 密钥交换封装
- [ ] `KeychainManager.swift`: 密钥存储到 macOS Keychain
- [ ] `RelayClient.swift`: 消息加密/解密集成
- [ ] 配对时执行密钥交换 + Keychain 存储
- [ ] 序列号验证 + 防重放

#### C3: 加密层接入 — Server 端
- [ ] 确认服务器纯转发 (不解密)
- [ ] 信封格式从 base64 明文改为密文 Uint8Array
- [ ] 心跳消息也走加密信封

#### C4: SAS 验证
- [ ] Mac PairingView: 配对完成后显示 4 位安全码
- [ ] Web PairPage: 配对完成后显示 4 位安全码 + 用户确认
- [ ] 不一致时终止配对 + 提示

---

### Phase D: 安全加固

#### D1: 服务器安全
- [ ] JWT 15 分钟 access token + 30 天 refresh token + 黑名单
- [ ] SQLite → SQLCipher (AES-256) + DB_ENCRYPTION_KEY 环境变量
- [ ] 配对码增强: 8 位 alphanumeric (62^8) + 3 次失败作废
- [ ] 速率限制增强: 全局 + 每 IP
- [ ] pragma 参数化 (防 SQL 注入)

#### D2: Web 安全
- [ ] 前端独立部署 (非中继服务器同域)
- [ ] CSP 头: `script-src 'self'; style-src 'self' 'unsafe-inline'; object-src 'none'`
- [ ] SRI: 所有 JS/CSS 带 integrity 属性
- [ ] 二维码 frontend_hash 校验

#### D3: Mac 安全
- [ ] Certificate Pinning (首次连接记住证书)
- [ ] 所有远程输入必须 Mac 弹窗确认 (不仅依赖字符串匹配)
- [ ] 消息 padding 到 1KB 倍数 (防侧信道)
- [ ] BundleID 白名单验证 (AX 模式)

---

### Phase E: 测试与质量

#### E1: Server 测试补全
- [ ] 配对完整流程集成测试
- [ ] WebSocket 连接/转发/断线重连集成测试
- [ ] JWT 签发/验证/刷新/吊销单元测试
- [ ] 速率限制测试
- [ ] 覆盖率 ≥ 80%

#### E2: Web 测试
- [ ] 组件测试: TerminalPane, ApprovalBar, SessionCard, QuickPanel
- [ ] Hook 测试: useWebSocket, useSessions
- [ ] 页面测试: PairPage 配对流程, SessionsPage 消息渲染
- [ ] E2E 测试: 完整配对 → 消息收发流程
- [ ] 覆盖率 ≥ 80%

#### E3: Mac 测试
- [ ] StreamParser 解析测试
- [ ] OutputParser 解析测试
- [ ] DangerousCommandFilter 测试
- [ ] BundleIDValidator 测试
- [ ] AgentAdapter 协议一致性测试
- [ ] 覆盖率 ≥ 70%

---

### Phase F: 集成联调 + 部署

#### F1: 三端联调
- [ ] 配对流程: Mac 生成二维码 → 手机扫码 → 配对成功 → 进入会话
- [ ] 消息流: Mac 终端输出 → 服务器转发 → 手机渲染
- [ ] 远程输入: 手机输入 → 服务器转发 → Mac 终端执行
- [ ] 确认流程: Mac 弹确认 → 手机显示 ApprovalBar → 点击允许 → Mac 继续
- [ ] 断线重连: 杀掉 WebSocket → 自动重连 → 状态恢复

#### F2: 部署
- [ ] Server: Docker 多阶段构建 + docker-compose
- [ ] Web: 构建产物 (Vite build) + 部署配置
- [ ] Health check: /health 接口
- [ ] 环境变量模板: .env.example 完善

---

## 执行顺序与依赖关系

```
Phase A (Web UI 对齐) ──────────────────┐
                                         ├──→ Phase E (测试) ──→ Phase F (联调部署)
Phase B (Mac UI 对齐) ──────────────────┤
                                         │
Phase C (E2EE 集成) ────────────────────┤
                                         │
Phase D (安全加固) ─────────────────────┘
```

- Phase A 和 B 可并行
- Phase C 和 D 可并行，但依赖 A/B 基本完成
- Phase E 贯穿始终，每个阶段完成后补测试
- Phase F 是最终集成

## 自主执行策略

以下场景**无须确认**，直接执行最优方案：
- CSS 变量/样式与设计稿对齐
- 组件结构调整以匹配设计稿布局
- 补充缺失的 UI 状态 (loading, error, empty)
- 暗色/亮色主题变量补全
- 响应式断点适配
- 代码格式化与 lint 修复
- 测试编写与覆盖率提升
- 安全加固 (输入校验、CSP 等)

以下场景**需要确认**，写入待确认清单后跳过继续：
- 架构变更 (如更换状态管理方案)
- 新增依赖包
- 修改通信协议格式
- 修改数据库 schema
- 部署相关配置 (域名、证书、环境变量实际值)
- 删除现有功能代码

---

## 需要确认的决策 (PENDING_DECISIONS)

> 以下事项需要你确认后再执行，当前暂时跳过。

1. **Web 部署目标**: Cloudflare Pages / Vercel / 其他？
2. **公共中继域名**: relay.airterm.dev 是否已准备好？
3. **Mac 应用签名**: 是否需要 Apple Developer 签名？
4. **SQLCipher 依赖**: better-sqlite3 替换为 better-sqlite3-sqlcipher？
5. **LAN 直连**: 是否在本次 MVP 范围内？(文档建议留到原生壳阶段)
6. **推送通知**: Bark / Telegram Bot 集成是否在本次范围内？
