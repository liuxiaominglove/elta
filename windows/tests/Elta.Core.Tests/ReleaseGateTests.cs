using System;
using System.IO;
using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    public class ReleaseGateTests
    {
        // MARK: - csproj 提取

        [Fact]
        public void ExtractCsprojVersion_Basic()
        {
            string xml = "<Project><PropertyGroup><Version>5.5.5</Version></PropertyGroup></Project>";
            Assert.Equal("5.5.5", ReleaseGate.ExtractCsprojVersion(xml));
        }

        [Fact]
        public void ExtractCsprojVersion_TrimsWhitespace()
        {
            string xml = "<Project>\n  <PropertyGroup>\n    <Version> 5.5.5 </Version>\n  </PropertyGroup>\n</Project>";
            Assert.Equal("5.5.5", ReleaseGate.ExtractCsprojVersion(xml));
        }

        [Fact]
        public void ExtractCsprojVersion_Missing_ReturnsNull()
        {
            Assert.Null(ReleaseGate.ExtractCsprojVersion("<Project><PropertyGroup></PropertyGroup></Project>"));
        }

        [Fact]
        public void ExtractCsprojVersion_InvalidXml_ReturnsNull()
        {
            Assert.Null(ReleaseGate.ExtractCsprojVersion("not xml at all"));
        }

        // MARK: - plist 提取

        [Fact]
        public void ExtractPlistVersion_Basic()
        {
            string xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleShortVersionString</key><string>5.5.5</string></dict></plist>";
            Assert.Equal("5.5.5", ReleaseGate.ExtractPlistVersion(xml));
        }

        [Fact]
        public void ExtractPlistVersion_WithDoctypeAndOthers_ReturnsValue()
        {
            string xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                         "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n" +
                         "<plist version=\"1.0\"><dict>" +
                         "<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>" +
                         "<key>CFBundleShortVersionString</key><string>5.5.5</string>" +
                         "</dict></plist>";
            Assert.Equal("5.5.5", ReleaseGate.ExtractPlistVersion(xml));
        }

        [Fact]
        public void ExtractPlistVersion_MissingKey_ReturnsNull()
        {
            string xml = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>Other</key><string>1.0</string></dict></plist>";
            Assert.Null(ReleaseGate.ExtractPlistVersion(xml));
        }

        // MARK: - 一致性判定

        [Fact]
        public void Check_Match_Ok()
        {
            string csproj = "<Project><PropertyGroup><Version>5.5.5</Version></PropertyGroup></Project>";
            string plist = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleShortVersionString</key><string>5.5.5</string></dict></plist>";
            VersionCheckResult r = ReleaseGate.Check(csproj, plist);
            Assert.True(r.Ok);
            Assert.Equal("5.5.5", r.CsprojVersion);
            Assert.Equal("5.5.5", r.PlistVersion);
            Assert.Null(r.Error);
        }

        [Fact]
        public void Check_Mismatch_NotOk_ReportsBoth()
        {
            string csproj = "<Project><PropertyGroup><Version>5.5.4</Version></PropertyGroup></Project>";
            string plist = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleShortVersionString</key><string>5.5.5</string></dict></plist>";
            VersionCheckResult r = ReleaseGate.Check(csproj, plist);
            Assert.False(r.Ok);
            Assert.Equal("5.5.4", r.CsprojVersion);
            Assert.Equal("5.5.5", r.PlistVersion);
            Assert.NotNull(r.Error);
            Assert.Contains("mismatch", r.Error);
        }

        [Fact]
        public void Check_CsprojMissing_NotOk()
        {
            string csproj = "<Project><PropertyGroup></PropertyGroup></Project>";
            string plist = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleShortVersionString</key><string>5.5.5</string></dict></plist>";
            VersionCheckResult r = ReleaseGate.Check(csproj, plist);
            Assert.False(r.Ok);
            Assert.Null(r.CsprojVersion);
            Assert.NotNull(r.Error);
        }

        [Fact]
        public void Check_PlistMissing_NotOk()
        {
            string csproj = "<Project><PropertyGroup><Version>5.5.5</Version></PropertyGroup></Project>";
            string plist = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict></dict></plist>";
            VersionCheckResult r = ReleaseGate.Check(csproj, plist);
            Assert.False(r.Ok);
            Assert.Null(r.PlistVersion);
            Assert.NotNull(r.Error);
        }

        // MARK: - 仓库实文件一致性（CI 门禁：每次 push 跑 Core 测试即校验）

        [Fact]
        public void RepoFiles_VersionsConsistent()
        {
            ReleaseLayoutResult layout = ReleaseLayout.Detect(AppContext.BaseDirectory);
            if (!layout.RepoRootFound)
            {
                // 独立存档（如仅 windows/ 的验收导出包，无 Resources/Info.plist）：无可校验对象，跳过。
                // 背景：2026-10-04 验收包唯一红灯即此场景（回传-验收-6080e55 ①，采纳建议 b）。
                Assert.True(layout.ArchiveLayout, "neither repo root nor windows archive layout found from " + AppContext.BaseDirectory);
                return;
            }

            string root = layout.RepoRoot!;
            string csproj = File.ReadAllText(Path.Combine(root, "windows", "src", "Elta.Windows", "Elta.Windows.csproj"));
            string plist = File.ReadAllText(Path.Combine(root, "Resources", "Info.plist"));
            VersionCheckResult r = ReleaseGate.Check(csproj, plist);
            Assert.True(r.Ok, r.Error ?? "version check failed");
        }
    }
}
