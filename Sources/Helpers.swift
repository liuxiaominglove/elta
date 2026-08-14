import Cocoa
import Carbon
import Security
import ApplicationServices

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

/// 支持 Cmd+C/V/X/A 的安全文本输入框（.accessory 应用无障碍 Edit 菜单）
final class PasteSecureTextField: NSSecureTextField {
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
    private static let newlineIndentRegex = try! NSRegularExpression(pattern: "\\n[\\t ]+")

    /// 段内单 \n 合并为空格，\n\n 保留为段落间隔，去掉首尾多余空行
    static func normalizeLineBreaks(_ text: String) -> String {
        // 预处理：换行+缩进（\n\t或\n 空格）→ 标准段落分隔
        var result = text
        let range = NSRange(result.startIndex..., in: result)
        result = newlineIndentRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "\n\n")
        let paragraphs = result.components(separatedBy: "\n\n")
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
        let valueData = key.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // 先尝试更新已存在项（保留旧值，避免"先删后加"失败丢 key）
        let update: [String: Any] = [kSecValueData as String: valueData]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = valueData
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess { loge("Keychain 写入失败: status=\(addStatus), account=\(account)") }
            return addStatus == errSecSuccess
        }
        loge("Keychain 写入失败: status=\(updateStatus), account=\(account)")
        return false
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

// MARK: - 剪贴板快照（深拷贝，避免 writeObjects 旧对象崩溃）

struct PasteboardSnapshot {
    struct ItemSnapshot {
        let types: [(type: NSPasteboard.PasteboardType, data: Data)]
    }
    let items: [ItemSnapshot]

    /// 深拷贝剪贴板内容：遍历每个条目每个类型，复制实际字节数据，不持有 NSPasteboardItem 引用
    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item -> ItemSnapshot in
            let types = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
            return ItemSnapshot(types: types)
        }
        return PasteboardSnapshot(items: items)
    }

    /// 用快照数据重建全新的 NSPasteboardItem 并写回，返回是否成功
    @discardableResult
    func restore(to pasteboard: NSPasteboard) -> Bool {
        let newItems: [NSPasteboardItem] = items.map { itemSnapshot in
            let newItem = NSPasteboardItem()
            for (type, data) in itemSnapshot.types {
                newItem.setData(data, forType: type)
            }
            return newItem
        }
        // 空快照 = 恢复成空状态，显式清空
        if newItems.isEmpty {
            pasteboard.clearContents()
            return true
        }
        // 非空：直接用 writeObjects 原子替换（不先 clearContents，避免写失败丢原内容）
        return pasteboard.writeObjects(newItems)
    }
}
