param(
  [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),
  [switch]$DryRun
)
# 一键交接：生成增量 + 全量 bundle（临时目录）→ 经 copy-to-removable.ps1 写入真 U 盘 → 输出清单。
# 禁止手选盘符：目标盘由全局闸机脚本自动识别（0 或 >1 个可移动盘都会拒绝）。
# 用法：powershell -ExecutionPolicy Bypass -File windows\make-handoff.ps1 [-DryRun]
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
$copyScript = Join-Path $HOME '.config\opencode\scripts\copy-to-removable.ps1'
if (-not (Test-Path $copyScript)) {
  "找不到全局闸机脚本 copy-to-removable.ps1：$copyScript"
  exit 2
}

# 交接前先对齐基准（Mac 回执 2026-10-04 第 5 条）：fetch 失败则警告并继续（基准可能过时）
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
git fetch origin | Out-Null
$fetchOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $prevEap
if (-not $fetchOk) { "警告：git fetch 失败（网络？），增量基准 origin/main 可能过时；确认网络后重跑。" }

$count = [int](git rev-list --count 'origin/main..main')
if ($count -eq 0) { "没有未推送 commit，无需交接。"; exit 0 }
"未推送 commit 数: $count"

$tmp = Join-Path $env:TEMP ('elta-handoff-' + (Get-Date -Format 'HHmmss'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  $inc = Join-Path $tmp ('elta-main-incremental-{0}.bundle' -f $Date)
  $full = Join-Path $tmp ('elta-full-{0}.bundle' -f $Date)
  $list = Join-Path $tmp ('elta-commits-{0}.txt' -f $Date)

  git bundle create $inc 'origin/main..main' | Out-Null
  git bundle create $full '--all' | Out-Null
  cmd /c ('git log origin/main..main --oneline > "' + $list + '"')

  # 给 Mac 端 opencode 的机器可读任务文件（Mac 端由 opencode 代用户操作）
  $task = Join-Path $tmp 'TASK.md'
  $head = (git rev-parse --short HEAD).Trim()
  $baseHead = (git rev-parse --short origin/main).Trim()
  # 清单从已写好的 UTF-8 文件读取（避免 PowerShell 捕获 git stdout 时按本地码页解码导致中文乱码）
  $commitList = [IO.File]::ReadAllText($list, (New-Object Text.UTF8Encoding($false))).TrimEnd()
  $ts = (Get-Date -Format 'yyyy-MM-dd HH:mm')
  $taskText = @"
# 任务（给 Mac 端 opencode）：合并 Windows 增量包并推送到 origin

用户已授权本次 push。请代用户执行并逐步核验；遇到冲突/非快进/任何不确定，停下并向用户报告，禁止强推。

生成时间：$ts（单槽任务文件：每次交接覆盖本文件；如需留档，覆盖前移入 归档\ 并加日期）

## 背景
- **本协作两端均由 opencode 代用户操作**：Windows 端 opencode 生成此包；你（Mac 端 opencode）负责合入并推送。
- 本包 = origin/main（$baseHead）之上的 $count 个 commit。
- bundle：本目录 elta-main-incremental-$Date.bundle（生成时经 SHA256 校验写入）。
- 人类可读版：同目录 HANDOFF.txt；仓库正式交接记录：windows/NOTES.md。

## 操作
1. 进入 Mac 上的 elta 仓库（没有则先 git clone https://github.com/liuxiaominglove/elta.git）
2. git fetch origin && git checkout main && git pull origin main      # 有脏状态/未推送提交先停下问用户
3. git pull "/Volumes/<U盘名>/elta-main-incremental-$Date.bundle" main   # 盘名用 ls /Volumes 探测
4. push 前核验：git log --oneline -5 头部应为 $head ; git rev-list --count origin/main..main 应为 $count
5. git push origin main        # 禁止 force
6. 推后核验：git rev-list --count origin/main..main 应为 0
7. 可选：sh windows/test-core.sh  （期望全部通过；当前基线 Core=406，需 .NET 8 SDK）
8. 回执：写 REPLY.md 放回 U 盘根目录（单槽：覆盖即最新；如需留档，覆盖前把旧版移入 归档\ 并加日期）。
   Windows 端 opencode 会读取；U 盘上的验收/证据（验收*-证据\）等历史文件亦可参考。

## 长期记忆同步（请代为持久化一次）
- 本协作的长期约定：合并后见 repo root `AGENTS.md`「跨端协作」节 + `windows/NOTES.md`「交接约定」。
- 请把以下要点写入你本机的持久记忆（全局规则 / 记忆库，按环境支持方式）：
  1) 两端均为 opencode 代用户操作；U 盘为文件总线（人工中转）。
  2) 文件总线单槽语义：Windows→Mac 用 TASK.md、Mac→Windows 用 REPLY.md；覆盖即最新，留档移入 归档\。
  3) 增量基准 = origin/main；合并前先 fetch/pull；Mac 端禁 force push。
  4) 回执（REPLY.md）写好后放回 U 盘根目录。

## 本次 commit 清单（$count 个）
$commitList

## 汇报格式（给用户）
- push 结果：成功/受阻（附第 4/6 步实际输出）
- 是否跑过 Core 测试及结果
- 任何异常原文
"@
  [IO.File]::WriteAllText($task, $taskText, (New-Object Text.UTF8Encoding($false)))

  if ($DryRun) {
    & $copyScript -Source $inc, $full, $list, $task -WhatIfOnly
    exit $LASTEXITCODE
  }
  & $copyScript -Source $inc, $full, $list, $task
  $code = $LASTEXITCODE
  if ($code -ne 0) { "写入 U 盘失败（exit $code），临时文件保留在: $tmp"; exit $code }
  "交接完成：4 个文件已写入 U 盘根目录（incremental / full / elta-commits-{0}.txt / TASK.md）" -f $Date
  exit 0
} finally {
  if (-not $DryRun -and (Test-Path $tmp)) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
