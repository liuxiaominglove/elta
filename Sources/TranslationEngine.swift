import Cocoa
import Foundation

// MARK: - 翻译引擎（多 AI 提供商支持）

final class TranslationEngine {
    static let shared = TranslationEngine()

    /// 当前进行中的翻译请求（用于 ESC 取消）
    private var currentTask: URLSessionDataTask?

    /// 取消当前翻译请求
    func cancelCurrentTask() {
        currentTask?.cancel()
        currentTask = nil
    }

    func translate(text: String, completion: @escaping (String?) -> Void) {
        let settings = SettingsManager.shared
        let provider = settings.apiProvider
        let key = settings.activeApiKey ?? ""
        if key.isEmpty {
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
                } else {
                    NSApp.deactivate()
                }
                completion(nil)
            }
            return
        }

        let messages: [[String: Any]] = [
            ["role": "system", "content": settings.systemPrompt],
            ["role": "user", "content": "请分析以下英文文本：\n\n\(text)"]
        ]

        let endpoint = provider.endpoint
        guard let url = URL(string: endpoint) else { loge("无效 API 地址"); completion(nil); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body = Self.chatBody(provider: provider, model: provider.defaultModel, messages: messages)

        request.timeoutInterval = 120

        do { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        catch { loge("JSON 序列化失败: \(error)"); completion(nil); return }

        logi("调用 \(provider.displayName) API...")

        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            // 回调统一切主线程：completion 会被调用方用于更新 UI，避免后台线程触达 AppKit
            DispatchQueue.main.async {
                if let t = task, self?.currentTask === t { self?.currentTask = nil }
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
                    loge("API 失败: HTTP \(http.statusCode), 响应体长度=\(data.count) 字节")
                    completion(nil)
                    return
                }

                let result = ResponseParser.parse(data: data)
                logi("API 返回 \(result?.count ?? 0) 字符")
                completion(result)
            }
        }
        self.currentTask = task
        task?.resume()
    }

    /// 构造 OpenAI 兼容 Chat Completions 请求体。
    /// DeepSeek V4 默认开启思考模式（先生成长思维链再输出，显著变慢），此处显式关闭。
    static func chatBody(provider: AIProvider, model: String, messages: [[String: Any]]) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.1,
            "max_tokens": 4096,
            "stream": false
        ]
        if provider == .deepseek {
            body["thinking"] = ["type": "disabled"]
        }
        return body
    }
}
