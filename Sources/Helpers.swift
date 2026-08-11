import Cocoa
import Carbon
import Security
import ApplicationServices

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


// MARK: - 文本归一化

enum TextNormalizer {
    /// 段内单 \n 合并为空格，\n\n 保留为段落间隔，去掉首尾多余空行
    static func normalizeLineBreaks(_ text: String) -> String {
        let paragraphs = text.components(separatedBy: "\n\n")
        let processed = paragraphs.map { paragraph in
            paragraph
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }.filter { !$0.isEmpty }
        return processed.joined(separator: "\n\n")
    }
}

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
            kSecValueData as String: key.data(using: .utf8) ?? Data(),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess { loge("Keychain 写入失败: status=\(status), account=\(account)") }
        return status == errSecSuccess
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
        if status != errSecSuccess {
            if status != errSecItemNotFound { loge("Keychain 读取失败: status=\(status), account=\(account)") }
            return nil
        }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { loge("Keychain 删除失败: status=\(status), account=\(account)") }
        return status == errSecSuccess
    }
}
