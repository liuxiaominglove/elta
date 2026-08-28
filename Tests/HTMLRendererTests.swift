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
        let markdown = "## 中文翻译\n包含 <script>alert('xss')</script> 的内容"
        let original = "test"
        let html = HTMLRenderer.render(markdown: markdown, originalText: original, isDark: false)
        try assertFalse(html.contains("<script>"), "AI response should not contain executable script tags")
        try assertTrue(html.contains("&lt;script&gt;"), "Script tag should be HTML-escaped")
    }

    test("render escapes AI response with img onerror") {
        let markdown = "## 中文翻译\n图片 <img src=x onerror=alert(1)> in text"
        let original = "test"
        let html = HTMLRenderer.render(markdown: markdown, originalText: original, isDark: false)
        try assertFalse(html.contains("<img"), "AI response should not contain raw <img tag")
        try assertTrue(html.contains("&lt;img"), "img tag should be HTML-escaped")
    }

    test("render preserves safe markdown formatting after escaping") {
        let markdown = "## 中文翻译\n这是 **加粗** 的内容"
        let original = "test"
        let html = HTMLRenderer.render(markdown: markdown, originalText: original, isDark: false)
        try assertTrue(html.contains("<strong>"), "Bold markdown should still be converted")
        try assertTrue(html.contains("<h2>中文翻译</h2>"), "Heading should still be converted")
    }

    test("render keeps literal asterisks inside inline code (not bold)") {
        let markdown = "参考 `**加粗**` 的用法"
        let html = HTMLRenderer.render(markdown: markdown, originalText: "x", isDark: false)
        try assertFalse(html.contains("<strong>加粗</strong>"), "代码内的 ** 不应被转成加粗")
        try assertTrue(html.contains("<code>"), "应保留 code 标签")
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

    test("render reverses escaped pipe in table cells") {
        let markdown = "## 中文翻译\n\n| 表达式 | 含义 |\n|---|---|\n| a\\|b | 管道 |"
        let html = HTMLRenderer.render(markdown: markdown, originalText: "原文", isDark: false)
        try assertTrue(html.contains("<td>a|b</td>"), "转义管道 \\| 应还原为 |")
        try assertTrue(html.contains("<td>管道</td>"), "普通单元格应正常渲染")
    }

    test("render reverses escaped backslash in table cells") {
        let markdown = "## 中文翻译\n\n| 路径 | 说明 |\n|---|---|\n| a\\\\b | 反斜杠 |"
        let html = HTMLRenderer.render(markdown: markdown, originalText: "原文", isDark: false)
        try assertTrue(html.contains("<td>a\\b</td>"), "转义反斜杠 \\\\ 应还原为 \\")
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

    // MARK: - 拆分翻译视图

    test("parseSections splits markdown into heading/body sections") {
        let markdown = "## 中文翻译\n\n你好世界\n\n## 重要词汇\n\n- **word**\n\n## 核查\n\n准确"
        let sections = HTMLRenderer.parseSections(markdown)
        try assertEqual(sections.count, 3)
        try assertEqual(sections[0].heading ?? "", "中文翻译")
        try assertEqual(sections[0].body, "你好世界")
        try assertEqual(sections[1].heading ?? "", "重要词汇")
        try assertEqual(sections[2].heading ?? "", "核查")
    }

    test("renderSplit produces split-pair with original and translation") {
        let markdown = "## 中文翻译\n\n这是第一句。这是第二句。\n\n## 核查\n\n准确"
        let html = HTMLRenderer.renderSplit(markdown: markdown, originalText: "First. Second.", isDark: false)
        try assertTrue(html.contains("class=\"split-list\""), "应存在 split-list 容器")
        try assertTrue(html.contains("class=\"split-pair\""), "应存在 split-pair")
        try assertTrue(html.contains("class=\"split-original\""), "应存在 split-original")
        try assertTrue(html.contains("class=\"split-translation\""), "应存在 split-translation")
        try assertTrue(html.contains("1. First."), "首句原文应带序号")
        try assertTrue(html.contains("这是第一句。"), "应含首句译文")
    }

    test("renderSplit hides original box in split mode") {
        let markdown = "## 中文翻译\n\n你好世界。这是第二句。"
        let html = HTMLRenderer.renderSplit(markdown: markdown, originalText: "Hello. Second.", isDark: false)
        try assertFalse(html.contains("<div class=\"original-box\">"), "拆分模式不应显示原文盒（原文已内联）")
        try assertTrue(html.contains("<h2>中文翻译</h2>"), "应保留译文标题")
        try assertTrue(html.contains("Powered by"), "应保留 footer")
    }

    test("renderSplit keeps vocab phrases and check sections") {
        let markdown = "## 中文翻译\n\n你好。世界。\n\n## 重要词汇\n\n- **word**\n\n## 常用短语与习语\n\n- phrase\n\n## 核查\n\n准确"
        let html = HTMLRenderer.renderSplit(markdown: markdown, originalText: "Hello. World.", isDark: false)
        try assertTrue(html.contains("<h2>重要词汇</h2>"), "拆分模式应保留词汇标题")
        try assertTrue(html.contains("<h2>常用短语与习语</h2>"), "拆分模式应保留短语标题")
        try assertTrue(html.contains("<h2>核查</h2>"), "拆分模式应保留核查标题")
    }

    test("renderSplit escapes original and translation text") {
        let markdown = "## 中文翻译\n\n包含 <b> 标签。第二句。"
        let html = HTMLRenderer.renderSplit(markdown: markdown, originalText: "A <script> B. Second.", isDark: false)
        try assertFalse(html.contains("<script>"), "原文脚本标签应转义")
        try assertTrue(html.contains("&lt;script&gt;"), "原文应转义为实体")
        try assertFalse(html.contains("<b>"), "译文标签应转义")
    }

    test("renderSplit falls back to whole mode when no 中文翻译 section") {
        let markdown = "## 重要词汇\n\n- **word**"
        let html = HTMLRenderer.renderSplit(markdown: markdown, originalText: "Hello", isDark: false)
        try assertTrue(html.contains("<div class=\"original-box\">"), "无中文翻译章节时应回退整段渲染（含原文盒）")
        try assertFalse(html.contains("<div class=\"split-list\">"), "回退整段渲染不应含 split-list 容器")
    }

    test("renderSplit falls back to whole mode when translation empty") {
        let markdown = "## 中文翻译\n\n\n\n## 核查\n\n准确"
        let html = HTMLRenderer.renderSplit(markdown: markdown, originalText: "", isDark: false)
        try assertTrue(html.contains("<div class=\"original-box\">"), "译文为空时应回退整段渲染")
    }

    // MARK: - canSplit 可行性判断

    test("canSplit returns false for table translation") {
        let markdown = "## 中文翻译\n\n| 列A | 列B |\n|---|---|\n| 1 | 2 |"
        let ok = HTMLRenderer.canSplit(markdown: markdown, originalText: "First. Second.")
        try assertFalse(ok, "表格译文不可拆分")
    }

    test("canSplit returns false for single sentence") {
        let markdown = "## 中文翻译\n\n你好世界。"
        let ok = HTMLRenderer.canSplit(markdown: markdown, originalText: "Hello.")
        try assertFalse(ok, "单句不可拆分")
    }

    test("canSplit returns true for multiple sentences") {
        let markdown = "## 中文翻译\n\n你好。世界。"
        let ok = HTMLRenderer.canSplit(markdown: markdown, originalText: "Hello. World.")
        try assertTrue(ok, "多句可拆分")
    }

    test("canSplit returns false for empty markdown") {
        let ok = HTMLRenderer.canSplit(markdown: "", originalText: "Hello. World.")
        try assertFalse(ok, "空 markdown 不可拆分")
    }

    test("canSplit returns false when no 中文翻译 section") {
        let markdown = "## 重要词汇\n\n- **word**"
        let ok = HTMLRenderer.canSplit(markdown: markdown, originalText: "Hello. World.")
        try assertFalse(ok, "无中文翻译章节不可拆分")
    }

    // MARK: - shouldStartSplit 初始模式决策

    test("shouldStartSplit prefers split when content splittable") {
        try assertTrue(HTMLRenderer.shouldStartSplit(preferSplit: true, canSplit: true))
    }

    test("shouldStartSplit falls back to whole when content not splittable") {
        try assertFalse(HTMLRenderer.shouldStartSplit(preferSplit: true, canSplit: false))
    }

    test("shouldStartSplit returns whole when prefer whole") {
        try assertFalse(HTMLRenderer.shouldStartSplit(preferSplit: false, canSplit: true))
    }

    test("shouldStartSplit returns whole when both false") {
        try assertFalse(HTMLRenderer.shouldStartSplit(preferSplit: false, canSplit: false))
    }

    // MARK: - renderSplit 表格回退

    test("renderSplit falls back to whole mode for table translation") {
        let markdown = "## 中文翻译\n\n| 列A | 列B |\n|---|---|\n| 1 | 2 |"
        let html = HTMLRenderer.renderSplit(markdown: markdown, originalText: "First. Second.", isDark: false)
        try assertTrue(html.contains("<div class=\"original-box\">"), "表格译文应回退整段渲染")
        try assertFalse(html.contains("<div class=\"split-list\">"), "表格译文不应生成 split-list")
    }

    // MARK: - 句子级富文本（inlineMarkdownToHTML）

    test("inlineMarkdownToHTML converts bold") {
        let html = HTMLRenderer.inlineMarkdownToHTML("这是 **重点** 内容")
        try assertTrue(html.contains("<strong>重点</strong>"), "应转加粗")
        try assertFalse(html.contains("**"), "不应残留星号")
    }

    test("inlineMarkdownToHTML converts inline code") {
        let html = HTMLRenderer.inlineMarkdownToHTML("看 `code` 这里")
        try assertTrue(html.contains("<code>code</code>"), "应转行内代码")
    }

    test("inlineMarkdownToHTML escapes script") {
        let html = HTMLRenderer.inlineMarkdownToHTML("<script>x</script>")
        try assertFalse(html.contains("<script>"), "应转义脚本标签")
        try assertTrue(html.contains("&lt;script&gt;"), "应转义为实体")
    }

    test("inlineMarkdownToHTML handles empty string") {
        try assertEqual(HTMLRenderer.inlineMarkdownToHTML(""), "")
    }

    test("inlineMarkdownToHTML handles unclosed bold") {
        let html = HTMLRenderer.inlineMarkdownToHTML("a **b")
        try assertTrue(html.contains("**b"), "未闭合加粗应原样保留")
    }

    test("renderSplit converts bold in translation sentence") {
        let markdown = "## 中文翻译\n\n这是 **重点**。第二句。"
        let html = HTMLRenderer.renderSplit(markdown: markdown, originalText: "One. Two.", isDark: false)
        try assertTrue(html.contains("<strong>重点</strong>"), "拆分模式译文应转加粗")
    }

    // MARK: - parseSections 前导内容

    test("parseSections preserves preamble") {
        let sections = HTMLRenderer.parseSections("前言\n\n## 中文翻译\n\n你好")
        try assertEqual(sections.count, 2)
        try assertNil(sections[0].heading)
        try assertEqual(sections[0].body, "前言")
        try assertEqual(sections[1].heading ?? "", "中文翻译")
    }

    test("renderSplit renders preamble") {
        let markdown = "以下是翻译：\n\n## 中文翻译\n\n你好。世界。"
        let html = HTMLRenderer.renderSplit(markdown: markdown, originalText: "Hello. World.", isDark: false)
        try assertTrue(html.contains("以下是翻译："), "拆分模式应渲染前导内容")
    }

    test("parseSections no preamble regression") {
        let sections = HTMLRenderer.parseSections("## 中文翻译\n\n你好")
        try assertEqual(sections.count, 1)
        try assertEqual(sections[0].heading ?? "", "中文翻译")
    }

    test("parseSections only preamble") {
        let sections = HTMLRenderer.parseSections("只有前言")
        try assertEqual(sections.count, 1)
        try assertNil(sections[0].heading)
        try assertEqual(sections[0].body, "只有前言")
    }

    // MARK: - 句数不一致提示条

    test("renderSplit shows mismatch warning when sentence counts differ") {
        let markdown = "## 中文翻译\n\n第一句。第二句。"
        let html = HTMLRenderer.renderSplit(markdown: markdown, originalText: "One. Two. Three.", isDark: false)
        try assertTrue(html.contains("句数不一致"), "句数不一致应显示提示条")
        try assertTrue(html.contains("split-warning"), "提示条应有 split-warning 样式")
    }

    test("renderSplit no warning when sentence counts match") {
        let markdown = "## 中文翻译\n\n第一句。第二句。"
        let html = HTMLRenderer.renderSplit(markdown: markdown, originalText: "One. Two.", isDark: false)
        try assertFalse(html.contains("句数不一致"), "句数一致不应显示提示条")
    }

    // MARK: - 弹窗字号缩放（fontSize 参数 + rem 相对字号）

    test("render defaults to 14px root font-size") {
        let html = HTMLRenderer.render(markdown: "## 中文翻译\n\n你好", originalText: "Hi", isDark: false)
        try assertTrue(html.contains("font-size:14px"), "默认根字号应为 14px")
    }

    test("render emits root font-size matching fontSize param") {
        let html = HTMLRenderer.render(markdown: "## 中文翻译\n\n你好", originalText: "Hi", isDark: false, fontSize: 20)
        try assertTrue(html.contains("font-size:20px"), "根字号应随 fontSize 参数变化")
    }

    test("render body uses relative 1rem not fixed px") {
        let html = HTMLRenderer.render(markdown: "## 中文翻译\n\n你好", originalText: "Hi", isDark: false, fontSize: 20)
        let bodyRule = try assertNotNil(cssRule("body", in: html), "应存在 body 规则")
        try assertTrue(bodyRule.contains("font-size:1rem"), "body 应用 1rem 相对字号")
        try assertFalse(bodyRule.contains("font-size:14px"), "body 不应再写死 14px")
    }

    test("renderSplit emits root font-size matching fontSize param") {
        let markdown = "## 中文翻译\n\n你好。世界。"
        let html = HTMLRenderer.renderSplit(markdown: markdown, originalText: "Hello. World.", isDark: false, fontSize: 18)
        try assertTrue(html.contains("font-size:18px"), "拆分渲染也应支持字号缩放")
    }
}
