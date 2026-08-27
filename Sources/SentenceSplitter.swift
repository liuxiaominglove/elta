import Foundation

// MARK: - 拆分翻译（逐句对照）

/// 原文句与译文句的一对
struct SplitPair {
    let original: String
    let translation: String
}

/// 把原文（英文）与译文（中文）拆成句子并按下标配对，用于「拆分翻译」逐句对照视图。
/// 不重新请求 AI，只对已有译文做排版级拆分，因此对齐是「按下标最近邻」的尽力而为。
enum SentenceSplitter {

    /// 常见英文缩写（避免在缩写后的句号处误拆）
    private static let abbreviations: Set<String> = [
        "Mr", "Mrs", "Ms", "Dr", "Prof", "St", "Mt", "vs", "etc", "No",
        "Inc", "Ltd", "Jr", "Sr", "Co", "Gen", "Rep", "Sen", "Jan", "Feb",
        "Mar", "Apr", "Jun", "Jul", "Aug", "Sep", "Sept", "Oct", "Nov", "Dec"
    ]

    /// 含中间句点的多段缩写（"e.g." / "i.e." / "U.S." 等），匹配最后一个句点前的片段
    private static let multiDotAbbreviations: Set<String> = [
        "e.g", "i.e", "U.S", "U.K", "Ph.D", "M.D", "B.C", "A.D", "vs", "a.m", "p.m"
    ]

    /// 含空格的多词缩写（如 "et al."），按「前一词 + 句点前词」整体匹配
    private static let multiWordAbbreviations: Set<String> = [
        "et al"
    ]

    /// 匹配 Apple Books 引用元信息「摘录来自《书名》作者」（condenseCitation 压缩后的固定形状），拆分前整段剔除
    private static let citationRegex = try! NSRegularExpression(pattern: "摘录来自《[^》]+》[^\\n]*")

    // MARK: - 英文分句

    static func splitEnglish(_ text: String) -> [String] {
        // 先剔除「摘录来自《…》…」引用元信息，避免它被当成一句原文
        let range = NSRange(text.startIndex..., in: text)
        let cleaned = citationRegex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")

        var result: [String] = []
        let paragraphs = cleaned.components(separatedBy: "\n\n")
        for paragraph in paragraphs {
            let singleLine = paragraph
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !singleLine.isEmpty else { continue }
            result.append(contentsOf: splitEnglishSentences(singleLine))
        }
        return result
    }

    private static func splitEnglishSentences(_ text: String) -> [String] {
        let chars = Array(text)
        var sentences: [String] = []
        var start = 0
        var i = 0

        while i < chars.count {
            let c = chars[i]
            let isTerminator = (c == "." || c == "!" || c == "?")
            if isTerminator && !isAbbreviationDot(chars, at: i) {
                // 向前跳过紧跟的引号/括号等收尾符号
                var j = i + 1
                while j < chars.count, isClosingPunctuation(chars[j]) {
                    j += 1
                }
                if j >= chars.count {
                    let sentence = String(chars[start..<j]).trimmingCharacters(in: .whitespaces)
                    if !sentence.isEmpty { sentences.append(sentence) }
                    start = j
                    i = j
                    continue
                }
                if chars[j] == " " || chars[j] == "\t" || chars[j] == "\n" {
                    // 空白后：跳过空白，看下一个非空白字符是否开启新句（大写字母或数字）
                    var k = j
                    while k < chars.count, (chars[k] == " " || chars[k] == "\t" || chars[k] == "\n") {
                        k += 1
                    }
                    if k >= chars.count {
                        let sentence = String(chars[start..<j]).trimmingCharacters(in: .whitespaces)
                        if !sentence.isEmpty { sentences.append(sentence) }
                        start = j
                        i = j
                        continue
                    }
                    let next = chars[k]
                    // 跳过连续的左引号（如 “Based… / "Go…），取其后第一个字符判断是否开启新句
                    var m = k
                    while m < chars.count, isOpeningPunctuation(chars[m]) {
                        m += 1
                    }
                    let effectiveNext = m < chars.count ? chars[m] : next
                    if effectiveNext.isUppercase || effectiveNext.isNumber {
                        let sentence = String(chars[start..<j]).trimmingCharacters(in: .whitespaces)
                        if !sentence.isEmpty { sentences.append(sentence) }
                        start = j
                        i = j
                        continue
                    }
                    // 小写字母或其他 → 非句尾（et al. / 引号内句号 / 缩写漏网）
                }
            }
            i += 1
        }

        let tail = String(chars[start...]).trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }

