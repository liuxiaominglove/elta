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
        if let table = tableMarkdown(blocks) {
            return table
        }
        return flatText(from: blocks)
    }

    /// 检测并转换为 Markdown 表格；若块不构成表格（<2 列或 <2 行）返回 nil。
    /// 要求传入的块是「干净的表格区域」（不含正文），供悬停翻译在聚行前识别表格用。
    static func tableMarkdown(_ blocks: [OCRBlock]) -> String? {
        guard blocks.count >= 4 else { return nil }

        // 1. 列检测：基于水平方向重叠聚类（而不是 X 中心距离）
        let columns = detectColumns(from: blocks)
        guard columns.count >= 2 else { return nil }

        // 2. 把每个文字块分配到一个主列
        let colAssignments = blocks.map { block -> Int in
            bestColumn(for: block, columns: columns)
        }

        // 3. 行检测
        let rows = detectRows(from: blocks, columns: columns, colAssignments: colAssignments)
        guard rows.count >= 2 else { return nil }

        // 4. 把每个块分配进网格单元格
        var cells: [[[(text: String, y: CGFloat)]]] = Array(
            repeating: Array(repeating: [], count: columns.count),
            count: rows.count
        )

        for (i, block) in blocks.enumerated() {
            let c = colAssignments[i]
            let r = nearestClusterIndex(value: block.boundingBox.midY, clusters: rows)
            guard r >= 0, r < rows.count, c >= 0, c < columns.count else { continue }
            cells[r][c].append((block.text, block.boundingBox.midY))
        }

        // 5. 合并单元格内多行文本，生成网格
        var grid: [[String]] = []
        for r in 0..<rows.count {
            var row: [String] = []
            for c in 0..<columns.count {
                let parts = cells[r][c].sorted { $0.y < $1.y }
                row.append(parts.map { $0.text }.joined(separator: " "))
            }
            grid.append(row)
        }

        // 6. 验证：至少 2 行，每行在 ≥2 个不同列里有内容
        let validRows = grid.filter { row in row.filter { !$0.isEmpty }.count >= 2 }.count
        guard validRows >= 2 else { return nil }

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
        let headerCells = lines[0].components(separatedBy: "\t").map { escapeMarkdownTableCell($0) }
        md.append("| " + headerCells.joined(separator: " | ") + " |")

        // 分隔线
        let seps = headerCells.map { _ in "---" }
        md.append("|" + seps.joined(separator: "|") + "|")

        // 数据行
        for line in lines.dropFirst() {
            let cells = line.components(separatedBy: "\t").map { escapeMarkdownTableCell($0) }
            md.append("| " + cells.joined(separator: " | ") + " |")
        }

        return md.joined(separator: "\n")
    }

    // MARK: - 列检测（基于水平重叠）

    private static func detectColumns(from blocks: [OCRBlock]) -> [(center: CGFloat, min: CGFloat, max: CGFloat)] {
        // 按 minX 排序，然后用「水平重叠」做传递聚类
        let sorted = blocks.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        var clusters: [[OCRBlock]] = []

        for block in sorted {
            var assigned = false
            for (i, cluster) in clusters.enumerated() {
                // 只要和簇中任意一个块水平重叠 ≥30%，就算同一列
                if cluster.contains(where: { horizontalOverlapRatio($0.boundingBox, block.boundingBox) >= 0.3 }) {
                    clusters[i].append(block)
                    assigned = true
                    break
                }
            }
            if !assigned {
                clusters.append([block])
            }
        }

        // 计算每列的包围范围，并按中心 X 排序
        return clusters.map { cluster -> (center: CGFloat, min: CGFloat, max: CGFloat) in
            let minX = cluster.map { $0.boundingBox.minX }.min() ?? 0
            let maxX = cluster.map { $0.boundingBox.maxX }.max() ?? 0
            return ((minX + maxX) / 2, minX, maxX)
        }.sorted { $0.center < $1.center }
    }

    /// 把块分配到水平重叠最多的列
    private static func bestColumn(for block: OCRBlock, columns: [(center: CGFloat, min: CGFloat, max: CGFloat)]) -> Int {
        var bestIdx = 0
        var bestOverlap: CGFloat = -1
        for (i, col) in columns.enumerated() {
            let colRect = CGRect(x: col.min, y: 0, width: col.max - col.min, height: CGFloat.greatestFiniteMagnitude)
            let overlap = horizontalOverlapRatio(block.boundingBox, colRect)
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestIdx = i
            }
        }
        return bestIdx
    }

    // MARK: - 行检测（列内先聚单元格，再跨列对齐）

    private static func detectRows(
        from blocks: [OCRBlock],
        columns: [(center: CGFloat, min: CGFloat, max: CGFloat)],
        colAssignments: [Int]
    ) -> [(center: CGFloat, min: CGFloat, max: CGFloat)] {
        var cellCenters: [CGFloat] = []

        for c in 0..<columns.count {
            let colBlocks = blocks.enumerated()
                .filter { colAssignments[$0.offset] == c }
                .map { $0.element }
                .sorted { $0.boundingBox.minY < $1.boundingBox.minY }

            // 在单列内部把块聚成单元格（处理多行单元格）
            let cells = clusterBlocksIntoCells(blocks: colBlocks)
            for cell in cells {
                let minY = cell.map { $0.boundingBox.minY }.min() ?? 0
                let maxY = cell.map { $0.boundingBox.maxY }.max() ?? 0
                cellCenters.append((minY + maxY) / 2)
            }
        }

        guard cellCenters.count >= 2 else { return [] }

        // 跨列聚类单元格中心 → 全局行
        return clusterByGaps(centers: cellCenters.sorted(), gapMultiplier: 1.5, minGap: 20)
    }

    /// 单列内部：把垂直距离近的块合并成一个单元格（处理单元格内换行）
    private static func clusterBlocksIntoCells(blocks: [OCRBlock]) -> [[OCRBlock]] {
        guard !blocks.isEmpty else { return [] }
        guard blocks.count >= 2 else { return [blocks] }

        // 计算中位高度，作为「行内换行」vs「行间」的参考
        let heights = blocks.map { $0.boundingBox.height }
        let medHeight = median(heights) ?? 14

        var cells: [[OCRBlock]] = []
        var current: [OCRBlock] = [blocks[0]]

        for block in blocks.dropFirst() {
            let gap = block.boundingBox.minY - (current.last?.boundingBox.maxY ?? 0)
            // 间隙小于 0.9 倍中位高度 → 同一单元格内换行
            if gap <= medHeight * 0.9 {
                current.append(block)
            } else {
                cells.append(current)
                current = [block]
            }
        }
        cells.append(current)
        return cells
    }

    // MARK: - 通用工具

    /// 两个矩形在 X 轴上的重叠比例（以较窄者的宽度为基准）
    private static func horizontalOverlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let minWidth = min(a.width, b.width)
        guard minWidth > 0 else { return 0 }
        return max(0, overlap / minWidth)
    }

    /// 通用间隙聚类：把坐标按大间隙切分成若干簇
    private static func clusterByGaps(
        centers: [CGFloat],
        gapMultiplier: CGFloat,
        minGap: CGFloat
    ) -> [(center: CGFloat, min: CGFloat, max: CGFloat)] {
        guard !centers.isEmpty else { return [] }
        guard centers.count >= 2 else {
            let avg = centers.reduce(0, +) / CGFloat(centers.count)
            return [(avg, centers.first!, centers.last!)]
        }

        var gaps: [CGFloat] = []
        for i in 1..<centers.count {
            gaps.append(centers[i] - centers[i - 1])
        }

        let medianGap = median(gaps) ?? minGap
        let boundaryThreshold = max(medianGap * gapMultiplier, minGap)

        var clusters: [(center: CGFloat, min: CGFloat, max: CGFloat)] = []
        var currentStart = 0

        for i in 0..<gaps.count {
            if gaps[i] > boundaryThreshold {
                let clusterCenters = Array(centers[currentStart...i])
                let avg = clusterCenters.reduce(0, +) / CGFloat(clusterCenters.count)
                clusters.append((avg, clusterCenters.first!, clusterCenters.last!))
                currentStart = i + 1
            }
        }

        let clusterCenters = Array(centers[currentStart..<centers.count])
        let avg = clusterCenters.reduce(0, +) / CGFloat(clusterCenters.count)
        clusters.append((avg, clusterCenters.first!, clusterCenters.last!))

        return clusters
    }

    private static func nearestClusterIndex(
        value: CGFloat,
        clusters: [(center: CGFloat, min: CGFloat, max: CGFloat)]
    ) -> Int {
        var bestIdx = 0
        var bestDist = abs(value - clusters[0].center)
        for (i, cluster) in clusters.enumerated().dropFirst() {
            let dist = abs(value - cluster.center)
            if dist < bestDist {
                bestDist = dist
                bestIdx = i
            }
        }
        return bestIdx
    }

    private static func flatText(from blocks: [OCRBlock]) -> String {
        let sorted = blocks.sorted { $0.boundingBox.minY < $1.boundingBox.minY }
        guard sorted.count >= 2 else {
            return sorted.first?.text ?? ""
        }

        let widths = sorted.map { $0.boundingBox.width }
        let minXs = sorted.map { $0.boundingBox.minX }
        let heights = sorted.map { $0.boundingBox.height }

        let lineHeight = median(heights) ?? 14
        let medianWidth = median(widths) ?? 500
        let normalWidths = widths.filter { $0 > medianWidth * 0.6 }
        let normalWidth = normalWidths.isEmpty ? medianWidth : (normalWidths.reduce(0, +) / CGFloat(normalWidths.count))
        let normalMinX = median(minXs) ?? 50

        var result = sorted[0].text
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            let gap = curr.boundingBox.minY - prev.boundingBox.maxY

            if gap > lineHeight * 1.5
                || curr.boundingBox.minX > normalMinX + 8
                || prev.boundingBox.width < normalWidth * 0.8 {
                result += "\n\n"
            } else {
                result += "\n"
            }
            result += curr.text
        }
        return result
    }

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

        let header = grid[0].map { escapeMarkdownTableCell($0) }
        lines.append("| " + header.joined(separator: " | ") + " |")

        var sepCells: [String] = []
        for c in 0..<colCount {
            let maxLen = max(grid.map { $0.count > c ? ($0[c]).count : 0 }.max() ?? 3, header[c].count, 3)
            sepCells.append(String(repeating: "-", count: maxLen))
        }
        lines.append("|" + sepCells.joined(separator: "|") + "|")

        for row in grid.dropFirst() {
            let cells = (0..<colCount).map { c in
                c < row.count ? escapeMarkdownTableCell(row[c]) : ""
            }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }

        return lines.joined(separator: "\n")
    }

    static func escapeMarkdownTableCell(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
