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

    test("gemini endpoint follows defaultModel") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.model.google_ai")
        let ep = "https://generativelanguage.googleapis.com/v1beta/models/\(AIProvider.googleAI.defaultModel):generateContent"
        try assertEqual(AIProvider.googleAI.endpoint, ep)
    }

    test("ollama endpoint is localhost") {
        try assertEqual(AIProvider.ollama.endpoint, "http://localhost:11434/v1/chat/completions")
    }

    test("deepseek defaultModel is 'deepseek-v4-flash'") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.model.deepseek")
        try assertEqual(AIProvider.deepseek.defaultModel, "deepseek-v4-flash")
    }

    test("openai defaultModel is 'gpt-4o-mini'") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.model.openai")
        try assertEqual(AIProvider.openai.defaultModel, "gpt-4o-mini")
    }

    test("gemini defaultModel is 'gemini-2.5-flash'") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.model.google_ai")
        try assertEqual(AIProvider.googleAI.defaultModel, "gemini-2.5-flash")
    }

    test("qwen defaultModel is 'qwen-plus'") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.model.qwen")
        try assertEqual(AIProvider.qwen.defaultModel, "qwen-plus")
    }

    test("anthropic defaultModel is 'claude-sonnet-4-6'") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.model.anthropic")
        try assertEqual(AIProvider.anthropic.defaultModel, "claude-sonnet-4-6")
    }

    test("deepseek availableModels are v4 flash/pro") {
        try assertEqual(AIProvider.deepseek.availableModels, ["deepseek-v4-flash", "deepseek-v4-pro"])
    }

    test("openAICompatible availableModels is nil (free input)") {
        try assertNil(AIProvider.openAICompatible.availableModels as Any?)
    }

    test("ollama availableModels is nil (free input)") {
        try assertNil(AIProvider.ollama.availableModels as Any?)
    }

    test("preset providers have non-empty availableModels containing defaultModel") {
        for p in [AIProvider.openai, .anthropic, .googleAI, .qwen] {
            let list = try assertNotNil(p.availableModels)
            try assertTrue(!list.isEmpty, "availableModels should not be empty for \(p.rawValue)")
            UserDefaults.standard.removeObject(forKey: "snaptranslate.model.\(p.rawValue)")
            try assertTrue(list.contains(p.defaultModel), "defaultModel \(p.defaultModel) should be in \(p.rawValue) availableModels")
        }
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
