# ELTA Windows —— 截图选择器「三项交互」自动回归（注入式端到端）
# 用法: powershell -ExecutionPolicy Bypass -File windows\test-selector-interactions.ps1 [-EvidenceDir <目录>]
#
# 覆盖（2026-10-04 audit-shell 合并修复后的行为，来源：真机验收 Step 3）：
#   T1 拖拽中按中键   -> 选区不提前提交、覆盖层保持；松开左键才提交
#   T2 单击（0 位移） -> 覆盖层保持打开；仅 ESC/右键取消
#   T3 左缘窄选区     -> 尺寸标签可见（区域差分取证）+ 提交尺寸匹配
#
# 产物：证据截图 + result.txt 写入 -EvidenceDir（默认 %TEMP%\opencode\selector-evidence）
# 注意：会注入鼠标/键盘并移动光标（约 40 秒）；运行期间请勿手动操作鼠标。
# 依赖：被测程序在运行（Elta.Windows 托盘）；日志目录 %LOCALAPPDATA%\ELTA\logs
param(
    [string]$EvidenceDir = (Join-Path $env:TEMP 'opencode\selector-evidence')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Drawing;
using System.Drawing.Imaging;
public static class SelWin2 {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr w, IntPtr l);
    public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int w, int h);
    [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);
    [DllImport("gdi32.dll")] public static extern bool BitBlt(IntPtr dst, int x, int y, int w, int h, IntPtr src, int sx, int sy, uint rop);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr o);
    [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr dc);

    public static IntPtr FindOverlay(uint pid, int minW, int minH) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, l) => {
            uint wp; GetWindowThreadProcessId(h, out wp);
            if (wp != pid || !IsWindowVisible(h)) return true;
            var c = new StringBuilder(64); GetClassName(h, c, 64);
            if (!c.ToString().StartsWith("WindowsForms10")) return true;   // 选择器是 WinForms；排除 WPF 结果窗等
            RECT r; GetWindowRect(h, out r);
            if ((r.Right - r.Left) >= minW && (r.Bottom - r.Top) >= minH) { found = h; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
    public static string Dump(uint pid) {
        var sb = new StringBuilder();
        EnumWindows((h, l) => {
            uint wp; GetWindowThreadProcessId(h, out wp);
            if (wp != pid || !IsWindowVisible(h)) return true;
            var c = new StringBuilder(64); GetClassName(h, c, 64);
            var t = new StringBuilder(128); GetWindowText(h, t, 128);
            RECT r; GetWindowRect(h, out r);
            sb.Append("[").Append(c).Append("]'").Append(t).Append("'").Append(r.Right - r.Left).Append("x").Append(r.Bottom - r.Top).Append("; ");
            return true;
        }, IntPtr.Zero);
        return sb.ToString();
    }
    public static int CloseDialogs(uint pid) {
        int n = 0;
        EnumWindows((h, l) => {
            uint wp; GetWindowThreadProcessId(h, out wp);
            if (wp != pid || !IsWindowVisible(h)) return true;
            var cls = new StringBuilder(64); GetClassName(h, cls, 64);
            if (cls.ToString() == "#32770") { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); n++; }
            return true;
        }, IntPtr.Zero);
        return n;
    }
    public static void CaptureTo(string path, int x, int y, int w, int h) {
        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memDc = CreateCompatibleDC(screenDc);
        IntPtr bmp = CreateCompatibleBitmap(screenDc, w, h);
        IntPtr old = SelectObject(memDc, bmp);
        BitBlt(memDc, 0, 0, w, h, screenDc, x, y, 0x00CC0020u | 0x40000000u);
        using (var img = Image.FromHbitmap(bmp)) { img.Save(path, ImageFormat.Jpeg); }
        SelectObject(memDc, old);
        DeleteObject(bmp);
        DeleteDC(memDc);
        ReleaseDC(IntPtr.Zero, screenDc);
    }
}
"@

function Send-CtrlT { [SelWin2]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60; [SelWin2]::keybd_event(0x54, 0, 0, [UIntPtr]::Zero); [SelWin2]::keybd_event(0x54, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60; [SelWin2]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero) }
function Send-Esc { [SelWin2]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); [SelWin2]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero) }
function MoveTo([int]$x, [int]$y) { [SelWin2]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 90 }
function LeftDown { [SelWin2]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80 }
function LeftUp { [SelWin2]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80 }
function MiddleDown { [SelWin2]::mouse_event(0x0020, 0, 0, 0, [UIntPtr]::Zero) }
function MiddleUp { [SelWin2]::mouse_event(0x0040, 0, 0, 0, [UIntPtr]::Zero) }

$app = Get-Process Elta.Windows -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $app) { Write-Host '[FAIL] Elta.Windows is not running'; exit 1 }
$appPid = [uint32]$app.Id
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$minW = [int]($vs.Width * 0.85); $minH = [int]($vs.Height * 0.85)