    /// 判断 index 处的句点是否为缩写的一部分（不构成句尾）
    private static func isAbbreviationDot(_ chars: [Character], at index: Int) -> Bool {
        guard index >= 0, index < chars.count, chars[index] == "." else { return false }

        // 多段缩写："e.g." / "i.e." / "U.S." 等 —— 取句点前 3 个字符比对
        if index >= 3 {
            let seg = String(chars[(index - 3)..<index])
            if multiDotAbbreviations.contains(seg) { return true }
        }

        // 单词缩写："Mr." / "Dr." 等 —— 取句点前连续字母组成的单词
        var k = index - 1
        var word = ""
        while k >= 0, chars[k].isLetter {
            word.insert(chars[k], at: word.startIndex)
            k -= 1
        }
        if abbreviations.contains(word) { return true }

        // 多词缩写（含空格，如 "et al."）：回溯句点前的「前一词 + 空格 + 当前词」整体比对
        if !word.isEmpty {
            var m = k
            while m >= 0, chars[m] == " " { m -= 1 }
            var prev = ""
            while m >= 0, chars[m].isLetter {
                prev.insert(chars[m], at: prev.startIndex)
                m -= 1
            }
            if multiWordAbbreviations.contains("\(prev) \(word)") { return true }
        }

        // 单大写字母缩写："J." "K."
        if word.count == 1, let ch = word.first, ch.isUppercase { return true }

        return false
    }

    private static func isClosingPunctuation(_ c: Character) -> Bool {
        c == "\"" || c == "”" || c == "’" || c == ")" || c == "]" || c == "'"
            || c == "）" || c == "】" || c == "』" || c == "」" || c == "｣"
    }

    private static func isOpeningPunctuation(_ c: Character) -> Bool {
        c == "\"" || c == "“" || c == "‘" || c == "'" || c == "(" || c == "[" || c == "{"
            || c == "（" || c == "【" || c == "『" || c == "「" || c == "｢"
    }

    // MARK: - 中文分句

