import Foundation

// 返回 needle 在 haystack 中首次出现的字符偏移，未找到返回 nil
func htmlOffset(_ needle: String, in haystack: String) -> Int? {
    guard let r = haystack.range(of: needle) else { return nil }
    return haystack.distance(from: haystack.startIndex, to: r.lowerBound)
}

// 提取 minified CSS 中的单条规则（selector{ ... }），未找到返回 nil
func cssRule(_ selector: String, in html: String) -> String? {
    guard let open = html.range(of: "\(selector){") else { return nil }
    guard let close = html.range(of: "}", range: open.upperBound..<html.endIndex) else { return nil }
    return String(html[open.lowerBound...close.lowerBound])
}

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

    // MARK: - 原文锁定（sticky 首行）布局测试

    test("render wraps translation body in content container") {
        let markdown = "## 中文翻译\n\n你好世界"
        let html = HTMLRenderer.render(markdown: markdown, originalText: "Hello world", isDark: false)
        let contentOpen = try assertNotNil(htmlOffset("<div class=\"content\">", in: html), "应存在 content 容器")
        let h2Translation = try assertNotNil(htmlOffset("<h2>中文翻译</h2>", in: html), "应存在译文标题")
        try assertTrue(contentOpen < h2Translation, "译文标题应位于 content 容器内")
    }

    test("render keeps footer inside content container") {
        let markdown = "## 中文翻译\n\n你好世界"
        let html = HTMLRenderer.render(markdown: markdown, originalText: "Hello world", isDark: false)
        let contentOpen = try assertNotNil(htmlOffset("<div class=\"content\">", in: html), "应存在 content 容器")
        let poweredBy = try assertNotNil(htmlOffset("Powered by", in: html), "应存在 footer")
        try assertTrue(contentOpen < poweredBy, "footer 应位于 content 容器内")
    }

    test("render handles empty markdown with content container") {
        let html = HTMLRenderer.render(markdown: "", originalText: "Hi", isDark: false)
        try assertTrue(html.contains("<div class=\"content\">"), "空 markdown 也应生成 content 容器")
    }

    test("render handles empty original text") {
        let html = HTMLRenderer.render(markdown: "## 中文翻译\n\n你好", originalText: "", isDark: false)
        try assertTrue(html.contains("original-box"), "原文盒应存在")
        try assertTrue(html.contains("<div class=\"content\">"), "content 容器应存在")
    }

    test("render removes body default padding") {
        let html = HTMLRenderer.render(markdown: "## 中文翻译\n\n你好", originalText: "Hi", isDark: false)
        try assertTrue(html.contains("padding:0"), "body 应无默认 padding")
        try assertFalse(html.contains("padding:20px 24px"), "不应残留旧的 20px 24px padding")
    }

    test("render makes original box sticky") {
        let html = HTMLRenderer.render(markdown: "## 中文翻译\n\n你好", originalText: "Hello", isDark: false)
        try assertTrue(html.contains("position:sticky"), "原文盒应 sticky")
        try assertTrue(html.contains("top:0"), "原文盒应贴顶")
        try assertTrue(html.contains("z-index:10"), "原文盒应有 z-index 覆盖滚动内容")
    }

    test("render light mode original box background") {
        let html = HTMLRenderer.render(markdown: "## 中文翻译\n\n你好", originalText: "Hi", isDark: false)
        try assertTrue(html.contains("body.light .original-box{background:#e8f0fe"), "light 模式原文盒应有浅蓝背景")
    }

    test("render dark mode original box background") {
        let html = HTMLRenderer.render(markdown: "## 中文翻译\n\n你好", originalText: "Hi", isDark: true)
        try assertTrue(html.contains("body class=\"dark\""), "dark 模式 body class")
        try assertTrue(html.contains("body.dark .original-box{background:#1c1c1e"), "dark 模式原文盒背景")
    }

    test("render empty original still sticky with label") {
        let html = HTMLRenderer.render(markdown: "## 中文翻译\n\n你好", originalText: "", isDark: false)
        try assertTrue(html.contains("📝 原文："), "原文标签应存在")
        try assertTrue(html.contains("position:sticky"), "空原文时原文盒仍 sticky")
    }

    test("render escapes special chars in original text") {
        let html = HTMLRenderer.render(markdown: "## 中文翻译\n\n你好", originalText: "A < B & C", isDark: false)
        try assertTrue(html.contains("&lt;"), "原文 < 应转义")
        try assertTrue(html.contains("&amp;"), "原文 & 应转义")
    }

    test("render adds max-height safeguard to original box") {
        let html = HTMLRenderer.render(markdown: "## 中文翻译\n\n你好", originalText: "Hi", isDark: false)
        let rule = try assertNotNil(cssRule(".original-box", in: html), "应存在 .original-box 规则")
        try assertTrue(rule.contains("max-height:50vh"), "原文盒应有最大高度上限")
        try assertTrue(rule.contains("overflow-y:auto"), "原文盒超长应内部滚动")
    }

    test("render scopes max-height to original box not content") {
        let html = HTMLRenderer.render(markdown: "## 中文翻译\n\n你好", originalText: "Hi", isDark: false)
        let obRule = try assertNotNil(cssRule(".original-box", in: html), "应存在 .original-box 规则")
        try assertTrue(obRule.contains("max-height:50vh"), "max-height 应挂在 .original-box")
        try assertTrue(obRule.contains("overflow-y:auto"), "overflow-y 应挂在 .original-box")
        let cRule = try assertNotNil(cssRule(".content", in: html), "应存在 .content 规则")
        try assertFalse(cRule.contains("overflow-y"), ".content 不应含 overflow-y")
    }

    test("render handles very long original text without crashing") {
        let long = "First line. " + String(repeating: "x", count: 5000) + "\n\nSecond paragraph."
        let html = HTMLRenderer.render(markdown: "## 中文翻译\n\n你好", originalText: long, isDark: false)
        try assertTrue(html.contains("original-box"), "长原文应正常渲染原文盒")
        try assertTrue(html.contains("<br><br>"), "多段落原文应保留段落分隔")
    }

    // MARK: - 顺序与回归测试

    test("render orders original box before translation before vocab before phrases") {
        let markdown = "## 中文翻译\n\n翻译\n\n## 重要词汇\n\n- **word** ｜ n ｜ 词\n\n## 常用短语与习语\n\n- phrase：短语"
        let html = HTMLRenderer.render(markdown: markdown, originalText: "Original", isDark: false)
        let ob = try assertNotNil(htmlOffset("original-box", in: html), "应存在原文盒")
        let t = try assertNotNil(htmlOffset("<h2>中文翻译</h2>", in: html), "应存在译文标题")
        let v = try assertNotNil(htmlOffset("<h2>重要词汇</h2>", in: html), "应存在词汇标题")
        let p = try assertNotNil(htmlOffset("<h2>常用短语与习语</h2>", in: html), "应存在短语标题")
        try assertTrue(ob < t && t < v && v < p, "顺序应为 原文 < 译文 < 词汇 < 短语")
    }

    test("render keeps vocab phrases and check inside content") {
        let markdown = "## 中文翻译\n\n翻译\n\n## 重要词汇\n\n- **word**\n\n## 常用短语与习语\n\n- phrase\n\n## 核查\n\n准确"
        let html = HTMLRenderer.render(markdown: markdown, originalText: "Original", isDark: false)
        let contentOpen = try assertNotNil(htmlOffset("<div class=\"content\">", in: html), "应存在 content 容器")
        let v = try assertNotNil(htmlOffset("<h2>重要词汇</h2>", in: html), "应存在词汇标题")
        let p = try assertNotNil(htmlOffset("<h2>常用短语与习语</h2>", in: html), "应存在短语标题")
        let c = try assertNotNil(htmlOffset("<h2>核查</h2>", in: html), "应存在核查标题")
        try assertTrue(v > contentOpen && p > contentOpen && c > contentOpen, "词汇/短语/核查应在 content 容器内")
    }
}
