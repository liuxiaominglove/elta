import Foundation

func runHTMLRendererTests() {
    print("\n--- HTMLRenderer Tests ---")

    // MARK: - HTML 转义测试

    test("escapeHTML escapes < > & \" characters") {
        let input = "price 5 < 10 \" & 3 > 1"
        let result = HTMLRenderer.escapeHTML(input)
        // 必须把 & 先转义，所以 "price 5 &lt; 10 &amp; 3 &gt; 1"
        try assertTrue(result.contains("&lt;"), "Should contain &lt; for <")
        try assertTrue(result.contains("&gt;"), "Should contain &gt; for >")
        try assertTrue(result.contains("&amp;"), "Should contain &amp; for &")
        try assertTrue(result.contains("&quot;"), "Should contain &quot; for \"")
    }

    test("escapeHTML handles script tag") {
        let input = #"<script>alert(1)</script>"#
        let result = HTMLRenderer.escapeHTML(input)
        try assertFalse(result.contains("<script>"), "Should not contain raw <script>")
        try assertTrue(result.contains("&lt;script&gt;"), "Should contain escaped script tag")
    }

    test("escapeHTML handles img onerror") {
        let input = #"<img src=x onerror="alert(1)">"#
        let result = HTMLRenderer.escapeHTML(input)
        try assertFalse(result.contains("<img"), "Should not contain raw <img")
        try assertTrue(result.contains("&lt;img"), "Should contain escaped img tag")
    }

    test("escapeHTML handles ampersand already in text") {
        let input = "A & B"
        let result = HTMLRenderer.escapeHTML(input)
        try assertEqual(result, "A &amp; B")
    }

    test("escapeHTML handles empty string") {
        let result = HTMLRenderer.escapeHTML("")
        try assertEqual(result, "")
    }

    // MARK: - render 方法安全性测试

    test("render escapes AI response markdown") {
        let markdown = ##"## 中文翻译\n包含 <script>alert('xss')</script> 的内容"##
        let original = "test"
        let html = HTMLRenderer.render(markdown: markdown, originalText: original, isDark: false)
        try assertFalse(html.contains("<script>"), "AI response should not contain executable script tags")
        try assertTrue(html.contains("&lt;script&gt;"), "Script tag should be HTML-escaped")
    }

    test("render escapes AI response with img onerror") {
        let markdown = ##"## 中文翻译\n图片 <img src=x onerror=alert(1)> in text"##
        let original = "test"
        let html = HTMLRenderer.render(markdown: markdown, originalText: original, isDark: false)
        try assertFalse(html.contains("<img"), "AI response should not contain raw <img tag")
        try assertTrue(html.contains("&lt;img"), "img tag should be HTML-escaped")
    }

    test("render preserves safe markdown formatting after escaping") {
        let markdown = ##"## 中文翻译\n这是 **加粗** 的内容"##
        let original = "test"
        let html = HTMLRenderer.render(markdown: markdown, originalText: original, isDark: false)
        try assertTrue(html.contains("<strong>"), "Bold markdown should still be converted")
        try assertTrue(html.contains("<h2>中文翻译</h2>"), "Heading should still be converted")
    }
}
