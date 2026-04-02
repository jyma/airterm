# AirTerm 开发进度

> 最后更新: 2026-04-02
> 分支: master
> 状态: 全部构建通过 / 80 测试通过

---

## 构建状态

| 模块 | 构建 | 测试 |
|------|------|------|
| `packages/crypto` | ✅ | 19/19 ✅ |
| `packages/protocol` | ✅ | 18/18 ✅ |
| `apps/server` | ✅ | 43/43 ✅ (8 E2E 需 server) |
| `apps/web` | ✅ (267KB JS, 24KB CSS gzip) | 待补 Web 组件测试 |
| `apps/mac` | ✅ (Swift build) | Swift 测试待补 |

运行测试: `pnpm test`
运行构建: `pnpm build && swift build`
E2E 测试: `E2E_SERVER_URL=http://your-server pnpm test`

---

## 已完成的工作 (本次会话)

### 修改了 32 个文件, 新增 14 个文件

#### Web 端 (apps/web)
- **globals.css** — 重写色板/字体/动画系统，新增 glass、approval-in、fade-in 动画
- **TerminalPane** — 重写：Markdown 渲染、时间戳、智能滚动(向上停/新消息滚底)、触觉反馈、长输出折叠(>30行)、Diff 文件头、工具卡片折叠、确认栏脉冲动画、中文化
- **TopBar** — 品牌改为 AirClaude，glass 毛玻璃效果，连接状态文字
- **PaneHeader** — 状态药丸(绿/蓝/灰)，返回箭头
- **SessionCard** — 紧凑模式，SVG 警告图标(替代 emoji)
- **MultiPaneView** — activeSessionId 同步，展开/折叠动画，onFocus 选择(防冒泡)
- **InputBar** — placeholder 中文化"输入消息..."，圆角输入框
- **QuickPanel** — 持久化快捷指令支持，触觉反馈
- **SettingsPage** — iOS 分组卡片风格，真实配对日期(pairedAt)，图标返回按钮
- **PairPage** — UA 设备名检测(iPhone/Android/iPad/Browser)，useEffect deps 修复
- **ApprovalBar.tsx** — 已删除(死代码，功能在 TerminalPane 内)
- **useSessions** — events 内存上限 500 条/会话，暴露 clearEvents
- **useWebSocket** — cryptoLayer 参数透传
- **ws-client** — E2EE CryptoLayer 集成(加密/解密切换)
- **storage** — PairingInfo 新增 pairedAt + macPublicKey 字段
- **新文件**: markdown.ts, shortcuts.ts, time.ts
- **新文件**: _headers (CSP/HSTS), _redirects (SPA), manifest.json (PWA)

#### Server 端 (apps/server)
- **index.ts** — 挂载 auth 路由，速率限制中间件(全局100/分+配对10/分)，安全头，结构化日志，优雅关停
- **token.ts / jwt.ts** — timingSafeEqual 修复 HMAC 比较
- **pair.ts** — 输入长度校验，pair code uppercase 归一化，移除 token 泄露
- **e2e.test.ts / e2e-relay.test.ts** — 移除硬编码生产 IP，skipIf 无 server
- **.env.example** — 补全 DB_ENCRYPTION_KEY 等变量
- **新文件**: jwt.test.ts, rate-limit.test.ts, logger.ts

#### Mac 端 (apps/mac)
- **AirTermApp** — 品牌 AirClaude，WiFi 图标按连接态变化，新增 Onboarding/Settings 窗口
- **MenuBarView** — 离线态(WiFi 断开+重连按钮)，首次启动触发 Onboarding，hover 样式
- **SettingsView** — 重写为侧栏导航(连接/设备/安全/外观/关于)，标题栏状态+配对按钮
- **PairingView** — dismissWindow 修复(替代 dismiss)
- **AppState** — pairedDevices 持久化(UserDefaults)，启动恢复连接，needsApproval 重置，公开 sendInputFromUI/sendApprovalFromUI
- **AccessibilityAdapter** — createSession 不再 fatalError
- **新文件**: OnboardingView.swift (首次启动引导)

