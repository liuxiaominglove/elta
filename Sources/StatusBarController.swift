import Cocoa
import Carbon

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
