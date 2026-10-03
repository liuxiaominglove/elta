using System.Windows;
using System.Windows.Controls;

namespace Elta.Windows
{
    /// <summary>C4b：发现新版本的三按钮对话框（前往下载 / 跳过此版本 / 稍后提醒），语义对齐 mac 更新弹窗。</summary>
    public sealed class UpdateDialog : Window
    {
        public enum Choice
        {
            Download,
            Skip,
            Later,
        }

        public Choice Result { get; private set; } = Choice.Later;

        public UpdateDialog(string currentVersion, string remoteVersion)
        {
            Title = "发现新版本";
            Width = 420;
            Height = 210;
            ResizeMode = ResizeMode.NoResize;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            ShowInTaskbar = false;

            var panel = new StackPanel { Margin = new Thickness(20) };
            panel.Children.Add(new TextBlock
            {
                Text = $"发现新版本 v{remoteVersion}",
                FontSize = 16,
                FontWeight = FontWeights.SemiBold,
            });
            panel.Children.Add(new TextBlock
            {
                Text = $"当前版本：v{currentVersion}\n最新版本：v{remoteVersion}\n\n点击「前往下载」打开下载页面。",
                FontSize = 12,
                Margin = new Thickness(0, 10, 0, 16),
                TextWrapping = TextWrapping.Wrap,
            });

            var row = new StackPanel { Orientation = Orientation.Horizontal };
            row.Children.Add(MakeButton("前往下载", Choice.Download, isDefault: true));
            row.Children.Add(MakeButton("跳过此版本", Choice.Skip));
            row.Children.Add(MakeButton("稍后提醒", Choice.Later));
            panel.Children.Add(row);

            Content = panel;
        }

        private Button MakeButton(string text, Choice choice, bool isDefault = false)
        {
            var button = new Button
            {
                Content = text,
                Padding = new Thickness(14, 5, 14, 5),
                Margin = new Thickness(0, 0, 8, 0),
                IsDefault = isDefault,
            };
            button.Click += (_, _) =>
            {
                Result = choice;
                Close();
            };
            return button;
        }
    }
}
