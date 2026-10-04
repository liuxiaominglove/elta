# ELTA Windows — P0.5 能力验证（Spike）

**目的**：在投入正式开发前，在 Windows 真机上验证 4 个高风险平台能力，把它们打成「已验证」或暴露问题。

> ⚠️ 只在 Windows 上编译运行（WPF + WinRT），macOS 无法构建。
> 🟢 已在真机编译通过（2026-10-03，修复 `CS0246` 缺 `using System.Windows.Automation.Text` 后，0 error；WFAC010 警告为 manifest 高 DPI 刻意配置）。
> 实测结论见 `windows/NOTES.md`「P0.5 已验证结论」。

## 1. 前置条件

1. **Windows 10 21H1+（build 19041）或 Windows 11**。
2. **.NET 8 SDK**：`winget install Microsoft.DotNet.SDK.8` 或运行 U 盘里 `installers\dotnet-sdk-8.0-win-x64.exe`。
3. 样例图在 `samples\`（英文段落、英文表格各一张）。

## 2. 运行

```bat
cd windows\spike
dotnet run -c Release
```

结果同时显示在窗口内，并写入 `bin\...\spike.log`。

## 3. 八个测试与判定

| # | 测试 | 操作 | 通过标准 |
|---|------|------|---------|
| 1 | OCR 语言清单 | 点按钮 | 是否含 `en-*` 与 `zh-*`；是否能建 en-US 引擎 |
| 2 | OCR 识别图片 | 选 `samples\sample_english.png` 与 `sample_table.png` | 能出文本；**能打印词级边界框**；记录实际用的引擎语言 |
| 3 | 截图 + DPI | 直接点按钮（程序自建独立红色标记窗口并采样） | 「命中红色=True」；**100% 与 150% 缩放各测一次** |
| 4 | UIA 读选中 | 点后**窗口自动最小化 4 秒**，期间切到目标程序选中文本 | 记事本 / Chrome / Edge / Word / PDF 逐个记录 |
| 5 | Ctrl+C 兜底 | 点后 3 秒内选中文本 | 取到文本；恢复剪贴板后原内容仍在 |
| 6 | 注册全局热键 | 点后按 Ctrl+T | 出现「收到 WM_HOTKEY」 |
| 7 | 低层键盘钩子 | 点后 **15 秒内**：先切到别的程序按键，再切回本窗口按键 | 「他程序」计数 > 0；记录杀软反应 |
| 8 | 打开语言/OCR 设置 | 点按钮 | 打开系统语言设置，用于装英文 OCR 包 |

**测 DPI（测试 3）时务必**：显示设置 → 缩放切到 **150%** 后重跑一次。

## 4. 回报模板

把 `spike.log` 整理回传：

```
[环境] Win10 build=____  dotnet=____
[OCR]  语言=____  可建en引擎=是/否  引擎语言=____  拿到词框=是/否
[截图] 100%命中红=是/否  150%命中红=是/否  副屏=是/否
[UIA]  记事本=__ Chrome=__ Edge=__ Word=__ PDF=__
[剪贴板] 取词=是/否  富文本/图片恢复=是/否
[热键] Ctrl+T=成功/失败
[钩子] 他程序计数=__  本窗口钩子计数=__  本窗口对照=__  杀软=____
```

## 5. 结果 → 架构决策

| 若结果是 | 则调整 |
|---|---|
| 缺英文 OCR 包 | 采用 **A+B**：优先系统英文 OCR；缺包时引导安装（测试 8 的设置入口）；仍不行用兜底引擎（PaddleOCR/Tesseract） |
| 拿不到词级边界框 | `TableExtractor` 需改算法 |
| 150% 下标记不命中 | 截图改用 WGC（`Windows.Graphics.Capture`）替代 GDI `CopyFromScreen` |
| UIA 大面积失败 | Ctrl+C 升为主取词路径，UIA 降为优化项 |
| 杀软拦截钩子 | 提前把代码签名提上日程；或以 `RegisterHotKey` 组合键为主 |
| 本窗口收不到钩子但对照有键 | 本窗口内用 WPF `PreviewKeyDown` 兜底（正常取舍） |

## 6. 文件说明

| 文件 | 说明 |
|---|---|
| `EltaSpike.csproj` | TFM `net8.0-windows10.0.19041.0`（WinRT 必需）；WPF + WinForms；x64 |
| `app.manifest` | **PerMonitorV2** DPI 感知；`asInvoker` |
| `SpikeWindow.cs` | 全部 8 个测试的实现 |
