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

:: B4 机侧测试（配置存储 / DPAPI 密钥库 / 键盘钩子 / 设置接线）
powershell -ExecutionPolicy Bypass -File windows\test-settings.ps1

:: 单项诊断（不启动托盘）
...\Elta.Windows.exe --selftest                   :: 剪贴板策略集成自检 → %TEMP%\elta-selftest.txt
...\Elta.Windows.exe --selection-cli <输出文件>   :: 绕过 UIA 直跑 Ctrl+C 兜底取词
...\Elta.Windows.exe --selection-selftest <输出>  :: 与 RunSelection 同路径（STA + UIA 看门狗）
...\Elta.Windows.exe --settings-selftest <输出>   :: 配置存储 / DPAPI 密钥库 / 默认值自检
...\Elta.Windows.exe --hook-selftest <输出>       :: 低级键盘钩子安装 + 注入触发自检
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
> **B3 已完成 🟢**；**P0/P1 机测通过 🟢**；**B4（配置存储 / DPAPI 密钥库 / Windows 默认值 / 热键服务）机测通过 🟢**
> （`windows/test-clipboard.ps1`、`windows/test-p1.ps1`、`windows/test-settings.ps1`）。下一步 **子计划 C**（设置/结果窗口/翻译接线）。

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

### B4：Windows 配置存储 / 密钥库 / 热键平台服务 ✅（机测通过）
- **Core**：`WindowsHotkeys`（VK↔可读名、键码夹取、修饰键判定；17 测试）+ `SettingsDefaults.Windows`
  （Ctrl+T / Ctrl+Shift+T / Esc / `` ` `` / Ctrl+D，其余值沿用 mac 对齐）。
- **外壳存储**：
  - `JsonSettingsStore`：`%APPDATA%\ELTA\settings.json`，整文件原子写、损坏自动备份 `.corrupt-*`。
    **踩坑修复**：① .NET 8 `JsonNode.ToJsonString(options)` 复用前需给 `TypeInfoResolver`；
    ② 泛型 `T? GetValue<T>` 对 `int/bool` 缺失时返回 0/false（不是 null）→ 默认值永不生效；
    改为按类型显式实现，并在 `--settings-selftest` 增加「缺失键必须为 null」回归断言。
  - `DpapiSecretStore`：`%APPDATA%\ELTA\secrets\` 每账户一文件，文件名 = SHA256(account)，内容 DPAPI(CurrentUser)；
    `Save` update-or-add、`Delete` 幂等；日志只含账户哈希前缀，**绝不出现密钥内容**。
- **热键服务**：`HotkeyManager` 从 `SettingsManager` 读取键位（清洗键码/掩码，防 mac Carbon 残留）；
  新增 `LowLevelKeyboardHook`（WH_KEYBOARD_LL）供**裸键**（ESC/`` ` ``）用——**仅应在面板打开期间启停，B4 不常驻**
  （子计划 C 接线）。
- **接线**：托盘菜单/气泡/启动日志均用设置里的热键显示；启动日志含 `settings provider=… model=… keySet=… hotkey=…`
  （只记 key 是否存在，**不打印 Key**）。
- **机测 ✅**（`windows/test-settings.ps1`）：`--settings-selftest`（存储 round-trip/持久化/缺失键/DPAPI/默认值）、
  `--hook-selftest`（钩子安装 + 注入 F13 触发）、托盘启动 + 设置接线日志 + 默认热键注册；P0/P1 回归全过。
- ⚠️ 未做（归后续）：设置 UI（C）、裸键钩子常驻策略（C）、更新检查 / 遥测上报（mac 有，Windows 后续）。

### 子计划 C：设置 / 结果窗口 / 翻译接线
- 源：`Sources/HotkeyHelpers.swift`。
- A6 未移植（归 C3）：`HotkeyRecorder`（UI）、`computeProviderCardLayout`（UI 布局）。
- 可复用 P0.5 已验证代码：`windows/spike/SpikeWindow.cs` 的 P/Invoke（`RegisterHotKey`/`SetWindowsHookEx`/
  `keybd_event`/`MonitorFromPoint`/`GetDpiForMonitor`）。

#### C1：翻译链路 MVP ✅（编译 + 单测绿；真实 API 成功路径待配 Key 手测 🟡）
- Core：`TranslationLogic.cs`（user 前缀 / `BuildChatBody` / `Classify`，对齐 mac `TranslationEngine`；
  +9 测试，Core **341 绿**）。
