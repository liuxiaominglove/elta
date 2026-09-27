# ELTA Windows 版 — 交接说明（NOTES）

> 新会话开头 `@windows/NOTES.md` 即可续上。本文件是进度与决策的唯一交接记录。

## 目标
把 macOS 版 ELTA（Swift/AppKit，仓库根 `Sources/`）移植为 **Windows 版**，技术栈
**C# / .NET 8 WPF + WebView2**。地址：`windows/`，架构：三段式
（Core 纯逻辑 / 平台外壳 / 共享 HTML）。

## 当前进度（子计划 A：Mac 可测的 Core）
已完成 **A1–A4**，Mac 上 **92 个测试全绿**。

| WI | 内容 | 状态 |
|----|------|------|
| A1 | solution 骨架 + CI + 测试脚本 | ✅ |
| A2 | TextNormalizer / TextPreprocessor / ResponseParser / AIProviders | ✅ 26 测试 |
| A3 | SentenceSplitter | ✅ 52 测试 |
| A4 | TableExtractor | ✅ 14 测试 |
| **A5** | **HtmlRenderer（markdown→HTML）** | ⬜ 下一步 |
| A6 | SettingsManager / Store / DPAPI 密钥抽象 | ⬜ |
| B1–B4 | 截图 / 取词 / 热键 / OCR 平台服务 | ⬜ 需 Windows |

## 命令
```sh
# Mac 上跑 Core 测试（需要 .NET 8 SDK，已装在 ~/.dotnet）
sh windows/test-core.sh
```
- .NET SDK 8.0.425 已**用户级**装在 `~/.dotnet`（无需 sudo）；若 PATH 无 `dotnet`，脚本会自动用 `~/.dotnet/dotnet`。
- CI：`.github/workflows/windows-ci.yml`（ubuntu + windows 各跑一遍 Core 测试）。

## 目录
```
windows/
  Elta.sln
  src/Elta.Core/            # net8.0 纯逻辑（Mac 可编译）
  src/Elta.Windows/         # net8.0-windows10.0.19041.0 WPF 外壳（仅 Windows 编译）
  tests/Elta.Core.Tests/    # xUnit
  test-core.sh
  spike/                    # P0.5 能力验证 Demo（已跑完，见下文）
```
> `bin/`、`obj/` 已在根 `.gitignore` 中忽略。**尚未 git 提交**。

## 关键决策
- **测试框架**：xUnit + `dotnet test`（不是 node:test）。
- **TFM**：Core = `net8.0`（Mac 可测）；Windows = `net8.0-windows10.0.19041.0`（WinRT/OCR 必需）。
- **字符串模型**：分句用 `char`（UTF-16）；已知与 Swift `Character`(字素) 在 emoji/组合字符上有差异，暂未处理（测试未覆盖）。
- **JSON**：System.Text.Json。
- **HTML**：手写移植 `HTMLRenderer`（要与 Mac 输出逐字节对齐，不用 Markdig）。
- **密钥**：DPAPI（Windows）替代 macOS Keychain。
- **OCR**：A+B 方案（优先系统 en-US 引擎 → 缺包时引导安装 → 自带兜底引擎）。
- **取词**：先 UIA（父链遍历）→ 失败回退 Ctrl+C + 剪贴板**深拷贝**恢复。
- **热键**：组合键 `RegisterHotKey`；裸键（ESC/`）用 `WH_KEYBOARD_LL`。

## 下一步（按序）

### WI-A5：HtmlRenderer
- 源：`Sources/ResultWindowController.swift` 的 `HTMLRenderer`（约 409 行起）+
  `Sources/SentenceSplitter.swift`（拆分视图用）。
- 黄金测试：`Tests/HTMLRendererTests.swift`。
- 产出：`windows/src/Elta.Core/HtmlRenderer.cs` + `tests/Elta.Core.Tests/HtmlRendererTests.cs`。
- 关注：`render` / `renderSplit` / `shouldStartSplit` / `canSplit`；HTML 转义（防注入）；深色/字号参数。

### WI-A6：SettingsManager
- 源：`Sources/SettingsManager.swift`。
- 黄金测试：`Tests/SettingsManagerTests.swift`、`Tests/SettingsManagerThreadSafetyTests.swift`。
- 产出：`SettingsManager.cs` + `SettingsStore.cs`（持久化抽象）+ `ISecretStore.cs`。
- 关注：默认值、字号夹紧 12–22、旧 prompt 迁移幂等、线程安全、密钥写失败不丢旧值。

### WI-B1–B4：平台服务（Windows 真机）
- 源：`Sources/ScreenshotEngine.swift`、`OverlayView.swift`、`TranslationPipeline.swift`（取词/剪贴板）、
  `HotkeyHelpers.swift`、`OCREngine.swift`、`Helpers.swift`（PasteboardSnapshot 对应剪贴板快照）。
- 做法：把可测的**纯逻辑**（坐标/DPI 换算、剪贴板快照序列化、热键解析、OCR 语言策略）放 `Elta.Core` 用假实现单测；
  Win32/WinRT 调用放 `Elta.Windows`，在 Windows 上做集成测试。

## P0.5 已验证结论（真机）
- 🟢 截图：GDI `CopyFromScreen` + 物理像素换算，100%/150% 均正确；**多屏热切换会错位** → 正式实现要截「鼠标所在屏」。
- 🟢 热键：`RegisterHotKey` 可用；`WH_KEYBOARD_LL` 双向可收（他程序 + 本窗口），无杀软拦截。
- 🟡 取词：UIA 在记事本/Edge/控制台可用；Chrome、WPS 文字、WPS PDF **读不到** → Ctrl+C 兜底必须为主路径。
- ⚠️ OCR：装了英文包识别质量极好；没装则很差 → A+B 方案。
- 目标机：**A 机**（1366×768 + 1280×800 双屏，已装英文 OCR）。
- Demo 与结果：`windows/spike/`（源码）；结果 txt 另见 U 盘 / `~/relay-handoff/`。

## 待办 / 风险
- `Elta.Windows` 目前只有 csproj，**无入口点**，Windows 构建会在加 Main 后才通过（子计划 C 的托盘程序）。
- 未提交 git；提交前请 `git status` 核对。
