using System;
using System.Drawing;
using System.Windows;
using Forms = System.Windows.Forms;

namespace Elta.Windows
{
    /// <summary>
    /// ELTA Windows 外壳入口（C0）：托盘常驻程序骨架。
    /// 目前只提供托盘图标与退出菜单，尚无翻译功能；B1–B4 在此基础上接入
    /// 截图 / 取词 / 热键 / OCR 平台服务。
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
            tray.ShowBalloonTip(2500, "ELTA", "托盘程序已启动（C0 骨架）", Forms.ToolTipIcon.Info);

            app.Exit += (_, _) =>
            {
                tray.Visible = false;
                tray.Dispose();
                menu.Dispose();
            };

            app.Run();
        }
    }
}
