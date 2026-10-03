using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Elta.Core;

namespace Elta.Windows
{
    /// <summary>
    /// C3：偏好设置窗口（WPF 代码布局，无 XAML）。C3a 实现「通用」页；快捷键/模板页为占位（C3b/C3c）。
    /// 语义对齐 mac SettingsWindowController：provider 切换即持久化旧 provider 的 key/模型；
    /// 「保存并应用」持久化并重注册热键；「恢复默认」不触碰 API Key。
    /// </summary>
    public sealed class SettingsWindow : Window
    {
        private readonly SettingsManager _settings;
        private readonly Action _onHotkeysChanged;
        private readonly ConnectionProbe _probe = new();

        private readonly ComboBox _providerBox = new();
        private readonly TextBlock _registerText = new();
        private readonly ComboBox _modelBox = new();
        private readonly PasswordBox _keyHidden = new();
        private readonly TextBox _keyVisible = new();
        private readonly Button _keyToggle = new();
        private readonly Button _testButton = new();
        private readonly TextBlock _testStatus = new();
        private readonly CheckBox _telemetry = new();
        private readonly TextBlock _saveStatus = new();

        private readonly List<HotkeyRecorder> _recorders = new();
        private HotkeyRecorder? _activeRecorder;
        private RadioButton _splitWhole = null!;
        private RadioButton _splitParts = null!;

        private bool _loading;
        private bool _keyRevealed;

        public SettingsWindow(SettingsManager settings, Action onHotkeysChanged)
        {
            _settings = settings;
            _onHotkeysChanged = onHotkeysChanged;

            Title = "ELTA 偏好设置";
            Width = 640;
            Height = 680;
            MinWidth = 520;
            MinHeight = 480;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;

            BuildUi();
            LoadFromSettings();

            // 录键：窗口级拦截（录制中吃掉所有按键，避免触发焦点/默认按钮）
            PreviewKeyDown += (_, e) =>
            {
                if (_activeRecorder is not { IsRecording: true }) return;
                _activeRecorder.HandleKey(e);
                if (!_activeRecorder.IsRecording) _activeRecorder = null;
            };
        }

        // MARK: - UI 组装

        private static TextBlock Label(string text, bool bold, bool secondary)
        {
            return new TextBlock
            {
                Text = text,
                FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal,
                FontSize = 12,
                Foreground = secondary ? Brushes.Gray : Brushes.Black,
                Margin = new Thickness(0, 6, 0, 4),
            };
        }

        private void BuildUi()
        {
            var root = new Grid { Margin = new Thickness(12) };
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var tabs = new TabControl();
            tabs.Items.Add(new TabItem { Header = "通用", Content = BuildGeneralTab() });
            tabs.Items.Add(new TabItem { Header = "快捷键", Content = BuildHotkeysTab() });
            tabs.Items.Add(new TabItem { Header = "模板", Content = Placeholder("翻译模板编辑将在下一步开发中提供（当前使用内置默认模板）。") });
            Grid.SetRow(tabs, 0);
            root.Children.Add(tabs);

            // 底部：保存 / 恢复默认 / 保存状态 / 版本
            var bottom = new Grid { Margin = new Thickness(0, 10, 0, 0) };
            bottom.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            bottom.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            bottom.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            bottom.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var saveButton = new Button
            {
                Content = "保存并应用",
                Padding = new Thickness(16, 6, 16, 6),
                IsDefault = true,
            };
            saveButton.Click += (_, _) => SaveAll();
            Grid.SetColumn(saveButton, 0);
            bottom.Children.Add(saveButton);

            var resetButton = new Button
            {
                Content = "恢复默认",
                Padding = new Thickness(16, 6, 16, 6),
                Margin = new Thickness(8, 0, 0, 0),
            };
            resetButton.Click += (_, _) => ResetAll();
            Grid.SetColumn(resetButton, 1);
            bottom.Children.Add(resetButton);

            _saveStatus.Foreground = Brushes.Green;
            _saveStatus.FontSize = 12;
            _saveStatus.VerticalAlignment = VerticalAlignment.Center;
            _saveStatus.Margin = new Thickness(12, 0, 0, 0);
            Grid.SetColumn(_saveStatus, 2);
            bottom.Children.Add(_saveStatus);

            var version = new TextBlock
            {
                Text = $"ELTA {typeof(SettingsWindow).Assembly.GetName().Version}",
                FontSize = 10,
                Foreground = Brushes.Gray,
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(version, 3);
            bottom.Children.Add(version);

            Grid.SetRow(bottom, 1);
            root.Children.Add(bottom);

            Content = root;
        }

        private HotkeyRecorder AddRecorderRow(
            Panel parent,
            string label,
            Func<int> getVk,
            Func<int> getMods,
            int[] allowedSolo,
            Action<int, int, string> apply)
        {
            parent.Children.Add(Label(label, bold: false, secondary: false));

            var button = new Button
            {
                HorizontalAlignment = HorizontalAlignment.Left,
                Padding = new Thickness(16, 5, 16, 5),
                MinWidth = 150,
            };
            var status = new TextBlock
            {
                FontSize = 11,
                Foreground = Brushes.Gray,
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 2, 0, 10),
            };

            var recorder = new HotkeyRecorder(
                button, status,
                () => WindowsHotkeys.Display(getVk(), getMods()),
                allowedSolo, apply);

            button.Click += (_, _) =>
            {
                if (_activeRecorder is { IsRecording: true }) return;
                if (recorder.IsRecording) return;
                _activeRecorder = recorder;
                recorder.Start();
            };

            parent.Children.Add(button);
            parent.Children.Add(status);
            _recorders.Add(recorder);
            return recorder;
        }

