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

## 已完成 / 待办（摘要，详情见 NOTES）

- ✅ Core：A1–A6（文本/分句/表格/HTML/设置），**332 测试**。
- ✅ C0：托盘外壳入口点 + CI 构建作业。
- ✅ B1：截图选区（A 机手测通过）。
- ✅ B2：取词（A 机手测通过；Chrome/Edge/WPS 走 Ctrl+C 兜底）。
- ✅ B3：OCR（WinRT；自动 + 真机手测通过）。
- ✅ P0/P1：剪贴板安全 / 日志兜底 / 取词线程化 / 热键自愈（机测通过）。
- ✅ B4：配置存储（JSON）/ 密钥库（DPAPI）/ Windows 默认值 / 热键服务（机测通过；裸键钩子待 C 接线）。
- ⬜ 子计划 C：设置 / 结果窗口 / 翻译接线。
