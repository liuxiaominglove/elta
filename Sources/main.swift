import Cocoa
import Carbon
import WebKit
import Vision
import UserNotifications
import Security
import ApplicationServices

// ============================================
// ELTA — 英语精读截图翻译助手
// 架构：菜单栏应用 → 屏幕快照选区 → OCR → AI 翻译 → 浮动结果面板
// 版本：编译时从 Info.plist 读取，无需手动同步
// ============================================

// MARK: - 全局常量

let APP_NAME          = "ELTA"
let APP_DISPLAY_NAME  = "ELTA"
let LOG_PATH          = "\(NSHomeDirectory())/Library/Logs/snaptranslate.log"
let DEFAULT_HOTKEY_KEYCODE: Int = 0x11  // T
let DEFAULT_SELECTION_HOTKEY_KEYCODE: Int = 0x11  // T（配合 Shift）

// 运行时从 Info.plist 读取版本号（每次编译/打包时自动同步）
let APP_SHORT_VERSION: String = {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "5.1"
}()
let APP_BUILD_VERSION: String = {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
}()
let APP_FULL_VERSION: String = "\(APP_SHORT_VERSION) (\(APP_BUILD_VERSION))"

// MARK: AI 提供商配置
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
}

// 绕过 Swift SDK 的 API 弃用标记，直接调用底层 C 函数
@_silgen_name("CGDisplayCreateImage")
func CGDisplayCaptureFull(_ display: CGDirectDisplayID) -> CGImage?

@_silgen_name("CGDisplayCreateImageForRect")
func CGDisplayCapture(_ display: CGDirectDisplayID, _ rect: CGRect) -> CGImage?

// MARK: - 可粘贴输入框（修复 .accessory 应用缺少 Edit 菜单导致 Cmd+V 无效）

class PasteTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard f == .command else { return super.performKeyEquivalent(with: event) }

        let sel: Selector?
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v": sel = #selector(NSText.paste(_:))
        case "c": sel = #selector(NSText.copy(_:))
        case "x": sel = #selector(NSText.cut(_:))
        case "a": sel = #selector(NSText.selectAll(_:))
        default:  sel = nil
        }
        guard let s = sel else { return super.performKeyEquivalent(with: event) }
        if NSApp.sendAction(s, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Logger

final class Logger {
    static let shared = Logger()
    private let handle: FileHandle?
    private let queue = DispatchQueue(label: "snaptranslate.logger")

    private init() {
        if !FileManager.default.fileExists(atPath: LOG_PATH) {
            FileManager.default.createFile(atPath: LOG_PATH, contents: nil)
        }
        handle = FileHandle(forUpdatingAtPath: LOG_PATH)
        handle?.seekToEndOfFile()
    }

    func info(_ msg: String) {
        let line = "[INFO] \(formattedTime()) \(msg)\n"
        queue.async { [weak self] in
            if let d = line.data(using: .utf8) { self?.handle?.write(d) }
        }
        print(line, terminator: "")
        fflush(stdout)
    }

    func error(_ msg: String) {
        let line = "[ERROR] \(formattedTime()) \(msg)\n"
        queue.async { [weak self] in
            if let d = line.data(using: .utf8) { self?.handle?.write(d) }
        }
        print(line, terminator: "")
        fflush(stdout)
    }

    private func formattedTime() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}

let logi = Logger.shared.info
let loge = Logger.shared.error

logi("===== \(APP_DISPLAY_NAME) \(APP_FULL_VERSION) 启动 =====")

// MARK: - Keychain 安全存储

struct KeychainHelper {
    static let service = "com.elta.snaptranslate"

    static func save(key: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary) // 先删旧值
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

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
            return v == 0 ? Int(cmdKey) : v
        }
        set { defaults.set(newValue, forKey: Keys.hotkeyModifiers) }
    }

    /// 快捷键的可读描述（如 "⌘T"）
    var hotkeyDisplay: String {
        get { defaults.string(forKey: Keys.hotkeyDisplay) ?? "⌘T" }
        set { defaults.set(newValue, forKey: Keys.hotkeyDisplay) }
    }

    // 划词翻译快捷键
    var selectionHotkeyKeyCode: Int {
        get { defaults.integer(forKey: Keys.selectionHotkeyKeyCode) == 0 ? DEFAULT_SELECTION_HOTKEY_KEYCODE : defaults.integer(forKey: Keys.selectionHotkeyKeyCode) }
        set { defaults.set(newValue, forKey: Keys.selectionHotkeyKeyCode) }
    }
    var selectionHotkeyModifiers: Int {
        get { defaults.integer(forKey: Keys.selectionHotkeyModifiers) == 0 ? Int(cmdKey | shiftKey) : defaults.integer(forKey: Keys.selectionHotkeyModifiers) }
        set { defaults.set(newValue, forKey: Keys.selectionHotkeyModifiers) }
    }
    var selectionHotkeyDisplay: String {
        get { defaults.string(forKey: Keys.selectionHotkeyDisplay) ?? "⇧⌘T" }
        set { defaults.set(newValue, forKey: Keys.selectionHotkeyDisplay) }
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

// MARK: - 快捷键辅助

/// 将 Carbon 修饰键掩码转为可读字符串（如 "⌘⌥F1"）
func hotkeyDisplayString(keyCode: Int, modifiers: Int) -> String {
    var parts: [String] = []
    if (modifiers & Int(cmdKey)) != 0 { parts.append("⌘") }
    if (modifiers & Int(optionKey)) != 0 { parts.append("⌥") }
    if (modifiers & Int(controlKey)) != 0 { parts.append("⌃") }
    if (modifiers & Int(shiftKey)) != 0 { parts.append("⇧") }

    // Carbon 键码 → 可读名称
    let keyNames: [Int: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
        0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
        0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
        0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
        0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
        0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M",
        0x2F: ".", 0x32: "`", 0x41: ".", 0x43: "*", 0x45: "+",
        0x47: "Clear", 0x4B: "/", 0x4C: "Enter", 0x4E: "-",
        0x51: "=", 0x52: "0", 0x53: "1", 0x54: "2",
        0x55: "3", 0x56: "4", 0x57: "5", 0x58: "6",
        0x59: "7", 0x5B: "8", 0x5C: "9",
        // 功能键
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        0x31: "Space", 0x24: "Return", 0x33: "Delete",
        0x30: "Tab", 0x35: "Escape",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
    ]
    let keyName = keyNames[keyCode] ?? "Key(\(keyCode))"
    parts.append(keyName)
    return parts.joined()
}

/// 将 NSEvent 的 Cocoa 修饰键标志转换为 Carbon 修饰键掩码（RegisterEventHotKey 使用）
func cocoaToCarbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
    var carbon = 0
    let deviceFlags = flags.intersection(.deviceIndependentFlagsMask)
    if deviceFlags.contains(.command) { carbon |= Int(cmdKey) }
    if deviceFlags.contains(.option)  { carbon |= Int(optionKey) }
    if deviceFlags.contains(.control) { carbon |= Int(controlKey) }
    if deviceFlags.contains(.shift)   { carbon |= Int(shiftKey) }
    return carbon
}

/// 检查快捷键是否包含至少一个修饰键
func hotkeyHasRequiredModifiers(_ modifiers: Int) -> Bool {
    (modifiers & Int(cmdKey | optionKey | controlKey | shiftKey)) != 0
}

/// 检测与 macOS 常见系统快捷键的冲突
/// 返回冲突提示字符串，无冲突返回 nil
func checkSystemHotkeyConflict(modifiers: Int, keyCode: Int) -> String? {
    let cmdOnly  = Int(cmdKey)
    let cmdShift = Int(cmdKey | shiftKey)
    let cmdOpt   = Int(cmdKey | optionKey)

    // 通用编辑快捷键（几乎所有 App 都使用）
    if modifiers == cmdOnly {
        switch keyCode {
        case 0x0C: return "⌘Q 退出当前应用（系统强占）"
        case 0x0D: return "⌘W 关闭窗口"
        case 0x0E: return "⌘E 搜索/显示"
        case 0x0F: return "⌘R 刷新/运行"
        case 0x10: return "⌘Y 历史/重做"
        case 0x11: return "⌘T 新建标签页"
        case 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19:
            return "⌘1-9 切换标签/窗口"
        case 0x00: return "⌘A 全选"
        case 0x01: return "⌘S 保存"
        case 0x02: return "⌘D 收藏/删除"
        case 0x03: return "⌘F 查找"
        case 0x05: return "⌘G 查找下一个"
        case 0x06: return "⌘Z 撤销"
        case 0x07: return "⌘X 剪切"
        case 0x08: return "⌘C 复制"
        case 0x09: return "⌘V 粘贴"
        case 0x0B: return "⌘B 加粗/隐藏"
        case 0x21: return "⌘[ 后退"
        case 0x1E: return "⌘] 前进"
        case 0x22: return "⌘I 斜体"
        case 0x23: return "⌘P 打印"
        case 0x25: return "⌘L 定位/跳转"
        case 0x26: return "⌘J 下载"
        case 0x27: return "⌘; 拼写检查"
        case 0x20: return "⌘U 下划线"
        case 0x24: return "⌘Return 默认确认"
        case 0x30: return "⌘Tab 应用切换器（系统强占）"
        case 0x31: return "⌘Space Spotlight（系统强占）"
        case 0x32: return "⌘` 同应用窗口切换"
        case 0x33: return "⌘Delete 删除"
        default: break
        }
    }

    // 截图 / Spotlight / Mission Control 等强占系统快捷键
    if modifiers == cmdShift {
        switch keyCode {
        case 0x14: return "⇧⌘3 全屏截图（系统强占）"
        case 0x15: return "⇧⌘4 区域截图（系统强占）"
        case 0x16: return "⇧⌘5 截屏工具（系统强占）"
        case 0x0D: return "⇧⌘W 关闭全部窗口"
        case 0x26: return "⇧⌘M 最小化所有"
        case 0x31: return "⇧⌘Space 切换输入法（系统强占）"
        default: break
        }
    }

    // 其他常见冲突
    if modifiers == cmdOpt {
        switch keyCode {
        case 0x22: return "⌥⌘I 浏览器开发者工具"
        case 0x24: return "⌥⌘Return 全屏"
        default: break
        }
    }

    return nil
}

// MARK: - 通知管理器（App Store 兼容：使用 UNUserNotificationCenter）

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            logi("通知权限: \(granted ? "已授权" : "未授权")" + (error != nil ? " (\(error!.localizedDescription))" : ""))
        }
    }

    func show(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // 立即触发
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let e = error { loge("通知发送失败: \(e.localizedDescription)") }
        }
    }

    // UNUserNotificationCenterDelegate — 前台也显示
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - 截图引擎（屏幕快照背景方案，全屏 Space 可靠）

final class ScreenshotEngine: NSObject {
    static let shared = ScreenshotEngine()

    private var panel: NSPanel?
    private var overlayView: OverlayView?
    private var startPoint: NSPoint = .zero
    fileprivate var isSelecting = false
    fileprivate var selectionRect: NSRect = .zero
    private var isActive = false
    private var safetyTimer: DispatchWorkItem?
    private var screenSnapshot: NSImage?
    private var fullScreenCGImage: CGImage?  // 首次截图时的原始 CGImage，用于裁切选区（避免拍到遮罩层）

