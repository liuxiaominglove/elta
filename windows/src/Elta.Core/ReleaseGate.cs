using System;
using System.IO;
using System.Xml;
using System.Xml.Linq;

namespace Elta.Core
{
    /// <summary>版本一致性检查结果（csproj 版本 与 期望版本 必须一致）。</summary>
    public sealed record VersionCheckResult(bool Ok, string? CsprojVersion, string? ExpectedVersion, string? Error);

    /// <summary>
    /// 发布版本闸机（每平台自有版本线）：<c>Elta.Windows.csproj</c> 的 &lt;Version&gt; 必须等于
    /// **期望版本**（来自发布 tag，如 <c>win-v1.0.0</c> → <c>1.0.0</c>）。
    /// 不再与 macOS 的 <c>Resources/Info.plist</c> 比对——Windows 与 macOS 是同一产品的两条
    /// **独立版本线**（mac 冻结在 5.5.5，Windows 从 1.0.0 起迭代）。纯逻辑，可跨平台测试。
    /// </summary>
    public static class ReleaseGate
    {
        public static string? ExtractCsprojVersion(string csprojXml)
        {
            XDocument? doc = ParseXml(csprojXml);
            if (doc == null) return null;
            foreach (XElement el in doc.Descendants())
            {
                if (el.Name.LocalName == "Version")
                {
                    string v = el.Value.Trim();
                    if (v.Length > 0) return v;
                }
            }
            return null;
        }

        /// <summary>校验 csproj &lt;Version&gt; 是否等于期望版本（如来自 tag）。</summary>
        public static VersionCheckResult Check(string csprojXml, string expectedVersion)
        {
            string? c = ExtractCsprojVersion(csprojXml);
            string? expected = expectedVersion?.Trim();
            if (c == null) return new VersionCheckResult(false, null, expected, "csproj <Version> not found");
            if (string.IsNullOrEmpty(expected))
                return new VersionCheckResult(false, c, null, "expected version empty");
            if (!string.Equals(c, expected, StringComparison.Ordinal))
                return new VersionCheckResult(false, c, expected, $"version mismatch: csproj={c} expected={expected}");
            return new VersionCheckResult(true, c, expected, null);
        }

        private static XDocument? ParseXml(string xml)
        {
            try
            {
                var settings = new XmlReaderSettings
                {
                    DtdProcessing = DtdProcessing.Ignore,
                    XmlResolver = null,
                };
                using var sr = new StringReader(xml);
                using var reader = XmlReader.Create(sr, settings);
                return XDocument.Load(reader);
            }
            catch
            {
                return null;
            }
        }
    }
}
