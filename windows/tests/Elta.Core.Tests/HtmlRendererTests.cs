using System;
using Xunit;

namespace Elta.Core.Tests
{
    public class HtmlRendererTests
    {
        // 返回 needle 在 haystack 中首次出现的字符偏移，未找到返回 -1
        private static int HtmlOffset(string needle, string haystack)
            => haystack.IndexOf(needle, StringComparison.Ordinal);

        // 提取 minified CSS 中的单条规则（selector{ ... }），未找到返回 null
        private static string? CssRule(string selector, string html)
        {
            int open = html.IndexOf(selector + "{", StringComparison.Ordinal);
            if (open < 0) return null;
            int close = html.IndexOf('}', open + selector.Length + 1);
            if (close < 0) return null;
            return html.Substring(open, close - open + 1);
        }

        // MARK: - HTML 转义测试

        [Fact]
        public void EscapeHTML_EscapesSpecialCharacters()
        {
            const string input = "price 5 < 10 \" & 3 > 1";
            string result = HtmlRenderer.EscapeHTML(input);
            Assert.Contains("&lt;", result);
            Assert.Contains("&gt;", result);
            Assert.Contains("&amp;", result);
            Assert.Contains("&quot;", result);
        }

        [Fact]
        public void EscapeHTML_HandlesScriptTag()
        {
            const string input = "<script>alert(1)</script>";
            string result = HtmlRenderer.EscapeHTML(input);
            Assert.DoesNotContain("<script>", result);
            Assert.Contains("&lt;script&gt;", result);
        }

        [Fact]
        public void EscapeHTML_HandlesImgOnerror()
        {
            const string input = "<img src=x onerror=\"alert(1)\">";
            string result = HtmlRenderer.EscapeHTML(input);
            Assert.DoesNotContain("<img", result);
            Assert.Contains("&lt;img", result);
        }

        [Fact]
        public void EscapeHTML_HandlesAmpersandAlreadyInText()
        {
            Assert.Equal("A &amp; B", HtmlRenderer.EscapeHTML("A & B"));
        }

        [Fact]
        public void EscapeHTML_HandlesEmptyString()
        {
            Assert.Equal("", HtmlRenderer.EscapeHTML(""));
        }

        // MARK: - Render 方法安全性测试

        [Fact]
        public void Render_EscapesAiResponseMarkdown()
        {
            const string markdown = "## 中文翻译\n包含 <script>alert('xss')</script> 的内容";
            string html = HtmlRenderer.Render(markdown, "test", isDark: false);
            Assert.DoesNotContain("<script>", html);
            Assert.Contains("&lt;script&gt;", html);
        }

        [Fact]
        public void Render_EscapesAiResponseWithImgOnerror()
        {
            const string markdown = "## 中文翻译\n图片 <img src=x onerror=alert(1)> in text";
            string html = HtmlRenderer.Render(markdown, "test", isDark: false);
            Assert.DoesNotContain("<img", html);
            Assert.Contains("&lt;img", html);
        }

        [Fact]
        public void Render_PreservesSafeMarkdownFormattingAfterEscaping()
        {
            const string markdown = "## 中文翻译\n这是 **加粗** 的内容";
            string html = HtmlRenderer.Render(markdown, "test", isDark: false);
            Assert.Contains("<strong>", html);
            Assert.Contains("<h2>中文翻译</h2>", html);
        }

        [Fact]
        public void Render_KeepsLiteralAsterisksInsideInlineCode()
        {
            const string markdown = "参考 `**加粗**` 的用法";
            string html = HtmlRenderer.Render(markdown, "x", isDark: false);
            Assert.DoesNotContain("<strong>加粗</strong>", html);
            Assert.Contains("<code>", html);
        }

        // MARK: - Markdown 表格 → HTML 表格

        [Fact]
        public void Render_ConvertsTwoColumnMarkdownTableToHtmlTable()
        {
            const string markdown = "## 中文翻译\n\n| 列A | 列B |\n|---|---|\n| 1 | 2 |";
            string html = HtmlRenderer.Render(markdown, "原文", isDark: false);
            Assert.Contains("<table>", html);
            Assert.Contains("<thead>", html);
            Assert.Contains("<th>列A</th>", html);
            Assert.Contains("<th>列B</th>", html);
            Assert.Contains("<tbody>", html);
            Assert.Contains("<td>1</td>", html);
            Assert.Contains("<td>2</td>", html);
            Assert.Contains("</table>", html);
        }

