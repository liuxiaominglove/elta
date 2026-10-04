using System;

namespace Elta.Core
{
    /// <summary>WebView2 初始化失败分类结果与用户可见文案。</summary>
    public sealed record WebView2FailureInfo(bool IsMissingRuntime, string UserMessage);

    /// <summary>
    /// WebView2 初始化失败的判定与文案（纯逻辑，可跨平台测试）。
    /// 背景：Win10 未预装 WebView2 运行时；缺失时 CreateAsync 抛
    /// WebView2RuntimeNotFoundException（或消息含特征串）。检测到缺失时给"可行动"文案 + 官方安装链接。
    /// </summary>
    public static class WebView2FallbackLogic
    {
        /// <summary>微软官方 Evergreen Bootstrapper 下载链接。</summary>
        public const string RuntimeDownloadUrl = "https://go.microsoft.com/fwlink/p/?LinkId=2124703";

        private static readonly string[] MessageSignatures =
        {
            "not installed",
            "not found",
            "未安装",
            "未找到",
            "找不到",
        };

        public static bool IsMissingRuntime(string? exceptionTypeName, string? message)
        {
            if (!string.IsNullOrEmpty(exceptionTypeName) &&
                exceptionTypeName!.Contains("WebView2RuntimeNotFoundException", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }

            if (string.IsNullOrEmpty(message)) return false;
            if (message!.IndexOf("WebView2", StringComparison.OrdinalIgnoreCase) < 0) return false;

            foreach (string sig in MessageSignatures)
            {
                if (message.IndexOf(sig, StringComparison.OrdinalIgnoreCase) >= 0) return true;
            }
            return false;
        }

        public static WebView2FailureInfo Describe(string? exceptionTypeName, string? message)
        {
            if (IsMissingRuntime(exceptionTypeName, message))
            {
                return new WebView2FailureInfo(true,
                    "无法启动内置浏览器引擎：未检测到 Microsoft Edge WebView2 运行时。\n" +
                    "请先安装（一分钟即可，无需管理员权限）：\n" +
                    RuntimeDownloadUrl);
            }

            return new WebView2FailureInfo(false, $"结果窗口初始化失败：\n{message}");
        }
    }
}
