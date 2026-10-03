using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace Elta.Windows
{
    /// <summary>
    /// C1：结果窗口（WPF + WebView2，装载 Core HtmlRenderer 输出的 HTML）。
    /// 整段/拆分、字号、ESC/`/Ctrl+D 交互归 C2。
    /// </summary>
    public sealed class ResultWindow : Window
    {
        private readonly WebView2 _view = new();
        private readonly string _html;

        public ResultWindow(string html)
        {
            _html = html;

            Title = "ELTA 翻译结果";
            Width = 680;
            Height = 560;
            MinWidth = 360;
            MinHeight = 240;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Content = _view;

            Loaded += async (_, _) => await InitializeAsync();
        }

        private async Task InitializeAsync()
        {
            try
            {
                string userDataFolder = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "ELTA", "WebView2");
                CoreWebView2Environment env = await CoreWebView2Environment.CreateAsync(null, userDataFolder);
                await _view.EnsureCoreWebView2Async(env);
                _view.NavigateToString(_html);
                Log.Info("result window shown");
            }
            catch (Exception ex)
            {
                Log.Error("result window init failed", ex);
                MessageBox.Show(
                    $"结果窗口初始化失败：\n{ex.Message}",
                    "ELTA", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }
}
