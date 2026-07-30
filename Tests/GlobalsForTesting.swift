import Foundation

// 测试环境需要的全局常量（原定义在 Sources/main.swift，测试编译时不可同时包含两个 main.swift）
let LOG_PATH = "\(NSHomeDirectory())/Library/Logs/elta_test.log"
let DEFAULT_HOTKEY_KEYCODE: Int = 0x11  // T
let DEFAULT_SELECTION_HOTKEY_KEYCODE: Int = 0x11  // T（配合 Shift）
