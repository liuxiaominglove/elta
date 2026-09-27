using System;
using System.Collections.Generic;

namespace Elta.Core
{
    /// <summary>支持的 AI 提供商。移植自 macOS 版 Sources/AIProvider.swift。</summary>
    public enum AIProvider
    {
        Deepseek,
        Qwen,
    }

    /// <summary>提供商的静态元数据与模型选择（不依赖设置持久化，覆盖值由调用方传入）。</summary>
    public static class AIProviders
    {
        public static string DisplayName(AIProvider provider) => provider switch
        {
            AIProvider.Deepseek => "DeepSeek（国内 · 推荐）",
            AIProvider.Qwen => "千问（阿里云 · 国内）",
            _ => throw new ArgumentOutOfRangeException(nameof(provider)),
        };

        public static string ShortName(AIProvider provider) => provider switch
        {
            AIProvider.Deepseek => "DeepSeek",
            AIProvider.Qwen => "千问",
            _ => throw new ArgumentOutOfRangeException(nameof(provider)),
        };

        public static string Endpoint(AIProvider provider) => provider switch
        {
            AIProvider.Deepseek => "https://api.deepseek.com/chat/completions",
            AIProvider.Qwen => "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            _ => throw new ArgumentOutOfRangeException(nameof(provider)),
        };

        /// <summary>内置默认模型（不含用户覆盖）。</summary>
        public static string HardcodedDefaultModel(AIProvider provider) => provider switch
        {
            AIProvider.Deepseek => "deepseek-v4-flash",
            AIProvider.Qwen => "qwen-plus",
            _ => throw new ArgumentOutOfRangeException(nameof(provider)),
        };

        /// <summary>生效模型：覆盖值非空则用覆盖值，否则回落内置默认。</summary>
        public static string DefaultModel(AIProvider provider, string? modelOverride)
            => string.IsNullOrEmpty(modelOverride) ? HardcodedDefaultModel(provider) : modelOverride;

        public static IReadOnlyList<string> AvailableModels(AIProvider provider) => provider switch
        {
            AIProvider.Deepseek => new[] { "deepseek-v4-flash", "deepseek-v4-pro" },
            AIProvider.Qwen => new[] { "qwen-turbo", "qwen-plus", "qwen-max" },
            _ => throw new ArgumentOutOfRangeException(nameof(provider)),
        };

        public static string RegisterUrl(AIProvider provider) => provider switch
        {
            AIProvider.Deepseek => "platform.deepseek.com",
            AIProvider.Qwen => "bailian.console.aliyun.com",
            _ => throw new ArgumentOutOfRangeException(nameof(provider)),
        };
    }
}
