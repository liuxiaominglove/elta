# Windows 下一轮任务（Mac → Windows 草案）

> **性质**：Mac 端 opencode 起草的下一轮待办草案，供 Windows 端 opencode 采纳并入其
> `TASK.md`（文件总线 `TASK.md` 仍由 Windows 侧生成，本文件**不是**总线单槽文件）。
> **来源**：v1.0.1 发布 + `VERIFY-BACKLOG` 收口后的遗留。
> **回传**：完成后把结果写入 U 盘 `REPORT.md`，并更新 `windows/NOTES.md` / 本文件状态。

## 状态总览

| ID | 事项 | 类型 | 前置 | 状态 |
|----|------|------|------|------|
| T1 | v1.0.1 真机回归（两个修复的回归点） | 验证 | 需已发布 v1.0.1 | ✅ 通过（test-release 6/6） |
| T2 | F1：划词空选弹模态框并持有 busy | 修复(bug) | 无 | ✅ 已修复（家族 3 处；test-selection-empty 4/4） |
| T3 | V1：设置窗深色（实现 vs 改期望） | 决策 | 需拍板 | ✅ 决策(b)：深色=结果窗专属 |
| T4 | V2/V4：WebView2 缺失弹窗 / Word 取词 | 验证(阻塞) | 特殊环境 | ⏭ 待条件 |

---

## T1 v1.0.1 真机回归（🎯 优先，验证已发布物）
- **背景**：v1.0.1 修了两个发布后 bug（更新平台分流 + zip 提取兼容），Mac 侧已发布并做代理核验；
  真机回归点需 Windows 侧确认。
- **步骤 / 期望**：
  1. 从 `https://autoelta.com/download/ELTA-Windows-v1.0.1-win-x64-single.zip` 下载 → 解压 →
     **右键「提取」应正常**（旧 bsdtar 产物报"压缩文件夹无效"）。【bug#2 回归】
  2. 运行 v1.0.1，触发更新检查 → 日志应见 `update check remote=1.0.1 platform=windows`，**不再弹** mac 版本线。
     【bug#1 回归】
  3. （可选）`--selftest` 6/6 + 一次真实翻译。
- **类型**：【自动可验】——下载/解压可用脚本；更新日志读 `%LOCALAPPDATA%\ELTA\logs\`。

## T2 F1 修复：划词空选弹模态框并持有 busy（🐞 真 bug，有已知修法）
- **背景**（`NOTES.md` 收口节）：Chrome 焦点未中导致**划词空选（len=0）**时弹模态框并**持有 busy**，
  后续热键被 `selection ignored: busy` 静默忽略；关框即恢复（复现 19:04–19:05）。
- **修法（候选，对齐已修 OCR 空选）**：空选区**不弹模态框**——改**托盘气球提示 + 即时释放 busy**
  （与「空选区 OCR 提示由模态框改为托盘气球 + busy 即时释放」同款，见 `NOTES.md` C2 加固节）。
- **验收**：① 空选区后 **busy 立即释放**（日志无 `ignored: busy` 卡顿）；② **补"空选不阻塞"回归用例**
  （触发条件已写明：修复时必须补该用例）。
- **类型**：【自动可验】——断言日志 `selection ignored: busy` 不再出现 + busy 标志释放。

## T3 V1 决策：设置窗深色（🤔 需拍板，无唯一正解）
- **背景**：`VERIFY-BACKLOG` V1 结果——结果窗深色 ✅ / **设置窗未实现深色（代码零主题逻辑）**。
- **待决**（二选一，需产品取舍）：
  - (a) **补实现**：`SettingsWindow` 读 `AppsUseLightTheme` 做深色（工作量小→中，沿用结果窗做法）；
  - (b) **改期望**：明确设置窗**不做深色**，同步修文档期望（成本≈0）。
- **依据提示**：设置窗是低频、功能性界面；结果窗是高频、阅读性界面。若两者视觉一致性非强需求，(b) 亦可。
- **类型**：决策（走三段：本质 / 最佳实践 / 方案），定后若选 (a) 再排实现。

## T4 阻塞项（条件满足再做）
- **V2 WebView2 缺失弹窗**：本机已装 Runtime，无法复现 → 建议后续加**故障注入钩子**（或干净环境）再验。
- **V4 Word 取词**：本机 Office 未授权 → 待**授权 Office** 的机器补测。

---

## 交付约定
- 每项完成后更新「状态总览」列，并在 U 盘 `REPORT.md` 记录：环境、结果、异常原文。
- 若 T2 修复涉及代码：按仓库纪律先 TDD（补回归用例）→ 冒烟 → 回传；Mac 侧合并发版（预计 `win-v1.0.2`）。
- 正式进度以 `windows/NOTES.md` 为准；本文件为派生草案。

---

## 执行结果（Windows，2026-10-04 晚）

- **T1 ✅ 通过（6/6）**：直链下载（断点续传）→ SHA256 与发布 `.sha256` 一致（`5aee39dd…`）→
  **资源管理器机制解压（CopyHere）✅**（bug#2 回归点）→ 解压 exe `--selftest` 6/6 →
  日志 `update check remote=1.0.1 platform=windows` + `update ignored … (same or skipped)`、无 `update found`（bug#1 回归点）→ 真实翻译 ✅。
  门禁已固化：`windows/test-release.ps1 -Version X.Y.Z`（含断点续传/缓存跳过）。
- **T2 ✅ 已修复**（家族修复 3 处：划词空选/取词异常/OCR 失败 → 托盘气球 + busy 即时释放；`NoLanguagePack` 问句框保留）：
  TDD RED 3 fail → GREEN `test-selection-empty.ps1` **4/4**；回归 `test-c2` 22/22、`test-selector-interactions` 4/4；
  AGENTS 新增「busy 纪律：持有 busy 的路径禁止弹模态（需应答除外）」。
- **T3 ✅ 决策 (b)**：深色主题=**结果窗专属（阅读场景）设计**，设置窗不做；需求出现时按
  「全控件样式 + test-c3 回归 + 双主题截图验收」清单实施（NOTES/BACKLOG 已同步）。
- T4：维持 ⏭ 待条件（WebView2 故障注入 / Word 授权环境）。
- 备注：GitHub 直连当晚多次间歇失败（fetch 重试后成功）；本批已 rebase 到 `f36abc0` 之上。
