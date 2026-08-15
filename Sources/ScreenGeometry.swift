import Foundation

// MARK: - 屏幕坐标映射

/// 全局屏幕坐标系（左下原点，points）↔ 屏幕截图图像像素坐标系（左上原点）的纯换算。
enum ScreenGeometry {
    /// 将全局点坐标（NSEvent.mouseLocation 语义：左下原点，points）
    /// 换算为对应屏幕截图图像中的像素坐标（左上原点）。
    static func pointToImagePixel(
        globalPoint: CGPoint,
        screenFrame: CGRect,   // NSScreen.frame（全局坐标系，points）
        imageSize: CGSize      // 截图的像素尺寸
    ) -> CGPoint {
        guard screenFrame.width > 0, screenFrame.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return .zero }

        let scaleX = imageSize.width / screenFrame.width
        let scaleY = imageSize.height / screenFrame.height
        let x = (globalPoint.x - screenFrame.minX) * scaleX
        let y = (screenFrame.maxY - globalPoint.y) * scaleY
        return CGPoint(x: x, y: y)
    }
}
