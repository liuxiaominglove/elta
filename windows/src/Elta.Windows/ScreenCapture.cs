using System.Drawing;
using System.Drawing.Imaging;

namespace Elta.Windows
{
    /// <summary>用 GDI 截取屏幕（物理像素）。调用前请确保屏幕未被本进程窗口遮挡。</summary>
    internal static class ScreenCapture
    {
        /// <summary>截取指定物理屏幕矩形，返回 32bpp 位图。</summary>
        public static Bitmap Capture(Rectangle physicalBounds)
        {
            var bitmap = new Bitmap(physicalBounds.Width, physicalBounds.Height, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bitmap))
            {
                g.CopyFromScreen(physicalBounds.Left, physicalBounds.Top, 0, 0,
                    physicalBounds.Size, CopyPixelOperation.SourceCopy);
            }
            return bitmap;
        }
    }
}
