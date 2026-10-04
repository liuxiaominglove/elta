# Windows 发布流水线 · 设计稿（提案）

> 状态：**提案**——动代码（新增 CI workflow）前先与 Mac 侧对齐。日期：2026-10-04。
> 已有资产：`windows/pack-release-windows.ps1`（自包含 single/folder 双形态；single 实测 69.4MB / 首启 1.26s）；
> 版本闸机 `ReleaseGate`（**每平台自有版本线**：Windows `csproj <Version>` == 发布 tag 版本；**不再比 mac `Info.plist`**）；`--version-check` CLI。
> 版本号：mac 冻结在 5.5.5；**Windows 独立版本线，自 1.0.0 起**（2026-10-04 决策）。

## 一、发布形态选项（待 Mac 决策）

| 选项 | 内容 | 优点 | 缺点 |
|---|---|---|---|
| **A（推荐）** | 独立 workflow `windows-release.yml` + 独立标签 `win-vX.Y.Z` + 独立 GitHub Release | 与 macOS `vX.Y.Z` 不撞名；两端发布节奏解耦；说明各自撰写 | 同一产品版本 = 两个 release |
| B | 复用 `v*` 标签，同一 release 追加 Windows 产物 | 单一 release，见一处即全 | 标签/说明耦合（mac 侧推送即触发 win 构建）；产物命名需区分 |

推荐 A 依据：Mac 侧此前已建议 `win-vX.Y.Z` 独立命名（避免撞名）；两端构建机不同（macos-14 vs windows-latest），解耦降低互相等待。

## 二、Windows 仓库侧（本仓库）已就绪 / 待新增

已就绪：

- 打包脚本 `windows/pack-release-windows.ps1`：版本闸机 → 双形态 publish → zip + sha256（冒烟含 selftest + 真机翻译）
- 版本纪律：Windows 版本单一源 = `Elta.Windows.csproj <Version>`（当前 **1.0.0**）；发布时 tag `win-vX.Y.Z` 必须 == 该版本（`ReleaseGate` 校验）。**与 mac `Resources/Info.plist` 无关**（两条独立版本线）。

决议后新增（约 30 行）：

- `.github/workflows/windows-release.yml`
  - 触发：push tag `win-v*`
  - 步骤：checkout → setup-dotnet 8 → **断言 tag 版本 == csproj Version** → `pack-release-windows.ps1 -SkipSmoke`
    → 上传 zip + sha256 到对应 GitHub Release
  - 注意：CI 内可跑 `--selftest`（无 GUI），**翻译冒烟需 API Key + 桌面交互**，CI 跳过；
    "发布前真机门禁"保留在本机（`test-c2` + `pack-release-windows.ps1` 全量冒烟）

## 三、Mac / 服务器侧待决（不在本仓库改代码）

1. **Release 归属**：选项 A（`win-v*` 独立 release）还是 B（同一 release）——tag 均在当前 GitHub 仓库
2. **官网下载入口**：加 Windows 下载按钮；建议版本化直链（对齐 DMG 惯例）：
   `https://autoelta.com/download/ELTA-Windows-vX.Y.Z-win-x64-single.zip`
3. **服务器 cron**：现 `/root/sync-elta-release.sh` 只拉 `.dmg`；需扩展为同时拉 Windows zip 到
   `/var/www/elta-downloads/` 并维护 `latest` 软链
4. （可选）**更新检查**：Windows 版 `UpdateLogic` 现指向官网首页；是否指向具体下载页

## 四、待 Mac 决策清单

- [ ] 形态 A / B
- [ ] 官网下载入口与直链格式
- [ ] 服务器同步脚本扩展（拉 zip + latest 链接）
- [ ] （可选）更新检查目标 URL

## 五、风险与备注

- CI 可行性：windows-latest 上 `dotnet publish` 自包含可行（本机 Win10 已实证；runner 为 Server 2022 同内核代）
- **代码签名**：无证书 → 首次运行 SmartScreen 提示（现状可接受；正式化再议）
- `Resources/Info.plist` 导出双保险：属"验收导出包"流程，与本流水线无关，另议
