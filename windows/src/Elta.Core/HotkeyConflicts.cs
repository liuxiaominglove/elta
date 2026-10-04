using System.Collections.Generic;

namespace Elta.Core
{
    /// <summary>
    /// Windows 常见系统/应用快捷键冲突提示（对齐 mac checkSystemHotkeyConflict 的角色）。
    /// 仅在用户新录制热键保存前做二次确认，不阻断。
    /// </summary>
    public static class HotkeyConflicts
    {
        public static string? Check(int modifiers, int virtualKey)
        {
            if ((modifiers & WindowsHotkeys.ModWin) != 0)
                return "Win 组合键多被系统占用（Win+D/E/L 等）";

            if (modifiers == WindowsHotkeys.ModAlt)
            {
                switch (virtualKey)
                {
                    case 0x73: return "Alt+F4 关闭窗口（系统）";
                    case 0x09: return "Alt+Tab 切换窗口（系统强占）";
                    case 0x1B: return "Alt+Esc 切换窗口（系统强占）";
                }
            }

            if (modifiers == WindowsHotkeys.ModControl)
            {
                switch (virtualKey)
                {
                    case 0x1B: return "Ctrl+Esc 开始菜单（系统强占）";
                    case 0x20: return "Ctrl+Space 输入法切换";
                    case 0x41: return "Ctrl+A 全选";
                    case 0x43: return "Ctrl+C 复制";
                    case 0x44: return "Ctrl+D 添加收藏 / 删除";
                    case 0x46: return "Ctrl+F 查找";
                    case 0x4E: return "Ctrl+N 新建";
                    case 0x4F: return "Ctrl+O 打开";
                    case 0x50: return "Ctrl+P 打印";
                    case 0x52: return "Ctrl+R 刷新";
                    case 0x53: return "Ctrl+S 保存";
                    case 0x54: return "Ctrl+T 新建标签页（也是本程序默认截图键）";
                    case 0x56: return "Ctrl+V 粘贴";
                    case 0x57: return "Ctrl+W 关闭标签 / 窗口";
                    case 0x58: return "Ctrl+X 剪切";
                    case 0x59: return "Ctrl+Y 重做";
                    case 0x5A: return "Ctrl+Z 撤销";
                }
            }

            if (modifiers == (WindowsHotkeys.ModControl | WindowsHotkeys.ModShift))
            {
                switch (virtualKey)
                {
                    case 0x1B: return "Ctrl+Shift+Esc 任务管理器（系统强占）";
                    case 0x54: return "Ctrl+Shift+T 恢复关闭的标签（浏览器）";
                }
            }

            if (modifiers == (WindowsHotkeys.ModControl | WindowsHotkeys.ModAlt) && virtualKey == 0x2E)
                return "Ctrl+Alt+Del 系统安全键（无法注册）";

            return null;
        }

        /// <summary>
        /// 与该项默认值相同的组合不告警：用户把某动作"重录"成它自身的默认键时不该弹噪音。
        /// </summary>
        public static string? CheckUnlessDefault(int virtualKey, int modifiers, int defaultVirtualKey, int defaultModifiers)
        {
            if (virtualKey == defaultVirtualKey && modifiers == defaultModifiers) return null;
            return Check(modifiers, virtualKey);
        }

        /// <summary>从「本次新录制的热键」收集冲突项；键码为 null 表示未录制，跳过。</summary>
        public static IReadOnlyList<(string Display, string Reason)> Collect(
            IEnumerable<(int? VirtualKey, int Modifiers)> recorded)
        {
            var list = new List<(string, string)>();
            foreach ((int? vk, int mods) in recorded)
            {
                if (vk is null) continue;
                string? reason = Check(mods, vk.Value);
                if (reason is not null)
                    list.Add((WindowsHotkeys.Display(vk.Value, mods), reason));
            }
            return list;
        }
    }
}
