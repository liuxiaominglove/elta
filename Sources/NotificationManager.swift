import Cocoa
import UserNotifications

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