    func start(done: @escaping (NSRect, CGImage?) -> Void) {
        guard !isActive else {
            logi("截图引擎已在运行中，忽略重复请求")
            done(.zero, nil)
            return
        }

        let pos = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pos) }) ?? NSScreen.main else {
            done(.zero, nil); return
        }

        // 1) 先截取当前屏幕画面（100% 精确的"后面有什么"）
        //    这样即使在最严格的全屏 Space 中，也能让用户看到图书文字
        //    同时保存 CGImage 和 NSImage：CGImage 用于最终裁切（避免拍到遮罩层），NSImage 用于 overlay 背景显示
        guard let (bg, rawCG) = captureFullScreen(screen: screen) else {
            logi("全屏截图失败")
            done(.zero, nil); return
        }
        screenSnapshot = bg
        fullScreenCGImage = rawCG

        // 2) 推入全局十字光标
        NSCursor.crosshair.push()
        logi("截图引擎启动：屏幕={\(Int(screen.frame.width))x\(Int(screen.frame.height))}")

        isActive = true

        // 3) 创建半透明遮罩面板（NSPanel 是 macOS 截图工具的经典选择）
        let p = NSPanel(contentRect: screen.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .screenSaver                    // 足够高，全屏可见
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.engine = self
        view.doneCallback = done
        view.backgroundImage = bg
        // 预渲染背景到 layer → 窗口出现瞬间就能看到背景文字
        view.wantsLayer = true
        if let cg = bg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            view.layer?.contents = cg
            view.layer?.contentsGravity = .resizeAspectFill
        }
        p.contentView = view

        self.panel = p
        self.overlayView = view

        p.orderFrontRegardless()
        p.makeKey()
        p.makeFirstResponder(view)

        // 安全超时 60 秒
        let timer = DispatchWorkItem { [weak self] in
            guard let self = self, self.isActive else { return }
            logi("安全超时：自动关闭遮罩")
            self.finish(rect: .zero, image: nil)
        }
        safetyTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timer)
    }

    // MARK: - 结束 & 清理

    private func finish(rect: NSRect, image: CGImage?) {
        overlayView?.doneCallback?(rect, image)
        cleanup()
    }

    func cleanup() {
        safetyTimer?.cancel()
        safetyTimer = nil
        isActive = false
        screenSnapshot = nil
        fullScreenCGImage = nil
        for _ in 0..<3 { NSCursor.crosshair.pop() }
        NSCursor.arrow.push(); NSCursor.arrow.pop()
        panel?.orderOut(nil)
        panel = nil
        overlayView = nil
        isSelecting = false
        selectionRect = .zero
    }

    // MARK: - 鼠标事件

    func mouseDown(_ point: NSPoint) {
        startPoint = point
        isSelecting = true
        selectionRect = .zero
        overlayView?.needsDisplay = true
    }

    func mouseDragged(_ point: NSPoint) {
        guard isSelecting else { return }
        selectionRect = NSRect(
            x: min(startPoint.x, point.x),
            y: min(startPoint.y, point.y),
            width: abs(point.x - startPoint.x),
            height: abs(point.y - startPoint.y)
        )
        overlayView?.needsDisplay = true
    }

    func mouseUp(_ point: NSPoint) {
        guard isSelecting else { return }
        isSelecting = false
        let rect = NSRect(
            x: min(startPoint.x, point.x),
            y: min(startPoint.y, point.y),
            width: abs(point.x - startPoint.x),
            height: abs(point.y - startPoint.y)
        )
        selectionRect = rect

        guard rect.width > 10, rect.height > 10 else {
            finish(rect: .zero, image: nil)
            return
        }

        // 实时截图选中区域（返回原始 CGImage，不做 NSImage 包装）
        let cg = captureRectCG(rect: rect)
        finish(rect: rect, image: cg)
    }

    // MARK: - 截图

    /// 将 raw screen-capture CGImage 转换为 Vision OCR 友好的标准 sRGB 无 Alpha 格式
    private func makeVisionFriendly(_ cg: CGImage) -> CGImage? {
        let ai = cg.alphaInfo
        if ai == .none || ai == .noneSkipFirst || ai == .noneSkipLast,
           cg.colorSpace?.model == .rgb { return cg }
        guard let ctx = CGContext(data: nil, width: cg.width, height: cg.height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return cg }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx.makeImage() ?? cg
    }

    /// 返回框选区域的高清 CGImage。使用初始全屏截图裁切（而非重新截图），
    /// 避免拍到我们自己的遮罩面板。
    private func captureRectCG(rect: NSRect) -> CGImage? {
        // 优先使用启动时缓存的原始 CGImage（最初的全屏截图，不含遮罩层）
        guard let full = fullScreenCGImage else {
            loge("缺少全屏 CGImage 缓存，回退实时截图")
            let pos = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pos) }) ?? NSScreen.main else { return nil }
            guard let fallback = captureDisplayImage(screen: screen) else { return nil }
            return cropFromFull(fallback, screen: screen, rect: rect)
        }

        let pos = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pos) }) ?? NSScreen.main else { return nil }
        return cropFromFull(full, screen: screen, rect: rect)
    }

    private func cropFromFull(_ full: CGImage, screen: NSScreen, rect: NSRect) -> CGImage? {
        let pw = CGFloat(full.width)
        let ph = CGFloat(full.height)
        let sf = screen.frame  // 点坐标

        let scaleX = pw / sf.width
        let scaleY = ph / sf.height
        logi("截图 scale: x=\(String(format: "%.3f", scaleX)) y=\(String(format: "%.3f", scaleY)), full=\(Int(pw))x\(Int(ph)) px, frame=\(sf)")

        // 3. 把 overlay view 点坐标 → 全屏 CGImage 像素坐标（CGImage 原点左上，y 向下）
        let cropX = round(rect.origin.x * scaleX)
        let cropY = round(ph - (rect.origin.y + rect.height) * scaleY)
        let cropW = round(rect.width  * scaleX)
        let cropH = round(rect.height * scaleY)

        guard cropW > 4, cropH > 4 else { loge("选区截图区域过小: \(cropW)x\(cropH)"); return nil }
        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH).intersection(CGRect(x: 0, y: 0, width: pw, height: ph))
        guard cropRect.width > 4, cropRect.height > 4 else { loge("裁剪后区域过小"); return nil }

        guard let cropped = full.cropping(to: cropRect) else { loge("CGImage 裁剪失败"); return nil }
        logi("截图 CGImage: \(cropped.width)x\(cropped.height) px (裁剪自 \(Int(pw))x\(Int(ph)))")
        return makeVisionFriendly(cropped)
    }

    /// 使用 CGWindowListCreateImage 截取屏幕内容，正确反映窗口叠放顺序
    private func captureDisplayImage(screen: NSScreen) -> CGImage? {
        let bounds = screen.frame  // 全局坐标系（左下角原点）
        return CGWindowListCreateImage(bounds,
                                       .optionOnScreenOnly,
                                       kCGNullWindowID,
                                       .bestResolution)
    }

    private func captureFullScreen(screen: NSScreen) -> (NSImage, CGImage?)? {
        guard let full = captureDisplayImage(screen: screen) else {
            loge("全屏截图失败 (CGWindowListCreateImage)")
            return nil
        }
        let sf = screen.frame
        let img = NSImage(size: sf.size)  // NSImage 用点坐标
        img.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.draw(full, in: CGRect(x: 0, y: 0, width: sf.width, height: sf.height))
        }
        img.unlockFocus()
        return (img, full)  // 返回 NSImage（显示用）+ CGImage（裁切用）
    }

    private func displayIDForScreen(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

// MARK: - 选区覆盖层视图（屏幕快照背景 → 看到的始终是图书文字）

private class OverlayView: NSView {
    weak var engine: ScreenshotEngine?
    var doneCallback: ((NSRect, CGImage?) -> Void)?
    var backgroundImage: NSImage?   // 全屏快照 → 显示背后的真实内容

    override var acceptsFirstResponder: Bool { true }

    private var showInstructions = true

    override func mouseDown(with e: NSEvent) {
        showInstructions = false
        needsDisplay = true
        engine?.mouseDown(convert(e.locationInWindow, from: nil))
    }
    override func mouseDragged(with e: NSEvent) {
        engine?.mouseDragged(convert(e.locationInWindow, from: nil))
    }
    override func mouseUp(with e: NSEvent) {
        engine?.mouseUp(convert(e.locationInWindow, from: nil))
    }
    override func rightMouseDown(with e: NSEvent) {
        doneCallback?(.zero, nil)
        engine?.cleanup()
    }
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { doneCallback?(.zero, nil); engine?.cleanup(); return }
        super.keyDown(with: e)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 背景：已由 layer.contents 预渲染（全屏快照），直接可见
        // 15% 黑色蒙层 → 微微变暗提示截图模式，文字完全可辨认
        NSColor.black.withAlphaComponent(0.15).setFill()
        bounds.fill()

        // 框选中 → 挖空选区 + 蓝色边框
        if let e = engine, e.isSelecting, e.selectionRect != .zero {
            let r = e.selectionRect
            NSColor.clear.set()
            r.fill(using: .sourceOut)
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: r)
            path.lineWidth = 2.0
            path.stroke()

            // 选区右上角尺寸标签
            let text = "\(Int(r.width)) × \(Int(r.height))"
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let sz = text.size(withAttributes: attr)
            let lr = NSRect(x: r.maxX - sz.width - 8, y: max(r.minY - sz.height - 6, 4),
                            width: sz.width + 12, height: sz.height + 6)
            let bp = NSBezierPath(roundedRect: lr, xRadius: 4, yRadius: 4)
            NSColor.systemBlue.withAlphaComponent(0.85).setFill()
            bp.fill()
            text.draw(at: NSPoint(x: lr.minX + 6, y: lr.minY + 3), withAttributes: attr)
        }

        // 引导提示
        guard showInstructions else { return }
        let line1 = "拖拽框选翻译区域"
        let line2 = "按 ESC 或右键取消"
        drawCenteredInstruction(text: line1, subText: line2)
    }

    private func drawCenteredInstruction(text: String, subText: String) {
        let cx = bounds.midX, cy = bounds.midY
        let ma: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: NSColor.white]
        let sa: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.7)]
        let ms = text.size(withAttributes: ma), ss = subText.size(withAttributes: sa)
        let th = ms.height + 6 + ss.height, mw = max(ms.width, ss.width)
        let bg = NSRect(x: cx - mw/2 - 24, y: cy - th/2 - 16, width: mw + 48, height: th + 32)
        NSBezierPath(roundedRect: bg, xRadius: 10, yRadius: 10).fill()
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 10, yRadius: 10).fill()

        let ca: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 28, weight: .thin), .foregroundColor: NSColor.white.withAlphaComponent(0.8)]
        let cs = "⊕".size(withAttributes: ca)
        "⊕".draw(at: NSPoint(x: cx - cs.width/2, y: bg.maxY - cs.height/2 + 28), withAttributes: ca)
        text.draw(at: NSPoint(x: cx - ms.width/2, y: bg.minY + 20 + ss.height + 6), withAttributes: ma)
        subText.draw(at: NSPoint(x: cx - ss.width/2, y: bg.minY + 18), withAttributes: sa)
    }
}

