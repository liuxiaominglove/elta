using System;
using System.Text.Json;

namespace Elta.Core
{
    /// <summary>
    /// 解析 AI 提供商的 JSON 响应，提取翻译文本（DeepSeek / 千问均为 OpenAI 兼容格式）。
    /// 移植自 macOS 版 Sources/ResponseParser.swift。
    /// </summary>
    public static class ResponseParser
    {
        public static string? Parse(byte[] data)
        {
            ArgumentNullException.ThrowIfNull(data);

            try
            {
                using JsonDocument doc = JsonDocument.Parse(data);
                JsonElement root = doc.RootElement;

                if (root.ValueKind != JsonValueKind.Object) return null;
                if (!root.TryGetProperty("choices", out JsonElement choices) ||
                    choices.ValueKind != JsonValueKind.Array ||
                    choices.GetArrayLength() == 0) return null;

                JsonElement first = choices[0];
                if (first.ValueKind != JsonValueKind.Object) return null;
                if (!first.TryGetProperty("message", out JsonElement message) ||
                    message.ValueKind != JsonValueKind.Object) return null;
                if (!message.TryGetProperty("content", out JsonElement content) ||
                    content.ValueKind != JsonValueKind.String) return null;

                return content.GetString();
            }
            catch (JsonException)
            {
                return null;
            }
        }
    }
}
