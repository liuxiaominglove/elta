using System;
using Xunit;

namespace Elta.Core.Tests
{
    public class AIProviderTests
    {
        [Fact]
        public void Deepseek_Metadata()
        {
            Assert.Equal("DeepSeek（国内 · 推荐）", AIProviders.DisplayName(AIProvider.Deepseek));
            Assert.Equal("DeepSeek", AIProviders.ShortName(AIProvider.Deepseek));
            Assert.Equal("https://api.deepseek.com/chat/completions", AIProviders.Endpoint(AIProvider.Deepseek));
            Assert.Equal("deepseek-v4-flash", AIProviders.HardcodedDefaultModel(AIProvider.Deepseek));
            Assert.Equal("platform.deepseek.com", AIProviders.RegisterUrl(AIProvider.Deepseek));
        }

        [Fact]
        public void Qwen_Metadata()
        {
            Assert.Equal("千问（阿里云 · 国内）", AIProviders.DisplayName(AIProvider.Qwen));
            Assert.Equal("千问", AIProviders.ShortName(AIProvider.Qwen));
            Assert.Equal("https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", AIProviders.Endpoint(AIProvider.Qwen));
            Assert.Equal("qwen-plus", AIProviders.HardcodedDefaultModel(AIProvider.Qwen));
            Assert.Equal("bailian.console.aliyun.com", AIProviders.RegisterUrl(AIProvider.Qwen));
        }

        [Fact]
        public void DefaultModel_NoOverride_FallsBackToHardcoded()
            => Assert.Equal("deepseek-v4-flash", AIProviders.DefaultModel(AIProvider.Deepseek, null));

        [Fact]
        public void DefaultModel_EmptyOverride_FallsBackToHardcoded()
            => Assert.Equal("deepseek-v4-flash", AIProviders.DefaultModel(AIProvider.Deepseek, ""));

        [Fact]
        public void DefaultModel_NonEmptyOverride_Wins()
            => Assert.Equal("deepseek-v4-pro", AIProviders.DefaultModel(AIProvider.Deepseek, "deepseek-v4-pro"));

        [Fact]
        public void AvailableModels_Deepseek()
            => Assert.Equal(new[] { "deepseek-v4-flash", "deepseek-v4-pro" }, AIProviders.AvailableModels(AIProvider.Deepseek));

        [Fact]
        public void AvailableModels_Qwen()
            => Assert.Equal(new[] { "qwen-turbo", "qwen-plus", "qwen-max" }, AIProviders.AvailableModels(AIProvider.Qwen));
    }
}