// MARK: - OCR 引擎（Vision Framework）

final class OCREngine {
    static let shared = OCREngine()

    func recognize(cgImage: CGImage) -> String? {
        logi("OCR: CGImage \(cgImage.width)x\(cgImage.height) px, alpha=\(cgImage.alphaInfo.rawValue)")

        let semaphore = DispatchSemaphore(value: 0)
        var result: String?

        let request = VNRecognizeTextRequest { (req, error) in
            defer { semaphore.signal() }
            if let e = error { loge("OCR Vision 错误: \(e.localizedDescription)"); return }
            guard let obs = req.results as? [VNRecognizedTextObservation] else { return }
            let lines = obs.compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            result = text.isEmpty ? nil : text
            logi("OCR: 识别到 \(obs.count) 块文本，\(result?.count ?? 0) 字符")
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "en-GB", "zh-Hans", "zh-Hant"]
        request.usesLanguageCorrection = false
        request.revision = VNRecognizeTextRequestRevision3

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            semaphore.wait()
        } catch {
            loge("OCR 执行失败: \(error.localizedDescription)")
            return nil
        }

        return result
    }
}

// MARK: - 翻译引擎（多 AI 提供商支持）

final class TranslationEngine {
    static let shared = TranslationEngine()

    func translate(text: String) -> String? {
        let settings = SettingsManager.shared
        let provider = settings.apiProvider
        guard let key = settings.activeApiKey, !key.isEmpty else {
            logi("未配置 \(provider.displayName) API Key")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "未配置 API Key"
                alert.informativeText = "请前往 偏好设置 配置 \(provider.displayName) API Key。\n访问 \(provider.registerURL) 注册获取。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "打开偏好设置")
                alert.addButton(withTitle: "取消")
                alert.layout()
                alert.window.level = .floating
                alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn {
                    SettingsWindowController.shared.show()
                }
                NSApp.deactivate()
            }
            return nil
        }

        let messages: [[String: Any]] = [
            ["role": "system", "content": settings.systemPrompt],
            ["role": "user", "content": "请分析以下英文文本：\n\n\(text)"]
        ]

        var body: [String: Any] = [:]
        let endpoint = provider.endpoint
        var request: URLRequest

        // 不同提供商的请求格式
        switch provider {
        case .anthropic:
            guard let url = URL(string: endpoint) else { loge("无效 API 地址"); return nil }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": provider.defaultModel,
                "max_tokens": 4096,
                "system": settings.systemPrompt,
                "messages": [["role": "user", "content": "请分析以下英文文本：\n\n\(text)"]]
            ]

        case .googleAI:
            let googleEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(provider.defaultModel):generateContent"
            guard let url = URL(string: googleEndpoint) else { loge("无效 API 地址"); return nil }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            let fullPrompt = "\(settings.systemPrompt)\n\n请分析以下英文文本：\n\n\(text)"
            body = [
                "contents": [["parts": [["text": fullPrompt]]]],
                "generationConfig": ["maxOutputTokens": 4096, "temperature": 0.1]
            ]

        default:
            // OpenAI-compatible API
            guard let url = URL(string: endpoint) else { loge("无效 API 地址"); return nil }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body = [
                "model": provider.defaultModel,
                "messages": messages,
                "temperature": 0.1,
                "max_tokens": 4096,
                "stream": false
            ]
        }

        request.timeoutInterval = 120

        do { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        catch { loge("JSON 序列化失败: \(error)"); return nil }

        logi("调用 \(provider.displayName) API...")
        let semaphore = DispatchSemaphore(value: 0)
        var resultText: String?
        var errorMsg: String?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let e = error { errorMsg = "网络: \(e.localizedDescription)"; return }
            guard let http = response as? HTTPURLResponse else { errorMsg = "无效响应"; return }
            guard let data = data else { errorMsg = "无数据"; return }
            if http.statusCode != 200 {
                let b = String(data: data, encoding: .utf8) ?? ""
                errorMsg = "HTTP \(http.statusCode): \(b.prefix(200))"; return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    switch provider {
                    case .anthropic:
                        // Anthropic 响应格式: { "content": [{"type": "text", "text": "..."}] }
                        if let content = json["content"] as? [[String: Any]],
                           let first = content.first,
                           let text = first["text"] as? String {
                            resultText = text
                        } else { errorMsg = "解析 Anthropic 响应失败" }
                    case .googleAI:
                        // Google Gemini 响应格式: { "candidates": [{"content": {"parts": [{"text": "..."}]}}] }
                        if let candidates = json["candidates"] as? [[String: Any]],
                           let first = candidates.first,
                           let content = first["content"] as? [String: Any],
                           let parts = content["parts"] as? [[String: Any]],
                           let firstPart = parts.first,
                           let text = firstPart["text"] as? String {
                            resultText = text
                        } else { errorMsg = "解析 Gemini 响应失败" }
                    default:
                        // OpenAI-compatible 响应格式: { "choices": [{"message": {"content": "..."}}] }
                        if let choices = json["choices"] as? [[String: Any]],
                           let first = choices.first,
                           let msg = first["message"] as? [String: Any],
                           let content = msg["content"] as? String {
                            resultText = content
                        } else { errorMsg = "解析响应失败" }
                    }
                } else { errorMsg = "解析响应失败" }
            } catch { errorMsg = "JSON 错误: \(error)" }
        }
        task.resume()
        semaphore.wait()

        if let err = errorMsg { loge("API 失败: \(err)"); return nil }
        logi("API 返回 \(resultText?.count ?? 0) 字符")
        return resultText
    }
}

// MARK: - 翻译流水线

final class TranslationPipeline {
    static let shared = TranslationPipeline()

    private var loadingPanel: NSPanel?

    /// 划词翻译触发时，记录前台应用的 PID，用于通过 Accessibility API 读取该应用的选中文本
    var selectionSourcePID: pid_t?

    /// 是否已触发过权限预检（确保两个 TCC 弹窗只在首次操作时出现一次）
    private static var permissionsPrimed = false

    /// 在首次截图或划词操作时，同时触发两个系统权限弹窗：
    /// 1. 辅助功能（Accessibility）— 划词翻译需要
    /// 2. 屏幕录制（Screen Recording）— 截图翻译需要
    private func primePermissionsIfNeeded() {
        guard !Self.permissionsPrimed else { return }
        Self.permissionsPrimed = true

        // 1. 触发辅助功能权限：
        //    仅调用 AXIsProcessTrusted() 不一定能稳定弹出 TCC 弹窗，
        //    需要实际尝试一次 Accessibility API 调用以确保系统检测到权限使用
        logi("Prime: 预触发辅助功能权限")
        if !AXIsProcessTrusted() {
            let sys = AXUIElementCreateSystemWide()
            var ref: CFTypeRef?
            AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &ref)
            logi("Accessibility 权限: 未授权，TCC 弹窗已触发")
        } else {
            logi("Accessibility 权限: 已授权")
        }

        // 2. 触发屏幕录制权限：
        //    CGWindowListCreateImage 的首次调用会自动弹出 TCC 授权弹窗
        logi("Prime: 预触发屏幕录制权限")
        if let mainScreen = NSScreen.main {
            let _ = CGWindowListCreateImage(mainScreen.frame,
                                            .optionOnScreenOnly,
                                            kCGNullWindowID,
                                            .bestResolution)
            logi("屏幕录制权限预触发完成")
        }

