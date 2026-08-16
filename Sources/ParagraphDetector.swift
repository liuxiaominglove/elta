import Foundation

// MARK: - 视觉文本行（OCR 块聚合后的行）

struct TextLine {
    let text: String
    let minX: CGFloat
    let maxX: CGFloat
    let minY: CGFloat
    let maxY: CGFloat

    var height: CGFloat { maxY - minY }
    var midY: CGFloat { (minY + maxY) / 2 }
}

// MARK: - 段落检测（悬停翻译核心）

/// 悬停翻译核心：提取鼠标上方固定高度窗口内的文本。
/// 输入带坐标的 OCR 块 + 鼠标（图像像素坐标，左上原点）+ 窗口高度，输出分段拼接文本。
enum ParagraphDetector {
    struct Config {
        /// 缩进阈值 = 中位行高 × indentRatio
        var indentRatio: CGFloat = 1.0
        /// 行距阈值 = 中位行高 × gapRatio（约半个行高，视为段落间距/空行）
        var gapRatio: CGFloat = 0.5
    }

    // MARK: - 聚行：把同一视觉行的 OCR 块合并

    /// 把 OCR 块按垂直位置聚成「视觉行」（每行 = 一组同 Y 的块，未合并文本）
    static func groupLines(_ blocks: [OCRBlock]) -> [[OCRBlock]] {
        guard !blocks.isEmpty else { return [] }

        let sorted = blocks.sorted {
            if $0.boundingBox.minY != $1.boundingBox.minY { return $0.boundingBox.minY < $1.boundingBox.minY }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
        let medH = median(blocks.map { $0.boundingBox.height }) ?? 14

        var groups: [[OCRBlock]] = []
        for b in sorted {
            if var last = groups.last {
                let lastMinY = last.map { $0.boundingBox.minY }.min() ?? 0
                let lastMaxY = last.map { $0.boundingBox.maxY }.max() ?? 0
                let lastMidY = (lastMinY + lastMaxY) / 2
                if abs(b.boundingBox.midY - lastMidY) <= medH * 0.5 {
                    last.append(b)
                    groups[groups.count - 1] = last
                    continue
                }
            }
            groups.append([b])
        }
        return groups
    }

    static func clusterLines(_ blocks: [OCRBlock]) -> [TextLine] {
        return groupLines(blocks).map { group -> TextLine in
            let xSorted = group.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            let minX = xSorted.map { $0.boundingBox.minX }.min() ?? 0
            let maxX = xSorted.map { $0.boundingBox.maxX }.max() ?? 0
            let minY = xSorted.map { $0.boundingBox.minY }.min() ?? 0
            let maxY = xSorted.map { $0.boundingBox.maxY }.max() ?? 0
            let text = xSorted.map { $0.text }.joined(separator: " ")
            return TextLine(text: text, minX: minX, maxX: maxX, minY: minY, maxY: maxY)
        }
    }

    // MARK: - 分段：按「行距为主 + 首行缩进为辅」切分段落

    /// 把视觉行按段落边界切分。段落起点 = 首行（恒为段首）或满足以下任一条件的行：
    /// - 行距：与上一行的垂直 gap ≥ 行距阈值（= 中位行高 × gapRatio，约半个行高即视为空行）
    /// - 首行缩进：本行相对上一行右移 ≥ 缩进阈值，且上一行仍在正文左边距（正文→缩进的首行；
    ///   整块引文/悬挂缩进不会误触发，因为它们的「上一行」本身已缩进）
    static func paragraphSegments(_ lines: [TextLine], config: Config = Config()) -> [[TextLine]] {
        guard !lines.isEmpty else { return [] }

        let rawMedH = median(lines.map { $0.height }) ?? 14
        let medH = rawMedH > 0 ? rawMedH : 14  // 全 0 高度退化防护
        // 正文左边距 = 最小 minX（首行缩进总是相对正文左移，续行定义最左列）
        let bodyMargin = lines.map { $0.minX }.min() ?? 0
        let indentThreshold = medH * config.indentRatio
        let gapThreshold = medH * config.gapRatio

        var segments: [[TextLine]] = []
        var current: [TextLine] = [lines[0]]

        for i in 1..<lines.count {
            let gap = lines[i].minY - lines[i - 1].maxY >= gapThreshold

            let shiftedRight = lines[i].minX - lines[i - 1].minX >= indentThreshold
            let prevAtBody = lines[i - 1].minX - bodyMargin < indentThreshold
            let indent = shiftedRight && prevAtBody

            if gap || indent {
                segments.append(current)
                current = [lines[i]]
            } else {
                current.append(lines[i])
            }
        }
        segments.append(current)
        return segments
    }

    // MARK: - 顶部 chrome 检测

    /// 检测正文顶部边界（排除顶部浏览器 chrome：标签栏/地址栏/书签栏）。
    /// 若顶部存在标签栏（浏览器 chrome 特征：y < 屏高 4% 的短块），用固定顶部比例（屏高 12%）裁掉 chrome；
    /// 干净阅读器（无标签栏）返回 0。不再用「大间隙」启发式——正文里的表格/标题间隙会误判。
    static func contentTop(_ blocks: [OCRBlock], screenHeight: CGFloat) -> CGFloat {
        let hasTabBar = blocks.contains { $0.boundingBox.maxY < screenHeight * 0.04 }
        return hasTabBar ? screenHeight * 0.12 : 0
    }

    // MARK: - 水平列（X 重叠聚类）

    /// 返回鼠标所在列的整块集合。按「水平是否重叠」聚类（正文段落间距不影响列归属）：
    /// 目录栏与正文、左右页之间因水平不重叠自动分离；顶部浏览器 chrome 已由 contentTop 裁掉。
    static func columnBlocks(_ blocks: [OCRBlock], mouseX: CGFloat, mouseY: CGFloat, maxScope: CGFloat) -> [OCRBlock] {
        let lowerBound = max(0, mouseX - maxScope)
        let lefts = blocks.filter { $0.boundingBox.minX <= mouseX }
        guard !lefts.isEmpty else { return [] }

        let n = lefts.count
        var parent = Array(0..<n)
        func find(_ i: Int) -> Int {
            var r = i
            while parent[r] != r { r = parent[r] }
            var c = i
            while parent[c] != r { let nx = parent[c]; parent[c] = r; c = nx }
            return r
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        for i in 0..<n {
            let a = lefts[i].boundingBox
            for j in (i + 1)..<n {
                let b = lefts[j].boundingBox
                let xOverlap = a.maxX >= b.minX && b.maxX >= a.minX
                if xOverlap { union(i, j) }
            }
        }

        func hDist(_ r: CGRect) -> CGFloat {
            if mouseX < r.minX { return r.minX - mouseX }
            if mouseX > r.maxX { return mouseX - r.maxX }
            return 0
        }
        func vDist(_ r: CGRect) -> CGFloat {
            if mouseY < r.minY { return r.minY - mouseY }
            if mouseY > r.maxY { return mouseY - r.maxY }
            return 0
        }

        var anchor = 0
        var best = CGFloat.greatestFiniteMagnitude
        for i in 0..<n {
            let score = vDist(lefts[i].boundingBox) * 2 + hDist(lefts[i].boundingBox)
            if score < best { best = score; anchor = i }
        }

        let root = find(anchor)
        var result: [OCRBlock] = []
        for i in 0..<n where find(i) == root {
            if lefts[i].boundingBox.minX >= lowerBound {
                result.append(lefts[i])
            }
        }
        return result
    }

    // MARK: - 表格识别 + 列内文本/表格组装

    /// 判断一个「视觉行」（同 Y 的块组）是否为表格行：X 排序后存在被「大间隙」分隔的多个单元格。
    static func isTableRow(_ line: [OCRBlock], cellGap: CGFloat) -> Bool {
        guard line.count >= 2 else { return false }
        let xSorted = line.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        for i in 1..<xSorted.count {
            if xSorted[i].boundingBox.minX - xSorted[i - 1].boundingBox.maxX > cellGap {
                return true
            }
        }
        return false
    }

    /// 把列内块转为文本：连续的表格行区域转 Markdown 表格，其余按「行距 + 缩进」分段。
    static func extractColumnText(_ blocks: [OCRBlock], config: Config) -> String {
        let lineGroups = groupLines(blocks)
        guard !lineGroups.isEmpty else { return "" }

        let medH = median(blocks.map { $0.boundingBox.height }) ?? 14
        let cellGap = max(medH * 0.4, 8)

        var parts: [String] = []
        var textRun: [OCRBlock] = []
        var tableRun: [OCRBlock] = []

        for line in lineGroups {
            if isTableRow(line, cellGap: cellGap) {
                if !textRun.isEmpty {
                    parts.append(renderTextRun(textRun, config: config))
                    textRun = []
                }
                tableRun.append(contentsOf: line)
            } else {
                if !tableRun.isEmpty {
                    parts.append(renderTableRun(tableRun, config: config))
                    tableRun = []
                }
                textRun.append(contentsOf: line)
            }
        }
        if !textRun.isEmpty {
            parts.append(renderTextRun(textRun, config: config))
        }
        if !tableRun.isEmpty {
            parts.append(renderTableRun(tableRun, config: config))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func renderTextRun(_ blocks: [OCRBlock], config: Config) -> String {
        let lines = clusterLines(blocks)
        let segments = paragraphSegments(lines, config: config)
        return segments.map { $0.map { $0.text }.joined(separator: " ") }
                       .joined(separator: "\n\n")
    }

    private static func renderTableRun(_ blocks: [OCRBlock], config: Config) -> String {
        if let table = TableExtractor.tableMarkdown(blocks) {
            return table
        }
        // 不是表格 → 回退为正文
        return renderTextRun(blocks, config: config)
    }

    // MARK: - 主入口：提取固定高度窗口 + 水平列内的文本（自动分段）

    /// 鼠标 = 段落右下角。先裁掉顶部浏览器 chrome（contentTop），再取垂直窗口
    /// [max(contentTop, mouseY - windowHeight), mouseY]，用「X 重叠」聚类取鼠标所在水平列
    /// （排除左侧目录/侧栏、右侧内容），按「行距 + 缩进」分段，段内行空格拼接、段间 "\n\n"。
    static func extractWindow(
        _ blocks: [OCRBlock],
        mouseX: CGFloat,
        mouseY: CGFloat,
        windowHeight: CGFloat,
        horizontalScope: CGFloat,
        config: Config = Config()
    ) -> String {
        guard !blocks.isEmpty else { return "" }

        // 1. 垂直窗口（顶部裁掉浏览器 chrome）
        let top = contentTop(blocks, screenHeight: windowHeight * 2)
        let windowTop = max(top, mouseY - windowHeight)
        let windowBlocks = blocks.filter {
            $0.boundingBox.maxY >= windowTop && $0.boundingBox.minY <= mouseY
        }
        guard !windowBlocks.isEmpty else { return "" }

        // 2. 水平列（X 重叠聚类取鼠标所在列的整块集合）
        let column = columnBlocks(windowBlocks, mouseX: mouseX, mouseY: mouseY, maxScope: horizontalScope)
        guard !column.isEmpty else { return "" }

        // 3. 聚行 + 分段（表格区域转 Markdown 表格，正文按「行距 + 缩进」分段）
        return extractColumnText(column, config: config)
    }

    // MARK: - 工具

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
}
