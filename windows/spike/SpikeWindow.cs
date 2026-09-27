using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage;
using WinForms = System.Windows.Forms;

namespace EltaSpike
{
    /// <summary>
    /// ELTA Windows P0.5 能力验证工具。
    /// 目的：在投入正式开发前，把 4 个高风险平台能力（OCR / 截图-DPI / UIA 取词 / 全局热键与钩子）
    /// 在 Windows 真机上打成"已验证"或"暴露问题"。所有结果写 spike.log 并显示在窗口内。
    /// </summary>
    public class SpikeWindow : Window
    {
        // ---------- P/Invoke ----------
        private delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromPoint(POINT pt, uint dwFlags);

        [DllImport("shcore.dll")]
        private static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetModuleHandle(string? lpModuleName);

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int X; public int Y; }

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

        private const uint MOD_CONTROL = 0x0002;
        private const int HOTKEY_ID = 0x4A17;
        private const int WM_HOTKEY = 0x0312;
        private const int WH_KEYBOARD_LL = 13;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const uint MONITOR_DEFAULTTONEAREST = 2;
        private const byte VK_CONTROL = 0x11;
        private const byte VK_C = 0x43;
        private const uint KEYEVENTF_KEYUP = 0x0002;

        // ---------- 状态 ----------
        private static readonly string LogPath = Path.Combine(AppContext.BaseDirectory, "spike.log");
        private readonly TextBox _log;
        private readonly StackPanel _panel;

        private IntPtr _hwnd = IntPtr.Zero;
        private HookProc? _hook;          // 必须用字段持有，否则被 GC 回收 → 崩溃
        private IntPtr _hookHandle = IntPtr.Zero;
        private int _hookOwn;
        private int _hookOther;
        private int _previewCount;        // 本窗口 PreviewKeyDown 对照计数
        private DateTime _hookStart;
        private DispatcherTimer? _hookTimer;

        [STAThread]
        public static void Main()
        {
            var app = new System.Windows.Application();
            app.Run(new SpikeWindow());
        }

        public SpikeWindow()
        {
            Title = "ELTA Windows P0.5 Spike";
            Width = 860;
            Height = 680;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;

            _log = new TextBox
            {
                IsReadOnly = true,
                AcceptsReturn = true,
                TextWrapping = TextWrapping.NoWrap,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                FontFamily = new System.Windows.Media.FontFamily("Consolas"),
                FontSize = 12,
                MinHeight = 380,
                Margin = new Thickness(0, 6, 0, 0)
            };
            _panel = new StackPanel { Margin = new Thickness(8) };

            var buttons = new (string Label, Action Run)[]
            {
                ("1. OCR 语言清单", TestOcrLanguages),
                ("2. OCR 识别图片…", () => _ = TestOcrImageAsync()),
                ("3. 截图 + DPI 标记校验", () => _ = TestCaptureAsync()),
                ("4. UIA 读选中文本（窗口会自动最小化 4 秒）", () => _ = TestUiaAsync()),
                ("5. Ctrl+C 兜底 + 剪贴板恢复（3 秒后）", () => _ = TestCopyFallbackAsync()),
                ("6. 注册全局热键 Ctrl+T", TestRegisterHotkey),
                ("7. 低层键盘钩子监听 15 秒", TestLowLevelHook),
                ("8. 打开语言/OCR 设置", OpenLanguageSettings),
            };

            foreach (var (label, run) in buttons)
            {
                var b = new Button
                {
                    Content = label,
                    Margin = new Thickness(0, 2, 0, 2),
                    Padding = new Thickness(10, 5, 10, 5),
                    HorizontalAlignment = HorizontalAlignment.Left
                };
                b.Click += (_, __) =>
                {
                    Log("──────── " + label + " ────────");
                    try { run(); }
                    catch (Exception ex) { Log("EXCEPTION: " + ex); }
                };
                _panel.Children.Add(b);
            }

            _panel.Children.Add(_log);
            Content = new ScrollViewer { Content = _panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };

            SourceInitialized += (_, __) =>
            {
                _hwnd = new WindowInteropHelper(this).Handle;
                HwndSource.FromHwnd(_hwnd)?.AddHook(WndProc);
            };
        }

