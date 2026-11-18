using WorldCapture.Core.Imaging;

namespace WorldCapture.Core.Tests;

/// <summary>逐条移植自 macos/Tests/CaptureKitTests/ScrollStitcherTests.swift（测试名保持对应）。</summary>
public class ScrollStitcherTests
{
    // —— 测试辅助 ——

    private static GrayImage MakeGray(int width, int height)
    {
        var pixels = new byte[width * height];
        for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
            pixels[y * width + x] = (byte)((y * 37 + x * 5) % 256);
        return new GrayImage(width, height, pixels);
    }

    private static GrayImage Slice(GrayImage image, int from, int rows)
    {
        var pixels = new byte[image.Width * rows];
        Array.Copy(image.Pixels, from * image.Width, pixels, 0, pixels.Length);
        return new GrayImage(image.Width, rows, pixels);
    }

    /// <summary>每行一个灰度值的不透明图。</summary>
    private static RgbaImage RowImage(int width, int height, Func<int, int> grayOfRow)
    {
        var image = new RgbaImage(width, height);
        for (var y = 0; y < height; y++)
        {
            var v = (byte)grayOfRow(y);
            image.Fill(0, y, width, 1, v, v, v);
        }
        return image;
    }

    /// <summary>行 0 = 顶部、第 i 行灰度 = ((fromRow+i)*37) mod 256 的窗口图。</summary>
    private static RgbaImage MakeWindowImage(int width, int fromRow, int rows, bool inverted = false) =>
        RowImage(width, rows, i =>
        {
            var v = (fromRow + i) * 37 % 256;
            return inverted ? 255 - v : v;
        });

    private static RgbaImage MakeSourceImage(int width, int height, bool inverted = false) =>
        MakeWindowImage(width, 0, height, inverted);

    private static ScrollStitcher.Options Step1(int band = 160) => new() { Band = band, ColumnStep = 1 };

    // —— 方向约定 ——

    [Fact]
    public void GrayImageRowZeroIsTopScanline()
    {
        // 行 0,1,2,3 的源值分别为 0、37、74、111。
        var gray = GrayImage.From(MakeWindowImage(2, 0, 4));
        Assert.Equal(0, gray.Pixels[0]);
        Assert.Equal(111, gray.Pixels[3 * 2]);
    }

    // —— 纵向对齐 ——

    [Fact]
    public void FindsKnownVerticalShift()
    {
        var source = MakeGray(20, 130);
        var a = Slice(source, 0, 100);
        var b = Slice(source, 15, 100);

        var alignment = ScrollStitcher.BestVerticalShift(a, b, columnStep: 1);
        Assert.NotNull(alignment);
        Assert.Equal(15, alignment.Value.Shift);
        Assert.True(alignment.Value.Score < 0.001);
    }

    [Fact]
    public void IdenticalFramesYieldZeroShift()
    {
        var image = MakeGray(16, 60);
        var alignment = ScrollStitcher.BestVerticalShift(image, image, columnStep: 1);
        Assert.Equal(new VerticalAlignment(0, 0), alignment);
    }

    [Fact]
    public void RejectsMismatchedWidths()
    {
        Assert.Null(ScrollStitcher.BestVerticalShift(MakeGray(16, 40), MakeGray(20, 40)));
    }

    /// <summary>左右为<b>固定纹理</b>侧栏（仅随行变化、两帧相同），中间列为随 contentFromRow 滚动的内容。</summary>
    private static GrayImage SidebarGray(int width, int height, int centerX0, int centerX1, int contentFromRow)
    {
        var pixels = new byte[width * height];
        for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
            pixels[y * width + x] = (byte)(x >= centerX0 && x < centerX1
                ? (contentFromRow + y) * 37 % 256   // 中间滚动内容
                : y * 23 % 256);                    // 固定纹理侧栏
        return new GrayImage(width, height, pixels);
    }

