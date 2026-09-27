using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Elta.Windows
{
    /// <summary>
    /// 全局热键宿主（可注册多个）。托盘图标只在主屏任务栏，副屏/任意前台程序下都靠全局热键触发。
    /// 用 <see cref="NativeWindow"/> 承载 WM_HOTKEY。B4 会用 SettingsManager 的默认值统一管理。
    /// </summary>
    internal sealed class HotkeyHost : NativeWindow, IDisposable
    {
        private const int WM_HOTKEY = 0x0312;
        private const uint MOD_NOREPEAT = 0x4000;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        private readonly Dictionary<int, Action> _handlers = new();
        private readonly List<int> _registered = new();

        public HotkeyHost()
        {
            var cp = new CreateParams { Caption = "EltaHotkeyHost", Parent = IntPtr.Zero };
            CreateHandle(cp);
        }

        /// <summary>注册一个全局热键；返回是否成功（被其他程序占用时为 false）。</summary>
        public bool Register(int id, uint modifiers, uint virtualKey, Action onTriggered)
        {
            if (!RegisterHotKey(Handle, id, modifiers | MOD_NOREPEAT, virtualKey)) return false;
            _handlers[id] = onTriggered;
            _registered.Add(id);
            return true;
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY && _handlers.TryGetValue(m.WParam.ToInt32(), out Action? handler))
            {
                handler();
                return;
            }
            base.WndProc(ref m);
        }

        public void Dispose()
        {
            foreach (int id in _registered) UnregisterHotKey(Handle, id);
            _registered.Clear();
            _handlers.Clear();
            DestroyHandle();
        }
    }
}