        [Fact]
        public void Render_ConvertsThreeColumnMarkdownTable()
        {
            const string markdown = "| 结构 | 名称 | 比喻 |\n|---|---|---|\n| 外皮层 | 人脑 | 车夫 |\n| 内皮层 | 猴脑 | 白马 |";
            string html = HtmlRenderer.Render(markdown, "原文", isDark: false);
            Assert.Contains("<th>结构</th>", html);
            Assert.Contains("<th>比喻</th>", html);
            Assert.Contains("<td>车夫</td>", html);
            Assert.Contains("<td>白马</td>", html);
        }

        [Fact]
        public void Render_DoesNotConvertPipeLineWithoutSeparatorToTable()
        {
            const string markdown = "## 中文翻译\n\n| 单列引用 |\n\n这是正文";
            string html = HtmlRenderer.Render(markdown, "原文", isDark: false);
            Assert.DoesNotContain("<table>", html);
        }

        [Fact]
        public void Render_ReversesEscapedPipeInTableCells()
        {
            const string markdown = "## 中文翻译\n\n| 表达式 | 含义 |\n|---|---|\n| a\\|b | 管道 |";
            string html = HtmlRenderer.Render(markdown, "原文", isDark: false);
            Assert.Contains("<td>a|b</td>", html);
            Assert.Contains("<td>管道</td>", html);
        }

        [Fact]
        public void Render_ReversesEscapedBackslashInTableCells()
        {
            const string markdown = "## 中文翻译\n\n| 路径 | 说明 |\n|---|---|\n| a\\\\b | 反斜杠 |";
            string html = HtmlRenderer.Render(markdown, "原文", isDark: false);
            Assert.Contains("<td>a\\b</td>", html);
        }

        // MARK: - 原文锁定（sticky 首行）布局测试

        [Fact]
        public void Render_WrapsTranslationBodyInContentContainer()
        {
            const string markdown = "## 中文翻译\n\n你好世界";
            string html = HtmlRenderer.Render(markdown, "Hello world", isDark: false);
            int contentOpen = HtmlOffset("<div class=\"content\">", html);
            int h2Translation = HtmlOffset("<h2>中文翻译</h2>", html);
            Assert.True(contentOpen >= 0, "应存在 content 容器");
            Assert.True(h2Translation >= 0, "应存在译文标题");
            Assert.True(contentOpen < h2Translation, "译文标题应位于 content 容器内");
        }

        [Fact]
        public void Render_KeepsFooterInsideContentContainer()
        {
            const string markdown = "## 中文翻译\n\n你好世界";
            string html = HtmlRenderer.Render(markdown, "Hello world", isDark: false);
            int contentOpen = HtmlOffset("<div class=\"content\">", html);
            int poweredBy = HtmlOffset("Powered by", html);
            Assert.True(contentOpen >= 0, "应存在 content 容器");
            Assert.True(poweredBy >= 0, "应存在 footer");
            Assert.True(contentOpen < poweredBy, "footer 应位于 content 容器内");
        }

        [Fact]
        public void Render_HandlesEmptyMarkdownWithContentContainer()
        {
            string html = HtmlRenderer.Render("", "Hi", isDark: false);
            Assert.Contains("<div class=\"content\">", html);
        }

        [Fact]
        public void Render_HandlesEmptyOriginalText()
        {
            string html = HtmlRenderer.Render("## 中文翻译\n\n你好", "", isDark: false);
            Assert.Contains("original-box", html);
            Assert.Contains("<div class=\"content\">", html);
        }

        [Fact]
        public void Render_RemovesBodyDefaultPadding()
        {
            string html = HtmlRenderer.Render("## 中文翻译\n\n你好", "Hi", isDark: false);
            Assert.Contains("padding:0", html);
            Assert.DoesNotContain("padding:20px 24px", html);
        }

        [Fact]
        public void Render_MakesOriginalBoxSticky()
        {
            string html = HtmlRenderer.Render("## 中文翻译\n\n你好", "Hello", isDark: false);
            Assert.Contains("position:sticky", html);
            Assert.Contains("top:0", html);
            Assert.Contains("z-index:10", html);
        }

