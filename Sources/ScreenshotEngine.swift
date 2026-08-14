import Cocoa
import Carbon

// MARK: - 截图引擎（屏幕快照背景方案，全屏 Space 可靠）

final class ScreenshotEngine: NSObject {
    static let shared = ScreenshotEngine()

    private var panel: NSPanel?
    private var overlayView: OverlayView?
    private var startPoint: NSPoint = .zero
    var isSelecting = false
    var selectionRect: NSRect = .zero
    private var isActive = false
    private var safetyTimer: DispatchWorkItem?
    private var screenSnapshot: NSImage?
    private var fullScreenCGImage: CGImage?  // 首次截图时的原始 CGImage，用于裁切选区（避免拍到遮罩层）
    private var capturedScreen: NSScreen?     // 启动时截图的屏幕（避免跨屏裁剪错位）

    func start(done: @escaping (NSRect, CGImage?) -> Void) {
        guard !isActive else {
            logi("截图引擎已在运行中，忽略重复请求")
            done(.zero, nil)
            return
        }

        let pos = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pos) }) ?? NSScreen.main else {
            done(.zero, nil); return
        }

        // 1) 先截取当前屏幕画面（100% 精确的"后面有什么"）
        //    这样即使在最严格的全屏 Space 中，也能让用户看到图书文字
        //    同时保存 CGImage 和 NSImage：CGImage 用于最终裁切（避免拍到遮罩层），NSImage 用于 overlay 背景显示
        guard let (bg, rawCG) = captureFullScreen(screen: screen) else {
            logi("全屏截图失败")
            done(.zero, nil); return
        }
        screenSnapshot = bg
        fullScreenCGImage = rawCG
        capturedScreen = screen

        // 2) 推入全局十字光标
        NSCursor.crosshair.push()
        logi("截图引擎启动：屏幕={\(Int(screen.frame.width))x\(Int(screen.frame.height))}")

        isActive = true

        // 3) 创建半透明遮罩面板（NSPanel 是 macOS 截图工具的经典选择）
        let p = NSPanel(contentRect: screen.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .screenSaver                    // 足够高，全屏可见
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.engine = self
        view.doneCallback = done
        view.backgroundImage = bg
        // 预渲染背景到 layer → 窗口出现瞬间就能看到背景文字
        view.wantsLayer = true
        if let cg = bg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            view.layer?.contents = cg
            view.layer?.contentsGravity = .resizeAspectFill
        }
        p.contentView = view

        self.panel = p
        self.overlayView = view

        p.orderFrontRegardless()
        p.makeKey()
        p.makeFirstResponder(view)

        // 安全超时 60 秒
        let timer = DispatchWorkItem { [weak self] in
            guard let self = self, self.isActive else { return }
            logi("安全超时：自动关闭遮罩")
            self.finish(rect: .zero, image: nil)
        }
        safetyTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timer)
    }

    // MARK: - 结束 & 清理

    private func finish(rect: NSRect, image: CGImage?) {
        overlayView?.doneCallback?(rect, image)
        cleanup()
    }

    func cleanup() {
        safetyTimer?.cancel()
        safetyTimer = nil
        isActive = false
        screenSnapshot = nil
        fullScreenCGImage = nil
        capturedScreen = nil
        NSCursor.crosshair.pop()
        NSCursor.arrow.push(); NSCursor.arrow.pop()
        panel?.orderOut(nil)
        panel = nil
        overlayView = nil
        isSelecting = false
        selectionRect = .zero
    }

    // MARK: - 鼠标事件

    func mouseDown(_ point: NSPoint) {
        startPoint = point
        isSelecting = true
        selectionRect = .zero
        overlayView?.needsDisplay = true
    }

    func mouseDragged(_ point: NSPoint) {
        guard isSelecting else { return }
        selectionRect = NSRect(
            x: min(startPoint.x, point.x),
            y: min(startPoint.y, point.y),
            width: abs(point.x - startPoint.x),
            height: abs(point.y - startPoint.y)
        )
        overlayView?.needsDisplay = true
    }

    func mouseUp(_ point: NSPoint) {
        guard isSelecting else { return }
        isSelecting = false
        let rect = NSRect(
            x: min(startPoint.x, point.x),
            y: min(startPoint.y, point.y),
            width: abs(point.x - startPoint.x),
            height: abs(point.y - startPoint.y)
        )
        selectionRect = rect

        guard rect.width > 10, rect.height > 10 else {
            finish(rect: .zero, image: nil)
            return
        }

        // 实时截图选中区域（返回原始 CGImage，不做 NSImage 包装）
        let cg = captureRectCG(rect: rect)
        finish(rect: rect, image: cg)
    }

    // MARK: - 截图

    /// 将 raw screen-capture CGImage 转换为 Vision OCR 友好的标准 sRGB 无 Alpha 格式
    private func makeVisionFriendly(_ cg: CGImage) -> CGImage? {
        let ai = cg.alphaInfo
        if ai == .none || ai == .noneSkipFirst || ai == .noneSkipLast,
           cg.colorSpace?.model == .rgb { return cg }
        guard let ctx = CGContext(data: nil, width: cg.width, height: cg.height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return cg }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx.makeImage() ?? cg
    }

    /// 返回框选区域的高清 CGImage。使用初始全屏截图裁切（而非重新截图），
    /// 避免拍到我们自己的遮罩面板。
    private func captureRectCG(rect: NSRect) -> CGImage? {
        guard let full = fullScreenCGImage else {
            loge("缺少全屏 CGImage 缓存，回退实时截图")
            let pos = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pos) }) ?? NSScreen.main else { return nil }
            guard let fallback = captureDisplayImage(screen: screen) else { return nil }
            return cropFromFull(fallback, screen: screen, rect: rect)
        }

        guard let screen = capturedScreen ?? NSScreen.main else { return nil }
        return cropFromFull(full, screen: screen, rect: rect)
    }

    private func cropFromFull(_ full: CGImage, screen: NSScreen, rect: NSRect) -> CGImage? {
        let pw = CGFloat(full.width)
        let ph = CGFloat(full.height)
        let sf = screen.frame  // 点坐标

        let scaleX = pw / sf.width
        let scaleY = ph / sf.height
        logi("截图 scale: x=\(String(format: "%.3f", scaleX)) y=\(String(format: "%.3f", scaleY)), full=\(Int(pw))x\(Int(ph)) px, frame=\(sf)")

        // 3. 把 overlay view 点坐标 → 全屏 CGImage 像素坐标（CGImage 原点左上，y 向下）
        let cropX = round(rect.origin.x * scaleX)
        let cropY = round(ph - (rect.origin.y + rect.height) * scaleY)
        let cropW = round(rect.width  * scaleX)
        let cropH = round(rect.height * scaleY)

        guard cropW > 4, cropH > 4 else { loge("选区截图区域过小: \(cropW)x\(cropH)"); return nil }
        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH).intersection(CGRect(x: 0, y: 0, width: pw, height: ph))
        guard cropRect.width > 4, cropRect.height > 4 else { loge("裁剪后区域过小"); return nil }

        guard let cropped = full.cropping(to: cropRect) else { loge("CGImage 裁剪失败"); return nil }
        logi("截图 CGImage: \(cropped.width)x\(cropped.height) px (裁剪自 \(Int(pw))x\(Int(ph)))")
        return makeVisionFriendly(cropped)
    }

    /// 使用 CGWindowListCreateImage 截取屏幕内容，正确反映窗口叠放顺序
    private func captureDisplayImage(screen: NSScreen) -> CGImage? {
        let bounds = screen.frame  // 全局坐标系（左下角原点）
        return CGWindowListCreateImage(bounds,
                                       .optionOnScreenOnly,
                                       kCGNullWindowID,
                                       .bestResolution)
    }

    private func captureFullScreen(screen: NSScreen) -> (NSImage, CGImage?)? {
        guard let full = captureDisplayImage(screen: screen) else {
            loge("全屏截图失败 (CGWindowListCreateImage)")
            return nil
        }
        let sf = screen.frame
        let img = NSImage(size: sf.size)  // NSImage 用点坐标
        img.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.draw(full, in: CGRect(x: 0, y: 0, width: sf.width, height: sf.height))
        }
        img.unlockFocus()
        return (img, full)  // 返回 NSImage（显示用）+ CGImage（裁切用）
    }
}
