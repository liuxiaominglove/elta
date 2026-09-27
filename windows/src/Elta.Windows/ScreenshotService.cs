using System.Drawing;
using System.Windows.Forms;
using Elta.Core;

namespace Elta.Windows
{
    /// <summary>B1 截图服务：截鼠标所在屏 → 用户框选 → 裁剪，返回选区位图。</summary>
    internal static class ScreenshotService
    {
        /// <summary>进入框选流程；取消或选区无效时返回 null。调用方负责释放返回的位图。</summary>
        public static Bitmap? CaptureSelection()
        {
            Screen? screen = Screen.FromPoint(Cursor.Position);
            if (screen == null) screen = Screen.PrimaryScreen;
            if (screen == null) return null;

            Rectangle bounds = screen.Bounds;         // 物理像素
            Bitmap full = ScreenCapture.Capture(bounds);
            try
            {
                using var selector = new ScreenshotSelector(full, bounds);
                selector.ShowDialog();

                if (selector.Selection is not RectF selection) return null;

                RectF? crop = ScreenshotGeometry.MapSelectionToImage(
                    selection,
                    surfaceWidth: selector.ClientSize.Width,
                    surfaceHeight: selector.ClientSize.Height,
                    imageWidth: full.Width,
                    imageHeight: full.Height,
                    originBottomLeft: false);

                if (crop is not RectF c) return null;

                var rect = new Rectangle((int)c.X, (int)c.Y, (int)c.Width, (int)c.Height);
                if (rect.Width <= 0 || rect.Height <= 0) return null;

                return full.Clone(rect, full.PixelFormat);
            }
            finally
            {
                full.Dispose();
            }
        }
    }
}
