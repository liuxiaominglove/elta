using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Windows.Media;
using Elta.Core;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using WinForms = System.Windows.Forms;

namespace Elta.Windows
{
    /// <summary>
    /// C2：翻译结果窗口。对齐 mac ResultWindowController：
    /// 工具栏（整段/拆分 + A−/A＋）+ WebView2；对侧半屏定位；移动/缩放记忆；非激活悬浮。
    /// ESC / ` / Ctrl+D 由 <see cref="PanelKeyRouter"/> 路由到 ClosePanel / TogglePosition / ToggleSplit。
    /// </summary>
    public sealed class ResultWindow : Window
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

        private static readonly IntPtr HWND_TOPMOST = new(-1);
        private const uint SWP_NOACTIVATE = 0x0010;

        private readonly SettingsManager _settings;
        private readonly string _markdown;
        private readonly string _originalText;
        private readonly Rectangle _avoidRect;   // 物理像素
        private readonly bool _isDark;
        private readonly bool _canSplit;

        private readonly WebView2 _view = new();
        private readonly ToggleButton _segWhole = new();
        private readonly ToggleButton _segSplit = new();
        private readonly Button _fontMinus = new();
        private readonly Button _fontPlus = new();

        private bool _isSplit;
        private bool _positioned;
        private bool _webViewReady;

        public ResultWindow(SettingsManager settings, string markdown, string originalText, Rectangle avoidRect)
        {
            _settings = settings;
            _markdown = markdown;
            _originalText = originalText;
            _avoidRect = avoidRect;
            _isDark = ThemeHelper.IsDark();
            _canSplit = HtmlRenderer.CanSplit(markdown, originalText);
            _isSplit = HtmlRenderer.ShouldStartSplit(settings.DefaultSplitMode, _canSplit);

            Title = "翻译结果 — ELTA";
            MinWidth = 420;
            MinHeight = ResultPanelGeometry.MinPanelHeight;
            Width = 620;
            Height = 700;
            WindowStartupLocation = WindowStartupLocation.Manual;
            ShowActivated = false;   // 非激活悬浮（对齐 mac nonactivatingPanel）
            Topmost = true;
            Content = BuildLayout();

            SourceInitialized += (_, _) =>
            {
                PositionPanel();
                _positioned = true;
            };
            Loaded += async (_, _) => await InitWebViewAsync();
            // 在 Closing（销毁前）保存：Closed 时 HWND 已销毁，GetWindowRect 会失败
            Closing += (_, _) => SaveFrame();
        }

        // MARK: - 布局

        private UIElement BuildLayout()
        {
            var dock = new DockPanel { LastChildFill = true };

            var toolbar = new Grid { Height = 36, Margin = new Thickness(8, 0, 8, 0) };
            toolbar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            toolbar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var left = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            _segWhole.Content = "整段";
            _segWhole.Padding = new Thickness(14, 3, 14, 3);
            // 用 Checked 而非 Click：既覆盖真实鼠标点击，也覆盖 UIA TogglePattern（无障碍路径）
            _segWhole.Checked += (_, _) => SetSplit(false);
            _segSplit.Content = "拆分";
            _segSplit.Padding = new Thickness(14, 3, 14, 3);
            _segSplit.Margin = new Thickness(6, 0, 0, 0);
            _segSplit.Checked += (_, _) => SetSplit(true);
            left.Children.Add(_segWhole);
            left.Children.Add(_segSplit);
            Grid.SetColumn(left, 0);
            toolbar.Children.Add(left);

            var right = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Center,
            };
            _fontMinus.Content = "A−";
            _fontMinus.Padding = new Thickness(10, 3, 10, 3);
            _fontMinus.Click += (_, _) => ChangeFontSize(-1);
            _fontPlus.Content = "A＋";
            _fontPlus.Padding = new Thickness(10, 3, 10, 3);
            _fontPlus.Margin = new Thickness(6, 0, 0, 0);
            _fontPlus.Click += (_, _) => ChangeFontSize(+1);
            right.Children.Add(_fontMinus);
            right.Children.Add(_fontPlus);
            Grid.SetColumn(right, 1);
            toolbar.Children.Add(right);

            DockPanel.SetDock(toolbar, Dock.Top);
            dock.Children.Add(toolbar);
            dock.Children.Add(_view);