        private UIElement BuildHotkeysTab()
        {
            var panel = new StackPanel { Margin = new Thickness(16) };
            panel.Children.Add(Label("点击按钮后按下新组合键（10 秒内）；「关闭面板」「切换弹窗位置」允许单键。",
                bold: false, secondary: true));

            AddRecorderRow(panel, "截图翻译", () => _settings.HotkeyKeyCode, () => _settings.HotkeyModifiers,
                Array.Empty<int>(),
                (vk, mods, display) =>
                {
                    _settings.HotkeyKeyCode = vk;
                    _settings.HotkeyModifiers = mods;
                    _settings.HotkeyDisplay = display;
                });

            AddRecorderRow(panel, "划词翻译", () => _settings.SelectionHotkeyKeyCode, () => _settings.SelectionHotkeyModifiers,
                Array.Empty<int>(),
                (vk, mods, display) =>
                {
                    _settings.SelectionHotkeyKeyCode = vk;
                    _settings.SelectionHotkeyModifiers = mods;
                    _settings.SelectionHotkeyDisplay = display;
                });

            AddRecorderRow(panel, "关闭面板（可单键）", () => _settings.ClosePanelHotkeyKeyCode, () => _settings.ClosePanelHotkeyModifiers,
                new[] { 0x1B },
                (vk, mods, display) =>
                {
                    _settings.ClosePanelHotkeyKeyCode = vk;
                    _settings.ClosePanelHotkeyModifiers = mods;
                    _settings.ClosePanelHotkeyDisplay = display;
                });

            AddRecorderRow(panel, "切换弹窗位置（可单键）", () => _settings.TogglePanelHotkeyKeyCode, () => _settings.TogglePanelHotkeyModifiers,
                new[] { 0xC0 },
                (vk, mods, display) =>
                {
                    _settings.TogglePanelHotkeyKeyCode = vk;
                    _settings.TogglePanelHotkeyModifiers = mods;
                    _settings.TogglePanelHotkeyDisplay = display;
                });

            AddRecorderRow(panel, "拆分翻译", () => _settings.SplitHotkeyKeyCode, () => _settings.SplitHotkeyModifiers,
                Array.Empty<int>(),
                (vk, mods, display) =>
                {
                    _settings.SplitHotkeyKeyCode = vk;
                    _settings.SplitHotkeyModifiers = mods;
                    _settings.SplitHotkeyDisplay = display;
                });

            panel.Children.Add(new Separator { Margin = new Thickness(0, 6, 0, 8) });
            panel.Children.Add(Label("默认优先弹窗模式：", bold: true, secondary: false));

            _splitWhole = new RadioButton { Content = "整段", Margin = new Thickness(0, 4, 0, 0) };
            _splitParts = new RadioButton { Content = "拆分（逐句对照）", Margin = new Thickness(0, 4, 0, 0) };
            panel.Children.Add(_splitWhole);
            panel.Children.Add(_splitParts);

            return new ScrollViewer
            {
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                Content = panel,
            };
        }

