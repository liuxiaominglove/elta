import Cocoa
import Foundation

final class UpdateChecker {
    static let shared = UpdateChecker()

    static let updateURL = "https://autoelta.com/api/update"
    static let downloadPageURL = "https://autoelta.com/"

    private var hasChecked = false

    func check() {
        guard !hasChecked else { return }
        hasChecked = true

        // 主流程先跑起来，后台异步检查更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.performCheck()
        }
    }

    /// 解析自建更新端点的响应：{"version":"5.6.0","url":"..."}
    /// 返回 nil 表示响应不合法（缺字段 / 空值 / 非 JSON / url 非 http(s) 协议）。
    static func parseUpdateResponse(_ data: Data) -> (version: String, url: String)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String,
              let url = json["url"] as? String else { return nil }
        let v = version.hasPrefix("v") ? String(version.dropFirst()) : version
        guard !v.isEmpty, !url.isEmpty else { return nil }
        // 只接受 http/https，拒绝 file://、javascript:、自定义 app scheme 等不可信协议
        guard let urlObj = URL(string: url),
              let scheme = urlObj.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return (version: v, url: url)
    }

    static func isNewer(remote: String, local: String) -> Bool {
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

    /// 是否需要提示更新：远程较新且未被用户跳过。
    static func shouldShowUpdate(remoteVersion: String, localVersion: String, skipVersion: String?) -> Bool {
        guard isNewer(remote: remoteVersion, local: localVersion) else { return false }
        if let skip = skipVersion, skip == remoteVersion { return false }
        return true
    }

    /// 构造更新检查 URL：开启匿名统计时附带 installID，否则不带。
    static func buildUpdateURL(telemetryEnabled: Bool, installID: String) -> String {
        if telemetryEnabled {
            return updateURL + "?id=" + installID
        }
        return updateURL
    }

    private func performCheck() {
        let settings = SettingsManager.shared
        let urlString = UpdateChecker.buildUpdateURL(telemetryEnabled: settings.telemetryEnabled,
                                                     installID: settings.installID)
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.setValue("ELTA/\(APP_SHORT_VERSION)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            guard let parsed = UpdateChecker.parseUpdateResponse(data) else { return }
            let remoteVersion = parsed.version
            guard UpdateChecker.shouldShowUpdate(remoteVersion: remoteVersion,
                                                 localVersion: APP_SHORT_VERSION,
                                                 skipVersion: settings.skipUpdateVersion) else { return }

            DispatchQueue.main.async {
                self.showUpdateAlert(version: remoteVersion, url: parsed.url)
            }
        }
        task.resume()
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
            // 打开前二次校验协议，防止不可信 URL 被打开；不合法则回退到官网下载页
            let fallback = URL(string: UpdateChecker.downloadPageURL)!
            var target = fallback
            if let u = URL(string: url),
               let scheme = u.scheme?.lowercased(),
               scheme == "https" || scheme == "http" {
                target = u
            }
            NSWorkspace.shared.open(target)
        case .alertSecondButtonReturn:
            SettingsManager.shared.skipUpdateVersion = version
            logi("跳过版本: v\(version)")
        default:
            break
        }
    }
}
