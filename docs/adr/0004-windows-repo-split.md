# 4. Windows 版拆分独立仓库（subtree split → elta-windows）

- 状态：提议
- 日期：2026-10-04

## 上下文

Windows 移植（子计划 B/C）已完成、v1.0.0 已发布，`windows/` 与 mac `Sources/` 现同处一仓、共用 `main`。
本仓已记录的启用门槛：`windows/NOTES.md`「B/C 完成后用 `git subtree split -P windows` 拆成独立仓库
`elta-windows`（保留历史）」；`REPORT.md` ④「同意择机」。相关现状事实：

- **版本线与发布通道已解耦**：Windows 版本单一源 = `Elta.Windows.csproj <Version>`（自 1.0.0）；tag `win-vX.Y.Z`
  → `.github/workflows/windows-release.yml` 建**独立** GitHub Release。仅**代码仓**未解耦。
- CI 路径耦合：`windows-ci.yml` / `windows-release.yml` 多处引用 `windows/...`（路径过滤 + 命令行）。
- 服务器 `/root/sync-elta-release.sh` 经 GitHub API 拉**本仓** release 产物（mac `.dmg` + Windows zip）。
- 跨端协作：Windows 端只 clone/pull **本仓**（`liuxiaominglove/elta`）。

## 决策

### 本质

不可逆偏有损的**仓库结构性变更**——是否把 `windows/` 拆为独立仓。它切断并改写多处引用（CI 路径、
服务器拉取仓库名、跨端协作 clone 目标、文档指引），而非"改一处"。核心矛盾：**独立节奏的收益**
vs **多养一个仓库、并同步四处引用的成本**。关键判据：该子树是否具**独立生命周期**且同处一仓是否已成**实际摩擦**。

### 最佳实践

- 拆分成立的条件：子树具**独立生命周期**（独立版本线 / 发布节奏 / 权限 / 贡献者）且 monorepo 耦合确为摩擦。
  此处版本与发布**已独立**，"独立节奏"诉求已满足；耦合造成的摩擦**尚未被证实**。
- 拆分手段：`git subtree split -P`（保历史）或 `git filter-repo --path`；拆后**必须同步改写**所有路径引用
  （CI、脚本、部署、文档），迁移面常被低估。
- 业界共识：多数场景 monorepo 多包更省事；**仅当耦合确为摩擦才拆**，且应"先条件化、再执行"。
- 真实诉求应直接满足：权限 → 单仓 `CODEOWNERS`；发布节奏 → 独立 tag/Release（已具备）；仅"独立对外"
  才真正需要拆仓。

### 方案

- **A（推荐·条件化暂缓）**：维持 monorepo，暂不拆。本轮已把官网版本号 bump 单命令化、Windows CI/Release
  已独立，摩擦已很低。设**触发条件**，任一出现再启动 B：
  1. Windows 需**独立 GitHub 权限 / 协作者**（`CODEOWNERS` 不足以满足时）；
  2. 两线 CI / 发布**互相干扰频发**；
  3. `windows/` 提交量使 `main` 历史**难以维护**。
- **B（执行拆分）**：`git subtree split -P windows -b elta-windows-main` → 建仓 `liuxiaominglove/elta-windows`
  → push；**同步迁移**：workflows 去 `windows/` 前缀、`windows/*` 脚本相对路径、服务器 `sync-elta-release.sh`
  仓库名、跨端协作协议（Windows clone 目标改新仓）、`windows/AGENTS.md` + `NOTES.md` 指引；主仓 `windows/`
  **移除**（不留镜像，避免双写）。迁移清单须**逐项验证**：CI 绿 / 能出独立 Release / 服务器直链可达 /
  跨端交接走通；并备回滚预案。

## 后果

- A：零迁移风险；现状已足够独立（版本 + 发布均独立）；代价 = `main` 继续承载两平台（可接受）。
- B：Windows 彻底独立（仓库 / 权限 / issue / Release 归其自管）；代价 = 迁移面广、有损、需服务器与协作协议
  同步改、回滚复杂。

## 被拒备选

- **立即拆分而不做条件评估**：摩擦未证实、连锁改写未备 → 高风险先行（YAGNI）。
- **保留 `windows/` 镜像双写**：引入同步一致性负担，反模式；一个文件只能有一个家。
