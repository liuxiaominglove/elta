import Carbon
import Foundation

// MARK: - 设置管理器

/// 悬停翻译内容范围
enum HoverLayoutMode: String {
    case halfColumn  // 双栏（同屏双页，水平取半屏宽）
    case fullWidth   // 整栏（全屏单栏，水平取整屏宽）
}

final class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard
    private let lock = NSLock()
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
        // 悬停翻译快捷键（免截图/划词）
        static let hoverHotkeyKeyCode  = "snaptranslate.hoverHotkeyKeyCode"
        static let hoverHotkeyModifiers = "snaptranslate.hoverHotkeyModifiers"
        static let hoverHotkeyDisplay  = "snaptranslate.hoverHotkeyDisplay"
        // 悬停翻译内容范围（双栏 / 整栏）
        static let hoverLayoutMode     = "snaptranslate.hoverLayoutMode"
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
            lock.lock(); defer { lock.unlock() }
            guard let raw = defaults.string(forKey: Keys.apiProvider),
                  let p = AIProvider(rawValue: raw) else { return .deepseek }
            return p
        }
        set {
            lock.lock()
            defaults.set(newValue.rawValue, forKey: Keys.apiProvider)
            lock.unlock()
        }
    }

    // MARK: API Keys（Keychain 安全存储）

    private static func apiKeyUDKey(for provider: AIProvider) -> String {
        "snaptranslate.apikey.\(provider.rawValue)"
    }

    func apiKey(for provider: AIProvider) -> String? {
        let account = Self.apiKeyUDKey(for: provider)
        if let result = KeychainHelper.read(account: account) {
            logi("Keychain 读取: provider=\(provider.rawValue), hit=true")
            return result
        }
        logi("Keychain 读取: provider=\(provider.rawValue), hit=false, fallback to UserDefaults")
        return defaults.string(forKey: account)
    }

    func setApiKey(_ key: String?, for provider: AIProvider) {
        let account = Self.apiKeyUDKey(for: provider)
        if let key = key, !key.isEmpty {
            logi("Keychain 写入: provider=\(provider.rawValue), len=\(key.count)")
            let ok = KeychainHelper.save(key: key, account: account)
            if ok {
                defaults.removeObject(forKey: account)
            } else {
                logi("Keychain 写入失败: provider=\(provider.rawValue)")
            }
        } else {
            logi("Keychain 删除: provider=\(provider.rawValue)")
            _ = KeychainHelper.delete(account: account)
            defaults.removeObject(forKey: account)
        }
    }

    /// 当前激活的 API Key（线程安全：一次锁定读取 provider + key）
    var activeApiKey: String? {
        lock.lock(); defer { lock.unlock() }
        return _apiKeyUnlocked(for: _apiProviderUnlocked())
    }

    private func _apiProviderUnlocked() -> AIProvider {
        guard let raw = defaults.string(forKey: Keys.apiProvider),
              let p = AIProvider(rawValue: raw) else { return .deepseek }
        return p
    }

    private func _apiKeyUnlocked(for provider: AIProvider) -> String? {
        let account = Self.apiKeyUDKey(for: provider)
        if let result = KeychainHelper.read(account: account) { return result }
        return defaults.string(forKey: account)
    }

    /// 迁移单个 provider：save 成功才移除 UserDefaults 明文，避免 Keychain 写失败丢 key。
    /// 返回 save 是否成功，供调用方判断迁移是否全部完成（失败则不标记已迁移，下次启动重试）。
    @discardableResult
    static func migrateKey(value: String, udKey: String, save: (String, String) -> Bool, remove: () -> Void) -> Bool {
        let ok = save(value, udKey)
        if ok {
            remove()
        }
        return ok
    }

    /// 一次性迁移：将之前误存到 UserDefaults 的 API Key 迁移到 Keychain 安全存储
    private func migrateAPIKeysToKeychain() {
        let migrated = "snaptranslate.keychain_migrated_v2"
        if defaults.bool(forKey: migrated) { return }

        var allMigrated = true
        for provider in AIProvider.allCases {
            let udKey = Self.apiKeyUDKey(for: provider)
            if let value = defaults.string(forKey: udKey), !value.isEmpty {
                let ok = Self.migrateKey(value: value, udKey: udKey, save: { KeychainHelper.save(key: $0, account: $1) }, remove: {
                    self.defaults.removeObject(forKey: udKey)
                    logi("迁移：\(provider.displayName) Key 从 UserDefaults → Keychain")
                })
                if !ok {
                    logi("迁移失败：\(provider.displayName) Key 保留在 UserDefaults，下次启动重试")
                    allMigrated = false
                }
            }
        }
        // 仅当全部迁移成功才标记，避免写失败的明文 Key 因 flag 而永久留在 UserDefaults
        if allMigrated {
            defaults.set(true, forKey: migrated)
        }
    }

    // MARK: 自定义配置（OpenAI-Compatible & Ollama）

    var customEndpoint: String? {
        get {
            lock.lock(); defer { lock.unlock() }
            return defaults.string(forKey: Keys.customEndpoint)
        }
        set {
            lock.lock()
            defaults.set(newValue, forKey: Keys.customEndpoint)
            lock.unlock()
        }
    }

    var customModel: String? {
        get {
            lock.lock(); defer { lock.unlock() }
            return defaults.string(forKey: Keys.customModel)
        }
        set {
            lock.lock()
            defaults.set(newValue, forKey: Keys.customModel)
            lock.unlock()
        }
    }

    var ollamaModel: String? {
        get {
            lock.lock(); defer { lock.unlock() }
            return defaults.string(forKey: Keys.ollamaModel)
        }
        set {
            lock.lock()
            defaults.set(newValue, forKey: Keys.ollamaModel)
            lock.unlock()
        }
    }

    // 旧版兼容：迁移旧的单一 apiKey → deepseek
    var apiKey: String? {
        get { activeApiKey }
        set { setApiKey(newValue, for: .deepseek) }
    }

    var systemPrompt: String {
        get {
            lock.lock(); defer { lock.unlock() }
            if let saved = defaults.string(forKey: Keys.prompt), !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return saved
            }
            return defaultPrompt
        }
        set {
            lock.lock()
            defaults.set(newValue, forKey: Keys.prompt)
            lock.unlock()
        }
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
        get {
            lock.lock(); defer { lock.unlock() }
            return defaults.object(forKey: Keys.hotkeyKeyCode) as? Int ?? DEFAULT_HOTKEY_KEYCODE
        }
        set {
            lock.lock()
            defaults.set(newValue, forKey: Keys.hotkeyKeyCode)
            lock.unlock()
        }
    }

    var hotkeyModifiers: Int {
        get {
            lock.lock(); defer { lock.unlock() }
            return defaults.object(forKey: Keys.hotkeyModifiers) as? Int ?? Int(controlKey)
        }
        set {
            lock.lock()
            defaults.set(newValue, forKey: Keys.hotkeyModifiers)
            lock.unlock()
        }
    }

    /// 快捷键的可读描述（如 "⌃T"）
    var hotkeyDisplay: String {
        get { defaults.string(forKey: Keys.hotkeyDisplay) ?? "⌃T" }
        set { defaults.set(newValue, forKey: Keys.hotkeyDisplay) }
    }

    // 划词翻译快捷键
    var selectionHotkeyKeyCode: Int {
        get { defaults.object(forKey: Keys.selectionHotkeyKeyCode) as? Int ?? DEFAULT_SELECTION_HOTKEY_KEYCODE }
        set { defaults.set(newValue, forKey: Keys.selectionHotkeyKeyCode) }
    }
    var selectionHotkeyModifiers: Int {
        get { defaults.object(forKey: Keys.selectionHotkeyModifiers) as? Int ?? Int(controlKey | shiftKey) }
        set { defaults.set(newValue, forKey: Keys.selectionHotkeyModifiers) }
    }
    var selectionHotkeyDisplay: String {
        get { defaults.string(forKey: Keys.selectionHotkeyDisplay) ?? "⇧⌃T" }
        set { defaults.set(newValue, forKey: Keys.selectionHotkeyDisplay) }
    }

    // 悬停翻译快捷键（默认 ⌥⌘T）
    var hoverHotkeyKeyCode: Int {
        get { defaults.object(forKey: Keys.hoverHotkeyKeyCode) as? Int ?? DEFAULT_HOVER_HOTKEY_KEYCODE }
        set { defaults.set(newValue, forKey: Keys.hoverHotkeyKeyCode) }
    }
    var hoverHotkeyModifiers: Int {
        get { defaults.object(forKey: Keys.hoverHotkeyModifiers) as? Int ?? Int(cmdKey | optionKey) }
        set { defaults.set(newValue, forKey: Keys.hoverHotkeyModifiers) }
    }
    var hoverHotkeyDisplay: String {
        get { defaults.string(forKey: Keys.hoverHotkeyDisplay) ?? "⌥⌘T" }
        set { defaults.set(newValue, forKey: Keys.hoverHotkeyDisplay) }
    }

    // 悬停翻译内容范围（默认双栏）
    var hoverLayoutMode: HoverLayoutMode {
        get {
            lock.lock(); defer { lock.unlock() }
            guard let raw = defaults.string(forKey: Keys.hoverLayoutMode),
                  let m = HoverLayoutMode(rawValue: raw) else { return .halfColumn }
            return m
        }
        set {
            lock.lock()
            defaults.set(newValue.rawValue, forKey: Keys.hoverLayoutMode)
            lock.unlock()
        }
    }

    // 关闭翻译面板快捷键（默认 ESC，keyCode 0x35，无修饰键）
    var closePanelHotkeyKeyCode: Int {
        get {
            lock.lock(); defer { lock.unlock() }
            return defaults.object(forKey: Keys.closePanelHotkeyKeyCode) as? Int ?? 0x35
        }
        set {
            lock.lock()
            defaults.set(newValue, forKey: Keys.closePanelHotkeyKeyCode)
            lock.unlock()
        }
    }
    var closePanelHotkeyModifiers: Int {
        get {
            lock.lock(); defer { lock.unlock() }
            return defaults.integer(forKey: Keys.closePanelHotkeyModifiers)
        }
        set {
            lock.lock()
            defaults.set(newValue, forKey: Keys.closePanelHotkeyModifiers)
            lock.unlock()
        }
    }
    var closePanelHotkeyDisplay: String {
        get { defaults.string(forKey: Keys.closePanelHotkeyDisplay) ?? "Esc" }
        set { defaults.set(newValue, forKey: Keys.closePanelHotkeyDisplay) }
    }

    // 切换弹窗位置快捷键（默认 ` 键，keyCode 0x32，无修饰键）
    var togglePanelHotkeyKeyCode: Int {
        get {
            lock.lock(); defer { lock.unlock() }
            return defaults.object(forKey: Keys.togglePanelHotkeyKeyCode) as? Int ?? 0x32
        }
        set {
            lock.lock()
            defaults.set(newValue, forKey: Keys.togglePanelHotkeyKeyCode)
            lock.unlock()
        }
    }
    var togglePanelHotkeyModifiers: Int {
        get {
            lock.lock(); defer { lock.unlock() }
            return defaults.integer(forKey: Keys.togglePanelHotkeyModifiers)
        }
        set {
            lock.lock()
            defaults.set(newValue, forKey: Keys.togglePanelHotkeyModifiers)
            lock.unlock()
        }
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
