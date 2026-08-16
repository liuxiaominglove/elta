import Foundation

// MARK: - 段落检测（悬停翻译核心）单元测试
// 语义：鼠标 = 段落右下角；水平范围由 horizontalScope 决定（双栏=半屏宽 / 整栏=整屏宽），
// 只保留 [max(0, mouseX-scope), mouseX] 内的块；垂直取鼠标上方半屏窗口；按「行距为主 + 首行缩进为辅」分段，段间 "\n\n"。

private func tl(_ text: String, _ x: CGFloat, _ y: CGFloat, _ h: CGFloat = 14) -> TextLine {
    TextLine(text: text, minX: x, maxX: x + 500, minY: y, maxY: y + h)
}

private func block(_ text: String, _ x: CGFloat, _ y: CGFloat,
                   w: CGFloat = 500, h: CGFloat = 14) -> OCRBlock {
    OCRBlock(text: text, boundingBox: CGRect(x: x, y: y, width: w, height: h))
}

/// 双页（同屏双栏）：左页 minX=50 宽 300（maxX=350），右页 minX=400 宽 300（maxX=700），中缝 gap=50
private func twoPageBlocks() -> [OCRBlock] {
    [block("L1 one", 50, 10, w: 300), block("L1 two", 50, 28, w: 300),
     block("R1 one", 400, 10, w: 300), block("R1 two", 400, 28, w: 300)]
}

/// 维基式（左目录 + 主文，间隙很小但水平不重叠）：TOC maxX≈617，主文 minX≈659
private func wikiBlocks() -> [OCRBlock] {
    [block("Contents", 109, 100, w: 300),
     block("Overview", 217, 118, w: 400),
     block("main one", 659, 100, w: 1900),
     block("main two", 660, 118, w: 1800)]
}

