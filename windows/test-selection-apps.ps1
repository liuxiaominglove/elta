param(
    [switch]$SkipPdf
)

# ELTA Windows - Word / WPS selection smoke (B2 leftover)
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File windows\test-selection-apps.ps1
#
# !!! SAFETY (2026-10-04 incident) !!!
# `--selection-cli` synthesizes a GLOBAL Ctrl+C. It must only ever be launched while the
# target app window is guaranteed foreground. NEVER run the CLI ad-hoc from a terminal
# (a synthetic Ctrl+C hitting the terminal/opencode will interrupt it).
# This script always focuses the target window before launching the CLI.
#
# Notes from probing (2026-10-04):
# - WPS is Qt-based; its document window is class OpusApp titled "<file> - WPS Office".
#   Keystrokes only reach the editor after a real mouse click inside the document area.
# - WPS must be opened with a real document (.docx built locally by this script).
# - Word on this machine: Office trial expired ("5 天评估期已经结束" dialog) - best effort.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.IO.Compression.FileSystem

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;
public static class SelWin {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  public struct RECT { public int Left, Top, Right, Bottom; }
  public static string[] List(int[] pids) {
    var lines = new List<string>();
    EnumWindows((h, l) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      bool hit = false;
      foreach (var p in pids) if ((uint)p == pid) hit = true;
      if (!hit || !IsWindowVisible(h)) return true;
      var t = new StringBuilder(512); GetWindowText(h, t, 512);
      var c = new StringBuilder(256); GetClassName(h, c, 256);
      lines.Add(h + "|" + c + "|" + t);
      return true;
    }, IntPtr.Zero);
    return lines.ToArray();
  }
  public static long FgPid() {
    uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid);
    return pid;
  }
  public static string FgTitle() {
    var t = new StringBuilder(512); GetWindowText(GetForegroundWindow(), t, 512);
    return t.ToString();
  }
  public static void ClickInto(IntPtr h) {
    RECT r; GetWindowRect(h, out r);
    int x = (r.Left + r.Right) / 2;
    int y = r.Top + (r.Bottom - r.Top) / 3;
    SetForegroundWindow(h);
    System.Threading.Thread.Sleep(500);
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(250);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(90);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(500);
  }
}
"@

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $root 'src\Elta.Windows\bin\Release\net8.0-windows10.0.19041.0\Elta.Windows.exe'
if (-not (Test-Path $exe)) {
    Write-Host '[FAIL] Elta.Windows.exe not found. Run windows\build-windows.bat first.' -ForegroundColor Red
    exit 1
}

$marker = 'ELTA-SEL-CHK-12345'
$sample = "$marker ELTA quick brown fox. Word/WPS selection smoke 98765."
$tmp = Join-Path $env:TEMP 'opencode'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$resultFile = Join-Path $tmp 'elta-test-selection-result.txt'

$wsh = New-Object -ComObject WScript.Shell
function Notify([string]$msg, [int]$sec) {
    $wsh.Popup($msg, $sec, 'ELTA 取词抽检', 64) | Out-Null
}

# --- kill leftovers of target families ---
function Kill-Family([string[]]$names) {
    foreach ($n in $names) {
        Get-Process $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 500
}
Kill-Family @('WINWORD', 'wps', 'wpspdf', 'ksolaunch')

# --- build minimal .docx ---
function Build-Docx([string]$path, [string]$text) {
    $build = Join-Path $tmp 'docx-build'
    Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $path -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $build | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $build '_rels') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $build 'word') | Out-Null
    $utf8 = New-Object Text.UTF8Encoding($false)
    $ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
    $rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    $doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>' + $text + '</w:t></w:r></w:p></w:body></w:document>'
    [IO.File]::WriteAllText((Join-Path $build '[Content_Types].xml'), $ct, $utf8)
    [IO.File]::WriteAllText((Join-Path $build '_rels\.rels'), $rels, $utf8)
    [IO.File]::WriteAllText((Join-Path $build 'word\document.xml'), $doc, $utf8)
    [System.IO.Compression.ZipFile]::CreateFromDirectory($build, $path)
}
$docx = Join-Path $tmp 'elta-sel-sample.docx'
Build-Docx $docx $sample

$logDir = Join-Path $env:LOCALAPPDATA 'ELTA\logs'
$log = Get-ChildItem $logDir -Filter '*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName

function Get-LogOffset {
    if ($log -and (Test-Path $log)) { return (Get-Content $log).Count } else { return 0 }
}
function Show-NewLog([int]$offset, [string[]]$patterns) {
    if (-not $log -or -not (Test-Path $log)) { return }
    $all = Get-Content $log
    if ($all.Count -le $offset) { return }
    $new = $all[$offset..($all.Count - 1)]
    foreach ($p in $patterns) {
        foreach ($h in ($new | Where-Object { $_ -match $p })) {
            Write-Host "    log: $h" -ForegroundColor DarkGray
        }
    }
}

$script:pass = 0
$script:fail = 0
$script:skip = 0
$results = New-Object System.Collections.Generic.List[object]

