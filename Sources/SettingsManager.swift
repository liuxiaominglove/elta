import Carbon
import Foundation

import Foundation

// MARK: - 设置管理器

final class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let apiProvider      = "snaptranslate.apiProvider"
        static let prompt           = "snaptranslate.prompt"
        static let windowFrame      = "snaptranslate.windowFrame"
        static let hotkeyKeyCode    = "snaptranslate.hotkeyKeyCode"
        static let hotkeyModifiers  = "snaptranslate.hotkeyModifiers"
        static let hotkeyDisplay    = "snaptranslate.hotkeyDisplay"
        // 划词翻译快捷键
        static let selectionHotkeyKeyCode  = "snaptranslate.selectionHotkeyKeyCode"
        static let selectionHotkeyModifiers = "snaptranslate.selectionHotkeyModifiers"
        static let selectionHotkeyDisplay  = "snaptranslate.selectionHotkeyDisplay"
        // 关闭翻译面板快捷键
        static let closePanelHotkeyKeyCode   = "snaptranslate.closePanelHotkeyKeyCode"
        static let closePanelHotkeyModifiers = "snaptranslate.closePanelHotkeyModifiers"
        static let closePanelHotkeyDisplay   = "snaptranslate.closePanelHotkeyDisplay"
        static let customEndpoint   = "snaptranslate.customEndpoint"
        static let customModel      = "snaptranslate.customModel"
        static let ollamaModel      = "snaptranslate.ollamaModel"
    }

    private init() {
        migrateAPIKeysFromKeychain()
    }

    // MARK: AI 提供商

    var apiProvider: AIProvider {
        get {
            guard let raw = defaults.string(forKey: Keys.apiProvider),
                  let p = AIProvider(rawValue: raw) else { return .deepseek }
            return p
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.apiProvider) }
    }

    // MARK: API Keys（UserDefaults 存储，无感无弹窗）

    private static func apiKeyUDKey(for provider: AIProvider) -> String {
        "snaptranslate.apikey.\(provider.rawValue)"
    }

    func apiKey(for provider: AIProvider) -> String? {
        let v = defaults.string(forKey: Self.apiKeyUDKey(for: provider))
        return (v?.isEmpty == false) ? v : nil
    }

    func setApiKey(_ key: String?, for provider: AIProvider) {
        if let key = key, !key.isEmpty {
            defaults.set(key, forKey: Self.apiKeyUDKey(for: provider))
        } else {
            defaults.removeObject(forKey: Self.apiKeyUDKey(for: provider))
        }
    }

    /// 当前激活的 API Key
    var activeApiKey: String? {
        apiKey(for: apiProvider)
    }

    /// 将之前误存到 Keychain 的 API Key 迁移回 UserDefaults（不再弹授权窗）
    private func migrateAPIKeysFromKeychain() {
        let migratedBack = "snaptranslate.keychain_unmigrated"
        if defaults.bool(forKey: migratedBack) { return }

        let allProviders: [AIProvider] = [.deepseek, .openai, .openAICompatible, .ollama, .googleAI]
        for provider in allProviders {
            let account = "apikey.\(provider.rawValue)"
            if let value = KeychainHelper.read(account: account), !value.isEmpty {
                defaults.set(value, forKey: Self.apiKeyUDKey(for: provider))
                _ = KeychainHelper.delete(account: account)
                logi("反向迁移：\(provider.displayName) Key 从 Keychain → UserDefaults")
            }
        }
        defaults.set(true, forKey: migratedBack)
    }

    // MARK: 自定义配置（OpenAI-Compatible & Ollama）

    var customEndpoint: String? {
        get { defaults.string(forKey: Keys.customEndpoint) }
        set { defaults.set(newValue, forKey: Keys.customEndpoint) }
    }

    var customModel: String? {
        get { defaults.string(forKey: Keys.customModel) }
        set { defaults.set(newValue, forKey: Keys.customModel) }
    }

    var ollamaModel: String? {
        get { defaults.string(forKey: Keys.ollamaModel) }
        set { defaults.set(newValue, forKey: Keys.ollamaModel) }
    }

    // 旧版兼容：迁移旧的单一 apiKey → deepseek
    var apiKey: String? {
        get { activeApiKey }
        set { setApiKey(newValue, for: .deepseek) }
    }

    var systemPrompt: String {
        get {
            if let saved = defaults.string(forKey: Keys.prompt), !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return saved
            }
            return defaultPrompt
        }
        set { defaults.set(newValue, forKey: Keys.prompt) }
    }

    /// 用户可编辑的默认翻译模板
    var defaultPrompt: String {
        """
        我会给你一段英文文本。请你按以下结构输出：

        ## 中文翻译
        （遵循"信达雅"原则，自然流畅的中文翻译）

        ## 重要词汇
        - **单词** ｜ 词性 ｜ 中文释义
        （列出句中较重要的词汇，跳过高中大纲基础词汇）

        ## 常用短语与习语
        - 短语 / 习语：中文释义
        （习语请标注【习语】）

        ## 核查
        核实翻译是否准确、通顺，无遗漏。
        """
    }

    // MARK: 快捷键

    var hotkeyKeyCode: Int {
        get { defaults.integer(forKey: Keys.hotkeyKeyCode) == 0 ? DEFAULT_HOTKEY_KEYCODE : defaults.integer(forKey: Keys.hotkeyKeyCode) }
        set { defaults.set(newValue, forKey: Keys.hotkeyKeyCode) }
    }

    var hotkeyModifiers: Int {
        get {
            let v = defaults.integer(forKey: Keys.hotkeyModifiers)
            return v == 0 ? Int(controlKey) : v
        }
        set { defaults.set(newValue, forKey: Keys.hotkeyModifiers) }
    }

    /// 快捷键的可读描述（如 "⌃T"）
    var hotkeyDisplay: String {
        get { defaults.string(forKey: Keys.hotkeyDisplay) ?? "⌃T" }
        set { defaults.set(newValue, forKey: Keys.hotkeyDisplay) }
    }

    // 划词翻译快捷键
    var selectionHotkeyKeyCode: Int {
        get { defaults.integer(forKey: Keys.selectionHotkeyKeyCode) == 0 ? DEFAULT_SELECTION_HOTKEY_KEYCODE : defaults.integer(forKey: Keys.selectionHotkeyKeyCode) }
        set { defaults.set(newValue, forKey: Keys.selectionHotkeyKeyCode) }
    }
    var selectionHotkeyModifiers: Int {
        get { defaults.integer(forKey: Keys.selectionHotkeyModifiers) == 0 ? Int(controlKey | shiftKey) : defaults.integer(forKey: Keys.selectionHotkeyModifiers) }
        set { defaults.set(newValue, forKey: Keys.selectionHotkeyModifiers) }
    }
    var selectionHotkeyDisplay: String {
        get { defaults.string(forKey: Keys.selectionHotkeyDisplay) ?? "⇧⌃T" }
        set { defaults.set(newValue, forKey: Keys.selectionHotkeyDisplay) }
    }

    // 关闭翻译面板快捷键（默认 ESC，keyCode 0x35，无修饰键）
    var closePanelHotkeyKeyCode: Int {
        get { defaults.integer(forKey: Keys.closePanelHotkeyKeyCode) == 0 ? 0x35 : defaults.integer(forKey: Keys.closePanelHotkeyKeyCode) }
        set { defaults.set(newValue, forKey: Keys.closePanelHotkeyKeyCode) }
    }
    var closePanelHotkeyModifiers: Int {
        get { defaults.integer(forKey: Keys.closePanelHotkeyModifiers) }
        set { defaults.set(newValue, forKey: Keys.closePanelHotkeyModifiers) }
    }
    var closePanelHotkeyDisplay: String {
        get { defaults.string(forKey: Keys.closePanelHotkeyDisplay) ?? "Esc" }
        set { defaults.set(newValue, forKey: Keys.closePanelHotkeyDisplay) }
    }

    // MARK: 窗口

    var windowFrame: NSRect? {
        get {
            guard let s = defaults.string(forKey: Keys.windowFrame) else { return nil }
            return NSRectFromString(s)
        }
        set {
            if let f = newValue { defaults.set(NSStringFromRect(f), forKey: Keys.windowFrame) }
            else { defaults.removeObject(forKey: Keys.windowFrame) }
        }
    }
}
