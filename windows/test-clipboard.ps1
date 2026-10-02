# ELTA Windows — 剪贴板安全机侧测试（WI-1）
# 用法: powershell -ExecutionPolicy Bypass -File windows\test-clipboard.ps1
# 覆盖: --selftest（策略集成 5 项）+ 记事本端到端（真实 Ctrl+C 兜底 + 原剪贴板保留）
# 注意: 会短暂借用剪贴板；只操作本脚本启动的记事本进程。
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $root 'src\Elta.Windows\bin\Release\net8.0-windows10.0.19041.0\Elta.Windows.exe'
if (-not (Test-Path $exe)) {
    Write-Host '[FAIL] 未找到构建产物，请先运行 windows\build-windows.bat' -ForegroundColor Red
    exit 1
}

$failed = 0

# --- 1) --selftest（剪贴板策略集成）---
Start-Process -FilePath $exe -ArgumentList '--selftest' -Wait
$report = Join-Path $env:TEMP 'elta-selftest.txt'
if ((Test-Path $report) -and ((Get-Content -LiteralPath $report -Raw) -match 'selftest pass=5 fail=0')) {
    Write-Host '[PASS] selftest 5/5' -ForegroundColor Green
} else {
    Write-Host '[FAIL] selftest' -ForegroundColor Red
    if (Test-Path $report) { Get-Content -LiteralPath $report }
    $failed++
}

# --- 2) 端到端：记事本全选 → --selection-cli（真实 Ctrl+C 兜底）---
$sample = 'The quick brown fox jumps over the lazy dog.'
$input = Join-Path $env:TEMP 'elta-sel-input.txt'
Set-Content -LiteralPath $input -Value $sample -Encoding UTF8
$np = Start-Process notepad.exe -ArgumentList "`"$input`"" -PassThru
Start-Sleep -Seconds 2

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class EltaTestFg { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd); }
"@
$np.Refresh()
[EltaTestFg]::SetForegroundWindow($np.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 800
[System.Windows.Forms.SendKeys]::SendWait('^a')
Start-Sleep -Milliseconds 800
Set-Clipboard -Value 'ORIGINAL-CLIP'

$out = Join-Path $env:TEMP 'elta-sel-out.txt'
if (Test-Path $out) { Remove-Item $out -Force }
Start-Process -FilePath $exe -ArgumentList '--selection-cli', "`"$out`"" -Wait
Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue

$sel = if (Test-Path $out) { Get-Content -LiteralPath $out -Raw } else { '' }
$clip = (Get-Clipboard -Raw)
if ($sel -like "*$sample*") {
    Write-Host '[PASS] Ctrl+C 兜底取词' -ForegroundColor Green
} else {
    Write-Host "[FAIL] Ctrl+C 兜底取词 → $sel" -ForegroundColor Red
    $failed++
}
if ($clip.Trim() -eq 'ORIGINAL-CLIP') {
    Write-Host '[PASS] 原剪贴板保留' -ForegroundColor Green
} else {
    Write-Host "[FAIL] 原剪贴板被改 → $clip" -ForegroundColor Red
    $failed++
}

if ($failed -eq 0) {
    Write-Host 'ALL PASS' -ForegroundColor Green
    exit 0
}
Write-Host "$failed FAILED" -ForegroundColor Red
exit 1