        private static UIElement Placeholder(string text)
        {
            return new TextBlock
            {
                Text = text,
                FontSize = 12,
                Foreground = Brushes.Gray,
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(16),
            };
        }

        private UIElement BuildGeneralTab()
        {
            var panel = new StackPanel { Margin = new Thickness(16) };

            panel.Children.Add(Label("AI 模型提供商：", bold: true, secondary: false));
            _providerBox.Margin = new Thickness(0, 0, 0, 10);
            foreach (AIProvider p in new[] { AIProvider.Deepseek, AIProvider.Qwen })
                _providerBox.Items.Add(AIProviders.DisplayName(p));
            _providerBox.SelectionChanged += (_, _) => OnProviderChanged();
            panel.Children.Add(_providerBox);

            _registerText.FontSize = 12;
            _registerText.Foreground = Brushes.Gray;
            _registerText.TextWrapping = TextWrapping.Wrap;
            panel.Children.Add(_registerText);

            panel.Children.Add(Label("模型（Model）：", bold: true, secondary: false));
            _modelBox.Margin = new Thickness(0, 0, 0, 10);
            panel.Children.Add(_modelBox);

            panel.Children.Add(Label("API Key：", bold: true, secondary: false));
            var keyRow = new Grid();
            keyRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            keyRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            _keyHidden.Padding = new Thickness(4);
            Grid.SetColumn(_keyHidden, 0);
            keyRow.Children.Add(_keyHidden);

            _keyVisible.Padding = new Thickness(4);
            _keyVisible.Visibility = Visibility.Collapsed;
            Grid.SetColumn(_keyVisible, 0);
            keyRow.Children.Add(_keyVisible);

            _keyToggle.Content = "显示";
            _keyToggle.Padding = new Thickness(10, 4, 10, 4);
            _keyToggle.Margin = new Thickness(6, 0, 0, 0);
            _keyToggle.Click += (_, _) => ToggleKeyReveal();
            Grid.SetColumn(_keyToggle, 1);
            keyRow.Children.Add(_keyToggle);
            panel.Children.Add(keyRow);

            _testButton.Content = "测试连接";
            _testButton.Padding = new Thickness(14, 5, 14, 5);
            _testButton.HorizontalAlignment = HorizontalAlignment.Left;
            _testButton.Margin = new Thickness(0, 12, 0, 0);
            _testButton.Click += (_, _) => TestConnection();
            panel.Children.Add(_testButton);

            _testStatus.FontSize = 11;
            _testStatus.Foreground = Brushes.Gray;
            _testStatus.TextWrapping = TextWrapping.Wrap;
            _testStatus.Margin = new Thickness(0, 4, 0, 0);
            panel.Children.Add(_testStatus);

            panel.Children.Add(new Separator { Margin = new Thickness(0, 14, 0, 6) });

            _telemetry.Content = "参与匿名使用统计";
            _telemetry.FontSize = 12;
            _telemetry.Checked += (_, _) => _settings.TelemetryEnabled = true;
            _telemetry.Unchecked += (_, _) => _settings.TelemetryEnabled = false;
            panel.Children.Add(_telemetry);

            var hint = new TextBlock
            {
                Text = "仅上报随机匿名标识统计每日使用人数，不含任何个人信息",
                FontSize = 10,
                Foreground = Brushes.Gray,
                Margin = new Thickness(22, 2, 0, 0),
                TextWrapping = TextWrapping.Wrap,
            };
            panel.Children.Add(hint);

            return new ScrollViewer
            {
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                Content = panel,
            };
        }

        // MARK: - 状态加载

        private void LoadFromSettings()
        {
            _loading = true;
            _providerBox.SelectedIndex = _settings.ApiProvider == AIProvider.Deepseek ? 0 : 1;
            LoadProviderCard(_settings.ApiProvider);
            _telemetry.IsChecked = _settings.TelemetryEnabled;
            _splitWhole.IsChecked = !_settings.DefaultSplitMode;
            _splitParts.IsChecked = _settings.DefaultSplitMode;
            _loading = false;
        }

