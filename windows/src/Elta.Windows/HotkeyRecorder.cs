using System;
using System.Collections.Generic;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using Elta.Core;

namespace Elta.Windows
{
    /// <summary>
    /// C3b：单个热键录制行。对齐 mac HotkeyRecorder：10s 超时、裸键白名单、
    /// 需至少一个修饰键、录制即检查常见冲突（保存时再统一二次确认）。
    /// </summary>
    public sealed class HotkeyRecorder
    {
        private readonly Button _button;
        private readonly TextBlock _status;
        private readonly Func<string> _defaultDisplay;
        private readonly HashSet<int> _allowedSolo;

        private DispatcherTimer? _timeout;

        public int? RecordedVk { get; private set; }
        public int RecordedModifiers { get; private set; }
        public bool IsRecording { get; private set; }
        public bool HasRecorded => RecordedVk is not null;
        public Action<int, int, string> Apply { get; }

        public HotkeyRecorder(
            Button button,
            TextBlock status,
            Func<string> defaultDisplay,
            int[] allowedSolo,
            Action<int, int, string> apply)
        {
            _button = button;
            _status = status;
            _defaultDisplay = defaultDisplay;
            _allowedSolo = new HashSet<int>(allowedSolo);
            Apply = apply;
            _button.Content = defaultDisplay();
        }

        public void Start()
        {
            if (IsRecording) return;
            IsRecording = true;
            RecordedVk = null;
            RecordedModifiers = 0;

            _button.Content = "按下组合键…";
            _status.Text = "请按下组合键…";

            var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(10) };
            timer.Tick += (_, _) =>
            {
                Cancel();
                _status.Text = "录制超时，请重试";
            };
            _timeout = timer;
            timer.Start();
        }

        /// <summary>窗口级 PreviewKeyDown 路由进来；返回后若 IsRecording 变 false，调用方应清空激活态。</summary>
        public void HandleKey(KeyEventArgs e)
        {
            Key key = e.Key == Key.System ? e.SystemKey : e.Key;
            e.Handled = true;

            // WPF 会把修饰键本身也送进 PreviewKeyDown（mac 的 flagsChanged 无此问题）：
            // 录制中忽略纯修饰键，继续等主键，否则会录成 "Ctrl+0xA2(LeftCtrl)" 这类脏值。
            if (IsModifierKey(key)) return;

            int vk = KeyInterop.VirtualKeyFromKey(key);
            int mods = ToModifiers(Keyboard.Modifiers);

            if (!_allowedSolo.Contains(vk) && !WindowsHotkeys.HasRequiredModifiers(mods))
            {
                StopTimer();
                IsRecording = false;
                _button.Content = _defaultDisplay();
                _status.Text = "❌ 单个字母不能作为快捷键\n请同时按住 Ctrl / Alt / Shift / Win 之一再按字母";
                return;
            }

            RecordedVk = vk;
            RecordedModifiers = mods;
            StopTimer();
            IsRecording = false;

            string display = WindowsHotkeys.Display(vk, mods);
            _button.Content = display;
            string text = $"已录制：{display}\n点击「保存并应用」使快捷键生效";
            string? conflict = HotkeyConflicts.Check(mods, vk);
            if (conflict is not null) text += $"\n⚠️ 可能与系统快捷键冲突：{conflict}";
            _status.Text = text;
        }

        public void Cancel()
        {
            StopTimer();
            IsRecording = false;
            _button.Content = _defaultDisplay();
        }

        /// <summary>恢复默认后调用：清空录制态，按钮显示当前（默认）值。</summary>
        public void Reset()
        {
            Cancel();
            RecordedVk = null;
            RecordedModifiers = 0;
        }

        public void SetStatus(string text) => _status.Text = text;

        private void StopTimer()
        {
            _timeout?.Stop();
            _timeout = null;
        }

        private static bool IsModifierKey(Key k) =>
            k is Key.LeftCtrl or Key.RightCtrl
              or Key.LeftShift or Key.RightShift
              or Key.LeftAlt or Key.RightAlt
              or Key.LWin or Key.RWin
              or Key.None;

        public static int ToModifiers(ModifierKeys m)
        {
            int mods = 0;
            if ((m & ModifierKeys.Control) != 0) mods |= WindowsHotkeys.ModControl;
            if ((m & ModifierKeys.Shift) != 0) mods |= WindowsHotkeys.ModShift;
            if ((m & ModifierKeys.Alt) != 0) mods |= WindowsHotkeys.ModAlt;
            if ((m & ModifierKeys.Windows) != 0) mods |= WindowsHotkeys.ModWin;
            return mods;
        }
    }
}
