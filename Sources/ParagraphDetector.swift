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

    static func clusterLines(_ blocks: [OCRBlock]) -> [TextLine] {
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

        return groups.map { group -> TextLine in
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

    // MARK: - 水平列边界（重叠聚类）

    /// 从 mouseX 向左寻找所在列的左边界。按「水平是否重叠」聚类（无需间隙阈值）：
    /// 目录栏与正文、左右页之间只要不水平重叠就会自动分离，返回最右列（鼠标所在列）的左缘。
    static func columnLeftBound(_ blocks: [OCRBlock], mouseX: CGFloat, maxScope: CGFloat) -> CGFloat {
        let lowerBound = max(0, mouseX - maxScope)
        let lefts = blocks.filter { $0.boundingBox.minX <= mouseX }
        guard !lefts.isEmpty else { return lowerBound }

        let sorted = lefts.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        var currentMin = sorted[0].boundingBox.minX
        var currentMax = sorted[0].boundingBox.maxX

        for b in sorted.dropFirst() {
            let r = b.boundingBox
            if r.minX <= currentMax {
                // 与当前列水平重叠 → 同列
                currentMin = min(currentMin, r.minX)
                currentMax = max(currentMax, r.maxX)
            } else {
                // 无重叠 → 右侧新列
                currentMin = r.minX
                currentMax = r.maxX
            }
        }
        return max(lowerBound, currentMin)
    }

    // MARK: - 主入口：提取固定高度窗口 + 水平列内的文本（自动分段）

    /// 鼠标 = 段落右下角。先取垂直窗口 [mouseY - windowHeight, mouseY]（排除顶部 chrome），
    /// 再用重叠聚类取鼠标所在水平列（排除左侧目录/侧栏、右侧内容），
    /// 按「行距 + 缩进」分段，段内行用空格拼接、段间用 "\n\n" 连接。
    static func extractWindow(
        _ blocks: [OCRBlock],
        mouseX: CGFloat,
        mouseY: CGFloat,
        windowHeight: CGFloat,
        horizontalScope: CGFloat,
        config: Config = Config()
    ) -> String {
        guard !blocks.isEmpty else { return "" }

        // 1. 垂直窗口
        let windowTop = max(0, mouseY - windowHeight)
        let windowBlocks = blocks.filter {
            $0.boundingBox.maxY >= windowTop && $0.boundingBox.minY <= mouseY
        }
        guard !windowBlocks.isEmpty else { return "" }

        // 2. 水平列（重叠聚类取鼠标所在列）
        let leftBound = columnLeftBound(windowBlocks, mouseX: mouseX, maxScope: horizontalScope)
        let horizontal = windowBlocks.filter {
            $0.boundingBox.minX >= leftBound && $0.boundingBox.minX <= mouseX
        }
        guard !horizontal.isEmpty else { return "" }

        // 3. 聚行 + 分段
        let lines = clusterLines(horizontal)
        let segments = paragraphSegments(lines, config: config)
        return segments.map { $0.map { $0.text }.joined(separator: " ") }
                       .joined(separator: "\n\n")
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
