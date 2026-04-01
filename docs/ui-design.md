# UI 设计规范

## 设计理念

为程序员打造的远程控制台 — 信息密度高、视觉干净、操作精准。

```
设计原则:
  1. 内容优先 — 终端输出是主角，UI 是配角
  2. 亮暗双模 — 跟随系统或手动切换，两套完整色板
  3. 等宽字体 — 代码和终端内容必须对齐
  4. 即时反馈 — 每个操作都有视觉/触觉响应
  5. 单手操作 — 手机端核心操作拇指可达
  6. 多窗口 — 同时查看多个会话，快速切换
```

---

## 色彩体系

灵感来源：GitHub Dark / Light、VS Code、Linear。

### 暗色模式 (Dark)

```
背景层
  bg-primary     #0d1117    页面背景
  bg-secondary   #161b22    卡片、气泡背景
  bg-tertiary    #21262d    输入框、分隔线、折叠区域
  bg-overlay     #1c2129    弹窗遮罩底层

文字层
  text-primary   #f0f6fc    正文
  text-secondary #8b949e    次要说明
  text-muted     #484f58    占位符、时间戳

语义色 (亮暗通用)
  accent-green   #3fb950    成功、添加、运行中、允许按钮
  accent-red     #f85149    错误、删除、危险操作
  accent-yellow  #d29922    警告、需要确认
  accent-blue    #58a6ff    链接、强调、发送按钮
  accent-purple  #bc8cff    搜索相关
  accent-cyan    #39d2c0    Bash 命令

Diff 色
  diff-add-bg    rgba(63, 185, 80, 0.15)
  diff-add-text  #3fb950
  diff-del-bg    rgba(248, 81, 73, 0.15)
  diff-del-text  #f85149
```

### 亮色模式 (Light)

```
背景层
  bg-primary     #ffffff    页面背景
  bg-secondary   #f6f8fa    卡片、气泡背景
  bg-tertiary    #d0d7de    输入框、分隔线
  bg-overlay     #e8ecf0    弹窗遮罩底层

文字层
  text-primary   #1f2328    正文
  text-secondary #656d76    次要说明
  text-muted     #8c959f    占位符、时间戳

语义色 (亮色微调)
  accent-green   #1a7f37    成功、添加
  accent-red     #d1242f    错误、删除
  accent-yellow  #9a6700    警告
  accent-blue    #0969da    链接、强调
  accent-purple  #8250df    搜索
  accent-cyan    #1b7c83    Bash

Diff 色
  diff-add-bg    rgba(26, 127, 55, 0.10)
  diff-add-text  #1a7f37
  diff-del-bg    rgba(209, 36, 47, 0.10)
  diff-del-text  #d1242f
```

### CSS 变量实现

```css
/* 默认暗色 */
:root {
  --bg-primary: #0d1117;
  --bg-secondary: #161b22;
  --bg-tertiary: #21262d;
  --bg-overlay: #1c2129;
  --text-primary: #f0f6fc;
  --text-secondary: #8b949e;
  --text-muted: #484f58;
  --accent-green: #3fb950;
  --accent-red: #f85149;
  --accent-yellow: #d29922;
  --accent-blue: #58a6ff;
  --accent-purple: #bc8cff;
  --accent-cyan: #39d2c0;
  --diff-add-bg: rgba(63, 185, 80, 0.15);
  --diff-add-text: #3fb950;
  --diff-del-bg: rgba(248, 81, 73, 0.15);
  --diff-del-text: #f85149;
  --border: #30363d;
  --shadow: 0 2px 8px rgba(0, 0, 0, 0.3);
  --card-radius: 12px;
}

/* 亮色模式 */
:root[data-theme="light"] {
  --bg-primary: #ffffff;
  --bg-secondary: #f6f8fa;
  --bg-tertiary: #d0d7de;
  --bg-overlay: #e8ecf0;
  --text-primary: #1f2328;
  --text-secondary: #656d76;
  --text-muted: #8c959f;
  --accent-green: #1a7f37;
  --accent-red: #d1242f;
  --accent-yellow: #9a6700;
  --accent-blue: #0969da;
  --accent-purple: #8250df;
  --accent-cyan: #1b7c83;
  --diff-add-bg: rgba(26, 127, 55, 0.10);
  --diff-add-text: #1a7f37;
  --diff-del-bg: rgba(209, 36, 47, 0.10);
  --diff-del-text: #d1242f;
  --border: #d0d7de;
  --shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
}

/* 跟随系统 */
@media (prefers-color-scheme: light) {
  :root:not([data-theme="dark"]) {
    /* 同上亮色变量 */
  }
}
```

