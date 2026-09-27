using System.Collections.Generic;
using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    public class ScreenshotGeometryTests
    {
        private static void AssertRect(RectF expected, RectF? actual)
        {
            Assert.True(actual.HasValue, "expected a rect, got null");
            RectF a = actual!.Value;
            Assert.Equal(expected.X, a.X, 6);
            Assert.Equal(expected.Y, a.Y, 6);
            Assert.Equal(expected.Width, a.Width, 6);
            Assert.Equal(expected.Height, a.Height, 6);
        }

        // MARK: - NormalizeSelection（从两次拖拽点构造规范化矩形）

        [Fact]
        public void Normalize_DragDownRight()
            => AssertRect(new RectF(10, 20, 30, 40),
                ScreenshotGeometry.NormalizeSelection(10, 20, 40, 60));

        [Fact]
        public void Normalize_DragUpLeft()
            => AssertRect(new RectF(10, 20, 30, 40),
                ScreenshotGeometry.NormalizeSelection(40, 60, 10, 20));

        [Fact]
        public void Normalize_MixedDirection()
            => AssertRect(new RectF(10, 20, 30, 40),
                ScreenshotGeometry.NormalizeSelection(40, 20, 10, 60));

        [Fact]
        public void Normalize_ZeroDrag()
            => AssertRect(new RectF(5, 5, 0, 0),
                ScreenshotGeometry.NormalizeSelection(5, 5, 5, 5));

        // MARK: - IsSelectionUsable（mac 行为：宽高都须 > 10 才有效）

        [Fact]
        public void Usable_ExactlyMinSize_IsFalse()
            => Assert.False(ScreenshotGeometry.IsSelectionUsable(new RectF(0, 0, 10, 10)));

        [Fact]
        public void Usable_JustAboveMin_IsTrue()
            => Assert.True(ScreenshotGeometry.IsSelectionUsable(new RectF(0, 0, 10.1, 10.1)));

        [Fact]
        public void Usable_ThinHeight_IsFalse()
            => Assert.False(ScreenshotGeometry.IsSelectionUsable(new RectF(0, 0, 100, 10)));

        [Fact]
        public void Usable_ThinWidth_IsFalse()
            => Assert.False(ScreenshotGeometry.IsSelectionUsable(new RectF(0, 0, 10, 100)));

        // MARK: - MapSelectionToImage（选区坐标 → 图像像素裁剪矩形）

        [Fact]
        public void Map_Scale1_Identity()
            => AssertRect(new RectF(10, 20, 30, 40),
                ScreenshotGeometry.MapSelectionToImage(new RectF(10, 20, 30, 40),
                    surfaceWidth: 100, surfaceHeight: 100, imageWidth: 100, imageHeight: 100,
                    originBottomLeft: false));

        [Fact]
        public void Map_Scale2_ScalesCoordinates()
            => AssertRect(new RectF(20, 40, 60, 80),
                ScreenshotGeometry.MapSelectionToImage(new RectF(10, 20, 30, 40),
                    surfaceWidth: 100, surfaceHeight: 100, imageWidth: 200, imageHeight: 200,
                    originBottomLeft: false));

        [Fact]
        public void Map_BottomLeftOrigin_FlipsY()
            => AssertRect(new RectF(10, 40, 30, 40),
                ScreenshotGeometry.MapSelectionToImage(new RectF(10, 20, 30, 40),
                    surfaceWidth: 100, surfaceHeight: 100, imageWidth: 100, imageHeight: 100,
                    originBottomLeft: true));

        [Fact]
        public void Map_RoundsHalfAwayFromZero()
        {
            // x = 5 × 0.5 = 2.5 → 3（Swift round 语义；银行家舍入会得 2）
            AssertRect(new RectF(3, 3, 10, 10),
                ScreenshotGeometry.MapSelectionToImage(new RectF(5, 5, 20, 20),
                    surfaceWidth: 200, surfaceHeight: 200, imageWidth: 100, imageHeight: 100,
                    originBottomLeft: false));
        }

        [Fact]
        public void Map_ClampsToImageBounds()
            => AssertRect(new RectF(90, 90, 10, 10),
                ScreenshotGeometry.MapSelectionToImage(new RectF(90, 90, 40, 40),
                    surfaceWidth: 100, surfaceHeight: 100, imageWidth: 100, imageHeight: 100,
                    originBottomLeft: false));

        [Fact]
        public void Map_TooSmallCrop_ReturnsNull()
            => Assert.Null(ScreenshotGeometry.MapSelectionToImage(new RectF(0, 0, 4, 4),
                surfaceWidth: 100, surfaceHeight: 100, imageWidth: 100, imageHeight: 100,
                originBottomLeft: false));

        [Fact]
        public void Map_FullyOutside_ReturnsNull()
            => Assert.Null(ScreenshotGeometry.MapSelectionToImage(new RectF(200, 200, 20, 20),
                surfaceWidth: 100, surfaceHeight: 100, imageWidth: 100, imageHeight: 100,
                originBottomLeft: false));

        [Fact]
        public void Map_ZeroSurface_ReturnsNull()
            => Assert.Null(ScreenshotGeometry.MapSelectionToImage(new RectF(0, 0, 20, 20),
                surfaceWidth: 0, surfaceHeight: 0, imageWidth: 100, imageHeight: 100,
                originBottomLeft: false));

        // MARK: - IndexOfScreenContaining（选择鼠标所在屏）

        private static readonly IReadOnlyList<RectF> Screens = new[]
        {
            new RectF(0, 0, 1366, 768),      // 屏 0
            new RectF(1366, 0, 1280, 800),   // 屏 1（右接屏 0）
        };

        [Fact]
        public void Screen_PointInFirst_Returns0()
            => Assert.Equal(0, ScreenshotGeometry.IndexOfScreenContaining(100, 100, Screens));

        [Fact]
        public void Screen_PointInSecond_Returns1()
            => Assert.Equal(1, ScreenshotGeometry.IndexOfScreenContaining(1400, 100, Screens));

        [Fact]
        public void Screen_PointInNone_ReturnsMinusOne()
            => Assert.Equal(-1, ScreenshotGeometry.IndexOfScreenContaining(5000, 5000, Screens));

        [Fact]
        public void Screen_MinEdgeInclusive_MaxEdgeExclusive()
        {
            Assert.Equal(0, ScreenshotGeometry.IndexOfScreenContaining(0, 0, Screens));
            Assert.Equal(1, ScreenshotGeometry.IndexOfScreenContaining(1366, 0, Screens));
        }
    }
}