        private void LoadProviderCard(AIProvider provider)
        {
            _registerText.Text = $"注册地址：{AIProviders.RegisterUrl(provider)}";

            _modelBox.Items.Clear();
            foreach (string model in AIProviders.AvailableModels(provider))
                _modelBox.Items.Add(model);
            string current = _settings.ModelOverride(provider) ?? AIProviders.HardcodedDefaultModel(provider);
            _modelBox.SelectedItem = current;
            if (_modelBox.SelectedIndex < 0 && _modelBox.Items.Count > 0) _modelBox.SelectedIndex = 0;

            string key = _settings.ApiKey(provider) ?? "";
            _keyHidden.Password = key;
            _keyVisible.Text = key;
            _keyRevealed = false;
            _keyVisible.Visibility = Visibility.Collapsed;
            _keyHidden.Visibility = Visibility.Visible;
            _keyToggle.Content = "显示";

            _testStatus.Text = "";
        }

        private string KeyValue => _keyRevealed ? _keyVisible.Text : _keyHidden.Password;

        private void OnProviderChanged()
        {
            if (_loading) return;

            // 对齐 mac：切换前先把当前 provider 的 key/模型落盘，避免未保存丢失
            AIProvider oldProvider = _settings.ApiProvider;
            PersistKeyAndModel(oldProvider);
            _settings.ApiProvider = _providerBox.SelectedIndex == 1 ? AIProvider.Qwen : AIProvider.Deepseek;
            LoadProviderCard(_settings.ApiProvider);
        }

        private void PersistKeyAndModel(AIProvider provider)
        {
            string key = KeyValue.Trim();
            _settings.SetApiKey(key.Length == 0 ? null : key, provider);
            if (_modelBox.SelectedItem is string model)
                _settings.SetModelOverride(model, provider);
        }

        // MARK: - 交互

        private void ToggleKeyReveal()
        {
            _keyRevealed = !_keyRevealed;
            if (_keyRevealed)
            {
                _keyVisible.Text = _keyHidden.Password;
                _keyHidden.Visibility = Visibility.Collapsed;
                _keyVisible.Visibility = Visibility.Visible;
                _keyToggle.Content = "隐藏";
            }
            else
            {
                _keyHidden.Password = _keyVisible.Text;
                _keyVisible.Visibility = Visibility.Collapsed;
                _keyHidden.Visibility = Visibility.Visible;
                _keyToggle.Content = "显示";
            }
        }

        private async void TestConnection()
        {
            AIProvider provider = _settings.ApiProvider;

            string key = KeyValue.Trim();
            if (key.Length == 0) key = _settings.ApiKey(provider) ?? "";
            if (key.Length == 0)
            {
                _testStatus.Text = "请先输入 API Key";
                _testStatus.Foreground = Brushes.Red;
                return;
            }

            string model = _modelBox.SelectedItem as string ?? AIProviders.HardcodedDefaultModel(provider);
            ResolvedConnectionTarget target = ConnectionTarget.Resolve(
                model, provider, AIProviders.DefaultModel(provider, null));

            _testStatus.Text = "测试中...";
            _testStatus.Foreground = Brushes.Gray;

            ConnectionProbeResult r = await _probe.TestAsync(target.Endpoint, target.Model, key);
            if (r.Cancelled) return;

            if (r.Error is not null)
            {
                _testStatus.Text = $"连接失败: {r.Error}";
                _testStatus.Foreground = Brushes.Red;
                return;
            }

            ConnectionResult result = r.Result!;
            switch (result.Kind)
            {
                case ConnectionResultKind.Success:
                    _testStatus.Text = $"连接成功 (HTTP {result.Code})";
                    _testStatus.Foreground = Brushes.Green;
                    break;
                case ConnectionResultKind.AuthFailure:
                    _testStatus.Text = $"API Key 无效 (HTTP {result.Code})";
                    _testStatus.Foreground = Brushes.Red;
                    break;
                default:
                    _testStatus.Text = $"服务器返回 HTTP {result.Code}";
                    _testStatus.Foreground = Brushes.Orange;
                    break;
            }
        }

