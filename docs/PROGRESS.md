# AirTerm Progress

> 当前进度与下次继续开工的准备信息。完整产品定位与阶段计划见 `docs/ROADMAP.md`。

**最后更新**: 2026-04-30
**当前分支**: `redesign`（v1 GA 时改名为 `main`），HEAD @ `3eac616`，**领先 `airterm/redesign` 2 个 commit 未 push**
**当前阶段**: Phase 1（7/7）✅ · Phase 2 ✅ · Phase 1 瑕疵扫尾 ✅ · **Phase 2.5 UI 重设计完成（15/15）✅** · **Phase 3 信令 + 配对 ✅** · **Phase 4 takeover ✅(广播+渲染+输入+reconnect)** · **Phase 5 mobile 工具栏 ✅(vim/htop 可用)**
**下次会话入口**: 直接进 Phase 3 — `Phase 3 · 信令 + 配对重建` 一节

---

## 已完成

### 项目重置（pre-Phase 1）
- ✅ 归档原 Claude Code 版本到 `master` + tag `v0-airclaude`（已推远程）
- ✅ 创建 `redesign` 分支作为主工作分支
- ✅ 删除 62 个 Claude Code 专属文件（UI、Agent 适配器、协议消息类型等），共 -8375 行
- ✅ 保留纯净地基：PTY / ANSIParser / TerminalScreen / RelayClient / PairingService / Crypto lib / Server
- ✅ Protocol 清理：`messages.ts` 删除，`SequencedMessage<T>` 泛型化

### Phase 1 步骤
- ✅ **[Step 1] App 入口 + Metal 视图骨架**（commit `c0d980c`）
  - `App/AirTermApp.swift` — `@main` AppKit 入口
  - `App/AppDelegate.swift` — 主菜单 + 窗口引导
  - `UI/TerminalWindow.swift` — NSWindow（1200×800，Catppuccin Mocha 背景）
  - `UI/TerminalView.swift` — MTKView 宿主
  - `Render/MetalRenderer.swift` — MTKViewDelegate（目前只 clear drawable）
  - `swift build` 通过，`bundle.sh` 打包 `AirTerm.app` 能启动并显示深色窗口

- ✅ **[Step 2] Metal 文本渲染 + 字形图集**
  - `Render/Shaders/grid.metal` — instanced-quad 顶点 + 覆盖度采样片段着色器，premultiplied alpha 混合
  - `Render/GlyphAtlas.swift` — 固定栅格 2048² `.r8Unorm` shared-storage 纹理；CoreText `CTLineDraw` rasterize 到 DeviceGray CGContext，按字符 LRU 缓存
  - `Render/GridLayout.swift` — 通过 CTFont 获取 ascent/descent/leading + `"M"` advance 计算单元格像素尺寸
  - `Render/MetalRenderer.swift` — 运行时编译 `grid.metal`（`Bundle.module` 加载），维护 pipeline/sampler，每帧构建 instance buffer 并 drawPrimitives（triangleStrip, vertexCount: 4, instanceCount: N）
  - 字体回落链：`JetBrainsMono-Regular → SFMono-Regular → Menlo-Regular`（JBM 未安装时静默回落 + DebugLog）
  - `Package.swift` 新增 `resources: [.process("Render/Shaders")]`

- ✅ **[Step 3] PTY → TerminalScreen → Renderer 串联 + 键盘输入**
  - `Services/TerminalSession.swift`（新）— 聚合 `PTY` + `TerminalScreen`，懒启动（首次 resize 回调时 fork），`start(rows:cols:)` 幂等，再次调用即 resize
  - `Services/TerminalScreen.swift` — 新增 `snapshot() -> TerminalSnapshot`（grid/cursor/rows/cols 锁内一次性拷贝）
  - `Render/GlyphAtlas.swift` — slot 0 预填 255 作为 `solid` 条目，供光标/选区/背景块复用
  - `Render/MetalRenderer.swift` — `session` 弱引用；每帧从 snapshot 读网格，逐非空格 cell 生成 instance；光标以 2px 下划线叠加；`MetalRendererDelegate` 在单元格尺寸已知时回报 rows×cols
  - `UI/TerminalView.swift` — first responder（`acceptsFirstResponder` + `viewDidMoveToWindow`→`makeFirstResponder`）；`keyDown` 映射：Ctrl+字母→control byte、Option+→ ESC 前缀、Return/Tab/Delete/Esc/箭头/PgUp/PgDn/Home/End 转义序列，其余走 `event.characters`
  - 验收：App 起来进 `$SHELL`，`echo AIRTERM_WORKS`、`ls /` 能跑；光标下划线位置正确；窗口 resize 走 `TIOCSWINSZ` + SIGWINCH