### 主题切换逻辑

```typescript
type Theme = "system" | "dark" | "light"

function setTheme(theme: Theme) {
  if (theme === "system") {
    document.documentElement.removeAttribute("data-theme")
  } else {
    document.documentElement.setAttribute("data-theme", theme)
  }
  localStorage.setItem("airterm-theme", theme)
}

// 初始化
const saved = localStorage.getItem("airterm-theme") as Theme | null
setTheme(saved ?? "system")
```

---

## 字体

```css
:root {
  /* 代码/终端内容 */
  --font-mono: "JetBrains Mono", "Fira Code", "SF Mono",
    "Cascadia Code", "Consolas", ui-monospace, monospace;

  /* UI 元素 */
  --font-ui: -apple-system, BlinkMacSystemFont, "SF Pro Text",
    "Segoe UI", system-ui, sans-serif;

  /* 字号 */
  --text-xs: 11px;
  --text-sm: 13px;
  --text-base: 14px;
  --text-lg: 16px;
  --text-xl: 18px;
}
```

---

## 页面结构与布局

### 整体页面关系

```
┌─────────────────────────────────────┐
│            会话列表页                 │  ← 首页
│   点击某个会话卡片                    │
│            ↓                        │
│        会话详情页                     │  ← 单会话全屏查看
│            ↓                        │
│        设置页                        │  ← 主题切换、设备管理
└─────────────────────────────────────┘

大屏 (≥ 769px):
┌────────────┬────────────────────────┐
│  会话列表    │      会话详情           │  ← 左右分栏同时显示
│  (侧栏)     │                       │
└────────────┴────────────────────────┘
```

---

## 页面设计：会话列表

### 手机端 (< 769px)

```
暗色                               亮色
┌─────────────────────────┐       ┌─────────────────────────┐
│░░░░░░░░░░░░░░░░░░░░░░░░░│       │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
│ AirTerm      🌙  ⚙️  │       │ AirTerm      ☀️  ⚙️  │
│─────────────────────────│       │─────────────────────────│
│                         │       │                         │
│ 3 个会话 · 2 运行中      │       │ 3 个会话 · 2 运行中      │
│                         │       │                         │
│ ┌─────────────────────┐ │       │ ┌─────────────────────┐ │
│ │ ● auth 重构       ⚠️ │ │       │ │ ● auth 重构       ⚠️ │ │
│ │ ~/projects/myapp     │ │       │ │ ~/projects/myapp     │ │
│ │ 等待确认: npm test   │ │       │ │ 等待确认: npm test   │ │
│ │ iTerm2 · 刚刚        │ │       │ │ iTerm2 · 刚刚        │ │
│ └─────────────────────┘ │       │ └─────────────────────┘ │
│                         │       │                         │
│ ┌─────────────────────┐ │       │ ┌─────────────────────┐ │
│ │ ● 写单元测试         │ │       │ │ ● 写单元测试         │ │
│ │ ~/projects/api       │ │       │ │ ~/projects/api       │ │
│ │ 正在执行 Bash...     │ │       │ │ 正在执行 Bash...     │ │
│ │ Terminal · 2 分钟前   │ │       │ │ Terminal · 2 分钟前   │ │
│ └─────────────────────┘ │       │ └─────────────────────┘ │
│                         │       │                         │
│ ┌─────────────────────┐ │       │ ┌─────────────────────┐ │
│ │ ○ 修复登录 bug       │ │       │ │ ○ 修复登录 bug       │ │
│ │ ~/projects/web       │ │       │ │ ~/projects/web       │ │
│ │ 会话已结束            │ │       │ │ 会话已结束            │ │
│ │ iTerm2 · 20 分钟前   │ │       │ │ iTerm2 · 20 分钟前   │ │
│ └─────────────────────┘ │       │ └─────────────────────┘ │
│                         │       │                         │
│                         │       │                         │
│                         │       │                         │
└─────────────────────────┘       └─────────────────────────┘
 bg-primary                        bg-primary (#fff)
 卡片 bg-secondary                  卡片 bg-secondary (#f6f8fa)
 文字 text-primary                  文字 text-primary (#1f2328)
```

