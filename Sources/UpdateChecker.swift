import Cocoa
import Foundation

final class UpdateChecker {
    static let shared = UpdateChecker()

    private let releasesURL = "https://api.github.com/repos/liuxiaominglove/elta/releases/latest"
    private let downloadPageURL = "https://autoelta.com/"

    private var hasChecked = false

    func check() {
        guard !hasChecked else { return }
        hasChecked = true

        // 主流程先跑起来，后台异步检查更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.performCheck()
        }
    }

    private func performCheck() {
        guard let url = URL(string: releasesURL) else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ELTA/\(APP_SHORT_VERSION)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let htmlURL = json["html_url"] as? String else { return }

                let remoteVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                guard self.isNewer(remote: remoteVersion, local: APP_SHORT_VERSION) else { return }

                let settings = SettingsManager.shared
                guard settings.skipUpdateVersion != remoteVersion else { return }

                DispatchQueue.main.async {
                    self.showUpdateAlert(version: remoteVersion, url: htmlURL)
                }
            } catch {}
        }
        task.resume()
    }

    private func isNewer(remote: String, local: String) -> Bool {
        let rv = remote.split(separator: ".").compactMap { Int($0) }
        let lv = local.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(rv.count, lv.count)

        for i in 0..<maxLen {
            let r = i < rv.count ? rv[i] : 0
            let l = i < lv.count ? lv[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    private func showUpdateAlert(version: String, url: String) {
        guard let window = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first else {
            // 没有窗口时给个通知
            let alert = NSAlert()
            alert.messageText = "发现新版本 v\(version)"
            alert.informativeText = "ELTA v\(version) 已发布。前往下载页面获取最新版。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "前往下载")
            alert.addButton(withTitle: "跳过此版本")
            alert.addButton(withTitle: "稍后提醒")
            alert.window.level = .floating
            alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            NSApp.activate(ignoringOtherApps: true)
            let result = alert.runModal()
            NSApp.deactivate()
            self.handleAlertResult(result, version: version, url: url)
            return
        }

        let alert = NSAlert()
        alert.messageText = "发现新版本 v\(version)"
        alert.informativeText = "当前版本：v\(APP_SHORT_VERSION)\n最新版本：v\(version)\n\n点击「前往下载」打开下载页面。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "跳过此版本")
        alert.addButton(withTitle: "稍后提醒")
        alert.window.level = .floating
        alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        NSApp.activate(ignoringOtherApps: true)
        alert.beginSheetModal(for: window) { [weak self] result in
            self?.handleAlertResult(result, version: version, url: url)
        }
    }

    private func handleAlertResult(_ result: NSApplication.ModalResponse, version: String, url: String) {
        switch result {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(URL(string: downloadPageURL)!)
        case .alertSecondButtonReturn:
            SettingsManager.shared.skipUpdateVersion = version
            logi("跳过版本: v\(version)")
        default:
            break
        }
    }
}
