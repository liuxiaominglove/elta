param(
    [ValidateSet('both', 'single', 'folder')]
    [string]$Flavor = 'both',
    [switch]$SkipSmoke
)

# ELTA Windows release packaging (3B)
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File windows\pack-release-windows.ps1 [-Flavor both|single|folder] [-SkipSmoke]
# - Version gate: Elta.Windows.csproj <Version> must equal Resources/Info.plist (via --version-check CLI, Core-tested).
# - Flavors: single = self-contained single-file exe; folder = self-contained folder layout.
# - Smoke: --selftest (6 cases) + one real translation via hotkey, from the staged package.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class PackFg { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); }
"@

$root = Split-Path -Parent $MyInvocation.MyCommand.Path          # windows/
$repo = Split-Path -Parent $root                                 # repo root
$exe = Join-Path $root 'src\Elta.Windows\bin\Release\net8.0-windows10.0.19041.0\Elta.Windows.exe'
$csproj = Join-Path $root 'src\Elta.Windows\Elta.Windows.csproj'
$plist = Join-Path $repo 'Resources\Info.plist'
$dist = Join-Path $root 'dist'
$tmp = Join-Path $env:TEMP 'opencode'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# --- 1) version gate ---
Write-Host '== version gate ==' -ForegroundColor Cyan
dotnet build (Join-Path $root 'src\Elta.Windows\Elta.Windows.csproj') -c Release | Out-Null
$vcOut = Join-Path $tmp 'elta-version-check.txt'
Remove-Item $vcOut -ErrorAction SilentlyContinue
$p = Start-Process -FilePath $exe -ArgumentList '--version-check', "`"$csproj`"", "`"$plist`"", "`"$vcOut`"" -Wait -PassThru
$vc = if (Test-Path $vcOut) { Get-Content $vcOut -Raw } else { '' }
Write-Host "  $vc"
if ($p.ExitCode -ne 0 -or $vc -notmatch 'ok=true version=(\S+)') {
    Write-Host '[FAIL] version gate: csproj 与 Info.plist 版本不一致（或读取失败），已中止打包。' -ForegroundColor Red
    exit 1
}
$version = $matches[1]
Write-Host "  version = $version" -ForegroundColor Green

# --- 2) publish ---
New-Item -ItemType Directory -Force -Path $dist | Out-Null

function Publish-Flavor([string]$name) {
    $out = Join-Path $dist "publish-$name"
    Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
    if ($name -eq 'single') {
        dotnet publish (Join-Path $root 'src\Elta.Windows\Elta.Windows.csproj') -c Release -r win-x64 `
            --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
            -p:EnableCompressionInSingleFile=true -o $out | Out-Null
    } else {
        dotnet publish (Join-Path $root 'src\Elta.Windows\Elta.Windows.csproj') -c Release -r win-x64 `
            --self-contained true -o $out | Out-Null
    }
    return $out
}

function Build-Stage([string]$name, [string]$publishDir) {
    $stage = Join-Path $dist "stage-$name"
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    if ($name -eq 'single') {
        Copy-Item (Join-Path $publishDir 'Elta.Windows.exe') (Join-Path $stage 'ELTA.exe')
    } else {
        Copy-Item "$publishDir\*" $stage -Recurse
        Rename-Item (Join-Path $stage 'Elta.Windows.exe') 'ELTA.exe'
    }
    $readme = @"
ELTA Windows v$version (x64)
============================
1. 双击 ELTA.exe 启动（常驻托盘）。
2. 用法：
   - Ctrl+T        截图翻译（拖拽框选）
   - Ctrl+Shift+T  划词翻译（先选中文字）
3. 首次使用：托盘菜单 -> 设置，配置 API Key。
4. 若提示缺少 WebView2 运行时，请安装（微软官方）：
   https://go.microsoft.com/fwlink/?LinkId=2124703
"@
    [IO.File]::WriteAllText((Join-Path $stage 'README.txt'), $readme, (New-Object Text.UTF8Encoding($true)))
    return $stage
}

function New-Zip([string]$stage, [string]$zipPath) {
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    $tar = Get-Command tar -ErrorAction SilentlyContinue
    if ($tar) {
        & tar -a -c -f $zipPath -C $stage . | Out-Null
    } else {
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -Force
    }
    return $zipPath
}

$results = New-Object System.Collections.Generic.List[object]