func runParagraphDetectorTests() {
    // ---- clusterLines：聚行（回归） ----
    test("clusterLines: 同一视觉行合并为一行（按 x 排序拼接）") {
        let lines = ParagraphDetector.clusterLines([block("Hello", 50, 10, w: 60), block("world", 130, 10, w: 50)])
        try assertEqual(lines.count, 1)
        try assertEqual(lines[0].text, "Hello world")
    }
    test("clusterLines: 不同行拆为两行") {
        let lines = ParagraphDetector.clusterLines([block("one", 50, 10), block("two", 50, 28)])
        try assertEqual(lines.count, 2)
    }
    test("clusterLines: 空块返回空") {
        try assertEqual(ParagraphDetector.clusterLines([]).count, 0)
    }

    // ---- paragraphSegments：分段（行距为主 + 缩进为辅） ----
    test("paragraphSegments: 空行分段为两段") {
        let lines = [tl("P1 a", 50, 10), tl("P1 b", 50, 28), tl("P2 a", 50, 66), tl("P2 b", 50, 84)]
        let segs = ParagraphDetector.paragraphSegments(lines)
        try assertEqual(segs.count, 2)
        try assertEqual(segs[0].map { $0.text }, ["P1 a", "P1 b"])
        try assertEqual(segs[1].map { $0.text }, ["P2 a", "P2 b"])
    }
    test("paragraphSegments: 首行缩进分段为两段") {
        let lines = [tl("A one", 50, 10), tl("A two", 50, 28), tl("B one", 78, 46), tl("B two", 50, 64)]
        let segs = ParagraphDetector.paragraphSegments(lines)
        try assertEqual(segs.count, 2)
        try assertEqual(segs[1].map { $0.text }, ["B one", "B two"])
    }
    test("paragraphSegments: 无信号单段") {
        let segs = ParagraphDetector.paragraphSegments([tl("a", 50, 10), tl("b", 50, 28)])
        try assertEqual(segs.count, 1)
    }
    test("paragraphSegments: 整块引文（每行都缩进）不逐行拆分") {
        let lines = [tl("body", 50, 10), tl("quote one", 78, 28), tl("quote two", 78, 46), tl("after", 50, 100)]
        let segs = ParagraphDetector.paragraphSegments(lines)
        try assertEqual(segs.count, 3)
        try assertEqual(segs[1].map { $0.text }, ["quote one", "quote two"])
    }
    test("paragraphSegments: 悬挂缩进（缩进块内编号列表）不逐行拆分") {
        let lines = [tl("body", 50, 10), tl("1. item", 78, 28), tl("cont", 106, 46), tl("2. item", 78, 64), tl("body2", 50, 100)]
        let segs = ParagraphDetector.paragraphSegments(lines)
        try assertEqual(segs.count, 3)
        try assertEqual(segs[1].map { $0.text }, ["1. item", "cont", "2. item"])
    }
    test("paragraphSegments: 段落间距（约半个行高以上）正确分段") {
        let lines = [tl("a1", 50, 10), tl("a2", 50, 29), tl("b1", 50, 84)]
        let segs = ParagraphDetector.paragraphSegments(lines)
        try assertEqual(segs.count, 2)
        try assertEqual(segs[0].map { $0.text }, ["a1", "a2"])
        try assertEqual(segs[1].map { $0.text }, ["b1"])
    }
    test("paragraphSegments: 空输入返回空") {
        try assertEqual(ParagraphDetector.paragraphSegments([]).count, 0)
    }

    // ---- columnBlocks：水平列（X 重叠聚类，返回整块集合） ----
    test("columnBlocks: 双页·鼠标在右页只取右页块") {
        let blocks = ParagraphDetector.columnBlocks(twoPageBlocks(), mouseX: 680, mouseY: 20, maxScope: 1400)
        try assertEqual(blocks.map { $0.text }.sorted(), ["R1 one", "R1 two"])
    }
    test("columnBlocks: 双页·鼠标在左页只取左页块") {
        let blocks = ParagraphDetector.columnBlocks(twoPageBlocks(), mouseX: 300, mouseY: 20, maxScope: 1400)
        try assertEqual(blocks.map { $0.text }.sorted(), ["L1 one", "L1 two"])
    }
    test("columnBlocks: 维基式·主文排除左目录") {
        let blocks = ParagraphDetector.columnBlocks(wikiBlocks(), mouseX: 2500, mouseY: 110, maxScope: 3360)
        try assertEqual(blocks.map { $0.text }.sorted(), ["main one", "main two"])
    }
    test("columnBlocks: 单栏取全部块") {
        let blocks = ParagraphDetector.columnBlocks([block("a", 100, 10, w: 1800), block("b", 100, 28, w: 1500)], mouseX: 1800, mouseY: 20, maxScope: 3360)
        try assertEqual(blocks.count, 2)
    }
    test("columnBlocks: 空块返回空") {
        try assertEqual(ParagraphDetector.columnBlocks([], mouseX: 1000, mouseY: 20, maxScope: 1400).count, 0)
    }

    // ---- contentTop：顶部 chrome 检测 ----
    test("contentTop: 有标签栏（浏览器）→ 固定顶部比例") {
        let blocks = [
            block("tab", 100, 22, w: 500),      // 22-36（标签栏，y < 4% 屏高）
            block("url", 29, 50, w: 1150),      // 50-64
            block("body", 898, 200, w: 2100),   // 200-214
        ]
        try assertEqual(ParagraphDetector.contentTop(blocks, screenHeight: 1000), 120)
    }
    test("contentTop: 有标签栏 + 正文带表格（大间隙）仍用固定比例，不被表格间隙误判") {
        let blocks = [
            block("tab", 100, 22, w: 500),      // 标签栏
            block("body", 898, 200, w: 2100),   // 正文
            block("table", 900, 320, w: 300),   // 表格（与正文有 80 大间隙）
        ]
        // 有标签栏 → 固定比例 120，而不是被正文→表格间隙带偏
        try assertEqual(ParagraphDetector.contentTop(blocks, screenHeight: 1000), 120)
    }
    test("contentTop: 干净阅读器（无标签栏）返回 0") {
        let blocks = [
            block("good question", 268, 116, w: 1289, h: 51),
            block("your parents", 1781, 116, w: 1267, h: 58),
            block("best to duck", 196, 181, w: 1332, h: 51),
        ]
        try assertEqual(ParagraphDetector.contentTop(blocks, screenHeight: 2100), 0)
    }
    test("contentTop: 单块返回 0") {
        try assertEqual(ParagraphDetector.contentTop([block("a", 100, 200)], screenHeight: 1000), 0)
    }

    // ---- extractWindow：固定窗口 + 水平列提取（自动分段） ----
    test("extractWindow: 双栏·鼠标在右页只取右页") {
        try assertEqual(ParagraphDetector.extractWindow(twoPageBlocks(), mouseX: 680, mouseY: 35, windowHeight: 100, horizontalScope: 350), "R1 one R1 two")
    }
    test("extractWindow: 双栏·鼠标在左页只取左页") {
        try assertEqual(ParagraphDetector.extractWindow(twoPageBlocks(), mouseX: 300, mouseY: 35, windowHeight: 100, horizontalScope: 350), "L1 one L1 two")
    }
    test("extractWindow: 维基式·整栏只取主文（排除左目录）") {
        try assertEqual(ParagraphDetector.extractWindow(wikiBlocks(), mouseX: 2500, mouseY: 130, windowHeight: 200, horizontalScope: 3360), "main one main two")
    }
    test("extractWindow: 顶部浏览器 chrome 被裁掉") {
        let blocks = [
            block("tab", 100, 22, w: 500),
            block("url", 29, 50, w: 1150),
            block("TOC1", 22, 300, w: 100),
            block("body1", 898, 300, w: 2100),
            block("body2", 898, 318, w: 2100),
        ]
        try assertEqual(ParagraphDetector.extractWindow(blocks, mouseX: 3044, mouseY: 325, windowHeight: 1000, horizontalScope: 3360), "body1 body2")
    }
    test("extractWindow: 整栏·全宽段落整段提取") {
        let blocks = [block("F1", 50, 10, w: 600), block("F2", 50, 28, w: 600)]
        try assertEqual(ParagraphDetector.extractWindow(blocks, mouseX: 680, mouseY: 35, windowHeight: 100, horizontalScope: 700), "F1 F2")
    }
    test("extractWindow: 整栏·右界排除鼠标右侧内容") {
        let blocks = [block("main", 50, 10, w: 600), block("pagenum", 690, 10, w: 20)]
        try assertEqual(ParagraphDetector.extractWindow(blocks, mouseX: 680, mouseY: 15, windowHeight: 100, horizontalScope: 700), "main")
    }
    test("extractWindow: 双栏模式·全宽段落左边界切空（选错模式的预期）") {
        let blocks = [block("F1", 50, 10, w: 600)]
        try assertEqual(ParagraphDetector.extractWindow(blocks, mouseX: 680, mouseY: 15, windowHeight: 100, horizontalScope: 350), "")
    }
    test("extractWindow: 正文+表格 → 表格转 Markdown，正文保留") {
        let blocks = [
            block("intro", 898, 296, w: 2143),
            block("H1", 927, 500, w: 210),
            block("H2", 1166, 500, w: 246),
            block("H3", 1434, 500, w: 311),
            block("R1C1", 927, 560, w: 167),
            block("R1C2", 1173, 560, w: 174),
            block("R1C3", 1441, 560, w: 80),
        ]
        let text = ParagraphDetector.extractWindow(blocks, mouseX: 2000, mouseY: 600, windowHeight: 1000, horizontalScope: 3360)
        try assertTrue(text.contains("intro"), "正文应保留")
        try assertTrue(text.contains("| H1 | H2 | H3 |"), "表头应为 Markdown")
        try assertTrue(text.contains("| R1C1 | R1C2 | R1C3 |"), "数据行应为 Markdown")
    }
    test("extractWindow: 纯文本（无表格）不变") {
        let blocks = [block("A a", 50, 300), block("A b", 50, 318), block("B one", 50, 344), block("B two", 50, 362)]
        try assertEqual(ParagraphDetector.extractWindow(blocks, mouseX: 600, mouseY: 378, windowHeight: 100, horizontalScope: 700), "A a A b\n\nB one B two")
    }

    test("extractWindow: 多段整窗口（缩进分段）") {
        let blocks = [block("A one", 50, 10), block("A two", 50, 28), block("B one", 78, 46), block("B two", 50, 64)]
        try assertEqual(ParagraphDetector.extractWindow(blocks, mouseX: 600, mouseY: 78, windowHeight: 100, horizontalScope: 700), "A one A two\n\nB one B two")
    }
    test("extractWindow: 顶部切半个段落 + 整段") {
        let blocks = [block("A a", 50, 10), block("A b", 50, 28), block("A c", 50, 46), block("B one", 50, 74)]
        try assertEqual(ParagraphDetector.extractWindow(blocks, mouseX: 600, mouseY: 88, windowHeight: 40, horizontalScope: 700), "A c\n\nB one")
    }
    test("extractWindow: 单行段落") {
        try assertEqual(ParagraphDetector.extractWindow([block("Solo line", 78, 10)], mouseX: 600, mouseY: 15, windowHeight: 100, horizontalScope: 700), "Solo line")
    }
    test("extractWindow: 空块返回空串") {
        try assertEqual(ParagraphDetector.extractWindow([], mouseX: 600, mouseY: 50, windowHeight: 100, horizontalScope: 700), "")
    }
    test("extractWindow: 鼠标太左（无水平范围内文本）返回空串") {
        try assertEqual(ParagraphDetector.extractWindow([block("a", 50, 10)], mouseX: 10, mouseY: 15, windowHeight: 100, horizontalScope: 350), "")
    }
    test("extractWindow: 窗口高于所有内容返回空串") {
        try assertEqual(ParagraphDetector.extractWindow([block("a", 50, 10), block("b", 50, 28)], mouseX: 600, mouseY: -5, windowHeight: 100, horizontalScope: 700), "")
    }
    test("extractWindow: 窗口低于所有内容返回空串") {
        try assertEqual(ParagraphDetector.extractWindow([block("a", 50, 10), block("b", 50, 28)], mouseX: 600, mouseY: 1000, windowHeight: 100, horizontalScope: 700), "")
    }
}

