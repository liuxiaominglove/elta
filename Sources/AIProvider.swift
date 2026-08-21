import Foundation

enum AIProvider: String, CaseIterable {
    case deepseek = "deepseek"
    case qwen     = "qwen"

    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek（国内 · 推荐）"
        case .qwen:     return "千问（阿里云 · 国内）"
        }
    }

    /// 简短名称，用于翻译结果页脚
    var shortName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .qwen:     return "千问"
        }
    }

    var endpoint: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com/chat/completions"
        case .qwen:     return "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        }
    }

    var defaultModel: String {
        if let override = SettingsManager.shared.modelOverride(for: self), !override.isEmpty {
            return override
        }
        return hardcodedDefaultModel
    }

    private var hardcodedDefaultModel: String {
        switch self {
        case .deepseek: return "deepseek-v4-flash"
        case .qwen:     return "qwen-plus"
        }
    }

    /// 预设模型列表（用于下拉框）
    var availableModels: [String] {
        switch self {
        case .deepseek: return ["deepseek-v4-flash", "deepseek-v4-pro"]
        case .qwen:     return ["qwen-turbo", "qwen-plus", "qwen-max"]
        }
    }

    var registerURL: String {
        switch self {
        case .deepseek: return "platform.deepseek.com"
        case .qwen:     return "bailian.console.aliyun.com"
        }
    }
}
