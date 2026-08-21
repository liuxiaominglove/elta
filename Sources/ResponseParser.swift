import Foundation

/// 解析 AI 提供商的 JSON 响应，提取翻译文本（DeepSeek / 千问均为 OpenAI 兼容格式）
struct ResponseParser {
    static func parse(data: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        if let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let msg = first["message"] as? [String: Any],
           let content = msg["content"] as? String {
            return content
        }
        return nil
    }
}
