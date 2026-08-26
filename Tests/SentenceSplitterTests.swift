import Foundation

func runSentenceSplitterTests() {
    print("\n--- SentenceSplitter Tests ---")

    // MARK: - 英文分句

    test("splitEnglish splits basic sentences") {
        let result = SentenceSplitter.splitEnglish("Hello world. This is a test. Goodbye.")
        try assertEqual(result, ["Hello world.", "This is a test.", "Goodbye."])
    }

    test("splitEnglish keeps question and exclamation marks") {
        let result = SentenceSplitter.splitEnglish("What is this? Really! Let's go.")
        try assertEqual(result, ["What is this?", "Really!", "Let's go."])
    }

    test("splitEnglish does not split after common abbreviation") {
        let result = SentenceSplitter.splitEnglish("Dr. Smith went home. He was tired.")
        try assertEqual(result, ["Dr. Smith went home.", "He was tired."])
    }

    test("splitEnglish does not split after e.g.") {
        let result = SentenceSplitter.splitEnglish("Some fruits, e.g. apples, are sweet. That's all.")
        try assertEqual(result, ["Some fruits, e.g. apples, are sweet.", "That's all."])
    }

    test("splitEnglish splits across paragraphs") {
        let result = SentenceSplitter.splitEnglish("First line.\n\nSecond paragraph here.")
        try assertEqual(result, ["First line.", "Second paragraph here."])
    }

    test("splitEnglish returns empty for empty input") {
        let result = SentenceSplitter.splitEnglish("")
        try assertEqual(result, [])
    }

    test("splitEnglish handles single sentence without terminator") {
        let result = SentenceSplitter.splitEnglish("no punctuation at all")
        try assertEqual(result, ["no punctuation at all"])
    }

    // MARK: - 中文分句

    test("splitChinese splits on 。！？ and keeps trailing 分号 as tail") {
        let result = SentenceSplitter.splitChinese("这是第一句。这是第二句！这是第三句？这是第四句；")
        try assertEqual(result, ["这是第一句。", "这是第二句！", "这是第三句？", "这是第四句；"])
    }

    test("splitChinese does not split on 分号 inside quotes") {
        let result = SentenceSplitter.splitChinese("他断言“食物中可找到良药；食物中也可找到劣药”，这一观点仍成立。")
        try assertEqual(result, ["他断言“食物中可找到良药；食物中也可找到劣药”，这一观点仍成立。"])
    }

    test("splitChinese does not split on 并列 分号") {
        let result = SentenceSplitter.splitChinese("甲；乙；丙。")
        try assertEqual(result, ["甲；乙；丙。"])
    }

    test("splitChinese preserves trailing punctuation") {
        let result = SentenceSplitter.splitChinese("你好。")
        try assertEqual(result, ["你好。"])
    }

    test("splitChinese splits across lines") {
        let result = SentenceSplitter.splitChinese("第一行。\n第二行。")
        try assertEqual(result, ["第一行。", "第二行。"])
    }

    test("splitChinese returns empty for empty input") {
        let result = SentenceSplitter.splitChinese("")
        try assertEqual(result, [])
    }

    test("splitChinese handles text without punctuation") {
        let result = SentenceSplitter.splitChinese("没有标点")
        try assertEqual(result, ["没有标点"])
    }

    // MARK: - 配对

    test("pair matches equal sentence counts by index") {
        let pairs = SentenceSplitter.pair(original: "Hello. World.", translation: "你好。世界。")
        try assertEqual(pairs.count, 2)
        try assertEqual(pairs[0].original, "Hello.")
        try assertEqual(pairs[0].translation, "你好。")
        try assertEqual(pairs[1].original, "World.")
        try assertEqual(pairs[1].translation, "世界。")
    }

    test("pair fills empty translation when original has more sentences") {
        let pairs = SentenceSplitter.pair(original: "One. Two. Three.", translation: "第一句。")
        try assertEqual(pairs.count, 3)
        try assertEqual(pairs[0].translation, "第一句。")
        try assertEqual(pairs[1].translation, "")
        try assertEqual(pairs[2].original, "Three.")
    }

    test("pair fills empty original when translation has more sentences") {
        let pairs = SentenceSplitter.pair(original: "One.", translation: "第一句。第二句。")
        try assertEqual(pairs.count, 2)
        try assertEqual(pairs[0].original, "One.")
        try assertEqual(pairs[1].original, "")
        try assertEqual(pairs[1].translation, "第二句。")
    }

    test("pair returns empty when both sides empty") {
        let pairs = SentenceSplitter.pair(original: "", translation: "")
        try assertEqual(pairs.count, 0)
    }

    // MARK: - WI-1 英文分句增强（边界识别）

    test("splitEnglish does not split after et al.") {
        let result = SentenceSplitter.splitEnglish("Smith et al. (2020) found it.")
        try assertEqual(result, ["Smith et al. (2020) found it."])
    }

    test("splitEnglish does not split after et al. followed by year") {
        let result = SentenceSplitter.splitEnglish("Smith et al. 2020 found it.")
        try assertEqual(result, ["Smith et al. 2020 found it."])
    }

    test("splitEnglish does not split after et al. followed by uppercase") {
        let result = SentenceSplitter.splitEnglish("Johnson et al. Nature published it.")
        try assertEqual(result, ["Johnson et al. Nature published it."])
    }

    test("splitEnglish does not split after single-letter initial") {
        let result = SentenceSplitter.splitEnglish("J. K. Rowling wrote it.")
        try assertEqual(result, ["J. K. Rowling wrote it."])
    }

    test("splitEnglish does not split inside quoted sentence") {
        let result = SentenceSplitter.splitEnglish(#"He said "Stop." and left."#)
        try assertEqual(result, [#"He said "Stop." and left."#])
    }

    test("splitEnglish does not split after decimal point") {
        let result = SentenceSplitter.splitEnglish("Version 1.2 is released.")
        try assertEqual(result, ["Version 1.2 is released."])
    }

    test("splitEnglish does not split after URL") {
        let result = SentenceSplitter.splitEnglish("Visit example.com and read more.")
        try assertEqual(result, ["Visit example.com and read more."])
    }

    test("splitEnglish handles very long text without punctuation") {
        let result = SentenceSplitter.splitEnglish(String(repeating: "x", count: 5000))
        try assertEqual(result.count, 1)
    }

    // MARK: - WI-2 中文分句增强（边界识别）

    test("splitChinese does not break ellipsis") {
        let result = SentenceSplitter.splitChinese("他走了……真的走了。")
        try assertEqual(result, ["他走了……", "真的走了。"])
    }

    test("splitChinese handles ellipsis before full-width closing bracket") {
        let result = SentenceSplitter.splitChinese("（内容省略……）然后继续。")
        try assertEqual(result, ["（内容省略……）", "然后继续。"])
    }

    test("splitChinese handles lone ellipsis") {
        let result = SentenceSplitter.splitChinese("……")
        try assertEqual(result, ["……"])
    }

    test("splitChinese does not break after full-width closing quote") {
        let result = SentenceSplitter.splitChinese("他说“你好。”然后走了。")
        try assertEqual(result, ["他说“你好。”", "然后走了。"])
    }

    // MARK: - 句数一致性

    test("sentenceCountsMatch returns true when counts equal") {
        let ok = SentenceSplitter.sentenceCountsMatch(original: "One. Two.", translation: "第一句。第二句。")
        try assertTrue(ok, "句数一致应返回 true")
    }

    test("sentenceCountsMatch returns false when counts differ") {
        let ok = SentenceSplitter.sentenceCountsMatch(original: "One. Two.", translation: "第一句。第二句。第三句。")
        try assertFalse(ok, "句数不一致应返回 false")
    }

    test("sentenceCountsMatch returns true for empty input") {
        let ok = SentenceSplitter.sentenceCountsMatch(original: "", translation: "")
        try assertTrue(ok, "空输入（0==0）应返回 true")
    }

    // MARK: - 摘录来自 引用块剔除

    test("splitEnglish removes citation block after double newline") {
        let result = SentenceSplitter.splitEnglish("Hello world.\n\n摘录来自《Outlive》Peter Attia, MD")
        try assertEqual(result, ["Hello world."])
    }

    test("splitEnglish removes citation block after single newline") {
        let result = SentenceSplitter.splitEnglish("Hello world.\n摘录来自《Outlive》Peter Attia, MD")
        try assertEqual(result, ["Hello world."])
    }

    test("splitEnglish removes citation-only text to empty") {
        let result = SentenceSplitter.splitEnglish("摘录来自《Outlive》Peter Attia, MD")
        try assertEqual(result, [])
    }

    test("splitEnglish does not remove bare 摘录来自 without book marks") {
        let result = SentenceSplitter.splitEnglish("This mentions 摘录来自 word.")
        try assertEqual(result, ["This mentions 摘录来自 word."])
    }

    test("pair aligns correctly after removing citation block") {
        let pairs = SentenceSplitter.pair(original: "One. Two.\n\n摘录来自《X》Y", translation: "第一。第二。")
        try assertEqual(pairs.count, 2)
        try assertEqual(pairs[0].original, "One.")
        try assertEqual(pairs[0].translation, "第一。")
        try assertEqual(pairs[1].original, "Two.")
        try assertEqual(pairs[1].translation, "第二。")
    }

    // MARK: - 左引号起始符（修复：句点后左引号+大写应拆句）

    test("splitEnglish splits before quoted sentence (curly quotes)") {
        let result = SentenceSplitter.splitEnglish("But instead he picked me. “Based on your previous career choice,” he said, “I suspect you are better prepared to deliver truly horrible news to people.”")
        try assertEqual(result, [
            "But instead he picked me.",
            "“Based on your previous career choice,” he said, “I suspect you are better prepared to deliver truly horrible news to people.”"
        ])
    }

    test("splitEnglish splits between two quoted sentences (straight quotes)") {
        let result = SentenceSplitter.splitEnglish(#"He said "Stop." "Go now.""#)
        try assertEqual(result, [#"He said "Stop.""#, #""Go now.""#])
    }

    test("splitEnglish does not split when opening quote followed by lowercase") {
        let result = SentenceSplitter.splitEnglish(#"He said "hello." "world.""#)
        try assertEqual(result, [#"He said "hello." "world.""#])
    }
}
