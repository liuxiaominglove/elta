using System;
using System.Collections.Generic;

namespace Elta.Core
{
    /// <summary>
    /// B4：Windows 热键纯逻辑。键码用 Win32 Virtual-Key（VK），修饰键用 Win32 MOD_* 掩码
    /// （与 RegisterHotKey 的 fsModifiers 一致）。显示串供设置界面/托盘展示。
    /// 平台方言集中在此，Core 其余部分不感知 Windows 常量。
    /// </summary>
    public static class WindowsHotkeys
    {
        public const int ModAlt = 0x0001;
        public const int ModControl = 0x0002;
        public const int ModShift = 0x0004;
        public const int ModWin = 0x0008;

        /// <summary>四个修饰键的并集；用于把外部/残留值掩码到合法位。</summary>
        public const int AllModifiers = ModAlt | ModControl | ModShift | ModWin;

        /// <summary>把键码夹到 VK 合法区间 [0x00, 0xFF]（对齐 mac sanitizeHotkeyCode 的防崩语义）。</summary>
        public static int SanitizeKeyCode(int value) => Math.Clamp(value, 0x00, 0xFF);

        /// <summary>热键是否至少含一个修饰键（裸键不算，需走低级键盘钩子）。</summary>
        public static bool HasRequiredModifiers(int modifiers) => (modifiers & AllModifiers) != 0;

        /// <summary>可读显示串，如 "Ctrl+Shift+T"；修饰键顺序 Ctrl+Shift+Alt+Win。</summary>
        public static string Display(int keyCode, int modifiers)
        {
            var parts = new List<string>(5);
            if ((modifiers & ModControl) != 0) parts.Add("Ctrl");
            if ((modifiers & ModShift) != 0) parts.Add("Shift");
            if ((modifiers & ModAlt) != 0) parts.Add("Alt");
            if ((modifiers & ModWin) != 0) parts.Add("Win");
            parts.Add(KeyName(keyCode));
            return string.Join("+", parts);
        }

        /// <summary>VK 码 → 可读键名；未知返回 "0xNN"。</summary>
        public static string KeyName(int keyCode) => keyCode switch
        {
            >= 0x41 and <= 0x5A => ((char)keyCode).ToString(),   // A-Z
            >= 0x30 and <= 0x39 => ((char)keyCode).ToString(),   // 0-9
            >= 0x70 and <= 0x7B => "F" + (keyCode - 0x6F),       // F1-F12
            0x08 => "Backspace",
            0x09 => "Tab",
            0x0D => "Enter",
            0x1B => "Esc",
            0x20 => "Space",
            0x25 => "Left",
            0x26 => "Up",
            0x27 => "Right",
            0x28 => "Down",
            0x2E => "Delete",
            0xC0 => "`",
            _ => $"0x{keyCode:X2}",
        };
    }
}