    [Fact]
    public void SideInsetIgnoresFixedSidebars()
    {
        const int w = 90, h = 130, c0 = 30, c1 = 60;
        var a = SidebarGray(w, h, c0, c1, 0);
        var b = SidebarGray(w, h, c0, c1, 15);  // 中列下移 15

        // 不排除侧栏：固定纹理侧栏（占 2/3 宽）在 d=0 完美对齐，污染整宽相关性，得不到干净的真实位移。
        var biased = ScrollStitcher.BestVerticalShift(a, b, columnStep: 1);
        Assert.NotNull(biased);
        Assert.False(biased.Value.Shift == 15 && biased.Value.Score < 0.001);

        // 排除左右各 30 列（只留中间滚动列）：得到正确位移 15、近零分数。
        var correct = ScrollStitcher.BestVerticalShift(a, b, columnStep: 1, sideInset: 30);
        Assert.NotNull(correct);
        Assert.Equal(15, correct.Value.Shift);
        Assert.True(correct.Value.Score < 0.001);
    }

    // —— 拼接 ——

    [Fact]
    public void StitchesOverlappingFramesIntoTallImage()
    {
        const int width = 16, sourceHeight = 120, frameHeight = 80, delta = 20;
        var source = MakeSourceImage(width, sourceHeight);

        var stitcher = new ScrollStitcher(Step1());
        var results = new List<ScrollStitcher.AppendResult>();
        for (var offset = 0; offset <= sourceHeight - frameHeight; offset += delta)
            results.Add(stitcher.Append(MakeWindowImage(width, offset, frameHeight)));

        Assert.Equal(ScrollStitcher.AppendResult.First, results[0]);
        Assert.All(results.Skip(1), r => Assert.Equal(ScrollStitcher.AppendResult.Appended(delta), r));
        Assert.Equal(3, stitcher.FrameCount);
        Assert.Equal(sourceHeight, stitcher.StitchedHeight);

        var stitched = stitcher.MakeImage();
        Assert.NotNull(stitched);
        Assert.Equal(width, stitched.Width);
        Assert.Equal(sourceHeight, stitched.Height);
        // macOS 版经 CoreGraphics 重绘，只能要求误差 ≤ 3；这里是逐字节拷贝，应当与原图完全相同。
        Assert.Equal(source.Pixels, stitched.Pixels);
    }

    [Fact]
    public void DetectsDuplicateWhenNotScrolled()
    {
        var source = MakeSourceImage(16, 60);
        var stitcher = new ScrollStitcher(Step1());

        Assert.Equal(ScrollStitcher.AppendResult.First, stitcher.Append(source));
        Assert.Equal(ScrollStitcher.AppendResult.Duplicate, stitcher.Append(source));
        Assert.Equal(1, stitcher.FrameCount);
        Assert.Equal(60, stitcher.StitchedHeight);
    }

    [Fact]
    public void StitchesPastStickyHeader()
    {
        // 模拟吸顶页眉：前 24 行无论怎么滚动都固定不变，其余内容随滚动上移。
        // 若从第 0 行比对，静止页眉会把对齐拉到 shift 0（误判「未滚动」）；跳过顶部后应正确求出滚动量并持续拼接。
        const int width = 16, height = 200, headerRows = 24, delta = 30;
        RgbaImage Frame(int position) =>
            RowImage(width, height, y => y < headerRows ? 200 : (position + y) * 37 % 256);

        var stitcher = new ScrollStitcher(Step1(band: 80));
        Assert.Equal(ScrollStitcher.AppendResult.First, stitcher.Append(Frame(0)));
        Assert.Equal(ScrollStitcher.AppendResult.Appended(delta), stitcher.Append(Frame(delta)));
        Assert.Equal(ScrollStitcher.AppendResult.Appended(delta), stitcher.Append(Frame(2 * delta)));
        Assert.Equal(3, stitcher.FrameCount);
    }

    /// <summary>逐行<b>伪随机</b>灰度（非周期、非线性，避免亮度偏移被某个位移「吸收」成假匹配）。与 Swift 版同一个哈希。</summary>
    private static int HashByte(int n)
    {
        unchecked
        {
            var x = (uint)n * 2_654_435_761u;
            x ^= x >> 15;
            x *= 2_246_822_519u;
            x ^= x >> 13;
            return (int)(x & 0xFF);
        }
    }

    /// <summary>从 position 起的逐行伪随机灰度图，整体叠加 brightness 亮度偏移（模拟「脏匹配」：内容对齐但有色差）。</summary>
    private static RgbaImage HashFrame(int width, int height, int position, int brightness) =>
        RowImage(width, height, y => Math.Clamp(HashByte(position + y) + brightness, 0, 255));

