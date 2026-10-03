using System.Text.Json.Nodes;

namespace Elta.Core
{
    // MARK: - 翻译结果分类

    public enum TranslationOutcomeKind
    {
        Success,
        Failure,
        MissingKey,
        Cancelled,
    }

    /// <summary>翻译结果。MissingKey / Cancelled 不应叠加「翻译失败」提示（对齐 mac TranslationOutcome）。</summary>
    public sealed record TranslationOutcome(TranslationOutcomeKind Kind, string? Text = null)
    {
        public static TranslationOutcome Success(string text) => new(TranslationOutcomeKind.Success, text);
        public static TranslationOutcome Failure { get; } = new(TranslationOutcomeKind.Failure);
        public static TranslationOutcome MissingKey { get; } = new(TranslationOutcomeKind.MissingKey);
        public static TranslationOutcome Cancelled { get; } = new(TranslationOutcomeKind.Cancelled);
    }

    /// <summary>请求体构造与结果分类。移植自 macOS 版 TranslationEngine.chatBody / translate 判定。</summary>
    public static class TranslationLogic
    {
        public const string UserContentPrefix = "请分析以下英文文本：\n\n";

        public static string UserContent(string text) => UserContentPrefix + text;

        /// <summary>OpenAI 兼容 Chat Completions 请求体。DeepSeek V4 默认思考模式需显式关闭（mac 同款）。</summary>
        public static string BuildChatBody(AIProvider provider, string model, string systemPrompt, string text)
        {
            var messages = new JsonArray
            {
                new JsonObject { ["role"] = "system", ["content"] = systemPrompt },
                new JsonObject { ["role"] = "user", ["content"] = UserContent(text) },
            };

            var body = new JsonObject
            {
                ["model"] = model,
                ["messages"] = messages,
                ["temperature"] = 0.1,
                ["max_tokens"] = 4096,
                ["stream"] = false,
            };

            if (provider == AIProvider.Deepseek)
                body["thinking"] = new JsonObject { ["type"] = "disabled" };

            return body.ToJsonString();
        }

        /// <summary>「测试连接」用的最小请求体（mac testAPIKeyConnection 同款：单条 hi、max_tokens=1）。</summary>
        public static string BuildProbeBody(string model)
        {
            var messages = new JsonArray
            {
                new JsonObject { ["role"] = "user", ["content"] = "hi" },
            };

            var body = new JsonObject
            {
                ["model"] = model,
                ["messages"] = messages,
                ["max_tokens"] = 1,
            };

            return body.ToJsonString();
        }

        /// <summary>对齐 mac：仅 HTTP 200 且解析出内容才算成功；其余一律 Failure。</summary>
        public static TranslationOutcome Classify(int statusCode, string? parsedText)
            => statusCode == 200 && parsedText is not null
                ? TranslationOutcome.Success(parsedText)
                : TranslationOutcome.Failure;
    }
}
