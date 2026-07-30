import Cocoa
import Carbon

import Carbon
import Foundation

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
