import Cocoa
import Foundation

// MARK: - 翻译引擎（多 AI 提供商支持）

final class TranslationEngine {
    static let shared = TranslationEngine()

    func translate(text: String, completion: @escaping (String?) -> Void) {
        let settings = SettingsManager.shared
        let provider = settings.apiProvider
        guard let key = settings.activeApiKey, !key.isEmpty else {
            logi("未配置 \(provider.displayName) API Key")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "未配置 API Key"
                alert.informativeText = "请前往 偏好设置 配置 \(provider.displayName) API Key。\n访问 \(provider.registerURL) 注册获取。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "打开偏好设置")
                alert.addButton(withTitle: "取消")
                alert.layout()
                alert.window.level = .floating
                alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn {
                    SettingsWindowController.shared.show()
                }
                NSApp.deactivate()
            }
            completion(nil)
            return
        }

        let messages: [[String: Any]] = [
            ["role": "system", "content": settings.systemPrompt],
            ["role": "user", "content": "请分析以下英文文本：\n\n\(text)"]
        ]

        var body: [String: Any] = [:]
        let endpoint = provider.endpoint
        var request: URLRequest

        switch provider {
        case .anthropic:
            guard let url = URL(string: endpoint) else { loge("无效 API 地址"); completion(nil); return }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": provider.defaultModel,
                "max_tokens": 4096,
                "system": settings.systemPrompt,
                "messages": [["role": "user", "content": "请分析以下英文文本：\n\n\(text)"]]
            ]

        case .googleAI:
            let googleEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(provider.defaultModel):generateContent"
            guard let url = URL(string: googleEndpoint) else { loge("无效 API 地址"); completion(nil); return }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            let fullPrompt = "\(settings.systemPrompt)\n\n请分析以下英文文本：\n\n\(text)"
            body = [
                "contents": [["parts": [["text": fullPrompt]]]],
                "generationConfig": ["maxOutputTokens": 4096, "temperature": 0.1]
            ]

        default:
            guard let url = URL(string: endpoint) else { loge("无效 API 地址"); completion(nil); return }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body = [
                "model": provider.defaultModel,
                "messages": messages,
                "temperature": 0.1,
                "max_tokens": 4096,
                "stream": false
            ]
        }

        request.timeoutInterval = 120

        do { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        catch { loge("JSON 序列化失败: \(error)"); completion(nil); return }

        logi("调用 \(provider.displayName) API...")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let e = error {
                loge("API 失败: 网络: \(e.localizedDescription)")
                completion(nil)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                loge("API 失败: 无效响应")
                completion(nil)
                return
            }
            guard let data = data else {
                loge("API 失败: 无数据")
                completion(nil)
                return
            }
            if http.statusCode != 200 {
                let b = String(data: data, encoding: .utf8) ?? ""
                loge("API 失败: HTTP \(http.statusCode): \(b.prefix(200))")
                completion(nil)
                return
            }

            let result = ResponseParser.parse(data: data, provider: provider)
            logi("API 返回 \(result?.count ?? 0) 字符")
            completion(result)
        }
        task.resume()
    }
}
