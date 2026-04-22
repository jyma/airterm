# AirTerm Progress

> 当前进度与下次继续开工的准备信息。完整产品定位与阶段计划见 `docs/ROADMAP.md`。

**最后更新**: 2026-04-22
**当前分支**: `redesign`（v1 GA 时改名为 `main`）
**当前阶段**: Phase 1 · Mac 终端引擎 MVP（约完成 5%）

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

---

## 下一步：Phase 1 Step 2 · Metal 文本渲染

**目标**：Metal 管线能渲染一行硬编码字符串 `"Hello AirTerm"`。

**需要实现的文件**：
- `Render/GlyphAtlas.swift` — CoreText rasterize 字形到 MTLTexture，LRU 缓存
- `Render/GridLayout.swift` — 字符坐标 ↔ 屏幕像素坐标转换
- `Render/Shaders/grid.metal` — Metal shader（实例化 quad 绘制 glyph）
- 更新 `MetalRenderer.swift` — pipeline state、vertex buffer、draw call

**技术要点**：
- 字体默认 JetBrains Mono 14pt（Retina 下 2x）
- 字形图集初始尺寸 2048×2048 单页，超出后扩展第二页
- 每个字符一个 quad，顶点通过 instanced rendering 批量绘制
- Color palette 从 `Palette` 结构读取（先 hardcode，Phase 2 接入 TOML）

**验收**：App 启动后，窗口左上角显示 `"Hello AirTerm"` 白色文字，清晰无锯齿，无抖动。

---

## Phase 1 全部剩余步骤

| # | 任务 | 状态 |
|---|---|---|
| 1 | App 入口 + Metal 视图骨架 | ✅ 完成 |
| 2 | Metal 文本渲染 + 字形图集 | ⬜ **下一个** |
| 3 | PTY → VTParser → TerminalScreen → Renderer 串联 + 键盘输入 | ⬜ |
| 4 | 滚动回溯、选区、复制粘贴 | ⬜ |
| 5 | Pane 树数据模型 + NSSplitView 递归 | ⬜ |
| 6 | Split / focus 快捷键（⌘D、⌘⇧D、⌘[、⌘]） | ⬜ |
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

## 待澄清问题（下次开工前需回答）

以下是上一轮 roadmap 讨论中未明确的点，下次继续时建议先定一下：

1. **时间投入**：全职（按 11 周预期）还是业余项目（3-6 个月）？影响每阶段打磨深度。
2. **品牌视觉**：Logo / icon / 官网视觉是否现在就做？Pencil 设计稿 `design/airterm.pen` 是否还适用？
3. **Phase 1 Step 2 字体选择**：JetBrains Mono 是否最终选型？是否需要同时支持自定义字体文件路径？
4. **配置文件位置**：`~/.config/airterm/config.toml` 还是 `~/Library/Application Support/AirTerm/config.toml`？（前者 unix 风，后者 Apple 惯例）
