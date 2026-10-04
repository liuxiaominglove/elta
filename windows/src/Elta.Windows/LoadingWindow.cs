using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using WinForms = System.Windows.Forms;

namespace Elta.Windows
{
    /// <summary>
    /// C2：翻译加载窗（300×140，靠鼠标定位，非激活悬浮）。ESC 取消由 <see cref="PanelKeyRouter"/> 路由。
    /// </summary>
    public sealed class LoadingWindow : Window
    {
        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

        private static readonly IntPtr HWND_TOPMOST = new(-1);
        private const uint SWP_NOACTIVATE = 0x0010;

        public LoadingWindow(string title, string subtitle)
        {
            Title = "ELTA";
            Width = 300;
            Height = 140;
            WindowStyle = WindowStyle.ToolWindow;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false;
            ShowActivated = false;
            Topmost = true;
            WindowStartupLocation = WindowStartupLocation.Manual;

            var root = new Grid { Margin = new Thickness(16) };
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var bar = new ProgressBar
            {
                IsIndeterminate = true,
                Height = 6,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(40, 8, 40, 8),
            };
            Grid.SetRow(bar, 0);
            root.Children.Add(bar);

            var titleText = new TextBlock
            {
                Text = title,
                FontSize = 13,
                HorizontalAlignment = HorizontalAlignment.Center,
            };
            Grid.SetRow(titleText, 1);
            root.Children.Add(titleText);

            var subText = new TextBlock
            {
                Text = subtitle,
                FontSize = 11,
                Foreground = Brushes.Gray,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 4, 0, 0),
            };
            Grid.SetRow(subText, 2);
            root.Children.Add(subText);

            Content = root;
            SourceInitialized += (_, _) => PositionNearMouse();
        }

        private void PositionNearMouse()
        {
            IntPtr hwnd = new WindowInteropHelper(this).Handle;
            if (hwnd == IntPtr.Zero) return;

            System.Drawing.Point cursor = WinForms.Cursor.Position;   // 物理像素
            WinForms.Screen screen = WinForms.Screen.FromPoint(cursor);
            System.Drawing.Rectangle wa = screen.WorkingArea;

            DpiScale dpi = VisualTreeHelper.GetDpi(this);
            int w = (int)Math.Round(Width * dpi.DpiScaleX);
            int h = (int)Math.Round(Height * dpi.DpiScaleY);

            int x = Math.Clamp(cursor.X + 16, wa.Left, Math.Max(wa.Left, wa.Right - w));
            int y = Math.Clamp(cursor.Y + 16, wa.Top, Math.Max(wa.Top, wa.Bottom - h));

            SetWindowPos(hwnd, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE);
        }
    }
}
