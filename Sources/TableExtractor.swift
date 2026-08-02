import Foundation

// MARK: - OCR 文字块（含坐标）

struct OCRBlock {
    let text: String
    let boundingBox: CGRect  // 图像像素坐标，左上角为原点
}

// MARK: - 表格提取器

/// 从 OCR 坐标还原表格结构，输出 Markdown 表格
final class TableExtractor {

    // MARK: - 截图翻译：OCR 坐标 → Markdown 表格

    /// 输入 OCR 识别到的所有文本块（含坐标），检测是否为表格，是则输出 Markdown 表格，否则输出纯文本
    static func process(blocks: [OCRBlock]) -> String {
        guard blocks.count >= 2 else {
            return blocks.first?.text ?? ""
        }

        // ---- 1. 按 Y 排序，分组为行 ----
        let sorted = blocks.sorted { $0.boundingBox.minY < $1.boundingBox.minY }

        // 用中位行高作为行间距判断阈值
        let heights = sorted.map { $0.boundingBox.height }
        let medianHeight = median(heights) ?? 14  // 默认 14pt

        var rows: [[OCRBlock]] = []
        var currentRow: [OCRBlock] = [sorted[0]]
        var lastRowMaxY = sorted[0].boundingBox.maxY

        for block in sorted.dropFirst() {
            let gap = block.boundingBox.minY - lastRowMaxY
            if gap > medianHeight * 0.6 {
                // 垂直间距超过 0.6 倍行高 → 新行
                rows.append(currentRow)
                currentRow = [block]
            } else {
                // 同一行（同一行内可能有多列）
                currentRow.append(block)
            }
            lastRowMaxY = max(lastRowMaxY, block.boundingBox.maxY)
        }
        rows.append(currentRow)

        // ---- 2. 每行内部按 X 排序 ----
        let sortedRows = rows.map { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }

        // ---- 3. 判断是否为表格 ----
        let colCounts = sortedRows.map { $0.count }
        let maxCols = colCounts.max() ?? 1
        guard maxCols >= 2, sortedRows.count >= 2 else {
            // 单列或单行 → 纯文本
            return sorted.map { $0.text }.joined(separator: "\n")
        }

        // 列数要一致（允许 ±1 的误差，因为某些单元格可能为空或者合并）
        let consistentColumns = colCounts.allSatisfy { $0 == maxCols || $0 == maxCols - 1 }
        guard consistentColumns else {
            return sorted.map { $0.text }.joined(separator: "\n")
        }

        // ---- 4. 构建表格网格 ----
        var grid: [[String]] = []
        for row in sortedRows {
            var cells = Array(repeating: "", count: maxCols)
            for (i, block) in row.enumerated() {
                if i < maxCols {
                    cells[i] = block.text
                }
            }
            grid.append(cells)
        }

        // ---- 5. 输出 Markdown 表格 ----
        return formatMarkdownTable(grid: grid)
    }

    // MARK: - 划词翻译：Tab 分隔符检测 → Markdown 表格

    /// 划词拿到的文本如果包含 Tab（\t），说明来自 Excel/Sheets，转为 Markdown 表格
    static func detectAndConvertTabSeparated(_ text: String) -> String {
        guard text.contains("\t") else { return text }

        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else { return text }

        var md: [String] = []

        // 表头
        let headerCells = lines[0].components(separatedBy: "\t")
        md.append("| " + headerCells.joined(separator: " | ") + " |")

        // 分隔线
        let seps = headerCells.map { _ in "---" }
        md.append("|" + seps.joined(separator: "|") + "|")

        // 数据行
        for line in lines.dropFirst() {
            let cells = line.components(separatedBy: "\t")
            md.append("| " + cells.joined(separator: " | ") + " |")
        }

        return md.joined(separator: "\n")
    }

    // MARK: - 内部工具

    private static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }

    private static func formatMarkdownTable(grid: [[String]]) -> String {
        guard !grid.isEmpty, !grid[0].isEmpty else { return "" }
        let colCount = grid[0].count

        var lines: [String] = []

        // 表头行（第一行）
        let header = grid[0].map { escapeMarkdownTableCell($0) }
        lines.append("| " + header.joined(separator: " | ") + " |")

        // 分隔线
        var sepCells: [String] = []
        for c in 0..<colCount {
            let maxLen = max(grid.map { $0.count > c ? ($0[c]).count : 0 }.max() ?? 3, header[c].count, 3)
            sepCells.append(String(repeating: "-", count: maxLen))
        }
        lines.append("|" + sepCells.joined(separator: "|") + "|")

        // 数据行
        for row in grid.dropFirst() {
            let cells = (0..<colCount).map { c in
                c < row.count ? escapeMarkdownTableCell(row[c]) : ""
            }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }

        return lines.joined(separator: "\n")
    }

    /// 转义单元格内可能破坏 Markdown 表格语法的特殊字符
    private static func escapeMarkdownTableCell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
