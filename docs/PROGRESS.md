# AirTerm Progress

> 当前进度与下次继续开工的准备信息。完整产品定位与阶段计划见 `docs/ROADMAP.md`。

**最后更新**: 2026-04-22
**当前分支**: `redesign`（v1 GA 时改名为 `main`）
**当前阶段**: Phase 1 · Mac 终端引擎 MVP（约完成 65%）

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

## 下一步：Phase 1 Step 6 · 焦点快捷键 + 活动 pane 视觉提示

**目标**：键盘快速切换活动 pane，活动 pane 有可见的高亮边/指示。

**需要实现**：
- ⌘[/⌘] 或 ⌥⌘Arrow 在 pane 之间切焦点（几何最近的邻居；按 leaves 的 frame 做命中）
- 活动 pane 有 1–2px 边框或微妙色差（最简：给 MTKView 设 1px borderLayer，inactive 时清掉）
- `TerminalWindow` 新增 `focusNeighbor(direction:)` 方法，实现 Pane tree + 屏幕坐标结合的邻居查找

**验收**：多 pane 下快捷键能切焦点；看得出哪个 pane 是活动的；关 pane 后焦点自动落到留存的某一个。

---

## Phase 1 全部剩余步骤

| # | 任务 | 状态 |
|---|---|---|
| 1 | App 入口 + Metal 视图骨架 | ✅ 完成 |
| 2 | Metal 文本渲染 + 字形图集 | ✅ 完成 |
| 3 | PTY → VTParser → TerminalScreen → Renderer 串联 + 键盘输入 | ✅ 完成 |
| 4 | 滚动回溯、选区、复制粘贴 | ✅ 完成 |
| 5 | Pane 树数据模型 + NSSplitView 递归 | ✅ 完成（含 ⌘D/⌘⇧D 分屏） |
| 6 | Focus 切换快捷键 + 活动 pane 视觉提示 | ⬜ **下一个** |
| 7 | Tab 系统（⌘T、⌘1-9） | ⬜ |

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
# 1. 切到工作分支
cd /Users/mje/GitHub/airterm
git checkout redesign
git pull airterm redesign   # 如果远程有更新

# 2. 读本文件 + docs/ROADMAP.md 对齐上下文

# 3. 编译 + 运行验证
bash apps/mac/scripts/bundle.sh
open apps/mac/build/AirTerm.app
#   预期：1200x800 深色窗口打开

# 4. 开始 Phase 1 Step 2
#   参考本文件 "下一步" 小节
```

---

## 已确认决策（2026-04-22）

- **配置文件位置**：`~/.config/airterm/config.toml`（unix 风）
- **品牌视觉**：暂不做 Logo / icon / 官网视觉；`design/airterm.pen` 搁置
- **默认字体**：JetBrains Mono 14pt（Phase 1 先硬编码，自定义字体路径后续再开）

## 待澄清问题（下次开工前需回答）

1. **时间投入**：全职（按 11 周预期）还是业余项目（3-6 个月）？影响每阶段打磨深度。
