import Foundation

// 测试环境需要的全局常量（原定义在 Sources/main.swift，测试编译时不可同时包含两个 main.swift）
let APP_NAME          = "ELTA"
let APP_DISPLAY_NAME  = "ELTA"
let LOG_PATH = "\(NSHomeDirectory())/Library/Logs/elta_test.log"
let DEFAULT_HOTKEY_KEYCODE: Int = 0x11  // T
let DEFAULT_SELECTION_HOTKEY_KEYCODE: Int = 0x11  // T（配合 Shift）
let APP_SHORT_VERSION: String = "5.1.31"
let APP_BUILD_VERSION: String = "0"
let APP_FULL_VERSION: String = "\(APP_SHORT_VERSION) (\(APP_BUILD_VERSION))"
