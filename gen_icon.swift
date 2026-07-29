import AppKit
import Foundation

// MARK: - 啄木鸟素描图标生成器
// 极简线条风格，适合 macOS 图标

func drawWoodpecker(size: CGFloat) -> NSImage {
    let W = size, H = size
    let img = NSImage(size: NSSize(width: W, height: H))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }

    let pad: CGFloat = size * 0.18
    let innerW = W - pad * 2
    let innerH = H - pad * 2
    let cx = W / 2, cy = H / 2

    // === 背景圆（浅灰） ===
    ctx.setFillColor(NSColor(white: 0.96, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: CGRect(x: pad * 0.5, y: pad * 0.5, width: W - pad, height: H - pad))

    // === 啄木鸟主体 ===
    let lineColor = NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0).cgColor
    let accentColor = NSColor(red: 0.85, green: 0.25, blue: 0.15, alpha: 1.0).cgColor  // 红冠

    ctx.setStrokeColor(lineColor)
    ctx.setLineWidth(size * 0.025)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // 缩放因子 - 让啄木鸟适配内部区域
    let s = innerW / 800.0
    let baseX = cx - 350 * s
    let baseY = cy + 80 * s

    // --- 身体轮廓 ---
    let body = CGMutablePath()
    // 从尾部开始（左下）
    body.move(to: CGPoint(x: baseX + 120 * s, y: baseY - 200 * s))
    // 腹线向右
    body.addCurve(to: CGPoint(x: baseX + 420 * s, y: baseY - 280 * s),
                  control1: CGPoint(x: baseX + 220 * s, y: baseY - 200 * s),
                  control2: CGPoint(x: baseX + 320 * s, y: baseY - 280 * s))
    // 胸线向上
    body.addCurve(to: CGPoint(x: baseX + 350 * s, y: baseY + 80 * s),
                  control1: CGPoint(x: baseX + 500 * s, y: baseY - 200 * s),
                  control2: CGPoint(x: baseX + 480 * s, y: baseY + 0 * s))
    // 颈部
    body.addCurve(to: CGPoint(x: baseX + 400 * s, y: baseY + 200 * s),
                  control1: CGPoint(x: baseX + 320 * s, y: baseY + 120 * s),
                  control2: CGPoint(x: baseX + 380 * s, y: baseY + 160 * s))
    // 头部顶部（冠羽处）
    body.addCurve(to: CGPoint(x: baseX + 350 * s, y: baseY + 350 * s),
                  control1: CGPoint(x: baseX + 450 * s, y: baseY + 280 * s),
                  control2: CGPoint(x: baseX + 400 * s, y: baseY + 330 * s))
    // 头顶
    body.addCurve(to: CGPoint(x: baseX + 220 * s, y: baseY + 380 * s),
                  control1: CGPoint(x: baseX + 300 * s, y: baseY + 370 * s),
                  control2: CGPoint(x: baseX + 260 * s, y: baseY + 390 * s))
    // 前额
    body.addLine(to: CGPoint(x: baseX + 140 * s, y: baseY + 340 * s))
    // 喙（长尖嘴）- 向前伸出
    body.addLine(to: CGPoint(x: baseX - 280 * s, y: baseY + 300 * s))
    body.addLine(to: CGPoint(x: baseX + 60 * s, y: baseY + 260 * s))
    // 下颌
    body.addCurve(to: CGPoint(x: baseX + 100 * s, y: baseY + 120 * s),
                  control1: CGPoint(x: baseX + 20 * s, y: baseY + 220 * s),
                  control2: CGPoint(x: baseX + 60 * s, y: baseY + 160 * s))
    // 回到腹部
    body.addCurve(to: CGPoint(x: baseX + 120 * s, y: baseY - 200 * s),
                  control1: CGPoint(x: baseX + 140 * s, y: baseY + 40 * s),
                  control2: CGPoint(x: baseX + 80 * s, y: baseY - 100 * s))
    body.closeSubpath()

    // 填充身体
    ctx.setFillColor(NSColor(white: 0.2, alpha: 1.0).cgColor)
    ctx.addPath(body)
    ctx.fillPath()

    // 描边身体轮廓
    ctx.setStrokeColor(lineColor)
    ctx.addPath(body)
    ctx.strokePath()

    // --- 翅膀弧线 ---
    let wing = CGMutablePath()
    wing.move(to: CGPoint(x: baseX + 220 * s, y: baseY + 150 * s))
    wing.addCurve(to: CGPoint(x: baseX + 160 * s, y: baseY - 100 * s),
                  control1: CGPoint(x: baseX + 280 * s, y: baseY + 80 * s),
                  control2: CGPoint(x: baseX + 260 * s, y: baseY - 40 * s))
    wing.addCurve(to: CGPoint(x: baseX + 240 * s, y: baseY + 180 * s),
                  control1: CGPoint(x: baseX + 100 * s, y: baseY - 120 * s),
                  control2: CGPoint(x: baseX + 160 * s, y: baseY + 100 * s))
    ctx.setFillColor(NSColor(white: 0.35, alpha: 1.0).cgColor)
    ctx.addPath(wing)
    ctx.fillPath()
    ctx.setStrokeColor(lineColor)
    ctx.addPath(wing)
    ctx.strokePath()

    // --- 尾羽 ---
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: baseX + 120 * s, y: baseY + 20 * s))
    tail.addCurve(to: CGPoint(x: baseX - 60 * s, y: baseY - 180 * s),
                  control1: CGPoint(x: baseX + 40 * s, y: baseY - 60 * s),
                  control2: CGPoint(x: baseX - 30 * s, y: baseY - 140 * s))
    tail.addLine(to: CGPoint(x: baseX + 30 * s, y: baseY - 80 * s))
    tail.addCurve(to: CGPoint(x: baseX + 130 * s, y: baseY + 10 * s),
                  control1: CGPoint(x: baseX + 70 * s, y: baseY - 40 * s),
                  control2: CGPoint(x: baseX + 100 * s, y: baseY - 10 * s))
    ctx.setFillColor(NSColor(white: 0.3, alpha: 1.0).cgColor)
    ctx.addPath(tail)
    ctx.fillPath()
    ctx.setStrokeColor(lineColor)
    ctx.addPath(tail)
    ctx.strokePath()

    // --- 眼部 ---
    let eyeX = baseX + 230 * s
    let eyeY = baseY + 310 * s
    let eyeR = 22 * s
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: eyeX - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2))
    ctx.setStrokeColor(lineColor)
    ctx.strokeEllipse(in: CGRect(x: eyeX - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2))
    // 瞳孔
    ctx.setFillColor(NSColor(white: 0.15, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: CGRect(x: eyeX - eyeR * 0.5, y: eyeY - eyeR * 0.5, width: eyeR, height: eyeR))
    // 眼部高光
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: eyeX - eyeR * 0.2, y: eyeY + eyeR * 0.1, width: eyeR * 0.35, height: eyeR * 0.35))

    // --- 冠羽红顶 ---
    let crest = CGMutablePath()
    crest.move(to: CGPoint(x: baseX + 220 * s, y: baseY + 370 * s))
    crest.addCurve(to: CGPoint(x: baseX + 200 * s, y: baseY + 430 * s),
                   control1: CGPoint(x: baseX + 240 * s, y: baseY + 400 * s),
                   control2: CGPoint(x: baseX + 220 * s, y: baseY + 430 * s))
    crest.addCurve(to: CGPoint(x: baseX + 280 * s, y: baseY + 440 * s),
                   control1: CGPoint(x: baseX + 180 * s, y: baseY + 460 * s),
                   control2: CGPoint(x: baseX + 240 * s, y: baseY + 460 * s))
    crest.addCurve(to: CGPoint(x: baseX + 350 * s, y: baseY + 350 * s),
                   control1: CGPoint(x: baseX + 320 * s, y: baseY + 410 * s),
                   control2: CGPoint(x: baseX + 360 * s, y: baseY + 380 * s))
    ctx.setFillColor(accentColor)
    ctx.addPath(crest)
    ctx.fillPath()
    ctx.setStrokeColor(lineColor)
    ctx.addPath(crest)
    ctx.strokePath()

    // --- 腿/爪 ---
    ctx.setLineWidth(size * 0.018)
    let legX = baseX + 260 * s  // 前腿
    let legX2 = baseX + 200 * s // 后腿
    let legBaseY = baseY - 280 * s

    // 前腿
    ctx.move(to: CGPoint(x: legX, y: legBaseY))
    ctx.addLine(to: CGPoint(x: legX - 10 * s, y: legBaseY - 70 * s))
    ctx.strokePath()
    // 前爪
    let clawPath = CGMutablePath()
    clawPath.move(to: CGPoint(x: legX - 10 * s, y: legBaseY - 70 * s))
    clawPath.addLine(to: CGPoint(x: legX - 40 * s, y: legBaseY - 100 * s))
    clawPath.move(to: CGPoint(x: legX - 10 * s, y: legBaseY - 70 * s))
    clawPath.addLine(to: CGPoint(x: legX, y: legBaseY - 110 * s))
    clawPath.move(to: CGPoint(x: legX - 10 * s, y: legBaseY - 70 * s))
    clawPath.addLine(to: CGPoint(x: legX + 25 * s, y: legBaseY - 95 * s))
    ctx.addPath(clawPath)
    ctx.strokePath()

    // 后腿
    ctx.move(to: CGPoint(x: legX2, y: legBaseY + 30 * s))
    ctx.addLine(to: CGPoint(x: legX2 - 5 * s, y: legBaseY - 45 * s))
    ctx.strokePath()
    let clawPath2 = CGMutablePath()
    clawPath2.move(to: CGPoint(x: legX2 - 5 * s, y: legBaseY - 45 * s))
    clawPath2.addLine(to: CGPoint(x: legX2 - 35 * s, y: legBaseY - 75 * s))
    clawPath2.move(to: CGPoint(x: legX2 - 5 * s, y: legBaseY - 45 * s))
    clawPath2.addLine(to: CGPoint(x: legX2 + 5 * s, y: legBaseY - 80 * s))
    ctx.addPath(clawPath2)
    ctx.strokePath()

    // --- 树干 / 树枝（啄木鸟站在上面） ---
    ctx.setLineWidth(size * 0.028)
    ctx.setStrokeColor(NSColor(red: 0.45, green: 0.30, blue: 0.20, alpha: 1.0).cgColor)
    ctx.move(to: CGPoint(x: baseX - 80 * s, y: legBaseY + 30 * s))
    ctx.addLine(to: CGPoint(x: baseX + 520 * s, y: legBaseY - 40 * s))
    ctx.strokePath()

    // 树干纹理线
    ctx.setLineWidth(size * 0.01)
    ctx.setStrokeColor(NSColor(red: 0.35, green: 0.22, blue: 0.14, alpha: 0.5).cgColor)
    let branchCY = legBaseY - 5 * s
    ctx.move(to: CGPoint(x: baseX + 80 * s, y: branchCY - 15 * s))
    ctx.addLine(to: CGPoint(x: baseX + 100 * s, y: branchCY + 5 * s))
    ctx.move(to: CGPoint(x: baseX + 300 * s, y: branchCY - 25 * s))
    ctx.addLine(to: CGPoint(x: baseX + 320 * s, y: branchCY - 5 * s))
    ctx.strokePath()

    img.unlockFocus()
    return img
}

// === 生成各种尺寸的 PNG，打包成 .iconset ===
let outputDir = URL(fileURLWithPath: "/Users/liuxiaoming/CodeBuddy/20260726144648/EnglishTranslator/Resources")
let iconsetDir = outputDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(CGFloat, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, name) in sizes {
    let img = drawWoodpecker(size: size)
    guard let tiff = img.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("ERROR: failed to encode \(name)")
        continue
    }
    let url = iconsetDir.appendingPathComponent(name)
    try png.write(to: url)
    print("  \(name) (\(Int(size))x\(Int(size))) ✓")
}

// 用 iconutil 打包成 .icns
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "-o", outputDir.appendingPathComponent("AppIcon.icns").path, iconsetDir.path]
try task.run()
task.waitUntilExit()
print("✅ AppIcon.icns 已生成: \(outputDir.appendingPathComponent("AppIcon.icns").path)")
