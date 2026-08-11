import Foundation

// MARK: - TextNormalizer Unit Tests

func runTextNormalizerTests() {
    // === 正常场景 ===
    test("collapses single newlines within one paragraph") {
        let input = "Line one\ncontinues\non next line"
        let expected = "Line one continues on next line"
        try assertEqual(TextNormalizer.normalizeLineBreaks(input), expected)
    }

    test("preserves double newlines as paragraph separators") {
        let input = "Para one line1\nline2\n\nPara two line1"
        let expected = "Para one line1 line2\n\nPara two line1"
        try assertEqual(TextNormalizer.normalizeLineBreaks(input), expected)
    }

    test("handles three paragraphs") {
        let input = "A\nB\n\nC\nD\n\nE\nF"
        let expected = "A B\n\nC D\n\nE F"
        try assertEqual(TextNormalizer.normalizeLineBreaks(input), expected)
    }

    // === 边界场景 ===
    test("unchanged for single line") {
        let input = "Single line"
        try assertEqual(TextNormalizer.normalizeLineBreaks(input), "Single line")
    }

    test("returns empty for empty string") {
        try assertEqual(TextNormalizer.normalizeLineBreaks(""), "")
    }

    test("trims trailing newlines") {
        let input = "text\n\n"
        try assertEqual(TextNormalizer.normalizeLineBreaks(input), "text")
    }

    test("trims leading newlines") {
        let input = "\n\ntext"
        try assertEqual(TextNormalizer.normalizeLineBreaks(input), "text")
    }

    test("collapses multiple blank lines") {
        let input = "A\n\n\nB"
        let expected = "A\n\nB"
        try assertEqual(TextNormalizer.normalizeLineBreaks(input), expected)
    }

    // === 缩进分段场景（Apple Books） ===
    test("tab-indented line starts new paragraph") {
        let input = "First paragraph\n\t\t\tSecond paragraph"
        let expected = "First paragraph\n\nSecond paragraph"
        try assertEqual(TextNormalizer.normalizeLineBreaks(input), expected)
    }

    test("mixed: inline continuation + tab-indented paragraph + standard paragraph") {
        let input = "A\nB\n\t\t\tC\n\nD\nE"
        let expected = "A B\n\nC\n\nD E"
        try assertEqual(TextNormalizer.normalizeLineBreaks(input), expected)
    }
}