// MARK: - 屏幕坐标映射单元测试

func runScreenGeometryTests() {
    test("pointToImagePixel: 屏幕中心映射为图像中心") {
        let p = ScreenGeometry.pointToImagePixel(
            globalPoint: CGPoint(x: 50, y: 50),
            screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            imageSize: CGSize(width: 200, height: 200))
        try assertTrue(abs(p.x - 100) < 0.001, "x 应 100")
        try assertTrue(abs(p.y - 100) < 0.001, "y 应 100")
    }

    test("pointToImagePixel: 左下原点翻转 Y 轴") {
        let p = ScreenGeometry.pointToImagePixel(
            globalPoint: CGPoint(x: 0, y: 0),
            screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            imageSize: CGSize(width: 200, height: 200))
        try assertTrue(abs(p.x - 0) < 0.001)
        try assertTrue(abs(p.y - 200) < 0.001, "底部应映射为图像底部 y=200")
    }

    test("pointToImagePixel: 屏幕左上角映射为图像顶部") {
        let p = ScreenGeometry.pointToImagePixel(
            globalPoint: CGPoint(x: 0, y: 100),
            screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            imageSize: CGSize(width: 200, height: 200))
        try assertTrue(abs(p.x - 0) < 0.001)
        try assertTrue(abs(p.y - 0) < 0.001)
    }

    test("pointToImagePixel: 副屏（带 frame 偏移）正确换算") {
        let p = ScreenGeometry.pointToImagePixel(
            globalPoint: CGPoint(x: 150, y: 50),
            screenFrame: CGRect(x: 100, y: 0, width: 100, height: 100),
            imageSize: CGSize(width: 200, height: 200))
        try assertTrue(abs(p.x - 100) < 0.001)
        try assertTrue(abs(p.y - 100) < 0.001)
    }

    test("pointToImagePixel: 非法尺寸返回零") {
        let p = ScreenGeometry.pointToImagePixel(
            globalPoint: CGPoint(x: 50, y: 50),
            screenFrame: CGRect(x: 0, y: 0, width: 0, height: 100),
            imageSize: CGSize(width: 200, height: 200))
        try assertTrue(abs(p.x) < 0.001, "x 应 0")
        try assertTrue(abs(p.y) < 0.001, "y 应 0")
    }
}
