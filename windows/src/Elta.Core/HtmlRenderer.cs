using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Elta.Core
{
    /// <summary>Markdown "## 章节" 的结构化表示。</summary>
    public sealed record MarkdownSection(string? Heading, string Body);

    /// <summary>
    /// 把 AI 返回的 Markdown 渲染成弹窗 HTML（整段与逐句拆分两种视图）。
    /// 移植自 macOS 版 Sources/ResultWindowController.swift 的 HTMLRenderer，
    /// 输出需与 Mac 版逐字节对齐。
    /// </summary>
    public static class HtmlRenderer
    {
        /// <summary>弹窗根字号默认值（px），与 SettingsManager.popupFontSizeDefault 对齐。</summary>
        public const int PopupFontSizeDefault = 14;

        private static readonly Regex BoldRegex =
            new Regex(@"\*\*(.+?)\*\*", RegexOptions.Compiled);

        private static readonly Regex InlineCodeRegex =
            new Regex("`([^`]+)`", RegexOptions.Compiled);

        private static readonly string[] HeadingKeywords =
            { "中文翻译", "重要词汇", "常用短语与习语", "核查" };

        // MARK: - 公共渲染入口

        public static string Render(
            string markdown,
            string originalText,
            bool isDark,
            int fontSize = PopupFontSizeDefault,
            string providerShortName = "DeepSeek")
        {
            string body = MarkdownBodyToHTML(markdown);
            return Shell(body, OriginalBoxHTML(originalText), isDark, fontSize, providerShortName);
        }

        /// <summary>
        /// 拆分翻译视图：把「中文翻译」章节按句拆分，与原文逐句对照；其余章节（词汇/短语/核查）原样保留。
        /// 不重新请求 AI；若译文无「中文翻译」章节（自定义模板）或拆分结果为空，则回退整段渲染。
        /// </summary>
        public static string RenderSplit(
            string markdown,
            string originalText,
            bool isDark,
            int fontSize = PopupFontSizeDefault,
            string providerShortName = "DeepSeek")
        {
            if (!CanSplit(markdown, originalText))
            {
                return Render(markdown, originalText, isDark, fontSize, providerShortName);
            }

            List<MarkdownSection> sections = ParseSections(markdown);
            MarkdownSection? transSection = sections.FirstOrDefault(
                s => s.Heading != null && s.Heading.Contains("中文翻译"));
            if (transSection == null)
            {
                return Render(markdown, originalText, isDark, fontSize, providerShortName);
            }

            List<SplitPair> pairs = SentenceSplitter.Pair(originalText, transSection.Body);

            // 前导内容（无标题），渲染在最前
            string preambleHtml = string.Concat(
                sections.Where(s => s.Heading == null).Select(s => MarkdownBodyToHTML(s.Body)));

            var splitHtml = new StringBuilder();
            splitHtml.Append(preambleHtml);
            if (!SentenceSplitter.SentenceCountsMatch(originalText, transSection.Body))
            {
                splitHtml.Append("<div class=\"split-warning\">⚠️ 原文与译文句数不一致，已自动对齐，请留意对照</div>");
            }
            splitHtml.Append("<h2>中文翻译</h2>");
            splitHtml.Append("<div class=\"split-list\">");
            for (int idx = 0; idx < pairs.Count; idx++)
            {
                SplitPair pair = pairs[idx];
                splitHtml.Append("<div class=\"split-pair\">");
                if (pair.Original.Length > 0)
                {
                    splitHtml.Append($"<div class=\"split-original\">{idx + 1}. {PlainTextToHTML(pair.Original)}</div>");
                }
                if (pair.Translation.Length > 0)
                {
                    splitHtml.Append($"<div class=\"split-translation\">{InlineMarkdownToHTML(pair.Translation)}</div>");
                }
                splitHtml.Append("</div>");
            }
            splitHtml.Append("</div>");

            List<MarkdownSection> otherSections = sections
                .Where(s => s.Heading != null && !ReferenceEquals(s, transSection))
                .ToList();
            string otherMarkdown = string.Join("\n\n",
                otherSections.Select(s => $"## {s.Heading}\n{s.Body}"));
            string otherHtml = otherMarkdown.Length == 0 ? "" : MarkdownBodyToHTML(otherMarkdown);

            return Shell(splitHtml + otherHtml, null, isDark, fontSize, providerShortName);
        }

        /// <summary>判定当前内容是否适合拆分翻译：有「中文翻译」章节、非表格、且能拆出 ≥2 句。</summary>
        public static bool CanSplit(string markdown, string originalText)
        {
            List<MarkdownSection> sections = ParseSections(markdown);
            MarkdownSection? transSection = sections.FirstOrDefault(
                s => s.Heading != null && s.Heading.Contains("中文翻译"));
            if (transSection == null) return false;
            if (IsTableBody(transSection.Body)) return false;
            List<SplitPair> pairs = SentenceSplitter.Pair(originalText, transSection.Body);
            return pairs.Count >= 2;
        }

        /// <summary>弹窗初始模式决策：用户偏好拆分且内容可拆分时才从拆分起步，否则落回整段。</summary>
        public static bool ShouldStartSplit(bool preferSplit, bool canSplit)
            => preferSplit && canSplit;

        // MARK: - Markdown 正文 → HTML

        /// <summary>判断译文正文是否包含 Markdown 表格分隔行（|----|），含则视为表格内容。</summary>
        private static bool IsTableBody(string body)
            => body.Split('\n').Any(IsTableSeparatorLine);

        /// <summary>Markdown 正文 → HTML（转义 + 标题/加粗/行内代码/表格/段落）。</summary>
        private static string MarkdownBodyToHTML(string markdown)
        {
            string escaped = EscapeHTML(markdown);
            // 先保护行内代码，避免后续标题/加粗替换污染 <code> 内容
            (string protectedText, List<string> codes) = ProtectInlineCode(escaped);
            string html = protectedText;
            foreach (string keyword in HeadingKeywords)
            {
                html = html.Replace($"## {keyword}", $"<h2>{keyword}</h2>");
            }
            html = BoldRegex.Replace(html, "<strong>$1</strong>");

            // MD 表格 → HTML 表格（在换行处理前，因为表格是多行的）
            html = ConvertMarkdownTables(html);

            html = html.Replace("\n\n", "</p><p>");
            html = html.Replace("\n", "<br>");
            html = "<p>" + html + "</p>";
            html = html.Replace("<p></p>", "");
            html = html.Replace("<p><br></p>", "");
            return RestoreInlineCode(html, codes);
        }

        /// <summary>
        /// 抽出行内代码为占位符，避免后续加粗/标题替换污染 <code> 内容。
        /// 返回（占位后的文本, 与占位 @@CODE{i}@@ 一一对应的 &lt;code&gt; HTML 数组）。
        /// </summary>
        private static (string, List<string>) ProtectInlineCode(string text)
        {
            MatchCollection matches = InlineCodeRegex.Matches(text);
            if (matches.Count == 0) return (text, new List<string>());

            var codes = new string[matches.Count];
            var result = new StringBuilder(text);
            for (int idx = matches.Count - 1; idx >= 0; idx--)
            {
                Match m = matches[idx];
                codes[idx] = $"<code>{m.Groups[1].Value}</code>";
                // 用私用区字符做哨兵，避免与正文中的普通文本碰撞
                result.Remove(m.Index, m.Length);
                result.Insert(m.Index, $"\uE000{idx}\uE000");
            }
            return (result.ToString(), codes.ToList());
        }

        private static string RestoreInlineCode(string text, List<string> codes)
        {
            string outHtml = text;
            for (int i = 0; i < codes.Count; i++)
            {
                outHtml = outHtml.Replace($"\uE000{i}\uE000", codes[i]);
            }
            return outHtml;
        }

        /// <summary>原文盒 HTML（拆分模式下不显示，原文已逐句内联）。</summary>
        private static string OriginalBoxHTML(string originalText)
        {
            string normalized = TextNormalizer.NormalizeLineBreaks(originalText);
            string escaped = normalized
                .Replace("&", "&amp;")
                .Replace("<", "&lt;")
                .Replace(">", "&gt;")
                .Replace("\n\n", "<br><br>");
            return $"<strong>📝 原文：</strong><br>{escaped}";
        }

        /// <summary>公共 HTML 外壳（head/CSS/body 结构 + footer）。fontSize 为根字号（px），其余字号按 rem 相对缩放。</summary>
        private static string Shell(string body, string? originalBox, bool isDark, int fontSize, string providerShortName)
        {
            string themeClass = isDark ? "dark" : "light";
            string originalBoxHtml = originalBox == null
                ? ""
                : $"<div class=\"original-box\">{originalBox}</div>";
            return $$"""
            <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
            <style>
                :root{color-scheme:light dark}html{font-size:{{fontSize}}px}*{box-sizing:border-box;margin:0;padding:0}
                body{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Microsoft YaHei",sans-serif;font-size:1rem;line-height:1.7;padding:0}
                body.light{color:#1d1d1f;background:#fff}
                body.dark{color:#e5e5e7;background:#1c1c1e}
                .original-box{position:sticky;top:0;z-index:10;border-bottom:1px solid;padding:14px 24px;font-size:1.07rem;font-style:italic;max-height:50vh;overflow-y:auto;overflow-wrap:break-word}
                body.light .original-box{background:#e8f0fe;border-bottom-color:#b8d4fe;color:#1a3a6b}
                body.dark .original-box{background:#1c1c1e;border-bottom-color:#3a3a3c;color:#e5e5e7}
                .content{padding:18px 24px 20px}
                h2{font-size:1.21rem;font-weight:600;margin:20px 0 12px;padding-bottom:8px;border-bottom:2px solid #0071e3}
                body.dark h2{color:#fff;border-bottom-color:#0a84ff}
                code{padding:2px 6px;border-radius:4px;font-family:"SF Mono",Menlo,monospace;font-size:0.93rem}
                body.light code{background:#f0f0f2;color:#9b4d1c}
                body.dark code{background:#3a3a3c;color:#ff9f0a}
                body.light strong{color:#0071e3}
                body.dark strong{color:#5eafff}
                blockquote{border-left:4px solid;padding:10px 16px;margin:8px 0 12px;border-radius:0 8px 8px 0;font-size:1.07rem}
                body.light blockquote{background:#f9f9fb;border-left-color:#0071e3;color:#3a3a3c}
                body.dark blockquote{background:#2c2c2e;border-left-color:#0a84ff;color:#c0c0c5}
                .split-list{display:flex;flex-direction:column;gap:10px;margin:8px 0 4px}
                .split-pair{border:1px solid;border-radius:8px;padding:10px 14px}
                body.light .split-pair{background:#f5f5f7;border-color:#e5e5e7}
                body.dark .split-pair{background:#2c2c2e;border-color:#3a3a3c}
                .split-original{font-style:italic;margin-bottom:4px;overflow-wrap:break-word}
                body.light .split-original{color:#1a3a6b}
                body.dark .split-original{color:#8ab4f8}
                .split-translation{overflow-wrap:break-word}
                body.light .split-translation{color:#1d1d1f}
                body.dark .split-translation{color:#e5e5e7}
                .split-warning{padding:10px 14px;margin:0 0 8px;border-radius:8px;font-size:0.93rem;border:1px solid}
                body.light .split-warning{background:#fff3cd;color:#8a6d3b;border-color:#ffe08a}
                body.dark .split-warning{background:#3a2f00;color:#ffd75e;border-color:#5c4a00}
                table{width:100%;border-collapse:collapse;margin:10px 0 16px;font-size:0.93rem}th{padding:10px 12px;text-align:left;font-weight:600}td{padding:8px 12px;border-bottom:1px solid;vertical-align:top}
                body.light th{background:#f5f5f7;color:#1d1d1f}body.light td{border-color:#e5e5e7;color:#1d1d1f}
                body.dark th{background:#2c2c2e;color:#fff}body.dark td{border-color:#3a3a3c;color:#e5e5e7}
                p{margin:6px 0}ul,ol{margin:8px 0;padding-left:20px}li{margin:4px 0}.footer{margin-top:20px;padding-top:12px;border-top:1px solid;font-size:0.79rem;text-align:center}
                body.light .footer{border-top-color:#e5e5e7;color:#86868b}
                body.dark .footer{border-top-color:#3a3a3c;color:#8e8e93}
            </style>
            </head><body class="{{themeClass}}">
            {{originalBoxHtml}}
            <div class="content">
            {{body}}
            <div class="footer">Powered by {{EscapeHTML(providerShortName)}} AI · ELTA — 截图即译，精读利器</div>
            </div>
            </body></html>
            """;
        }

        // MARK: - 章节解析

        /// <summary>解析 Markdown 的 "## 章节" 结构为 [标题, 正文]。</summary>
        public static List<MarkdownSection> ParseSections(string markdown)
        {
            var sections = new List<MarkdownSection>();
            string[] lines = markdown.Split('\n');
            string? currentHeading = null;
            var currentBody = new List<string>();

            void Flush()
            {
                string body = string.Join("\n", currentBody).Trim();
                if (body.Length > 0 || currentHeading != null)
                {
                    sections.Add(new MarkdownSection(currentHeading, body));
                }
                currentBody.Clear();
            }

            foreach (string line in lines)
            {
                if (line.StartsWith("## ", StringComparison.Ordinal))
                {
                    Flush();
                    currentHeading = line.Substring(3).Trim();
                }
                else
                {
                    currentBody.Add(line);
                }
            }
            Flush();
            return sections;
        }

        // MARK: - 转义 / 行内富文本

        public static string EscapeHTML(string text)
            => text.Replace("&", "&amp;")
                .Replace("<", "&lt;")
                .Replace(">", "&gt;")
                .Replace("\"", "&quot;");

        /// <summary>句子级 Markdown 富文本 → HTML：转义 + 加粗 + 行内代码（不做标题/表格/段落，句子已是单行）。</summary>
        public static string InlineMarkdownToHTML(string text)
        {
            string escaped = EscapeHTML(text);
            (string protectedText, List<string> codes) = ProtectInlineCode(escaped);
            string html = protectedText;
            html = html.Replace("\n", "<br>");
            html = BoldRegex.Replace(html, "<strong>$1</strong>");
            return RestoreInlineCode(html, codes);
        }

        /// <summary>纯文本 → HTML：只做 HTML 转义 + 换行转 &lt;br&gt;，不解析任何 Markdown（用于原文，原文非 Markdown）。</summary>
        public static string PlainTextToHTML(string text)
            => EscapeHTML(text).Replace("\n", "<br>");

        // MARK: - Markdown 表格 → HTML 表格

        /// <summary>在文本中检测 Markdown 表格块并转为 HTML &lt;table&gt;。</summary>
        private static string ConvertMarkdownTables(string html)
        {
            string[] lines = html.Split('\n');
            var result = new List<string>();
            int i = 0;

            while (i < lines.Length)
            {
                // 检测表格起始：当前行是 |...| 格式，且下一行是分隔线
                if (IsTableHeaderCandidate(lines[i]) &&
                    i + 1 < lines.Length && IsTableSeparatorLine(lines[i + 1]))
                {
                    var tableLines = new List<string>();
                    while (i < lines.Length && IsTableLine(lines[i]))
                    {
                        tableLines.Add(lines[i]);
                        i++;
                    }
                    if (tableLines.Count >= 2)
                    {
                        result.Add(RenderHtmlTable(tableLines));
                    }
                    else
                    {
                        result.AddRange(tableLines);
                    }
                }
                else
                {
                    result.Add(lines[i]);
                    i++;
                }
            }

            return string.Join("\n", result);
        }

        /// <summary>是否可能是表头行（以 | 开头和结尾）。</summary>
        private static bool IsTableHeaderCandidate(string line) => IsTableLine(line);

        /// <summary>是否为表格行（以 | 开头且以 | 结尾）。</summary>
        private static bool IsTableLine(string line)
        {
            string trimmed = line.Trim();
            return trimmed.StartsWith("|", StringComparison.Ordinal)
                && trimmed.EndsWith("|", StringComparison.Ordinal);
        }

        /// <summary>是否为表格分隔行（|:---|:---:| 等）。</summary>
        private static bool IsTableSeparatorLine(string line)
        {
            string trimmed = line.Trim();
            if (!IsTableLine(trimmed)) return false;
            List<string> cells = trimmed.Split('|').Where(c => c.Length > 0).ToList();
            if (cells.Count == 0) return false;
            return cells.All(cell =>
            {
                string stripped = cell.Trim();
                return stripped.Length > 0 && stripped.All(c => c == '-' || c == ':');
            });
        }

        /// <summary>解析单行表格为单元格数组（还原 TableExtractor 对单元格内 | 与 \ 的转义）。</summary>
        private static List<string> ParseTableCells(string line)
        {
            string trimmed = line.Trim();
            List<string> cells = SplitUnescapedPipes(trimmed);
            // 去除首尾空串（| 在收尾时产生）
            if (cells.Count > 0 && cells[0].Trim().Length == 0) cells.RemoveAt(0);
            if (cells.Count > 0 && cells[cells.Count - 1].Trim().Length == 0) cells.RemoveAt(cells.Count - 1);
            return cells.Select(c => UnescapeMarkdownTableCell(c.Trim())).ToList();
        }

        /// <summary>按「未转义」的 | 切分单元格：TableExtractor 用 \| 转义单元格内的管道符，偶数个反斜杠后的 | 才是分隔符。</summary>
        private static List<string> SplitUnescapedPipes(string line)
        {
            char[] chars = line.ToCharArray();
            var cells = new List<string>();
            var current = new StringBuilder();
            int i = 0;
            while (i < chars.Length)
            {
                if (chars[i] == '\\')
                {
                    int slashCount = 0;
                    int j = i;
                    while (j < chars.Length && chars[j] == '\\') { slashCount++; j++; }
                    current.Append(chars, i, j - i);
                    if (j < chars.Length && chars[j] == '|')
                    {
                        if (slashCount % 2 == 0)
                        {
                            cells.Add(current.ToString());   // 偶数反斜杠：| 是分隔符
                            current.Clear();
                        }
                        else
                        {
                            current.Append('|');             // 奇数反斜杠：\| 是转义管道
                        }
                        i = j + 1;
                        continue;
                    }
                    i = j;
                    continue;
                }
                if (chars[i] == '|')
                {
                    cells.Add(current.ToString());
                    current.Clear();
                }
                else
                {
                    current.Append(chars[i]);
                }
                i++;
            }
            cells.Add(current.ToString());
            return cells;
        }

        /// <summary>还原 TableExtractor 的单元格转义（\| → |，\\ → \）。</summary>
        private static string UnescapeMarkdownTableCell(string text)
            => text.Replace("\\|", "|").Replace("\\\\", "\\");

        /// <summary>将 Markdown 表格行数组转换为 HTML &lt;table&gt;。</summary>
        private static string RenderHtmlTable(List<string> lines)
        {
            if (lines.Count < 2) return lines.Count > 0 ? lines[0] : "";

            List<string> headerCells = ParseTableCells(lines[0]);
            int colCount = headerCells.Count;
            var tableHtml = new StringBuilder("<table>");

            // 表头
            tableHtml.Append("<thead><tr>");
            foreach (string cell in headerCells)
            {
                tableHtml.Append($"<th>{cell}</th>");
            }
            tableHtml.Append("</tr></thead>");

            // 数据行（跳过第二行分隔线）
            tableHtml.Append("<tbody>");
            for (int rowIdx = 2; rowIdx < lines.Count; rowIdx++)
            {
                List<string> cells = ParseTableCells(lines[rowIdx]);
                tableHtml.Append("<tr>");
                for (int c = 0; c < colCount; c++)
                {
                    string content = c < cells.Count ? cells[c] : "";
                    tableHtml.Append($"<td>{content}</td>");
                }
                tableHtml.Append("</tr>");
            }
            tableHtml.Append("</tbody></table>");

            return tableHtml.ToString();
        }
    }
}
