import Foundation

// MARK: - TextPreprocessor Unit Tests

func runTextPreprocessorTests() {
    // === 正常场景：标准 Apple Books 引用 ===
    test("condenses standard Apple Books citation") {
        let input = "hello world\n\n摘录来自\nOutlive\nPeter Attia, MD\n此材料受版权保护。"
        let expected = "hello world\n\n摘录来自《Outlive》Peter Attia, MD"
        let result = TextPreprocessor.condenseCitation(input)
        try assertEqual(result, expected)
    }

    test("condenses citation when it is the only content") {
        let input = "摘录来自\nOutlive\nPeter Attia, MD\n此材料受版权保护。"
        let expected = "摘录来自《Outlive》Peter Attia, MD"
        let result = TextPreprocessor.condenseCitation(input)
        try assertEqual(result, expected)
    }

    test("condenses citation with Chinese title") {
        let input = "摘录来自\n三体\n刘慈欣\n此材料受版权保护。"
        let expected = "摘录来自《三体》刘慈欣"
        let result = TextPreprocessor.condenseCitation(input)
        try assertEqual(result, expected)
    }

    test("condenses citation with long title containing colon") {
        let input = "摘录来自\nSapiens: A Brief History of Humankind\nYuval Noah Harari\n此材料受版权保护。"
        let expected = "摘录来自《Sapiens: A Brief History of Humankind》Yuval Noah Harari"
        let result = TextPreprocessor.condenseCitation(input)
        try assertEqual(result, expected)
    }

    test("condenses citation with Arabic title and English author") {
        let input = "摘录来自\nأن تقتل طائرا بريئا\nHarper Lee\n此材料受版权保护。"
        let expected = "摘录来自《أن تقتل طائرا بريئا》Harper Lee"
        let result = TextPreprocessor.condenseCitation(input)
        try assertEqual(result, expected)
    }

    test("condenses citation with Japanese title and author") {
        let input = "摘录来自\nノルウェイの森\n村上春樹\n此材料受版权保护。"
        let expected = "摘录来自《ノルウェイの森》村上春樹"
        let result = TextPreprocessor.condenseCitation(input)
        try assertEqual(result, expected)
    }

    // === 边界场景：无引用块应直通 ===
    test("passes through text without citation") {
        let input = "This is a normal English sentence."
        let result = TextPreprocessor.condenseCitation(input)
        try assertEqual(result, input)
    }

    test("passes through empty string") {
        let input = ""
        let result = TextPreprocessor.condenseCitation(input)
        try assertEqual(result, "")
    }

    test("passes through text with only partial citation prefix") {
        let input = "摘录来自"
        let result = TextPreprocessor.condenseCitation(input)
        try assertEqual(result, "摘录来自")
    }

    test("passes through text where 摘录来自 appears in body not as citation") {
        let input = "文本中提到'摘录来自'这个词"
        let result = TextPreprocessor.condenseCitation(input)
        try assertEqual(result, input)
    }

    test("passes through incomplete citation missing title line") {
        let input = "摘录来自\n\n此材料受版权保护。"
        let result = TextPreprocessor.condenseCitation(input)
        try assertEqual(result, input)
    }

    test("condenses citation with only title (author line empty)") {
        let input = "摘录来自\nOutlive\n此材料受版权保护。"
        let expected = "摘录来自《Outlive》"
        let result = TextPreprocessor.condenseCitation(input)
        try assertEqual(result, expected)
    }

    test("condenses citation with content before and after") {
        let input = "A sentence.\n摘录来自\nBook\nAuthor\n此材料受版权保护。\nMore text."
        let expected = "A sentence.\n摘录来自《Book》Author\nMore text."
        let result = TextPreprocessor.condenseCitation(input)
        try assertEqual(result, expected)
    }

    // === 多引用场景 ===
    test("condenses multiple citations in text") {
        let input = "摘录来自\nBook1\nAuthor1\n此材料受版权保护。\n---\n摘录来自\nBook2\nAuthor2\n此材料受版权保护。"
        let expected = "摘录来自《Book1》Author1\n---\n摘录来自《Book2》Author2"
        let result = TextPreprocessor.condenseCitation(input)
        try assertEqual(result, expected)
    }
}