**顶栏：**
- 左侧：AirTerm 标题
- 右侧：主题切换按钮（🌙/☀️）+ 设置齿轮
- 毛玻璃效果 `backdrop-filter: blur(12px)`
- 固定在顶部

**统计栏：**
- "3 个会话 · 2 运行中"
- `text-secondary` 色

**会话卡片：**
- 需要确认的会话置顶，右上角 ⚠️ 图标
- 运行中 ● 绿色脉冲动画
- 已结束 ○ `text-muted` 色
- 卡片间距 12px
- 卡片内边距 16px

**交互：**
- 点击进入详情
- 左滑显示操作（发消息 / 终止）
- 下拉刷新

---

## 页面设计：会话详情

### 手机端 (< 769px)

```
暗色
┌─────────────────────────┐
│ ← auth 重构      ● 运行中│  ← 顶栏
│─────────────────────────│
│                         │
│ ┌ Claude ─────────────┐ │  ← 消息气泡
│ │ 我来检查 `auth.ts`   │ │
│ │ 中的安全问题。        │ │
│ └──────────── 10:32 ──┘ │
│                         │
│ ┌ Read ───────────────┐ │  ← 工具卡片 (蓝色左边条)
│ │ 📄 src/auth.ts       │ │
│ │ 142 行          [▼]  │ │  ← 可折叠
│ └─────────────────────┘ │
│                         │
│ ┌ Edit ───────────────┐ │  ← Diff 卡片 (黄色左边条)
│ │ src/auth.ts          │ │
│ │ 42 │- const token =  │ │  ← 红底删除行
│ │    │  "hardcoded"    │ │
│ │ 42 │+ const token =  │ │  ← 绿底添加行
│ │    │  process.env..  │ │
│ └─────────────────────┘ │
│                         │
│ ┌ Claude ─────────────┐ │
│ │ 已修复硬编码 token。  │ │
│ │ 现在运行测试确认。    │ │
│ └──────────── 10:33 ──┘ │
│                         │
│ ┌ Bash ───────────────┐ │  ← 命令卡片 (青色左边条)
│ │ $ npm test           │ │
│ │ ┌ 输出 ────────────┐ │ │
│ │ │ PASS auth.test   │ │ │
│ │ │ 3 passed         │ │ │
│ │ └──────────────────┘ │ │
│ └─────────────────────┘ │
│                         │
│┌──────────────────────┐ │  ← 确认操作栏 (黄色边框)
││ ⚠️ 需要确认            │ │
││                       │ │
││ 允许执行 Bash:         │ │
││ ┌───────────────────┐ │ │
││ │ git push origin   │ │ │  ← bg-tertiary 底色
││ │ main              │ │ │     等宽字体
││ └───────────────────┘ │ │
││                       │ │
││ ┌────────┐ ┌────────┐ │ │
││ │  拒绝   │ │ ✅ 允许 │ │ │  ← 48px 高, 手指友好
││ └────────┘ └────────┘ │ │
│└──────────────────────┘ │
│                         │
├─────────────────────────┤  ← 底部固定区域
│ ┌─────────────────┐ [▶] │  ← 输入栏
│ │ 输入消息...       │     │
│ └─────────────────┘     │
│ /commit /review 继续 ⛔  │  ← 快捷指令 pill 横滚
└─────────────────────────┘
```

---

