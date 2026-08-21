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
let LOG_PATH          = "\(NSHomeDirectory())/Library/Logs/elta.log"
let DEFAULT_HOTKEY_KEYCODE: Int = 0x11  // T
let DEFAULT_SELECTION_HOTKEY_KEYCODE: Int = 0x11  // T（配合 Shift）
let DEFAULT_SPLIT_HOTKEY_KEYCODE: Int = 0x02  // D（配合 Control）

// 运行时从 Info.plist 读取版本号（每次编译/打包时自动同步）
let APP_SHORT_VERSION: String = {
    guard let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
        fatalError("缺少 CFBundleShortVersionString — Info.plist 可能未正确打包")
    }
    return v
}()
let APP_BUILD_VERSION: String = {
    guard let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
        fatalError("缺少 CFBundleVersion — Info.plist 可能未正确打包")
    }
    return v
}()
let APP_FULL_VERSION: String = "\(APP_SHORT_VERSION) (\(APP_BUILD_VERSION))"

// 启动日志（须在所有模块初始化完成后调用）
logi("===== \(APP_DISPLAY_NAME) \(APP_FULL_VERSION) 启动 =====")

// MARK: - 入口

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
