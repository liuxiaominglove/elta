import Cocoa
import Carbon

// MARK: - 选区覆盖层视图（屏幕快照背景 → 看到的始终是图书文字）

class OverlayView: NSView {
    weak var engine: ScreenshotEngine?
    var doneCallback: ((NSRect, CGImage?) -> Void)?
    var backgroundImage: NSImage?   // 全屏快照 → 显示背后的真实内容

    override var acceptsFirstResponder: Bool { true }

    private var showInstructions = true

    override func mouseDown(with e: NSEvent) {
        showInstructions = false
        needsDisplay = true
        engine?.mouseDown(convert(e.locationInWindow, from: nil))
    }
    override func mouseDragged(with e: NSEvent) {
        engine?.mouseDragged(convert(e.locationInWindow, from: nil))
    }
    override func mouseUp(with e: NSEvent) {
        engine?.mouseUp(convert(e.locationInWindow, from: nil))
    }
    override func rightMouseDown(with e: NSEvent) {
        doneCallback?(.zero, nil)
        engine?.cleanup()
    }
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { doneCallback?(.zero, nil); engine?.cleanup(); return }
        super.keyDown(with: e)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 背景：已由 layer.contents 预渲染（全屏快照），直接可见
        // 15% 黑色蒙层 → 微微变暗提示截图模式，文字完全可辨认
        NSColor.black.withAlphaComponent(0.15).setFill()
        bounds.fill()

        // 框选中 → 挖空选区 + 蓝色边框
        if let e = engine, e.isSelecting, e.selectionRect != .zero {
            let r = e.selectionRect
            NSColor.clear.set()
            r.fill(using: .sourceOut)
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: r)
            path.lineWidth = 2.0
            path.stroke()

            // 选区右上角尺寸标签
            let text = "\(Int(r.width)) × \(Int(r.height))"
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let sz = text.size(withAttributes: attr)
            let lr = NSRect(x: r.maxX - sz.width - 8, y: max(r.minY - sz.height - 6, 4),
                            width: sz.width + 12, height: sz.height + 6)
            let bp = NSBezierPath(roundedRect: lr, xRadius: 4, yRadius: 4)
            NSColor.systemBlue.withAlphaComponent(0.85).setFill()
            bp.fill()
            text.draw(at: NSPoint(x: lr.minX + 6, y: lr.minY + 3), withAttributes: attr)
        }

        // 引导提示
        guard showInstructions else { return }
        let line1 = "拖拽框选翻译区域"
        let line2 = "按 ESC 或右键取消"
        drawCenteredInstruction(text: line1, subText: line2)
    }

    private func drawCenteredInstruction(text: String, subText: String) {
        let cx = bounds.midX, cy = bounds.midY
        let ma: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: NSColor.white]
        let sa: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.7)]
        let ms = text.size(withAttributes: ma), ss = subText.size(withAttributes: sa)
        let th = ms.height + 6 + ss.height, mw = max(ms.width, ss.width)
        let bg = NSRect(x: cx - mw/2 - 24, y: cy - th/2 - 16, width: mw + 48, height: th + 32)
        NSBezierPath(roundedRect: bg, xRadius: 10, yRadius: 10).fill()
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 10, yRadius: 10).fill()

        let ca: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 28, weight: .thin), .foregroundColor: NSColor.white.withAlphaComponent(0.8)]
        let cs = "⊕".size(withAttributes: ca)
        "⊕".draw(at: NSPoint(x: cx - cs.width/2, y: bg.maxY - cs.height/2 + 28), withAttributes: ca)
        text.draw(at: NSPoint(x: cx - ms.width/2, y: bg.minY + 20 + ss.height + 6), withAttributes: ma)
        subText.draw(at: NSPoint(x: cx - ss.width/2, y: bg.minY + 18), withAttributes: sa)
    }
}