- 外壳：`TranslationService.cs`（HttpClient / Bearer / 120s / 取消旧请求）、`ResultWindow.cs`（WPF + WebView2，
  装载 `HtmlRenderer` 输出）；`Elta.Windows.csproj` 新增 `Microsoft.Web.WebView2 1.0.4258.31`
  （本机运行时 154.0.4258.53 已装）。
- 接线：`RunScreenshot` / `RunSelection` 识别/取词成功 → `TranslateAndShowAsync` → 结果窗口；
  MissingKey / Failure 弹窗；翻译不进 busy 守卫（服务自带取消旧请求）。
- 冒烟（本机 2026-10-03）：划词 62 字符 → 日志 `translate missing key`（keySet=False）→ 缺 Key 分支正确。
- **真机 E2E ✅（2026-10-03，配真实 Key 后）**：划词 128 字符 → `translate http=200 chars=280` → `result window shown`；
  截图 787×118 → OCR 2 块 → `translate http=200 chars=289` → `result window shown`（两条触发路径均通）。
- 待办（C2）：结果窗口整段/拆分 / A± 字号 / 面板定位 / ESC·`` ` ``·Ctrl+D（裸键钩子接线）+ 字号持久化。

#### C3a：设置窗口「通用」页 ✅（渲染 + 测试连接负路径冒烟 🟢；真实 Key 的保存/翻译 E2E 待手测）
- 新增 `SettingsWindow.cs`（WPF 代码布局）：通用页 = provider / 模型 / API Key（密文+明文切换）/ 测试连接 /
  匿名统计；快捷键与模板页为占位（C3b/C3c）。底栏 = 保存并应用 / 恢复默认（API Key 除外，对齐 mac）/ 版本号。
- 新增 `ConnectionProbe.cs`（10s 超时；HTTP 分类复用 Core `ConnectionResult`）+
  Core `TranslationLogic.BuildProbeBody`（mac 同款最小请求，+1 测试，Core **342 绿**）。
- 接线：托盘新增「设置…」；缺 Key 弹窗可跳设置；保存/恢复默认后 `HotkeyManager.Reset()` + 重注册
  （新增 `HotkeyHost.Unregister` / `HotkeyManager.Reset`）；调试入口 `--settings-ui`（无托盘直开设置）。
- 冒烟（本机 2026-10-03）：假 Key → 日志 `probe http=401` + UI「API Key 无效 (HTTP 401)」✓；
  provider 切换即落盘旧 provider 的 key/模型（mac 语义）。
- **真机 E2E ✅（2026-10-03，真实 Key）**：测试连接 200 → 保存（`Keychain 写入 len=35` + `settings saved keyLen=35`）→
  划词/截图两条链路均翻译成功并弹出结果窗口。

#### C3b：设置窗口「快捷键」页 ✅（录键/恢复默认机测通过 🟢）
- Core `HotkeyConflicts`（Windows 冲突表：Ctrl 常用键 / Alt+F4·Tab / Ctrl+Shift+Esc / Win 组合 / Ctrl+Alt+Del）
  + 7 测试（Core **349 绿**）。
- 外壳 `HotkeyRecorder`：10s 超时、裸键白名单（关闭面板 Esc / 切换位置 `` ` ``）、需修饰键校验、录制即冲突提示。
- 「快捷键」页：5 行录制器 + 默认优先弹窗（整段/拆分）；保存前收集冲突统一二次确认；恢复默认同步复位录制器。
- 踩坑：WPF `PreviewKeyDown` 会把**修饰键本身**也送进来（mac 的 flagsChanged 不会）→ 第一版录成 `Ctrl+0xA2`（LeftCtrl）；
  已加纯修饰键过滤（`IsModifierKey` 忽略并继续等待主键）。
- 机测（本机 2026-10-03，`--settings-ui` + UIA/SendKeys 自动化）：录制 Ctrl+Shift+Y → 按钮/状态正确；
  恢复默认 → 确认框 → 全部复位为默认（日志 `settings reset to defaults (api key kept)`）。

