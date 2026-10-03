using System.Collections.Generic;
using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    public class HotkeyConflictsTests
    {
        // MARK: - 单键组合冲突检测

        [Fact]
        public void Check_CtrlCopy_ReportsConflict()
        {
            string? reason = HotkeyConflicts.Check(WindowsHotkeys.ModControl, 0x43);
            Assert.NotNull(reason);
            Assert.Contains("复制", reason!);
        }

        [Fact]
        public void Check_CtrlT_ReportsConflict()
        {
            Assert.NotNull(HotkeyConflicts.Check(WindowsHotkeys.ModControl, 0x54));
        }

        [Fact]
        public void Check_CtrlShiftEsc_ReportsConflict()
        {
            Assert.NotNull(HotkeyConflicts.Check(
                WindowsHotkeys.ModControl | WindowsHotkeys.ModShift, 0x1B));
        }

        [Fact]
        public void Check_AltF4_And_AltTab_ReportConflict()
        {
            Assert.NotNull(HotkeyConflicts.Check(WindowsHotkeys.ModAlt, 0x73));
            Assert.NotNull(HotkeyConflicts.Check(WindowsHotkeys.ModAlt, 0x09));
        }

        [Fact]
        public void Check_WinCombo_ReportsConflict()
        {
            Assert.NotNull(HotkeyConflicts.Check(
                WindowsHotkeys.ModWin | WindowsHotkeys.ModControl, 0x41));
        }

        [Fact]
        public void Check_PlainCombo_NoConflict()
        {
            Assert.Null(HotkeyConflicts.Check(
                WindowsHotkeys.ModControl | WindowsHotkeys.ModShift, 0x51)); // Ctrl+Shift+Q
        }

        [Fact]
        public void CheckUnlessDefault_SkipsOwnDefaultCombo()
        {
            // 划词默认 Ctrl+Shift+T 在冲突表里（浏览器恢复标签），但重录成同一默认值不应告警
            Assert.Null(HotkeyConflicts.CheckUnlessDefault(
                0x54, WindowsHotkeys.ModControl | WindowsHotkeys.ModShift,
                0x54, WindowsHotkeys.ModControl | WindowsHotkeys.ModShift));
        }

        [Fact]
        public void CheckUnlessDefault_StillReportsOtherCombos()
        {
            Assert.NotNull(HotkeyConflicts.CheckUnlessDefault(
                0x43, WindowsHotkeys.ModControl,          // Ctrl+C
                0x54, WindowsHotkeys.ModControl | WindowsHotkeys.ModShift));
        }

        // MARK: - 批量收集（保存前二次确认用）

        [Fact]
        public void Collect_SkipsUnrecordedAndReportsDisplay()
        {
            var recorded = new List<(int?, int)>
            {
                (0x43, WindowsHotkeys.ModControl),   // Ctrl+C 冲突
                (null, 0),                             // 未录制，跳过
                (0x51, WindowsHotkeys.ModControl | WindowsHotkeys.ModShift), // Ctrl+Shift+Q 不冲突
            };

            IReadOnlyList<(string Display, string Reason)> conflicts = HotkeyConflicts.Collect(recorded);

            Assert.Single(conflicts);
            Assert.Equal("Ctrl+C", conflicts[0].Display);
        }
    }
}
