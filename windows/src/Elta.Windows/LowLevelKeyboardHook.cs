using System;
using System.Runtime.InteropServices;

namespace Elta.Windows
{
    /// <summary>
    /// B4：低级键盘钩子（WH_KEYBOARD_LL），用于**裸键**热键（ESC / `）。
    /// 注意：不要常驻——ESC 全局拦截会干扰所有程序；仅在需要时启停（结果面板打开期间，由子计划 C 接线）。
    /// 必须在带消息循环的线程（本程序为 UI 线程）安装，否则回调不会送达。
    /// </summary>
    internal sealed class LowLevelKeyboardHook : IDisposable
    {
        private const int WH_KEYBOARD_LL = 13;
        private const int HC_ACTION = 0;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_SYSKEYDOWN = 0x0104;

        private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr GetModuleHandle(string? lpModuleName);

        [StructLayout(LayoutKind.Sequential)]
        private struct KbdLlHookStruct
        {
            public uint VkCode;
            public uint ScanCode;
            public uint Flags;
            public uint Time;
            public IntPtr ExtraInfo;
        }

        private readonly LowLevelKeyboardProc _proc;   // 保持引用，防止被 GC 回收
        private IntPtr _hook;
        private bool _disposed;

        /// <summary>键按下回调（VK 码）；返回 true 表示吞掉该按键。</summary>
        public Func<int, bool>? OnKeyDown { get; set; }

        public LowLevelKeyboardHook()
        {
            _proc = HookProc;
        }

        public bool IsRunning => _hook != IntPtr.Zero;

        public bool Start()
        {
            if (_disposed) return false;
            if (_hook != IntPtr.Zero) return true;

            _hook = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, GetModuleHandle(null), 0);
            if (_hook == IntPtr.Zero)
            {
                Log.Warn($"keyboard hook install failed err={Marshal.GetLastWin32Error()}");
                return false;
            }
            Log.Info("keyboard hook installed");
            return true;
        }

        public void Stop()
        {
            if (_hook == IntPtr.Zero) return;
            UnhookWindowsHookEx(_hook);
            _hook = IntPtr.Zero;
            Log.Info("keyboard hook removed");
        }

        private IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode == HC_ACTION)
            {
                int message = wParam.ToInt32();
                if (message == WM_KEYDOWN || message == WM_SYSKEYDOWN)
                {
                    var data = Marshal.PtrToStructure<KbdLlHookStruct>(lParam);
                    int vk = (int)data.VkCode;
                    try
                    {
                        if (OnKeyDown?.Invoke(vk) == true) return 1;   // 吞掉按键
                    }
                    catch (Exception ex)
                    {
                        Log.Error("keyboard hook callback failed", ex);
                    }
                }
            }
            return CallNextHookEx(_hook, nCode, wParam, lParam);
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            Stop();
        }
    }
}