            UpdateSplitButtons();
            UpdateFontButtons();
            return dock;
        }

        private void UpdateSplitButtons()
        {
            _segWhole.IsChecked = !_isSplit;
            _segSplit.IsChecked = _isSplit;
            _segSplit.IsEnabled = _canSplit;
        }

        private void UpdateFontButtons()
        {
            SettingsDefaults d = _settings.Defaults;
            int size = _settings.PopupFontSize;
            _fontMinus.IsEnabled = size > d.PopupFontSizeMin;
            _fontPlus.IsEnabled = size < d.PopupFontSizeMax;
        }

        // MARK: - 渲染

        private string CurrentHtml()
        {
            string provider = AIProviders.ShortName(_settings.ApiProvider);
            int size = _settings.PopupFontSize;
            return _isSplit
                ? HtmlRenderer.RenderSplit(_markdown, _originalText, _isDark, size, provider)
                : HtmlRenderer.Render(_markdown, _originalText, _isDark, size, provider);
        }

        private void Rerender()
        {
            if (!_webViewReady) return;
            _view.NavigateToString(CurrentHtml());
        }

        private async Task InitWebViewAsync()
        {
            try
            {
                string userDataFolder = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "ELTA", "WebView2");
                CoreWebView2Environment env = await CoreWebView2Environment.CreateAsync(null, userDataFolder);
                await _view.EnsureCoreWebView2Async(env);
                _view.CoreWebView2.Settings.IsScriptEnabled = false;   // 对齐 mac allowsContentJavaScript = false

                _webViewReady = true;
                _view.NavigateToString(CurrentHtml());
                Log.Info($"result window shown split={_isSplit} canSplit={_canSplit} " +
                         $"fontSize={_settings.PopupFontSize} dark={_isDark}");
            }
            catch (Exception ex)
            {
                Log.Error("result window init failed", ex);
                MessageBox.Show(
                    $"结果窗口初始化失败：\n{ex.Message}",
                    "ELTA", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        // MARK: - 交互（PanelKeyRouter / 按钮共用）

        public void ClosePanel() => Close();

        private void SetSplit(bool split)
        {
            if (split && !_canSplit)
            {
                UpdateSplitButtons();
                return;
            }
            if (_isSplit == split)
            {
                UpdateSplitButtons();
                return;
            }
            _isSplit = split;
            UpdateSplitButtons();
            Rerender();
        }

        /// <summary>Ctrl+D / 拆分按钮共用；内容不可拆分时忽略。</summary>
        public void ToggleSplit() => SetSplit(!_isSplit);

        private void ChangeFontSize(int delta)
        {
            SettingsDefaults d = _settings.Defaults;
            int target = Math.Clamp(_settings.PopupFontSize + delta, d.PopupFontSizeMin, d.PopupFontSizeMax);
            if (target == _settings.PopupFontSize) return;
            _settings.PopupFontSize = target;
            UpdateFontButtons();
            Rerender();
        }

        /// <summary>` 键：翻到另一侧半屏。</summary>
        public void TogglePosition()
        {
            IntPtr hwnd = new WindowInteropHelper(this).Handle;
            if (hwnd == IntPtr.Zero) return;
            if (!GetWindowRect(hwnd, out RECT r)) return;

            WinForms.Screen screen = WinForms.Screen.FromRectangle(_avoidRect) ?? WinForms.Screen.PrimaryScreen!;
            RectF screenRect = ToRectF(screen.WorkingArea);
            bool currentlyRight = (r.Left + r.Right) / 2.0 >= screenRect.MidX;

            RectF target = ResultPanelGeometry.ComputeForSide(
                screenRect, panelOnRight: !currentlyRight,
                savedHeight: r.Bottom - r.Top, savedY: r.Top);
            ApplyPhysicalFrame(target);
        }

        // MARK: - 定位与记忆

        private void PositionPanel()
        {
            IntPtr hwnd = new WindowInteropHelper(this).Handle;
            if (hwnd == IntPtr.Zero) return;

            WinForms.Screen screen = WinForms.Screen.FromRectangle(_avoidRect) ?? WinForms.Screen.PrimaryScreen!;
            RectF screenRect = ToRectF(screen.WorkingArea);
            RectF avoidRect = ToRectF(_avoidRect);

            double? savedHeight = null;
            double? savedY = null;
            if (_settings.WindowFrame is WindowFrame saved)
            {
                savedHeight = saved.Height;
                savedY = saved.Y;
            }

            RectF target = ResultPanelGeometry.Compute(screenRect, avoidRect, savedHeight, savedY);
            ApplyPhysicalFrame(target);
        }

        private void ApplyPhysicalFrame(RectF rect)
        {
            IntPtr hwnd = new WindowInteropHelper(this).Handle;
            if (hwnd == IntPtr.Zero) return;
            SetWindowPos(hwnd, HWND_TOPMOST,
                (int)Math.Round(rect.X), (int)Math.Round(rect.Y),
                (int)Math.Round(rect.Width), (int)Math.Round(rect.Height),
                SWP_NOACTIVATE);
        }

        private void SaveFrame()
        {
            if (!_positioned) return;
            IntPtr hwnd = new WindowInteropHelper(this).Handle;
            if (hwnd == IntPtr.Zero) return;
            if (!GetWindowRect(hwnd, out RECT r)) return;
            _settings.WindowFrame = new WindowFrame(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
        }

        private static RectF ToRectF(Rectangle r) => new(r.X, r.Y, r.Width, r.Height);
    }

    /// <summary>系统深浅色（读注册表，平台方言留在外壳）。</summary>
    internal static class ThemeHelper
    {
        public static bool IsDark()
        {
            try
            {
                using Microsoft.Win32.RegistryKey? key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
                return key?.GetValue("AppsUseLightTheme") is int v && v == 0;
            }
            catch
            {
                return false;
            }
        }
    }
}