    [Fact]
    public void EndOfPageSmallDirtyShiftStopsWithoutJitter()
    {
        const int w = 16, h = 120;   // height/20 = 6 → 位移 4 属「小位移」
        var a = HashFrame(w, h, 0, 0);
        var dirty = HashFrame(w, h, 4, 15);  // 小位移 + 色差脏匹配（分数落在 0.045~0.08）
        var stitcher = new ScrollStitcher(Step1());
        Assert.Equal(ScrollStitcher.AppendResult.First, stitcher.Append(a));
        Assert.Equal(ScrollStitcher.AppendResult.Duplicate, stitcher.Append(dirty));   // 收尾防抖：判为到底，不追加抖动半帧
        Assert.Equal(1, stitcher.FrameCount);
    }

    [Fact]
    public void EndOfPageSmallCleanShiftStillAppends()
    {
        const int w = 16, h = 120;
        var a = HashFrame(w, h, 0, 0);
        var clean = HashFrame(w, h, 4, 0);  // 小位移但干净 → 仍追加
        var stitcher = new ScrollStitcher(Step1());
        Assert.Equal(ScrollStitcher.AppendResult.First, stitcher.Append(a));
        Assert.Equal(ScrollStitcher.AppendResult.Appended(4), stitcher.Append(clean));
    }

    [Fact]
    public void ReportsNoOverlapForUnrelatedFrame()
    {
        var stitcher = new ScrollStitcher(Step1());
        Assert.Equal(ScrollStitcher.AppendResult.First, stitcher.Append(MakeSourceImage(16, 60)));
        Assert.Equal(ScrollStitcher.AppendResult.NoOverlap, stitcher.Append(MakeSourceImage(16, 60, inverted: true)));
        Assert.Equal(1, stitcher.FrameCount);
    }

    // —— 以下为 Windows 侧补充（Swift 侧没有对应用例）——

    [Fact]
    public void FrameOfADifferentSizeIsRejected()
    {
        var stitcher = new ScrollStitcher(Step1());
        Assert.Null(stitcher.MakeImage());
        Assert.Equal(ScrollStitcher.AppendResult.First, stitcher.Append(MakeSourceImage(16, 60)));
        Assert.Equal(ScrollStitcher.AppendResult.Invalid, stitcher.Append(MakeSourceImage(20, 60)));
        Assert.Equal(ScrollStitcher.AppendResult.Invalid, stitcher.Append(MakeWindowImage(16, 10, 70)));
        Assert.Equal(1, stitcher.FrameCount);
    }

    [Fact]
    public void AlignColumnsOptionLetsTheStitcherFollowTheScrollingColumn()
    {
        // 宽 200，只有 [120,180) 这 60 列在滚，其余是固定侧栏。默认只左右各排除 50 列，
        // 参与比对的 [50,150) 里大半是侧栏 → 位移估不准；用 AlignColumns 指定滚动列才对得上。
        const int w = 200, h = 130, c0 = 120, c1 = 180;
        RgbaImage Frame(int position)
        {
            var image = new RgbaImage(w, h);
            for (var y = 0; y < h; y++)
            {
                var side = (byte)(y * 23 % 256);
                var mid = (byte)((position + y) * 37 % 256);
                image.Fill(0, y, w, 1, side, side, side);
                image.Fill(c0, y, c1 - c0, 1, mid, mid, mid);
            }
            return image;
        }

        var plain = new ScrollStitcher(Step1());
        plain.Append(Frame(0));
        Assert.NotEqual(ScrollStitcher.AppendResult.Appended(15), plain.Append(Frame(15)));

        var guided = new ScrollStitcher(Step1() with { AlignColumns = (c0, c1) });
        guided.Append(Frame(0));
        Assert.Equal(ScrollStitcher.AppendResult.Appended(15), guided.Append(Frame(15)));
    }

    [Fact]
    public void GrayConversionUsesLumaWeights()
    {
        var image = new RgbaImage(3, 1, [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255]);
        Assert.Equal([76, 150, 29], GrayImage.From(image).Pixels);
    }
}
