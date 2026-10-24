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

        func addItem(_ title: String, action: Selector, target: AnyObject?, keyEquivalent: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
            item.target = target
            menu.addItem(item)
        }

        addItem("📷 截图翻译", action: #selector(AppDelegate.screenshotTranslate), target: NSApp.delegate)
        addItem("📝 划词翻译", action: #selector(AppDelegate.selectionTranslate), target: NSApp.delegate)
        menu.addItem(.separator())
        addItem("⚙️ 偏好设置...", action: #selector(AppDelegate.openSettings), target: NSApp.delegate, keyEquivalent: ",")
        menu.addItem(.separator())
        addItem("退出 \(APP_DISPLAY_NAME)", action: #selector(NSApplication.terminate(_:)), target: NSApp, keyEquivalent: "q")
        statusItem?.menu = menu
    }
}
