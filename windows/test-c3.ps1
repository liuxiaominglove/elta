# ELTA Windows 机测：设置窗口三页（通用 / 快捷键 / 模板）
# 离线用例，无需 API Key。用法：
#   powershell -ExecutionPolicy Bypass -File windows\test-c3.ps1
# 退出码：0=全部通过；1=有失败。
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class C3Native {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public static void Activate(IntPtr h) {
    ShowWindow(h, 9);
    IntPtr fg = GetForegroundWindow();
    uint p; uint tid = GetWindowThreadProcessId(fg, out p);
    AttachThreadInput(GetCurrentThreadId(), tid, true);
    SetForegroundWindow(h);
    AttachThreadInput(GetCurrentThreadId(), tid, false);
  }
  public static IntPtr FindDialog(uint targetPid) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p == targetPid && IsWindowVisible(h)) {
        var sb = new StringBuilder(64);
        GetClassName(h, sb, 64);
        if (sb.ToString() == "#32770") { found = h; return false; }
      }
      return true;
    }, IntPtr.Zero);
    return found;
  }
  private delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr l);
}
'@

$pass = 0; $fail = 0
function Check([string]$name, [bool]$cond) {
  if ($cond) { $script:pass++; Write-Host "PASS $name" } else { $script:fail++; Write-Host "FAIL $name" }
}
function ByName([string]$n) {
  New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $n)
}
function ByType($t) {
  New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $t)
}
function Wait-Desc($root, $cond, [int]$ms = 8000) {
  $dl = (Get-Date).AddMilliseconds($ms)
  while ((Get-Date) -lt $dl) {
    $e = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($e) { return $e }
    Start-Sleep -Milliseconds 250
  }
  return $null
}
function Find-WinPid([string]$t, [int]$pid2) {
  foreach ($w in [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
      [System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    try { if ($w.Current.Name -eq $t -and $w.Current.ProcessId -eq $pid2) { return $w } } catch {}
  }
  return $null
}
function Confirm-ResetDialog([int]$pid2) {
  Start-Sleep -Milliseconds 1000
  $h = [C3Native]::FindDialog([uint32]$pid2)
  if ($h -eq [IntPtr]::Zero) { return $false }
  [C3Native]::Activate($h)
  Start-Sleep -Milliseconds 300
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  return $true
}
function Get-Setting([string]$key) {
  $sf = "$env:APPDATA\ELTA\settings.json"
  if (-not (Test-Path $sf)) { return $null }
  return (Get-Content $sf -Raw -Encoding UTF8 | ConvertFrom-Json).$key
}

$exe = Join-Path $PSScriptRoot 'src\Elta.Windows\bin\Release\net8.0-windows10.0.19041.0\Elta.Windows.exe'
if (-not (Test-Path $exe)) { Write-Host "先构建：dotnet build windows\src\Elta.Windows -c Release"; exit 1 }

Get-Process Elta.Windows -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600

$app = Start-Process $exe -ArgumentList '--settings-ui' -PassThru
$title = 'ELTA 偏好设置'
$win = $null
$dl = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $dl -and -not $win) { $win = Find-WinPid $title $app.Id; if (-not $win) { Start-Sleep -Milliseconds 300 } }
if (-not $win) { Write-Host 'FAIL settings window not found'; Stop-Process -Id $app.Id -Force; exit 1 }
[C3Native]::Activate([IntPtr]$win.Current.NativeWindowHandle)
Start-Sleep -Milliseconds 800

# ---- 通用页 ----
Check '通用页：provider 组合框存在' ($null -ne (Wait-Desc $win (ByType ([System.Windows.Automation.ControlType]::ComboBox)) 5000))
Check '通用页：匿名统计勾选框存在' ($null -ne (Wait-Desc $win (ByName '参与匿名使用统计') 3000))
Check '通用页：测试连接按钮存在' ($null -ne (Wait-Desc $win (ByName '测试连接') 3000))

# ---- 快捷键页 ----
$tabHotkeys = '快捷键'
$tab = Wait-Desc $win (ByName $tabHotkeys) 5000
($tab.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)).Select()
Start-Sleep -Milliseconds 700
$recBtn = Wait-Desc $win (ByName 'Ctrl+T') 6000
Check '快捷键页：截图录制按钮存在（Ctrl+T）' ($null -ne $recBtn)
if ($recBtn) {
  ($recBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
  Start-Sleep -Milliseconds 500
  [System.Windows.Forms.SendKeys]::SendWait('^+y')
  Start-Sleep -Milliseconds 900
  Check '快捷键页：录得 Ctrl+Shift+Y' ($null -ne (Wait-Desc $win (ByName 'Ctrl+Shift+Y') 4000))
}
$resetBtn = Wait-Desc $win (ByName '恢复默认') 4000
if ($resetBtn) {
  ($resetBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
  Check '快捷键页：恢复默认确认框弹出' (Confirm-ResetDialog $app.Id)
  Start-Sleep -Milliseconds 1000
  Check '快捷键页：复位回 Ctrl+T' ($null -ne (Wait-Desc $win (ByName 'Ctrl+T') 4000))
}

# ---- 模板页 ----
$tab = Wait-Desc $win (ByName '模板') 4000
($tab.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)).Select()
Start-Sleep -Milliseconds 700
$edit = Wait-Desc $win (ByType ([System.Windows.Automation.ControlType]::Edit)) 6000
Check '模板页：模板文本框存在' ($null -ne $edit)
if ($edit) {
  $vp = $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
  Check '模板页：默认态只读' ($vp.Current.IsReadOnly)
  $customRadio = Wait-Desc $win (ByName '自定义模板') 4000
  ($customRadio.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)).Select()
  Start-Sleep -Milliseconds 500
  Check '模板页：自定义态可编辑' (-not $vp.Current.IsReadOnly)
  $vp.SetValue('REGRESSION TEMPLATE')
  Start-Sleep -Milliseconds 300
  $saveBtn = Wait-Desc $win (ByName '保存并应用') 4000
  ($saveBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
  Start-Sleep -Milliseconds 1000
  Check '模板页：保存写入 custom' ((Get-Setting 'snaptranslate.prompt.custom') -eq 'REGRESSION TEMPLATE')
  Check '模板页：保存 usesDefault=false' ((Get-Setting 'snaptranslate.prompt.usesDefault') -eq $false)
  $resetBtn2 = Wait-Desc $win (ByName '恢复默认') 4000
  ($resetBtn2.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
  [void](Confirm-ResetDialog $app.Id)
  Start-Sleep -Milliseconds 1100
  Check '模板页：恢复默认 usesDefault=true' ((Get-Setting 'snaptranslate.prompt.usesDefault') -eq $true)
  Check '模板页：恢复默认清除 custom' ($null -eq (Get-Setting 'snaptranslate.prompt.custom'))
}

Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400
$sf = "$env:APPDATA\ELTA\settings.json"
try {
  $json = Get-Content $sf -Raw -Encoding UTF8 | ConvertFrom-Json
  $json.PSObject.Properties.Remove('snaptranslate.popupFontSize')
  $json | ConvertTo-Json -Depth 5 | Set-Content $sf -Encoding UTF8
} catch {}

Write-Host "---- test-c3: pass=$pass fail=$fail ----"
if ($fail -eq 0) { exit 0 } else { exit 1 }
