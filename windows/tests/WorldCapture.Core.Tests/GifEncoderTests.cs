using WorldCapture.Core.Imaging;

namespace WorldCapture.Core.Tests;

/// <summary>
/// 前三条移植自 macos/Tests/CaptureKitTests/GIFEncoderTests.swift（测试名保持对应）。
/// macOS 那边用 ImageIO 回读来数帧；这里用文件末尾的小解码器回读，顺带把像素、延时、循环次数都核对一遍。
/// </summary>
public class GifEncoderTests
{
    private static RgbaImage ColorFrame(double gray, int size = 16)
    {
        var v = (byte)Math.Round(gray * 255);
        var image = new RgbaImage(size, size);
        image.Fill(0, 0, size, size, v, v, v);
        return image;
    }

    [Fact]
    public void EncodesAnimatedGIFWithFrameCount()
    {
        var data = GifEncoder.Encode([
            new GifEncoder.Frame(ColorFrame(0.1), 0.1),
            new GifEncoder.Frame(ColorFrame(0.5), 0.1),
            new GifEncoder.Frame(ColorFrame(0.9), 0.1),
        ]);

        // GIF magic header "GIF8".
        Assert.Equal([0x47, 0x49, 0x46, 0x38], data[..4]);
        Assert.Equal(3, Decode(data).Frames.Count);
    }

    [Fact]
    public void EmptyFramesThrows()
    {
        Assert.ThrowsAny<Exception>(() => GifEncoder.Encode([]));
    }

    [Fact]
    public void DelaysComputedFromTimestamps()
    {
        var img = ColorFrame(0.4);
        var frames = GifEncoder.Frames([(img, 0.0), (img, 0.2), (img, 0.5)], fallbackFps: 10);
        Assert.Equal(3, frames.Count);
        Assert.Equal(0.2, frames[0].Delay, 4);
        Assert.Equal(0.3, frames[1].Delay, 4);
        // Last frame falls back to 1/fps.
        Assert.Equal(0.1, frames[2].Delay, 4);
    }

    // —— 以下为 Windows 侧补充（Swift 侧没有对应用例）——

    [Fact]
    public void FramesWithFewColorsRoundTripLosslessly()
    {
        // 200 种颜色的图：不超过 256 色时必须原样保留。
        var image = new RgbaImage(40, 25);
        for (var y = 0; y < 25; y++)
        for (var x = 0; x < 40; x++)
        {
            var n = (x * 7 + y * 13) % 200;
            image.Fill(x, y, 1, 1, (byte)n, (byte)(255 - n), (byte)(n * 3 % 256));
        }
        var solid = ColorFrame(0.5, 40);
        var second = new RgbaImage(40, 25, solid.Pixels[..(40 * 25 * 4)]);

        var gif = Decode(GifEncoder.Encode([new GifEncoder.Frame(image, 0.25), new GifEncoder.Frame(second, 1.5)], loopCount: 3));
        Assert.Equal((40, 25), (gif.Width, gif.Height));
        Assert.Equal(2, gif.RepeatCount);   // 播 3 遍 = 再重复 2 次
        Assert.Equal([25, 150], gif.Frames.Select(f => f.DelayCentiseconds));
        Assert.Equal(Rgb(image), gif.Frames[0].Rgb);
        Assert.Equal(Rgb(second), gif.Frames[1].Rgb);
    }

    [Fact]
    public void LargeNoisyFrameSurvivesCodeTableResets()
    {
        // 256 色的伪随机噪声几乎不可压缩，LZW 码表会反复写满并重置；解出来仍须逐像素相同。
        var image = new RgbaImage(300, 200);
        var state = 12345u;
        for (var i = 0; i < 300 * 200; i++)
        {
            state = state * 1664525u + 1013904223u;
            var v = (byte)(state >> 24);
            image.Pixels[i * 4] = v; image.Pixels[i * 4 + 1] = (byte)(255 - v); image.Pixels[i * 4 + 2] = v; image.Pixels[i * 4 + 3] = 255;
        }
        var gif = Decode(GifEncoder.Encode([new GifEncoder.Frame(image, 0.1)]));
        Assert.Equal(0, gif.RepeatCount);   // 默认无限循环
        Assert.Equal(Rgb(image), gif.Frames[0].Rgb);
    }