$log = Get-ChildItem "$env:LOCALAPPDATA\ELTA\logs\*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
function Log-Lines([int]$off) { return @(Get-Content $log | Select-Object -Skip $off) }
function Count-Captured([int]$off) { return @(Log-Lines $off | Where-Object { $_ -match 'screenshot captured' }).Count }
function Get-CapturedLine([int]$off) { return (Log-Lines $off | Where-Object { $_ -match 'screenshot captured' } | Select-Object -Last 1) }
function Wait-Log([int]$off, [string]$pattern, [int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        $hit = Log-Lines $off | Where-Object { $_ -match $pattern } | Select-Object -Last 1
        if ($hit) { return $hit }
        Start-Sleep -Milliseconds 300
    }
    return $null
}
function Wait-Overlay([int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        $h = [SelWin2]::FindOverlay($appPid, $minW, $minH)
        if ($h -ne [IntPtr]::Zero) { return $h }
        Start-Sleep -Milliseconds 300
    }
    return [IntPtr]::Zero
}
function Wait-OverlayGone([int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        $h = [SelWin2]::FindOverlay($appPid, $minW, $minH)
        if ($h -eq [IntPtr]::Zero) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return $false
}
function Windows-Dump { return [SelWin2]::Dump($appPid) }

New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

# 干净起点：关残留弹窗/覆盖层（防 busy 卡留）
[SelWin2]::CloseDialogs($appPid) | Out-Null
Start-Sleep -Milliseconds 400
$stray = [SelWin2]::FindOverlay($appPid, $minW, $minH)
if ($stray -ne [IntPtr]::Zero) { Send-Esc; Start-Sleep -Milliseconds 700 }

$pass = 0; $fail = 0
function Check([string]$name, [bool]$cond, [string]$detail) {
    if ($cond) { $script:pass++; Write-Host "PASS $name" } else { $script:fail++; Write-Host "FAIL $name | $detail" }
}
$details = @()

# ---------- T1: 拖拽中按中键 ----------
# 用记事本文字做目标（避免空选区触发 OCR 模态框）
$doc = Join-Path $env:TEMP 'opencode\selector-t1.txt'
New-Item -ItemType Directory -Force -Path (Split-Path $doc) | Out-Null
@(
 'The quick brown fox jumps over the lazy dog.',
 'ELTA middle button drag test line one.',
 'Line two for OCR target text.',
 'Line three keeps the selection tall.'
) | Set-Content -LiteralPath $doc -Encoding UTF8
Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force
$np = Start-Process notepad.exe "`"$doc`"" -PassThru
Start-Sleep -Seconds 2
$np.Refresh()
[SelWin2]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 300, 200, 700, 500, 0x0040) | Out-Null
Start-Sleep -Milliseconds 400
[SelWin2]::SetForegroundWindow($np.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 400

$off = (Get-Content $log).Count
Send-CtrlT; Start-Sleep -Milliseconds 900
$ov = Wait-Overlay 4
if ($ov -eq [IntPtr]::Zero) {
    Check 'T1 中键拖拽' $false ("overlay not found after Ctrl+T; windows=" + (Windows-Dump))
} else {
    MoveTo 340 290; LeftDown
    MoveTo 430 315; MoveTo 520 340; MoveTo 610 360; MoveTo 650 365
    [SelWin2]::CaptureTo((Join-Path $EvidenceDir 't1-drag.jpg'), $vs.X, $vs.Y, $vs.Width, $vs.Height)
    MiddleDown; Start-Sleep -Milliseconds 900
    $ovMid = [SelWin2]::FindOverlay($appPid, $minW, $minH)
    $commitsMid = Count-Captured $off
    [SelWin2]::CaptureTo((Join-Path $EvidenceDir 't1-middle.jpg'), $vs.X, $vs.Y, $vs.Width, $vs.Height)
    MiddleUp; Start-Sleep -Milliseconds 300
    LeftUp
    $line = Wait-Log $off 'screenshot captured' 8
    $commitsEnd = Count-Captured $off
    $t1ok = ($ovMid -ne [IntPtr]::Zero) -and ($commitsMid -eq 0) -and ($commitsEnd -eq 1)
    $details += "T1 duringMiddle overlay=$($ovMid -ne [IntPtr]::Zero) commits=$commitsMid; afterRelease commits=$commitsEnd $line"
    Check 'T1 中键拖拽' $t1ok ($details[-1])
    # 等流水线完全落地再进入 T2
    Wait-Log $off 'translate kind=' 25 | Out-Null
    Wait-Log $off 'result window shown' 10 | Out-Null
    Start-Sleep -Seconds 2
}

# ---------- T2: 单击不取消 ----------
$off2 = (Get-Content $log).Count
Send-CtrlT; Start-Sleep -Milliseconds 900
$ov2 = Wait-Overlay 4
if ($ov2 -eq [IntPtr]::Zero) {
    # 可能是残留 busy/弹窗；清理后重试一次
    [SelWin2]::CloseDialogs($appPid) | Out-Null
    Start-Sleep -Milliseconds 600
    Send-CtrlT; Start-Sleep -Milliseconds 900
    $ov2 = Wait-Overlay 3
}
if ($ov2 -eq [IntPtr]::Zero) {
    Check 'T2 单击不取消' $false ("overlay not found after Ctrl+T; windows=" + (Windows-Dump))
} else {
    MoveTo 500 420; LeftDown; Start-Sleep -Milliseconds 50; LeftUp
    $ovAfterClick = Wait-Overlay 3
    [SelWin2]::CaptureTo((Join-Path $EvidenceDir 't2-after-click.jpg'), $vs.X, $vs.Y, $vs.Width, $vs.Height)
    $commits2 = Count-Captured $off2
    # 取消用右键：规范允许 ESC/右键；但"结果窗开启"时面板键盘路由会先截走 ESC（2026-10-04 发现，见 NOTES），
    # 右键对覆盖层始终有效，作为稳定的自动取消路径。
    [SelWin2]::mouse_event(0x0008, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60; [SelWin2]::mouse_event(0x0010, 0, 0, 0, [UIntPtr]::Zero)
    $gone = Wait-OverlayGone 4
    $t2ok = ($ovAfterClick -ne [IntPtr]::Zero) -and ($commits2 -eq 0) -and $gone
    $detail2 = "T2 afterClick overlay=$($ovAfterClick -ne [IntPtr]::Zero) commits=$commits2; afterEsc gone=$gone"
    if (-not $t2ok) { $detail2 += "; windows=" + (Windows-Dump) }
    $details += $detail2
    Check 'T2 单击不取消' $t2ok $detail2
}

# ---------- T3: 左缘窄选区 + 尺寸标签 ----------
$off3 = (Get-Content $log).Count
Send-CtrlT; Start-Sleep -Milliseconds 900
$ov3 = Wait-Overlay 4
if ($ov3 -eq [IntPtr]::Zero) {
    [SelWin2]::CloseDialogs($appPid) | Out-Null
    Start-Sleep -Milliseconds 600
    Send-CtrlT; Start-Sleep -Milliseconds 900
    $ov3 = Wait-Overlay 3
}
if ($ov3 -eq [IntPtr]::Zero) {
    Check 'T3 窄选区标签' $false ("overlay not found after Ctrl+T; windows=" + (Windows-Dump))
} else {
    $refPath = Join-Path $EvidenceDir 't3-ref.jpg'
    [SelWin2]::CaptureTo($refPath, $vs.X, $vs.Y, $vs.Width, $vs.Height)
    MoveTo 1 300; LeftDown
    MoveTo 8 340; MoveTo 15 400; MoveTo 22 460; MoveTo 22 500
    Start-Sleep -Milliseconds 500
    $holdPath = Join-Path $EvidenceDir 't3-hold.jpg'
    [SelWin2]::CaptureTo($holdPath, $vs.X, $vs.Y, $vs.Width, $vs.Height)
    # 标签差分取证：标签位于左缘窄选区上方 (~x 4..80, y ~277..294)
    $a = [System.Drawing.Bitmap]::FromFile($refPath)
    $b = [System.Drawing.Bitmap]::FromFile($holdPath)
    $changed = 0
    for ($y = 250; $y -lt 330; $y += 2) {
        for ($x = 0; $x -lt 140; $x += 2) {
            $ca = $a.GetPixel($x, $y); $cb = $b.GetPixel($x, $y)
            if (([Math]::Abs($ca.R - $cb.R) + [Math]::Abs($ca.G - $cb.G) + [Math]::Abs($ca.B - $cb.B)) -gt 90) { $changed++ }
        }
    }
    $a.Dispose(); $b.Dispose()
    LeftUp
    $line3 = Wait-Log $off3 'screenshot captured' 8
    $w = 0; $h = 0
    if ($line3 -match 'screenshot captured (\d+)x(\d+)') { $w = [int]$Matches[1]; $h = [int]$Matches[2] }
    $t3ok = ($changed -gt 80) -and ($w -gt 0) -and ($w -le 40) -and ($h -ge 100)
    $details += "T3 labelChangedPixels=$changed dims=${w}x${h} $line3"
    Check 'T3 窄选区标签' $t3ok ($details[-1])
}

# 收尾：关 OCR 模态框（空选区路径可能弹）、清理记事本、光标归位
Start-Sleep -Seconds 2
[SelWin2]::CloseDialogs($appPid) | Out-Null
Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force
MoveTo 700 400

Write-Host "---- test-selector-interactions: pass=$pass fail=$fail ----"
[IO.File]::WriteAllText((Join-Path $EvidenceDir 'result.txt'),
    ("pass=$pass fail=$fail" + "`r`n" + ($details -join "`r`n")),
    (New-Object Text.UTF8Encoding($false)))
Write-Host "evidence: $EvidenceDir"
if ($fail -gt 0) { exit 1 } else { exit 0 }
