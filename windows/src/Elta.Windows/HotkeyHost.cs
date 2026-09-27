using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Elta.Windows
{
    /// <summary>
    /// 全局热键宿主（B1 测试用临时热键 Ctrl+T）。
    /// 托盘菜单只能在主屏点击（Windows 托盘只在主屏任务栏），无法在副屏触发截图；
    /// 全局热键让「鼠标停在任何屏」都能触发，<see cref="ScreenshotService"/> 再按
    /// 鼠标位置选取对应屏幕。正式热键默认值在 B4 统一。
    /// </summary>
    internal sealed class HotkeyHost : NativeWindow, IDisposable
    {
        private const int WM_HOTKEY = 0x0312;
        private const uint MOD_CONTROL = 0x0002;
        private const uint MOD_NOREPEAT = 0x4000;
        private const int HOTKEY_ID = 0x4A17;
        private const uint VK_T = 0x54;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        private bool _registered;

        /// <summary>热键是否注册成功（被其他程序占用时为 false，托盘菜单仍可用）。</summary>
        public bool Registered => _registered;

        public event Action? Triggered;

        public HotkeyHost()
        {
            var cp = new CreateParams { Caption = "EltaHotkeyHost", Parent = IntPtr.Zero };
            CreateHandle(cp);
            _registered = RegisterHotKey(Handle, HOTKEY_ID, MOD_CONTROL | MOD_NOREPEAT, VK_T);
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == HOTKEY_ID)
            {
                Triggered?.Invoke();
                return;
            }
            base.WndProc(ref m);
        }

        public void Dispose()
        {
            if (_registered)
            {
                UnregisterHotKey(Handle, HOTKEY_ID);
                _registered = false;
            }
            DestroyHandle();
        }
    }
}