        private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_HOTKEY)
            {
                Log($"收到 WM_HOTKEY id={wParam}（注册式热键工作正常）");
                handled = true;
            }
            return IntPtr.Zero;
        }

        // ===================== 1. OCR 语言 =====================
        private void TestOcrLanguages()
        {
            Log($"OcrEngine.MaxImageDimension = {OcrEngine.MaxImageDimension}（超过需先缩放）");
            var langs = OcrEngine.AvailableRecognizerLanguages;
            Log($"可用 OCR 语言数 = {langs.Count}");
            foreach (var l in langs)
                Log($"  - {l.LanguageTag} / {l.DisplayName}");

            bool hasEn = langs.Any(l => l.LanguageTag.StartsWith("en", StringComparison.OrdinalIgnoreCase));
            bool hasZh = langs.Any(l => l.LanguageTag.StartsWith("zh", StringComparison.OrdinalIgnoreCase));
            OcrEngine? enEngine = null;
            try { enEngine = OcrEngine.TryCreateFromLanguage(new Language("en-US")); } catch { }
            Log($"判定：英文包={hasEn}  中文包={hasZh}  可创建 en-US 引擎={enEngine != null}");
            if (!hasEn)
                Log("⚠️ 缺少英文 OCR 包 → ELTA 主场景是英文，需引导安装英文包 + 自带兜底 OCR（A+B 方案）");
            if (!hasZh)
                Log("ℹ️ 缺少中文 OCR 包（ELTA 译文不需要 OCR，影响不大）");
        }

        private void OpenLanguageSettings()
        {
            try
            {
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("ms-settings:regionlanguage")
                {
                    UseShellExecute = true
                });
                Log("已尝试打开 Windows「语言和区域」设置。安装英文 OCR：添加 English (United States) → 语言选项 → 可选功能里勾选「光学字符识别 (OCR)」");
            }
            catch (Exception ex)
            {
                Log("打开设置失败: " + ex.Message);
            }
        }

        // ===================== 2. OCR 识别 + 边界框 =====================
        private async Task TestOcrImageAsync()
        {
            var dlg = new WinForms.OpenFileDialog
            {
                Title = "选择要 OCR 的图片（建议用 samples 下的英文样例）",
                Filter = "图片|*.png;*.jpg;*.jpeg;*.bmp|所有文件|*.*"
            };
            if (dlg.ShowDialog() != WinForms.DialogResult.OK) { Log("已取消"); return; }

            try
            {
                StorageFile file = await StorageFile.GetFileFromPathAsync(Path.GetFullPath(dlg.FileName));
                using var stream = await file.OpenAsync(FileAccessMode.Read);
                var decoder = await BitmapDecoder.CreateAsync(stream);
                using SoftwareBitmap sb0 = await decoder.GetSoftwareBitmapAsync();

                SoftwareBitmap sb = sb0;
                if (sb.BitmapPixelFormat != BitmapPixelFormat.Bgra8 ||
                    sb.BitmapAlphaMode == BitmapAlphaMode.Straight)
                {
                    sb = SoftwareBitmap.Convert(sb0, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
                    Log("已将位图转换为 Bgra8/Premultiplied");
                }

                if (Math.Max(sb.PixelWidth, sb.PixelHeight) > OcrEngine.MaxImageDimension)
                    Log($"⚠️ 图片 {sb.PixelWidth}x{sb.PixelHeight} 超过 MaxImageDimension，正式实现需先等比缩小");

                // 优先英文引擎（ELTA 源文本是英文），再退回系统用户语言
                OcrEngine? engine = OcrEngine.TryCreateFromLanguage(new Language("en-US"))
                                    ?? OcrEngine.TryCreateFromUserProfileLanguages();
                if (engine is null) { Log("❌ 无法创建 OCR 引擎（无可用语言包）"); return; }
                Log($"使用 OCR 引擎语言 = {engine.RecognizerLanguage.LanguageTag}");

                OcrResult result = await engine.RecognizeAsync(sb);
                int wordCount = result.Lines.Sum(l => l.Words.Count);
                Log($"图像 {sb.PixelWidth}x{sb.PixelHeight}px，行数={result.Lines.Count}，词数={wordCount}");
                Log("---- 识别文本 ----");
                Log(result.Text);
                Log("---- 边界框抽样（决定 TableExtractor 能否移植）----");
                int shown = 0;
                foreach (var line in result.Lines)
                {
                    if (shown++ >= 3) break;
                    var w = line.Words.FirstOrDefault();
                    if (w != null)
                        Log($"  word='{w.Text}' rect=({w.BoundingRect.X:0},{w.BoundingRect.Y:0},{w.BoundingRect.Width:0},{w.BoundingRect.Height:0})");
                }
                Log(wordCount > 0
                    ? "✅ 可获取行/词级边界框 → 表格还原逻辑可移植"
                    : "❌ 未获得词级边界框 → TableExtractor 需重定方案");
            }
            catch (Exception ex)
            {
                Log("OCR 失败: " + ex);
            }
        }

        // ===================== 3. 截图 + DPI（独立物理标记窗口）=====================
        private async Task TestCaptureAsync()
        {
            var dpi = VisualTreeHelper.GetDpi(this);
            Log($"WPF DpiScale = {dpi.DpiScaleX:0.00} x {dpi.DpiScaleY:0.00}");
            Log($"VirtualScreen(px) = {WinForms.SystemInformation.VirtualScreen}");
            foreach (var s in WinForms.Screen.AllScreens)
            {
                uint mx = GetMonitorDpiForBounds(s.Bounds, out uint my);
                Log($"屏幕 {s.DeviceName} primary={s.Primary} bounds(px)={s.Bounds} dpi={mx}x{my}");
            }

            var primary = WinForms.Screen.PrimaryScreen;
            if (primary is null) { Log("无主屏"); return; }
            Rectangle b = primary.Bounds;

            // 独立红色标记窗口（WinForms，物理像素定位，避免 WPF DIP 干扰）
            var marker = new WinForms.Form
            {
                FormBorderStyle = WinForms.FormBorderStyle.None,
                StartPosition = WinForms.FormStartPosition.Manual,
                Location = new System.Drawing.Point(300, 300),
                Size = new System.Drawing.Size(60, 60),
                BackColor = System.Drawing.Color.Red,
                TopMost = true,
                ShowInTaskbar = false
            };
            marker.Show();
            await Task.Delay(250);

            IntPtr mh = marker.Handle;
            GetWindowRect(mh, out RECT r);
            int cx = (r.Left + r.Right) / 2;
            int cy = (r.Top + r.Bottom) / 2;
            Log($"标记窗口实际物理矩形 = ({r.Left},{r.Top})-({r.Right},{r.Bottom})，中心=({cx},{cy})");

            using var bmp = new Bitmap(b.Width, b.Height);
            using (var g = Graphics.FromImage(bmp))
                g.CopyFromScreen(b.Left, b.Top, 0, 0, b.Size);

            string outPath = Path.Combine(AppContext.BaseDirectory, "capture.png");
            bmp.Save(outPath, ImageFormat.Png);
            Log($"已截图主屏 → {outPath}（{bmp.Width}x{bmp.Height}px）");

            int sx = cx - b.Left;
            int sy = cy - b.Top;
            if (sx >= 0 && sy >= 0 && sx < bmp.Width && sy < bmp.Height)
            {
                System.Drawing.Color c = bmp.GetPixel(sx, sy);
                bool red = c.R > 150 && c.G < 110 && c.B < 110;
                Log($"物理像素采样=({sx},{sy}) 颜色=#{c.R:X2}{c.G:X2}{c.B:X2} 命中红色={red}");
                Log(red
                    ? "✅ 物理坐标↔截图像素一致（当前缩放下）"
                    : "❌ 坐标错位 → 截图方案（GDI/WGC）需调整");
            }
            else
            {
                Log($"⚠️ 采样点越界：({sx},{sy}) 不在 {bmp.Width}x{bmp.Height} 内，检查坐标换算");
            }

            marker.Close();
        }

        private static uint GetMonitorDpiForBounds(Rectangle bounds, out uint dpiY)
        {
            var pt = new POINT { X = bounds.Left + bounds.Width / 2, Y = bounds.Top + bounds.Height / 2 };
            IntPtr mon = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
            if (GetDpiForMonitor(mon, 0, out uint x, out uint y) == 0)
            {
                dpiY = y;
                return x;
            }
            dpiY = 0;
            return 0;
        }

        // ===================== 4. UIA 读选中文本（自动最小化）=====================
        private async Task TestUiaAsync()
        {
            Log("本窗口将最小化 4 秒。请立刻切到目标程序并选中一段文字……");
            WindowState = WindowState.Minimized;
            await Task.Delay(4000);

            AutomationElement? el = AutomationElement.FocusedElement;
            if (el is null)
            {
                Log("❌ FocusedElement = null");
            }
            else
            {
                string name = Safe(() => el.Current.Name);
                string cls = Safe(() => el.Current.ClassName);
                int pid = 0;
                try { pid = el.Current.ProcessId; } catch { }
                Log($"焦点元素：name='{name}' class='{cls}' pid={pid}");

                string? text = ReadSelection(el);
                if (text is null)
                    Log("❌ UIA 未取到选中文本（该程序可能不暴露 TextPattern）");
                else
                    Log($"✅ UIA 取到 {text.Length} 字符：{Trunc(text)}");
            }

            WindowState = WindowState.Normal;
            Activate();
        }

        /// <summary>沿 UIA 父链向上最多 10 层查找 TextPattern（对应 Mac 版 AX 父链遍历）。</summary>
        private static string? ReadSelection(AutomationElement? el)
        {
            for (int depth = 0; depth < 10 && el != null; depth++)
            {
                if (el.TryGetCurrentPattern(TextPattern.Pattern, out object po))
                {
                    var tp = (TextPattern)po;
                    TextPatternRange[] ranges = tp.GetSelection();
                    if (ranges.Length > 0)
                    {
                        string t = ranges[0].GetText(-1);
                        if (!string.IsNullOrEmpty(t))
                            return t;
                    }
                }
                try { el = TreeWalker.ControlViewWalker.GetParent(el); }
                catch { return null; }
            }
            return null;
        }

        // ===================== 5. Ctrl+C 兜底 + 剪贴板恢复 =====================
        private async Task TestCopyFallbackAsync()
        {
            Log("3 秒内：选中一段文本（任意程序）……");
            await Task.Delay(3000);

            ClipSnap snap;
            try { snap = ClipSnap.Capture(); Log($"剪贴板快照：{snap.Count} 个格式"); }
            catch (Exception ex) { Log("剪贴板快照失败: " + ex.Message); snap = new ClipSnap(); }

            SendCtrlC();
            await Task.Delay(200);

            string? text = null;
            try
            {
                if (WinForms.Clipboard.ContainsText())
                    text = WinForms.Clipboard.GetText();
            }
            catch (Exception ex) { Log("读取剪贴板失败: " + ex.Message); }

            Log(text is null
                ? "❌ Ctrl+C 未取到文本"
                : $"✅ Ctrl+C 取到 {text.Length} 字符：{Trunc(text)}");

            try
            {
                snap.Restore();
                Log("剪贴板已恢复（请手动确认原富文本/图片仍在）");
            }
            catch (Exception ex) { Log("❌ 剪贴板恢复失败: " + ex.Message); }
        }

        private static void SendCtrlC()
        {
            keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
            keybd_event(VK_C, 0, 0, UIntPtr.Zero);
            keybd_event(VK_C, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        }

        // ===================== 6. 注册式全局热键 =====================
        private void TestRegisterHotkey()
        {
            if (_hwnd == IntPtr.Zero) { Log("窗口句柄未就绪"); return; }
            bool ok = RegisterHotKey(_hwnd, HOTKEY_ID, MOD_CONTROL, 0x54); // 0x54 = 'T'
            if (ok)
                Log("✅ Ctrl+T 注册成功。现在按 Ctrl+T，若下面出现「收到 WM_HOTKEY」即为工作正常");
            else
                Log($"❌ Ctrl+T 注册失败 err={Marshal.GetLastWin32Error()}（多为被其他程序占用）");
        }

        // ===================== 7. 低层键盘钩子（带本窗口对照）=====================
        private void TestLowLevelHook()
        {
            if (_hookHandle != IntPtr.Zero) { Log("钩子已在运行"); return; }

            _hookOwn = 0;
            _hookOther = 0;
            _previewCount = 0;
            _hookStart = DateTime.Now;
            IntPtr self = _hwnd;

            _hook = (nCode, wParam, lParam) =>
            {
                // 回调内只做极轻量工作；不写文件、不更新 UI，避免超过 LowLevelHooksTimeout 被系统摘除
                if (nCode >= 0 && (wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN))
                {
                    if (GetForegroundWindow() == self) _hookOwn++;
                    else _hookOther++;
                }
                return CallNextHookEx(_hookHandle, nCode, wParam, lParam);
            };

            _hookHandle = SetWindowsHookEx(WH_KEYBOARD_LL, _hook!, GetModuleHandle(null), 0);
            if (_hookHandle == IntPtr.Zero)
            {
                Log($"❌ 钩子安装失败 err={Marshal.GetLastWin32Error()}");
                _hook = null;
                return;
            }

            PreviewKeyDown += OnTestPreviewKeyDown;
            Log("✅ 钩子已安装。请立刻：①切到【别的程序】按几次字母键；②再切回【本窗口】按几次键。监听 15 秒…");

            _hookTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(15) };
            _hookTimer.Tick += (_, __) =>
            {
                _hookTimer!.Stop();
                PreviewKeyDown -= OnTestPreviewKeyDown;
                UnhookWindowsHookEx(_hookHandle);
                _hookHandle = IntPtr.Zero;
                _hook = null;
                double sec = (DateTime.Now - _hookStart).TotalSeconds;
                Log($"钩子结果：他程序={_hookOther}，本窗口(钩子)={_hookOwn}，本窗口(PreviewKeyDown对照)={_previewCount}，用时={sec:0.0}s");
                if (_hookOther > 0)
                    Log("✅ 他程序聚焦时能收到 LL 事件（裸 ESC/` 拦截可行）");
                else if (_previewCount > 0)
                    Log("⚠️ 他程序没收到、但本窗口有键 → 很可能没切到别的程序或没按时按，请重跑");
                else
                    Log("❌ 全程未捕获任何按键 → 很可能没按，或被杀软/UIPI 拦截");
            };
            _hookTimer.Start();
        }

        private void OnTestPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e) => _previewCount++;

        // ===================== 日志 =====================
        // 所有测试逻辑均在 UI 线程执行；低层钩子回调刻意不调用本方法（见 TestLowLevelHook 注释）。
        private void Log(string message)
        {
            string line = $"[{DateTime.Now:HH:mm:ss.fff}] {message}";
            try { File.AppendAllText(LogPath, line + Environment.NewLine, Encoding.UTF8); } catch { }
            Console.WriteLine(line);
            if (Dispatcher.CheckAccess())
                _log.AppendText(line + Environment.NewLine);
            else
                Dispatcher.BeginInvoke(new Action(() => _log.AppendText(line + Environment.NewLine)));
        }

        private static string Trunc(string s) => s.Length <= 120 ? s : s.Substring(0, 120) + "…";
        private static string Safe(Func<string> f) { try { return f(); } catch { return "<err>"; } }

        // ===================== 剪贴板深拷贝快照 =====================
        private sealed class ClipSnap
        {
            private readonly List<(string Format, object? Data)> _items = new();
            public int Count => _items.Count;

            public static ClipSnap Capture()
            {
                var snap = new ClipSnap();
                var data = WinForms.Clipboard.GetDataObject();
                if (data is null) return snap;
                foreach (string fmt in data.GetFormats())
                {
                    try
                    {
                        object? v = data.GetData(fmt, true);
                        // 深拷贝流，避免持有 COM 懒引用（对应 Mac 版 PasteboardSnapshot 的教训）
                        if (v is Stream st && st.CanSeek)
                        {
                            st.Position = 0;
                            var ms = new MemoryStream();
                            st.CopyTo(ms);
                            ms.Position = 0;
                            v = ms;
                        }
                        snap._items.Add((fmt, v));
                    }
                    catch { /* 个别格式不可克隆，跳过 */ }
                }
                return snap;
            }

            public void Restore()
            {
                if (_items.Count == 0) { WinForms.Clipboard.Clear(); return; }
                var d = new WinForms.DataObject();
                foreach (var (fmt, val) in _items)
                {
                    if (val is null) continue;
                    try { d.SetData(fmt, val); } catch { }
                }
                WinForms.Clipboard.SetDataObject(d, true);
            }
        }
    }
}
