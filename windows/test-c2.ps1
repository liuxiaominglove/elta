# ELTA Windows 机测：结果窗口交互（C2 回归门禁）
# 覆盖：对侧半屏定位 / 默认拆分 / 整段切换 / A± 持久化与边界 / ` 翻面 / Ctrl+D / ESC 关闭 /
#       双触发竞态（任务代数）/ 加载期 ESC 取消 / 窗口记忆 / 截图拖拽链 / 副屏 150% 冒烟
# 需要：已构建 + 已配置 API Key（无 Key 时输出 SKIP 并以退出码 3 结束）。用法：
#   powershell -ExecutionPolicy Bypass -File windows\test-c2.ps1
# 退出码：0=全过；1=有失败；3=无 Key 跳过。
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class C2Native {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  public static void Activate(IntPtr h) {
    ShowWindow(h, 9);
    IntPtr fg = GetForegroundWindow();
    uint p; uint tid = GetWindowThreadProcessId(fg, out p);
    AttachThreadInput(GetCurrentThreadId(), tid, true);
    SetForegroundWindow(h);
    AttachThreadInput(GetCurrentThreadId(), tid, false);
  }
  public static IntPtr FindWinPid(string title, int pid) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p == (uint)pid && IsWindowVisible(h)) {
        var sb = new StringBuilder(300);
        GetWindowText(h, sb, 300);
        if (sb.ToString() == title) { found = h; return false; }
      }
      return true;
    }, IntPtr.Zero);
    return found;
  }
  private delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] private static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr h);
}
'@

