import Foundation

enum TextPreprocessor {
    /// 检测并压缩 Apple Books 的四行中文引用块为单行。
    ///
    /// 支持两种格式：
    /// - 四行：`摘录来自\n<书名>\n<作者>\n此材料受版权保护。`  →  `摘录来自《书名》作者`
    /// - 三行：`摘录来自\n<书名>\n此材料受版权保护。`          →  `摘录来自《书名》`
    ///
    /// 无引用块的文本原样返回。
    static func condenseCitation(_ text: String) -> String {
        var result = text

        let pattern4 = "摘录来自\\n([^\\n]+)\\n([^\\n]+)\\n此材料受版权保护。"
        let pattern3 = "摘录来自\\n([^\\n]+)\\n此材料受版权保护。"

        if let r = try? NSRegularExpression(pattern: pattern4) {
            let range = NSRange(result.startIndex..., in: result)
            result = r.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "摘录来自《$1》$2")
        }
        if let r = try? NSRegularExpression(pattern: pattern3) {
            let range = NSRange(result.startIndex..., in: result)
            result = r.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "摘录来自《$1》")
        }
        return result
    }
}
