# ELTA Windows — B4 机侧测试（配置存储 / DPAPI 密钥库 / 键盘钩子 / 设置接线）
# 用法: powershell -ExecutionPolicy Bypass -File windows\test-settings.ps1
# 注意: 使用临时目录做存储自检，不触碰真实设置与密钥；钩子测试注入的是 F13。
$ErrorActionPreference = 'Stop'

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

# ---------- 1) --settings-selftest ----------
$out1 = Join-Path $env:TEMP 'elta-settings-selftest.txt'
if (Test-Path $out1) { Remove-Item $out1 -Force }
Start-Process -FilePath $exe -ArgumentList '--settings-selftest', "`"$out1`"" -Wait
$r1 = if (Test-Path $out1) { Get-Content -LiteralPath $out1 -Raw } else { '' }
Assert ($r1 -match 'settings-selftest pass=\d+ fail=0') 'settings-selftest（存储/密钥/默认值）全过' $r1

# ---------- 2) --hook-selftest ----------
$out2 = Join-Path $env:TEMP 'elta-hook-selftest.txt'
if (Test-Path $out2) { Remove-Item $out2 -Force }
Start-Process -FilePath $exe -ArgumentList '--hook-selftest', "`"$out2`"" -Wait
$r2 = if (Test-Path $out2) { Get-Content -LiteralPath $out2 -Raw } else { '' }
Assert ($r2 -match 'hook-selftest pass=\d+ fail=0') 'hook-selftest（安装 + 注入触发）全过' $r2

# ---------- 3) 托盘启动 + 设置接线（日志含 settings provider=） ----------
Get-Process -Name 'Elta.Windows' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
$log = Join-Path (Join-Path $env:LOCALAPPDATA 'ELTA\logs') ("elta-" + (Get-Date -Format yyyyMMdd) + ".log")
$base = if (Test-Path $log) { @(Get-Content -LiteralPath $log).Count } else { 0 }

$a = Start-Process -FilePath $exe -PassThru
Start-Sleep -Seconds 4
$a.Refresh()
Assert (-not $a.HasExited) '托盘实例存活' '进程已退出'

$lines = @(Get-Content -LiteralPath $log)
$new = if ($lines.Count -gt $base) { $lines[$base..($lines.Count - 1)] } else { @() }
$joined = $new -join "`n"
Assert ($joined -match 'settings provider=') '启动日志含 settings 接线（provider/model/keySet/hotkey）' $joined
Assert ($joined -match 'hotkey=Ctrl\+T') '热键来自 Windows 默认值（Ctrl+T）' $joined
Assert ($joined -match 'hotkey registered name=shot') '快捷键已注册（无占用时）' $joined

Stop-Process -Id $a.Id -Force -ErrorAction SilentlyContinue

if ($script:failed -eq 0) {
    Write-Host 'ALL PASS' -ForegroundColor Green
    exit 0
}
Write-Host "$script:failed FAILED" -ForegroundColor Red
exit 1