        // MARK: - 保存 / 恢复默认

        private void SaveAll()
        {
            // 保存前：新录制的热键若命中常见系统/应用快捷键，先二次确认（对齐 mac）
            var recorded = new List<(int?, int)>();
            foreach (HotkeyRecorder rec in _recorders)
                if (rec.HasRecorded) recorded.Add((rec.RecordedVk, rec.RecordedModifiers));

            IReadOnlyList<(string Display, string Reason)> conflicts = HotkeyConflicts.Collect(recorded);
            if (conflicts.Count > 0)
            {
                string details = string.Join("\n", conflicts.Select(c => $"「{c.Display}」：{c.Reason}"));
                MessageBoxResult use = MessageBox.Show(
                    this,
                    $"以下快捷键在大多数应用中是常用功能：\n\n{details}\n\n" +
                    "全局注册后，这些应用内按此键将触发翻译而非原功能。确定要使用吗？",
                    "快捷键可能与系统冲突",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Warning);
                if (use != MessageBoxResult.Yes) return;
            }

            AIProvider provider = _settings.ApiProvider;
            PersistKeyAndModel(provider);

            foreach (HotkeyRecorder rec in _recorders)
            {
                if (!rec.HasRecorded) continue;
                int vk = rec.RecordedVk!.Value;
                rec.Apply(vk, rec.RecordedModifiers, WindowsHotkeys.Display(vk, rec.RecordedModifiers));
            }

            _settings.DefaultSplitMode = _splitParts.IsChecked == true;
            _onHotkeysChanged();

            Log.Info($"settings saved provider={AIProviders.RawValue(provider)} " +
                     $"keyLen={KeyValue.Trim().Length} model={_modelBox.SelectedItem} " +
                     $"hotkeyChanges={recorded.Count} defaultSplit={_settings.DefaultSplitMode}");
            _saveStatus.Text = "已保存";
        }

        private void ResetAll()
        {
            MessageBoxResult r = MessageBox.Show(
                this,
                "将恢复 API Key 以外的所有设置为默认值，包括快捷键和翻译模板。确定继续？",
                "恢复默认设置",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);
            if (r != MessageBoxResult.Yes) return;

            SettingsDefaults d = _settings.Defaults;
            _settings.CustomPrompt = null;
            _settings.UsesDefaultPrompt = true;

            _settings.HotkeyKeyCode = d.HotkeyKeyCode;
            _settings.HotkeyModifiers = d.HotkeyModifiers;
            _settings.HotkeyDisplay = d.HotkeyDisplay;
            _settings.SelectionHotkeyKeyCode = d.SelectionHotkeyKeyCode;
            _settings.SelectionHotkeyModifiers = d.SelectionHotkeyModifiers;
            _settings.SelectionHotkeyDisplay = d.SelectionHotkeyDisplay;
            _settings.ClosePanelHotkeyKeyCode = d.ClosePanelHotkeyKeyCode;
            _settings.ClosePanelHotkeyModifiers = d.ClosePanelHotkeyModifiers;
            _settings.ClosePanelHotkeyDisplay = d.ClosePanelHotkeyDisplay;
            _settings.TogglePanelHotkeyKeyCode = d.TogglePanelHotkeyKeyCode;
            _settings.TogglePanelHotkeyModifiers = d.TogglePanelHotkeyModifiers;
            _settings.TogglePanelHotkeyDisplay = d.TogglePanelHotkeyDisplay;
            _settings.SplitHotkeyKeyCode = d.SplitHotkeyKeyCode;
            _settings.SplitHotkeyModifiers = d.SplitHotkeyModifiers;
            _settings.SplitHotkeyDisplay = d.SplitHotkeyDisplay;
            _settings.DefaultSplitMode = d.DefaultSplitMode;

            foreach (HotkeyRecorder rec in _recorders)
            {
                rec.Reset();
                rec.SetStatus("已恢复默认快捷键");
            }
            _splitWhole.IsChecked = !_settings.DefaultSplitMode;
            _splitParts.IsChecked = _settings.DefaultSplitMode;

            _onHotkeysChanged();
            Log.Info("settings reset to defaults (api key kept)");
            _saveStatus.Text = "已恢复默认";
        }
    }
}