## 页面设计：多窗口视图

### 大屏 (≥ 769px) — 左右分栏

```
┌──────────────────────────────────────────────────────────────┐
│ AirTerm                              🌙  ⚙️  连接状态: ● │
├──────────────┬───────────────────────────────────────────────┤
│              │                                               │
│  会话列表     │  auth 重构                          ● 运行中  │
│              │                                               │
│ ┌──────────┐ │  ┌ Claude ─────────────────────────────────┐  │
│ │● auth重构 │ │  │ 我来检查 `auth.ts` 中的安全问题。         │  │
│ │  等待确认 ⚠│ │  └─────────────────────────────── 10:32 ──┘  │
│ └──────────┘ │                                               │
│              │  ┌ Read ───────────────────────────────────┐  │
│ ┌──────────┐ │  │ 📄 src/auth.ts · 142 行             [▼] │  │
│ │● 写测试   │ │  └───────────────────────────────────────┘  │
│ │  执行中   │ │                                               │
│ └──────────┘ │  ┌ Edit ───────────────────────────────────┐  │
│              │  │ src/auth.ts                              │  │
│ ┌──────────┐ │  │  42 │ - const token = "hardcoded"       │  │
│ │○ 修bug   │ │  │  42 │ + const token = process.env.TOK   │  │
│ │  已结束   │ │  └───────────────────────────────────────┘  │
│ └──────────┘ │                                               │
│              │  ┌ ⚠️ 需要确认 ─────────────────────────────┐  │
│              │  │ Bash: git push origin main               │  │
│              │  │                                          │  │
│              │  │       [ 拒绝 ]       [ ✅ 允许 ]          │  │
│              │  └──────────────────────────────────────────┘  │
│              │                                               │
│              │  ┌───────────────────────────────────┐  [▶]   │
│              │  │ 输入消息...                         │        │
│              │  └───────────────────────────────────┘        │
│              │  /commit  /review  继续  ⛔                    │
├──────────────┴───────────────────────────────────────────────┤
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**侧栏行为：**
- 宽度固定 280px
- 当前选中会话高亮（`accent-blue` 左边条）
- 每个卡片显示：状态点、名称、摘要、⚠️ 图标
- 点击切换右侧详情

### 大屏 — 多窗口分屏

在侧栏顶部提供布局切换：

```
布局模式: [列表] [双栏] [三栏]
```

**双栏模式 — 同时查看两个会话：**

```
┌──────────┬─────────────────────────┬─────────────────────────┐
│ 会话列表  │ auth 重构        ● 运行中│ 写单元测试       ● 运行中 │
│          │                         │                         │
│ ● auth重构│ Claude:                 │ Claude:                 │
│   ⚠️     │ 发现安全问题 3 个        │ 开始编写 user.test.ts   │
│          │                         │                         │
│ ● 写测试  │ Edit: auth.ts           │ Bash:                   │
│          │ - token = "hard.."      │ $ npm test              │
│ ○ 修bug  │ + token = env.TOK       │ PASS user.test.ts       │
│          │                         │ 5 passed                │
│          │ ⚠️ 需要确认              │                         │
│          │ git push origin main    │ Claude:                 │
│          │ [拒绝]    [✅ 允许]      │ 全部测试通过。            │
│          │                         │                         │
│          │ [输入消息...]        [▶] │ [输入消息...]        [▶] │
│          │ /commit /review 继续    │ /commit /review 继续    │
└──────────┴─────────────────────────┴─────────────────────────┘
```

**三栏模式 — 同时查看三个会话：**

```
┌──────┬──────────────────┬──────────────────┬──────────────────┐
│列表   │ auth 重构  ● ⚠️  │ 写测试     ●     │ 修 bug    ○     │
│      │                  │                  │                  │
│● auth│ 发现安全问题      │ npm test         │ 会话已结束       │
│● 测试│ - token="hard"   │ PASS 5/5         │                  │
│○ bug │ + token=env.TOK  │                  │ 最后输出:         │
│      │                  │ 全部通过 ✓        │ 已提交修复        │
│      │ ⚠️ git push?     │                  │                  │
│      │ [拒绝] [允许]     │ [输入...]    [▶] │                  │
│      │ [输入...]    [▶] │                  │                  │
└──────┴──────────────────┴──────────────────┴──────────────────┘
```

---

## 页面设计：设置页

```
┌─────────────────────────┐
│ ← 设置                  │
│─────────────────────────│
│                         │
│ 外观                     │
│ ┌─────────────────────┐ │
│ │ 主题     [系统 ▼]    │ │  ← 下拉: 系统 / 暗色 / 亮色
│ └─────────────────────┘ │
│                         │
│ 连接                     │
│ ┌─────────────────────┐ │
│ │ 服务器  airterm.io │ │
│ │ 状态    ● 已连接     │ │
│ └─────────────────────┘ │
│                         │
│ 已配对设备               │
│ ┌─────────────────────┐ │
│ │ 📱 My iPhone         │ │
│ │ 配对于 3月28日        │ │
│ │ 最后活跃: 刚刚        │ │
│ │              [撤销]  │ │  ← 红色文字
│ └─────────────────────┘ │
│                         │
│ ┌─────────────────────┐ │
│ │ [+ 配对新设备]        │ │  ← accent-blue 描边按钮
│ └─────────────────────┘ │
│                         │
│ 快捷指令                 │
│ ┌─────────────────────┐ │
│ │ /commit  [编辑] [删除]│ │
│ │ /review  [编辑] [删除]│ │
│ │ 继续     [编辑] [删除]│ │
│ │ [+ 添加自定义指令]    │ │
│ └─────────────────────┘ │
│                         │
│ 安全                     │
│ ┌─────────────────────┐ │
│ │ 高危命令拦截  [开启]  │ │
│ │ 操作日志     [开启]  │ │
│ │ 自动锁定 30 分钟 [▼] │ │
│ └─────────────────────┘ │
│                         │
│ 关于                     │
│ AirTerm v0.1.0        │
│                         │
└─────────────────────────┘
```

---

## 组件样式规范

### 消息气泡 (ChatBubble)

```css
.chat-bubble {
  background: var(--bg-secondary);
  border-radius: var(--card-radius);
  padding: 12px 16px;
  font-family: var(--font-ui);
  font-size: var(--text-base);
  color: var(--text-primary);
  line-height: 1.6;
}
.chat-bubble code {
  font-family: var(--font-mono);
  background: var(--bg-tertiary);
  padding: 2px 6px;
  border-radius: 4px;
  font-size: var(--text-sm);
}
.chat-bubble .timestamp {
  font-size: var(--text-xs);
  color: var(--text-muted);
  margin-top: 6px;
}
```

### Diff 查看器 (DiffViewer)

```css
.diff-viewer {
  font-family: var(--font-mono);
  font-size: var(--text-sm);
  border-radius: 8px;
  overflow: hidden;
  border: 1px solid var(--border);
}
.diff-file-header {
  background: var(--bg-tertiary);
  padding: 8px 12px;
  font-size: var(--text-xs);
  color: var(--text-secondary);
  border-bottom: 1px solid var(--border);
}
.diff-line-add {
  background: var(--diff-add-bg);
  color: var(--diff-add-text);
}
.diff-line-remove {
  background: var(--diff-del-bg);
  color: var(--diff-del-text);
}
.diff-line-number {
  color: var(--text-muted);
  user-select: none;
  min-width: 40px;
  text-align: right;
  padding-right: 12px;
}
```

### 工具调用卡片 (ToolCard)

```css
.tool-card {
  background: var(--bg-secondary);
  border-radius: 8px;
  border-left: 3px solid var(--accent-blue);
  overflow: hidden;
}
.tool-card-header {
  padding: 8px 12px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-family: var(--font-mono);
  font-size: var(--text-sm);
  color: var(--text-secondary);
  cursor: pointer;
}
.tool-card-header .collapse-icon {
  transition: transform var(--duration-fast);
}
.tool-card-header[aria-expanded="false"] .collapse-icon {
  transform: rotate(-90deg);
}
.tool-card-body {
  padding: 0 12px 12px;
  font-family: var(--font-mono);
  font-size: var(--text-sm);
}

