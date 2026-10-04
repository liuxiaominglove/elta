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
            string xml = "<Project><PropertyGroup><Version>1.0.0</Version></PropertyGroup></Project>";
            Assert.Equal("1.0.0", ReleaseGate.ExtractCsprojVersion(xml));
        }

        [Fact]
        public void ExtractCsprojVersion_TrimsWhitespace()
        {
            string xml = "<Project>\n  <PropertyGroup>\n    <Version> 1.0.0 </Version>\n  </PropertyGroup>\n</Project>";
            Assert.Equal("1.0.0", ReleaseGate.ExtractCsprojVersion(xml));
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

        // MARK: - 版本闸机（每平台自有版本线：csproj <Version> == 期望版本，来自 tag）

        [Fact]
        public void Check_Match_Ok()
        {
            string csproj = "<Project><PropertyGroup><Version>1.0.0</Version></PropertyGroup></Project>";
            VersionCheckResult r = ReleaseGate.Check(csproj, "1.0.0");
            Assert.True(r.Ok);
            Assert.Equal("1.0.0", r.CsprojVersion);
            Assert.Equal("1.0.0", r.ExpectedVersion);
            Assert.Null(r.Error);
        }

        [Fact]
        public void Check_TrimsExpected()
        {
            string csproj = "<Project><PropertyGroup><Version>1.0.0</Version></PropertyGroup></Project>";
            Assert.True(ReleaseGate.Check(csproj, " 1.0.0 ").Ok);
        }

        [Fact]
        public void Check_Mismatch_NotOk_ReportsBoth()
        {
            string csproj = "<Project><PropertyGroup><Version>1.0.0</Version></PropertyGroup></Project>";
            VersionCheckResult r = ReleaseGate.Check(csproj, "1.0.1");
            Assert.False(r.Ok);
            Assert.Equal("1.0.0", r.CsprojVersion);
            Assert.Equal("1.0.1", r.ExpectedVersion);
            Assert.NotNull(r.Error);
            Assert.Contains("mismatch", r.Error);
        }

        [Fact]
        public void Check_CsprojMissing_NotOk()
        {
            string csproj = "<Project><PropertyGroup></PropertyGroup></Project>";
            VersionCheckResult r = ReleaseGate.Check(csproj, "1.0.0");
            Assert.False(r.Ok);
            Assert.Null(r.CsprojVersion);
            Assert.NotNull(r.Error);
        }

        [Fact]
        public void Check_ExpectedEmpty_NotOk()
        {
            string csproj = "<Project><PropertyGroup><Version>1.0.0</Version></PropertyGroup></Project>";
            VersionCheckResult r = ReleaseGate.Check(csproj, "");
            Assert.False(r.Ok);
            Assert.Equal("1.0.0", r.CsprojVersion);
            Assert.NotNull(r.Error);
        }

        // MARK: - 仓库实文件（CI 门禁：Windows csproj 必须有 <Version>）
        // 注意：Windows 与 macOS 是同一产品的两条独立版本线（mac=Info.plist，win=csproj），
        // 故此处**不再**校验两者相等；只校验 Windows 版本存在。

        [Fact]
        public void RepoFiles_WindowsVersionPresent()
        {
            ReleaseLayoutResult layout = ReleaseLayout.Detect(AppContext.BaseDirectory);
            if (!layout.RepoRootFound)
            {
                // 独立存档（如仅 windows/ 的验收导出包，无 Resources/Info.plist）：无可校验对象，跳过。
                Assert.True(layout.ArchiveLayout, "neither repo root nor windows archive layout found from " + AppContext.BaseDirectory);
                return;
            }

            string root = layout.RepoRoot!;
            string csproj = File.ReadAllText(Path.Combine(root, "windows", "src", "Elta.Windows", "Elta.Windows.csproj"));
            string? version = ReleaseGate.ExtractCsprojVersion(csproj);
            Assert.False(string.IsNullOrEmpty(version), "Elta.Windows.csproj 缺少 <Version>");
        }
    }
}
