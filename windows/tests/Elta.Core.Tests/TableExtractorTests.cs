using System;
using System.Collections.Generic;
using System.Linq;
using Xunit;

namespace Elta.Core.Tests
{
    public class TableExtractorTests
    {
        private static OcrBlock B(string text, double x, double y, double w, double h)
            => new OcrBlock(text, new RectF(x, y, w, h));

        [Fact]
        public void SmallGap_JoinedWithNewline()
        {
            var blocks = new[] { B("Line one", 50, 10, 500, 14), B("Line two", 50, 28, 500, 14) };
            Assert.Contains("Line one\nLine two", TableExtractor.Process(blocks));
        }

        [Fact]
        public void LargeGap_ParagraphBreak()
        {
            var blocks = new[] { B("Para one", 50, 10, 500, 14), B("Para two", 50, 50, 500, 14) };
            Assert.Contains("Para one\n\nPara two", TableExtractor.Process(blocks));
        }

        [Fact]
        public void IndentedLine_NewParagraph()
        {
            var blocks = new[] { B("End of para", 50, 10, 500, 14), B("New para", 80, 28, 470, 14) };
            Assert.Contains("End of para\n\nNew para", TableExtractor.Process(blocks));
        }

        [Fact]
        public void ShortLine_NewParagraph()
        {
            var blocks = new[] { B("Short end line", 50, 10, 200, 14), B("Next paragraph starts", 50, 28, 500, 14) };
            Assert.Contains("Short end line\n\nNext paragraph starts", TableExtractor.Process(blocks));
        }

        [Fact]
        public void NormalContinuation_StaysOneParagraph()
        {
            var blocks = new[]
            {
                B("This is the first line of the paragraph", 50, 10, 500, 14),
                B("continuing on the second line here", 50, 27, 500, 14),
                B("and the third line finishes it", 50, 44, 500, 14),
            };
            Assert.Single(TableExtractor.Process(blocks).Split(new[] { "\n\n" }, StringSplitOptions.None));
        }

        [Fact]
        public void WordLevelBlocks_NotSplitIntoParagraphs()
        {
            var blocks = new[] { B("The", 50, 10, 30, 14), B("quick", 85, 10, 50, 14), B("jumps", 50, 28, 60, 14) };
            Assert.Equal("The quick\njumps", TableExtractor.Process(blocks));
        }

        [Fact]
        public void TableMarkdown_ThreeColumns()
        {
            var blocks = new[]
            {
                B("H1", 100, 10, 100, 14), B("H2", 250, 10, 100, 14), B("H3", 400, 10, 100, 14),
                B("R1C1", 100, 40, 100, 14), B("R1C2", 250, 40, 100, 14), B("R1C3", 400, 40, 100, 14),
            };
            string? table = TableExtractor.TableMarkdown(blocks);
            Assert.NotNull(table);
            Assert.Contains("| H1 | H2 | H3 |", table);
            Assert.Contains("| R1C1 | R1C2 | R1C3 |", table);
        }

        [Fact]
        public void TableMarkdown_SingleColumn_ReturnsNull()
        {
            var blocks = new[] { B("line one", 100, 10, 500, 14), B("line two", 100, 28, 500, 14) };
            Assert.Null(TableExtractor.TableMarkdown(blocks));
        }

        [Fact]
        public void TabSeparated_EscapesPipeInCell()
        {
            string result = TableExtractor.DetectAndConvertTabSeparated("H1\tH2\nA\tB|C");
            Assert.Contains("| H1 | H2 |", result);
            Assert.Contains("| A | B\\|C |", result);
            Assert.DoesNotContain("B|C |", result);
        }

        [Fact]
        public void TabSeparated_EscapesPipeInHeader()
        {
            string result = TableExtractor.DetectAndConvertTabSeparated("Title|Subtitle\tNotes\nA\tB");
            Assert.Contains("| Title\\|Subtitle | Notes |", result);
        }

        [Fact]
        public void TabSeparated_NoPipe_UnchangedShape()
        {
            string result = TableExtractor.DetectAndConvertTabSeparated("H1\tH2\nA\tB");
            Assert.Contains("| A | B |", result);
        }

        [Fact]
        public void EscapeMarkdownTableCell_PipeAndNewline()
        {
            Assert.Equal("a\\|b", TableExtractor.EscapeMarkdownTableCell("a|b"));
            Assert.Equal("a b", TableExtractor.EscapeMarkdownTableCell("a\nb"));
        }

        [Fact]
        public void EscapeMarkdownTableCell_EscapesBackslashFirst()
        {
            Assert.Equal("a\\\\\\|b", TableExtractor.EscapeMarkdownTableCell("a\\|b"));
        }

        [Fact]
        public void Null_Throws()
        {
            Assert.Throws<ArgumentNullException>(() => TableExtractor.Process(null!));
            Assert.Throws<ArgumentNullException>(() => TableExtractor.EscapeMarkdownTableCell(null!));
        }

        // ---------- 审计修复：制表符表格列数归一 ----------

        [Fact]
        public void DetectAndConvertTabSeparated_PadsShortRowsToHeaderWidth()
        {
            string md = TableExtractor.DetectAndConvertTabSeparated("Name\tAge\nAlice");
            string[] lines = md.Split('\n');
            Assert.Equal(3, lines.Length);
            Assert.Equal("| Name | Age |", lines[0]);
            Assert.Equal("| Alice |  |", lines[2]);
        }

        [Fact]
        public void DetectAndConvertTabSeparated_TruncatesExtraCellsToHeaderWidth()
        {
            string md = TableExtractor.DetectAndConvertTabSeparated("Name\tAge\nAlice\t30\tExtra");
            string[] lines = md.Split('\n');
            Assert.Equal("| Alice | 30 |", lines[2]);
        }

        // ---------- 审计修复：FlatText 排序须为全序 ----------

        [Fact]
        public void Process_FlatText_OrdersBlocksByYThenX_TotalOrder()
        {
            var blocks = new List<OcrBlock>
            {
                B("A", 30, 1.0, 5, 0.1),
                B("B", 20, 1.2, 5, 0.1),
                B("C", 10, 1.4, 5, 0.1),
            };
            string text = TableExtractor.Process(blocks);
            int ia = text.IndexOf('A');
            int ib = text.IndexOf('B');
            int ic = text.IndexOf('C');
            Assert.True(ia >= 0 && ib >= 0 && ic >= 0 && ia < ib && ib < ic,
                $"expected reading order A,B,C but got: {text}");
        }
    }
}
