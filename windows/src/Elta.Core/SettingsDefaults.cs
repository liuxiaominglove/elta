namespace Elta.Core
{
    /// <summary>
    /// 设置默认值（平台「方言」）。存储逻辑在 <see cref="SettingsManager"/>，默认值随平台注入：
    /// 单元测试用 <see cref="MacParity"/>（对齐 macOS 版，供黄金测试验证移植保真）；
    /// Windows 外壳在 B4 用 <c>MacParity with { ... }</c> 覆盖为 Windows 键位与显示符号。
    /// </summary>
    public sealed record SettingsDefaults
    {
        // Carbon 修饰键位（macOS 值；Windows 在 B4 覆盖）
        private const int ControlKey = 0x1000;
        private const int ShiftKey = 0x0200;

        public AIProvider ApiProvider { get; init; } = AIProvider.Deepseek;

        public int HotkeyKeyCode { get; init; } = 0x11;            // T
        public int HotkeyModifiers { get; init; } = ControlKey;
        public string HotkeyDisplay { get; init; } = "⌃T";

        public int SelectionHotkeyKeyCode { get; init; } = 0x11;   // T（配合 Shift）
        public int SelectionHotkeyModifiers { get; init; } = ControlKey | ShiftKey;
        public string SelectionHotkeyDisplay { get; init; } = "⇧⌃T";

        public int ClosePanelHotkeyKeyCode { get; init; } = 0x35;  // ESC
        public int ClosePanelHotkeyModifiers { get; init; } = 0;   // mac defaults.integer 未设置默认 0
        public string ClosePanelHotkeyDisplay { get; init; } = "Esc";

        public int TogglePanelHotkeyKeyCode { get; init; } = 0x32; // ` 键
        public int TogglePanelHotkeyModifiers { get; init; } = 0;
        public string TogglePanelHotkeyDisplay { get; init; } = "`";

        public int SplitHotkeyKeyCode { get; init; } = 0x02;       // D（配合 Control）
        public int SplitHotkeyModifiers { get; init; } = ControlKey;
        public string SplitHotkeyDisplay { get; init; } = "⌃D";

        public int PopupFontSizeDefault { get; init; } = 14;
        public int PopupFontSizeMin { get; init; } = 12;
        public int PopupFontSizeMax { get; init; } = 22;

        public bool DefaultSplitMode { get; init; } = true;
        public bool UsesDefaultPrompt { get; init; } = true;
        public bool TelemetryEnabled { get; init; } = true;

        /// <summary>与 macOS 版逐值对齐的默认值（供移植黄金测试）。</summary>
        public static SettingsDefaults MacParity { get; } = new();
    }
}
