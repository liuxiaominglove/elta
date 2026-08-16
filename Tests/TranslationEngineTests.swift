import Foundation

func runTranslationEngineTests() {
    print("\n--- TranslationEngine Tests ---")

    test("parseOpenAIResponse extracts content correctly") {
        let json = """
        {"choices":[{"message":{"content":"这是翻译结果"}}]}
        """
        let data = json.data(using: .utf8)!
        let result = ResponseParser.parse(data: data, provider: .deepseek)
        try assertEqual(result, "这是翻译结果")
    }

    test("parseOpenAIResponse returns nil on empty choices") {
        let json = """
        {"choices":[]}
        """
        let data = json.data(using: .utf8)!
        let result = ResponseParser.parse(data: data, provider: .openai)
        try assertNil(result as Any?)
    }

    test("parseOpenAIResponse handles nil content") {
        let json = """
        {"choices":[{"message":{}}]}
        """
        let data = json.data(using: .utf8)!
        let result = ResponseParser.parse(data: data, provider: .qwen)
        try assertNil(result as Any?)
    }

    test("parseAnthropicResponse extracts text") {
        let json = """
        {"content":[{"type":"text","text":"Anthrophic 翻译"}]}
        """
        let data = json.data(using: .utf8)!
        let result = ResponseParser.parse(data: data, provider: .anthropic)
        try assertEqual(result, "Anthrophic 翻译")
    }

    test("parseGeminiResponse extracts text") {
        let json = """
        {"candidates":[{"content":{"parts":[{"text":"Gemini 翻译"}]}}]}
        """
        let data = json.data(using: .utf8)!
        let result = ResponseParser.parse(data: data, provider: .googleAI)
        try assertEqual(result, "Gemini 翻译")
    }

    test("parseResponse returns nil on invalid JSON") {
        let data = "not json".data(using: .utf8)!
        let result = ResponseParser.parse(data: data, provider: .deepseek)
        try assertNil(result as Any?)
    }

    // ━━━ 修复：DeepSeek V4 默认思考模式导致翻译慢，需显式关闭 ━━━

    test("chatBody includes thinking=disabled for deepseek") {
        let body = TranslationEngine.chatBody(provider: .deepseek, model: "deepseek-v4-flash", messages: [["role": "user", "content": "hi"]])
        let thinking = body["thinking"] as? [String: Any]
        try assertEqual(thinking?["type"] as? String, "disabled")
    }

    test("chatBody omits thinking for openai") {
        let body = TranslationEngine.chatBody(provider: .openai, model: "gpt-4o-mini", messages: [["role": "user", "content": "hi"]])
        try assertNil(body["thinking"] as Any?)
    }

    test("chatBody omits thinking for qwen") {
        let body = TranslationEngine.chatBody(provider: .qwen, model: "qwen-plus", messages: [["role": "user", "content": "hi"]])
        try assertNil(body["thinking"] as Any?)
    }

    test("chatBody carries model/temperature/max_tokens/stream") {
        let body = TranslationEngine.chatBody(provider: .deepseek, model: "m", messages: [["role": "user", "content": "hi"]])
        try assertEqual(body["model"] as? String, "m")
        try assertEqual(body["temperature"] as? Double, 0.1)
        try assertEqual(body["max_tokens"] as? Int, 4096)
        try assertEqual(body["stream"] as? Bool, false)
    }
}
