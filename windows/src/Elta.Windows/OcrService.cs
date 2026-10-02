using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Threading.Tasks;
using Elta.Core;
using Windows.Foundation;
using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;

namespace Elta.Windows
{
    internal enum OcrStatus
    {
        Ok,
        NoLanguagePack,
        Failed,
    }

    internal sealed class OcrOutcome
    {
        public OcrStatus Status { get; }
        public IReadOnlyList<OcrBlock> Blocks { get; }
        public string? Error { get; }

        private OcrOutcome(OcrStatus status, IReadOnlyList<OcrBlock> blocks, string? error)
        {
            Status = status;
            Blocks = blocks;
            Error = error;
        }

        public static OcrOutcome Ok(IReadOnlyList<OcrBlock> blocks) => new OcrOutcome(OcrStatus.Ok, blocks, null);
        public static OcrOutcome NoLanguagePack() => new OcrOutcome(OcrStatus.NoLanguagePack, Array.Empty<OcrBlock>(), null);
        public static OcrOutcome Failed(string error) => new OcrOutcome(OcrStatus.Failed, Array.Empty<OcrBlock>(), error);
    }

    /// <summary>
    /// B3 OCR 平台服务：把选区位图交给 Windows.Media.Ocr（WinRT），
    /// 组装为 Core 约定的行级 <see cref="OcrBlock"/>。
    ///
    /// 平台约定：OcrLine 无包围盒，行盒取该行各词 BoundingRect 的并集；
    /// 行文本直接取 OcrLine.Text（不 join(" ")，以免损坏中文）。
    /// 图像长边超 MaxImageDimension 时先等比缩小，识别后再把坐标映射回原图。
    /// </summary>
    internal static class OcrService
    {
        public static async Task<OcrOutcome> RecognizeAsync(Bitmap source)
        {
            ArgumentNullException.ThrowIfNull(source);

            OcrEngine? engine;
            try
            {
                engine = OcrEngine.TryCreateFromLanguage(new Language("en-US"))
                         ?? OcrEngine.TryCreateFromUserProfileLanguages();
            }
            catch (Exception ex)
            {
                return OcrOutcome.Failed(ex.Message);
            }

            if (engine is null) return OcrOutcome.NoLanguagePack();

            Bitmap working = source;
            bool workingIsCopy = false;
            try
            {
                double scale = OcrGeometry.FitScale(source.Width, source.Height, (int)OcrEngine.MaxImageDimension);
                if (scale < 1.0)
                {
                    working = Downscale(source, scale);
                    workingIsCopy = true;
                }

                using SoftwareBitmap softwareBitmap = await DecodeToSoftwareBitmapAsync(EncodePng(working));
                OcrResult result = await engine.RecognizeAsync(softwareBitmap);

                // 下采样后的坐标 × (1/scale) 映射回原图
                double inverse = scale > 0 ? 1.0 / scale : 1.0;
                var blocks = new List<OcrBlock>();
                foreach (OcrLine line in result.Lines)
                {
                    var wordRects = new List<RectF>(line.Words.Count);
                    foreach (OcrWord word in line.Words)
                    {
                        Rect r = word.BoundingRect;
                        wordRects.Add(OcrGeometry.ScaleRect(new RectF(r.X, r.Y, r.Width, r.Height), inverse));
                    }

                    OcrBlock? block = OcrGeometry.ToLineBlock(line.Text, wordRects);
                    if (block is not null) blocks.Add(block);
                }

                return OcrOutcome.Ok(blocks);
            }
            catch (Exception ex)
            {
                return OcrOutcome.Failed(ex.Message);
            }
            finally
            {
                if (workingIsCopy) working.Dispose();
            }
        }

        /// <summary>打开系统语言/区域设置，引导用户安装英文 OCR 语言包。</summary>
        public static void OpenLanguageSettings()
        {
            try
            {
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("ms-settings:regionlanguage")
                {
                    UseShellExecute = true,
                });
            }
            catch
            {
                // 打不开设置不致命，交由调用方提示
            }
        }

        private static Bitmap Downscale(Bitmap source, double scale)
        {
            int width = Math.Max(1, (int)Math.Round(source.Width * scale));
            int height = Math.Max(1, (int)Math.Round(source.Height * scale));
            var target = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            using Graphics g = Graphics.FromImage(target);
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.DrawImage(source, 0, 0, width, height);
            return target;
        }

        private static byte[] EncodePng(Bitmap bitmap)
        {
            using var ms = new MemoryStream();
            bitmap.Save(ms, ImageFormat.Png);
            return ms.ToArray();
        }

        private static async Task<SoftwareBitmap> DecodeToSoftwareBitmapAsync(byte[] png)
        {
            using var ras = new InMemoryRandomAccessStream();
            using (var writer = new DataWriter(ras.GetOutputStreamAt(0)))
            {
                writer.WriteBytes(png);
                await writer.StoreAsync();
                await writer.FlushAsync();
                writer.DetachStream();
            }
            ras.Seek(0);

            BitmapDecoder decoder = await BitmapDecoder.CreateAsync(ras);
            SoftwareBitmap decoded = await decoder.GetSoftwareBitmapAsync();

            SoftwareBitmap result;
            if (decoded.BitmapPixelFormat == BitmapPixelFormat.Bgra8 &&
                decoded.BitmapAlphaMode == BitmapAlphaMode.Premultiplied)
            {
                result = SoftwareBitmap.Copy(decoded);
            }
            else
            {
                result = SoftwareBitmap.Convert(decoded, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
            }
            decoded.Dispose();
            return result;
        }
    }
}
