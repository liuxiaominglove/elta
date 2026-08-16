import Foundation

// MARK: - OCR 段落检测单元测试

func runTableExtractorTests() {
    test("blocks with small gap are joined with single newline") {
        let blocks = [
            OCRBlock(text: "Line one", boundingBox: CGRect(x: 50, y: 10, width: 500, height: 14)),
            OCRBlock(text: "Line two", boundingBox: CGRect(x: 50, y: 28, width: 500, height: 14)),
        ]
        let result = TableExtractor.process(blocks: blocks)
        try assertTrue(result.contains("Line one\nLine two"), "Should join with single newline")
    }

    test("large vertical gap inserts paragraph break") {
        let blocks = [
            OCRBlock(text: "Para one", boundingBox: CGRect(x: 50, y: 10, width: 500, height: 14)),
            OCRBlock(text: "Para two", boundingBox: CGRect(x: 50, y: 50, width: 500, height: 14)),
        ]
        let result = TableExtractor.process(blocks: blocks)
        try assertTrue(result.contains("Para one\n\nPara two"), "Should have paragraph break")
    }

    test("indented line starts new paragraph") {
        let blocks = [
            OCRBlock(text: "End of para", boundingBox: CGRect(x: 50, y: 10, width: 500, height: 14)),
            OCRBlock(text: "New para", boundingBox: CGRect(x: 80, y: 28, width: 470, height: 14)),
        ]
        let result = TableExtractor.process(blocks: blocks)
        try assertTrue(result.contains("End of para\n\nNew para"), "Indent should start new paragraph")
    }

    test("short line (paragraph end) followed by normal line starts new paragraph") {
        let blocks = [
            OCRBlock(text: "Short end line", boundingBox: CGRect(x: 50, y: 10, width: 200, height: 14)),
            OCRBlock(text: "Next paragraph starts", boundingBox: CGRect(x: 50, y: 28, width: 500, height: 14)),
        ]
        let result = TableExtractor.process(blocks: blocks)
        try assertTrue(result.contains("Short end line\n\nNext paragraph starts"), "Short line should end paragraph")
    }

    test("normal continuation lines stay in same paragraph") {
        let blocks = [
            OCRBlock(text: "This is the first line of the paragraph",
                      boundingBox: CGRect(x: 50, y: 10, width: 500, height: 14)),
            OCRBlock(text: "continuing on the second line here",
                      boundingBox: CGRect(x: 50, y: 27, width: 500, height: 14)),
            OCRBlock(text: "and the third line finishes it",
                      boundingBox: CGRect(x: 50, y: 44, width: 500, height: 14)),
        ]
        let result = TableExtractor.process(blocks: blocks)
        let lines = result.components(separatedBy: "\n\n")
        try assertEqual(lines.count, 1)
    }

    test("tableMarkdown: 三列表格返回 Markdown 表格") {
        let blocks = [
            OCRBlock(text: "H1", boundingBox: CGRect(x: 100, y: 10, width: 100, height: 14)),
            OCRBlock(text: "H2", boundingBox: CGRect(x: 250, y: 10, width: 100, height: 14)),
            OCRBlock(text: "H3", boundingBox: CGRect(x: 400, y: 10, width: 100, height: 14)),
            OCRBlock(text: "R1C1", boundingBox: CGRect(x: 100, y: 40, width: 100, height: 14)),
            OCRBlock(text: "R1C2", boundingBox: CGRect(x: 250, y: 40, width: 100, height: 14)),
            OCRBlock(text: "R1C3", boundingBox: CGRect(x: 400, y: 40, width: 100, height: 14)),
        ]
        let table = try assertNotNil(TableExtractor.tableMarkdown(blocks), "应为表格")
        try assertTrue(table.contains("| H1 | H2 | H3 |"), "表头")
        try assertTrue(table.contains("| R1C1 | R1C2 | R1C3 |"), "数据行")
    }

    test("tableMarkdown: 单列文本返回 nil") {
        let blocks = [
            OCRBlock(text: "line one", boundingBox: CGRect(x: 100, y: 10, width: 500, height: 14)),
            OCRBlock(text: "line two", boundingBox: CGRect(x: 100, y: 28, width: 500, height: 14)),
        ]
        try assertNil(TableExtractor.tableMarkdown(blocks))
    }

    // ━━━ 审计修复：Tab 分隔转 Markdown 表格必须转义单元格内的管道符/换行 ━━━

    test("detectAndConvertTabSeparated escapes literal pipe in cell") {
        let input = "H1\tH2\nA\tB|C"
        let result = TableExtractor.detectAndConvertTabSeparated(input)
        try assertTrue(result.contains("| H1 | H2 |"), "表头")
        try assertTrue(result.contains("| A | B\\|C |"), "数据行单元格含 | 应被转义")
        try assertFalse(result.contains("B|C |"), "未转义的 | 不应出现在单元格分隔之外")
    }

    test("detectAndConvertTabSeparated escapes pipe in header") {
        let input = "Title|Subtitle\tNotes\nA\tB"
        let result = TableExtractor.detectAndConvertTabSeparated(input)
        try assertTrue(result.contains("| Title\\|Subtitle | Notes |"), "表头单元格含 | 应被转义")
    }

    test("detectAndConvertTabSeparated without pipe is unchanged") {
        let input = "H1\tH2\nA\tB"
        let result = TableExtractor.detectAndConvertTabSeparated(input)
        try assertTrue(result.contains("| A | B |"), "普通单元格不应被改动")
    }

    test("escapeMarkdownTableCell escapes pipe and newline") {
        try assertEqual(TableExtractor.escapeMarkdownTableCell("a|b"), "a\\|b")
        try assertEqual(TableExtractor.escapeMarkdownTableCell("a\nb"), "a b")
    }

    test("escapeMarkdownTableCell escapes backslash first") {
        try assertEqual(TableExtractor.escapeMarkdownTableCell("a\\|b"), "a\\\\\\|b")
    }
}