#### C3c：设置窗口「模板」页 ✅（保存/恢复默认机测通过 🟢）
- UI 对齐 mac：默认模板（只读展示内置提示词）/ 自定义模板（可编辑，等宽字体）双态切换 + 状态文案。
- 保存走 Core `TemplateLogic.ResolveSave` 三分支（保持默认 / 存自定义 / 清空回退默认）；恢复默认同步复位 UI。
- 机测（`--settings-ui` 自动化 2026-10-03）：只读/可编辑切换正确；保存 → `settings.json` 写入
  `prompt.custom` + `usesDefault=false`；恢复默认 → `usesDefault=true` 且 `custom` 清除（净零）。
- **设置窗口三页（通用 / 快捷键 / 模板）全部落地**。

#### C2：结果窗口交互（完整对齐 mac）✅（自动 E2E 全过 🟢；深色主题路径 🟡 未实测）
- Core：`ResultPanelGeometry`（对侧半屏 + saved frame 夹紧/回退；+9 测试，Core **358 绿**）。
- 结果窗重写 `ResultWindow`：工具栏（整段/拆分用 `Checked` 事件，兼容鼠标与 UIA/无障碍；不可拆则禁用）+
  A−/A＋（12–22 即改即存）+ WebView2（禁 JS）；初始模式 = `ShouldStartSplit(DefaultSplitMode, CanSplit)`；
  非激活悬浮（ShowActivated=false + Topmost）；定位 = 选区对侧半屏（划词用鼠标锚点）；
  `Closing` 时写回 `WindowFrame`，下次展示复用高度/纵向位置。
- `LoadingWindow`（300×140 靠鼠标）+ `PanelKeyRouter`（复用 `LowLevelKeyboardHook`，仅面板/加载期间启停；
  `GetAsyncKeyState` 判定修饰键）+ `TranslationService.CancelCurrent`；`ScreenshotService` 暴露选区屏幕矩形。
- 键位取自设置：Esc=关闭/取消、`` ` ``=翻面、Ctrl+D=拆分（与 mac 语义一致；加载期只响应 Esc 取消）。
- 自动 E2E（本机 2026-10-03，真实 Key）：
  - 划词链：面板对侧定位✓、默认拆分✓、整段切换✓、A＋ 持久化（14→15）✓、A−（15→14→13；下界 12 由 Core 夹紧）✓、
    `` ` ``翻面✓、Ctrl+D 拆分✓、Esc 关闭✓；加载期 Esc 取消（`panel key: cancel translation` → `translate cancelled`）✓；
    窗口记忆（移/缩到 y=120/h=450 → 关闭 → 重开复用）✓。
  - 截图链（合成拖拽 460×150 框选）：captured → OCR Ok → translate Success → 面板对侧 ✓ → Esc ✓。
- 深色主题：代码路径就绪（读 `AppsUseLightTheme`），本机浅色实测；深色未切换系统主题验证 🟡。

#### C2 自查加固（grill 后修复，2026-10-03）✅
- **任务代数守卫（对齐 mac `currentTaskGeneration`）**：新增 `_pipelineGeneration`，流水线起点递增、所有异步边界校验。
  修两个真 bug：① 连按两次划词时旧任务回调会误关新任务的加载窗/弹陈旧结果；② OCR 阶段 ESC 无效（现 ESC 取消整个流水线）。
- **裸键路由与 mac 对齐**：结果窗与加载窗短暂并存（旧结果 + 新任务加载）时，Esc 现在**两个动作都执行**
  （此前 loading 分支提前 return，会吞掉"关旧面板"）。回归：`test-c2.ps1` B/C/D/E 全过。
- **跨屏 DPI 修复**：窗口移到不同 DPI 显示器时 WPF 会按 DIP 覆盖 `SetWindowPos` 的物理矩形（实测副屏上被改成 960×813）；
  现监听 `DpiChanged` 并在 Loaded 收尾重套几何，实测副屏窗口 = 右半屏 640×760 精确值。回归：`test-c2.ps1` F1。
- **A± 单位修正**：`ResultWindow` 的 Min 尺寸按目标屏 DPI 换算（几何常量是物理像素）。
- **冲突降噪**：新增 `HotkeyConflicts.CheckUnlessDefault`——重录成该动作自身默认键不再弹冲突提示（+2 测试）。
- **isDark 每渲染现读**：运行中切系统主题可生效（实测 `dark=True` 🟢，测毕已还原主题）。
- **退出清理**：`app.Exit` 停低级钩子；`--settings-ui` 检测到托盘实例时日志提示共用配置。
- **机测脚本入库**（UTF-8+BOM，仓库惯例）：
  - `windows/test-c2.ps1`：22 用例（交互/竞态/取消/记忆/截图链/副屏/A− 边界），需 Key，无 Key 退出码 3；
  - `windows/test-c3.ps1`：14 用例（设置三页离线流程）。
