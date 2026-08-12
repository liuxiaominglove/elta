import Foundation

enum AIProvider: String, CaseIterable {
    case deepseek          = "deepseek"
    case openai            = "openai"
    case anthropic         = "anthropic"
    case openAICompatible  = "openai_compatible"
    case googleAI          = "google_ai"
    case ollama            = "ollama"
    case qwen              = "qwen"

    var displayName: String {
        switch self {
        case .deepseek:          return "DeepSeek（国内 · 推荐）"
        case .openai:            return "OpenAI（国外）"
        case .anthropic:         return "Anthropic（Claude）"
        case .openAICompatible:  return "OpenAI-Compatible（自定义）"
        case .googleAI:          return "Google AI（Gemini）"
        case .ollama:            return "Ollama（本地 API）"
        case .qwen:              return "千问（阿里云 · 国内）"
        }
    }

    /// 简短名称，用于翻译结果页脚
    var shortName: String {
        switch self {
        case .deepseek:          return "DeepSeek"
        case .openai:            return "OpenAI"
        case .anthropic:         return "Anthropic"
        case .openAICompatible:  return "OpenAI-Compatible"
        case .googleAI:          return "Google AI"
        case .ollama:            return "Ollama"
        case .qwen:              return "千问"
        }
    }

    var endpoint: String {
        switch self {
        case .deepseek:          return "https://api.deepseek.com/chat/completions"
        case .openai:            return "https://api.openai.com/v1/chat/completions"
        case .anthropic:         return "https://api.anthropic.com/v1/messages"
        case .openAICompatible:  return SettingsManager.shared.customEndpoint ?? "https://your-api.com/v1/chat/completions"
        case .googleAI:          return "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
        case .ollama:            return "http://localhost:11434/v1/chat/completions"
        case .qwen:              return "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek:          return "deepseek-chat"
        case .openai:            return "gpt-4o-mini"
        case .anthropic:         return "claude-3-5-sonnet-20241022"
        case .openAICompatible:  return SettingsManager.shared.customModel ?? "gpt-3.5-turbo"
        case .googleAI:          return "gemini-2.0-flash"
        case .ollama:            return SettingsManager.shared.ollamaModel ?? "llama3.2"
        case .qwen:              return "qwen-plus"
        }
    }

    var registerURL: String {
        switch self {
        case .deepseek:          return "platform.deepseek.com"
        case .openai:            return "platform.openai.com"
        case .anthropic:         return "console.anthropic.com"
        case .openAICompatible:  return "（自定义兼容 OpenAI 接口的地址）"
        case .googleAI:          return "aistudio.google.com/apikey"
        case .ollama:            return "（本地运行，无需注册）"
        case .qwen:              return "bailian.console.aliyun.com"
        }
    }

    /// 是否需要自定义 endpoint（用户可编辑）
    var needsCustomEndpoint: Bool {
        self == .openAICompatible || self == .ollama
    }

    /// 是否需要自定义 model 名称
    var needsCustomModel: Bool {
        self == .openAICompatible || self == .ollama
    }

    /// 是否需要 API Key（Ollama 本地不需要）
    var needsAPIKey: Bool {
        self != .ollama
    }

    static func isValidEndpoint(_ urlString: String) -> Bool {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased() else { return false }

        switch scheme {
        case "https":
            return true
        case "http":
            return isPrivateOrLocalhost(url.host?.lowercased() ?? "")
        default:
            return false
        }
    }

    private static func isPrivateOrLocalhost(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host == "::1" { return true }
        if host.hasPrefix("192.168.") { return true }
        // 10.x.x.x 私有网段 — 必须为纯数字 IP，排除 10.example.com 类域名
        if host.hasPrefix("10.") {
            let tail = String(host.dropFirst(3))
            let isNumericIP = !tail.isEmpty && tail.allSatisfy { $0.isNumber || $0 == "." }
            if isNumericIP { return true }
        }
        return false
    }
}