        logi("Prime: 两个权限弹窗应已依次出现，请在系统设置中分别授权")
    }

    func start() {
        logi("===== 翻译流水线开始 =====")
        primePermissionsIfNeeded()
        ScreenshotEngine.shared.start { [weak self] rect, cgImage in
            guard let cgImage = cgImage, rect != .zero else {
                logi("截图取消或失败"); return
            }
            logi("截图成功: \(cgImage.width)x\(cgImage.height) px, 选区@(\(Int(rect.origin.x)),\(Int(rect.origin.y)))")
            self?.showLoading()

            DispatchQueue.global(qos: .userInitiated).async {
                // OCR（直接传原始 CGImage，不做 NSImage 包装）
                logi("[Step 2] OCR 识别...")
                guard let text = OCREngine.shared.recognize(cgImage: cgImage) else {
                    self?.hideLoading()
                    self?.showError("OCR 未能识别到文字。\n请确认框选区域包含清晰文字，且文字不过小/模糊。")
                    return
                }

                // 翻译
                logi("[Step 3] AI 翻译...")
                guard let result = TranslationEngine.shared.translate(text: text) else {
                    self?.hideLoading()
                    self?.showError("AI 翻译失败。\nOCR 已识别文本：\n\(text.prefix(200))")
                    return
                }

                self?.hideLoading()
                ResultWindowController.shared.show(markdown: result, originalText: text, screenshotRect: rect)
                NotificationManager.shared.show(title: APP_DISPLAY_NAME, body: "翻译完成，点击查看结果")
                logi("流水线完成")
            }
        }
    }

    /// 通过 macOS Accessibility API 读取指定应用（或系统全局）当前聚焦元素中的选中文本
    /// - Parameter pid: 目标应用的进程 PID；传 nil 则回退为系统全局聚焦元素（兼容旧逻辑）
    /// 不依赖剪贴板，也不需要模拟 Cmd+C，兼容性更好
    private func getSelectedTextViaAccessibility(pid: pid_t? = nil) -> String? {
        // 检查辅助功能权限
        guard AXIsProcessTrusted() else {
            logi("Accessibility：未获得辅助功能权限，提示用户授权")
            DispatchQueue.main.async {
                self.promptAccessibilityPermission()
            }
            return nil
        }

        // 定位聚焦元素：优先按 PID 定位目标 App，再读取其焦点元素
        let focusedElement: AXUIElement
        if let pid = pid, pid != 0 {
            let app = AXUIElementCreateApplication(pid)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
                  let element = ref else {
                logi("Accessibility：无法获取 PID=\(pid) 的聚焦元素，回退系统全局")
                // 回退：使用系统全局
                let sys = AXUIElementCreateSystemWide()
                var sysRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &sysRef) == .success,
                      let sysElement = sysRef else {
                    logi("Accessibility：系统全局也无法获取聚焦元素")
                    return nil
                }
                focusedElement = sysElement as! AXUIElement
                return extractSelectedText(from: focusedElement)
            }
            focusedElement = element as! AXUIElement
        } else {
            let system = AXUIElementCreateSystemWide()
            var focusedRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
                  let element = focusedRef else {
                logi("Accessibility：无法获取聚焦元素")
                return nil
            }
            focusedElement = element as! AXUIElement
        }

        return extractSelectedText(from: focusedElement)
    }

    /// 从指定元素提取选中文本（通用逻辑）
    private func extractSelectedText(from element: AXUIElement) -> String? {
        // 先尝试 kAXSelectedTextAttribute
        var selectedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedValue) == .success,
           let text = selectedValue as? String, !text.isEmpty {
            logi("Accessibility：直接获取选中文本 \(text.count) 字符")
            return text
        }

        // 兜底：尝试 kAXValueAttribute，再过滤选中的部分
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let fullText = valueRef as? String, !fullText.isEmpty {
            var selectedRangeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success,
               let rangeValue = selectedRangeRef,
               CFGetTypeID(rangeValue) == AXValueGetTypeID() {
                let axValue = rangeValue as! AXValue
                var range = CFRange(location: 0, length: 0)
                if AXValueGetValue(axValue, .cfRange, &range) {
                    let nsRange = NSRange(location: range.location, length: range.length)
                    if nsRange.location != NSNotFound,
                       nsRange.location >= 0,
                       nsRange.location + nsRange.length <= fullText.count {
                        let start = fullText.index(fullText.startIndex, offsetBy: nsRange.location)
                        let end = fullText.index(start, offsetBy: nsRange.length)
                        let selected = String(fullText[start..<end])
                        if !selected.isEmpty {
                            logi("Accessibility：按范围截取选中文本 \(selected.count) 字符")
                            return selected
                        }
                    }
                }
            }
            logi("Accessibility：未拿到范围，使用完整文本兜底 \(fullText.count) 字符")
            return fullText
        }

        logi("Accessibility：未找到任何文本")
        return nil
    }

    /// 引导用户前往系统设置开启辅助功能权限
    /// 引导用户前往系统设置开启辅助功能权限（同一会话仅提示一次）
    private static var accessibilityPrompted = false

    private func promptAccessibilityPermission() {
        guard !Self.accessibilityPrompted else { return }
        Self.accessibilityPrompted = true
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "为了获取您在任意应用中选中的文本（划词翻译），ELTA 需要【辅助功能】权限。\n\n请前往 系统设置 → 隐私与安全性 → 辅助功能，找到并启用 ELTA。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    /// 划词翻译：读取选中文本 → 直接翻译（跳过截图+OCR）
    func startTextTranslation() {
        logi("===== 划词翻译流水线开始 =====")
        primePermissionsIfNeeded()

        // 0. 记录触发时的鼠标位置（用于弹窗左右判断）
        let mouseLocation = NSEvent.mouseLocation

        // 1. 等待用户释放快捷键按键（Cmd/Shift）
        usleep(300_000)  // 300ms

        // 2. 优先使用 Accessibility API 读取选中文本（最可靠）
        //    传入快捷键触发时捕获的前台应用 PID，确保从正确的应用读取焦点元素
        var selectedText: String? = getSelectedTextViaAccessibility(pid: selectionSourcePID)

        // 3. Accessibility 失败时，兜底使用 Cmd+C + 剪贴板
        if selectedText == nil || selectedText!.isEmpty {
            logi("Accessibility 未获取到文本，尝试 Cmd+C 兜底")
            selectedText = getSelectedTextViaCopyPasteboard()
        }

        guard let text = selectedText, !text.isEmpty else {
            showError("未能获取选中文本。\n可能原因：\n1. 未选中文本\n2. 未授予【辅助功能】权限（系统设置 → 隐私与安全性 → 辅助功能）")
            return
        }

        logi("划词获取文本: \(text.prefix(100))...")
        showTextLoading()

        // 4. 直接翻译
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let result = TranslationEngine.shared.translate(text: text) else {
                self?.hideLoading()
                self?.showError("AI 翻译失败。\n选中文本：\n\(text.prefix(200))")
                return
            }
            self?.hideLoading()
            // 用鼠标位置构造一个小矩形，让弹窗知道用户在哪一侧屏幕
            let mouseRect = NSRect(x: mouseLocation.x - 5, y: mouseLocation.y - 5, width: 10, height: 10)
            ResultWindowController.shared.show(markdown: result, originalText: text, screenshotRect: mouseRect)
            NotificationManager.shared.show(title: APP_DISPLAY_NAME, body: "划词翻译完成，点击查看结果")
            logi("划词翻译流水线完成")
        }
    }

    /// Cmd+C + 剪贴板兜底方案
    private func getSelectedTextViaCopyPasteboard() -> String? {
        let pasteboard = NSPasteboard.general
        let oldChangeCount = pasteboard.changeCount
        let oldItems = pasteboard.pasteboardItems?.compactMap { $0.string(forType: .string) } ?? []

        // 模拟 Cmd+C 复制选中文本
        // 关键：cmdDown 的 flags 必须为空（不能设 .maskCommand），否则系统认为事件矛盾
        let src = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
        let cDown   = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        cDown?.flags = .maskCommand
        let cUp     = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        cUp?.flags  = .maskCommand
        let cmdUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)

        cmdDown?.post(tap: .cghidEventTap)
        usleep(30_000)
        cDown?.post(tap: .cghidEventTap)
        usleep(40_000)
        cUp?.post(tap: .cghidEventTap)
        usleep(30_000)
        cmdUp?.post(tap: .cghidEventTap)

        // 读取剪贴板（重试等待目标 App 处理 Cmd+C）
        var selectedText: String? = nil
        let maxRetries = 15
        for i in 0..<maxRetries {
            usleep(100_000)  // 每次等待 100ms，总计最多 1.5 秒
            if pasteboard.changeCount != oldChangeCount,
               let newText = pasteboard.string(forType: .string),
               !newText.isEmpty {
                selectedText = newText
                logi("Cmd+C 获取成功（重试 \(i + 1) 次）")
                break
            }
        }
        // 兜底：changeCount 没变但内容确实变了（部分 App 不更新 changeCount）
        if selectedText == nil,
           let newText = pasteboard.string(forType: .string),
           !newText.isEmpty,
           !oldItems.contains(newText) {
            selectedText = newText
            logi("Cmd+C 获取成功（兜底读取）")
        }

        // 恢复旧剪贴板（如果可能）
        if !oldItems.isEmpty {
            pasteboard.clearContents()
            pasteboard.writeObjects(oldItems as [NSPasteboardWriting])
        }

        return selectedText
    }

    private func showTextLoading() {
        DispatchQueue.main.async { [weak self] in self?.showTextLoadingPanel() }
    }

    private func showTextLoadingPanel() {
        guard loadingPanel == nil else { return }
        let w: CGFloat = 300, h: CGFloat = 140
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                            styleMask: [.titled, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = APP_DISPLAY_NAME
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        let spinner = NSProgressIndicator(frame: NSRect(x: (w - 40) / 2, y: 60, width: 40, height: 40))
        spinner.style = .spinning; spinner.startAnimation(nil); v.addSubview(spinner)

        let label = NSTextField(labelWithString: "正在翻译...")
        label.frame = NSRect(x: 0, y: 30, width: w, height: 24); label.alignment = .center
        label.font = .systemFont(ofSize: 14); v.addSubview(label)

        let sub = NSTextField(labelWithString: "划词翻译 → AI 翻译分析")
        sub.frame = NSRect(x: 0, y: 12, width: w, height: 18); sub.alignment = .center
        sub.font = .systemFont(ofSize: 11); sub.textColor = .secondaryLabelColor; v.addSubview(sub)

        panel.contentView = v
        loadingPanel = panel
    }

    private func showLoading() {
        DispatchQueue.main.async { [weak self] in self?.showLoadingPanel() }
    }

    private func hideLoading() {
        DispatchQueue.main.async { [weak self] in
            self?.loadingPanel?.close()
            self?.loadingPanel = nil
        }
    }

    private func showLoadingPanel() {
        guard loadingPanel == nil else { return }
        let w: CGFloat = 300, h: CGFloat = 140
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                            styleMask: [.titled, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = APP_DISPLAY_NAME
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        let spinner = NSProgressIndicator(frame: NSRect(x: (w - 40) / 2, y: 60, width: 40, height: 40))
        spinner.style = .spinning; spinner.startAnimation(nil); v.addSubview(spinner)

        let label = NSTextField(labelWithString: "正在识别与翻译...")
        label.frame = NSRect(x: 0, y: 30, width: w, height: 24); label.alignment = .center
        label.font = .systemFont(ofSize: 14); v.addSubview(label)

        let sub = NSTextField(labelWithString: "OCR 识别 → AI 翻译分析")
        sub.frame = NSRect(x: 0, y: 12, width: w, height: 18); sub.alignment = .center
        sub.font = .systemFont(ofSize: 11); sub.textColor = .secondaryLabelColor; v.addSubview(sub)

        panel.contentView = v
        loadingPanel = panel
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            // 临时切换激活策略为 regular，确保在全屏 Space 中能获取焦点
            let currentPolicy = NSApp.activationPolicy()
            if currentPolicy != .regular { NSApp.setActivationPolicy(.regular) }
            usleep(80_000)  // 等待系统处理策略切换

            let alert = NSAlert()
            alert.messageText = "翻译失败"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.window.level = .screenSaver
            alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.deactivate()
            // 恢复原来的激活策略
            if currentPolicy != .regular { NSApp.setActivationPolicy(currentPolicy) }
        }
    }
}

// MARK: - 结果窗口控制器

final class ResultWindowController: NSObject, NSWindowDelegate {
    static let shared = ResultWindowController()

    private var panel: NSPanel?
    private var webView: WKWebView?

    func show(markdown: String, originalText: String, screenshotRect: NSRect) {
        DispatchQueue.main.async { [weak self] in
            self?.panel?.close()
            let frame = self?.computeFrame(avoidRect: screenshotRect) ?? NSRect(x: 0, y: 0, width: 620, height: 700)

            let panel = NSPanel(contentRect: frame,
                                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.title = "翻译结果 — \(APP_DISPLAY_NAME)"
            panel.isMovableByWindowBackground = true
            panel.minSize = NSSize(width: 420, height: 400)
            panel.delegate = self

            let config = WKWebViewConfiguration()
            let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height),
                               configuration: config)
            wv.autoresizingMask = [.width, .height]
            wv.setValue(false, forKey: "drawsBackground")
            wv.loadHTMLString(HTMLRenderer.render(markdown: markdown, originalText: originalText), baseURL: nil)
            panel.contentView = wv
            panel.makeKeyAndOrderFront(nil)

            self?.panel = panel
            self?.webView = wv
        }
    }

    /// 弹窗铺满截图对侧半个屏幕（不越过中线）
    private func computeFrame(avoidRect: NSRect) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(avoidRect) })
                ?? NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 620, height: 700)
        }
        let vf = screen.visibleFrame
        let midline = screen.frame.midX
        let onLeftSide = avoidRect.midX < midline

        let x: CGFloat = onLeftSide ? midline : vf.minX
        let w: CGFloat = onLeftSide ? (vf.maxX - midline) : (midline - vf.minX)

        if let saved = SettingsManager.shared.windowFrame {
            return NSRect(x: x, y: saved.origin.y, width: w, height: saved.height)
        }
        return NSRect(x: x, y: vf.minY, width: w, height: vf.height)
    }

    func windowDidMove(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win == panel else { return }
        SettingsManager.shared.windowFrame = win.frame
    }
}

// MARK: - HTML 渲染器

