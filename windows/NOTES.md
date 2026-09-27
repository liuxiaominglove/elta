# ELTA Windows 版 — 交接说明（NOTES）

> 新会话开头 `@windows/NOTES.md` 即可续上。本文件是进度与决策的唯一交接记录。

## 目标
把 macOS 版 ELTA（Swift/AppKit，仓库根 `Sources/`）移植为 **Windows 版**，技术栈
**C# / .NET 8 WPF + WebView2**。地址：`windows/`，架构：三段式
（Core 纯逻辑 / 平台外壳 / 共享 HTML）。

## 当前进度（子计划 A：Mac 可测的 Core）
已完成 **A1–A6**，Mac 上 **240 个测试全绿**。**子计划 A 收尾**。

| WI | 内容 | 状态 |
|----|------|------|
| A1 | solution 骨架 + CI + 测试脚本 | ✅ |
| A2 | TextNormalizer / TextPreprocessor / ResponseParser / AIProviders | ✅ 26 测试 |
| A3 | SentenceSplitter | ✅ 52 测试 |
| A4 | TableExtractor | ✅ 14 测试 |
| A5 | HtmlRenderer（markdown→HTML） | ✅ 64 测试 |
| A6 | SettingsManager / Store / 密钥抽象 | ✅ 84 测试 |
| C0 | 托盘外壳入口点 + WPF 构建 CI | ✅ 真机编译通过 |
| B1 | 截图选区（Core 几何 + GDI overlay） | ✅ 260 测试 + 编译过；运行期待 A 机手测 |
| B2–B4 | 取词 / OCR / 热键平台服务 | ⬜ 下一步 |

## 命令
```sh
# Mac 上跑 Core 测试（需要 .NET 8 SDK，已装在 ~/.dotnet）
sh windows/test-core.sh
```
- .NET SDK 8.0.425 已**用户级**装在 `~/.dotnet`（无需 sudo）；若 PATH 无 `dotnet`，脚本会自动用 `~/.dotnet/dotnet`。
- CI：`.github/workflows/windows-ci.yml`：ubuntu/windows 各跑 Core 测试 + **windows-latest 构建 Elta.Windows**。
  → 推送 `windows/**` 即自动真机编译验证外壳（C0 已由此验证通过）；运行期行为仍需真机手测。
- 真机验证通道：Mac 写代码 → `git push origin main` → Windows A 机 `cd C:\elta-spike && git pull` → `dotnet build windows\src\Elta.Windows -c Release` → 运行。

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
  - shell 字面量已脚本比对 Swift 原文，**逐字节一致**（3370 B）。A6 之前 `render`/`renderSplit` 的
    `providerShortName` 是显式参数（默认 `"DeepSeek"`），待 SettingsManager 落地后由调用方注入。
