using System;

namespace Elta.Core
{
    /// <summary>
    /// C2：翻译结果面板的几何计算。移植自 mac ResultWindowController.computeFrame：
    /// 面板铺在截图选区（划词为鼠标锚点）所在侧的**对侧半屏**；高度/纵向位置复用已保存的窗口 frame 并夹紧。
    /// 坐标约定：左上原点 + 物理像素（与 RectF 一致）。
    /// </summary>
    public static class ResultPanelGeometry
    {
        public const double MinPanelHeight = 400;

        /// <summary>avoidRect 在中线左侧 → 面板放右半屏（mac：avoidRect.midX &lt; midline）。</summary>
        public static bool PanelOnRight(RectF screenVisible, RectF avoidRect)
            => avoidRect.MidX < screenVisible.MidX;

        public static RectF Compute(RectF screenVisible, RectF avoidRect, double? savedHeight, double? savedY)
            => ComputeForSide(screenVisible, PanelOnRight(screenVisible, avoidRect), savedHeight, savedY);

        /// <summary>` 键翻面用：按显式侧别计算。</summary>
        public static RectF ComputeForSide(RectF screenVisible, bool panelOnRight, double? savedHeight, double? savedY)
        {
            double midline = screenVisible.MidX;
            double x = panelOnRight ? midline : screenVisible.MinX;
            double width = panelOnRight ? screenVisible.MaxX - midline : midline - screenVisible.MinX;

            double height = savedHeight is double sh
                ? Math.Clamp(sh, MinPanelHeight, screenVisible.Height)
                : screenVisible.Height;

            double y = savedY is double sy
                ? Math.Clamp(sy, screenVisible.MinY, screenVisible.MaxY - height)
                : screenVisible.MinY;

            return new RectF(x, y, width, height);
        }
    }
}
