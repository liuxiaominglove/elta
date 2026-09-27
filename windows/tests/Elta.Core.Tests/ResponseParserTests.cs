using System;
using System.Text;
using Xunit;

namespace Elta.Core.Tests
{
    public class ResponseParserTests
    {
        private static byte[] Utf8(string s) => Encoding.UTF8.GetBytes(s);

        [Fact]
        public void ValidResponse_ReturnsContent()
            => Assert.Equal("你好",
                ResponseParser.Parse(Utf8("{\"choices\":[{\"message\":{\"content\":\"你好\"}}]}")));

        [Fact]
        public void EmptyChoices_ReturnsNull()
            => Assert.Null(ResponseParser.Parse(Utf8("{\"choices\":[]}")));

        [Fact]
        public void InvalidJson_ReturnsNull()
            => Assert.Null(ResponseParser.Parse(Utf8("not json")));

        [Fact]
        public void MissingMessage_ReturnsNull()
            => Assert.Null(ResponseParser.Parse(Utf8("{\"choices\":[{\"x\":1}]}")));

        [Fact]
        public void ContentNotString_ReturnsNull()
            => Assert.Null(ResponseParser.Parse(Utf8("{\"choices\":[{\"message\":{\"content\":123}}]}")));

        [Fact]
        public void EmptyBytes_ReturnsNull()
            => Assert.Null(ResponseParser.Parse(Array.Empty<byte>()));

        [Fact]
        public void Null_Throws()
            => Assert.Throws<ArgumentNullException>(() => ResponseParser.Parse(null!));
    }
}
