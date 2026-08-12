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
}
