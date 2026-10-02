using System;
using System.Collections.Generic;
using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    /// <summary>B3 OCR 几何纯逻辑：下采样回映射 + 词框并集 → 行级 OcrBlock。</summary>
    public class OcrGeometryTests
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

        // MARK: - FitScale（超 MaxImageDimension 时返回 (0,1] 缩放因子）

        [Fact]
        public void FitScale_WithinLimit_ReturnsOne()
            => Assert.Equal(1.0, OcrGeometry.FitScale(100, 50, 10000), 6);

        [Fact]
        public void FitScale_ExactlyAtLimit_ReturnsOne()
            => Assert.Equal(1.0, OcrGeometry.FitScale(10000, 5000, 10000), 6);

        [Fact]
        public void FitScale_TooWide_ScalesByWidth()
            => Assert.Equal(0.5, OcrGeometry.FitScale(20000, 5000, 10000), 6);

        [Fact]
        public void FitScale_TooTall_ScalesByHeight()
            => Assert.Equal(0.5, OcrGeometry.FitScale(5000, 20000, 10000), 6);

        [Fact]
        public void FitScale_Square_PicksLongestEdge()
            => Assert.Equal(10000.0 / 30000.0, OcrGeometry.FitScale(30000, 10000, 10000), 6);

        [Fact]
        public void FitScale_NonPositiveMax_ReturnsOne()
            => Assert.Equal(1.0, OcrGeometry.FitScale(20000, 5000, 0), 6);

        [Fact]
        public void FitScale_ZeroDimensions_ReturnsOne()
            => Assert.Equal(1.0, OcrGeometry.FitScale(0, 0, 10000), 6);

        // MARK: - ScaleRect（坐标缩放）

        [Fact]
        public void ScaleRect_ScaleOne_Identity()
            => AssertRect(new RectF(10, 20, 30, 40), OcrGeometry.ScaleRect(new RectF(10, 20, 30, 40), 1.0));

        [Fact]
        public void ScaleRect_ScaleTwo_DoublesAllComponents()
            => AssertRect(new RectF(20, 40, 60, 80), OcrGeometry.ScaleRect(new RectF(10, 20, 30, 40), 2.0));

        [Fact]
        public void ScaleRect_ScaleHalf_HalvesAllComponents()
            => AssertRect(new RectF(5, 10, 15, 20), OcrGeometry.ScaleRect(new RectF(10, 20, 30, 40), 0.5));

        [Fact]
        public void ScaleRect_InverseRoundTrip_RestoresOriginal()
        {
            var original = new RectF(123, 45, 67, 89);
            RectF down = OcrGeometry.ScaleRect(original, 0.5);
            AssertRect(original, OcrGeometry.ScaleRect(down, 2.0));
        }

        // MARK: - UnionAll（多矩形并集）

        [Fact]
        public void UnionAll_Single_Identity()
            => AssertRect(new RectF(10, 20, 30, 40), OcrGeometry.UnionAll(new[] { new RectF(10, 20, 30, 40) }));

        [Fact]
        public void UnionAll_TwoDisjoint_ReturnsBoundingBox()
            => AssertRect(new RectF(10, 20, 100, 40),
                OcrGeometry.UnionAll(new[] { new RectF(10, 20, 30, 40), new RectF(80, 30, 30, 30) }));

        [Fact]
        public void UnionAll_HandlesNegativeCoordinates()
            => AssertRect(new RectF(-50, -10, 100, 40),
                OcrGeometry.UnionAll(new[] { new RectF(-50, -10, 20, 40), new RectF(30, 5, 20, 10) }));

        [Fact]
        public void UnionAll_Empty_ReturnsNull()
            => Assert.Null(OcrGeometry.UnionAll(new RectF[0]));

        [Fact]
        public void UnionAll_Null_Throws()
            => Assert.Throws<ArgumentNullException>(() => OcrGeometry.UnionAll(null!));

        // MARK: - ToLineBlock（行文本 + 词框 → 行级 OcrBlock）

        [Fact]
        public void ToLineBlock_UsesTextVerbatim_AndUnionOfWordRects()
        {
            OcrBlock? block = OcrGeometry.ToLineBlock("Hello world",
                new[] { new RectF(10, 20, 30, 14), new RectF(45, 20, 35, 14) });
            Assert.NotNull(block);
            Assert.Equal("Hello world", block!.Text);
            AssertRect(new RectF(10, 20, 70, 14), block.BoundingBox);
        }

        [Fact]
        public void ToLineBlock_CjkText_HasNoInsertedSpaces()
        {
            // 回归点：WinRT 词级框若被 join(" ") 重建，会损坏中文；行文本必须原样透传。
            OcrBlock? block = OcrGeometry.ToLineBlock("精读助手",
                new[] { new RectF(0, 0, 20, 14), new RectF(20, 0, 20, 14) });
            Assert.NotNull(block);
            Assert.Equal("精读助手", block!.Text);
            Assert.DoesNotContain(" ", block.Text);
        }

        [Fact]
        public void ToLineBlock_EmptyWordRects_ReturnsNull()
            => Assert.Null(OcrGeometry.ToLineBlock("orphan", new RectF[0]));

        [Fact]
        public void ToLineBlock_NullWordRects_Throws()
            => Assert.Throws<ArgumentNullException>(() => OcrGeometry.ToLineBlock("x", null!));
    }
}
