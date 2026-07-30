import Foundation

func runAIProviderTests() {
    print("\n--- AIProvider Tests ---")

    test("allCases contains all 7 providers") {
        let cases = AIProvider.allCases
        try assertEqual(cases.count, 7)
    }

    test("deepseek displayName is correct") {
        try assertEqual(AIProvider.deepseek.displayName, "DeepSeek（国内 · 推荐）")
    }

    test("openai displayName is correct") {
        try assertEqual(AIProvider.openai.displayName, "OpenAI（国外）")
    }

    test("anthropic displayName is correct") {
        try assertEqual(AIProvider.anthropic.displayName, "Anthropic（Claude）")
    }

    test("ollama displayName is correct") {
        try assertEqual(AIProvider.ollama.displayName, "Ollama（本地 API）")
    }

    test("deepseek shortName is correct") {
        try assertEqual(AIProvider.deepseek.shortName, "DeepSeek")
    }

    test("openai endpoint is correct") {
        try assertEqual(AIProvider.openai.endpoint, "https://api.openai.com/v1/chat/completions")
    }

    test("deepseek endpoint is correct") {
        try assertEqual(AIProvider.deepseek.endpoint, "https://api.deepseek.com/chat/completions")
    }

    test("gemini endpoint is correct") {
        let ep = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
        try assertEqual(AIProvider.googleAI.endpoint, ep)
    }

    test("ollama endpoint is localhost") {
        try assertEqual(AIProvider.ollama.endpoint, "http://localhost:11434/v1/chat/completions")
    }

    test("deepseek defaultModel is 'deepseek-chat'") {
        try assertEqual(AIProvider.deepseek.defaultModel, "deepseek-chat")
    }

    test("openai defaultModel is 'gpt-4o-mini'") {
        try assertEqual(AIProvider.openai.defaultModel, "gpt-4o-mini")
    }

    test("gemini defaultModel is 'gemini-2.0-flash'") {
        try assertEqual(AIProvider.googleAI.defaultModel, "gemini-2.0-flash")
    }

    test("qwen defaultModel is 'qwen-plus'") {
        try assertEqual(AIProvider.qwen.defaultModel, "qwen-plus")
    }

    test("deepseek registerURL is correct") {
        try assertEqual(AIProvider.deepseek.registerURL, "platform.deepseek.com")
    }

    test("openai registerURL is correct") {
        try assertEqual(AIProvider.openai.registerURL, "platform.openai.com")
    }

    test("needsCustomEndpoint: openAICompatible needs custom") {
        try assertTrue(AIProvider.openAICompatible.needsCustomEndpoint)
    }

    test("needsCustomEndpoint: ollama needs custom") {
        try assertTrue(AIProvider.ollama.needsCustomEndpoint)
    }

    test("needsCustomEndpoint: deepseek does not need custom") {
        try assertFalse(AIProvider.deepseek.needsCustomEndpoint)
    }

    test("needsCustomEndpoint: openai does not need custom") {
        try assertFalse(AIProvider.openai.needsCustomEndpoint)
    }

    test("needsCustomModel: openAICompatible needs custom model") {
        try assertTrue(AIProvider.openAICompatible.needsCustomModel)
    }

    test("needsCustomModel: ollama needs custom model") {
        try assertTrue(AIProvider.ollama.needsCustomModel)
    }

    test("needsAPIKey: ollama does not need API key") {
        try assertFalse(AIProvider.ollama.needsAPIKey)
    }

    test("needsAPIKey: deepseek needs API key") {
        try assertTrue(AIProvider.deepseek.needsAPIKey)
    }

    test("needsAPIKey: openai needs API key") {
        try assertTrue(AIProvider.openai.needsAPIKey)
    }

    test("rawValue roundtrip for all providers") {
        for provider in AIProvider.allCases {
            let reconstructed = AIProvider(rawValue: provider.rawValue)
            try assertEqual(reconstructed, provider)
        }
    }

    test("all displayNames are non-empty") {
        for provider in AIProvider.allCases {
            try assertTrue(!provider.displayName.isEmpty, "displayName should not be empty for \(provider.rawValue)")
        }
    }

    test("all shortNames are non-empty") {
        for provider in AIProvider.allCases {
            try assertTrue(!provider.shortName.isEmpty, "shortName should not be empty for \(provider.rawValue)")
        }
    }
}