        [Fact]
        public void Render_LightModeOriginalBoxBackground()
        {
            string html = HtmlRenderer.Render("## 中文翻译\n\n你好", "Hi", isDark: false);
            Assert.Contains("body.light .original-box{background:#e8f0fe", html);
        }

        [Fact]
        public void Render_DarkModeOriginalBoxBackground()
        {
            string html = HtmlRenderer.Render("## 中文翻译\n\n你好", "Hi", isDark: true);
            Assert.Contains("body class=\"dark\"", html);
            Assert.Contains("body.dark .original-box{background:#1c1c1e", html);
        }

        [Fact]
        public void Render_EmptyOriginalStillStickyWithLabel()
        {
            string html = HtmlRenderer.Render("## 中文翻译\n\n你好", "", isDark: false);
            Assert.Contains("📝 原文：", html);
            Assert.Contains("position:sticky", html);
        }

        [Fact]
        public void Render_EscapesSpecialCharsInOriginalText()
        {
            string html = HtmlRenderer.Render("## 中文翻译\n\n你好", "A < B & C", isDark: false);
            Assert.Contains("&lt;", html);
            Assert.Contains("&amp;", html);
        }

        [Fact]
        public void Render_AddsMaxHeightSafeguardToOriginalBox()
        {
            string html = HtmlRenderer.Render("## 中文翻译\n\n你好", "Hi", isDark: false);
            string? rule = CssRule(".original-box", html);
            Assert.NotNull(rule);
            Assert.Contains("max-height:50vh", rule);
            Assert.Contains("overflow-y:auto", rule);
        }

        [Fact]
        public void Render_ScopesMaxHeightToOriginalBoxNotContent()
        {
            string html = HtmlRenderer.Render("## 中文翻译\n\n你好", "Hi", isDark: false);
            string? obRule = CssRule(".original-box", html);
            Assert.NotNull(obRule);
            Assert.Contains("max-height:50vh", obRule);
            Assert.Contains("overflow-y:auto", obRule);
            string? cRule = CssRule(".content", html);
            Assert.NotNull(cRule);
            Assert.DoesNotContain("overflow-y", cRule);
        }

        [Fact]
        public void Render_HandlesVeryLongOriginalTextWithoutCrashing()
        {
            string longText = "First line. " + new string('x', 5000) + "\n\nSecond paragraph.";
            string html = HtmlRenderer.Render("## 中文翻译\n\n你好", longText, isDark: false);
            Assert.Contains("original-box", html);
            Assert.Contains("<br><br>", html);
        }

        // MARK: - 顺序与回归测试

        [Fact]
        public void Render_OrdersOriginalBoxBeforeTranslationBeforeVocabBeforePhrases()
        {
            const string markdown = "## 中文翻译\n\n翻译\n\n## 重要词汇\n\n- **word** ｜ n ｜ 词\n\n## 常用短语与习语\n\n- phrase：短语";
            string html = HtmlRenderer.Render(markdown, "Original", isDark: false);
            int ob = HtmlOffset("<div class=\"original-box\">", html);
            int t = HtmlOffset("<h2>中文翻译</h2>", html);
            int v = HtmlOffset("<h2>重要词汇</h2>", html);
            int p = HtmlOffset("<h2>常用短语与习语</h2>", html);
            Assert.True(ob >= 0 && t >= 0 && v >= 0 && p >= 0);
            Assert.True(ob < t && t < v && v < p, "顺序应为 原文 < 译文 < 词汇 < 短语");
        }

        [Fact]
        public void Render_KeepsVocabPhrasesAndCheckInsideContent()
        {
            const string markdown = "## 中文翻译\n\n翻译\n\n## 重要词汇\n\n- **word**\n\n## 常用短语与习语\n\n- phrase\n\n## 核查\n\n准确";
            string html = HtmlRenderer.Render(markdown, "Original", isDark: false);
            int contentOpen = HtmlOffset("<div class=\"content\">", html);
            int v = HtmlOffset("<h2>重要词汇</h2>", html);
            int p = HtmlOffset("<h2>常用短语与习语</h2>", html);
            int c = HtmlOffset("<h2>核查</h2>", html);
            Assert.True(contentOpen >= 0);
            Assert.True(v > contentOpen && p > contentOpen && c > contentOpen, "词汇/短语/核查应在 content 容器内");
        }

        // MARK: - 拆分翻译视图