#### 部署 / CI
- **docker-compose.yml** — 新增 DB_ENCRYPTION_KEY、DOMAIN、日志配置
- **.github/workflows/ci.yml** — 测试 + Cloudflare Pages 自动部署
- **新文件**: packages/protocol/src/__tests__/messages.test.ts, pairing.test.ts

#### 协议 (packages/protocol)
- **pairing.ts** — PairingInfo 新增 macPublicKey (E2EE 密钥交换准备)

---

## 未完成项 (下次继续)

### P0 — 上线前必须

- [ ] **E2EE 激活**: PairPage 中实际调用 createCryptoLayer() + 密钥交换 + SAS 确认 UI
- [ ] **E2EE 激活**: SessionsPage 创建 cryptoLayer 并传入 useWebSocket
- [ ] **E2EE 激活**: Mac PairingView 生成密钥对 + 二维码编码公钥 + SAS 显示
- [ ] **E2EE 激活**: Mac RelayClient 消息加解密
- [ ] **SQLCipher**: 替换 better-sqlite3 为 better-sqlite3-sqlcipher (需 `pnpm add`)
- [ ] **JWT 替换**: pair.ts 改用 jwtService 替代 tokenService (两套系统合并)
- [ ] **Token 自动刷新**: Web 端 401 → refresh → retry 逻辑
- [ ] **SettingsPage 连接状态**: 当前硬编码"已连接"，需传入实际 connectionState
- [ ] **Mac 设备撤销**: SettingsView 中 "撤销" 按钮实际实现
- [ ] **Mac 设置持久化**: dangerBlock/opLog/autoLaunch toggle 绑定 @AppStorage
- [ ] **Mac 服务器 URL**: Settings 自定义服务器地址保存逻辑
- [ ] **Web 测试**: 组件测试 (TerminalPane, SessionCard 等) — 覆盖率目标 80%
- [ ] **App 图标**: icon-192.png / icon-512.png 制作

### P1 — 体验增强

- [ ] **代码语法高亮**: 考虑轻量方案 (Shiki/Prism 或纯 CSS)
- [ ] **搜索输出内容**: TerminalPane 内搜索
- [ ] **下拉刷新**: 会话列表下拉刷新
- [ ] **会话历史**: 已结束会话快照持久化
- [ ] **Mac Tab 栏**: 多内置终端 Tab UI
- [ ] **Mac 侧栏折叠动画**: 可拖拽分割线
- [ ] **Mac 危险命令弹窗**: AlertDialog 替代静默拦截
- [ ] **Mac 终端颜色**: ANSI escape code 渲染
- [ ] **Mac Notification Center**: 会话结束通知
- [ ] **RelayClient 线程安全**: 改用 actor 或 NSLock

### P2 — 部署相关

- [ ] Cloudflare API Token 配置 (CLOUDFLARE_API_TOKEN secret)
- [ ] 服务器实际部署 (relay.airterm.ai)
- [ ] Let's Encrypt 证书自动化
- [ ] Mac 应用签名决定

---

## 决策记录

| 决策项 | 结论 | 日期 |
|--------|------|------|
| 前端部署 | Cloudflare Pages | 2026-04-01 |
| 域名 | airterm.ai | 2026-04-01 |
| Mac 签名 | 最后决定 | 2026-04-01 |
| SQLCipher | 需要 | 2026-04-01 |
| LAN 直连 | 不在本次范围 | 2026-04-01 |
| 推送通知 | 下个版本 | 2026-04-01 |

---

## 快速恢复开发

```bash
# 安装依赖
pnpm install

# 构建全部
pnpm build

# 构建 Mac
cd apps/mac && swift build

# 运行测试
pnpm test

# E2E 测试 (需要运行中的 server)
E2E_SERVER_URL=http://localhost:3000 pnpm test

# 开发模式
pnpm dev:server  # 启动中继服务器 :3000
pnpm dev:web     # 启动 Web 前端 :5173
```
