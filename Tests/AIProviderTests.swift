import Foundation

func runAIProviderTests() {
    print("\n--- AIProvider Tests ---")

    test("allCases contains 2 providers") {
        let cases = AIProvider.allCases
        try assertEqual(cases.count, 2)
    }

    test("deepseek displayName is correct") {
        try assertEqual(AIProvider.deepseek.displayName, "DeepSeek（国内 · 推荐）")
    }

    test("qwen displayName is correct") {
        try assertEqual(AIProvider.qwen.displayName, "千问（阿里云 · 国内）")
    }

    test("deepseek shortName is correct") {
        try assertEqual(AIProvider.deepseek.shortName, "DeepSeek")
    }

    test("qwen shortName is correct") {
        try assertEqual(AIProvider.qwen.shortName, "千问")
    }

    test("deepseek endpoint is correct") {
        try assertEqual(AIProvider.deepseek.endpoint, "https://api.deepseek.com/chat/completions")
    }

    test("qwen endpoint is correct") {
        try assertEqual(AIProvider.qwen.endpoint, "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
    }

    test("deepseek defaultModel is 'deepseek-v4-flash'") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.model.deepseek")
        try assertEqual(AIProvider.deepseek.defaultModel, "deepseek-v4-flash")
    }

    test("qwen defaultModel is 'qwen-plus'") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.model.qwen")
        try assertEqual(AIProvider.qwen.defaultModel, "qwen-plus")
    }

    test("deepseek availableModels are v4 flash/pro") {
        try assertEqual(AIProvider.deepseek.availableModels, ["deepseek-v4-flash", "deepseek-v4-pro"])
    }

    test("qwen availableModels are turbo/plus/max") {
        try assertEqual(AIProvider.qwen.availableModels, ["qwen-turbo", "qwen-plus", "qwen-max"])
    }

    test("providers have non-empty availableModels containing defaultModel") {
        for p in [AIProvider.deepseek, .qwen] {
            let list = p.availableModels
            try assertTrue(!list.isEmpty, "availableModels should not be empty for \(p.rawValue)")
            UserDefaults.standard.removeObject(forKey: "snaptranslate.model.\(p.rawValue)")
            try assertTrue(list.contains(p.defaultModel), "defaultModel \(p.defaultModel) should be in \(p.rawValue) availableModels")
        }
    }

    test("deepseek registerURL is correct") {
        try assertEqual(AIProvider.deepseek.registerURL, "platform.deepseek.com")
    }

    test("qwen registerURL is correct") {
        try assertEqual(AIProvider.qwen.registerURL, "bailian.console.aliyun.com")
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