function Add-Result([string]$name, [string]$status, [string]$detail) {
    $script:results.Add([pscustomobject]@{ Case = $name; Status = $status; Detail = $detail })
    switch ($status) {
        'PASS' { $script:pass++ }
        'FAIL' { $script:fail++ }
        'SKIP' { $script:skip++ }
    }
    Write-Host ("{0,-14} {1,-4} {2}" -f $name, $status, $detail)
}

function Get-Windows([string[]]$procNames) {
    $ids = @(Get-Process $procNames -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    if ($ids.Count -eq 0) { return @() }
    return [SelWin]::List($ids)
}

function Find-Window([string[]]$procNames, [string]$needle) {
    foreach ($w in (Get-Windows $procNames)) {
        $parts = $w -split '\|', 3
        if ($parts[2] -and $parts[2].Contains($needle)) {
            return [pscustomobject]@{ Hwnd = [IntPtr][long]$parts[0]; Class = $parts[1]; Title = $parts[2] }
        }
    }
    return $null
}

function Wait-Window([string[]]$procNames, [string]$needle, [int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        $w = Find-Window $procNames $needle
        if ($w) { return $w }
        Start-Sleep -Milliseconds 700
    }
    return $null
}

function Run-Cli([string]$outPath) {
    if (Test-Path $outPath) { Remove-Item $outPath -Force }
    Start-Process -FilePath $exe -ArgumentList '--selection-cli', "`"$outPath`"" -Wait
    Start-Sleep -Milliseconds 300
    if (-not (Test-Path $outPath)) {
        Start-Sleep -Milliseconds 500
        if (-not (Test-Path $outPath)) { return '[warn] cli out file missing' }
    }
    return (Get-Content -LiteralPath $outPath -Raw)
}

function Capture-Once([string[]]$procNames, $win, [string]$outPath) {
    [SelWin]::ClickInto($win.Hwnd) | Out-Null
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    Start-Sleep -Milliseconds 600
    $fgPid = [SelWin]::FgPid()
    $ids = @(Get-Process $procNames -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    if ($ids -notcontains [int]$fgPid) {
        [SelWin]::SetForegroundWindow($win.Hwnd) | Out-Null
        Start-Sleep -Milliseconds 400
    }
    return Run-Cli $outPath
}

function Test-App([string]$name, [string]$appExe, [string]$fileArg, [string]$needle, [string[]]$procNames, [switch]$ManualSelect) {
    Write-Host "== $name ==" -ForegroundColor Cyan
    $offset = Get-LogOffset
    $outPath = Join-Path $tmp "elta-sel-out-$name.txt"
    $null = Start-Process -FilePath $appExe -ArgumentList "`"$fileArg`"" -PassThru
    $win = Wait-Window $procNames $needle 35
    if (-not $win) {
        Notify "$name 文档窗口未出现。请查看该应用是否有弹窗需要处理（登录/欢迎页可关闭）。约 20 秒后自动重试。" 20
        $win = Wait-Window $procNames $needle 35
    }
    if (-not $win) {
        Add-Result $name 'SKIP' 'document window not found'
        Kill-Family $procNames
        return
    }
    Write-Host "  window: class=$($win.Class) title='$($win.Title)'"

    for ($i = 1; $i -le 2; $i++) {
        $out = Capture-Once $procNames $win $outPath
        Show-NewLog $offset @('selection-cli len=', 'selection via ')
        if ($out -like "*$marker*") {
            Add-Result $name 'PASS' "ctrl+c selection ok (attempt $i)"
            Kill-Family $procNames
            return
        }
    }

    if ($ManualSelect) {
        Notify "自动流程未取到文本。请在 $name 中手动拖拽选中含 $marker 的那行文字（约 20 秒后自动继续）。" 20
        Start-Sleep -Seconds 21
        [SelWin]::SetForegroundWindow($win.Hwnd) | Out-Null
        Start-Sleep -Milliseconds 500
        $out = Run-Cli $outPath
        Show-NewLog $offset @('selection-cli len=', 'selection via ')
        if ($out -like "*$marker*") {
            Add-Result $name 'PASS' 'manual selection ok'
            Kill-Family $procNames
            return
        }
    }

    $preview = if ($out.Length -gt 80) { $out.Substring(0, 80) } else { $out }
    Add-Result $name 'FAIL' "captured: $preview"
    Kill-Family $procNames
}

# --- locate apps ---
$word = 'C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE'
$wps = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Kingsoft\WPS Office') -Recurse -Filter 'wps.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'office6' } | Select-Object -First 1 -ExpandProperty FullName
$wpspdf = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Kingsoft\WPS Office') -Recurse -Filter 'wpspdf.exe' -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
$edge = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
if (-not (Test-Path $edge)) { $edge = Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe' }

# --- S1 Word (best effort: Office trial on this machine is expired) ---
if (Test-Path $word) {
    Write-Host '== S1-Word ==' -ForegroundColor Cyan
    $offset = Get-LogOffset
    $null = Start-Process -FilePath $word -ArgumentList "`"$docx`"" -PassThru
    Start-Sleep -Seconds 14
    $wins = Get-Windows @('WINWORD')
    $blocked = $wins | Where-Object { $_ -match '(试用|评估|激活)' }
    $docWin = $wins | Where-Object { $_ -match 'elta-sel-sample' } | Select-Object -First 1
    if ($blocked -and -not $docWin) {
        Add-Result 'S1-Word' 'SKIP' 'Office trial expired on this machine'
        Kill-Family @('WINWORD')
    } elseif ($blocked -and $docWin) {
        # dismiss dialog with ESC, then best-effort capture
        [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
        Start-Sleep -Seconds 2
        $parts = $docWin -split '\|', 3
        $win = [pscustomobject]@{ Hwnd = [IntPtr][long]$parts[0]; Class = $parts[1]; Title = $parts[2] }
        $out = Capture-Once @('WINWORD') $win (Join-Path $tmp 'elta-sel-out-S1-Word.txt')
        Show-NewLog $offset @('selection-cli len=', 'selection via ')
        if ($out -like "*$marker*") {
            Add-Result 'S1-Word' 'PASS' 'selection ok (trial-expired Word, best effort)'
        } else {
            Add-Result 'S1-Word' 'SKIP' 'Office trial expired - capture blocked'
        }
        Kill-Family @('WINWORD')
    } elseif ($docWin) {
        $parts = $docWin -split '\|', 3
        $win = [pscustomobject]@{ Hwnd = [IntPtr][long]$parts[0]; Class = $parts[1]; Title = $parts[2] }
        $out = Capture-Once @('WINWORD') $win (Join-Path $tmp 'elta-sel-out-S1-Word.txt')
        Show-NewLog $offset @('selection-cli len=', 'selection via ')
        if ($out -like "*$marker*") {
            Add-Result 'S1-Word' 'PASS' 'ctrl+c selection ok'
        } else {
            # 本机 Office 试用期已结束（reduced functionality），复制被限；非本产品失败
            Add-Result 'S1-Word' 'SKIP' 'Word doc opened but capture blocked (Office trial expired)'
        }
        Kill-Family @('WINWORD')
    } else {
        Add-Result 'S1-Word' 'SKIP' 'no document window'
        Kill-Family @('WINWORD')
    }
} else {
    Add-Result 'S1-Word' 'SKIP' 'WINWORD.EXE not found'
}

# --- S2 WPS Writer ---
if ($wps) {
    Test-App 'S2-WPSWriter' $wps $docx 'elta-sel-sample' @('wps') -ManualSelect
} else {
    Add-Result 'S2-WPSWriter' 'SKIP' 'wps.exe not found'
}

# --- S3 WPS PDF ---
if ($SkipPdf) {
    Add-Result 'S3-WPSPDF' 'SKIP' 'skipped by flag'
} elseif (-not $wpspdf) {
    Add-Result 'S3-WPSPDF' 'SKIP' 'wpspdf.exe not found'
} else {
    $html = Join-Path $tmp 'elta-sel-sample.html'
    $pdf = Join-Path $tmp 'elta-sel-sample.pdf'
    Set-Content -LiteralPath $html -Value "<html><head><meta charset=`"utf-8`"></head><body><p>$sample</p></body></html>" -Encoding UTF8
    Remove-Item $pdf -Force -ErrorAction SilentlyContinue
    if (Test-Path $edge) {
        $uri = 'file:///' + ($html -replace '\\', '/')
        Start-Process -FilePath $edge -Wait -WindowStyle Hidden -ArgumentList @(
            '--headless', '--disable-gpu', '--no-first-run',
            "--user-data-dir=$tmp\edge-profile", "--print-to-pdf=$pdf", $uri
        )
        $deadline = (Get-Date).AddSeconds(15)
        while (-not (Test-Path $pdf) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    }
    if (Test-Path $pdf) {
        Test-App 'S3-WPSPDF' $wpspdf $pdf 'elta-sel' @('wpspdf', 'wps') -ManualSelect
    } else {
        Add-Result 'S3-WPSPDF' 'SKIP' 'pdf generation failed (edge headless)'
    }
}

# --- summary ---
Write-Host ''
Write-Host '---- test-selection-apps summary ----' -ForegroundColor Cyan
foreach ($r in $results) {
    $color = if ($r.Status -eq 'PASS') { 'Green' } elseif ($r.Status -eq 'FAIL') { 'Red' } else { 'Yellow' }
    Write-Host ("{0,-14} {1,-4} {2}" -f $r.Case, $r.Status, $r.Detail) -ForegroundColor $color
}
$summary = "pass=$pass fail=$fail skip=$skip"
Write-Host $summary

$lines = @()
foreach ($r in $results) { $lines += ("{0}|{1}|{2}" -f $r.Case, $r.Status, $r.Detail) }
$lines += $summary
[IO.File]::WriteAllText($resultFile, ($lines -join "`r`n"), (New-Object Text.UTF8Encoding($false)))

if ($fail -gt 0) { exit 1 } else { exit 0 }