        [Fact]
        public void ParseSections_SplitsMarkdownIntoHeadingBodySections()
        {
            const string markdown = "## 中文翻译\n\n你好世界\n\n## 重要词汇\n\n- **word**\n\n## 核查\n\n准确";
            var sections = HtmlRenderer.ParseSections(markdown);
            Assert.Equal(3, sections.Count);
            Assert.Equal("中文翻译", sections[0].Heading);
            Assert.Equal("你好世界", sections[0].Body);
            Assert.Equal("重要词汇", sections[1].Heading);
            Assert.Equal("核查", sections[2].Heading);
        }

        [Fact]
        public void RenderSplit_ProducesSplitPairWithOriginalAndTranslation()
        {
            const string markdown = "## 中文翻译\n\n这是第一句。这是第二句。\n\n## 核查\n\n准确";
            string html = HtmlRenderer.RenderSplit(markdown, "First. Second.", isDark: false);
            Assert.Contains("class=\"split-list\"", html);
            Assert.Contains("class=\"split-pair\"", html);
            Assert.Contains("class=\"split-original\"", html);
            Assert.Contains("class=\"split-translation\"", html);
            Assert.Contains("1. First.", html);
            Assert.Contains("这是第一句。", html);
        }

        [Fact]
        public void RenderSplit_HidesOriginalBoxInSplitMode()
        {
            const string markdown = "## 中文翻译\n\n你好世界。这是第二句。";
            string html = HtmlRenderer.RenderSplit(markdown, "Hello. Second.", isDark: false);
            Assert.DoesNotContain("<div class=\"original-box\">", html);
            Assert.Contains("<h2>中文翻译</h2>", html);
            Assert.Contains("Powered by", html);
        }

        [Fact]
        public void RenderSplit_KeepsVocabPhrasesAndCheckSections()
        {
            const string markdown = "## 中文翻译\n\n你好。世界。\n\n## 重要词汇\n\n- **word**\n\n## 常用短语与习语\n\n- phrase\n\n## 核查\n\n准确";
            string html = HtmlRenderer.RenderSplit(markdown, "Hello. World.", isDark: false);
            Assert.Contains("<h2>重要词汇</h2>", html);
            Assert.Contains("<h2>常用短语与习语</h2>", html);
            Assert.Contains("<h2>核查</h2>", html);
        }

        [Fact]
        public void RenderSplit_EscapesOriginalAndTranslationText()
        {
            const string markdown = "## 中文翻译\n\n包含 <b> 标签。第二句。";
            string html = HtmlRenderer.RenderSplit(markdown, "A <script> B. Second.", isDark: false);
            Assert.DoesNotContain("<script>", html);
            Assert.Contains("&lt;script&gt;", html);
            Assert.DoesNotContain("<b>", html);
        }

        [Fact]
        public void RenderSplit_RendersOriginalAsPlainTextNotMarkdownBold()
        {
            const string markdown = "## 中文翻译\n\n你好。世界。";
            string html = HtmlRenderer.RenderSplit(markdown, "Hello **bold** world. Second.", isDark: false);
            Assert.DoesNotContain("<strong>bold</strong>", html);
            Assert.Contains("**bold**", html);
        }

        [Fact]
        public void RenderSplit_FallsBackToWholeModeWhenNoTranslationSection()
        {
            const string markdown = "## 重要词汇\n\n- **word**";
            string html = HtmlRenderer.RenderSplit(markdown, "Hello", isDark: false);
            Assert.Contains("<div class=\"original-box\">", html);
            Assert.DoesNotContain("<div class=\"split-list\">", html);
        }

        [Fact]
        public void RenderSplit_FallsBackToWholeModeWhenTranslationEmpty()
        {
            const string markdown = "## 中文翻译\n\n\n\n## 核查\n\n准确";
            string html = HtmlRenderer.RenderSplit(markdown, "", isDark: false);
            Assert.Contains("<div class=\"original-box\">", html);
        }

        // MARK: - canSplit 可行性判断

        [Fact]
        public void CanSplit_ReturnsFalseForTableTranslation()
        {
            const string markdown = "## 中文翻译\n\n| 列A | 列B |\n|---|---|\n| 1 | 2 |";
            Assert.False(HtmlRenderer.CanSplit(markdown, "First. Second."));
        }

