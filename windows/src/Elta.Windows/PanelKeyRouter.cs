using System;
using System.Runtime.InteropServices;
using Elta.Core;

namespace Elta.Windows
{
    /// <summary>
    /// C2：面板期间的低级键盘路由（Esc / ` / Ctrl+D 等）。复用 <see cref="LowLevelKeyboardHook"/>，
    /// 仅在加载窗或结果窗存在期间启停；命中且已消费时吞掉按键（对齐 mac CGEventTap 语义）。
    /// </summary>
    internal sealed class PanelKeyRouter
    {
        [DllImport("user32.dll")]
        private static extern short GetAsyncKeyState(int vKey);

        private readonly LowLevelKeyboardHook _hook = new();

        /// <summary>(vk, 当前修饰键掩码) → 是否消费；由 Program 按设置里的键位判定。</summary>
        public Func<int, int, bool>? Match { get; set; }

        public bool IsRunning => _hook.IsRunning;

        public void Start()
        {
            if (_hook.IsRunning) return;
            _hook.OnKeyDown = OnKeyDown;
            _hook.Start();
        }

        public void Stop()
        {
            if (!_hook.IsRunning) return;
            _hook.Stop();
        }

        private bool OnKeyDown(int vk)
        {
            try
            {
                return Match?.Invoke(vk, CurrentModifiers()) == true;
            }
            catch (Exception ex)
            {
                Log.Error("panel key router failed", ex);
                return false;
            }
        }

        /// <summary>钩子回调内读取物理按键状态（低级钩子回调不携带修饰键信息）。</summary>
        public static int CurrentModifiers()
        {
            const int VK_SHIFT = 0x10, VK_CONTROL = 0x11, VK_MENU = 0x12, VK_LWIN = 0x5B, VK_RWIN = 0x5C;
            int mods = 0;
            if (Down(VK_CONTROL)) mods |= WindowsHotkeys.ModControl;
            if (Down(VK_SHIFT)) mods |= WindowsHotkeys.ModShift;
            if (Down(VK_MENU)) mods |= WindowsHotkeys.ModAlt;
            if (Down(VK_LWIN) || Down(VK_RWIN)) mods |= WindowsHotkeys.ModWin;
            return mods;
        }

        private static bool Down(int vk) => (GetAsyncKeyState(vk) & 0x8000) != 0;
    }
}
