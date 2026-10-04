# Windows 发布流水线 · 计划（已落地）

> 状态：**已落地**——形态 A 已实施（PR #6/#7），v1.0.0 已发布（2026-10-04）；本文件转为"计划 + 发版检查单"（living doc）。
> 已有资产：`windows/pack-release-windows.ps1`（自包含 single/folder；single ≈69.3–69.4MB）；
> 版本闸机 `ReleaseGate`（**每平台自有版本线**：Windows `csproj <Version>` == 发布 tag 版本；**不再比 mac `Info.plist`**）。
> 版本号：mac 冻结在 5.5.5；**Windows 独立版本线，自 1.0.0 起**。

## 一、发布形态（已决策：A）

| 选项 | 内容 | 结果 |
|---|---|---|
| **A** | 独立 workflow `windows-release.yml` + 独立标签 `win-vX.Y.Z` + 独立 GitHub Release | ✅ **已采纳**（PR #6/#7；v1.0.0 首发验证） |
| B | 复用 `v*` 标签、同一 release 追加 Windows 产物 | 未采纳（撞名/耦合发布节奏） |

## 二、Windows 仓库侧（本仓库）

- ✅ 打包脚本 `windows/pack-release-windows.ps1`：版本闸机（`-ExpectedVersion`，来自 tag）→ 双形态 publish → zip + sha256 → 冒烟（selftest + 真机翻译）
- ✅ 版本纪律：Windows 版本单一源 = `Elta.Windows.csproj <Version>`（当前 **1.0.1**）；tag `win-vX.Y.Z` 必须 == 该版本（`ReleaseGate` 校验）
- ✅ `.github/workflows/windows-release.yml`：push tag `win-v*` → 版本断言 → `pack-release-windows.ps1 -SkipSmoke` → 上传 zip + sha256 到独立 Release
  - CI 只跑编译级 + `--selftest` 可选项；**翻译冒烟需 API Key/桌面交互 → 真机门禁在本地执行**（见「六、发版检查单」）

## 三、Mac / 服务器侧（已落地 PR #6–#10）

1. ✅ Release 归属：形态 A（`win-v*` 独立 release）
2. ✅ 官网下载入口：双平台下载已上架；版本化直链 `https://autoelta.com/download/ELTA-Windows-vX.Y.Z-win-x64-single.zip`（+ `latest-win.zip`）
3. ✅ 服务器双通道同步（`/root/sync-elta-release.sh`：mac `.dmg` 直连；Windows zip 走代理 + `.sha256` 直连校验 → `latest-win.zip`）
4. ⏳ （可选，未做）更新检查目标是否指向具体下载页

## 四、决策记录

- [x] 形态 A（2026-10-04）
- [x] 官网下载入口与直链格式
- [x] 服务器同步脚本扩展（拉 zip + latest 链接）
- [ ] （可选）更新检查目标 URL —— 保持现状（指向官网首页）

## 五、风险与备注

- CI 可行性：windows-latest 自包含 publish 已验证（v1.0.0 首发产物通过真机冒烟）
- **代码签名**：无证书 → 首次运行 SmartScreen 提示（现状可接受；正式化再议）
- 本地源 zip 与 CI 产物 SHA 不同属正常（构建非确定性）；两者各自通过验证即视为绿
- `Resources/Info.plist` 导出双保险：属"验收导出包"流程，与本流水线无关，另议

## 六、发版检查单（Windows 侧；自 v1.0.1 起强制）

> 复盘（v1.0.0）：CI 构建 ✅、对已发布物冒烟 ✅；缺"tag 前本机全量冒烟"一步（当时新版闸机尚未在本机跑过）。

1. [ ] bump `Elta.Windows.csproj <Version>` 并提交（Windows 版本单一源）
       ⚠ 约定：**修复批次提交时一并 bump**（避免发布方 Mac 越界改 Windows 版本源；v1.0.2 即因未带 bump 由 Mac 补）
2. [ ] **tag 前**本机全量冒烟：`windows/pack-release-windows.ps1 -Flavor single -ExpectedVersion X.Y.Z`（含真机翻译）→ 通过才可打 tag
3. [ ] 打 tag `win-vX.Y.Z` 并推送（`windows-release.yml` 出独立 Release）
4. [ ] 发布后：对**已发布物**冒烟（直链下载 → SHA256 校验 → 解压 → selftest + 真实翻译）
5. [ ] 官网 bump：`bash scripts/bump-website-version.sh win X.Y.Z`（单命令，改 `website/index.html`、`website/install.html` 的版本号与直链）→ 提交。
       发版门禁自检：`bash scripts/bump-website-version.sh win X.Y.Z --check`（返回 0 才算官网已对齐）。
       ⏳ 后续可选：CI 在 tag 后自动跑该脚本并写回 main（全自动）。
6. [ ] 核验更新接口分流：`curl "https://autoelta.com/api/update?platform=windows"` → 应返回 Windows 线（含 `"platform":"windows"`）；
       再启动 Windows 端确认日志 `update check remote=... platform=windows` 且不再误报。
