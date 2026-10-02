# ELTA Windows 版 — 交接说明（NOTES）

> 新会话开头 `@windows/NOTES.md` 即可续上。本文件是进度与决策的唯一交接记录。

## 目标
把 macOS 版 ELTA（Swift/AppKit，仓库根 `Sources/`）移植为 **Windows 版**，技术栈
**C# / .NET 8 WPF + WebView2**。地址：`windows/`，架构：三段式
（Core 纯逻辑 / 平台外壳 / 共享 HTML）。

## 当前进度
Core 已完成 **A1–A6**；外壳 **C0**、平台服务 **B1/B2/B3** 见下表。**Core 303 测试全绿**（B3 新增 `OcrGeometry` 20 条）。

| WI | 内容 | 状态 |
|----|------|------|
| A1 | solution 骨架 + CI + 测试脚本 | ✅ |
| A2 | TextNormalizer / TextPreprocessor / ResponseParser / AIProviders | ✅ 26 测试 |
| A3 | SentenceSplitter | ✅ 52 测试 |
| A4 | TableExtractor | ✅ 14 测试 |
| A5 | HtmlRenderer（markdown→HTML） | ✅ 64 测试 |
| A6 | SettingsManager / Store / 密钥抽象 | ✅ 84 测试 |
| C0 | 托盘外壳入口点 + WPF 构建 CI | ✅ 真机编译通过 |
| B1 | 截图选区（Core 几何 + GDI overlay） | ✅ 260 测试 + 编译 + **A 机手测全通过** |
| B2 | 取词（UIA → Ctrl+C 兜底 + 剪贴板恢复） | ✅ Core 283 + 编译 + **A 机手测通过**（Word/WPS 待人工抽检） |
| B3 | OCR（WinRT Windows.Media.Ocr → 行级 OcrBlock） | ✅ Core 303 + 编译 + 自动验证 + **A 机手测全通过** |
| B4 | 热键平台服务 + Windows 配置/密钥/默认值落地 | ⬜ 下一步 |

## 命令
```sh
# Mac 上跑 Core 测试（需要 .NET 8 SDK，已装在 ~/.dotnet）
sh windows/test-core.sh
```

```bat
:: 无头 OCR 诊断（自动验证 B3 代码路径；不启动托盘），结果写 <图片>.ocr.txt
windows\src\Elta.Windows\bin\Release\net8.0-windows10.0.19041.0\Elta.Windows.exe --ocr <图片路径>

:: 剪贴板安全机侧测试（WI-1）：策略集成 + 记事本端到端，全过退出码 0
powershell -ExecutionPolicy Bypass -File windows\test-clipboard.ps1

:: P1 机侧测试（WI-3 取词 STA/UIA 看门狗 + WI-4 热键自愈）
powershell -ExecutionPolicy Bypass -File windows\test-p1.ps1

:: 单项诊断（不启动托盘）
...\Elta.Windows.exe --selftest                   :: 剪贴板策略集成自检 → %TEMP%\elta-selftest.txt
...\Elta.Windows.exe --selection-cli <输出文件>   :: 绕过 UIA 直跑 Ctrl+C 兜底取词
...\Elta.Windows.exe --selection-selftest <输出>  :: 与 RunSelection 同路径（STA + UIA 看门狗）
```
- .NET SDK 8.0.425 已**用户级**装在 `~/.dotnet`（无需 sudo）；若 PATH 无 `dotnet`，脚本会自动用 `~/.dotnet/dotnet`。
- CI：`.github/workflows/windows-ci.yml`：ubuntu/windows 各跑 Core 测试 + **windows-latest 构建 Elta.Windows**。
  → 推送 `windows/**` 即自动真机编译验证外壳（C0 已由此验证通过）；运行期行为仍需真机手测。
- 开发通道：**主 = git**（Mac 写 → `git push` → Windows `git clone/pull`；仓库 public，免认证）。
  **Windows 侧 git 只读、不 push**；Windows 上的改动经 **U 盘 / Syncthing 回传**（或由 Mac 侧代为提交）。U 盘仅作**离线兜底**。
- Windows 侧构建/测试/运行命令见 `windows/AGENTS.md`。