- 最终验证：Core **360 绿**；`test-c3.ps1` 14/14；`test-c2.ps1` 22/22（副屏现为 1280×800，F 段按实时屏幕校验）。

## P0.5 已验证结论（真机）

### A 机（初次，2026-09）
- 🟢 截图：GDI `CopyFromScreen` + 物理像素换算，100%/150% 均正确；**多屏热切换会错位** → 正式实现要截「鼠标所在屏」。
- 🟢 热键：`RegisterHotKey` 可用；`WH_KEYBOARD_LL` 双向可收（他程序 + 本窗口），无杀软拦截。
- 🟡 取词：UIA 在记事本/Edge/控制台可用；Chrome、WPS 文字、WPS PDF **读不到** → Ctrl+C 兜底必须为主路径。
- ⚠️ OCR：装了英文包识别质量极好；没装则很差 → A+B 方案。
- 目标机：**A 机**（1366×768 + 1280×800 双屏，已装英文 OCR）。
- Demo 与结果：`windows/spike/`（源码）；结果 txt 另见 U 盘 / `~/relay-handoff/`。

### 复测（2026-10-03，Win10 22H2 build 19045 / .NET 8.0.425；1366×768@100% + 1920×1200@150% 双屏）
- 🟢 U 盘 7 项版全部通过：OCR 语言 `en-US` + `zh-Hans-CN`、行/词级框可用（表格图按列聚合，需按词框坐标重建行列）；
  坐标换算在 100% / 125% / 150% 均「命中红色=True」；记事本 / Chrome / Edge UIA 取词成功（142 / 136 / 136 字符）；
  Ctrl+C 取词 + 剪贴板图片完整恢复；Ctrl+T 注册成功并收到 `WM_HOTKEY`；LL 钩子双向可收（3/3），Defender 无报警。
- 🟡 修正：A 机「Chrome 读不到 UIA」属**版本相关**——新版 Chrome/Edge 已暴露 UIA TextPattern；取词主路径仍保留
  Ctrl+C（旧版 / WPS / 中文场景更稳），原决策不变。
- ⚠️ 本机主屏（LGD044C / Intel HD）标准缩放档位仅 100%/125%（无 150%，驱动/面板限制）→ 150% 复测在副屏
  （RTK1601 / AMD，原生 150%）临时切为主屏完成，测毕两组设置均已还原。
- 🟢 编译：U 盘快照缺 `using System.Windows.Automation.Text`（CS0246）；本仓库 `windows/spike/SpikeWindow.cs`
  已修复并真机编译通过（0 error；仓库 8 项版的第 8 项仅语言包引导页，未单独跑）。
- 结果文件：U 盘 `ELTA-Windows-P0.5\results\`（`spike.log` / `capture.png` / `changes.diff`）。

## 待办 / 风险
- Windows 仓库策略：**方案 B**——移植期先留 `windows/` 于主仓库，B/C 完成后用 `git subtree split -P windows`
  拆成独立仓库 `elta-windows`（保留历史）。
- 运行期验证需 A 机手测（CI 只做编译级）。
- **回传**（2026-10-02）：本地全部未推送 commit 已打包到 U 盘
  `F:\ELTA-Windows-B3\elta-main-incremental-2026-10-02.bundle`（`git bundle verify` 通过；清单见同目录 `commits.txt`）；
  Mac 侧 `git pull <bundle> main && git push origin main`。数量以 `commits.txt` / `git rev-list --count origin/main..main` 为准。
- **回传**（2026-10-03）：本地全部未推送 commit（P0.5 复测归档 + C1 翻译链路 + C3 设置三页 + C2 结果窗）已打包到 U 盘
  `E:\elta-main-incremental-2026-10-03.bundle`（`git bundle verify` 通过；清单见 `E:\elta-commits-2026-10-03.txt`）；
  Mac 侧 `git pull <bundle> main && git push origin main`。数量以清单 / `git rev-list --count origin/main..main` 为准。
- 同日另附**全量 bundle**（`--all`，自包含、可独立 clone，灾备用）：`E:\elta-full-2026-10-03.bundle`。
