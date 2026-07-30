import Cocoa
import Foundation

import Foundation

// MARK: - 翻译引擎（多 AI 提供商支持）

final class TranslationEngine {
    static let shared = TranslationEngine()

    func translate(text: String) -> String? {
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
            return nil
        }

        let messages: [[String: Any]] = [
            ["role": "system", "content": settings.systemPrompt],
            ["role": "user", "content": "请分析以下英文文本：\n\n\(text)"]
        ]

        var body: [String: Any] = [:]
        let endpoint = provider.endpoint
        var request: URLRequest

        // 不同提供商的请求格式
        switch provider {
        case .anthropic:
            guard let url = URL(string: endpoint) else { loge("无效 API 地址"); return nil }
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
            guard let url = URL(string: googleEndpoint) else { loge("无效 API 地址"); return nil }
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
            // OpenAI-compatible API
            guard let url = URL(string: endpoint) else { loge("无效 API 地址"); return nil }
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
        catch { loge("JSON 序列化失败: \(error)"); return nil }

        logi("调用 \(provider.displayName) API...")
        let semaphore = DispatchSemaphore(value: 0)
        var resultText: String?
        var errorMsg: String?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let e = error { errorMsg = "网络: \(e.localizedDescription)"; return }
            guard let http = response as? HTTPURLResponse else { errorMsg = "无效响应"; return }
            guard let data = data else { errorMsg = "无数据"; return }
            if http.statusCode != 200 {
                let b = String(data: data, encoding: .utf8) ?? ""
                errorMsg = "HTTP \(http.statusCode): \(b.prefix(200))"; return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    switch provider {
                    case .anthropic:
                        // Anthropic 响应格式: { "content": [{"type": "text", "text": "..."}] }
                        if let content = json["content"] as? [[String: Any]],
                           let first = content.first,
                           let text = first["text"] as? String {
                            resultText = text
                        } else { errorMsg = "解析 Anthropic 响应失败" }
                    case .googleAI:
                        // Google Gemini 响应格式: { "candidates": [{"content": {"parts": [{"text": "..."}]}}] }
                        if let candidates = json["candidates"] as? [[String: Any]],
                           let first = candidates.first,
                           let content = first["content"] as? [String: Any],
                           let parts = content["parts"] as? [[String: Any]],
                           let firstPart = parts.first,
                           let text = firstPart["text"] as? String {
                            resultText = text
                        } else { errorMsg = "解析 Gemini 响应失败" }
                    default:
                        // OpenAI-compatible 响应格式: { "choices": [{"message": {"content": "..."}}] }
                        if let choices = json["choices"] as? [[String: Any]],
                           let first = choices.first,
                           let msg = first["message"] as? [String: Any],
                           let content = msg["content"] as? String {
                            resultText = content
                        } else { errorMsg = "解析响应失败" }
                    }
                } else { errorMsg = "解析响应失败" }
            } catch { errorMsg = "JSON 错误: \(error)" }
        }
        task.resume()
        semaphore.wait()

        if let err = errorMsg { loge("API 失败: \(err)"); return nil }
        logi("API 返回 \(resultText?.count ?? 0) 字符")
        return resultText
    }
}