## 目录
```
windows/
  Elta.sln
  src/Elta.Core/            # net8.0 纯逻辑（Mac 可编译）
  src/Elta.Windows/         # net8.0-windows10.0.19041.0 WPF 外壳（仅 Windows 编译）
  tests/Elta.Core.Tests/    # xUnit
  test-core.sh              # Mac 跑 Core 测试
  test-core.bat             # Windows 跑 Core 测试
  运行ELTA.bat              # Windows 编译并运行外壳
  AGENTS.md                 # Windows 侧开发约定
  spike/                    # P0.5 能力验证 Demo（已跑完，见下文）
```
> `bin/`、`obj/` 已在根 `.gitignore` 中忽略；`windows/**` 已提交到主仓库
> （方案 B：移植完成后再 `git subtree split -P windows` 拆成独立仓库）。

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
  - **语言：仅 `en-US`**——产品确认截图源域为**纯英文**，不做中文兜底（见 `docs/adr/0003-ocr-english-only.md`）。
- **取词**：先 UIA（父链遍历）→ 失败回退 Ctrl+C + 剪贴板**深拷贝**恢复。
- **热键**：组合键 `RegisterHotKey`；裸键（ESC/`）用 `WH_KEYBOARD_LL`。
- **单实例**：托盘用互斥锁 `Local\Elta.Windows.SingleInstance` 守卫——第二实例提示后退出，
  防止「进程在跑但注册不到热键」的僵尸实例（`--ocr` 无头模式不受守卫影响）。
- **配置/密钥/默认值分层**（A6 定）：核心原则——**平台「方言」一律下沉到 Windows 外壳，Core 只管机制**。
  - 配置：Core 只定 `ISettingsStore`；Windows 具体实现（注册表 或 %APPDATA% JSON）留到 B/C。
  - 密钥：Core 只定 `ISecretStore`；Windows 实现（凭据管理器 CredMan〔更像 mac Keychain〕或 DPAPI 加密文件）留到 B/C。
  - 默认值：`SettingsDefaults` 参数化——测试用 `MacParity`（对齐 mac，供黄金测试），B4 用
    `MacParity with { ... }` 注入 Windows 键位/显示（如 `Ctrl+T`、Windows VK）。
  - 已知差异：`WindowFrame` 序列化为 `x,y,w,h`（invariant），**不兼容** mac `NSRect` 字符串；
    `installID` 用 `Guid`（小写）vs mac 大写 UUID，行为等价。键名沿用 `snaptranslate.*`。

## 下一步（按序）

> **0) B2 已通过**（`回传-B2.txt`，Win10，零 Fail）：记事本（单行/多行/中英混合）、Chrome、Edge 取词；
> 剪贴板恢复（UIA 路径与 Ctrl+C 兜底路径的文本/图片/空/大文本/emoji）全部通过；Ctrl+T 截图回归正常。
> Word/WPS 文字/WPS PDF 因自动化限制未跑（非失败）→ 建议人工各抽检一次，即可升 🟢。
> **B3 已完成 🟢**；**P0（剪贴板安全 / 日志兜底）与 P1（取词线程化 / 热键自愈）机测通过 🟢**
> （`windows/test-clipboard.ps1`、`windows/test-p1.ps1`）。下一步 **B4**（热键 + Windows 配置/密钥/默认值落地）。

### C0：托盘外壳入口点 ✅
- `Elta.Windows/Program.cs`（`[STAThread]` + WPF `Application` + WinForms `NotifyIcon` 托盘图标/退出菜单）+ `app.manifest`（PerMonitorV2）。
- CI 已在 windows-latest 真机编译通过（🟡 编译级）。运行期（托盘图标可见）待 A 机手测。

### B1：截图选区 ✅（含 A 机真机验证）
- **A 机手测结果（`回传-B1.txt`，Win10 / 双屏扩展 / 100%+150%）**：托盘图标✓、气泡✓、Ctrl+T✓；
  主屏正向拖拽✓、反向拖拽✓、极小区域取消✓、ESC/右键取消✓、
  副屏（主屏触发后移过去）✓、副屏（Ctrl+T 触发）✓、150% 缩放✓、无报错。→ B1 收尾。
- **Core（Mac 可测，TDD）**：`ScreenshotGeometry.cs` —— `NormalizeSelection` / `IsSelectionUsable`（>10）/
  `MapSelectionToImage`（选区→像素裁剪，`originBottomLeft` 区分 mac/Windows，`round` 远离零）/ `IndexOfScreenContaining`。
  20 单测见 `ScreenshotGeometryTests.cs`。
- **外壳**：`ScreenCapture.cs`（GDI）、`ScreenshotSelector.cs`（**WinForms** overlay，横跨**整个虚拟桌面**
  `SystemInformation.VirtualScreen`，物理像素坐标——刻意不用 WPF Window，并设 `AutoScaleMode.None` 规避多屏 DIP 错位）、
  `ScreenshotService.cs`、`PreviewForm.cs`；`HotkeyHost.cs`（全局热键 **Ctrl+T**，B1 临时；正式默认值归 B4）。
  托盘菜单 + 热键两条触发路径。
- ⚠️ 覆盖层必须横跨所有显示器：否则从主屏（托盘所在的屏）触发后，副屏上十字光标会消失、无法框选。
- Windows 托盘图标只在主屏任务栏；热键 Ctrl+T 让鼠标停在哪块屏都能触发（非必需，但更方便）。
- **运行方式**（两条，代码同源）：
  1. `git clone https://github.com/liuxiaominglove/elta.git`（public）→ 仓库内 `windows\运行ELTA.bat`，或
     `dotnet run --project windows\src\Elta.Windows\Elta.Windows.csproj -c Release`。
  2. U 盘 `ELTA-Windows-B1\`（源码 + 运行ELTA.bat + 操作说明；**注意 U 盘快照可能落后于仓库**）。
- **A 机手测步骤**：见 U 盘 `ELTA-Windows-B1-操作说明.txt` 第 4 节；重点=扩展屏副屏 + 150% 各框选一次。

### B2：取词（UIA → Ctrl+C 兜底）✅（含 A 机手测）
- **A 机手测结果（`回传-B2.txt`，Win10，`Fail=0`）**：记事本 单行/多行/中英混合 ✓、空选提示 ✓；
  记事本/Chrome/Edge 取到 ✓；**剪贴板恢复**（UIA 路径 + Ctrl+C 兜底路径）的 文本/图片/空/大文本/emoji ✓；
  Ctrl+T 截图回归 ✓。**未自动跑**（非失败）：Word、WPS 文字、WPS PDF、托盘目视 → 建议人工抽检。
  自动化方法：PowerShell + Win32 P/Invoke 注入热键并读 MessageBox 文本、校验剪贴板（合成输入 🟡）。
- **Core（Mac 可测，TDD）**：`SelectionText`（`SubstringInRange` UTF-16 区间取子串 + `IsUsable`，移植 mac
  `substringInRange`）、`ClipboardAcceptPolicy`（`AcceptByChangeCount` / `AcceptByFallback`）。测试见
  `SelectionTextTests.cs` / `ClipboardAcceptPolicyTests.cs`。
- **外壳**：`SelectionReader.cs`（UIA `TextPattern`→父链上溯；失败回退 **Ctrl+C**：`keybd_event` + 剪贴板序号
  `GetClipboardSequenceNumber` 轮询 → 兜底比对旧文本）、`ClipboardService.cs`（**对象式深拷贝快照**+恢复，流拷进
  MemoryStream；空快照→清空）、`HotkeyHost` 改为支持多热键。
- ⚠️ 取词主路径是 **Ctrl+C**（P0.5：Chrome/WPS 读不到 UIA）。触发前 `Thread.Sleep(300)` 等用户松开热键，
  否则合成的 Ctrl+C 会带上 Shift。
- **A 机手测步骤**：运行后，在**记事本**选中一段英文 → 按 **Ctrl+Shift+T** → 应弹框显示「取到 N 字符」；
  再到 **Chrome / Edge / WPS / PDF** 各试一次（预期 Chrome/WPS 走 Ctrl+C 也能取到）；
  且**取词后原剪贴板内容仍在**（先复制一段别的内容再测）。
- 与 B1 不同：B2 目前只把取到的文本弹给用户看，**尚未接翻译**（B3/后续再接 AI）。

### B3：OCR（WinRT `Windows.Media.Ocr`）✅ 代码 / 🟡 真机手测待做
- **实现**：
  - Core：`OcrGeometry.cs`（`FitScale` 下采样因子 / `ScaleRect` 坐标回映射 / `UnionAll` 词框并集 /
    `ToLineBlock` 行级块），测试 `OcrGeometryTests.cs` 20 条。Core 303 全绿。
  - 外壳：`OcrService.cs`（`Bitmap → PNG → InMemoryRandomAccessStream → BitmapDecoder → SoftwareBitmap`；
    `TryCreateFromLanguage("en-US") ?? TryCreateFromUserProfileLanguages()`；每行 `OcrLine.Text` + 词框并集 → `OcrBlock`；
    图像长边超 `MaxImageDimension` 先等比缩小、识别后按 `1/scale` 回映射）。
  - `Program.cs`：`RunScreenshot` 改 `async void`——截图 → `await OcrService.RecognizeAsync` →
    `TableExtractor.Process` → `TextPreprocessor.CondenseCitation` → 弹框展示（沿用 B1/B2 调试形态；正式 UI 留 C）。
- **关键点**：`OcrLine` **无包围盒**（官方 API 只有 `Text`/`Words`），行盒必须取词框并集；
  行文本**直取 `OcrLine.Text`**，**不可** `join(" ")` 重建（否则中文字间被插空格）。
- **自动化验证（真机，走本客户端代码路径）✅**：
  - 新增无头入口 `Elta.Windows.exe --ocr <图片路径>`（不启动托盘）：跑 `OcrService.RecognizeAsync`，把
    `status / blocks / 文本 / 各块坐标` 写入 `<图片>.ocr.txt`（并尝试附加父控制台）。
  - 结果（本机）：
    - `sample_english.png` → `status=Ok, blocks=3`；3 行英文文本与行盒坐标正确。
    - `sample_table.png` → `status=Ok, blocks=5`；`TableExtractor` 正确输出 Markdown 表格（中文单元格因 en-US 为空）。
    - `sample_cjk.png` → `status=Ok, blocks=0`（印证 en-US 读不了中文）。
  - 平台级佐证（P0.5 spike `回传.txt`）：可用语言 `en-US, zh-Hans-CN`，可建 en-US 引擎，1200×380 英文段落/表格图均识别成功。
- **稳定性收尾**：`RunScreenshot`（`async void`）加 try/catch 兜底——异常不再导致进程崩溃；OCR 移入后台线程
  （`Task.Run`），避免位图编码/识别阻塞 UI；外壳启动冒烟通过（进程存活 5s 无崩溃）。
- **A 机手测（本机）✅**：`运行ELTA.bat` 启动 → Ctrl+T 框选英文 → 弹框文本正确 ✓；ESC 取消无异常 ✓；
  空白区 → 「未识别到文字」 ✓；托盘退出 ✓（表格项未单独测，逻辑已由 `--ocr` 覆盖）。
  踩坑记录：曾因**旧实例占用全局热键**导致新实例 Ctrl+T 失效（RegisterHotKey 失败且不重试）——
  已加**单实例守卫**（`Local\Elta.Windows.SingleInstance` 互斥锁，第二实例提示「已在运行」并退出）。
- **已知限制（已定为决策）**：仅 **en-US** 引擎；截图含中文时中文部分为空。产品已确认源文本域为**纯英文**，
  故**不做** zh 兜底（`docs/adr/0003-ocr-english-only.md`）。若未来扩大到中英混排，改用「en+zh 双引擎按 CJK 过滤合并」。
- **手测步骤（A 机）**：运行后 Ctrl+T 框选屏幕上一段英文 → 弹框应显示正确文本；
  框选一张英文表格 → 应输出 Markdown 表格；框选中文 → 预期为空或乱码（记录以便评估是否加 zh 兜底）；
  取消（ESC/右键）不报错。
- **样例图**：测试机本地目录 `C:\Users\admin\AppData\Local\Temp\opencode\elta-b3-samples\`
  （`sample_english.png` / `sample_table.png` / `sample_cjk.png`），仅生成未入库（如需入库请示）。

### 稳定性加固 P0：WI-1 剪贴板安全 / WI-2 日志与兜底 ✅（机测通过）
- **WI-1（数据安全）**：Core 新增 `ClipboardRestorePolicy`（12 测试）——捕获失败 / 被第三方改写 / 序号未变 → **不动**；
  确认原本为空 → 清空（去 Ctrl+C 残留）；原有内容 → 还原。
  外壳 `ClipboardState` 显式记录 `CaptureSucceeded`，剪贴板读写加退避重试，单格式 50MB 上限（标 `Partial`）；
  `SelectionReader` 按策略处置 + 第三方改写终检。
  → **杜绝「剪贴板读取失败 → `Clear()` 清空用户剪贴板」的数据丢失路径**。
- **WI-2（可诊断/不崩）**：新增 `Log`（`%LOCALAPPDATA%\ELTA\logs\elta-YYYYMMDD.log`；按天 + 保留 7 天 + 2MB 滚动；
  **只记状态/长度，不记内容**；写盘失败静默）；全局兜底（Dispatcher / AppDomain / UnobservedTask）+ `RunSelection` 包 catch；
  埋点：启动（版本/热键结果）、截图、OCR、取词、退出。
- **机侧自动验证 ✅**：
  - Core **315 绿**；外壳编译 0 错误；`--ocr` 回归 `status=Ok blocks=3`；托盘冒烟存活。
  - 新增 `--selftest`：剪贴板策略集成 **5/5**（文本还原 / 图片还原 / 捕获失败不清空 / 空→去残留 / 第三方不动）。
  - 新增 `--selection-cli <out>`：绕过 UIA 直跑 Ctrl+C 兜底（供脚本驱动）。
  - `windows/test-clipboard.ps1`：`--selftest` + 记事本端到端（真实 Ctrl+C 取词 46 字符 + **原剪贴板保留**）→ **ALL PASS**。
  - 日志实测落盘（`start` / `ocr` / `selection` / `selftest`）。
- ⚠️ **仍未自动化**：真实 `Ctrl+Shift+T` 热键入口、Chrome/Edge（UIA 失败→Ctrl+C）路径、图片原剪贴板走真实取词。
  如需覆盖可在 `test-clipboard.ps1` 扩展（Chrome 需额外自动化）。

### 稳定性加固 P1：WI-3 取词线程化 + UIA 看门狗 / WI-4 热键自愈 ✅（机测通过）
- **WI-3**：
  - 取词移入**专用 STA 工作线程**（`StaRunner`；WinForms 剪贴板要求 STA）——UI 不再被 `Sleep(300)` + 轮询冻结。
  - UIA 跨进程调用加**看门狗**：放 MTA 子线程 `Join(500ms)`，超时记 `uia timeout` 并回落 Ctrl+C（被放弃线程为后台线程）。
  - **全局重入守卫**（`Interlocked`）：截图/取词/OCR 任一在跑时忽略新触发（日志 `ignored: busy`）。
- **WI-4**：`HotkeyManager`——注册失败每 **10s 重试**，占用解除后自动恢复；日志与托盘提示同步
  （`hotkey busy` → `hotkey registered` → `hotkey recovered` → `hotkeys all registered`）。
- **机测 ✅**（`windows/test-p1.ps1`）：
  - `--selection-selftest`（STA + UIA 路径）取到文本 ✓
  - 热键自愈：后台占用 Ctrl+T → 启动检测到 `hotkey busy` / `pending:shot` → 释放占用 → ≤14s 自动
    `hotkey registered name=shot` + `hotkey recovered` ✓
  - P0 回归 `test-clipboard.ps1` 仍 **ALL PASS** ✓
- ⚠️ 踩坑：`.ps1` 必须存为 **UTF-8 带 BOM**，否则 PowerShell 5.1 按 ANSI 解析中文会语法错误（两个脚本已加 BOM）。
- 仍未自动化：真实 `Ctrl+Shift+T` 热键入口、Chrome/Edge（UIA 失败→Ctrl+C）路径。

### WI-B4：热键平台服务（下一步）
- 源：`Sources/HotkeyHelpers.swift`。
- B4 需同时落地：**Windows 配置存储实现 + 密钥库实现 + Windows 版 `SettingsDefaults`**（A6 只定了接口）；
  OCR 兜底引擎（B）视 B3 手测结果再定。
- A6 未移植（归 B4/C）：`HotkeyRecorder`（UI）、`computeProviderCardLayout`（UI 布局）。
- 可复用 P0.5 已验证代码：`windows/spike/SpikeWindow.cs` 的 P/Invoke（`RegisterHotKey`/`SetWindowsHookEx`/
  `keybd_event`/`MonitorFromPoint`/`GetDpiForMonitor`）。

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
- **回传**（2026-10-02）：B3 + P0 共 6 个 commit 已打包到 U 盘
  `F:\ELTA-Windows-B3\elta-main-incremental-2026-10-02.bundle`（`git bundle verify` 通过）；
  Mac 侧 `git pull <bundle> main && git push origin main`。