    static func splitChinese(_ text: String) -> [String] {
        var result: [String] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            result.append(contentsOf: splitChineseSentences(trimmed))
        }
        return result
    }

    /// 按句末标点（。！？…）拆分中文，保留标点（分号「；」表并列，不拆）
    private static func splitChineseSentences(_ text: String) -> [String] {
        let chars = Array(text)
        var sentences: [String] = []
        var start = 0
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "。" || c == "！" || c == "？" || c == "…" {
                // 跳过连续省略号（……）
                var j = i + 1
                while j < chars.count, chars[j] == "…" {
                    j += 1
                }
                // 跳过紧随的收尾引号/括号
                while j < chars.count, isClosingPunctuation(chars[j]) {
                    j += 1
                }
                let sentence = String(chars[start..<j]).trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty { sentences.append(sentence) }
                start = j
                i = j
                continue
            }
            i += 1
        }
        let tail = String(chars[start...]).trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }

    // MARK: - 配对

    /// 原文句与译文句配对。
    /// 句数一致时按下标逐句 1:1；句数不一致时按「字符数比例」贪心对齐，支持一对多/多对一合并。
    static func pair(original: String, translation: String) -> [SplitPair] {
        let originals = splitEnglish(original)
        let translations = splitChinese(translation)

        // 单侧为空：退回下标补齐（无长度可对齐）
        if originals.isEmpty {
            return translations.map { SplitPair(original: "", translation: $0) }
        }
        if translations.isEmpty {
            return originals.map { SplitPair(original: $0, translation: "") }
        }

        // 句数一致：快路径逐句 1:1
        if originals.count == translations.count {
            var pairs: [SplitPair] = []
            pairs.reserveCapacity(originals.count)
            for i in 0..<originals.count {
                pairs.append(SplitPair(original: originals[i], translation: translations[i]))
            }
            return pairs
        }

        // 句数不一致：长度比例贪心对齐
        if originals.count < translations.count {
            return alignConsumingTranslations(originals: originals, translations: translations)
        } else {
            return alignConsumingOriginals(originals: originals, translations: translations)
        }
    }

    /// 英文句少、中文句多：以英文句为骨架，每个英文句吃 ≥1 个中文句（一对多）
    private static func alignConsumingTranslations(originals: [String], translations: [String]) -> [SplitPair] {
        let eLens = originals.map { Double($0.count) }
        let cLens = translations.map { Double($0.count) }
        let totalE = eLens.reduce(0, +)
        let totalC = cLens.reduce(0, +)
        let ratio = totalE > 0 ? totalC / totalE : 1.0

        var pairs: [SplitPair] = []
        pairs.reserveCapacity(originals.count)
        var j = 0
        for i in 0..<originals.count {
            let remainingEnglish = originals.count - i - 1
            // 最多吃掉的中文句数，保证后续每个英文句至少 1 个中文句
            let maxTake = translations.count - j - remainingEnglish
            let expected = eLens[i] * ratio
            var take = 1
            var acc = cLens[j]
            while take < maxTake {
                let next = cLens[j + take]
                if abs(acc + next - expected) < abs(acc - expected) {
                    acc += next
                    take += 1
                } else {
                    break
                }
            }
            // 最后一个骨架句必须吞掉剩余全部，避免尾部译文被静默丢弃
            if remainingEnglish == 0 { take = maxTake }
            let merged = translations[j..<(j + take)].joined(separator: "\n")
            pairs.append(SplitPair(original: originals[i], translation: merged))
            j += take
        }
        return pairs
    }

    /// 英文句多、中文句少：以中文句为骨架，每个中文句吃 ≥1 个英文句（多对一）
    private static func alignConsumingOriginals(originals: [String], translations: [String]) -> [SplitPair] {
        let eLens = originals.map { Double($0.count) }
        let cLens = translations.map { Double($0.count) }
        let totalE = eLens.reduce(0, +)
        let totalC = cLens.reduce(0, +)
        let ratio = totalC > 0 ? totalC / totalE : 1.0

        var pairs: [SplitPair] = []
        pairs.reserveCapacity(translations.count)
        var i = 0
        for j in 0..<translations.count {
            let remainingChinese = translations.count - j - 1
            let maxTake = originals.count - i - remainingChinese
            let expected = cLens[j] / ratio   // 中文句应占的英文字符数
            var take = 1
            var acc = eLens[i]
            while take < maxTake {
                let next = eLens[i + take]
                if abs(acc + next - expected) < abs(acc - expected) {
                    acc += next
                    take += 1
                } else {
                    break
                }
            }
            // 最后一个骨架句必须吞掉剩余全部，避免尾部原文被静默丢弃
            if remainingChinese == 0 { take = maxTake }
            let merged = originals[i..<(i + take)].joined(separator: " ")
            pairs.append(SplitPair(original: merged, translation: translations[j]))
            i += take
        }
        return pairs
    }

    /// 原文句数与译文句数是否一致（用于提示逐句对照可能错位）
    static func sentenceCountsMatch(original: String, translation: String) -> Bool {
        splitEnglish(original).count == splitChinese(translation).count
    }
}
