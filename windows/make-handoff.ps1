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

  if ($DryRun) {
    & $copyScript -Source $inc, $full, $list -WhatIfOnly
    exit $LASTEXITCODE
  }
  & $copyScript -Source $inc, $full, $list
  $code = $LASTEXITCODE
  if ($code -ne 0) { "写入 U 盘失败（exit $code），临时文件保留在: $tmp"; exit $code }
  "交接完成：3 个文件已写入 U 盘根目录（incremental / full / elta-commits-{0}.txt）" -f $Date
  exit 0
} finally {
  if (-not $DryRun -and (Test-Path $tmp)) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
