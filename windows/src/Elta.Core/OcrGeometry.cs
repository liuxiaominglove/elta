using System;
using System.Collections.Generic;

namespace Elta.Core
{
    /// <summary>
    /// OCR 结果的纯几何与组装逻辑（平台无关）。
    ///
    /// Windows.Media.Ocr 的 <c>OcrLine</c> 只有 <c>Text</c> 与 <c>Words</c>，没有行包围盒；
    /// 而 Core 的 <see cref="TableExtractor"/> 约定输入为「行级」<see cref="OcrBlock"/>。
    /// 本类负责把词级边界框组装成行级块，并在位图下采样后把坐标映射回原图。
    /// 平台方言（WinRT 类型）留在 Elta.Windows，Core 只持机制。
    /// </summary>
    public static class OcrGeometry
    {
        /// <summary>
        /// 当图像长边超过 <paramref name="maxDimension"/>（对应 OcrEngine.MaxImageDimension）时，
        /// 返回 (0,1] 的等比缩放因子；否则返回 1.0。非法输入一律返回 1.0（不缩放）。
        /// </summary>
        public static double FitScale(int pixelWidth, int pixelHeight, int maxDimension)
        {
            if (pixelWidth <= 0 || pixelHeight <= 0 || maxDimension <= 0) return 1.0;
            int longest = Math.Max(pixelWidth, pixelHeight);
            if (longest <= maxDimension) return 1.0;
            return (double)maxDimension / longest;
        }

        /// <summary>按比例缩放矩形各分量。下采样后回映射应传 <c>1/scale</c>。</summary>
        public static RectF ScaleRect(RectF rect, double scale)
            => new RectF(rect.X * scale, rect.Y * scale, rect.Width * scale, rect.Height * scale);

        /// <summary>多个矩形的并集（外接矩形）；空集合返回 null。</summary>
        public static RectF? UnionAll(IReadOnlyList<RectF> rects)
        {
            ArgumentNullException.ThrowIfNull(rects);
            if (rects.Count == 0) return null;

            double minX = rects[0].MinX;
            double minY = rects[0].MinY;
            double maxX = rects[0].MaxX;
            double maxY = rects[0].MaxY;
            for (int i = 1; i < rects.Count; i++)
            {
                RectF r = rects[i];
                if (r.MinX < minX) minX = r.MinX;
                if (r.MinY < minY) minY = r.MinY;
                if (r.MaxX > maxX) maxX = r.MaxX;
                if (r.MaxY > maxY) maxY = r.MaxY;
            }
            return new RectF(minX, minY, maxX - minX, maxY - minY);
        }

        /// <summary>
        /// 由「行文本 + 该行各词框」构造行级块。
        /// 文本原样透传（不 join(" ")，以免损坏中文）；包围盒取词框并集。
        /// 词框为空返回 null（该行无有效几何，调用方应跳过）。
        /// </summary>
        public static OcrBlock? ToLineBlock(string lineText, IReadOnlyList<RectF> wordRects)
        {
            ArgumentNullException.ThrowIfNull(lineText);
            ArgumentNullException.ThrowIfNull(wordRects);
            RectF? box = UnionAll(wordRects);
            if (box is not RectF b) return null;
            return new OcrBlock(lineText, b);
        }
    }
}
