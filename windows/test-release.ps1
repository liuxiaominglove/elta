param(
    [Parameter(Mandatory = $true)][string]$Version,
    [switch]$SkipTranslate
)
# ELTA Windows 发布物真机回归门禁（自 v1.0.1 起，每次发布后跑一次）
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File windows\test-release.ps1 -Version 1.0.1
# 覆盖（发布物全链路）：
#   1) 从 autoelta.com 下载版本化 zip + .sha256 → SHA 校验
#   2) 资源管理器同款机制解压（Shell CopyHere）→ 断言 ELTA.exe（bug#2 回归点：bsdtar 产物失败）
#   3) 解压 exe 跑 --selftest → 期望 6/6
#   4) 启动 → 断言日志 update check remote=<Version> platform=windows 且不弹更新（bug#1 回归点）
#   5) （默认）记事本真实翻译一次 → Success（-SkipTranslate 可跳）
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class RelFg {
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, UIntPtr e);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint fl);
    public static void CtrlShiftT() {
        keybd_event(0x11,0,0,UIntPtr.Zero); keybd_event(0x10,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(50);
        keybd_event(0x54,0,0,UIntPtr.Zero); keybd_event(0x54,0,2,UIntPtr.Zero); System.Threading.Thread.Sleep(50);
        keybd_event(0x10,0,2,UIntPtr.Zero); keybd_event(0x11,0,2,UIntPtr.Zero);
    }
}
"@

$base = 'https://autoelta.com/download'
$zipName = "ELTA-Windows-v$Version-win-x64-single.zip"
$tmp = Join-Path $env:TEMP ("opencode\release-regress-" + $Version)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Remove-Item (Join-Path $tmp 'extracted') -Recurse -Force -ErrorAction SilentlyContinue
$zip = Join-Path $tmp $zipName
$sha = $zip + '.sha256'
$pass = 0; $fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "PASS $name" } else { $script:fail++; Write-Host "FAIL $name | $detail" }
}

# ---- 1) 下载（断点续传 + 缓存跳过）+ SHA 校验 ----
curl.exe -L -sS --retry 3 -o $sha "$base/$zipName.sha256"
$expected = ((Get-Content $sha -Raw).Trim() -split '\s+')[0].ToLower()
$actual = if (Test-Path $zip) { (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower() } else { '' }
if ($actual -ne $expected) {
    Write-Host "downloading $zipName ... (resume supported)"
    if (Test-Path $zip) {
        curl.exe -L -sS -C - --retry 3 --retry-delay 2 --max-time 900 -o $zip "$base/$zipName"
    } else {
        curl.exe -L -sS --retry 3 --retry-delay 2 --max-time 900 -o $zip "$base/$zipName"
    }
    $actual = if (Test-Path $zip) { (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower() } else { '' }
}
Check 'sha256 match' ($expected -eq $actual) "expected=$expected actual=$actual"
if ($expected -ne $actual) { Write-Host '[abort] download incomplete'; exit 1 }

# ---- 2) 资源管理器同款机制解压（bug#2 回归点） ----
$dest = Join-Path $tmp 'extracted'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$shell = New-Object -ComObject Shell.Application
$shell.NameSpace($dest).CopyHere($shell.NameSpace($zip).Items(), 16)
$dl = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $dl -and -not (Test-Path (Join-Path $dest 'ELTA.exe'))) { Start-Sleep -Milliseconds 800 }
$exe = Join-Path $dest 'ELTA.exe'
Check 'explorer-mechanism extract' (Test-Path $exe) 'CopyHere failed (bug#2 regression!)'
if (-not (Test-Path $exe)) { Write-Host '[abort] cannot continue without extracted exe'; exit 1 }

# ---- 3) selftest ----
Get-Process Elta.Windows, ELTA -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800
$rep = Join-Path $env:TEMP 'elta-selftest.txt'
Remove-Item $rep -ErrorAction SilentlyContinue
Start-Process -FilePath $exe -ArgumentList '--selftest' -Wait
Start-Sleep -Milliseconds 500
$st = if (Test-Path $rep) { (Get-Content $rep -Raw).Split([char]10)[0].Trim() } else { 'MISSING' }
Check 'selftest 6/6' ($st -match 'pass=6 fail=0') $st

# ---- 4) 启动 + 更新检查（bug#1 回归点） ----
$log = Get-ChildItem "$env:LOCALAPPDATA\ELTA\logs\*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
$off = (Get-Content $log).Count
Start-Process -FilePath $exe
Start-Sleep -Seconds 3
$dl = (Get-Date).AddSeconds(15)
$upd = $null
while ((Get-Date) -lt $dl -and -not $upd) {
    Start-Sleep -Milliseconds 400
    $upd = (Get-Content $log | Select-Object -Skip $off | Where-Object { $_ -match 'update check remote=' } | Select-Object -Last 1)
}
Check "update check remote=$Version platform=windows" ($upd -match ("remote=" + [regex]::Escape($Version) + " platform=windows")) "$upd"
Start-Sleep -Seconds 2
$found = @(Get-Content $log | Select-Object -Skip $off | Where-Object { $_ -match 'update found' }).Count
$ignored = (Get-Content $log | Select-Object -Skip $off | Where-Object { $_ -match 'update ignored remote=' } | Select-Object -Last 1)
Check 'no false update prompt' ($found -eq 0) "update found x$found"
Write-Host "  ($ignored)"

# ---- 5) 真实翻译 ----
if (-not $SkipTranslate) {
    $doc = Join-Path $tmp 'release-smoke.txt'
    Set-Content -LiteralPath $doc -Value 'ELTA release regression translation. The quick brown fox jumps over the lazy dog.' -Encoding UTF8
    Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force
    $np = Start-Process notepad.exe "`"$doc`"" -PassThru
    Start-Sleep -Seconds 2
    $np.Refresh()
    [RelFg]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 300, 200, 700, 500, 0x0040) | Out-Null
    Start-Sleep -Milliseconds 400
    [RelFg]::SetForegroundWindow($np.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 500
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    Start-Sleep -Milliseconds 400
    $off2 = (Get-Content $log).Count
    [RelFg]::CtrlShiftT()
    $dl = (Get-Date).AddSeconds(25)
    $tr = $null
    while ((Get-Date) -lt $dl -and -not $tr) {
        Start-Sleep -Milliseconds 400
        $tr = (Get-Content $log | Select-Object -Skip $off2 | Where-Object { $_ -match 'translate kind=' } | Select-Object -Last 1)
    }
    Check 'translation e2e' ($tr -match 'translate kind=Success') "$tr"
    Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue
}

Get-Process Elta.Windows, ELTA -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host "---- test-release v$Version : pass=$pass fail=$fail ----"
if ($fail -gt 0) { exit 1 } else { exit 0 }
