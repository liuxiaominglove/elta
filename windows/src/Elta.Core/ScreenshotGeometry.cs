using System;
using System.Collections.Generic;

namespace Elta.Core
{
    /// <summary>
    /// 截图选区的纯几何逻辑（平台无关），移植自 macOS 版
    /// Sources/ScreenshotEngine.swift + OverlayView.swift。
    /// 坐标约定由调用方通过 <c>originBottomLeft</c> 指定：
    /// macOS 视图原点在左下（Y 需翻转），Windows WPF 原点在左上（Y 不翻转）。
    /// </summary>
    public static class ScreenshotGeometry
    {
        /// <summary>选区最小有效边长（mac：宽高都须 &gt; 10，否则视为取消）。</summary>
        public const double MinSelectionSize = 10.0;

        /// <summary>裁剪结果最小有效边长（mac：宽高都须 &gt; 4，否则返回 nil）。</summary>
        public const double MinCropSize = 4.0;

        /// <summary>由拖拽起止两点构造规范化矩形（左上原点 + 非负宽高）。</summary>
        public static RectF NormalizeSelection(double x1, double y1, double x2, double y2)
            => new RectF(Math.Min(x1, x2), Math.Min(y1, y2), Math.Abs(x2 - x1), Math.Abs(y2 - y1));

        /// <summary>选区是否足够大（宽、高都须严格大于 minSize）。</summary>
        public static bool IsSelectionUsable(RectF selection, double minSize = MinSelectionSize)
            => selection.Width > minSize && selection.Height > minSize;

        /// <summary>
        /// 把「选区（overlay 坐标）」映射为「截图像素裁剪矩形」。
        /// 尺寸比例 = 图像像素 / overlay 坐标尺寸（mac: 点→像素；Windows: DIP→物理像素）。
        /// 结果会裁剪到图像边界内；过小或完全越界返回 null。
        /// 舍入采用「四舍五入、远离零」，与 Swift <c>round()</c> 一致。
        /// </summary>
        public static RectF? MapSelectionToImage(
            RectF selection,
            double surfaceWidth,
            double surfaceHeight,
            int imageWidth,
            int imageHeight,
            bool originBottomLeft,
            double minCrop = MinCropSize)
        {
            if (surfaceWidth <= 0 || surfaceHeight <= 0 || imageWidth <= 0 || imageHeight <= 0)
                return null;

            double scaleX = imageWidth / surfaceWidth;
            double scaleY = imageHeight / surfaceHeight;

            double rawX = selection.X * scaleX;
            double rawW = selection.Width * scaleX;
            double rawH = selection.Height * scaleY;
            double rawY = originBottomLeft
                ? imageHeight - (selection.Y + selection.Height) * scaleY
                : selection.Y * scaleY;

            double cropX = Math.Round(rawX, MidpointRounding.AwayFromZero);
            double cropY = Math.Round(rawY, MidpointRounding.AwayFromZero);
            double cropW = Math.Round(rawW, MidpointRounding.AwayFromZero);
            double cropH = Math.Round(rawH, MidpointRounding.AwayFromZero);

            if (cropW <= minCrop || cropH <= minCrop) return null;

            double intersectX = Math.Max(cropX, 0);
            double intersectY = Math.Max(cropY, 0);
            double intersectMaxX = Math.Min(cropX + cropW, imageWidth);
            double intersectMaxY = Math.Min(cropY + cropH, imageHeight);
            double finalW = intersectMaxX - intersectX;
            double finalH = intersectMaxY - intersectY;

            if (finalW <= minCrop || finalH <= minCrop) return null;

            return new RectF(intersectX, intersectY, finalW, finalH);
        }

        /// <summary>
        /// 返回包含点 (x,y) 的首个屏幕索引；无命中返回 -1。
        /// 边界语义对齐 CGRectContainsPoint：最小边含、最大边不含。
        /// </summary>
        public static int IndexOfScreenContaining(double x, double y, IReadOnlyList<RectF> screens)
        {
            ArgumentNullException.ThrowIfNull(screens);
            for (int i = 0; i < screens.Count; i++)
            {
                RectF s = screens[i];
                if (x >= s.MinX && x < s.MaxX && y >= s.MinY && y < s.MaxY) return i;
            }
            return -1;
        }
    }
}
