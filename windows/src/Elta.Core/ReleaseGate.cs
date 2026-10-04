using System;
using System.IO;
using System.Xml;
using System.Xml.Linq;

namespace Elta.Core
{
    /// <summary>版本一致性检查结果（csproj 与 Info.plist 必须一致）。</summary>
    public sealed record VersionCheckResult(bool Ok, string? CsprojVersion, string? PlistVersion, string? Error);

    /// <summary>
    /// 发布版本闸机：Elta.Windows.csproj 的 &lt;Version&gt; 与 Resources/Info.plist 的
    /// CFBundleShortVersionString 必须一致（版本单一事实源纪律）。纯逻辑，可跨平台测试。
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

        public static string? ExtractPlistVersion(string plistXml)
        {
            XDocument? doc = ParseXml(plistXml);
            if (doc == null) return null;
            bool sawKey = false;
            foreach (XElement el in doc.Descendants())
            {
                if (!sawKey)
                {
                    if (el.Name.LocalName == "key" &&
                        string.Equals(el.Value.Trim(), "CFBundleShortVersionString", StringComparison.Ordinal))
                    {
                        sawKey = true;
                    }
                    continue;
                }

                // key 之后的第一个元素必须是 <string>，否则视为缺失
                if (el.Name.LocalName == "string")
                {
                    string v = el.Value.Trim();
                    return v.Length > 0 ? v : null;
                }
                return null;
            }
            return null;
        }

        public static VersionCheckResult Check(string csprojXml, string plistXml)
        {
            string? c = ExtractCsprojVersion(csprojXml);
            string? p = ExtractPlistVersion(plistXml);
            if (c == null) return new VersionCheckResult(false, null, p, "csproj <Version> not found");
            if (p == null) return new VersionCheckResult(false, c, null, "Info.plist CFBundleShortVersionString not found");
            if (!string.Equals(c, p, StringComparison.Ordinal))
                return new VersionCheckResult(false, c, p, $"version mismatch: csproj={c} plist={p}");
            return new VersionCheckResult(true, c, p, null);
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