function Smoke-Test([string]$name, [string]$runExe) {
    # kill leftovers (process name follows the exe file name: Elta.Windows.exe or renamed ELTA.exe)
    Get-Process Elta.Windows, ELTA -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500

    # selftest (headless clipboard policy, 6 cases)
    $report = Join-Path $env:TEMP 'elta-selftest.txt'
    Remove-Item $report -ErrorAction SilentlyContinue
    Start-Process -FilePath $runExe -ArgumentList '--selftest' -Wait
    Start-Sleep -Milliseconds 500
    $selftestOk = (Test-Path $report) -and ((Get-Content $report -Raw) -match 'selftest pass=6 fail=0')

    # first-launch timing + real translation via hotkey
    $log = Get-ChildItem "$env:LOCALAPPDATA\ELTA\logs\*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    $off = (Get-Content $log).Count
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $app = Start-Process -FilePath $runExe -PassThru
    $started = $false
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 200
        $new = Get-Content $log | Select-Object -Skip $off
        if ($new -match 'start version=') { $started = $true; break }
    }
    $sw.Stop()
    $launchMs = $sw.ElapsedMilliseconds

    $translateOk = $false
    if ($started) {
        $doc = Join-Path $tmp 'elta-pack-smoke.txt'
        Set-Content -LiteralPath $doc -Value 'ELTA package smoke test. The quick brown fox jumps over the lazy dog.' -Encoding UTF8
        Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force
        $np = Start-Process notepad.exe "`"$doc`"" -PassThru
        Start-Sleep -Seconds 2
        $np.Refresh()
        [PackFg]::SetForegroundWindow($np.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 800
        [System.Windows.Forms.SendKeys]::SendWait('^a')
        Start-Sleep -Milliseconds 500
        $off2 = (Get-Content $log).Count
        [System.Windows.Forms.SendKeys]::SendWait('^+t')
        $deadline = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 300
            $new2 = Get-Content $log | Select-Object -Skip $off2
            if ($new2 -match 'translate kind=Success') { $translateOk = $true; break }
        }
        Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue
    }
    Get-Process Elta.Windows, ELTA -ErrorAction SilentlyContinue | Stop-Process -Force
    return [pscustomobject]@{ Selftest = $selftestOk; LaunchMs = $launchMs; Translate = $translateOk }
}

$flavors = if ($Flavor -eq 'both') { @('single', 'folder') } else { @($Flavor) }
foreach ($f in $flavors) {
    Write-Host "== publish $f ==" -ForegroundColor Cyan
    $pub = Publish-Flavor $f
    $stage = Build-Stage $f $pub
    $zip = Join-Path $dist ("ELTA-Windows-v{0}-win-x64-{1}.zip" -f $version, $f)
    New-Zip $stage $zip | Out-Null
    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    [IO.File]::WriteAllText($zip + '.sha256', "$hash  $([IO.Path]::GetFileName($zip))", (New-Object Text.UTF8Encoding($false)))
    $zipMB = [math]::Round((Get-Item $zip).Length / 1MB, 1)
    Write-Host ("  zip: {0} ({1} MB)" -f [IO.Path]::GetFileName($zip), $zipMB)
    Write-Host ("  sha256: {0}" -f $hash)

    $smoke = $null
    if (-not $SkipSmoke) {
        Write-Host "  smoke..."
        $runExe = if ($f -eq 'single') { Join-Path $stage 'ELTA.exe' } else { Join-Path $stage 'ELTA.exe' }
        $smoke = Smoke-Test $f $runExe
        Write-Host ("  smoke: selftest={0} launch={1}ms translate={2}" -f $smoke.Selftest, $smoke.LaunchMs, $smoke.Translate)
    }
    $results.Add([pscustomobject]@{ Flavor = $f; ZipMB = $zipMB; Sha256 = $hash; Selftest = ($smoke -and $smoke.Selftest); LaunchMs = ($smoke -and $smoke.LaunchMs); Translate = ($smoke -and $smoke.Translate) })
}

Write-Host ''
Write-Host '== summary ==' -ForegroundColor Cyan
foreach ($r in $results) {
    Write-Host ("{0,-8} zipMB={1,-8} selftest={2} launchMs={3} translate={4}" -f $r.Flavor, $r.ZipMB, $r.Selftest, $r.LaunchMs, $r.Translate)
}
$allOk = $true
foreach ($r in $results) {
    if (-not $SkipSmoke -and (-not $r.Selftest -or -not $r.Translate)) { $allOk = $false }
}
if (-not $allOk) { exit 1 } else { exit 0 }
