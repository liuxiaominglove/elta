using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    public class WebView2FallbackLogicTests
    {
        [Fact]
        public void IsMissingRuntime_ByExactTypeName_True()
        {
            Assert.True(WebView2FallbackLogic.IsMissingRuntime(
                "Microsoft.Web.WebView2.Core.WebView2RuntimeNotFoundException",
                "any message"));
        }

        [Fact]
        public void IsMissingRuntime_BySimpleTypeName_True()
        {
            Assert.True(WebView2FallbackLogic.IsMissingRuntime(
                "WebView2RuntimeNotFoundException",
                null));
        }

        [Fact]
        public void IsMissingRuntime_ByMessageSignature_True()
        {
            Assert.True(WebView2FallbackLogic.IsMissingRuntime(
                "System.Runtime.InteropServices.COMException",
                "WebView2 runtime is not installed on this machine"));
        }

        [Fact]
        public void IsMissingRuntime_MessageCaseInsensitive_True()
        {
            Assert.True(WebView2FallbackLogic.IsMissingRuntime(
                "System.Exception",
                "WEBVIEW2 NOT INSTALLED"));
        }

        [Fact]
        public void IsMissingRuntime_Unrelated_ReturnsFalse()
        {
            Assert.False(WebView2FallbackLogic.IsMissingRuntime(
                "System.UnauthorizedAccessException",
                "access denied"));
            Assert.False(WebView2FallbackLogic.IsMissingRuntime(null, null));
        }

        [Fact]
        public void Describe_MissingRuntime_ActionableWithDownloadUrl()
        {
            WebView2FailureInfo info = WebView2FallbackLogic.Describe(
                "WebView2RuntimeNotFoundException", null);
            Assert.True(info.IsMissingRuntime);
            Assert.Contains(WebView2FallbackLogic.RuntimeDownloadUrl, info.UserMessage);
        }

        [Fact]
        public void Describe_Unrelated_KeepsOriginalMessage()
        {
            WebView2FailureInfo info = WebView2FallbackLogic.Describe(
                "System.InvalidOperationException", "boom");
            Assert.False(info.IsMissingRuntime);
            Assert.Contains("boom", info.UserMessage);
        }
    }
}