        [Fact]
        public void CanSplit_ReturnsFalseForSingleSentence()
        {
            Assert.False(HtmlRenderer.CanSplit("## 中文翻译\n\n你好世界。", "Hello."));
        }

        [Fact]
        public void CanSplit_ReturnsTrueForMultipleSentences()
        {
            Assert.True(HtmlRenderer.CanSplit("## 中文翻译\n\n你好。世界。", "Hello. World."));
        }

        [Fact]
        public void CanSplit_ReturnsFalseForEmptyMarkdown()
        {
            Assert.False(HtmlRenderer.CanSplit("", "Hello. World."));
        }

        [Fact]
        public void CanSplit_ReturnsFalseWhenNoTranslationSection()
        {
            Assert.False(HtmlRenderer.CanSplit("## 重要词汇\n\n- **word**", "Hello. World."));
        }

        // MARK: - shouldStartSplit 初始模式决策

        [Fact]
        public void ShouldStartSplit_PrefersSplitWhenContentSplittable()
            => Assert.True(HtmlRenderer.ShouldStartSplit(preferSplit: true, canSplit: true));

        [Fact]
        public void ShouldStartSplit_FallsBackToWholeWhenContentNotSplittable()
            => Assert.False(HtmlRenderer.ShouldStartSplit(preferSplit: true, canSplit: false));

        [Fact]
        public void ShouldStartSplit_ReturnsWholeWhenPreferWhole()
            => Assert.False(HtmlRenderer.ShouldStartSplit(preferSplit: false, canSplit: true));

        [Fact]
        public void ShouldStartSplit_ReturnsWholeWhenBothFalse()
            => Assert.False(HtmlRenderer.ShouldStartSplit(preferSplit: false, canSplit: false));

        // MARK: - renderSplit 表格回退

        [Fact]
        public void RenderSplit_FallsBackToWholeModeForTableTranslation()
        {
            const string markdown = "## 中文翻译\n\n| 列A | 列B |\n|---|---|\n| 1 | 2 |";
            string html = HtmlRenderer.RenderSplit(markdown, "First. Second.", isDark: false);
            Assert.Contains("<div class=\"original-box\">", html);
            Assert.DoesNotContain("<div class=\"split-list\">", html);
        }

        // MARK: - 句子级富文本（inlineMarkdownToHTML）

        [Fact]
        public void InlineMarkdownToHTML_ConvertsBold()
        {
            string html = HtmlRenderer.InlineMarkdownToHTML("这是 **重点** 内容");
            Assert.Contains("<strong>重点</strong>", html);
            Assert.DoesNotContain("**", html);
        }

        [Fact]
        public void InlineMarkdownToHTML_ConvertsInlineCode()
        {
            string html = HtmlRenderer.InlineMarkdownToHTML("看 `code` 这里");
            Assert.Contains("<code>code</code>", html);
        }

        [Fact]
        public void InlineMarkdownToHTML_EscapesScript()
        {
            string html = HtmlRenderer.InlineMarkdownToHTML("<script>x</script>");
            Assert.DoesNotContain("<script>", html);
            Assert.Contains("&lt;script&gt;", html);
        }

        [Fact]
        public void InlineMarkdownToHTML_HandlesEmptyString()
            => Assert.Equal("", HtmlRenderer.InlineMarkdownToHTML(""));

        [Fact]
        public void InlineMarkdownToHTML_HandlesUnclosedBold()
        {
            string html = HtmlRenderer.InlineMarkdownToHTML("a **b");
            Assert.Contains("**b", html);
        }

        [Fact]
        public void RenderSplit_ConvertsBoldInTranslationSentence()
        {
            const string markdown = "## 中文翻译\n\n这是 **重点**。第二句。";
            string html = HtmlRenderer.RenderSplit(markdown, "One. Two.", isDark: false);
            Assert.Contains("<strong>重点</strong>", html);
        }

        // MARK: - parseSections 前导内容

        [Fact]
        public void ParseSections_PreservesPreamble()
        {
            var sections = HtmlRenderer.ParseSections("前言\n\n## 中文翻译\n\n你好");
            Assert.Equal(2, sections.Count);
            Assert.Null(sections[0].Heading);
            Assert.Equal("前言", sections[0].Body);
            Assert.Equal("中文翻译", sections[1].Heading);
        }

