using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Elta.Core
{
    /// <summary>图像像素坐标的矩形，左上角为原点（对应 macOS 版 CGRect）。</summary>
    public readonly struct RectF
    {
        public double X { get; }
        public double Y { get; }
        public double Width { get; }
        public double Height { get; }

        public RectF(double x, double y, double width, double height)
        {
            X = x; Y = y; Width = width; Height = height;
        }

        public double MinX => X;
        public double MaxX => X + Width;
        public double MinY => Y;
        public double MaxY => Y + Height;
        public double MidX => X + Width / 2.0;
        public double MidY => Y + Height / 2.0;
    }

    /// <summary>OCR 文字块（含坐标）。</summary>
    public sealed record OcrBlock(string Text, RectF BoundingBox);

    /// <summary>
    /// 从 OCR 坐标还原表格结构，输出 Markdown 表格。
    /// 移植自 macOS 版 Sources/TableExtractor.swift。
    /// </summary>
    public static class TableExtractor
    {
        private readonly record struct Column(double Center, double Min, double Max);

        // MARK: - 截图翻译：OCR 坐标 → Markdown 表格

        /// <summary>检测是否为表格，是则输出 Markdown 表格，否则输出纯文本。</summary>
        public static string Process(IReadOnlyList<OcrBlock> blocks)
        {
            ArgumentNullException.ThrowIfNull(blocks);
            return TableMarkdown(blocks) ?? FlatText(blocks);
        }

        /// <summary>块不构成表格（&lt;4 块 / &lt;2 列 / &lt;2 行 / &lt;2 有效行）时返回 null。</summary>
        public static string? TableMarkdown(IReadOnlyList<OcrBlock> blocks)
        {
            ArgumentNullException.ThrowIfNull(blocks);
            if (blocks.Count < 4) return null;

            List<Column> columns = DetectColumns(blocks);
            if (columns.Count < 2) return null;

            var colAssignments = new List<int>(blocks.Count);
            foreach (OcrBlock block in blocks)
                colAssignments.Add(BestColumn(block, columns));

            List<Column> rows = DetectRows(blocks, columns, colAssignments);
            if (rows.Count < 2) return null;

            var cells = new List<(string Text, double Y)>[rows.Count][];
            for (int r = 0; r < rows.Count; r++)
            {
                cells[r] = new List<(string, double)>[columns.Count];
                for (int c = 0; c < columns.Count; c++)
                    cells[r][c] = new List<(string, double)>();
            }

            for (int i = 0; i < blocks.Count; i++)
            {
                int c = colAssignments[i];
                int r = NearestClusterIndex(blocks[i].BoundingBox.MidY, rows);
                if (r < 0 || r >= rows.Count || c < 0 || c >= columns.Count) continue;
                cells[r][c].Add((blocks[i].Text, blocks[i].BoundingBox.MidY));
            }

            var grid = new List<List<string>>();
            for (int r = 0; r < rows.Count; r++)
            {
                var row = new List<string>();
                for (int c = 0; c < columns.Count; c++)
                {
                    string merged = string.Join(" ", cells[r][c].OrderBy(p => p.Y).Select(p => p.Text));
                    row.Add(merged);
                }
                grid.Add(row);
            }

            int validRows = grid.Count(row => row.Count(cell => cell.Length > 0) >= 2);
            if (validRows < 2) return null;

            return FormatMarkdownTable(grid);
        }

        // MARK: - 划词翻译：Tab 分隔符 → Markdown 表格

        public static string DetectAndConvertTabSeparated(string text)
        {
            ArgumentNullException.ThrowIfNull(text);
            if (!text.Contains('\t')) return text;

            List<string> lines = text
                .Split('\n')
                .Select(l => l.Trim('\n', '\r'))
                .Where(l => l.Length > 0)
                .ToList();

            if (lines.Count < 2) return text;

            var md = new List<string>();
            List<string> headerCells = lines[0].Split('\t').Select(EscapeMarkdownTableCell).ToList();
            md.Add("| " + string.Join(" | ", headerCells) + " |");

            var seps = headerCells.Select(_ => "---");
            md.Add("|" + string.Join("|", seps) + "|");

            foreach (string line in lines.Skip(1))
            {
                List<string> cells = line.Split('\t').Select(EscapeMarkdownTableCell).ToList();
                md.Add("| " + string.Join(" | ", cells) + " |");
            }

            return string.Join("\n", md);
        }

        // MARK: - 列检测（基于水平重叠）

        private static List<Column> DetectColumns(IReadOnlyList<OcrBlock> blocks)
        {
            List<OcrBlock> sorted = blocks.OrderBy(b => b.BoundingBox.MinX).ToList();
            var clusters = new List<List<OcrBlock>>();

            foreach (OcrBlock block in sorted)
            {
                bool assigned = false;
                for (int i = 0; i < clusters.Count; i++)
                {
                    if (clusters[i].Any(b => HorizontalOverlapRatio(b.BoundingBox, block.BoundingBox) >= 0.3))
                    {
                        clusters[i].Add(block);
                        assigned = true;
                        break;
                    }
                }
                if (!assigned) clusters.Add(new List<OcrBlock> { block });
            }

            return clusters
                .Select(cluster =>
                {
                    double minX = cluster.Min(b => b.BoundingBox.MinX);
                    double maxX = cluster.Max(b => b.BoundingBox.MaxX);
                    return new Column((minX + maxX) / 2.0, minX, maxX);
                })
                .OrderBy(c => c.Center)
                .ToList();
        }

        private static int BestColumn(OcrBlock block, List<Column> columns)
        {
            int bestIdx = 0;
            double bestOverlap = -1;
            for (int i = 0; i < columns.Count; i++)
            {
                Column col = columns[i];
                var colRect = new RectF(col.Min, 0, col.Max - col.Min, double.MaxValue);
                double overlap = HorizontalOverlapRatio(block.BoundingBox, colRect);
                if (overlap > bestOverlap)
                {
                    bestOverlap = overlap;
                    bestIdx = i;
                }
            }
            return bestIdx;
        }

        // MARK: - 行检测

        private static List<Column> DetectRows(
            IReadOnlyList<OcrBlock> blocks,
            List<Column> columns,
            List<int> colAssignments)
        {
            var cellCenters = new List<double>();

            for (int c = 0; c < columns.Count; c++)
            {
                var colBlocks = new List<OcrBlock>();
                for (int i = 0; i < blocks.Count; i++)
                    if (colAssignments[i] == c) colBlocks.Add(blocks[i]);
                colBlocks = colBlocks.OrderBy(b => b.BoundingBox.MinY).ToList();

                List<List<OcrBlock>> cells = ClusterBlocksIntoCells(colBlocks);
                foreach (List<OcrBlock> cell in cells)
                {
                    double minY = cell.Min(b => b.BoundingBox.MinY);
                    double maxY = cell.Max(b => b.BoundingBox.MaxY);
                    cellCenters.Add((minY + maxY) / 2.0);
                }
            }

            if (cellCenters.Count < 2) return new List<Column>();
            cellCenters.Sort();
            return ClusterByGaps(cellCenters, 1.5, 20);
        }

        private static List<List<OcrBlock>> ClusterBlocksIntoCells(List<OcrBlock> blocks)
        {
            var result = new List<List<OcrBlock>>();
            if (blocks.Count == 0) return result;
            if (blocks.Count < 2)
            {
                result.Add(new List<OcrBlock>(blocks));
                return result;
            }

            List<double> heights = blocks.Select(b => b.BoundingBox.Height).ToList();
            double medHeight = Median(heights) ?? 14;

            var current = new List<OcrBlock> { blocks[0] };
            for (int i = 1; i < blocks.Count; i++)
            {
                OcrBlock block = blocks[i];
                double gap = block.BoundingBox.MinY - current[current.Count - 1].BoundingBox.MaxY;
                if (gap <= medHeight * 0.9)
                {
                    current.Add(block);
                }
                else
                {
                    result.Add(current);
                    current = new List<OcrBlock> { block };
                }
            }
            result.Add(current);
            return result;
        }

        // MARK: - 通用工具

        private static double HorizontalOverlapRatio(RectF a, RectF b)
        {
            double overlap = Math.Min(a.MaxX, b.MaxX) - Math.Max(a.MinX, b.MinX);
            double minWidth = Math.Min(a.Width, b.Width);
            if (minWidth <= 0) return 0;
            return Math.Max(0, overlap / minWidth);
        }

        private static List<Column> ClusterByGaps(List<double> centers, double gapMultiplier, double minGap)
        {
            var result = new List<Column>();
            if (centers.Count == 0) return result;
            if (centers.Count < 2)
            {
                result.Add(new Column(centers[0], centers[0], centers[0]));
                return result;
            }

            var gaps = new List<double>();
            for (int i = 1; i < centers.Count; i++)
                gaps.Add(centers[i] - centers[i - 1]);

            double medianGap = Median(gaps) ?? minGap;
            double boundaryThreshold = Math.Max(medianGap * gapMultiplier, minGap);

            int currentStart = 0;
            for (int i = 0; i < gaps.Count; i++)
            {
                if (gaps[i] > boundaryThreshold)
                {
                    result.Add(MakeColumn(centers.GetRange(currentStart, i - currentStart + 1)));
                    currentStart = i + 1;
                }
            }
            result.Add(MakeColumn(centers.GetRange(currentStart, centers.Count - currentStart)));
            return result;
        }

        private static Column MakeColumn(List<double> clusterCenters)
            => new Column(clusterCenters.Average(), clusterCenters[0], clusterCenters[clusterCenters.Count - 1]);

        private static int NearestClusterIndex(double value, List<Column> clusters)
        {
            int bestIdx = 0;
            double bestDist = Math.Abs(value - clusters[0].Center);
            for (int i = 1; i < clusters.Count; i++)
            {
                double dist = Math.Abs(value - clusters[i].Center);
                if (dist < bestDist)
                {
                    bestDist = dist;
                    bestIdx = i;
                }
            }
            return bestIdx;
        }

        private static string FlatText(IReadOnlyList<OcrBlock> blocks)
        {
            var sorted = blocks.ToList();
            sorted.Sort((a, b) =>
            {
                if (Math.Abs(a.BoundingBox.MinY - b.BoundingBox.MinY) > 0.5)
                    return a.BoundingBox.MinY.CompareTo(b.BoundingBox.MinY);
                return a.BoundingBox.MinX.CompareTo(b.BoundingBox.MinX);
            });
            if (sorted.Count == 0) return "";

            List<List<OcrBlock>> lines = ClusterIntoLines(sorted);
            if (lines.Count < 2)
                return LineText(lines.Count > 0 ? lines[0] : new List<OcrBlock>());

            List<double> lineMinYs = lines.Select(l => l.Min(b => b.BoundingBox.MinY)).ToList();
            List<double> lineMaxYs = lines.Select(l => l.Max(b => b.BoundingBox.MaxY)).ToList();
            List<double> lineHeights = lines.Select(l => l.Max(b => b.BoundingBox.Height)).ToList();
            List<double> lineWidths = lines.Select(l =>
            {
                double minX = l.Min(b => b.BoundingBox.MinX);
                double maxX = l.Max(b => b.BoundingBox.MaxX);
                return maxX - minX;
            }).ToList();
            List<double> lineMinXs = lines.Select(l => l.Min(b => b.BoundingBox.MinX)).ToList();

            double lineHeight = Median(lineHeights) ?? 14;
            double medianWidth = Median(lineWidths) ?? 500;
            List<double> normalWidths = lineWidths.Where(w => w > medianWidth * 0.6).ToList();
            double normalWidth = normalWidths.Count == 0 ? medianWidth : normalWidths.Average();
            double normalMinX = Median(lineMinXs) ?? 50;

            var sb = new StringBuilder(LineText(lines[0]));
            for (int i = 1; i < lines.Count; i++)
            {
                double gap = lineMinYs[i] - lineMaxYs[i - 1];
                double currMinX = lineMinXs[i];
                double prevWidth = lineWidths[i - 1];

                if (gap > lineHeight * 1.5
                    || currMinX > normalMinX + 8
                    || prevWidth < normalWidth * 0.8)
                {
                    sb.Append("\n\n");
                }
                else
                {
                    sb.Append('\n');
                }
                sb.Append(LineText(lines[i]));
            }
            return sb.ToString();
        }

        private static List<List<OcrBlock>> ClusterIntoLines(List<OcrBlock> sorted)
        {
            var lines = new List<List<OcrBlock>>();
            if (sorted.Count == 0) return lines;

            List<double> heights = sorted.Select(b => b.BoundingBox.Height).ToList();
            double lineHeight = Median(heights) ?? 14;
            double tolerance = lineHeight * 0.6;

            var current = new List<OcrBlock> { sorted[0] };
            double currentMinY = sorted[0].BoundingBox.MinY;
            for (int i = 1; i < sorted.Count; i++)
            {
                OcrBlock block = sorted[i];
                if (Math.Abs(block.BoundingBox.MinY - currentMinY) <= tolerance)
                {
                    current.Add(block);
                }
                else
                {
                    lines.Add(current);
                    current = new List<OcrBlock> { block };
                    currentMinY = block.BoundingBox.MinY;
                }
            }
            lines.Add(current);
            return lines;
        }

        private static string LineText(List<OcrBlock> line)
            => string.Join(" ", line.OrderBy(b => b.BoundingBox.MinX).Select(b => b.Text));

        private static double? Median(List<double> values)
        {
            if (values.Count == 0) return null;
            List<double> sorted = values.OrderBy(v => v).ToList();
            int mid = sorted.Count / 2;
            if (sorted.Count % 2 == 0)
                return (sorted[mid - 1] + sorted[mid]) / 2.0;
            return sorted[mid];
        }

        private static string FormatMarkdownTable(List<List<string>> grid)
        {
            if (grid.Count == 0 || grid[0].Count == 0) return "";
            int colCount = grid[0].Count;

            var lines = new List<string>();
            List<string> header = grid[0].Select(EscapeMarkdownTableCell).ToList();
            lines.Add("| " + string.Join(" | ", header) + " |");

            var sepCells = new List<string>();
            for (int c = 0; c < colCount; c++)
            {
                int maxLen = Math.Max(Math.Max(grid.Max(row => row.Count > c ? row[c].Length : 0), header[c].Length), 3);
                sepCells.Add(new string('-', maxLen));
            }
            lines.Add("|" + string.Join("|", sepCells) + "|");

            for (int r = 1; r < grid.Count; r++)
            {
                List<string> row = grid[r];
                List<string> cells = Enumerable.Range(0, colCount)
                    .Select(c => c < row.Count ? EscapeMarkdownTableCell(row[c]) : "")
                    .ToList();
                lines.Add("| " + string.Join(" | ", cells) + " |");
            }

            return string.Join("\n", lines);
        }

        public static string EscapeMarkdownTableCell(string text)
        {
            ArgumentNullException.ThrowIfNull(text);
            return text.Replace("\\", "\\\\").Replace("|", "\\|").Replace("\n", " ");
        }
    }
}
