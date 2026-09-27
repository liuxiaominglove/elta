using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    public class SettingsLogicTests
    {
        // MARK: - 连接状态分类

        [Fact]
        public void Classify_Treats2xxAsSuccess()
        {
            Assert.Equal(ConnectionResultKind.Success, ConnectionResult.Classify(200).Kind);
            Assert.Equal(ConnectionResultKind.Success, ConnectionResult.Classify(299).Kind);
        }

        [Fact]
        public void Classify_Treats401And403AsAuthFailure()
        {
            Assert.Equal(ConnectionResultKind.AuthFailure, ConnectionResult.Classify(401).Kind);
            Assert.Equal(ConnectionResultKind.AuthFailure, ConnectionResult.Classify(403).Kind);
        }

        [Fact]
        public void Classify_TreatsOtherCodesAsServerError()
        {
            Assert.Equal(ConnectionResultKind.ServerError, ConnectionResult.Classify(500).Kind);
            Assert.Equal(ConnectionResultKind.ServerError, ConnectionResult.Classify(404).Kind);
        }

        // MARK: - 连接目标解析

        [Fact]
        public void ResolveConnectionTarget_PrefersTypedModel()
        {
            ResolvedConnectionTarget t = ConnectionTarget.Resolve("qwen-max", AIProvider.Qwen, "qwen-plus");
            Assert.Equal(AIProviders.Endpoint(AIProvider.Qwen), t.Endpoint);
            Assert.Equal("qwen-max", t.Model);
        }

        [Fact]
        public void ResolveConnectionTarget_FallsBackToProviderWhenModelEmpty()
        {
            ResolvedConnectionTarget t = ConnectionTarget.Resolve("  ", AIProvider.Deepseek, "deepseek-v4-flash");
            Assert.Equal(AIProviders.Endpoint(AIProvider.Deepseek), t.Endpoint);
            Assert.Equal("deepseek-v4-flash", t.Model);
        }

        // MARK: - 模板双态：显示内容决策

        [Fact]
        public void TemplateContent_ReturnsDefaultWhenUsesDefaultTrueEvenWithCustom()
            => Assert.Equal("DEFAULT", TemplateLogic.Content(usesDefault: true, custom: "custom", defaultPrompt: "DEFAULT"));

        [Fact]
        public void TemplateContent_ReturnsCustomWhenUsesDefaultFalseAndCustomSet()
            => Assert.Equal("MY", TemplateLogic.Content(usesDefault: false, custom: "MY", defaultPrompt: "DEFAULT"));

        [Fact]
        public void TemplateContent_ReturnsDefaultWhenCustomNull()
            => Assert.Equal("DEFAULT", TemplateLogic.Content(usesDefault: false, custom: null, defaultPrompt: "DEFAULT"));

        [Fact]
        public void TemplateContent_ReturnsDefaultWhenCustomEmpty()
            => Assert.Equal("DEFAULT", TemplateLogic.Content(usesDefault: false, custom: "", defaultPrompt: "DEFAULT"));

        // MARK: - 模板双态：保存决策

        [Fact]
        public void ResolveTemplateSave_KeepDefaultWhenUsesDefaultTrue()
            => Assert.Equal(TemplateSaveAction.KeepDefault, TemplateLogic.ResolveSave(usesDefault: true, content: "x"));

        [Fact]
        public void ResolveTemplateSave_SaveCustomWhenContentNonEmpty()
            => Assert.Equal(TemplateSaveAction.SaveCustom("hello"), TemplateLogic.ResolveSave(usesDefault: false, content: "hello"));

        [Fact]
        public void ResolveTemplateSave_ClearCustomWhenContentWhitespace()
            => Assert.Equal(TemplateSaveAction.ClearCustom, TemplateLogic.ResolveSave(usesDefault: false, content: "   \n "));
    }
}
