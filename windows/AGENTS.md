# AGENTS.md — ELTA Windows 版（`windows/`）

> 本目录是 macOS 版 ELTA（仓库根 `Sources/`，Swift/AppKit）的 **Windows 移植**。
> **进度与决策的唯一交接记录是 `windows/NOTES.md`——开工先读它。**

## 技术栈与结构

| 目录 | 说明 |
|------|------|
| `src/Elta.Core/` | `net8.0` 纯逻辑（跨平台，Mac 也能编） |
| `src/Elta.Windows/` | `net8.0-windows10.0.19041.0`，WPF + WinForms（**仅 Windows 编译**） |
| `tests/Elta.Core.Tests/` | xUnit |
| `Elta.sln` | 解决方案 |

架构：**Core 纯逻辑 / 平台外壳 / 共享 HTML**。铁律：**平台「方言」一律下沉到 `Elta.Windows`；Core 只放机制**（详见 NOTES「关键决策」）。

## 构建 / 测试 / 运行（**原生 Windows；不要用 WSL**——WSL 是 Linux，编不了 WPF）

```bat
:: 跑 Core 测试（或双击 windows\test-core.bat）
dotnet test windows\tests\Elta.Core.Tests\Elta.Core.Tests.csproj

:: 编译并运行外壳（或双击 windows\运行ELTA.bat）
dotnet run --project windows\src\Elta.Windows\Elta.Windows.csproj -c Release

:: 仅编译外壳（CI 同款）
dotnet build windows\src\Elta.Windows\Elta.Windows.csproj -c Release
```

- 需 **.NET 8 SDK**（不是仅 Runtime）。
- CI：`.github/workflows/windows-ci.yml` 在 ubuntu + windows-latest 跑 Core 测试，并在 **windows-latest 编译 Elta.Windows**。推送即验证（**编译级**）。

## 纪律

- **TDD**：Core 的纯逻辑先写测试（xUnit，`tests/Elta.Core.Tests/`）再实现。
- **验证三色**：结论按 🟢实测 / 🟡机制或编译级 / 🔴未验证 标注；**运行期行为必须真机手测**，不得因「编译通过」就宣称可用。
- **动手前**：先读 `windows/NOTES.md`，并遵守仓库根 `AGENTS.md` 的纪律（改代码前先理解调用链与共享状态）。
- **平台差异集中**：命名/默认值/存储实现等平台相关项放在 `Elta.Windows` 与 `SettingsDefaults`，不要在 Core 写死某平台常量。
- **密钥安全**：不打印、不提交任何 key；用 opencode `/connect` 或环境变量。
- **热键**：组合键用 `RegisterHotKey`，裸键（ESC/`` ` ``）用 `WH_KEYBOARD_LL`。
- **取词**：主路径是 **Ctrl+C**（UIA 常读不到：Chrome/WPS）。
- **Git**：本机（Windows）**只做 `clone`/`pull`（public 免认证），不 push**；本机改动经 **U 盘 / Syncthing 回传**，或由 Mac 侧代为提交。**不要**在本机配置 GitHub 凭证。
  交接统一走 `windows/make-handoff.ps1`（自动识别可移动盘，禁止手选盘符）；设备/路径核验闸机见全局规则 `verification-discipline.md`「设备/路径指代核验」。

## 验证默认自动化（2026-10-04 验收事故后落地）

验收/交互验证先做能力对照，默认自动化；仅不可自动化项请用户并注明原因。

本项目已验证的自动化手段（优先使用，均有当日实测）：

| 手段 | 工具 | 实测备注 |
|---|---|---|
| 热键注入 | `keybd_event`（Ctrl+T / Ctrl+Shift+T） | 可触发 RegisterHotKey 全局热键（SendKeys 不可靠，勿用） |
| 鼠标注入 | `SetCursorPos` + `mouse_event`（左/中键、拖拽） | 三项交互（中键/单击/窄选区）全自动通过 |
| UI 自动化 | UIA（AutomationElement / InvokePattern） | 设置窗口按钮 Invoke（测试连接 → probe http=200） |
| 截图取证 | `CopyFromScreen` 或 `BitBlt + CAPTUREBLT` | 两者均可抓选择器覆盖层（对照实测 delta 一致）；CAPTUREBLT 已用于验收取证 |
| 日志断言 | `%LOCALAPPDATA%\ELTA\logs\*.log` | 行为断言首选（screenshot captured / translate kind / result window reuse…） |
| 现成门禁 | `test-c2` / `test-c3` / `test-selection-apps` / `test-selector-interactions` / `test-clipboard` / `pack-release`（含冒烟） | 直接复用 |

**验收清单约定**：每项标注【自动可验 / 需人工（+原因）】；"需人工"必须给出不可自动化的理由。

## 已完成 / 待办（摘要，详情见 NOTES）

- ✅ Core：A1–A6（文本/分句/表格/HTML/设置），**375 测试**。
- ✅ C0：托盘外壳入口点 + CI 构建作业。
- ✅ B1：截图选区（A 机手测通过）。
- ✅ B2：取词（A 机手测通过；Chrome/Edge/WPS 走 Ctrl+C 兜底；2026-10-04 补测 WPS 文字/PDF ✅，Word 因本机 Office 试用期届满 SKIP）。
- ✅ 剪贴板加固（2026-10-04）：恢复仅写回安全格式（修复 WPS 富格式触发 OleFlushClipboard 原生 AV）；selftest 6/6；抽检脚本 `windows/test-selection-apps.ps1`。
- ✅ B3：OCR（WinRT；自动 + 真机手测通过）。
- ✅ P0/P1：剪贴板安全 / 日志兜底 / 取词线程化 / 热键自愈（机测通过）。
- ✅ B4：配置存储（JSON）/ 密钥库（DPAPI）/ Windows 默认值 / 热键服务（机测通过；裸键钩子待 C 接线）。
- ✅ 子计划 C 全部完成：C1 翻译链路 + C2 结果窗交互（加载/裸键/窗口记忆，含任务代数守卫与跨屏 DPI 加固）+ C3 设置三页，真机 E2E / 机测通过。
  回归门禁：`windows/test-c2.ps1`（22 用例，需 Key）/ `test-c3.ps1`（14 用例，离线）/ `test-selector-interactions.ps1`（选择器三交互 3 用例，离线，2026-10-04 起）。
- ✅ C4：完成通知 / 更新检查 / 遥测（真机验证；Core 375 测试）。版本纪律：Info.plist 与 Elta.Windows.csproj 同步 bump。
- ✅ 3A/3B/3B-2（2026-10-04）：应用图标（elta.ico，exe+托盘）；发布打包 `pack-release-windows.ps1`（版本闸机 Core TDD + single/folder 实测，**single 胜出** 69.4MB）；WebView2 缺失友好提示（Core TDD）。
- ⏭ 跨端待办：已归一（main=`6080e55` 基线，全量回归绿）；本机新增 {选择器三交互测试, ReleaseGate 导出包容错} 待下一次交接；下轮交接的 HANDOFF.txt 追加「清单标注：自动可验/需人工（+原因）」。
