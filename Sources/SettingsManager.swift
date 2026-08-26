import Carbon
import Foundation

// MARK: - 设置管理器

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
        // 关闭翻译面板快捷键
        static let closePanelHotkeyKeyCode   = "snaptranslate.closePanelHotkeyKeyCode"
        static let closePanelHotkeyModifiers = "snaptranslate.closePanelHotkeyModifiers"
        static let closePanelHotkeyDisplay   = "snaptranslate.closePanelHotkeyDisplay"
        // 切换弹窗位置快捷键
        static let togglePanelHotkeyKeyCode   = "snaptranslate.togglePanelHotkeyKeyCode"
        static let togglePanelHotkeyModifiers = "snaptranslate.togglePanelHotkeyModifiers"
        static let togglePanelHotkeyDisplay   = "snaptranslate.togglePanelHotkeyDisplay"
        // 拆分翻译快捷键（弹窗内整段/拆分切换）
        static let splitHotkeyKeyCode   = "snaptranslate.splitHotkeyKeyCode"
        static let splitHotkeyModifiers = "snaptranslate.splitHotkeyModifiers"
        static let splitHotkeyDisplay   = "snaptranslate.splitHotkeyDisplay"
        // 默认优先弹窗模式（true=拆分，false=整段；默认拆分）
        static let defaultSplitMode = "snaptranslate.defaultSplitMode"
        static let skipUpdateVersion = "snaptranslate.skipUpdateVersion"
        static let installID = "snaptranslate.installID"
        static let telemetryEnabled = "snaptranslate.telemetryEnabled"
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

    @discardableResult
    func setApiKey(_ key: String?, for provider: AIProvider) -> Bool {
        let account = Self.apiKeyUDKey(for: provider)
        if let key = key, !key.isEmpty {
            logi("Keychain 写入: provider=\(provider.rawValue), len=\(key.count)")
            let ok = KeychainHelper.save(key: key, account: account)
            if ok {
                defaults.removeObject(forKey: account)
                return true
            } else {
                loge("Keychain 写入失败: provider=\(provider.rawValue) — 新 key 未被保存，旧 key 仍生效")
                return false
            }
        } else {
            logi("Keychain 删除: provider=\(provider.rawValue)")
            let deleted = KeychainHelper.delete(account: account)
            defaults.removeObject(forKey: account)
            if !deleted {
                loge("Keychain 删除失败: provider=\(provider.rawValue) — 旧 key 可能仍残留")
            }
            return deleted
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

    // MARK: 模型选择（所有 provider 统一）

    private static func modelOverrideUDKey(for provider: AIProvider) -> String {
        "snaptranslate.model.\(provider.rawValue)"
    }

    func modelOverride(for provider: AIProvider) -> String? {
        lock.lock(); defer { lock.unlock() }
        return defaults.string(forKey: Self.modelOverrideUDKey(for: provider))
    }

    func setModelOverride(_ value: String?, for provider: AIProvider) {
        lock.lock()
        if let v = value, !v.isEmpty {
            defaults.set(v, forKey: Self.modelOverrideUDKey(for: provider))
        } else {
            defaults.removeObject(forKey: Self.modelOverrideUDKey(for: provider))
        }
        lock.unlock()
    }

    // MARK: 旧版兼容：迁移旧的单一 apiKey → deepseek
    // 注：旧 `apiKey` 读写不一致（getter 返回当前 provider 的 key、setter 写死 deepseek），且已无调用方，故移除。

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
        单词：音标 ｜ 词性 ｜ 中文释义
        （列出句中较重要的词汇，跳过高中大纲基础词汇）

        ## 常用短语与习语
        短语 / 习语：中文释义
        （习语请标注【习语】）
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

    // 拆分翻译快捷键（默认 ⌃D，keyCode 0x02）
    var splitHotkeyKeyCode: Int {
        get {
            lock.lock(); defer { lock.unlock() }
            return defaults.object(forKey: Keys.splitHotkeyKeyCode) as? Int ?? DEFAULT_SPLIT_HOTKEY_KEYCODE
        }
        set {
            lock.lock()
            defaults.set(newValue, forKey: Keys.splitHotkeyKeyCode)
            lock.unlock()
        }
    }
    var splitHotkeyModifiers: Int {
        get {
            lock.lock(); defer { lock.unlock() }
            return defaults.object(forKey: Keys.splitHotkeyModifiers) as? Int ?? Int(controlKey)
        }
        set {
            lock.lock()
            defaults.set(newValue, forKey: Keys.splitHotkeyModifiers)
            lock.unlock()
        }
    }
    var splitHotkeyDisplay: String {
        get { defaults.string(forKey: Keys.splitHotkeyDisplay) ?? "⌃D" }
        set { defaults.set(newValue, forKey: Keys.splitHotkeyDisplay) }
    }

    /// 弹窗默认优先模式：true=拆分，false=整段（默认拆分）
    var defaultSplitMode: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            if defaults.object(forKey: Keys.defaultSplitMode) == nil { return true }
            return defaults.bool(forKey: Keys.defaultSplitMode)
        }
        set {
            lock.lock()
            defaults.set(newValue, forKey: Keys.defaultSplitMode)
            lock.unlock()
        }
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

    // MARK: 匿名使用统计

    /// 匿名安装标识：首次读取时生成随机 UUID 并持久化，不含任何设备/个人信息。
    var installID: String {
        get {
            lock.lock(); defer { lock.unlock() }
            if let existing = defaults.string(forKey: Keys.installID), !existing.isEmpty {
                return existing
            }
            let id = UUID().uuidString
            defaults.set(id, forKey: Keys.installID)
            return id
        }
    }

    /// 是否参与匿名使用统计（默认开启；关闭时更新检查不再附带 installID）。
    var telemetryEnabled: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            if defaults.object(forKey: Keys.telemetryEnabled) == nil { return true }
            return defaults.bool(forKey: Keys.telemetryEnabled)
        }
        set {
            lock.lock()
            defaults.set(newValue, forKey: Keys.telemetryEnabled)
            lock.unlock()
        }
    }
}
