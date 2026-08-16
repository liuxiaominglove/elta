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

    // MARK: - Markdown 表格 → HTML 表格

    test("render converts two-column markdown table to HTML table") {
        let markdown = "## 中文翻译\n\n| 列A | 列B |\n|---|---|\n| 1 | 2 |"
        let html = HTMLRenderer.render(markdown: markdown, originalText: "原文", isDark: false)
        try assertTrue(html.contains("<table>"), "应生成 <table>")
        try assertTrue(html.contains("<thead>"), "应生成 <thead>")
        try assertTrue(html.contains("<th>列A</th>"), "表头应含列A")
        try assertTrue(html.contains("<th>列B</th>"), "表头应含列B")
        try assertTrue(html.contains("<tbody>"), "应生成 <tbody>")
        try assertTrue(html.contains("<td>1</td>"), "数据行应含 1")
        try assertTrue(html.contains("<td>2</td>"), "数据行应含 2")
        try assertTrue(html.contains("</table>"), "应闭合 </table>")
    }

    test("render converts three-column markdown table") {
        let markdown = "| 结构 | 名称 | 比喻 |\n|---|---|---|\n| 外皮层 | 人脑 | 车夫 |\n| 内皮层 | 猴脑 | 白马 |"
        let html = HTMLRenderer.render(markdown: markdown, originalText: "原文", isDark: false)
        try assertTrue(html.contains("<th>结构</th>"), "表头应含结构")
        try assertTrue(html.contains("<th>比喻</th>"), "表头应含比喻")
        try assertTrue(html.contains("<td>车夫</td>"), "数据行应含车夫")
        try assertTrue(html.contains("<td>白马</td>"), "数据行应含白马")
    }

    test("render does not convert pipe line without separator to table") {
        let markdown = "## 中文翻译\n\n| 单列引用 |\n\n这是正文"
        let html = HTMLRenderer.render(markdown: markdown, originalText: "原文", isDark: false)
        try assertFalse(html.contains("<table>"), "无分隔行的 | 不应转成表格")
    }
}
