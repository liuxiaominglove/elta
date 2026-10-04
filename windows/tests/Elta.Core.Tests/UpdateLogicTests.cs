using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    public class UpdateLogicTests
    {
        // MARK: - 响应解析（对齐 mac parseUpdateResponse）

        [Fact]
        public void Parse_ValidJson_ReturnsVersionAndUrl()
        {
            UpdateInfo? info = UpdateLogic.ParseUpdateResponse("{\"version\":\"5.6.0\",\"url\":\"https://autoelta.com/\"}");
            Assert.NotNull(info);
            Assert.Equal("5.6.0", info!.Version);
            Assert.Equal("https://autoelta.com/", info.Url);
        }

        [Fact]
        public void Parse_VPrefix_IsStripped()
        {
            UpdateInfo? info = UpdateLogic.ParseUpdateResponse("{\"version\":\"v5.6.0\",\"url\":\"https://autoelta.com/\"}");
            Assert.NotNull(info);
            Assert.Equal("5.6.0", info!.Version);
        }

        [Fact]
        public void Parse_MissingOrEmptyFields_ReturnsNull()
        {
            Assert.Null(UpdateLogic.ParseUpdateResponse("{\"url\":\"https://a.com\"}"));
            Assert.Null(UpdateLogic.ParseUpdateResponse("{\"version\":\"5.6.0\"}"));
            Assert.Null(UpdateLogic.ParseUpdateResponse("{\"version\":\"\",\"url\":\"https://a.com\"}"));
            Assert.Null(UpdateLogic.ParseUpdateResponse("{\"version\":\"v\",\"url\":\"https://a.com\"}"));
            Assert.Null(UpdateLogic.ParseUpdateResponse("{\"version\":\"5.6.0\",\"url\":\"\"}"));
        }

        [Fact]
        public void Parse_InvalidJson_ReturnsNull()
        {
            Assert.Null(UpdateLogic.ParseUpdateResponse("not json"));
            Assert.Null(UpdateLogic.ParseUpdateResponse("[]"));
            Assert.Null(UpdateLogic.ParseUpdateResponse(""));
        }

        [Fact]
        public void Parse_NonHttpSchemes_Rejected()
        {
            Assert.Null(UpdateLogic.ParseUpdateResponse("{\"version\":\"5.6.0\",\"url\":\"file:///etc/passwd\"}"));
            Assert.Null(UpdateLogic.ParseUpdateResponse("{\"version\":\"5.6.0\",\"url\":\"javascript:alert(1)\"}"));
            Assert.Null(UpdateLogic.ParseUpdateResponse("{\"version\":\"5.6.0\",\"url\":\"ftp://a.com/x\"}"));
            Assert.NotNull(UpdateLogic.ParseUpdateResponse("{\"version\":\"5.6.0\",\"url\":\"http://a.com/x\"}"));
        }

        // MARK: - 版本比较（数字段比较，对齐 mac isNewer）

        [Fact]
        public void IsNewer_RemoteHigher_True()
        {
            Assert.True(UpdateLogic.IsNewer("5.6.0", "5.5.5"));
            Assert.True(UpdateLogic.IsNewer("5.6.1", "5.6"));
        }

        [Fact]
        public void IsNewer_EqualOrLower_False()
        {
            Assert.False(UpdateLogic.IsNewer("5.5.5", "5.5.5"));
            Assert.False(UpdateLogic.IsNewer("5.5.4", "5.5.5"));
            Assert.False(UpdateLogic.IsNewer("5.6", "5.6.0"));
        }

        [Fact]
        public void IsNewer_NumericNotLexicographic()
        {
            Assert.True(UpdateLogic.IsNewer("5.10", "5.9"));
        }

        [Fact]
        public void IsNewer_NonNumericSegmentsDropped()
        {
            // 对齐 mac compactMap Int：非数字段被丢弃
            Assert.False(UpdateLogic.IsNewer("5.6.0-beta", "5.6"));
        }

        // MARK: - 是否提示（跳过版本记忆，对齐 mac shouldShowUpdate）

        [Fact]
        public void ShouldShowUpdate_NewerAndNotSkipped_True()
        {
            Assert.True(UpdateLogic.ShouldShowUpdate("5.6.0", "5.5.5", skipVersion: null));
            Assert.True(UpdateLogic.ShouldShowUpdate("5.6.0", "5.5.5", skipVersion: "5.5.9"));
        }

        [Fact]
        public void ShouldShowUpdate_SkippedExact_False()
        {
            Assert.False(UpdateLogic.ShouldShowUpdate("5.6.0", "5.5.5", skipVersion: "5.6.0"));
        }

        [Fact]
        public void ShouldShowUpdate_NotNewer_False()
        {
            Assert.False(UpdateLogic.ShouldShowUpdate("5.5.5", "5.5.5", skipVersion: null));
            Assert.False(UpdateLogic.ShouldShowUpdate("5.5.4", "5.5.5", skipVersion: "5.5.4"));
        }

        // MARK: - 更新检查 URL（平台参数 + 遥测 id）

        [Fact]
        public void BuildUpdateUrl_TelemetryOn_IncludesIdAndPlatform()
        {
            string url = UpdateLogic.BuildUpdateUrl(telemetryEnabled: true, installId: "abc-123");
            Assert.Equal(UpdateLogic.UpdateUrl + "?platform=windows&id=abc-123", url);
        }

        [Fact]
        public void BuildUpdateUrl_TelemetryOff_PlatformOnly()
        {
            Assert.Equal(UpdateLogic.UpdateUrl + "?platform=windows", UpdateLogic.BuildUpdateUrl(telemetryEnabled: false, installId: "abc-123"));
        }

        // MARK: - 平台字段（服务端按 platform 分流；缺省=旧服务器，兼容放行）

        [Fact]
        public void Parse_WithPlatformField_ReadsIt()
        {
            UpdateInfo? info = UpdateLogic.ParseUpdateResponse("{\"version\":\"1.0.1\",\"url\":\"https://autoelta.com/download/x.zip\",\"platform\":\"windows\"}");
            Assert.NotNull(info);
            Assert.Equal("windows", info!.Platform);
        }

        [Fact]
        public void Parse_WithoutPlatformField_PlatformNull()
        {
            UpdateInfo? info = UpdateLogic.ParseUpdateResponse("{\"version\":\"5.6.0\",\"url\":\"https://autoelta.com/\"}");
            Assert.NotNull(info);
            Assert.Null(info!.Platform);
        }

        [Fact]
        public void Parse_PlatformWrongType_PlatformNull()
        {
            UpdateInfo? info = UpdateLogic.ParseUpdateResponse("{\"version\":\"5.6.0\",\"url\":\"https://autoelta.com/\",\"platform\":123}");
            Assert.NotNull(info);
            Assert.Null(info!.Platform);
        }

        [Fact]
        public void IsApplicablePlatform_LegacyNull_True()
        {
            Assert.True(UpdateLogic.IsApplicablePlatform(null));
            Assert.True(UpdateLogic.IsApplicablePlatform(""));
        }

        [Fact]
        public void IsApplicablePlatform_Windows_True()
        {
            Assert.True(UpdateLogic.IsApplicablePlatform("windows"));
            Assert.True(UpdateLogic.IsApplicablePlatform("Windows"));
        }

        [Fact]
        public void IsApplicablePlatform_Macos_False()
        {
            Assert.False(UpdateLogic.IsApplicablePlatform("macos"));
        }

        // MARK: - 协议白名单（打开链接前二次校验复用）

        [Fact]
        public void IsHttpUrl_OnlyHttpAndHttps()
        {
            Assert.True(UpdateLogic.IsHttpUrl("https://a.com/x"));
            Assert.True(UpdateLogic.IsHttpUrl("HTTP://a.com/x"));
            Assert.False(UpdateLogic.IsHttpUrl("http://"));
            Assert.False(UpdateLogic.IsHttpUrl("file:///etc/passwd"));
            Assert.False(UpdateLogic.IsHttpUrl("javascript:alert(1)"));
            Assert.False(UpdateLogic.IsHttpUrl("ftp://a.com"));
            Assert.False(UpdateLogic.IsHttpUrl(null));
            Assert.False(UpdateLogic.IsHttpUrl(""));
        }
    }
}