        [Fact]
        public void RenderSplit_RendersPreamble()
        {
            const string markdown = "以下是翻译：\n\n## 中文翻译\n\n你好。世界。";
            string html = HtmlRenderer.RenderSplit(markdown, "Hello. World.", isDark: false);
            Assert.Contains("以下是翻译：", html);
        }

        [Fact]
        public void ParseSections_NoPreambleRegression()
        {
            var sections = HtmlRenderer.ParseSections("## 中文翻译\n\n你好");
            Assert.Single(sections);
            Assert.Equal("中文翻译", sections[0].Heading);
        }

        [Fact]
        public void ParseSections_OnlyPreamble()
        {
            var sections = HtmlRenderer.ParseSections("只有前言");
            Assert.Single(sections);
            Assert.Null(sections[0].Heading);
            Assert.Equal("只有前言", sections[0].Body);
        }

        // MARK: - 句数不一致提示条

        [Fact]
        public void RenderSplit_ShowsMismatchWarningWhenSentenceCountsDiffer()
        {
            const string markdown = "## 中文翻译\n\n第一句。第二句。";
            string html = HtmlRenderer.RenderSplit(markdown, "One. Two. Three.", isDark: false);
            Assert.Contains("句数不一致", html);
            Assert.Contains("split-warning", html);
        }

        [Fact]
        public void RenderSplit_NoWarningWhenSentenceCountsMatch()
        {
            const string markdown = "## 中文翻译\n\n第一句。第二句。";
            string html = HtmlRenderer.RenderSplit(markdown, "One. Two.", isDark: false);
            Assert.DoesNotContain("句数不一致", html);
        }

        // MARK: - 弹窗字号缩放（fontSize 参数 + rem 相对字号）

        [Fact]
        public void Render_DefaultsTo14pxRootFontSize()
        {
            string html = HtmlRenderer.Render("## 中文翻译\n\n你好", "Hi", isDark: false);
            Assert.Contains("font-size:14px", html);
        }

        [Fact]
        public void Render_EmitsRootFontSizeMatchingParam()
        {
            string html = HtmlRenderer.Render("## 中文翻译\n\n你好", "Hi", isDark: false, fontSize: 20);
            Assert.Contains("font-size:20px", html);
        }

        [Fact]
        public void Render_BodyUsesRelativeRemNotFixedPx()
        {
            string html = HtmlRenderer.Render("## 中文翻译\n\n你好", "Hi", isDark: false, fontSize: 20);
            string? bodyRule = CssRule("body", html);
            Assert.NotNull(bodyRule);
            Assert.Contains("font-size:1rem", bodyRule);
            Assert.DoesNotContain("font-size:14px", bodyRule);
        }

        [Fact]
        public void RenderSplit_EmitsRootFontSizeMatchingParam()
        {
            const string markdown = "## 中文翻译\n\n你好。世界。";
            string html = HtmlRenderer.RenderSplit(markdown, "Hello. World.", isDark: false, fontSize: 18);
            Assert.Contains("font-size:18px", html);
        }

        // MARK: - footer 提供商名

        [Fact]
        public void Render_FooterUsesProviderShortName()
        {
            string html = HtmlRenderer.Render("## 中文翻译\n\n你好", "Hi", isDark: false, providerShortName: "千问");
            Assert.Contains("Powered by 千问 AI · ELTA", html);
        }

        // MARK: - 审计修复

        [Fact]
        public void RenderSplit_KeepsEmptyBodyHeading()
        {
            const string markdown = "## 中文翻译\n\n你好。世界。\n\n## 核查\n";
            string html = HtmlRenderer.RenderSplit(markdown, "Hello. World.", isDark: false);
            Assert.Contains("核查", html);
        }

        [Fact]
        public void RenderSplit_KeepsSecondChineseTranslationSection()
        {
            const string markdown = "## 中文翻译\n\n你好。世界。\n\n## 中文翻译（意译）\n\n第三句。";
            string html = HtmlRenderer.RenderSplit(markdown, "Hello. World.", isDark: false);
            Assert.Contains("第三句", html);
        }

        [Fact]
        public void Render_EscapesProviderShortNameInFooter()
        {
            string html = HtmlRenderer.Render("## 中文翻译\n\n你好", "Hi", isDark: false,
                providerShortName: "A<script>alert(1)</script>");
            Assert.DoesNotContain("<script>", html);
            Assert.Contains("A&lt;script&gt;", html);
        }
    }
}