    [Fact]
    public void FramesWithManyColorsAreReducedTo256WithSmallError()
    {
        // 平滑渐变有 6 万多种颜色：压到 256 色后，每个通道的误差应当很小。
        var image = new RgbaImage(256, 256);
        for (var y = 0; y < 256; y++)
        for (var x = 0; x < 256; x++)
            image.Fill(x, y, 1, 1, (byte)x, (byte)y, (byte)((x + y) / 2));

        var (palette, indices) = GifEncoder.Quantize(image);
        Assert.Equal(256 * 3, palette.Length);

        var decoded = Decode(GifEncoder.Encode([new GifEncoder.Frame(image, 0.1)])).Frames[0].Rgb;
        var original = Rgb(image);
        var worst = 0;
        long total = 0;
        for (var i = 0; i < original.Length; i++)
        {
            var d = Math.Abs(original[i] - decoded[i]);
            worst = Math.Max(worst, d);
            total += d;
        }
        Assert.True(worst <= 24, $"单通道最大误差 {worst}");
        Assert.True(total / (double)original.Length < 6, $"平均误差 {total / (double)original.Length:F2}");
        Assert.Equal(256 * 256, indices.Length);
    }

    [Fact]
    public void DelaysAreClampedAndRoundedToCentiseconds()
    {
        Assert.Equal(2, GifEncoder.DelayCentiseconds(0));
        Assert.Equal(2, GifEncoder.DelayCentiseconds(0.004));
        Assert.Equal(10, GifEncoder.DelayCentiseconds(0.1));
        Assert.Equal(3, GifEncoder.DelayCentiseconds(0.033));
        // 时间戳挤在一起（甚至倒退）时，帧间延时抬到最小值。
        var img = ColorFrame(0.4);
        var frames = GifEncoder.Frames([(img, 1.0), (img, 1.001), (img, 0.5)], fallbackFps: 0);
        Assert.Equal([0.02, 0.02, 1.0], frames.Select(f => f.Delay));
        Assert.Empty(GifEncoder.Frames([], 10));
    }

    [Fact]
    public void LoopCountMeansTotalPlaysLikeImageIO()
    {
        // 用 macOS 的 ImageIO 实测过：loopCount 0 → 扩展里写 0（无限）；1 → 不写扩展（只播一遍）；N → 写 N − 1。
        GifEncoder.Frame[] frames = [new(ColorFrame(0.2), 0.1), new(ColorFrame(0.8), 0.1)];
        Assert.Equal(0, Decode(GifEncoder.Encode(frames, loopCount: 0)).RepeatCount);
        Assert.Null(Decode(GifEncoder.Encode(frames, loopCount: 1)).RepeatCount);
        Assert.Equal(1, Decode(GifEncoder.Encode(frames, loopCount: 2)).RepeatCount);
        Assert.Equal(4, Decode(GifEncoder.Encode(frames, loopCount: 5)).RepeatCount);
    }

    [Fact]
    public void FramesOfDifferentSizesAreRejected()
    {
        Assert.Throws<ArgumentException>(() => GifEncoder.Encode([
            new GifEncoder.Frame(ColorFrame(0.1, 16), 0.1),
            new GifEncoder.Frame(ColorFrame(0.1, 20), 0.1),
        ]));
    }

    /// <summary>
    /// 设了环境变量 WC_DEBUG_OUT 时，把一个样例 GIF 写到那个目录，供别的解码器（浏览器、系统看图）核对。
    /// 和 macOS 测试里的 WC_DEBUG_OUT 是同一个约定。
    /// </summary>
    [Fact]
    public void WritesASampleGifWhenDebugOutputIsRequested()
    {
        if (Environment.GetEnvironmentVariable("WC_DEBUG_OUT") is not { Length: > 0 } dir) return;
        var frames = new List<GifEncoder.Frame>();
        for (var f = 0; f < 4; f++)
        {
            var image = new RgbaImage(120, 80);
            for (var y = 0; y < 80; y++)
            for (var x = 0; x < 120; x++)
                image.Fill(x, y, 1, 1, (byte)(x * 2), (byte)(y * 3), (byte)(f * 60));
            image.Fill(10 + f * 25, 30, 20, 20, 255, 255, 255);
            frames.Add(new GifEncoder.Frame(image, 0.25));
        }
        File.WriteAllBytes(Path.Combine(dir, "gif-sample.gif"), GifEncoder.Encode(frames, loopCount: 2));
        File.WriteAllBytes(Path.Combine(dir, "gif-sample-frame0.rgb"), Rgb(frames[0].Image));
    }

    // —— 测试用的小解码器（只认本编码器会写出的结构：每帧整幅、带局部调色板）——

    private sealed record DecodedFrame(int DelayCentiseconds, byte[] Rgb);

    private sealed record DecodedGif(int Width, int Height, int? RepeatCount, List<DecodedFrame> Frames);

