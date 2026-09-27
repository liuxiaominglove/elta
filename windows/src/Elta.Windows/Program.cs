using System;
using System.Drawing;
using System.Windows;
using Forms = System.Windows.Forms;

namespace Elta.Windows
{
    /// <summary>
    /// ELTA Windows 外壳入口：托盘常驻程序。
    /// C0：托盘图标 + 退出菜单；B1：截图选区（菜单项，验证 GDI 截图 + 几何裁剪）。
    /// 后续 B2–B4 接入取词 / OCR / 热键。
    /// </summary>
    public static class Program
    {
        [STAThread]
        public static void Main()
        {
            var app = new System.Windows.Application
            {
                ShutdownMode = ShutdownMode.OnExplicitShutdown,
            };

            var menu = new Forms.ContextMenuStrip();

            var shotItem = new Forms.ToolStripMenuItem("截图选区（B1 测试）");
            shotItem.Click += (_, _) => RunScreenshot();
            menu.Items.Add(shotItem);
            menu.Items.Add(new Forms.ToolStripSeparator());

            var exitItem = new Forms.ToolStripMenuItem("退出 ELTA");
            exitItem.Click += (_, _) => app.Shutdown();
            menu.Items.Add(exitItem);

            var tray = new Forms.NotifyIcon
            {
                Icon = SystemIcons.Application,
                Text = "ELTA — 截图即译，精读利器",
                Visible = true,
                ContextMenuStrip = menu,
            };
            tray.ShowBalloonTip(2500, "ELTA", "托盘程序已启动（C0/B1 骨架）", Forms.ToolTipIcon.Info);

            app.Exit += (_, _) =>
            {
                tray.Visible = false;
                tray.Dispose();
                menu.Dispose();
            };

            app.Run();
        }

        private static void RunScreenshot()
        {
            Bitmap? cropped = ScreenshotService.CaptureSelection();
            if (cropped == null) return;   // 取消或选区无效

            using var preview = new PreviewForm(cropped);
            preview.ShowDialog();
        }
    }
}
