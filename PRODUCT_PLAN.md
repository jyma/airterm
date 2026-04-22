# AirTerm 正式产品计划

> 目标：交付一个完整、体验优秀的正式产品，而非 MVP
> 域名：airterm.ai
> 前端：Cloudflare Pages
> 更新日期：2026-04-01

---

## 决策记录

| 决策项 | 结论 |
|--------|------|
| 前端部署 | Cloudflare Pages |
| 域名 | airterm.ai |
| Mac 签名 | 最后决定 |
| SQLCipher 数据库加密 | 需要 |
| LAN 直连 | 不在本次范围 |
| 推送通知 | 下个版本 |

---

## 当前完成状态

| 模块 | 构建 | 测试 | 状态 |
|------|------|------|------|
| Server (Hono + SQLite) | ✅ | 88/88 ✅ | 核心完成 |
| Web (React + Tailwind) | ✅ | - | UI 完成，需打磨 |
| Mac (Swift + SwiftUI) | ✅ | Swift 测试待补 | 功能完成，需打磨 |
| Crypto (X25519 + ChaCha20) | ✅ | 19/19 ✅ | 完成 |
| Protocol (TypeScript types) | ✅ | 18/18 ✅ | 完成 |

---

## 产品打磨清单

以下是从 MVP 到正式产品需要完善的所有细节，按优先级排序。

### P0：必须完成（上线前）

#### 1. E2EE 全链路加密激活
- [ ] 配对时执行 X25519 密钥交换（Web PairPage + Mac PairingView）
- [ ] 配对完成后 SAS 安全码校验（4 位数字双方确认）
- [ ] WebSocket 消息自动加密/解密（当前明文 base64）
- [ ] 心跳消息也走加密信封
- [ ] Mac Keychain 存储私钥
- [ ] Web IndexedDB 存储密钥

#### 2. SQLCipher 数据库加密
- [ ] 替换 better-sqlite3 为 better-sqlite3-sqlcipher
- [ ] 启动时从环境变量读取 DB_ENCRYPTION_KEY
- [ ] 缺失密钥时拒绝启动并报错
- [ ] 迁移脚本（现有明文 DB → 加密 DB）

#### 3. Web 交互体验打磨
- [ ] 消息气泡：添加时间戳显示（设计稿中有 "10:32"）
- [ ] 工具卡片：Read 显示文件名 + 行数 + [▼] 折叠指示
- [ ] Diff 块：文件头显示文件路径 + bg-tertiary 背景
- [ ] 确认栏：黄色边框脉冲动画吸引注意力
- [ ] 输入栏：placeholder 中文化 "输入消息..."
- [ ] 快捷指令：支持自定义（从设置页管理）
- [ ] 会话卡片：显示终端来源（iTerm2 / Terminal）和时间（"刚刚"、"2分钟前"）
- [ ] 空状态：更友好的引导提示
- [ ] 滚动行为：新消息到达时自动滚到底部（已实现），用户向上滚动时停止自动滚动
- [ ] 长按/双击消息可复制文本
- [ ] 页面转场动画（列表→详情 slide-in-right）
- [ ] 下拉刷新会话列表
- [ ] 触觉反馈：按钮点击时 vibrate

#### 4. Web 安全加固
- [ ] CSP 头配置（Cloudflare Pages _headers 文件）
- [ ] SRI：构建产物自动加 integrity 属性
- [ ] 前端独立域名部署（web.airterm.ai 或 app.airterm.ai）
- [ ] 二维码包含前端 JS 哈希（frontend_hash），手机端校验
- [ ] 配对码增强为 8 位（62^8 熵）

#### 5. Server 生产化
- [ ] JWT 替换简单 token（配对路由改用 jwtService）
- [ ] Access token 15 分钟 + Refresh token 30 天
- [ ] Token 自动刷新逻辑（Web 端 401 → refresh → retry）
- [ ] SQLCipher pragma 参数化
- [ ] 速率限制：WebSocket 连接也限速
- [ ] 日志系统（pino/winston）
- [ ] 错误监控集成准备（Sentry hook）
- [ ] Docker 健康检查优化
- [ ] Graceful shutdown 完善（等待 WebSocket 断开）

#### 6. Mac 交互体验打磨
- [ ] 菜单栏面板：hover 高亮效果
- [ ] 主窗口：侧栏折叠/展开动画
- [ ] 主窗口：双面板拖拽分割线
- [ ] 主窗口：Tab 栏（多个内置终端 Tab）
- [ ] 配对窗口：配对成功后显示绿色对勾 + 自动关闭
- [ ] Onboarding：首次启动自动弹出
- [ ] 设置窗口：连接延迟实时显示
- [ ] 设置窗口：设备撤销功能实现
- [ ] 危险命令拦截：弹窗确认 UI（不仅静默拦截）
- [ ] 内置终端：完整终端模拟（支持颜色、光标定位）
- [ ] 会话结束通知（Notification Center）

#### 7. Cloudflare Pages 部署
- [ ] wrangler.toml 配置
- [ ] _headers 文件（CSP、HSTS、安全头）
- [ ] _redirects 文件（SPA fallback）
- [ ] 自定义域名 airterm.ai 绑定
- [ ] GitHub Actions CI/CD（push → deploy）

#### 8. Docker 部署
- [ ] Dockerfile 多阶段构建优化
- [ ] docker-compose.yml 完善（环境变量、volume、healthcheck）
- [ ] .env.example 完善所有必需变量
- [ ] 中继服务器域名配置（relay.airterm.ai）
- [ ] Let's Encrypt 自动证书
- [ ] 部署文档更新

### P1：体验增强（上线后快速迭代）

#### 9. 智能输出解析增强
- [ ] Markdown 渲染（Claude 消息中的粗体、链接、列表）
- [ ] 代码块语法高亮（Prism.js / Shiki）
- [ ] 大输出自动折叠（>50 行折叠，显示摘要）
- [ ] Bash 输出可折叠展开
- [ ] 搜索输出内容

#### 10. PWA 支持
- [ ] manifest.json（app 名称、图标、主题色）
- [ ] Service Worker（离线缓存 shell）
- [ ] "添加到主屏幕" 提示
- [ ] 启动画面

#### 11. 多设备支持
- [ ] 一台 Mac 配对多部手机
- [ ] 同时在线时消息同步推送
- [ ] 设备管理页可撤销单个设备

#### 12. 会话历史
- [ ] 已结束会话保留最后输出快照
- [ ] 历史会话列表（按时间排序）
- [ ] 历史详情查看

---

## 执行顺序

```
阶段一（立即执行）:
  ├─ #1 E2EE 全链路激活
  ├─ #2 SQLCipher
  ├─ #3 Web 交互打磨
  └─ #4 Web 安全加固

阶段二（并行执行）:
  ├─ #5 Server 生产化
  ├─ #6 Mac 交互打磨
  ├─ #7 Cloudflare 部署
  └─ #8 Docker 部署

阶段三（上线后迭代）:
  ├─ #9 输出解析增强
  ├─ #10 PWA
  ├─ #11 多设备
  └─ #12 会话历史
```

---

## 质量标准

| 指标 | 目标 |
|------|------|
| Web 首次加载 | < 2 秒 |
| 构建产物大小 | < 300KB gzip |
| 测试覆盖率 | ≥ 80% |
| Lighthouse 评分 | ≥ 90 |
| 无障碍 (WCAG AA) | 对比度 ≥ 4.5:1 |
| TypeScript strict | 无 any |
| 零 console.log | 生产构建 |
| 端到端加密 | 全部消息 |