$pass = 0; $fail = 0; $skip = 0
function Check([string]$name, [bool]$cond) {
  if ($cond) { $script:pass++; Write-Host "PASS $name" } else { $script:fail++; Write-Host "FAIL $name" }
}
function Skip([string]$name) { $script:skip++; Write-Host "SKIP $name" }
function IsZero($h) { return ($null -eq $h) -or ($h -eq [IntPtr]::Zero) }
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
function Find-ResultWin([int]$pid2) { return [C2Native]::FindWinPid($resultTitle, $pid2) }
function Wait-Result([int]$seconds) {
  $dl = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $dl) {
    $h = Find-ResultWin $app.Id
    if (-not (IsZero $h)) { return $h }
    Start-Sleep -Milliseconds 300
  }
  return [IntPtr]::Zero
}
function Wait-NoResult([int]$seconds) {
  $dl = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $dl) {
    if (IsZero (Find-ResultWin $app.Id)) { return $true }
    Start-Sleep -Milliseconds 250
  }
  return (IsZero (Find-ResultWin $app.Id))
}
function SendEsc { [System.Windows.Forms.SendKeys]::SendWait('{ESC}') }
# 段间清场：ESC（先取消可能的加载，再关可能的面板），直到无结果窗
function EnsureClean {
  for ($i = 0; $i -lt 3; $i++) {
    SendEsc
    Start-Sleep -Milliseconds 500
    if (IsZero (Find-ResultWin $app.Id)) { break }
  }
  [void](Wait-NoResult 4)
}
function Get-UaWin {
  foreach ($w in [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
      [System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    try { if ($w.Current.Name -eq $resultTitle -and $w.Current.ProcessId -eq $app.Id) { return $w } } catch {}
  }
  return $null
}
function New-Rect { New-Object C2Native+RECT }
function Get-Rect($h) {
  $r = New-Rect
  [void][C2Native]::GetWindowRect($h, [ref]$r)
  return $r
}
function TriggerSelection {
  [void]$sh.AppActivate($np.Id)
  Start-Sleep -Milliseconds 400
  [System.Windows.Forms.SendKeys]::SendWait('^a')
  Start-Sleep -Milliseconds 300
  [System.Windows.Forms.SendKeys]::SendWait('^+t')
}
function Get-Setting([string]$key) {
  $sf = "$env:APPDATA\ELTA\settings.json"
  if (-not (Test-Path $sf)) { return $null }
  return (Get-Content $sf -Raw -Encoding UTF8 | ConvertFrom-Json).$key
}
function Log-Since([int]$offset) { (Get-Content $logFile | Select-Object -Skip $offset) -join "`n" }

$resultTitle = '翻译结果 — ELTA'

$exe = Join-Path $PSScriptRoot 'src\Elta.Windows\bin\Release\net8.0-windows10.0.19041.0\Elta.Windows.exe'
if (-not (Test-Path $exe)) { Write-Host "先构建：dotnet build windows\src\Elta.Windows -c Release"; exit 1 }

Get-Process Elta.Windows, notepad -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600

$doc = Join-Path $env:TEMP 'elta-c2-regression.txt'
Set-Content -Path $doc -Value @(
  'Artificial intelligence is changing the way people read and write.',
  'Modern language models can summarize long documents in seconds.',
  'However, accuracy still depends on the quality of the input text.'
) -Encoding ascii
$np = Start-Process notepad.exe $doc -PassThru
$app = Start-Process $exe -PassThru
Start-Sleep -Seconds 3

$logFile = (Get-ChildItem "$env:LOCALAPPDATA\ELTA\logs\*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
$keySet = ((Get-Content $logFile -Tail 20) -match 'keySet=True')
if (-not $keySet) {
  Write-Host "SKIP：未配置 API Key（keySet=False），翻译类用例跳过"
  Stop-Process -Id $np.Id, $app.Id -Force -ErrorAction SilentlyContinue
  exit 3
}
$offset = (Get-Content $logFile).Count

$sh = New-Object -ComObject WScript.Shell
$midline = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width / 2

# ---- A. 划词交互链（1 次翻译）----
[void][C2Native]::SetCursorPos(300, 300)   # 锚点放左半屏 → 面板应在右半屏
Start-Sleep -Milliseconds 300
TriggerSelection
$win = Wait-Result 25
$okA = -not (IsZero $win)
Check 'A1 结果窗口出现' $okA
if ($okA) {
  Start-Sleep -Milliseconds 1000
  $r1 = Get-Rect $win
  Check 'A2 对侧半屏定位（右）' ($r1.Left -ge ($midline - 10))

  $uaWin = Get-UaWin
  $splitBtn = Wait-Desc $uaWin (ByName '拆分') 5000
  $wholeBtn = Wait-Desc $uaWin (ByName '整段') 5000
  $tpSplit = $splitBtn.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
  Check 'A3 默认拆分模式生效' ($tpSplit.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On)

  $tpWhole = $wholeBtn.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
  $tpWhole.Toggle()
  Start-Sleep -Milliseconds 700
  Check 'A4 整段切换（UIA Toggle）' ($tpSplit.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::Off)

  # A＋ 按钮（U+FF0B）
  $plusBtn = $null
  foreach ($b in $uaWin.FindAll([System.Windows.Automation.TreeScope]::Descendants, (ByType ([System.Windows.Automation.ControlType]::Button)))) {
    try { if ($b.Current.Name -eq ('A' + [char]0xFF0B)) { $plusBtn = $b } } catch {}
  }
  if ($plusBtn) { ($plusBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke() }
  Start-Sleep -Milliseconds 600
  Check 'A5 A＋ 持久化（14→15）' ((Get-Setting 'snaptranslate.popupFontSize') -eq 15)

  [System.Windows.Forms.SendKeys]::SendWait('`')
  Start-Sleep -Milliseconds 900
  $r2 = Get-Rect $win
  Check 'A6 ` 翻面到左半屏' ($r2.Left -lt ($midline - 10))

  [System.Windows.Forms.SendKeys]::SendWait('^d')
  Start-Sleep -Milliseconds 700
  Check 'A7 Ctrl+D 拆分切回' ($tpSplit.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On)

  SendEsc
  Start-Sleep -Milliseconds 900
  Check 'A8 ESC 关闭' (IsZero (Find-ResultWin $app.Id))
}
EnsureClean

# ---- B. 双触发竞态（任务代数）----
$offsetB = (Get-Content $logFile).Count
TriggerSelection
Start-Sleep -Milliseconds 600      # T2 在 T1 翻译期前启动 → T1 应被代数守卫丢弃
TriggerSelection
$staleOk = $false
$dl = (Get-Date).AddSeconds(25)
while ((Get-Date) -lt $dl -and -not $staleOk) {
  if ((Log-Since $offsetB) -match 'pipeline stale') { $staleOk = $true; break }
  Start-Sleep -Milliseconds 400
}
Start-Sleep -Milliseconds 2500     # 等 T2 完成出结果
$countB = 0
foreach ($w in [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
    [System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
  try { if ($w.Current.Name -eq $resultTitle -and $w.Current.ProcessId -eq $app.Id) { $countB++ } } catch {}
}
Check 'B1 陈旧任务被代数守卫丢弃' $staleOk
Check 'B2 竞态后仅 1 个结果窗口' ($countB -eq 1)
EnsureClean

# ---- C. 加载期 ESC 取消（不产生结果）----
$offsetC = (Get-Content $logFile).Count
TriggerSelection
Start-Sleep -Milliseconds 900
SendEsc
Start-Sleep -Seconds 3
$logC = Log-Since $offsetC
Check 'C1 取消流水线日志' ($logC -match 'panel key: cancel pipeline')
Check 'C2 网络请求已取消' ($logC -match 'translate cancelled')
Check 'C3 取消后无结果窗口' (IsZero (Find-ResultWin $app.Id))
EnsureClean

# ---- D. 窗口记忆 ----
TriggerSelection
$winD = Wait-Result 25
Check 'D0 结果窗口出现' (-not (IsZero $winD))
if (-not (IsZero $winD)) {
  Start-Sleep -Milliseconds 900
  $rd0 = Get-Rect $winD
  [void][C2Native]::SetWindowPos($winD, [IntPtr](-1), $rd0.Left, 120, $rd0.Right - $rd0.Left, 450, 0x0010)
  Start-Sleep -Milliseconds 600
  SendEsc
  [void](Wait-NoResult 5)
  TriggerSelection
  $winD2 = Wait-Result 25
  $dOk = $false
  if (-not (IsZero $winD2)) {
    Start-Sleep -Milliseconds 900
    $rd2 = Get-Rect $winD2
    $dOk = ([Math]::Abs($rd2.Top - 120) -le 2) -and ([Math]::Abs(($rd2.Bottom - $rd2.Top) - 450) -le 2)
  }
  Check 'D1 窗口位置/高度记忆' $dOk
}
EnsureClean

# ---- E. 截图拖拽链 ----
[void][C2Native]::SetWindowPos($np.MainWindowHandle, [IntPtr](-1), 80, 120, 500, 220, 0x0040)
[C2Native]::Activate($np.MainWindowHandle)
Start-Sleep -Milliseconds 500
$offsetE = (Get-Content $logFile).Count
[System.Windows.Forms.SendKeys]::SendWait('^t')
Start-Sleep -Milliseconds 1000
[void][C2Native]::SetCursorPos(100, 150)
Start-Sleep -Milliseconds 200
[C2Native]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 200
for ($i = 1; $i -le 8; $i++) {
  [void][C2Native]::SetCursorPos(100 + [int](460 * $i / 8), 150 + [int](150 * $i / 8))
  Start-Sleep -Milliseconds 80
}
[C2Native]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
# 等截图日志出现（避免读到上一段的状态）
$captured = $false
$dl = (Get-Date).AddSeconds(25)
while ((Get-Date) -lt $dl -and -not $captured) {
  if ((Log-Since $offsetE) -match 'screenshot captured') { $captured = $true; break }
  Start-Sleep -Milliseconds 400
}
$winE = Wait-Result 30
$logE = Log-Since $offsetE
Check 'E1 截图捕获+OCR' ($captured -and ($logE -match 'ocr status=Ok'))
Check 'E2 截图链结果窗口' (-not (IsZero $winE))
if (-not (IsZero $winE)) {
  Start-Sleep -Milliseconds 900
  $re = Get-Rect $winE
  Check 'E3 截图链对侧定位' ($re.Left -ge ($midline - 10))
}
EnsureClean

# ---- F. 副屏 150% 冒烟（无双屏则 SKIP）----
$screens = [System.Windows.Forms.Screen]::AllScreens
$sec = $screens | Where-Object { -not $_.Primary } | Select-Object -First 1
if ($null -eq $sec) {
  Skip 'F 副屏 150% 冒烟（无双屏）'
} else {
  [void][C2Native]::SetCursorPos($sec.Bounds.Left + 300, 300)
  Start-Sleep -Milliseconds 300
  TriggerSelection
  $winF = Wait-Result 25
  $fOk = $false
  if (-not (IsZero $winF)) {
    Start-Sleep -Milliseconds 900
    $rf = Get-Rect $winF
    $fOk = ($rf.Left -ge $sec.Bounds.Left) -and ($rf.Right -le $sec.Bounds.Right) -and
           ($rf.Top -ge $sec.Bounds.Top) -and ($rf.Bottom -le $sec.Bounds.Bottom)
  }
  Check 'F1 副屏上定位且不越界' $fOk
}
EnsureClean

# ---- G. A− 与边界禁用 ----
TriggerSelection
$winG = Wait-Result 25
Check 'G0 结果窗口出现' (-not (IsZero $winG))
if (-not (IsZero $winG)) {
  Start-Sleep -Milliseconds 900
  $uaWinG = Get-UaWin
  $minusBtn = $null
  foreach ($b in $uaWinG.FindAll([System.Windows.Automation.TreeScope]::Descendants, (ByType ([System.Windows.Automation.ControlType]::Button)))) {
    try { if ($b.Current.Name -eq ('A' + [char]0x2212)) { $minusBtn = $b } } catch {}
  }
  for ($i = 0; $i -lt 3; $i++) {
    ($minusBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
    Start-Sleep -Milliseconds 400
  }
  Check 'G1 A− 递减到 12' ((Get-Setting 'snaptranslate.popupFontSize') -eq 12)
  Check 'G2 到 12 后 A− 禁用' ($minusBtn.Current.IsEnabled -eq $false)
}
EnsureClean

# ---- 清理 ----
Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400
$sf = "$env:APPDATA\ELTA\settings.json"
try {
  $json = Get-Content $sf -Raw -Encoding UTF8 | ConvertFrom-Json
  $json.PSObject.Properties.Remove('snaptranslate.popupFontSize')
  $json | ConvertTo-Json -Depth 5 | Set-Content $sf -Encoding UTF8
} catch {}

Write-Host "---- test-c2: pass=$pass fail=$fail skip=$skip ----"
if ($fail -eq 0) { exit 0 } else { exit 1 }