final class HTMLRenderer {
    static func render(markdown: String, originalText: String) -> String {
        var html = markdown
        // MD 标题 → HTML 标题
        for keyword in ["中文翻译", "重要词汇", "常用短语与习语", "核查"] {
            html = html.replacingOccurrences(of: "## \(keyword)", with: "<h2>\(keyword)</h2>")
        }
        html = html.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
        html = html.replacingOccurrences(of: "\n\n", with: "</p><p>")
        html = html.replacingOccurrences(of: "\n", with: "<br>")
        html = "<p>" + html + "</p>"
        html = html.replacingOccurrences(of: "<p></p>", with: "")
        html = html.replacingOccurrences(of: "<p><br></p>", with: "")

        let escaped = originalText
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
        <style>
            :root{color-scheme:light dark}*{box-sizing:border-box;margin:0;padding:0}
            body{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Microsoft YaHei",sans-serif;font-size:14px;line-height:1.7;color:#1d1d1f;padding:20px 24px;background:#fff}
            @media(prefers-color-scheme:dark){body{color:#e5e5e7;background:#1c1c1e}.original-box{background:#1e3a5f;border-color:#2d5aa0;color:#abd5ff}h2{color:#fff;border-bottom-color:#0a84ff}code{background:#3a3a3c;color:#ff9f0a}.footer{border-top-color:#3a3a3c}strong{color:#5eafff}}
            .original-box{background:#e8f0fe;border:1px solid #b8d4fe;border-radius:10px;padding:14px 18px;margin-bottom:18px;font-size:15px;color:#1a3a6b;font-style:italic}
            h2{font-size:17px;font-weight:600;margin:20px 0 12px;padding-bottom:8px;border-bottom:2px solid #0071e3}
            code{background:#f0f0f2;padding:2px 6px;border-radius:4px;font-family:"SF Mono",Menlo,monospace;font-size:13px;color:#9b4d1c}
            strong{color:#0071e3}
            blockquote{background:#f9f9fb;border-left:4px solid #0071e3;padding:10px 16px;margin:8px 0 12px;border-radius:0 8px 8px 0;color:#3a3a3c;font-size:15px}
            @media(prefers-color-scheme:dark){blockquote{background:#2c2c2e;border-left-color:#0a84ff;color:#c0c0c5}}
            table{width:100%;border-collapse:collapse;margin:10px 0 16px;font-size:13px}th{background:#f5f5f7;padding:10px 12px;text-align:left;font-weight:600}td{padding:8px 12px;border-bottom:1px solid #e5e5e7;vertical-align:top}
            @media(prefers-color-scheme:dark){th{background:#2c2c2e;color:#fff}td{border-color:#3a3a3c;color:#e5e5e7}}
            p{margin:6px 0}ul,ol{margin:8px 0;padding-left:20px}li{margin:4px 0}.footer{margin-top:20px;padding-top:12px;border-top:1px solid #e5e5e7;font-size:11px;color:#86868b;text-align:center}
        </style>
        </head><body>
        <div class="original-box"><strong>📝 原文：</strong><br>\(escaped)</div>
        \(html)
        <div class="footer">Powered by DeepSeek AI · ELTA — 截图即译，精读利器</div>
        </body></html>
        """
    }
}

// MARK: - 偏好设置窗口

final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var tabView: NSTabView?

    // Tab 1: 通用 — API 提供商 & Key
    private var providerPopup: NSPopUpButton?
    private var apiKeyVisibleField: PasteTextField?   // 明文输入
    private var apiKeyHiddenField: NSSecureTextField?  // 密文（默认显示）
    private var apiKeyEyeButton: NSButton?
    private var apiKeyVisible: Bool = false             // 当前是否明文
    private var customEndpointField: NSTextField?
    private var customModelField: NSTextField?
    private var providerDescLabel: NSTextField?
    private var testStatusLabel: NSTextField?
    private var providerCardView: NSView?          // 当前提供商的卡片容器
    private var providerCardHeight: CGFloat = 0

    // Tab 2: 快捷键
    private var hotkeyLabel: NSTextField?
    private var hotkeyRecordBtn: NSButton?
    private var hotkeyStatusLabel: NSTextField?
    private var isRecordingHotkey = false
    private var recordedKeyCode: Int = 0
    private var recordedModifiers: Int = 0

    // 划词翻译快捷键
    private var selectionHotkeyRecordBtn: NSButton?
    private var selectionHotkeyStatusLabel: NSTextField?
    private var isRecordingSelectionHotkey = false
    private var recordedSelectionKeyCode: Int = 0
    private var recordedSelectionModifiers: Int = 0
    private var hotkeyMonitor: Any?

    // Tab 3: 翻译模板
    private var templateTextView: NSTextView?
    private var templatePreviewWebView: WKWebView?

    func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }

        let ww: CGFloat = 640, hh: CGFloat = 700
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: ww, height: hh),
                           styleMask: [.titled, .closable, .miniaturizable],
                           backing: .buffered, defer: false)
        win.title = "\(APP_DISPLAY_NAME) 偏好设置"
        win.center()
        win.isReleasedWhenClosed = false

        let content = NSView(frame: NSRect(x: 0, y: 0, width: ww, height: hh))

        // ---- 标签页 ----
        let tabView = NSTabView(frame: NSRect(x: 16, y: 50, width: ww - 32, height: hh - 66))
        tabView.tabViewType = .topTabsBezelBorder

        // Tab 1: 通用
        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = "通用"
        generalTab.view = buildGeneralTab(size: tabView.frame.size)
        tabView.addTabViewItem(generalTab)

        // Tab 2: 快捷键
        let hotkeyTab = NSTabViewItem(identifier: "hotkey")
        hotkeyTab.label = "快捷键"
        hotkeyTab.view = buildHotkeyTab(size: tabView.frame.size)
        tabView.addTabViewItem(hotkeyTab)

        // Tab 3: 翻译模板
        let templateTab = NSTabViewItem(identifier: "template")
        templateTab.label = "翻译模板"
        templateTab.view = buildTemplateTab(size: tabView.frame.size)
        tabView.addTabViewItem(templateTab)

        content.addSubview(tabView)
        self.tabView = tabView

        // ---- 底部按钮 ----
        let resetBtn = NSButton(title: "恢复默认", target: self, action: #selector(resetAll))
        resetBtn.frame = NSRect(x: 16, y: 12, width: 100, height: 28)
        resetBtn.bezelStyle = .rounded
        content.addSubview(resetBtn)

        let saveBtn = NSButton(title: "保存并应用", target: self, action: #selector(saveAllSettings))
        saveBtn.frame = NSRect(x: ww - 135, y: 12, width: 120, height: 28)
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        content.addSubview(saveBtn)

        // ---- 版本号（底部居中，极简不干扰 UI） ----
        let versionLabel = NSTextField(labelWithString: "ELTA \(APP_FULL_VERSION)")
        versionLabel.frame = NSRect(x: (ww - 160) / 2, y: 0, width: 160, height: 14)
        versionLabel.alignment = .center
        versionLabel.font = .systemFont(ofSize: 10, weight: .regular)
        versionLabel.textColor = .secondaryLabelColor
        content.addSubview(versionLabel)

        win.contentView = content
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    // MARK: - Tab 1: 通用（滚动列表 + 动态卡片）

    private func buildGeneralTab(size: NSSize) -> NSView {
        let v = NSView(frame: NSRect(origin: .zero, size: size))
        let w = size.width
        var y: CGFloat = size.height - 30

        // --- 标题 ---
        let titleLabel = NSTextField(labelWithString: "AI 翻译引擎配置")
        titleLabel.frame = NSRect(x: 20, y: y, width: 300, height: 22)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(titleLabel)
        y -= 28

        // --- 提供商下拉选择器 ---
        let providerLabel = NSTextField(labelWithString: "当前 AI 提供商：")
        providerLabel.frame = NSRect(x: 20, y: y, width: 200, height: 18)
        providerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        v.addSubview(providerLabel)
        y -= 24

        let providerPopup = NSPopUpButton(frame: NSRect(x: 20, y: y, width: 280, height: 26), pullsDown: false)
        providerPopup.addItems(withTitles: AIProvider.allCases.map { $0.displayName })
        let currentProvider = SettingsManager.shared.apiProvider
        providerPopup.selectItem(at: AIProvider.allCases.firstIndex(of: currentProvider) ?? 0)
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged(_:))
        v.addSubview(providerPopup)
        self.providerPopup = providerPopup
        y -= 40

        // --- 分隔线 ---
        let sep = NSBox(frame: NSRect(x: 20, y: y, width: w - 40, height: 1))
        sep.boxType = .separator
        v.addSubview(sep)
        y -= 12

        // --- 动态卡片区域（根据选中提供商显示对应配置） ---
        let cardScroll = NSScrollView(frame: NSRect(x: 16, y: 10, width: w - 32, height: y - 10))
        cardScroll.hasVerticalScroller = true
        cardScroll.autohidesScrollers = true
        cardScroll.borderType = .noBorder
        cardScroll.drawsBackground = false
        v.addSubview(cardScroll)

        providerCardHeight = y - 10
        let cardView = buildProviderCard(width: w - 36, provider: currentProvider)
        cardScroll.documentView = cardView
        self.providerCardView = cardView

        return v
    }

    /// 根据提供商构建动态配置卡片
    private func buildProviderCard(width w: CGFloat, provider: AIProvider) -> NSView {
        let settings = SettingsManager.shared
        let workingHeight: CGFloat = 800
        let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: workingHeight))
        var y: CGFloat = workingHeight - 16

        // --- API Key 区域 ---
        if provider.needsAPIKey {
            let apiTitle = NSTextField(labelWithString: "\(provider.displayName) API Key：")
            apiTitle.frame = NSRect(x: 4, y: y, width: w - 8, height: 18)
            apiTitle.font = .systemFont(ofSize: 12, weight: .semibold)
            v.addSubview(apiTitle)
            y -= 20

            let apiDesc = NSTextField(labelWithString: "注册地址：\(provider.registerURL)")
            apiDesc.frame = NSRect(x: 4, y: y, width: w - 8, height: 14)
            apiDesc.font = .systemFont(ofSize: 10)
            apiDesc.textColor = .secondaryLabelColor
            v.addSubview(apiDesc)
            self.providerDescLabel = apiDesc
            y -= 20

            // API Key 输入行：密文字段 + 明文字段（叠放） + 小眼睛切换按钮
            let keyRow = NSView(frame: NSRect(x: 4, y: y, width: w - 8, height: 26))
            let fieldWid = w - 8 - 32  // 为眼睛按钮留 32pt

            // 明文输入框（PasteTextField，支持 Cmd+V）
            let visibleField = PasteTextField(frame: NSRect(x: 0, y: 0, width: fieldWid, height: 26))
            visibleField.placeholderString = (provider == .anthropic) ? "sk-ant-..." : "sk-..."
            visibleField.stringValue = settings.apiKey(for: provider) ?? ""
            visibleField.isBordered = true
            visibleField.bezelStyle = .roundedBezel
            visibleField.isEditable = true
            visibleField.isSelectable = true
            visibleField.isHidden = true  // 默认隐藏（密文模式）
            keyRow.addSubview(visibleField)

            // 密文输入框（NSSecureTextField，默认显示）
            let hiddenField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: fieldWid, height: 26))
            hiddenField.placeholderString = (provider == .anthropic) ? "sk-ant-..." : "sk-..."
            hiddenField.stringValue = settings.apiKey(for: provider) ?? ""
            hiddenField.isBordered = true
            hiddenField.bezelStyle = .roundedBezel
            hiddenField.isEditable = true
            hiddenField.isSelectable = true
            keyRow.addSubview(hiddenField)

            // 小眼睛按钮
            let eyeBtn = NSButton(frame: NSRect(x: fieldWid + 4, y: 1, width: 26, height: 24))
            eyeBtn.bezelStyle = .regularSquare
            eyeBtn.isBordered = false
            eyeBtn.title = "🔐"
            eyeBtn.toolTip = "显示/隐藏 API Key"
            eyeBtn.font = .systemFont(ofSize: 16)
            eyeBtn.target = self
            eyeBtn.action = #selector(toggleApiKeyVisibility(_:))
            keyRow.addSubview(eyeBtn)

            v.addSubview(keyRow)
            apiKeyVisibleField = visibleField
            apiKeyHiddenField = hiddenField
            apiKeyEyeButton = eyeBtn
            apiKeyVisible = false
            y -= 36

            let testBtn = NSButton(title: "测试连接", target: self, action: #selector(testAPIKey))
            testBtn.frame = NSRect(x: 4, y: y, width: 90, height: 28)
            testBtn.bezelStyle = .rounded
            v.addSubview(testBtn)

            let statusLabel = NSTextField(labelWithString: "")
            statusLabel.frame = NSRect(x: 100, y: y + 4, width: w - 104, height: 18)
            statusLabel.font = .systemFont(ofSize: 11)
            statusLabel.textColor = .secondaryLabelColor
            v.addSubview(statusLabel)
            self.testStatusLabel = statusLabel
            y -= 42
        } else {
            // Ollama 无需 API Key
            let noKeyLabel = NSTextField(labelWithString: "Ollama 运行在本地，无需 API Key。")
            noKeyLabel.frame = NSRect(x: 4, y: y, width: w - 8, height: 18)
            noKeyLabel.font = .systemFont(ofSize: 12, weight: .medium)
            noKeyLabel.textColor = .secondaryLabelColor
            v.addSubview(noKeyLabel)
            y -= 28
        }

        // --- 分隔线 ---
        let sep1 = NSBox(frame: NSRect(x: 4, y: y, width: w - 8, height: 1))
        sep1.boxType = .separator
        v.addSubview(sep1)
        y -= 16

        // --- 自定义 Endpoint（OpenAI-Compatible 和 Ollama） ---
        if provider.needsCustomEndpoint {
            let epTitle = NSTextField(labelWithString: "API 地址（Endpoint）：")
            epTitle.frame = NSRect(x: 4, y: y, width: w - 8, height: 18)
            epTitle.font = .systemFont(ofSize: 12, weight: .semibold)
            v.addSubview(epTitle)
            y -= 22

            let epField = PasteTextField(frame: NSRect(x: 4, y: y, width: w - 8, height: 26))
            epField.placeholderString = provider == .ollama
                ? "http://localhost:11434/v1/chat/completions"
                : "https://your-api.com/v1/chat/completions"
            epField.stringValue = settings.customEndpoint ?? provider.endpoint
            epField.isBordered = true
            epField.bezelStyle = .roundedBezel
            v.addSubview(epField)
            self.customEndpointField = epField
            y -= 40
        }

        // --- 自定义 Model ---
        if provider.needsCustomModel {
            let mdlTitle = NSTextField(labelWithString: "模型名称（Model）：")
            mdlTitle.frame = NSRect(x: 4, y: y, width: w - 8, height: 18)
            mdlTitle.font = .systemFont(ofSize: 12, weight: .semibold)
            v.addSubview(mdlTitle)
            y -= 22

            let mdlField = PasteTextField(frame: NSRect(x: 4, y: y, width: w - 8, height: 26))
            mdlField.placeholderString = provider == .ollama ? "llama3.2" : "gpt-3.5-turbo"
            let currentModel: String
            if provider == .ollama {
                currentModel = settings.ollamaModel ?? provider.defaultModel
            } else {
                currentModel = settings.customModel ?? provider.defaultModel
            }
            mdlField.stringValue = currentModel
            mdlField.isBordered = true
            mdlField.bezelStyle = .roundedBezel
            v.addSubview(mdlField)
            self.customModelField = mdlField
            y -= 40
        }

        // --- 分隔线 ---
        let sep2 = NSBox(frame: NSRect(x: 4, y: y, width: w - 8, height: 1))
        sep2.boxType = .separator
        v.addSubview(sep2)
        y -= 16

        // --- 其他提供商的 Key 列表 ---
        let otherTitle = NSTextField(labelWithString: "其他 AI 提供商的 API Key（填入后切换即可使用）：")
        otherTitle.frame = NSRect(x: 4, y: y, width: w - 8, height: 18)
        otherTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        v.addSubview(otherTitle)
        y -= 26

        for p in AIProvider.allCases where p != provider && p.needsAPIKey {
            let hasKey = (settings.apiKey(for: p) ?? "").isEmpty ? false : true
            let statusIcon = hasKey ? "✅" : "⬜"
            let rowLabel = NSTextField(labelWithString: "\(statusIcon)  \(p.displayName)")
            rowLabel.frame = NSRect(x: 8, y: y, width: 200, height: 18)
            rowLabel.font = .systemFont(ofSize: 11)
            rowLabel.textColor = hasKey ? .labelColor : .secondaryLabelColor
            v.addSubview(rowLabel)
            y -= 18
        }

        // --- 提示信息 ---
        let infoLabel = NSTextField(labelWithString: """
        💡 提示：Key 仅保存在本地，不会上传到任何第三方服务器。
        切换提供商后需点击底部「保存并应用」才能生效。
        """)
        let infoTop = max(y - 50, 20)
        infoLabel.frame = NSRect(x: 4, y: infoTop, width: w - 8, height: 50)
        infoLabel.font = .systemFont(ofSize: 10)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.lineBreakMode = .byWordWrapping
        v.addSubview(infoLabel)

        // 根据实际内容动态调整卡片高度，并整体下移内容，避免提示文字与列表重叠
        let requiredHeight = infoTop + 50 + 16
        let offset = workingHeight - requiredHeight
        for subview in v.subviews {
            var frame = subview.frame
            frame.origin.y -= offset
            subview.frame = frame
        }
        v.frame = NSRect(x: 0, y: 0, width: w, height: requiredHeight)

        return v
    }

    // MARK: - Tab 2: 快捷键

    private func buildHotkeyTab(size: NSSize) -> NSView {
        let v = NSView(frame: NSRect(origin: .zero, size: size))
        let w = size.width
        let y0: CGFloat = size.height - 30

        // ---- 1. 截图翻译 ----
        let titleLabel = NSTextField(labelWithString: "📷 截图翻译快捷键")
        titleLabel.frame = NSRect(x: 20, y: y0, width: 300, height: 22)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: "框选屏幕区域 → OCR 识别 → AI 翻译")
        descLabel.frame = NSRect(x: 20, y: y0 - 24, width: w - 40, height: 16)
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        v.addSubview(descLabel)

        let currentDisplay = SettingsManager.shared.hotkeyDisplay
        let recordBtn = NSButton(title: "    \(currentDisplay)    ", target: self, action: #selector(startRecordingHotkey))
        recordBtn.frame = NSRect(x: 20, y: y0 - 80, width: 180, height: 42)
        recordBtn.bezelStyle = .rounded
        recordBtn.font = .systemFont(ofSize: 20, weight: .medium)
        v.addSubview(recordBtn)
        hotkeyRecordBtn = recordBtn

        let statusLabel = NSTextField(labelWithString: "点击上方按钮开始录制新快捷键")
        statusLabel.frame = NSRect(x: 210, y: y0 - 70, width: w - 230, height: 30)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        v.addSubview(statusLabel)
        hotkeyStatusLabel = statusLabel

        // ---- 2. 划词翻译 ----
        let selY = y0 - 150
        let sTitle = NSTextField(labelWithString: "📝 划词翻译快捷键")
        sTitle.frame = NSRect(x: 20, y: selY, width: 300, height: 22)
        sTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(sTitle)

        let sDesc = NSTextField(labelWithString: "先选中文字，再按快捷键 → 直接 AI 翻译（无需截图+OCR）")
        sDesc.frame = NSRect(x: 20, y: selY - 24, width: w - 40, height: 16)
        sDesc.font = .systemFont(ofSize: 11)
        sDesc.textColor = .secondaryLabelColor
        v.addSubview(sDesc)

        let selDisplay = SettingsManager.shared.selectionHotkeyDisplay
        let selRecordBtn = NSButton(title: "    \(selDisplay)    ", target: self, action: #selector(startRecordingSelectionHotkey))
        selRecordBtn.frame = NSRect(x: 20, y: selY - 80, width: 180, height: 42)
        selRecordBtn.bezelStyle = .rounded
        selRecordBtn.font = .systemFont(ofSize: 20, weight: .medium)
        v.addSubview(selRecordBtn)
        selectionHotkeyRecordBtn = selRecordBtn

        let selStatus = NSTextField(labelWithString: "点击上方按钮开始录制新快捷键")
        selStatus.frame = NSRect(x: 210, y: selY - 70, width: w - 230, height: 30)
        selStatus.font = .systemFont(ofSize: 12)
        selStatus.textColor = .secondaryLabelColor
        selStatus.lineBreakMode = .byWordWrapping
        v.addSubview(selStatus)
        selectionHotkeyStatusLabel = selStatus

        // ---- 3. ESC 关闭翻译面板 ----
        let escY = selY - 150
        let escTitle = NSTextField(labelWithString: "📋 关闭翻译面板")
        escTitle.frame = NSRect(x: 20, y: escY, width: 300, height: 22)
        escTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(escTitle)

        let escDesc = NSTextField(labelWithString: "翻译浮动面板显示时，按下 ESC 键即可关闭")
        escDesc.frame = NSRect(x: 20, y: escY - 24, width: w - 40, height: 16)
        escDesc.font = .systemFont(ofSize: 11)
        escDesc.textColor = .secondaryLabelColor
        v.addSubview(escDesc)

        let escKeyBox = NSTextField(labelWithString: "    Esc    ")
        escKeyBox.frame = NSRect(x: 20, y: escY - 65, width: 80, height: 32)
        escKeyBox.font = .systemFont(ofSize: 18, weight: .medium)
        escKeyBox.isBezeled = true
        escKeyBox.isEditable = false
        escKeyBox.isSelectable = false
        escKeyBox.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5)
        escKeyBox.alignment = .center
        v.addSubview(escKeyBox)

        let escFixed = NSTextField(labelWithString: "系统内置，不可修改")
        escFixed.frame = NSRect(x: 112, y: escY - 56, width: 200, height: 20)
        escFixed.font = .systemFont(ofSize: 12)
        escFixed.textColor = .tertiaryLabelColor
        v.addSubview(escFixed)

        // ---- 统一提示 ----
        let infoLabel = NSTextField(labelWithString: """
        💡 提示：
        • 截图翻译：任意位置按下快捷键 → 框选区域 → 自动翻译
        • 划词翻译：先选中文字 → 按下快捷键 → 自动翻译（更快捷）
        • 关闭面板：翻译浮动面板显示时，按 ESC 键即可关闭
        • 必须组合键：⌘Command、⌥Option、⌃Control、⇧Shift + 任意按键（单个字母无效）
        • 红色代表未保存，点击「保存并应用」立即生效
        • 录制时若检测到与系统快捷键冲突，会给出黄色提醒
        """)
        infoLabel.frame = NSRect(x: 20, y: escY - 190, width: w - 40, height: 100)
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.lineBreakMode = .byWordWrapping
        v.addSubview(infoLabel)

        return v
    }

    @objc private func startRecordingHotkey() {
        guard !isRecordingHotkey else { return }
        isRecordingHotkey = true
        recordedKeyCode = 0
        recordedModifiers = 0

        hotkeyRecordBtn?.title = "  ... 按下组合键 ...  "
        hotkeyRecordBtn?.bezelColor = .systemOrange
        hotkeyStatusLabel?.stringValue = "请按下组合键..."

        // 监听全局按键（通过 NSEvent 本地监听）
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecordingHotkey else { return event }
            self.recordHotkey(event: event)
            return nil // 消费事件
        }

        // 如果 10 秒内没按，自动取消
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.isRecordingHotkey else { return }
            self.cancelRecording()
        }
    }

    private func recordHotkey(event: NSEvent) {
        let carbonModifiers = cocoaToCarbonModifiers(event.modifierFlags)
        let keyCode = Int(event.keyCode)

        // 必须有修饰键（禁止单个字母）
        guard hotkeyHasRequiredModifiers(carbonModifiers) else {
            cancelRecording()
            hotkeyStatusLabel?.stringValue = "❌ 单个字母不能作为快捷键\n请同时按住 ⌘ / ⌥ / ⌃ / ⇧ 之一再按字母"
            hotkeyRecordBtn?.bezelColor = .systemRed
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.hotkeyRecordBtn?.bezelColor = nil
            }
            return
        }

        recordedKeyCode = keyCode
        recordedModifiers = carbonModifiers
        isRecordingHotkey = false

        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }

        let display = hotkeyDisplayString(keyCode: recordedKeyCode, modifiers: recordedModifiers)
        hotkeyRecordBtn?.title = "    \(display)    "
        hotkeyRecordBtn?.bezelColor = .systemGreen
        var status = "✅ 已录制：\(display)\n点击「保存并应用」使快捷键生效"
        if let conflict = checkSystemHotkeyConflict(modifiers: recordedModifiers, keyCode: recordedKeyCode) {
            status += "\n⚠️ 可能与系统快捷键冲突：\(conflict)"
            hotkeyRecordBtn?.bezelColor = .systemOrange
        }
        hotkeyStatusLabel?.stringValue = status

        // 闪烁效果后恢复
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.hotkeyRecordBtn?.bezelColor = nil
        }
    }

    private func cancelRecording() {
        isRecordingHotkey = false
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
        let display = SettingsManager.shared.hotkeyDisplay
        hotkeyRecordBtn?.title = "    \(display)    "
        hotkeyRecordBtn?.bezelColor = nil
        hotkeyStatusLabel?.stringValue = "录制超时，请重试"
    }

    // MARK: - 划词翻译快捷键录制

    @objc private func startRecordingSelectionHotkey() {
        guard !isRecordingSelectionHotkey, !isRecordingHotkey else { return }
        isRecordingSelectionHotkey = true
        recordedSelectionKeyCode = 0
        recordedSelectionModifiers = 0

        selectionHotkeyRecordBtn?.title = "  ... 按下组合键 ...  "
        selectionHotkeyRecordBtn?.bezelColor = .systemOrange
        selectionHotkeyStatusLabel?.stringValue = "请按下组合键..."

        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecordingSelectionHotkey else { return event }
            self.recordSelectionHotkey(event: event)
            return nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.isRecordingSelectionHotkey else { return }
            self.cancelSelectionRecording()
        }
    }

    private func recordSelectionHotkey(event: NSEvent) {
        let carbonModifiers = cocoaToCarbonModifiers(event.modifierFlags)
        let keyCode = Int(event.keyCode)

        // 必须有修饰键（禁止单个字母）
        guard hotkeyHasRequiredModifiers(carbonModifiers) else {
            cancelSelectionRecording()
            selectionHotkeyStatusLabel?.stringValue = "❌ 单个字母不能作为快捷键\n请同时按住 ⌘ / ⌥ / ⌃ / ⇧ 之一再按字母"
            selectionHotkeyRecordBtn?.bezelColor = .systemRed
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.selectionHotkeyRecordBtn?.bezelColor = nil
            }
            return
        }

        recordedSelectionKeyCode = keyCode
        recordedSelectionModifiers = carbonModifiers
        isRecordingSelectionHotkey = false

        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }

        let display = hotkeyDisplayString(keyCode: recordedSelectionKeyCode, modifiers: recordedSelectionModifiers)
        selectionHotkeyRecordBtn?.title = "    \(display)    "
        selectionHotkeyRecordBtn?.bezelColor = .systemGreen
        var status = "✅ 已录制：\(display)\n点击「保存并应用」使快捷键生效"
        if let conflict = checkSystemHotkeyConflict(modifiers: recordedSelectionModifiers, keyCode: recordedSelectionKeyCode) {
            status += "\n⚠️ 可能与系统快捷键冲突：\(conflict)"
            selectionHotkeyRecordBtn?.bezelColor = .systemOrange
        }
        selectionHotkeyStatusLabel?.stringValue = status

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.selectionHotkeyRecordBtn?.bezelColor = nil
        }
    }

    private func cancelSelectionRecording() {
        isRecordingSelectionHotkey = false
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
        let display = SettingsManager.shared.selectionHotkeyDisplay
        selectionHotkeyRecordBtn?.title = "    \(display)    "
        selectionHotkeyRecordBtn?.bezelColor = nil
        selectionHotkeyStatusLabel?.stringValue = "录制超时，请重试"
    }

    // MARK: - Tab 3: 翻译模板

    private func buildTemplateTab(size: NSSize) -> NSView {
        let v = NSView(frame: NSRect(origin: .zero, size: size))
        let w = size.width

        let titleLabel = NSTextField(labelWithString: "翻译提示词模板（可编辑）")
        titleLabel.frame = NSRect(x: 20, y: size.height - 30, width: 400, height: 22)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: "AI 将按此模板输出翻译结果。支持 Markdown 格式。")
        descLabel.frame = NSRect(x: 20, y: size.height - 52, width: w - 40, height: 16)
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        v.addSubview(descLabel)

        // 编辑器（左半边）
        let editorScroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: w/2 - 30, height: size.height - 90))
        editorScroll.hasVerticalScroller = true
        editorScroll.borderType = .bezelBorder
        editorScroll.autohidesScrollers = true

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: editorScroll.contentSize.width, height: editorScroll.contentSize.height))
        tv.string = SettingsManager.shared.systemPrompt
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.isEditable = true
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.textContainerInset = NSSize(width: 8, height: 8)
        // 实时预览：编辑时更新
        tv.delegate = self
        editorScroll.documentView = tv
        v.addSubview(editorScroll)
        templateTextView = tv

        // 预览面板（右半边）
        let previewScroll = NSScrollView(frame: NSRect(x: w/2 + 10, y: 20, width: w/2 - 30, height: size.height - 90))
        previewScroll.hasVerticalScroller = true
        previewScroll.borderType = .bezelBorder
        previewScroll.autohidesScrollers = true

        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: previewScroll.contentSize.width, height: previewScroll.contentSize.height), configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        wv.loadHTMLString(templatePreviewHTML(), baseURL: nil)
        previewScroll.documentView = wv
        v.addSubview(previewScroll)
        templatePreviewWebView = wv

        return v
    }

    private func templatePreviewHTML() -> String {
        let prompt = templateTextView?.string ?? SettingsManager.shared.systemPrompt
        let escaped = prompt
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
            :root{color-scheme:light dark}*{box-sizing:border-box;margin:0;padding:0}
            body{font-family:-apple-system,"PingFang SC",sans-serif;font-size:11px;line-height:1.5;color:#555;padding:10px 12px;background:#fff}
            @media(prefers-color-scheme:dark){body{color:#aaa;background:#2c2c2e}}
            .preview-title{font-size:12px;font-weight:600;color:#0071e3;margin-bottom:8px;border-bottom:1px solid #e5e5e7;padding-bottom:6px}
            @media(prefers-color-scheme:dark){.preview-title{color:#0a84ff;border-color:#3a3a3c}}
            .prompt-text{white-space:pre-wrap;word-break:break-word}
        </style>
        </head><body>
        <div class="preview-title">📋 模板预览（AI 将按此结构输出）</div>
        <div class="prompt-text">\(escaped)</div>
        </body></html>
        """
    }

    // MARK: - Actions

    /// 切换 API Key 输入框的显隐（明文 ↔ 密文）
    @objc private func toggleApiKeyVisibility(_ sender: NSButton) {
        apiKeyVisible.toggle()
        if apiKeyVisible {
            // 切到明文：密文框内容同步到明文框
            apiKeyVisibleField?.stringValue = apiKeyHiddenField?.stringValue ?? ""
            apiKeyVisibleField?.isHidden = false
            apiKeyHiddenField?.isHidden = true
            apiKeyEyeButton?.title = "🔓"
            apiKeyVisibleField?.window?.makeFirstResponder(apiKeyVisibleField)
        } else {
            // 切到密文：明文框内容同步到密文框
            apiKeyHiddenField?.stringValue = apiKeyVisibleField?.stringValue ?? ""
            apiKeyHiddenField?.isHidden = false
            apiKeyVisibleField?.isHidden = true
            apiKeyEyeButton?.title = "🔐"
            apiKeyHiddenField?.window?.makeFirstResponder(apiKeyHiddenField)
        }
    }

    /// 获取当前显示的 API Key 文本（无论明文/密文模式）
    private var activeApiKeyFieldValue: String {
        if apiKeyVisible {
            return apiKeyVisibleField?.stringValue ?? ""
        } else {
            return apiKeyHiddenField?.stringValue ?? ""
        }
    }

    @objc private func saveAllSettings() {
        let settings = SettingsManager.shared

        // API Key — 保存当前提供商的 Key
        let keyStr = activeApiKeyFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyStr.isEmpty {
            settings.setApiKey(keyStr, for: settings.apiProvider)
        } else {
            // 清空 Key
            settings.setApiKey(nil, for: settings.apiProvider)
        }

        // 自定义 Endpoint & Model
        if let ep = customEndpointField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !ep.isEmpty {
            settings.customEndpoint = ep
        }
        if let mdl = customModelField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !mdl.isEmpty {
            if settings.apiProvider == .ollama {
                settings.ollamaModel = mdl
            } else {
                settings.customModel = mdl
            }
        }

        // 快捷键
        if recordedKeyCode != 0 {
            settings.hotkeyKeyCode = recordedKeyCode
            settings.hotkeyModifiers = recordedModifiers
            settings.hotkeyDisplay = hotkeyDisplayString(keyCode: recordedKeyCode, modifiers: recordedModifiers)
        }

        // 划词翻译快捷键
        if recordedSelectionKeyCode != 0 {
            settings.selectionHotkeyKeyCode = recordedSelectionKeyCode
            settings.selectionHotkeyModifiers = recordedSelectionModifiers
            settings.selectionHotkeyDisplay = hotkeyDisplayString(keyCode: recordedSelectionKeyCode, modifiers: recordedSelectionModifiers)
        }

        // 重新注册所有快捷键
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.reregisterHotkey()
        }

        // 翻译模板
        if let template = templateTextView?.string, !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.systemPrompt = template
        }

        logi("设置已保存")
        window?.close()
    }

    @objc private func resetAll() {
        let alert = NSAlert()
        alert.messageText = "恢复默认设置"
        alert.informativeText = "将恢复 API Key 以外的所有设置为默认值，包括快捷键和翻译模板。确定继续？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        alert.layout()
        alert.window.level = .floating
        alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if alert.runModal() != .alertFirstButtonReturn { return }

        let settings = SettingsManager.shared
        settings.systemPrompt = settings.defaultPrompt
        settings.hotkeyKeyCode = DEFAULT_HOTKEY_KEYCODE
        settings.hotkeyModifiers = Int(cmdKey)
        settings.hotkeyDisplay = "⌘T"
        settings.selectionHotkeyKeyCode = DEFAULT_SELECTION_HOTKEY_KEYCODE
        settings.selectionHotkeyModifiers = Int(cmdKey | shiftKey)
        settings.selectionHotkeyDisplay = "⇧⌘T"

        // 更新 UI
        templateTextView?.string = settings.defaultPrompt
        templatePreviewWebView?.loadHTMLString(templatePreviewHTML(), baseURL: nil)
        hotkeyRecordBtn?.title = "    ⌘T    "
        hotkeyStatusLabel?.stringValue = "已恢复默认快捷键 ⌘T"
        selectionHotkeyRecordBtn?.title = "    ⇧⌘T    "
        selectionHotkeyStatusLabel?.stringValue = "已恢复默认快捷键 ⇧⌘T"

        // 清除录制的临时值
        recordedKeyCode = 0
        recordedModifiers = 0
        recordedSelectionKeyCode = 0
        recordedSelectionModifiers = 0
    }

    // MARK: - 提供商切换

    @objc private func providerChanged(_ sender: NSPopUpButton) {
        guard let idx = AIProvider.allCases.firstIndex(where: { sender.titleOfSelectedItem == $0.displayName }) else { return }
        let newProvider = AIProvider.allCases[idx]
        let settings = SettingsManager.shared

        // 保存当前 Key 到当前提供商
        let currentKey = activeApiKeyFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentKey.isEmpty {
            settings.setApiKey(currentKey, for: settings.apiProvider)
        }

        // 保存自定义 Endpoint/Model
        if let ep = customEndpointField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !ep.isEmpty {
            settings.customEndpoint = ep
        }
        if let mdl = customModelField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !mdl.isEmpty {
            if settings.apiProvider == .ollama {
                settings.ollamaModel = mdl
            } else {
                settings.customModel = mdl
            }
        }

        // 切换提供商
        settings.apiProvider = newProvider

        // 重建卡片（刷新 UI）
        guard let scrollView = providerCardView?.superview as? NSScrollView else { return }
        let cardWidth = scrollView.contentSize.width
        let newCard = buildProviderCard(width: cardWidth, provider: newProvider)
        scrollView.documentView = newCard
        self.providerCardView = newCard
    }

    @objc private func testAPIKey() {
        let settings = SettingsManager.shared
        let provider = settings.apiProvider
        let key = activeApiKeyFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            let a = NSAlert(); a.messageText = "提示"; a.informativeText = "请先输入 API Key。"
            a.alertStyle = .informational; a.addButton(withTitle: "确定")
            a.layout(); a.window.level = .floating
            a.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            a.runModal(); return
        }

        testStatusLabel?.stringValue = "正在测试..."
        testStatusLabel?.textColor = .systemOrange

        let endpoint = provider.endpoint
        var body: [String: Any] = [:]
        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 15

        // 不同提供商的请求格式和认证方式
        switch provider {
        case .anthropic:
            req.setValue("x-api-key", forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            body = [
                "model": provider.defaultModel,
                "max_tokens": 5,
                "messages": [["role": "user", "content": "回复OK"]]
            ]
        case .googleAI:
            // Google Gemini uses API key as query param
            let googleEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(key)"
            req = URLRequest(url: URL(string: googleEndpoint)!)
            req.httpMethod = "POST"
            req.timeoutInterval = 15
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            body = [
                "contents": [["parts": [["text": "回复OK"]]]],
                "generationConfig": ["maxOutputTokens": 5]
            ]
        default:
            // OpenAI-compatible API（DeepSeek, OpenAI, 千问, Ollama 等）
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body = [
                "model": provider.defaultModel,
                "messages": [["role": "user", "content": "回复OK"]],
                "max_tokens": 5
            ]
        }

        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let sem = DispatchSemaphore(value: 0)
        var success = false; var errMsg = ""
        URLSession.shared.dataTask(with: req) { data, resp, error in
            defer { sem.signal() }
            if let e = error { errMsg = e.localizedDescription; return }
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 { success = true }
            else { errMsg = "状态码 \((resp as? HTTPURLResponse)?.statusCode ?? 0)" }
        }.resume()
        sem.wait()

        DispatchQueue.main.async {
            if success {
                self.testStatusLabel?.stringValue = "✅ 连接成功"
                self.testStatusLabel?.textColor = .systemGreen
            } else {
                self.testStatusLabel?.stringValue = "❌ 失败：\(errMsg)"
                self.testStatusLabel?.textColor = .systemRed
            }
        }
    }
}

// MARK: - NSTextViewDelegate (实时模板预览)

extension SettingsWindowController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView, tv == templateTextView else { return }
        templatePreviewWebView?.loadHTMLString(templatePreviewHTML(), baseURL: nil)
    }
}

// MARK: - 菜单栏控制器

final class StatusBarController {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "📖"
            button.toolTip = APP_DISPLAY_NAME
            // 设置合适的字体大小让 emoji 显示正常
            button.font = NSFont.systemFont(ofSize: 14)
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "📷 截图翻译", action: #selector(AppDelegate.screenshotTranslate), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "📝 划词翻译", action: #selector(AppDelegate.selectionTranslate), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "⚙️ 偏好设置...", action: #selector(AppDelegate.openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 \(APP_DISPLAY_NAME)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyRef: EventHotKeyRef?
    private var selectionHotkeyRef: EventHotKeyRef?
    private let settings = SettingsManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 后台应用模式（菜单栏运行）— 保障全局热键 + 全屏 Space 截图正常
        NSApp.setActivationPolicy(.accessory)

        // 稍后显示 Dock 图标（使用 kCurrentProcess 常量，避免已废弃的 GetCurrentProcess）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
            TransformProcessType(&psn, ProcessApplicationTransformState(kProcessTransformToForegroundApplication))
        }

        // 注册通知
        _ = NotificationManager.shared

        // 设置菜单栏
        StatusBarController.shared.setup()

        // 注册全局快捷键
        registerHotkey()

        // 启动时弹出设置窗口
        if settings.activeApiKey == nil || settings.activeApiKey!.isEmpty {
            logi("首次运行，API Key 未配置")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            SettingsWindowController.shared.show()
        }

        logi("\(APP_DISPLAY_NAME) 就绪 — Cmd+T 截图翻译 | Shift+Cmd+T 划词翻译 | 点击菜单栏 📖 操作")
    }

    /// 点击 Dock 图标时弹出设置窗口（保持 .accessory，不切换策略）
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    private func registerHotkey() {
        reregisterHotkey()
    }

    /// 重新注册快捷键（用户更改设置后调用）
    func reregisterHotkey() {
        // 先注销旧的
        if let ref = hotkeyRef { UnregisterEventHotKey(ref); hotkeyRef = nil }
        if let ref = selectionHotkeyRef { UnregisterEventHotKey(ref); selectionHotkeyRef = nil }

        // ---- 截图翻译热键（id=1） ----
        var hotkeyID1 = EventHotKeyID(signature: 0x534E5452, id: 1)  // "SNTR"
        let keyCode = settings.hotkeyKeyCode
        let modifiers = settings.hotkeyModifiers
        let s1 = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotkeyID1,
                                      GetApplicationEventTarget(), 0, &hotkeyRef)
        if s1 != noErr {
            hotkeyID1.id = 2
            let fbStatus = RegisterEventHotKey(0x78, UInt32(cmdKey), hotkeyID1,
                                                GetApplicationEventTarget(), 0, &hotkeyRef)
            if fbStatus == noErr {
                settings.hotkeyKeyCode = 0x78; settings.hotkeyModifiers = Int(cmdKey)
                settings.hotkeyDisplay = "⌘F2"
                logi("截图快捷键降级为 Cmd+F2")
            } else { loge("截图快捷键注册失败") }
        } else {
            settings.hotkeyDisplay = hotkeyDisplayString(keyCode: keyCode, modifiers: modifiers)
            logi("截图快捷键: \(settings.hotkeyDisplay)")
        }

        // ---- 划词翻译热键（id=10） ----
        var hotkeyID10 = EventHotKeyID(signature: 0x534E5452, id: 10)
        let selKeyCode = settings.selectionHotkeyKeyCode
        let selMods = settings.selectionHotkeyModifiers
        let s10 = RegisterEventHotKey(UInt32(selKeyCode), UInt32(selMods), hotkeyID10,
                                       GetApplicationEventTarget(), 0, &selectionHotkeyRef)
        if s10 == noErr {
            settings.selectionHotkeyDisplay = hotkeyDisplayString(keyCode: selKeyCode, modifiers: selMods)
            logi("划词快捷键: \(settings.selectionHotkeyDisplay)")
        } else {
            // 降级：Cmd+Shift+F2
            hotkeyID10.id = 11
            let fb2 = RegisterEventHotKey(0x78, UInt32(cmdKey | shiftKey), hotkeyID10,
                                           GetApplicationEventTarget(), 0, &selectionHotkeyRef)
            if fb2 == noErr {
                settings.selectionHotkeyKeyCode = 0x78
                settings.selectionHotkeyModifiers = Int(cmdKey | shiftKey)
                settings.selectionHotkeyDisplay = "⇧⌘F2"
                logi("划词快捷键降级为 ⇧⌘F2")
            } else { loge("划词快捷键注册失败") }
        }

        // 事件处理器（只安装一次，按 id 分发）
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(),
        { (_, evt, _) -> OSStatus in
            var hkID = EventHotKeyID()
            let err = GetEventParameter(evt, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if err == noErr {
                // 在快捷键事件上下文中立即捕获前台应用的 PID，
                // 避免 dispatch async 之后焦点已转移到自身导致读取失败
                let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                DispatchQueue.main.async {
                    if hkID.id == 10 || hkID.id == 11 {
                        // 划词翻译
                        TranslationPipeline.shared.selectionSourcePID = frontPID
                        TranslationPipeline.shared.startTextTranslation()
                    } else {
                        // 截图翻译
                        TranslationPipeline.shared.start()
                    }
                }
            }
            return noErr
        }, 1, &eventSpec, nil, nil)
    }

    @objc func screenshotTranslate() {
        TranslationPipeline.shared.start()
    }

    @objc func selectionTranslate() {
        TranslationPipeline.shared.startTextTranslation()
    }

    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScreenshotEngine.shared.cleanup()
        if let ref = hotkeyRef { UnregisterEventHotKey(ref) }
        if let ref = selectionHotkeyRef { UnregisterEventHotKey(ref) }
        logi("\(APP_DISPLAY_NAME) 已退出")
    }
}

// MARK: - 入口

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
