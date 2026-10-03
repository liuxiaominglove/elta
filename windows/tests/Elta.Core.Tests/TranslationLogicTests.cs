using System.Text.Json;
using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    public class TranslationLogicTests
    {
        // MARK: - 用户消息构造（对齐 mac TranslationEngine.translate 的 user 前缀）

        [Fact]
        public void UserContent_PrefixesInstruction()
        {
            Assert.Equal("请分析以下英文文本：\n\nHello world.", TranslationLogic.UserContent("Hello world."));
        }

        [Fact]
        public void UserContent_EmptyText_KeepsPrefix()
        {
            Assert.Equal("请分析以下英文文本：\n\n", TranslationLogic.UserContent(""));
        }

        // MARK: - Chat Completions 请求体

        [Fact]
        public void ChatBody_ContainsModelAndMessages()
        {
            string json = TranslationLogic.BuildChatBody(AIProvider.Deepseek, "deepseek-v4-flash", "SYS", "TEXT");
            using JsonDocument doc = JsonDocument.Parse(json);
            JsonElement root = doc.RootElement;

            Assert.Equal("deepseek-v4-flash", root.GetProperty("model").GetString());
            JsonElement messages = root.GetProperty("messages");
            Assert.Equal(2, messages.GetArrayLength());
            Assert.Equal("system", messages[0].GetProperty("role").GetString());
            Assert.Equal("SYS", messages[0].GetProperty("content").GetString());
            Assert.Equal("user", messages[1].GetProperty("role").GetString());
            Assert.Equal("请分析以下英文文本：\n\nTEXT", messages[1].GetProperty("content").GetString());
        }

        [Fact]
        public void ChatBody_UsesMacSamplingParams()
        {
            string json = TranslationLogic.BuildChatBody(AIProvider.Qwen, "qwen-plus", "S", "T");
            using JsonDocument doc = JsonDocument.Parse(json);

            Assert.Equal(0.1, doc.RootElement.GetProperty("temperature").GetDouble(), 3);
            Assert.Equal(4096, doc.RootElement.GetProperty("max_tokens").GetInt32());
            Assert.False(doc.RootElement.GetProperty("stream").GetBoolean());
        }

        [Fact]
        public void ChatBody_Deepseek_DisablesThinking()
        {
            string json = TranslationLogic.BuildChatBody(AIProvider.Deepseek, "m", "s", "t");
            using JsonDocument doc = JsonDocument.Parse(json);

            Assert.Equal("disabled", doc.RootElement.GetProperty("thinking").GetProperty("type").GetString());
        }

        [Fact]
        public void ChatBody_Qwen_OmitsThinking()
        {
            string json = TranslationLogic.BuildChatBody(AIProvider.Qwen, "m", "s", "t");
            using JsonDocument doc = JsonDocument.Parse(json);

            Assert.False(doc.RootElement.TryGetProperty("thinking", out _));
        }

        // MARK: - 结果分类（对齐 mac：仅 HTTP 200 且解析出文本算成功）

        [Fact]
        public void Classify_200WithText_IsSuccess()
        {
            TranslationOutcome o = TranslationLogic.Classify(200, "译文");
            Assert.Equal(TranslationOutcomeKind.Success, o.Kind);
            Assert.Equal("译文", o.Text);
        }

        [Fact]
        public void Classify_200WithoutText_IsFailure()
        {
            Assert.Equal(TranslationOutcomeKind.Failure, TranslationLogic.Classify(200, null).Kind);
        }

        [Fact]
        public void Classify_Non200_IsFailure()
        {
            Assert.Equal(TranslationOutcomeKind.Failure, TranslationLogic.Classify(401, "x").Kind);
            Assert.Equal(TranslationOutcomeKind.Failure, TranslationLogic.Classify(500, null).Kind);
        }
    }
}
