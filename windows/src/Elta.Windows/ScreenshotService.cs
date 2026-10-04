using System.Drawing;
using System.Windows.Forms;
using Elta.Core;

namespace Elta.Windows
{
    /// <summary>B1 截图服务：截取整个虚拟桌面 → 用户框选 → 裁剪，返回选区位图。</summary>
    internal static class ScreenshotService
    {
        /// <summary>覆盖层是否正在显示（面板键盘路由据此让位：ESC 交给选择器，见 Program.HandlePanelKey）。</summary>
        public static bool IsSelectorOpen { get; private set; }

        /// <summary>
        /// 进入框选流程；取消或选区无效时返回 (null, Empty)。调用方负责释放返回的位图。
        /// ScreenRect = 选区在虚拟桌面上的物理像素矩形（C2 结果面板定位用）。
        /// </summary>
        public static (Bitmap? Bitmap, Rectangle ScreenRect) CaptureSelection()
        {
            // 覆盖整个虚拟桌面（所有显示器），而不是鼠标所在的那一块屏——否则从主屏
            // 触发时，副屏上框选不到（覆盖层只盖住了主屏）。
            Rectangle bounds = SystemInformation.VirtualScreen;   // 物理像素，可为负原点
            if (bounds.Width <= 0 || bounds.Height <= 0) return (null, Rectangle.Empty);

            Bitmap full = ScreenCapture.Capture(bounds);
            IsSelectorOpen = true;
            try
            {
                using var selector = new ScreenshotSelector(full, bounds);
                selector.ShowDialog();

                if (selector.Selection is not RectF selection) return (null, Rectangle.Empty);

                RectF? crop = ScreenshotGeometry.MapSelectionToImage(
                    selection,
                    surfaceWidth: selector.ClientSize.Width,
                    surfaceHeight: selector.ClientSize.Height,
                    imageWidth: full.Width,
                    imageHeight: full.Height,
                    originBottomLeft: false);

                if (crop is not RectF c) return (null, Rectangle.Empty);

                var rect = new Rectangle((int)c.X, (int)c.Y, (int)c.Width, (int)c.Height);
                if (rect.Width <= 0 || rect.Height <= 0) return (null, Rectangle.Empty);

                var screenRect = new Rectangle(bounds.X + rect.X, bounds.Y + rect.Y, rect.Width, rect.Height);
                return (full.Clone(rect, full.PixelFormat), screenRect);
            }
            finally
            {
                IsSelectorOpen = false;
                full.Dispose();
            }
        }
    }
}
