import Carbon
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
        // 切换弹窗位置快捷键
        static let togglePanelHotkeyKeyCode   = "snaptranslate.togglePanelHotkeyKeyCode"
        static let togglePanelHotkeyModifiers = "snaptranslate.togglePanelHotkeyModifiers"
        static let togglePanelHotkeyDisplay   = "snaptranslate.togglePanelHotkeyDisplay"
        static let customEndpoint   = "snaptranslate.customEndpoint"
        static let customModel      = "snaptranslate.customModel"
        static let ollamaModel      = "snaptranslate.ollamaModel"
        static let skipUpdateVersion = "snaptranslate.skipUpdateVersion"
    }

    private init() {
        migrateAPIKeysToKeychain()
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

    // MARK: API Keys（Keychain 安全存储）

    private static func apiKeyUDKey(for provider: AIProvider) -> String {
        "snaptranslate.apikey.\(provider.rawValue)"
    }

    func apiKey(for provider: AIProvider) -> String? {
        let result = KeychainHelper.read(account: Self.apiKeyUDKey(for: provider))
        logi("Keychain 读取: provider=\(provider.rawValue), hit=\(result != nil)")
        return result
    }

    func setApiKey(_ key: String?, for provider: AIProvider) {
        let account = Self.apiKeyUDKey(for: provider)
        if let key = key, !key.isEmpty {
            logi("Keychain 写入: provider=\(provider.rawValue), len=\(key.count)")
            _ = KeychainHelper.save(key: key, account: account)
        } else {
            logi("Keychain 删除: provider=\(provider.rawValue)")
            _ = KeychainHelper.delete(account: account)
        }
    }

    /// 当前激活的 API Key
    var activeApiKey: String? {
        apiKey(for: apiProvider)
    }

    /// 一次性迁移：将之前误存到 UserDefaults 的 API Key 迁移到 Keychain 安全存储
    private func migrateAPIKeysToKeychain() {
        let migrated = "snaptranslate.keychain_migrated_v2"
        if defaults.bool(forKey: migrated) { return }

        for provider in AIProvider.allCases {
            let udKey = Self.apiKeyUDKey(for: provider)
            if let value = defaults.string(forKey: udKey), !value.isEmpty {
                _ = KeychainHelper.save(key: value, account: udKey)
                defaults.removeObject(forKey: udKey)
                logi("迁移：\(provider.displayName) Key 从 UserDefaults → Keychain")
            }
        }
        defaults.set(true, forKey: migrated)
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

        ---
        如果原文是 Markdown 表格，请严格保持表格结构，对每个单元格独立翻译，输出同样列数的 Markdown 表格。不要合并列、不要打乱顺序，空单元格保留为空。
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

    // 切换弹窗位置快捷键（默认 ` 键，keyCode 0x32，无修饰键）
    var togglePanelHotkeyKeyCode: Int {
        get { defaults.integer(forKey: Keys.togglePanelHotkeyKeyCode) == 0 ? 0x32 : defaults.integer(forKey: Keys.togglePanelHotkeyKeyCode) }
        set { defaults.set(newValue, forKey: Keys.togglePanelHotkeyKeyCode) }
    }
    var togglePanelHotkeyModifiers: Int {
        get { defaults.integer(forKey: Keys.togglePanelHotkeyModifiers) }
        set { defaults.set(newValue, forKey: Keys.togglePanelHotkeyModifiers) }
    }
    var togglePanelHotkeyDisplay: String {
        get { defaults.string(forKey: Keys.togglePanelHotkeyDisplay) ?? "`" }
        set { defaults.set(newValue, forKey: Keys.togglePanelHotkeyDisplay) }
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

    // MARK: 更新跳过

    /// 用户选择跳过的版本号，此版本不再提醒更新
    var skipUpdateVersion: String? {
        get { defaults.string(forKey: Keys.skipUpdateVersion) }
        set { defaults.set(newValue, forKey: Keys.skipUpdateVersion) }
    }
}