- ✅ **[Step 7] Tab 系统（⌘T / ⌘1-9）**
  - `UI/TerminalWindow.swift` — 每个 tab = 独立 NSWindow；`tabbingMode = .preferred` + `tabbingIdentifier = "airterm.tab-group"` 让 macOS 自动合成 tab 栏
  - `UI/TerminalWindow.swift` — `override newWindowForTab(_:)` 新建 TerminalWindow 并 `addTabbedWindow(_:ordered:)`（tab 栏 "+" 按钮和菜单一起受益）
  - `UI/TerminalWindow.swift` — `selectTabByTag(_:)` 从 `sender.tag` 读索引，走 `tabGroup.windows[i].makeKeyAndOrderFront`
  - `App/AppDelegate.swift` — File → New Tab 接 `newWindowForTab:`（⌘T）；View 菜单循环加 9 个 Select Tab N（⌘1–⌘9）共用 `selectTabByTag(_:)` + `tag = i-1`
  - 验收：⌘T 连续开三个 tab，tab 栏显示三个 AirTerm；⌘1/⌘3 能跳到对应 tab 并在该 tab 的活动 pane 继续输入；⌘W 依然 close pane → close tab → close window 级联

- ✅ **[Step 6] Focus 切换快捷键 + 活动 pane 视觉提示**
  - `UI/TerminalView.swift` — MTKView 缩进 2px；TerminalView 自己的 layer 做 2px border，`isActive` 在 active ↔ inactive 间切 `Palette.accent` / `Palette.background`（inactive 时融进窗口背景看不见）；鼠标 `docPoint` 坐标换算减掉 border inset
  - `UI/TerminalWindow.swift` — `activeTerminalView` didSet 自动翻转新旧 pane 的 `isActive`；`cycleFocus(forward:)` 按 `rootPane.leaves` 顺序前后循环；`moveFocus(_:)` 用窗口坐标几何距离找指定方向的最近邻（`directionalDistance` 主轴距离 + 跨轴偏移 0.5 权重）
  - `UI/TerminalWindow.swift` — `FocusDirection` + 6 个 `@objc` 菜单响应器：`focusNext/PreviousPane:`, `focusPane{Left,Right,Up,Down}:`
  - `App/AppDelegate.swift` — View 菜单加 Previous Pane (⌘[) / Next Pane (⌘]) 以及 Select Pane Left/Right/Up/Down (⌥⌘Arrow)
  - `UI/TerminalWindow.swift` — `Palette.accent` 取 Catppuccin Mocha Blue (#89B4FA)
  - 验收：三 pane 布局下 ⌘]/⌘[ 能按树序循环焦点，⌥⌘↑↓←→ 按几何方向选最近邻 pane；活动 pane 有明显蓝框，inactive pane 边框融进窗口背景

- ✅ **[Step 5] Pane 树 + NSSplitView 递归**
  - `UI/Pane.swift`（新）— 引用类型树节点；`leaf(TerminalView)` 或 `split(orientation, children)`；`leaves` 深度遍历；`parent` 弱引用防环
  - `UI/PaneContainerView.swift`（新）— 从 `Pane` 根递归 build NSSplitView；rebuild 后 `layoutSubtreeIfNeeded` + `distributeEvenly` 把 divider 按子数均分
  - `UI/TerminalWindow.swift` — 持有 `rootPane` + `activeTerminalView`；`splitPaneVertically:` / `splitPaneHorizontally:` / `closeActivePane:` 菜单响应器；split 时若父节点同方向则追加，否则在父节点里把活动 leaf 换成新 split；close 时父节点只剩 1 娃就塌陷；根 leaf 关了就关窗
  - `UI/TerminalView.swift` — `onActivated` 闭包在 `becomeFirstResponder` 里回调，取代旧的 `viewDidMoveToWindow` 自动抓焦（多 pane 里不再抢焦）
  - `App/AppDelegate.swift` — File 菜单加 Split Vertically（⌘D）/ Split Horizontally（⌘⇧D）/ Close Pane（⌘W，root 落下就关窗）
  - 验收：⌘D 并排切，⌘⇧D 堆叠切，各 pane 独立 shell（PTY 实际跑在 `TIOCSWINSZ` 给它的尺寸上，如 70×43）；输入只进活动 pane；⌘W 关 pane，父节点塌陷合并

- ✅ **[Step 4] 滚动回溯 + 鼠标选区 + 复制粘贴**
  - `Services/Cell.swift` — 新增 `DocPoint{docRow, col}` + `Selection{anchor, head}`，`normalized` 规范化起止点
  - `Services/TerminalScreen.swift` — `snapshot(topDocLine:)` 把 scrollback + live grid 拼成固定大小的视口（`topDocLine=nil` 即 tail 跟随）；新增 `textInRange(from:to:)` 返回选区文本（行末空格自动去除）；TerminalSnapshot 加 `topDocLine/scrollbackCount/atTail`
  - `Render/MetalRenderer.swift` — `scrollTopDocLine`、`selection` 属性；三 pass 叠层（bg → 选区高亮 → glyph/underline/strikethrough）；`latestSnapshot` 供 view 做坐标换算
  - `UI/TerminalView.swift` — `isFlipped=true`；`scrollWheel` 把 `scrollingDeltaY` 按 cell 高度累加换行；鼠标 down/dragged/up 维护 `Selection`；`copy:` / `paste:` / `validateMenuItem:` 接 `NSPasteboard.general`；keyDown 一触发就 `jumpToTail()`（输入回到最新）；粘贴时把 `\r\n` / `\n` 归一化为 `\r`
  - 验收：输出 60 行，滚轮上下走；拖拽产生蓝色选区（0.25/0.45/0.75/0.55）；⌘C 写入 pasteboard；⌘V 从 pasteboard 读入并发给 PTY

- ✅ **[Step 3.5] Per-cell 颜色 + 正确字体**
  - 新增 `Services/Cell.swift` — `Cell { char, attrs }` + `CellAttributes { fg/bg/bold/dim/italic/underline/reverse/strikethrough }` + `AnsiPalette`（8/16/256/24-bit 调色板为 `SIMD4<Float>`，不再走 NSColor）
  - `Services/TerminalScreen.swift` — grid 类型从 `[[Character]]` 改为 `[[Cell]]`；SGR 参数解析（0/1/2/3/4/7/9/22-29/30-37/38/39/40-47/48/49/90-97/100-107，支持 5/2 扩展色）；写字符时打 `currentAttrs` 标签；erase 操作用 `currentAttrs.bg` 填充（兼容 "\e[41mK" 留红条）；CSI 解析支持冒号分隔符归一化为分号
  - 删除 `Services/ANSIParser.swift`（v0 走 NSAttributedString 的 dead code）
  - `Render/MetalRenderer.swift` — 每 cell 双 pass：先 bg（solid slot + 颜色），再 fg/underline/strikethrough；reverse 交换 fg/bg，dim 乘 0.5 系数
  - `brew install --cask font-jetbrains-mono` 完成，字体链自动命中 JetBrainsMono-Regular（cell 17×37 @2x）
  - 验收：`printf "\e[31mRED \e[42;30mBG \e[7mREVERSE \e[4mUNDERLINE\e[0m"` 四种效果正确渲染

---

## Phase 1 瑕疵扫尾（2-5 项）✅

- **双击选词 / 三击选行 / ⌥ 拖拽块选** — `Selection.Mode {linear, block}` + `columnRange(forDocRow:cols:)`；`TerminalView` 用 `GestureMode` 跟踪每次 mouseDown（clickCount 1/2/3 + Option flag）；`textInRange(_ selection:)` 按 mode 分支（block 保留列宽矩形）
- **120fps + 帧时延 telemetry** — MTKView `preferredFramesPerSecond = 120`；`MetalRenderer` 每秒打 `fps avg/min/max | cpu avg/max headroomFps`；实测 CPU draw ~2.5-3.3 ms/帧，headroom ~300-400 fps（显示器上限兜底）
- **Bold 真字重** — `GlyphAtlas` 带 `regularFont` + `boldFont` 两套字形，cache 按 `(Character, bold)` keyed；`MetalRenderer.loadMonoFont` 改走 `CTFontDescriptor` + `kCTFontSymbolicTrait = .boldTrait`（JetBrainsMono 的 bold PostScript 名其实是 "JetBrainsMono-Regular_Bold"，精确字符串匹配根本命中不了）
- **Metal instance buffer 修正** — `setVertexBytes` 4 KB 上限在 hexdump 下一帧 >85 个 instance 时崩溃（AGX::RenderContext::setVertexProgramBufferBytes SIGABRT），换成 growable 的 shared `MTLBuffer`，步幅对齐 4 KB 只涨不降
- **彩色 scrollback** — `TerminalScreen.scrollback` 从 `[String]` 改成 `[[Cell]]`；滚出屏幕的行保留 SGR 完整属性（fg/bg/bold/underline…）；`scrollUp` trim 尾部空白无 bg cell 免内存膨胀；`snapshot` 直接拼 `[Cell]` 行，不再 String↔Cell 来回转

---

## Phase 2 落地 ✅

- `Config/TOML.swift` — 手写 TOML 子集解析器（section headers、dotted keys、quoted string、int、double、bool、行内注释、字符串转义），~100 行；解析失败抛 `ParseError`，不炸 App
- `Config/Theme.swift` — `Theme` 结构体（bg/fg/cursor/selection/accent + 8 标准 + 8 亮 ANSI）；4 套内置：Catppuccin Mocha / Tokyo Night / Dracula / Solarized Dark
- `Config/Config.swift` — `Config` 结构（`font.family`、`font.size`、`theme.name`、`cursor.style`、`window.padding`、`window.opacity`），每项有 fallback；`seedIfMissing` 在 `~/.config/airterm/config.toml` 首次启动时写样板
- `Config/ConfigStore.swift` — 单例加载 / 订阅机制；`startWatching` 用 `DispatchSource.makeFileSystemObjectSource` 监听文件，编辑器"原子替换"后自动 re-install watcher；改动推给所有观察者
- `Services/Cell.swift` — `AnsiPalette` 改成 theme-aware（`AnsiPalette.theme` 静态属性），`CellAttributes.default*` 跟着 theme 动
- `Render/MetalRenderer.swift` — `fontFamily/pointSize/cursorStyle/theme` 变配置属性；font/size 改了自动把 `atlas = nil` 重建；cursor 渲染按 `CursorStyle` 分三种（`.underline` 底边 2px / `.bar` 左侧 2px 宽 / `.block` 整格半透明）；selection/cursor 颜色走 theme
- `UI/TerminalView.swift` — init 从 `ConfigStore.shared` 拉当前值，`subscribe` 绑观察者；`padding` 改了同步更新 `layer.borderWidth` 和 MTKView inset；border 颜色 active=theme.accent，inactive=theme.background（隐形）
- `UI/TerminalWindow.swift` — 窗口 `backgroundColor` 跟 `theme.background`；`alphaValue` 跟 `window.opacity`；`Palette` enum 移除（色值都在 Theme 里）
- `App/AppDelegate.swift` — `applicationDidFinishLaunching` 优先 `ConfigStore.shared` 和 `startWatching()`，保证第一帧就按配置画
- 验收：改 `~/.config/airterm/config.toml` 切 theme / 字号 / 光标样式 / padding / opacity 都立即生效，不重启；破格 TOML 打 log 后回落默认；四套 theme 肉眼区分

---

## Phase 1 已完整落地 🎉

MVP Mac 终端引擎 7/7 步全部达成，可以单独把它当成一个日常能用的原生 macOS 终端。

**后续已完成增强**：
- Phase 2：TOML 配置热重载 + 4 套主题（catppuccin-mocha / tokyo-night / dracula / solarized-dark）+ 字体/字号/光标样式/padding/opacity
- 选区：双击选词 / 三击选行 / ⌥ 拖拽块选
- 吞吐：120fps request + per-frame CPU telemetry（实测 ~3ms/帧）
- Bold：CTFontDescriptor trait-based 匹配，真正的 bold 字体
- 彩色 scrollback：scrollback 保留 SGR 属性
- 稳定性：setVertexBytes → MTLBuffer 修了 hexdump 下 >85 instance 的 Metal 崩溃

**遗留的"用户环境"问题（非 AirTerm bug）**：
- 用户 `~/.bash_profile` 启动期打印 `bash: Savings: command not found`
- `swift test` CLI 触发 XCTest 仍报模块找不到，目前靠 Xcode 跑

---

## Phase 1 全部步骤

| # | 任务 | 状态 |
|---|---|---|
| 1 | App 入口 + Metal 视图骨架 | ✅ 完成 |
| 2 | Metal 文本渲染 + 字形图集 | ✅ 完成 |
| 3 | PTY → VTParser → TerminalScreen → Renderer 串联 + 键盘输入 | ✅ 完成 |
| 4 | 滚动回溯、选区、复制粘贴 | ✅ 完成 |
| 5 | Pane 树数据模型 + NSSplitView 递归 | ✅ 完成（含 ⌘D/⌘⇧D 分屏） |
| 6 | Focus 切换快捷键 + 活动 pane 视觉提示 | ✅ 完成 |
| 7 | Tab 系统（⌘T、⌘1-9） | ✅ 完成 |

**Phase 1 验收**：`vim README.md` 正常；`cat /dev/urandom \| head -c 10M \| hexdump` 帧率稳定 120fps；竖切屏幕同时运行多个 shell。

---

## 工程约定（已生效）

- 分支：主开发在 `redesign`，v0 归档在 `master` + `v0-airclaude` tag
- 远程：`airterm` → `git@github.com:jyma/airterm.git`
- 测试：Mac 端 `swift test` 暂时无法通过（XCTest 模块 CLI 找不到），优先用 Xcode 跑或 Phase 7 前修
- 构建：`bash apps/mac/scripts/bundle.sh` → `apps/mac/build/AirTerm.app`

---

## 恢复开发的最短路径

```bash
# 1. 切到工作分支（redesign 已领先 airterm/redesign 同步）
cd /Users/mje/GitHub/airterm
git checkout redesign
git pull airterm redesign

# 2. 读本文件顶部（下一步 Phase 3）+ docs/ROADMAP.md

# 3. 编译 + 打包（config 文件 ~/.config/airterm/config.toml 已存在，首启会自动种子）
bash apps/mac/scripts/bundle.sh
open apps/mac/build/AirTerm.app
#   预期：1200x800 深色窗口、bash/zsh 落地、⌘T 开新 tab、⌘D/⌘⇧D 分屏
#   调试日志：tail -f /tmp/airterm-debug.log

# 4. Phase 3 起点（见下方"下一步"）
```

---

## Phase 2.5 · UI 重设计(对标 Ghostty 功能 + Starship 美感)✅

**启动**: 2026-04-30
**完成**: 2026-04-30(全 15 任务一气推完,共 15 个 commit)
**目标**: 在 Phase 3 之前先把 UI 推到产品级 — Ghostty 级窗口质感 + Starship 级 prompt + Chrome Theme 系统。
**进度**: **15/15 ✅**

### 已完成(15 个 commit)

- ✅ **A1+A2** Nerd Font 内置 + Ghostty 风 chrome — `06c01b9`
  - JetBrainsMono Nerd Font Mono 4 权重 ttf 进 `Resources/Fonts/`(OFL)
  - `BundledFonts.registerAll()` 用 process scope 注册,不污染系统
  - styleMask `.fullSizeContentView` + `titleVisibility = .hidden` + 28pt traffic-light inset
- ✅ **A5-1** airprompt Cargo 骨架 — `6d33ac6`(913KB,冷启 10ms)
- ✅ **A5-2** airprompt 真模块 — `0b9dedc`(libgit2 + chrono;1.5MB,冷启 20ms)
- ✅ **A7+A9** shell-init 注入 + bundle 集成 — `7f925d6`
  - ZDOTDIR shim(zsh)+ `--rcfile`(bash 丢 `-l`)注入,不动用户 dotfiles
  - 检测 starship/p10k/oh-my-zsh 自动 yield;`[shell] inject_prompt` toml 字段
  - bundle.sh cargo build + 拷 binary 到 `Resources/bin/airprompt`
- ✅ **A3+A4 + Ghostty dim** Theme 语义色 + Status Bar + 焦点指示 — `23f47a1`
  - Theme extension 给 14 套主题 free derive 7 个 semantic colors
  - StatusBarView (22pt) 手工 layout(避开 NSStackView intrinsic 反向缩 window),模块: branch placeholder /  paneCount /  HH:mm
  - 整圈 border 移除,改 Ghostty 风 dim overlay(inactive pane alpha=0.3)
- ✅ **A8 (1/2)** OSC 7 + OSC 133 shell 集成 — `8e47a2a`
  - airprompt prompt 包 OSC 133;A/B;shell-init 发 OSC 7 cwd + OSC 133;C/D
  - TerminalScreen 真解析 OSC payload,onCwdChange / onPromptStart callbacks
  - StatusBar 替换 placeholder 为真实 cwd basename + git branch(读 .git/HEAD)
- ✅ **A8 (2/2)** Prompt 左侧色条 — `21c627f`
  - inPromptArea 状态 + promptStartDocRow,snapshot.promptStartRow viewport-相对
  - MetalRenderer 加 stripe pass:2pt accent stripe at col 0 from promptStart through cursorRow
- ✅ **A6** 5 套 starship preset prompt.toml — `0f75f4c`
  - pastel-powerline / tokyo-night / gruvbox-rainbow / jetpack / minimal
  - bundle.sh 拷 presets 到 `Resources/airprompt-presets/`,README 说明 `cp` 切换
- ✅ **B4** ⇧⌘P 命令面板 — `9554d4e`
  - NSPanel 浮窗 + NSSearchField + NSTableView,substring filter
  - 命令:14 主题切换 / split / new tab / close pane / open config
  - 通过 Edit 菜单 ⇧⌘P 走 responder chain,无全局 event monitor
- ✅ **C1** Onboarding 首启 + Preset 切换 UI — `22a01c9`(prompt preset 切换 5 套,通过 ⇧⌘P 命令面板)
- ✅ **B3** 自定义 Tab Bar 替换原生 — `74468a4`
  - `Tab` 模型持有 rootPane + paneContainer + activeTerminalView
  - `TabIcon.iconFor(cwd:)` 按项目标记选 nf-icon(Cargo.toml/go.mod/package.json/pyproject.toml/git/home/folder)
  - `TabBarView` 32pt 自渲染 tab strip,圆角 chip + accent 图标 + 主题色,左 80pt 给 traffic light,尾部 "+" 按钮
  - `TabChipView` 悬停显示 ✕ close 按钮(active 永显);hitTest 吞所有 chip 内 click
  - `TerminalWindow` 重构:`tabs: [Tab]` + `activeTabIndex`,`tabbingMode = .disallowed`
  - 切 tab = reparent paneContainer(PTY session 跨 tab 切换不重启)
  - ⌘T → addTab,⌘W → 级联 pane → tab → window;⌘1-9 selectTabByTag;⌃⇥/⌃⇧⇥ 走 selectNextTab/Previous
  - statusBar + tabBar 都跟 OSC 7 cwd 变化刷新标题/图标
- ✅ **B1+B2** ChromeTheme 整套切换 — `3eac616`
  - `ChromeTheme.swift` 5 套静态 preset:pastel-powerline → catppuccin-mocha / tokyo-night → tokyo-night / gruvbox-rainbow → gruvbox-dark / jetpack → dracula / minimal → nord
  - `apply()` 复制 prompt.toml + setTheme(named:)
  - `Config.Chrome.preset` 字段,`[chrome] preset = "..."` toml 段
  - `ConfigStore.applyChromePresetIfNeeded` 仅在 preset name 改变时 apply,避免编辑无关字段时反复覆盖 prompt.toml
  - `ConfigStore.applyChromeTheme(_:)` 命令面板调:transient 不写回 toml(声明式持久化由用户手写)
  - CommandPalette 加 5 个 "Chrome: ..." 顶置命令,优先于 14 个 Theme 和 5 个 Prompt Preset

### 核心产品命题已达成
用户打开 AirTerm 即时获得:Ghostty 级 chrome + 自动注入 Starship 级 prompt + status bar + 自定义 tab bar(按项目自动选 nf-icon) + 5 套 ChromeTheme 整体切换 + ⇧⌘P 命令面板 + 14 套 color theme。Phase 2.5 收官。

---

## Phase 3 · 信令 + 配对重建(进行中)

**已落地**:
- ✅ **P3-1** `packages/protocol` 加 signaling schema(`993f4ea`)
  - signaling.ts:NoiseHandshakeFrame(3 stage IK + ack)/ EncryptedFrame(seq 化)/ SignalingPlainMessage(WebRTC offer/answer/ICE/ping/pong/bye)
  - pairing.ts:QRCodePayloadV1 / V2 拆分,V2 强制 macPublicKey + version 字段;`isQRCodePayloadV2` 类型守卫
  - tests:10 新签名 + 4 新 pairing test,共 26 通过
  - server 已是 pure relay(WSManager 按 `type='relay'` 转发,payload 不动),无需改动
- ✅ **P3-3a** Mac KeyStore + v2 QR 生成(`8872acf`)
  - `Services/KeyStore.swift`:CryptoKit Curve25519 X25519 静态身份生成 + UserDefaults 持久化(production 应迁 Keychain)
  - `Models/PairInfo.swift`:QRCodePayload 重做成 v2(macPublicKey + v=2 + encodedJSON)
  - `Services/PairingService.swift`:加载/生成静态 keypair,`macPublicKeyBase64` API,initiatePairing 加 URL/HTTP 校验
- ✅ **P3-4a** Web Vite + React pair 骨架(`6a968ad`)
  - `index.html` / `main.tsx` / `App.tsx`:React 19 + BrowserRouter,3 路由 `/` `/pair` `/paired`
  - `lib/pair-client.ts`:`parseQRPayload`(只接受 v2,拒 v1 / 非 http(s) / 空 pubkey) + `completePair`(类型化 HTTP 错误)+ 浏览器 device id 持久化
  - `components/QRScanner.tsx`:`BarcodeDetector` + `getUserMedia` 扫码,无第三方库依赖,environment camera 默认
  - `pages/PairPage.tsx`:scan / manual 模式切换,manual JSON 表单走相同 parser
  - `pages/PairedPage.tsx`:Mac 名称 / 设备 id / 时间 + Forget 按钮
  - drive-by:修 `ws-client.ts` 旧 `BusinessMessage` 失效 import(改为本地 `type BusinessMessage = unknown`)
  - 5 个新测试通过,`vite build` 干净(240KB / 77KB gzipped)
- ✅ **P3-3c-i** Mac PairingWindow + QR 渲染(`010ffd4`)
  - `UI/PairingWindow.swift`:NSPanel 浮窗,主题感知(订阅 ConfigStore);async startPairing 走 `/api/pair/init` → CIQRCodeGenerator 渲染 280pt QR + monospaced 大粗体显示 pair code
  - `Utils/MacDeviceID.swift`:稳定 per-install UUID(同 KeyStore 的 production caveat,GA 前迁 Keychain)
  - `App/AppDelegate.swift`:File → Pair New Device 菜单;`AIRTERM_RELAY_URL` env 覆盖,默认 `https://relay.airterm.dev`
- ✅ **P3-3c-ii** Mac WS 连接 + pair_completed 监听(`f0b94e9`)— **demo 路径已闭合**
  - PairingWindow 在 init 成功后开 RelayClient,onMessage 看 `pair_completed`,实时更新状态
  - 状态线:`Requesting…` → `Opening relay channel…` → `Waiting for phone…` → `Paired with <name>!`
  - 关闭面板自动 disconnect;deinit 也兜底
- ✅ **P3-3d** Mac 持久化 paired phones + relay token(`2f70694`)
  - `Services/PairingStore.swift`:`PairedPhone` Codable 列表(deviceId/name/pairedAt/publicKey?)+ Mac JWT token,UserDefaults 存
  - PairingWindow 在 pair_completed 时 addOrUpdate + saveMacToken
  - 重启后还认得手机;phone publicKey 等 P3-4b 把 Noise 接进来再填
- ✅ **P3-Noise-TS** Noise IK 参考实现(`0d2e591`)— **核心安全基础落地**
  - `packages/crypto/src/noise.ts`:SymmetricState + CipherState + HandshakeState (IK pattern §7.5)
  - Curve25519 + ChaCha20-Poly1305 + SHA-256(全部 @noble);`Noise_IK_25519_ChaChaPoly_SHA256` 协议名
  - 11 新测试通过:round-trip 握手 / 双向 transport 加密 / tamper 拒绝 / prologue 不匹配拒 / role 守卫
  - Web 直接 `import { HandshakeState } from '@airterm/crypto'`;Mac 端下一刀按这个 reference 移植

**Phase 3 剩余**:
- ✅ **P3-3b** Mac NoiseSession.swift(`daf86ed`) — 镜像 TS reference,DEBUG 自测在启动时 fail-fast
- ✅ **P3-4b 基础** phone-identity + publicKeyFromPrivate(`024b260`) — phone X25519 静态身份持久化(IndexedDB)
- ✅ **P3-Noise-Wire-Web** NoisePairDriver(`86f4c8d`) — 纯逻辑 IK initiator 驱动器,7 测试通过,IO 注入便于换 WS
- ✅ **P3-Noise-Wire-Mac** NoisePairResponder + PairingWindow 路由(`022f48e`) — Mac 端在 pair_completed / 收到 stage-1 时 lazy-create responder,跑 readMessageA/writeMessageB,sendRelay 回 phone,只在 Noise 完成后才标记 "Securely paired"(MITM 拿了 JWT 也过不了)
- ✅ **P3-Noise-Wire-Final** Web pair-flow 整合(`bb34746`) — `runPhonePairFlow(rawQR)` 串起 parseQR / completePair / loadOrCreatePhoneIdentity / createWSClient / NoisePairDriver,30s 安全超时,异常路径 WS 必断;PairPage.tsx 一行调用替代旧的 4 步
- ✅ **drive-by** `packages/crypto/sas.ts` 改用 @noble/hashes 替代 node:crypto(浏览器构建解锁)
- ✅ **P3-5** E2E 测试通过(`2e1fd2b`):server 进程内起真 Hono+WS+SQLite,模拟 Mac responder + Phone initiator(都用 @airterm/crypto HandshakeState),走完完整 pair init→complete→WS→Noise IK→双向 transport 加密路径,254ms 完成。**Phase 3 收官** ✅

---

## Phase 4 · WebRTC 数据通道 + 屏幕镜像(进行中)

**起步路线**:先用 Phase 3 的 Noise transport over WS 跑 takeover 数据面(JSON 帧 + ChaCha20-Poly1305),功能闭合后再切 WebRTC P2P(Phase 4.x)。

**已落地**:
- ✅ **P4-1** protocol takeover schema + Web TakeoverChannel(`1a2db2a`)
  - 6 帧:ScreenSnapshot / ScreenDelta / InputEvent / Resize / Ping / Bye
  - CellFrame 包 ch + fg/bg/attrs/width;ATTR_BOLD..STRIKETHROUGH 常量
  - Web TakeoverChannel:两 CipherState 包装,encode→encrypt→EncryptedFrame;replay 拒绝;tampering / decode 失败走 onError;7 tests 通过
- ✅ **P4-2** Mac TakeoverFrame + TakeoverChannel Swift 移植(`8a2f71f`)
  - 手写 Codable 离散联合 → JSON byte-for-byte 对齐 TS reference
  - TakeoverChannel 镜像 Web 端;NoiseSession.runSelfTest 扩展含 takeover round-trip
  - 启动时 DEBUG self-test 把 Swift Codable 漂移在 launch 第一帧抓住
- ✅ **P4-3** E2E 测试扩展(`0926a64`)— Noise 握手后再走 ScreenSnapshot(Mac→Phone) + InputEvent(Phone→Mac),全在 215ms

**待办**:
- ✅ **P4-Wire-Mac** TakeoverEncoder + TakeoverSession + AppDelegate 接管 RelayClient(`28fc074`)— Mac 端 30Hz 广播 ScreenSnapshot/Delta + 反向 InputEvent → PTY + Resize 处理
- ✅ **P4-Wire-Web** TakeoverViewer DOM grid + PairPage handoff(`a9b94d1`)— phone 实时渲染 cell 网格,无 xterm.js,直接读 CellFrame 走 React DOM
- ✅ **P4-Wire-Web-Input** 键盘 → InputEvent(`9cfe963`)— keyToBytes 映射所有终端键(printable / 名键 / Ctrl-letter / Alt-letter),phone 输入直达 Mac PTY,19 tests
- ✅ **P4-Reconnect** 刷新页面后 phone 重新握手 + Mac 后台 listen(`03f87e4`)
  - Mac:`PairingCoordinator` 启动时从 PairingStore 读 token+paired phones,开 RelayClient,routes by `from`(新 `onRelayFrame` callback);Noise stage-1 → NoisePairResponder → 同 `PairingHandoff` 给 AppDelegate;活跃 takeover 期间暂停 coordinator(server one-WS-per-deviceId),takeover 结束自动 reboot
  - Web:`reconnect-flow.ts` 跳 HTTP 只重跑 Noise IK 用 stored {token, macPublicKey, phoneIdentity};PairedPage 重写在 mount 时驱动,失败 inline 出错不丢 stored 上下文;startedRef 防 React strict-mode 双触发
  - **效果**:phone 刷新 → 自动重连 → 终端实时 mirror,无需重新扫码
- ⏳ **P4-Hub**(优化)单一 RelayClient 多订阅 — 干掉"PairingWindow 临时踢 coordinator"的 WS flap
- ⏳ **P4.x** 切 WebRTC P2P 替代 WS relay(libwebrtc Swift + 浏览器原生 RTCPeerConnection;SDP/ICE 已经有 schema)

**Phase 4 MVP 数据面闭合 ✅**:Mac 30Hz 广播 → phone DOM grid 实时渲染 → phone 键盘 → InputEvent → Mac PTY。全程经 Noise transport 加密,relay 看不见明文。

---

## Phase 5 · 手机接管输入(进行中)

ROADMAP 原本 Phase 5 是"手机虚拟键盘 + 输入"。Phase 4 P4-Wire-Web-Input 已经做了基础键映射;Phase 5 这里追加移动端可用性。

- ✅ **P5-Mobile-Input** Phone 软键盘 + 终端控制工具栏(`915a917`)
  - `MobileKeyToolbar.tsx`:Esc / Tab / Ctrl(latch)/ ↑↓←→ 7 键沿底,respect `env(safe-area-inset-bottom)` 避 iOS 手势条
  - `TakeoverViewer.tsx`:1×1 隐藏 `<input>` 触发 iOS 软键盘;`beforeinput` 处理 insertText / IME composition / insertLineBreak / deleteContentBackward / deleteContentForward;`keydown` 仍处理 hardware 键;font-size 16px 防 iOS auto-zoom
  - Ctrl latch:读 ref(不读 state)避免 re-render race;tap Ctrl + tap c 立刻发 0x03
  - 效果:phone 上能跑 vim / htop / Ctrl-C 了

**核心决策已锁定**:WebRTC P2P DataChannel + TURN fallback(coturn);E2E Noise IK。

**目标**：Mac 菜单"配对新设备" → 出二维码 → 手机扫码 → Noise IK 握手完成 → 配对 token 持久化。此阶段不传屏幕数据。

**现状勘察**（上次会话已看过）：
- `apps/server`（1400+ 行 TS）：保留了老 AirClaude 的 auth / pair / db / ws 全套；需要剥成"纯信令 WebSocket"（只转发 SDP/ICE，不碰业务）
- `apps/web`：已被 redesign 清空成骨架（`src/lib/` 剩 crypto-layer / key-store / ws-client / storage / theme / time，**没有 React 应用入口**，需要从零搭 pair + takeover 页面）
- `apps/mac/AirTerm/Services/`：`PairingService.swift` + `RelayClient.swift` 是 AirClaude 遗产，需要重写成 Noise IK + SDP 交换
- `packages/protocol`：有老的 envelope / pairing 类型，需要加 signaling frames（SDP offer/answer、ICE candidate、Noise handshake payload）

**建议切片**（分多个 commit）：
1. `packages/protocol`：signaling 消息 schema 定义
2. `apps/server`：剥成纯 WS relay，保留最小 auth（配对 short code）
3. `apps/mac`：重写 `PairingService`（Noise IK 握手）+ QR 生成 + 存储
4. `apps/web`：搭 Vite + React 应用骨架，pair 页 + QR 扫描
5. 端到端联调 + 验收

**验收**：Mac App 菜单「配对新设备」→ 弹窗出二维码 → 手机浏览器扫码 → Mac App 和手机 PWA 都提示"配对成功" → Mac 重启后配对仍在。

---

## 已确认决策

- **配置文件位置**：`~/.config/airterm/config.toml`（unix 风，非 Apple `~/Library/Application Support`）
- **品牌视觉**：搁置；`design/airterm.pen` 不用
- **默认字体**：JetBrains Mono 14pt，brew cask 安装；不在时回落 SFMono / Menlo
- **配置层**：TOML + DispatchSource hot reload；改文件无需重启
- **主题**：内置 catppuccin-mocha（默认）/ tokyo-night / dracula / solarized-dark
- **Pane 模型**：引用类型树，NSSplitView 递归渲染；每 pane 自带 TerminalSession / PTY
- **Tab**：用 macOS 原生 `tabbingMode = .preferred`，不自己画
- **传输（Phase 3+）**：WebRTC P2P DataChannel + TURN fallback（coturn）
- **E2E 加密（Phase 3+）**：Noise Protocol IK