/* 不同工具类型的左侧色条 */
.tool-card[data-tool="Bash"]  { border-left-color: var(--accent-cyan); }
.tool-card[data-tool="Edit"]  { border-left-color: var(--accent-yellow); }
.tool-card[data-tool="Read"]  { border-left-color: var(--accent-blue); }
.tool-card[data-tool="Write"] { border-left-color: var(--accent-green); }
.tool-card[data-tool="Grep"]  { border-left-color: var(--accent-purple); }
```

### 确认操作栏 (ApprovalBar)

```css
.approval-bar {
  background: var(--bg-secondary);
  border: 1px solid var(--accent-yellow);
  border-radius: var(--card-radius);
  padding: 16px;
}
.approval-command {
  font-family: var(--font-mono);
  font-size: var(--text-sm);
  background: var(--bg-tertiary);
  padding: 8px 12px;
  border-radius: 6px;
  margin: 8px 0 16px;
  color: var(--text-primary);
}
.approval-actions {
  display: flex;
  gap: 12px;
}
.btn-deny {
  flex: 1;
  height: 48px;
  border: 1px solid var(--border);
  border-radius: 10px;
  color: var(--text-primary);
  background: transparent;
  font-size: var(--text-base);
  font-family: var(--font-ui);
  cursor: pointer;
}
.btn-allow {
  flex: 1;
  height: 48px;
  border: none;
  border-radius: 10px;
  color: #ffffff;
  background: var(--accent-green);
  font-size: var(--text-base);
  font-weight: 600;
  font-family: var(--font-ui);
  cursor: pointer;
}
.btn-deny:active,
.btn-allow:active {
  transform: scale(0.96);
  opacity: 0.8;
}
```

### 快捷指令 (QuickPanel)

```css
.quick-panel {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  padding: 8px 16px;
  scrollbar-width: none;
  -webkit-overflow-scrolling: touch;
}
.quick-panel::-webkit-scrollbar {
  display: none;
}
.quick-pill {
  flex-shrink: 0;
  padding: 6px 14px;
  border-radius: 16px;
  background: var(--bg-tertiary);
  color: var(--text-secondary);
  font-family: var(--font-mono);
  font-size: var(--text-sm);
  white-space: nowrap;
  cursor: pointer;
  transition: all var(--duration-fast);
  border: none;
}
.quick-pill:active {
  background: var(--accent-blue);
  color: #ffffff;
}
.quick-pill[data-danger] {
  color: var(--accent-red);
}
```

### 输入栏 (InputBar)

```css
.input-bar {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  background: var(--bg-primary);
  border-top: 1px solid var(--border);
  padding: 8px 16px;
  padding-bottom: calc(8px + env(safe-area-inset-bottom, 0px));
}
.input-row {
  display: flex;
  gap: 8px;
  align-items: center;
}
.input-field {
  flex: 1;
  background: var(--bg-tertiary);
  border: 1px solid transparent;
  border-radius: 20px;
  padding: 10px 16px;
  color: var(--text-primary);
  font-family: var(--font-ui);
  font-size: var(--text-base);
  outline: none;
}
.input-field:focus {
  border-color: var(--accent-blue);
}
.input-field::placeholder {
  color: var(--text-muted);
}
.btn-send {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  background: var(--accent-blue);
  border: none;
  color: #ffffff;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  flex-shrink: 0;
}
.btn-send:disabled {
  opacity: 0.4;
}
```

### 会话卡片 (SessionCard)

```css
.session-card {
  background: var(--bg-secondary);
  border-radius: var(--card-radius);
  padding: 16px;
  cursor: pointer;
  transition: transform var(--duration-fast);
  border: 1px solid transparent;
}
.session-card:active {
  transform: scale(0.98);
}
.session-card[data-selected] {
  border-color: var(--accent-blue);
}
.session-card[data-needs-approval] {
  border-color: var(--accent-yellow);
}
.session-card .status-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  display: inline-block;
}
.session-card .status-dot[data-active] {
  background: var(--accent-green);
  animation: pulse 2s ease-in-out infinite;
}
.session-card .status-dot[data-idle] {
  background: var(--accent-blue);
}
.session-card .status-dot[data-ended] {
  background: var(--text-muted);
}
.session-card .session-name {
  font-family: var(--font-ui);
  font-size: var(--text-lg);
  font-weight: 600;
  color: var(--text-primary);
}
.session-card .session-path {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  color: var(--text-muted);
  margin-top: 2px;
}
.session-card .session-preview {
  font-size: var(--text-sm);
  color: var(--text-secondary);
  margin-top: 8px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.session-card .session-meta {
  font-size: var(--text-xs);
  color: var(--text-muted);
  margin-top: 8px;
}
```

---

## 动画与交互

### 过渡时间

```css
:root {
  --duration-fast: 100ms;
  --duration-normal: 200ms;
  --duration-slow: 300ms;
  --easing: cubic-bezier(0.25, 0.1, 0.25, 1);
}
```

### 关键动画

```css
/* 新消息出现 */
@keyframes message-in {
  from { opacity: 0; transform: translateY(12px); }
  to { opacity: 1; transform: translateY(0); }
}

/* 确认栏出现 */
@keyframes approval-in {
  0% { transform: translateY(100%); opacity: 0; }
  70% { transform: translateY(-4px); }
  100% { transform: translateY(0); opacity: 1; }
}

/* 状态点呼吸 */
@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

/* 页面左右切换 */
@keyframes slide-in-right {
  from { transform: translateX(100%); }
  to { transform: translateX(0); }
}
@keyframes slide-out-left {
  from { transform: translateX(0); }
  to { transform: translateX(-30%); opacity: 0.5; }
}

/* 主题切换 — 平滑过渡 */
:root {
  transition: background-color var(--duration-slow),
              color var(--duration-slow);
}
```

### 触觉反馈

```typescript
function hapticFeedback(style: "light" | "medium" | "heavy" = "light") {
  if ("vibrate" in navigator) {
    navigator.vibrate(style === "light" ? 10 : style === "medium" ? 20 : 30)
  }
}
```

---

## 响应式断点

```css
/* 手机竖屏 — 单栏 */
/* 默认样式即手机端 */

/* 平板 / 桌面 — 左右分栏 */
@media (min-width: 769px) {
  .layout {
    display: grid;
    grid-template-columns: 280px 1fr;
    height: 100vh;
  }
  .sidebar {
    border-right: 1px solid var(--border);
    overflow-y: auto;
  }
}

/* 宽屏 — 支持多窗口分屏 */
@media (min-width: 1200px) {
  .layout[data-columns="2"] {
    grid-template-columns: 240px 1fr 1fr;
  }
  .layout[data-columns="3"] {
    grid-template-columns: 200px 1fr 1fr 1fr;
  }
  .detail-panel {
    border-right: 1px solid var(--border);
  }
}
```

### 安全区域 (iPhone)

```css
body {
  padding-top: env(safe-area-inset-top);
}
.input-bar {
  padding-bottom: calc(8px + env(safe-area-inset-bottom));
}
.top-bar {
  padding-top: calc(12px + env(safe-area-inset-top));
}
```

---

## 可访问性

```
- 最小触控区域: 44×44px (Apple HIG)
- 文字对比度: 至少 4.5:1 (WCAG AA)
  - 暗色: #f0f6fc on #0d1117 = 15.3:1 ✓
  - 亮色: #1f2328 on #ffffff = 16.9:1 ✓
- 所有交互元素有 :focus-visible 样式
- 按钮有 aria-label
- 动画尊重 prefers-reduced-motion
- 主题切换有 aria-pressed 状态
- 工具卡片折叠有 aria-expanded 状态
```

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}

:focus-visible {
  outline: 2px solid var(--accent-blue);
  outline-offset: 2px;
}
```
