$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class SelEmpty {
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, UIntPtr e);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint fl);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder sb, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public static bool HasDialog(uint pid) {
        bool found = false;
        EnumWindows((h, l) => {
            uint wp; GetWindowThreadProcessId(h, out wp);
            if (wp != pid || !IsWindowVisible(h)) return true;
            var c = new StringBuilder(64); GetClassName(h, c, 64);
            if (c.ToString() == "#32770") { found = true; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
    public static int CloseDialogs(uint pid) {
        int n = 0;
        EnumWindows((h, l) => {
            uint wp; GetWindowThreadProcessId(h, out wp);
            if (wp != pid || !IsWindowVisible(h)) return true;
            var c = new StringBuilder(64); GetClassName(h, c, 64);
            if (c.ToString() == "#32770") { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); n++; }
            return true;
        }, IntPtr.Zero);
        return n;
    }
    public static void CtrlShiftT() {
        keybd_event(0x11,0,0,UIntPtr.Zero); keybd_event(0x10,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(50);
        keybd_event(0x54,0,0,UIntPtr.Zero); keybd_event(0x54,0,2,UIntPtr.Zero); System.Threading.Thread.Sleep(50);
        keybd_event(0x10,0,2,UIntPtr.Zero); keybd_event(0x11,0,2,UIntPtr.Zero);
    }
}
"@

# ELTA Windows -「划词空选不阻塞」回归（F1 修复验收）
# 断言：① 空选触发后无 #32770 模态框；② busy 立即释放——紧接着的真实选择能正常取词+翻译（无 ignored: busy）
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File windows\test-selection-empty.ps1

$app = Get-Process Elta.Windows -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $app) { Write-Host '[FAIL] app not running'; exit 1 }
$appPid = [uint32]$app.Id
$log = Get-ChildItem "$env:LOCALAPPDATA\ELTA\logs\*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
function LogNew([int]$off) { return @(Get-Content $log | Select-Object -Skip $off) }

$pass = 0; $fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "PASS $name" } else { $script:fail++; Write-Host "FAIL $name | $detail" }
}

# 干净起点
[SelEmpty]::CloseDialogs($appPid) | Out-Null
Start-Sleep -Milliseconds 600

# 记事本：有文本、无选区（光标置于文末）
$doc = Join-Path $env:TEMP 'opencode\selection-empty.txt'
Set-Content -LiteralPath $doc -Value 'ELTA selection empty regression. The quick brown fox jumps over the lazy dog.' -Encoding UTF8
Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force
$np = Start-Process notepad.exe "`"$doc`"" -PassThru
Start-Sleep -Seconds 2
$np.Refresh()
[SelEmpty]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 300, 200, 700, 500, 0x0040) | Out-Null
Start-Sleep -Milliseconds 400
[SelEmpty]::SetForegroundWindow($np.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait('{END}')   # 收起任何已有选区（空选区状态）
Start-Sleep -Milliseconds 300
Set-Clipboard -Value 'SEL-EMPTY-SENTINEL'

# ① 空选触发
$off = (Get-Content $log).Count
[SelEmpty]::CtrlShiftT()
$dl = (Get-Date).AddSeconds(15)
$len0 = $null
while ((Get-Date) -lt $dl -and -not $len0) {
    Start-Sleep -Milliseconds 300
    $len0 = LogNew $off | Where-Object { $_ -match 'selection len=' } | Select-Object -Last 1
}
Check 'empty selection logged' ($len0 -match 'selection len=0') "$len0"
$dialog = $false
$dl = (Get-Date).AddSeconds(4)
while ((Get-Date) -lt $dl -and -not $dialog) {
    $dialog = [SelEmpty]::HasDialog($appPid)
    if (-not $dialog) { Start-Sleep -Milliseconds 400 }
}
Check 'no modal dialog on empty selection' (-not $dialog) 'dialog #32770 appeared (F1 not fixed)'

# ② busy 立即释放：紧接着真实选择应能正常取词+翻译
$np.Refresh()
[SelEmpty]::SetForegroundWindow($np.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 400
[System.Windows.Forms.SendKeys]::SendWait('^a')
Start-Sleep -Milliseconds 400
$off2 = (Get-Content $log).Count
[SelEmpty]::CtrlShiftT()
$dl = (Get-Date).AddSeconds(25)
$tr = $null
while ((Get-Date) -lt $dl -and -not $tr) {
    Start-Sleep -Milliseconds 400
    $tr = LogNew $off2 | Where-Object { $_ -match 'translate kind=' } | Select-Object -Last 1
}
$newLines = LogNew $off2
$ignored = @($newLines | Where-Object { $_ -match 'selection ignored: busy' }).Count
$len2 = @($newLines | Where-Object { $_ -match 'selection len=' } | Select-Object -Last 1)
Check 'busy released immediately (no ignored: busy)' ($ignored -eq 0) "ignored:busy x$ignored"
Check 'follow-up selection works' (($len2 -match 'selection len=[1-9]') -and ($tr -match 'translate kind=Success')) "len=$len2 tr=$tr"

[SelEmpty]::CloseDialogs($appPid) | Out-Null
Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue
Write-Host "---- test-selection-empty: pass=$pass fail=$fail ----"
if ($fail -gt 0) { exit 1 } else { exit 0 }