    private static byte[] Rgb(RgbaImage image)
    {
        var rgb = new byte[image.Width * image.Height * 3];
        for (int i = 0, o = 0; i < rgb.Length; i += 3, o += 4)
        {
            rgb[i] = image.Pixels[o]; rgb[i + 1] = image.Pixels[o + 1]; rgb[i + 2] = image.Pixels[o + 2];
        }
        return rgb;
    }

    private static DecodedGif Decode(byte[] data)
    {
        Assert.Equal("GIF89a"u8.ToArray(), data[..6]);
        int U16(int at) => data[at] | (data[at + 1] << 8);
        int width = U16(6), height = U16(8);
        var p = 13;
        if ((data[10] & 0x80) != 0) p += 3 << ((data[10] & 7) + 1);

        byte[] SubBlocks()
        {
            var bytes = new List<byte>();
            while (data[p] != 0)
            {
                bytes.AddRange(data.AsSpan(p + 1, data[p]));
                p += 1 + data[p];
            }
            p++;
            return bytes.ToArray();
        }

        int? loopCount = null;
        var delay = 0;
        var frames = new List<DecodedFrame>();
        while (data[p] != 0x3B)
        {
            if (data[p] == 0x21 && data[p + 1] == 0xF9)
            {
                delay = U16(p + 4);
                p += 8;
            }
            else if (data[p] == 0x21)
            {
                p += 2;
                var isNetscape = data[p] == 11 && data.AsSpan(p + 1, 11).SequenceEqual("NETSCAPE2.0"u8);
                p += 1 + data[p];
                var payload = SubBlocks();
                if (isNetscape) loopCount = payload[1] | (payload[2] << 8);
            }
            else
            {
                Assert.Equal(0x2C, data[p]);
                Assert.Equal((0, 0, width, height), (U16(p + 1), U16(p + 3), U16(p + 5), U16(p + 7)));
                var packed = data[p + 9];
                p += 10;
                Assert.True((packed & 0x80) != 0, "每帧都应带局部调色板");
                var palette = data.AsSpan(p, 3 << ((packed & 7) + 1)).ToArray();
                p += palette.Length;
                var minCodeSize = data[p++];
                var indices = Unlzw(SubBlocks(), minCodeSize, width * height);
                var rgb = new byte[indices.Length * 3];
                for (var i = 0; i < indices.Length; i++)
                    Array.Copy(palette, indices[i] * 3, rgb, i * 3, 3);
                frames.Add(new DecodedFrame(delay, rgb));
            }
        }
        Assert.Equal(data.Length - 1, p);
        return new DecodedGif(width, height, loopCount, frames);
    }

    private static byte[] Unlzw(byte[] data, int minCodeSize, int pixelCount)
    {
        var clearCode = 1 << minCodeSize;
        var endCode = clearCode + 1;
        var prefix = new int[4096];
        var suffix = new byte[4096];
        var output = new List<byte>(pixelCount);
        var stack = new Stack<byte>();

        var codeSize = minCodeSize + 1;
        var nextCode = endCode + 1;
        var previous = -1;
        int bitBuffer = 0, bitCount = 0, at = 0;
        while (true)
        {
            while (bitCount < codeSize)
            {
                bitBuffer |= data[at++] << bitCount;
                bitCount += 8;
            }
            var code = bitBuffer & ((1 << codeSize) - 1);
            bitBuffer >>= codeSize;
            bitCount -= codeSize;

            if (code == endCode) break;
            if (code == clearCode)
            {
                codeSize = minCodeSize + 1;
                nextCode = endCode + 1;
                previous = -1;
                continue;
            }

            Assert.True(code <= nextCode, "LZW 码超出了码表");
            var current = code;
            if (previous >= 0 && code == nextCode)
            {
                // 码表里还没有这个码：它等于「上一串 + 上一串的首字节」。
                current = previous;
                while (current > clearCode) current = prefix[current];
                stack.Push((byte)current);
                current = previous;
            }
            while (current > clearCode)
            {
                stack.Push(suffix[current]);
                current = prefix[current];
            }
            var first = (byte)current;
            stack.Push(first);
            while (stack.Count > 0) output.Add(stack.Pop());

            if (previous >= 0 && nextCode < 4096)
            {
                prefix[nextCode] = previous;
                suffix[nextCode] = first;
                nextCode++;
                if (nextCode == 1 << codeSize && codeSize < 12) codeSize++;
            }
            previous = code;
        }
        Assert.Equal(pixelCount, output.Count);
        return output.ToArray();
    }
}