- **密钥**：DPAPI（Windows）替代 macOS Keychain。
- **OCR**：A+B 方案（优先系统 en-US 引擎 → 缺包时引导安装 → 自带兜底引擎）。
- **取词**：先 UIA（父链遍历）→ 失败回退 Ctrl+C + 剪贴板**深拷贝**恢复。
- **热键**：组合键 `RegisterHotKey`；裸键（ESC/`）用 `WH_KEYBOARD_LL`。
- **配置/密钥/默认值分层**（A6 定）：核心原则——**平台「方言」一律下沉到 Windows 外壳，Core 只管机制**。
  - 配置：Core 只定 `ISettingsStore`；Windows 具体实现（注册表 或 %APPDATA% JSON）留到 B/C。
  - 密钥：Core 只定 `ISecretStore`；Windows 实现（凭据管理器 CredMan〔更像 mac Keychain〕或 DPAPI 加密文件）留到 B/C。
  - 默认值：`SettingsDefaults` 参数化——测试用 `MacParity`（对齐 mac，供黄金测试），B4 用
    `MacParity with { ... }` 注入 Windows 键位/显示（如 `Ctrl+T`、Windows VK）。
  - 已知差异：`WindowFrame` 序列化为 `x,y,w,h`（invariant），**不兼容** mac `NSRect` 字符串；
    `installID` 用 `Guid`（小写）vs mac 大写 UUID，行为等价。键名沿用 `snaptranslate.*`。

## 下一步（按序）

### C0：托盘外壳入口点 ✅
- `Elta.Windows/Program.cs`（`[STAThread]` + WPF `Application` + WinForms `NotifyIcon` 托盘图标/退出菜单）+ `app.manifest`（PerMonitorV2）。
- CI 已在 windows-latest 真机编译通过（🟡 编译级）。运行期（托盘图标可见）待 A 机手测。

### B1：截图选区 ✅（Core TDD 完成，运行期待手测）
- **Core（Mac 可测，TDD）**：`ScreenshotGeometry.cs` —— `NormalizeSelection` / `IsSelectionUsable`（>10）/
  `MapSelectionToImage`（选区→像素裁剪，`originBottomLeft` 区分 mac/Windows，`round` 远离零）/ `IndexOfScreenContaining`。
  20 单测见 `ScreenshotGeometryTests.cs`。
- **外壳**：`ScreenCapture.cs`（GDI）、`ScreenshotSelector.cs`（**WinForms** 全屏 overlay，物理像素坐标——
  刻意不用 WPF Window 以规避多屏 DIP 错位）、`ScreenshotService.cs`、`PreviewForm.cs`；
  `HotkeyHost.cs`（全局热键 **Ctrl+T**，B1 临时；正式默认值归 B4）。托盘菜单 + 热键两条触发路径。
- ⚠️ **Windows 托盘图标只在主屏任务栏** → 副屏测试必须用热键 Ctrl+T（鼠标在哪块屏就截哪块）。
- **运行方式**（两条，代码同源）：
  1. `git clone https://github.com/liuxiaominglove/elta.git`（public）→ 仓库内 `windows\运行ELTA.bat`，或
     `dotnet run --project windows\src\Elta.Windows\Elta.Windows.csproj -c Release`。
  2. U 盘 `ELTA-Windows-B1\`（源码 + 运行ELTA.bat + 操作说明；**注意 U 盘快照可能落后于仓库**）。
- **A 机手测步骤**：见 U 盘 `ELTA-Windows-B1-操作说明.txt` 第 4 节；重点=扩展屏副屏 + 150% 各框选一次。

### WI-B2–B4：平台服务（Windows 真机）
- 源：`Sources/ScreenshotEngine.swift`、`OverlayView.swift`、`TranslationPipeline.swift`（取词/剪贴板）、
  `HotkeyHelpers.swift`、`OCREngine.swift`、`Helpers.swift`（PasteboardSnapshot 对应剪贴板快照）。
- 做法：把可测的**纯逻辑**（坐标/DPI 换算、剪贴板快照序列化、热键解析、OCR 语言策略）放 `Elta.Core` 用假实现单测；
  Win32/WinRT 调用放 `Elta.Windows`，在 Windows 上做集成测试。
- **建议顺序 B1 截图 ✅ → B2 取词 → B3 OCR → B4 热键**。
- B4 需同时落地：**Windows 配置存储实现 + 密钥库实现 + Windows 版 `SettingsDefaults`**（A6 只定了接口）。
- A6 未移植（归 B4/C）：`HotkeyRecorder`（UI）、`computeProviderCardLayout`（UI 布局）。
- 可复用 P0.5 已验证代码：`windows/spike/SpikeWindow.cs` 的 P/Invoke（`RegisterHotKey`/`SetWindowsHookEx`/
  `keybd_event`/`MonitorFromPoint`/`GetDpiForMonitor`）、截图、UIA、剪贴板快照。

## P0.5 已验证结论（真机）
- 🟢 截图：GDI `CopyFromScreen` + 物理像素换算，100%/150% 均正确；**多屏热切换会错位** → 正式实现要截「鼠标所在屏」。
- 🟢 热键：`RegisterHotKey` 可用；`WH_KEYBOARD_LL` 双向可收（他程序 + 本窗口），无杀软拦截。
- 🟡 取词：UIA 在记事本/Edge/控制台可用；Chrome、WPS 文字、WPS PDF **读不到** → Ctrl+C 兜底必须为主路径。
- ⚠️ OCR：装了英文包识别质量极好；没装则很差 → A+B 方案。
- 目标机：**A 机**（1366×768 + 1280×800 双屏，已装英文 OCR）。
- Demo 与结果：`windows/spike/`（源码）；结果 txt 另见 U 盘 / `~/relay-handoff/`。

## 待办 / 风险
- Windows 仓库策略：**方案 B**——移植期先留 `windows/` 于主仓库，B/C 完成后用 `git subtree split -P windows`
  拆成独立仓库 `elta-windows`（保留历史）。
- 运行期验证需 A 机手测（CI 只做编译级）。
