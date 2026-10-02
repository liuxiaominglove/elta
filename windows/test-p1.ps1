# ELTA Windows — P1 机侧测试（WI-3 取词线程化/UIA 看门狗；WI-4 热键自愈）
# 用法: powershell -ExecutionPolicy Bypass -File windows\test-p1.ps1
# 注意: 会短暂占用/释放 Ctrl+T、短暂借用剪贴板；只操作本脚本启动的进程。
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $root 'src\Elta.Windows\bin\Release\net8.0-windows10.0.19041.0\Elta.Windows.exe'
if (-not (Test-Path $exe)) {
    Write-Host '[FAIL] 构建产物不存在，请先运行 windows\build-windows.bat' -ForegroundColor Red
    exit 1
}

$script:failed = 0
function Assert([bool]$ok, [string]$name, [string]$detail) {
    if ($ok) {
        Write-Host "[PASS] $name" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $name :: $detail" -ForegroundColor Red
        $script:failed++
    }
}

# ---------- A) --selection-selftest：STA 工作线程 + UIA 看门狗路径 ----------
$sample = 'The quick brown fox jumps over the lazy dog.'
$input = Join-Path $env:TEMP 'elta-p1-input.txt'
Set-Content -LiteralPath $input -Value $sample -Encoding UTF8
$np = Start-Process notepad.exe -ArgumentList "`"$input`"" -PassThru
Start-Sleep -Seconds 2
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class EltaP1Fg { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd); }
"@
$np.Refresh()
[EltaP1Fg]::SetForegroundWindow($np.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 800
[System.Windows.Forms.SendKeys]::SendWait('^a')
Start-Sleep -Milliseconds 800

$out = Join-Path $env:TEMP 'elta-p1-sel.txt'
if (Test-Path $out) { Remove-Item $out -Force }
Start-Process -FilePath $exe -ArgumentList '--selection-selftest', "`"$out`"" -Wait
Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue
$sel = if (Test-Path $out) { Get-Content -LiteralPath $out -Raw } else { '' }
Assert ($sel -like "*$sample*") 'selection-selftest 取到文本（STA + UIA 路径）' $sel

# ---------- B) 热键自愈：占用 Ctrl+T → 启动 → 释放 → 自动恢复 ----------
Get-Process -Name 'Elta.Windows' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

$job = Start-Job -ScriptBlock {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class EltaOccupy {
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
"@
    $ok = [EltaOccupy]::RegisterHotKey([IntPtr]::Zero, 8888, 0x0002, 0x54)
    Write-Output "occupy=$ok"
    Start-Sleep -Seconds 30
    [EltaOccupy]::UnregisterHotKey([IntPtr]::Zero, 8888) | Out-Null
}
Start-Sleep -Seconds 2
$occupy = (Receive-Job $job -Keep) -join ';'
Assert ($occupy -match 'occupy=True') '前置：后台占用 Ctrl+T' $occupy

$logDir = Join-Path $env:LOCALAPPDATA 'ELTA\logs'
$log = Join-Path $logDir ("elta-" + (Get-Date -Format yyyyMMdd) + ".log")
$base = if (Test-Path $log) { @(Get-Content -LiteralPath $log).Count } else { 0 }

$a = Start-Process -FilePath $exe -PassThru
Start-Sleep -Seconds 4
$a.Refresh()
Assert (-not $a.HasExited) '托盘实例存活' '进程已退出'

$lines = @(Get-Content -LiteralPath $log)
$new = if ($lines.Count -gt $base) { $lines[$base..($lines.Count - 1)] } else { @() }
$joined = $new -join "`n"
Assert ($joined -match 'hotkey busy name=shot') '启动时检测到 Ctrl+T 被占用' $joined
Assert ($joined -match 'pending:shot') '启动日志 pending:shot' $joined

Stop-Job $job
Remove-Job $job -Force
Write-Host '已释放 Ctrl+T 占用，等待自愈（<=15s）...'
Start-Sleep -Seconds 14

$lines2 = @(Get-Content -LiteralPath $log)
$new2 = if ($lines2.Count -gt $base) { $lines2[$base..($lines2.Count - 1)] } else { @() }
$joined2 = $new2 -join "`n"
Assert ($joined2 -match 'hotkey registered name=shot') '热键自愈：shot 已注册' $joined2
Assert ($joined2 -match 'hotkey recovered') '自愈日志（hotkey recovered）' $joined2

Stop-Process -Id $a.Id -Force -ErrorAction SilentlyContinue

if ($script:failed -eq 0) {
    Write-Host 'ALL PASS' -ForegroundColor Green
    exit 0
}
Write-Host "$script:failed FAILED" -ForegroundColor Red
exit 1
