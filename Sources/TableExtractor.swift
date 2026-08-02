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
        guard blocks.count >= 4 else {
            return flatText(from: blocks)
        }

        // 1. 用「间隙聚类」分别找出所有列中心和行中心
        //    这样即使某个单元格内部有换行（多行文本），也会被归到同一个网格单元格里
        let columns = detectColumns(from: blocks)
        let rows = detectRows(from: blocks)

        guard columns.count >= 2, rows.count >= 2 else {
            logi("表格检测: 列数=\(columns.count), 行数=\(rows.count), 不足2×2，回退纯文本")
            return flatText(from: blocks)
        }

        // 2. 把每个文字块投进最近的 (行, 列) 单元格
        //    一个单元格可能包含多个块（多行单元格），按 Y 坐标排序后合并
        var cells: [[[(text: String, y: CGFloat)]]] = Array(
            repeating: Array(repeating: [], count: columns.count),
            count: rows.count
        )

        for block in blocks {
            let r = nearestClusterIndex(value: block.boundingBox.midY, clusters: rows)
            let c = nearestClusterIndex(value: block.boundingBox.midX, clusters: columns)
            guard r >= 0, r < rows.count, c >= 0, c < columns.count else { continue }
            cells[r][c].append((block.text, block.boundingBox.midY))
        }

        // 3. 合并单元格内多行文本，生成网格
        var grid: [[String]] = []
        for r in 0..<rows.count {
            var row: [String] = []
            for c in 0..<columns.count {
                let parts = cells[r][c].sorted { $0.y < $1.y }
                row.append(parts.map { $0.text }.joined(separator: " "))
            }
            grid.append(row)
        }

        // 4. 验证：至少要有 2 行，每行在 ≥2 个不同列里有内容
        let validRows = grid.filter { row in row.filter { !$0.isEmpty }.count >= 2 }.count
        guard validRows >= 2 else {
            logi("表格检测: 有效多列行不足(\(validRows))，回退纯文本")
            return flatText(from: blocks)
        }

        logi("表格检测: 成功还原 \(rows.count) 行 × \(columns.count) 列表格")
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

    // MARK: - 行列检测（间隙聚类）

    /// 通过 X 中心坐标的大间隙来检测列
    private static func detectColumns(from blocks: [OCRBlock]) -> [(center: CGFloat, min: CGFloat, max: CGFloat)] {
        let centers = blocks.map { $0.boundingBox.midX }.sorted()
        return clusterByGaps(centers: centers, gapMultiplier: 2.0, minGap: 24)
    }

    /// 通过 Y 中心坐标的大间隙来检测行
    private static func detectRows(from blocks: [OCRBlock]) -> [(center: CGFloat, min: CGFloat, max: CGFloat)] {
        let centers = blocks.map { $0.boundingBox.midY }.sorted()
        return clusterByGaps(centers: centers, gapMultiplier: 2.5, minGap: 14)
    }

    /// 通用间隙聚类：把坐标按大间隙切分成若干簇
    /// - Parameters:
    ///   - centers: 已排序的坐标数组
    ///   - gapMultiplier: 判定为边界的间隙是「中位间隙」的几倍
    ///   - minGap: 最小边界阈值，防止单列/单行被过度拆分
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

        // 计算相邻坐标之间的间隙
        var gaps: [CGFloat] = []
        for i in 1..<centers.count {
            gaps.append(centers[i] - centers[i - 1])
        }

        // 用中位间隙的倍数作为边界阈值
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

        // 最后一个簇
        let clusterCenters = Array(centers[currentStart..<centers.count])
        let avg = clusterCenters.reduce(0, +) / CGFloat(clusterCenters.count)
        clusters.append((avg, clusterCenters.first!, clusterCenters.last!))

        return clusters
    }

    /// 找到距离 value 最近的簇
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

    // MARK: - 内部工具

    private static func flatText(from blocks: [OCRBlock]) -> String {
        let sorted = blocks.sorted { $0.boundingBox.minY < $1.boundingBox.minY }
        return sorted.map { $0.text }.joined(separator: "\n")
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
