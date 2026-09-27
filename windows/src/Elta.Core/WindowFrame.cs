using System;
using System.Globalization;

namespace Elta.Core
{
    /// <summary>
    /// 平台无关的窗口矩形（左上原点 + 宽高，DIP）。
    /// 序列化为 invariant 的 "x,y,w,h"，与 macOS 版 NSRect 字符串格式不兼容
    /// （Windows 为新装，无跨端迁移需求）。
    /// </summary>
    public sealed record WindowFrame(double X, double Y, double Width, double Height)
    {
        public override string ToString()
            => FormattableString.Invariant($"{X},{Y},{Width},{Height}");

        public static bool TryParse(string? text, out WindowFrame? frame)
        {
            frame = null;
            if (string.IsNullOrEmpty(text)) return false;
            string[] parts = text!.Split(',');
            if (parts.Length != 4) return false;
            if (!double.TryParse(parts[0], NumberStyles.Float, CultureInfo.InvariantCulture, out double x)) return false;
            if (!double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out double y)) return false;
            if (!double.TryParse(parts[2], NumberStyles.Float, CultureInfo.InvariantCulture, out double w)) return false;
            if (!double.TryParse(parts[3], NumberStyles.Float, CultureInfo.InvariantCulture, out double h)) return false;
            frame = new WindowFrame(x, y, w, h);
            return true;
        }
    }
}
