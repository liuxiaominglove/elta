using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    /// <summary>B4：Windows 热键纯逻辑（VK 码 + Win32 MOD_* 掩码）+ Windows 默认值预设。</summary>
    public class WindowsHotkeysTests
    {
        // MARK: - SanitizeKeyCode

        [Fact]
        public void Sanitize_Negative_ClampsToZero()
            => Assert.Equal(0x00, WindowsHotkeys.SanitizeKeyCode(-5));

        [Fact]
        public void Sanitize_Zero_Stays()
            => Assert.Equal(0x00, WindowsHotkeys.SanitizeKeyCode(0));

        [Fact]
        public void Sanitize_ValidKey_Stays()
            => Assert.Equal(0x54, WindowsHotkeys.SanitizeKeyCode(0x54));

        [Fact]
        public void Sanitize_TooLarge_ClampsTo255()
            => Assert.Equal(0xFF, WindowsHotkeys.SanitizeKeyCode(300));

        [Fact]
        public void Sanitize_255_Stays()
            => Assert.Equal(0xFF, WindowsHotkeys.SanitizeKeyCode(255));

        // MARK: - HasRequiredModifiers

        [Fact]
        public void RequiredModifiers_None_IsFalse()
            => Assert.False(WindowsHotkeys.HasRequiredModifiers(0));

        [Fact]
        public void RequiredModifiers_Control_IsTrue()
            => Assert.True(WindowsHotkeys.HasRequiredModifiers(WindowsHotkeys.ModControl));

        [Fact]
        public void RequiredModifiers_AnyOfFour_IsTrue()
        {
            Assert.True(WindowsHotkeys.HasRequiredModifiers(WindowsHotkeys.ModAlt));
            Assert.True(WindowsHotkeys.HasRequiredModifiers(WindowsHotkeys.ModShift));
            Assert.True(WindowsHotkeys.HasRequiredModifiers(WindowsHotkeys.ModWin));
        }

        [Fact]
        public void RequiredModifiers_CarbonLeakValue_IsFalse()
        {
            // mac Carbon 的 controlKey=0x1000 不是 Win32 MOD_CONTROL(0x2)，不应被当作修饰键
            Assert.False(WindowsHotkeys.HasRequiredModifiers(0x1000));
        }

        // MARK: - Display

        [Fact]
        public void Display_CtrlT()
            => Assert.Equal("Ctrl+T", WindowsHotkeys.Display(0x54, WindowsHotkeys.ModControl));

        [Fact]
        public void Display_CtrlShiftT()
            => Assert.Equal("Ctrl+Shift+T",
                WindowsHotkeys.Display(0x54, WindowsHotkeys.ModControl | WindowsHotkeys.ModShift));

        [Fact]
        public void Display_AllModifiers_OrderCtrlShiftAltWin()
            => Assert.Equal("Ctrl+Shift+Alt+Win+A",
                WindowsHotkeys.Display(0x41,
                    WindowsHotkeys.ModControl | WindowsHotkeys.ModShift | WindowsHotkeys.ModAlt | WindowsHotkeys.ModWin));

        [Fact]
        public void Display_Escape_NoModifiers()
            => Assert.Equal("Esc", WindowsHotkeys.Display(0x1B, 0));

        [Fact]
        public void Display_Backtick()
            => Assert.Equal("`", WindowsHotkeys.Display(0xC0, 0));

        [Fact]
        public void Display_FunctionKeys()
        {
            Assert.Equal("F1", WindowsHotkeys.Display(0x70, 0));
            Assert.Equal("F12", WindowsHotkeys.Display(0x7B, 0));
        }

        [Fact]
        public void Display_UnknownKey_HexFallback()
            => Assert.Equal("0x01", WindowsHotkeys.Display(0x01, 0));

        // MARK: - SettingsDefaults.Windows

        [Fact]
        public void WindowsDefaults_MatchExpectedHotkeys()
        {
            SettingsDefaults d = SettingsDefaults.Windows;
            Assert.Equal(0x54, d.HotkeyKeyCode);
            Assert.Equal(WindowsHotkeys.ModControl, d.HotkeyModifiers);
            Assert.Equal("Ctrl+T", d.HotkeyDisplay);

            Assert.Equal(0x54, d.SelectionHotkeyKeyCode);
            Assert.Equal(WindowsHotkeys.ModControl | WindowsHotkeys.ModShift, d.SelectionHotkeyModifiers);
            Assert.Equal("Ctrl+Shift+T", d.SelectionHotkeyDisplay);

            Assert.Equal(0x1B, d.ClosePanelHotkeyKeyCode);
            Assert.Equal(0, d.ClosePanelHotkeyModifiers);

            Assert.Equal(0xC0, d.TogglePanelHotkeyKeyCode);
            Assert.Equal(0x44, d.SplitHotkeyKeyCode);
            Assert.Equal(WindowsHotkeys.ModControl, d.SplitHotkeyModifiers);
        }
    }
}
