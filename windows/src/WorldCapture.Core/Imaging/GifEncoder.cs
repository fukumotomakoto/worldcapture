namespace WorldCapture.Core.Imaging;

/// <summary>
/// 把一串带延时的帧编码为动图 GIF（GIF89a）。
/// <para>
/// macOS 版的 <c>GIFEncoder.swift</c> 把编码交给系统的 ImageIO，自己只算延时。Windows 没有 ImageIO，
/// 所以这里是一份不依赖任何平台的完整编码器：每帧自带调色板（不超过 256 色）+ LZW 压缩。
/// 延时规则（最小 0.02 秒、末帧用回退帧率）与 macOS 版一致；<b>调色板的选色是这里自己的算法，
/// 画面观感和文件大小不保证与 macOS 导出的 GIF 相同</b>。
/// </para>
/// </summary>
public static class GifEncoder
{
    /// <summary>一帧画面及其显示时长（秒），即到下一帧的间隔。透明度不参与编码，帧按不透明处理。</summary>
    public readonly record struct Frame(RgbaImage Image, double Delay);

    /// <summary>每帧最短显示时长（秒）。再小的话各浏览器会自行改成 0.1 秒，播放速度就不可控了。</summary>
    public const double MinimumDelay = 0.02;

    /// <summary>
    /// 编码。<paramref name="loopCount"/> 是总共播放几遍，0 表示无限循环（与 macOS 版同义）。所有帧必须同尺寸，宽高不超过 65535。
    /// 没有帧、帧尺寸不一致时抛 <see cref="ArgumentException"/>。
    /// </summary>
    public static byte[] Encode(IReadOnlyList<Frame> frames, int loopCount = 0)
    {
        if (frames.Count == 0) throw new ArgumentException("没有可编码的帧", nameof(frames));
        int width = frames[0].Image.Width, height = frames[0].Image.Height;
        if (width > ushort.MaxValue || height > ushort.MaxValue)
            throw new ArgumentException("GIF 的宽高不能超过 65535", nameof(frames));
        if (frames.Any(f => f.Image.Width != width || f.Image.Height != height))
            throw new ArgumentException("所有帧的尺寸必须相同", nameof(frames));

        using var stream = new MemoryStream();
        stream.Write("GIF89a"u8);
        WriteUInt16(stream, width);
        WriteUInt16(stream, height);
        stream.WriteByte(0x70);   // 无全局调色板（每帧自带），色深 8 位
        stream.WriteByte(0);      // 背景色索引
        stream.WriteByte(0);      // 像素宽高比：未指定

        // 循环次数（NETSCAPE2.0 应用扩展）。扩展里存的是「再重复几次」：0 = 无限，不写扩展 = 只播一遍。
        // loopCount 的含义照 macOS 的 ImageIO：总共播放几遍。所以 1 不写扩展，N 写 N − 1。
        if (loopCount != 1)
        {
            stream.Write([0x21, 0xFF, 0x0B]);
            stream.Write("NETSCAPE2.0"u8);
            stream.Write([0x03, 0x01]);
            WriteUInt16(stream, Math.Clamp(loopCount - 1, 0, ushort.MaxValue));
            stream.WriteByte(0);
        }

        foreach (var frame in frames)
        {
            var (palette, indices) = Quantize(frame.Image);
            var bits = PaletteBits(palette.Length / 3);

            // 图形控制扩展：处置方式 1（保留本帧，下一帧整幅覆盖），延时单位 1/100 秒。
            stream.Write([0x21, 0xF9, 0x04, 0x04]);
            WriteUInt16(stream, DelayCentiseconds(frame.Delay));
            stream.Write([0x00, 0x00]);

            // 图像描述符 + 本帧调色板。
            stream.WriteByte(0x2C);
            WriteUInt16(stream, 0);
            WriteUInt16(stream, 0);
            WriteUInt16(stream, width);
            WriteUInt16(stream, height);
            stream.WriteByte((byte)(0x80 | (bits - 1)));
            stream.Write(palette);
            stream.Write(new byte[(1 << bits) * 3 - palette.Length]);   // 调色板长度必须是 2 的幂，不足的补黑

            WriteLzw(stream, indices, Math.Max(2, bits));
        }

        stream.WriteByte(0x3B);
        return stream.ToArray();
    }

    /// <summary>由带时间戳的帧计算每帧延时：第 i 帧延时 = t[i+1] − t[i]（不小于 <see cref="MinimumDelay"/>）；末帧用回退帧率。</summary>
    public static IReadOnlyList<Frame> Frames(IReadOnlyList<(RgbaImage Image, double Timestamp)> timestamped, int fallbackFps)
    {
        var fallbackDelay = 1.0 / Math.Max(1, fallbackFps);
        var frames = new List<Frame>(timestamped.Count);
        for (var i = 0; i < timestamped.Count; i++)
        {
            var delay = i + 1 < timestamped.Count
                ? Math.Max(MinimumDelay, timestamped[i + 1].Timestamp - timestamped[i].Timestamp)
                : fallbackDelay;
            frames.Add(new Frame(timestamped[i].Image, delay));
        }
        return frames;
    }

    /// <summary>秒 → GIF 的延时单位（1/100 秒），先抬到最小延时再四舍五入。</summary>
    internal static int DelayCentiseconds(double delay) =>
        Math.Clamp((int)Math.Round(Math.Max(MinimumDelay, delay) * 100, MidpointRounding.AwayFromZero), 2, ushort.MaxValue);

    private static void WriteUInt16(Stream stream, int value)
    {
        stream.WriteByte((byte)(value & 0xFF));
        stream.WriteByte((byte)((value >> 8) & 0xFF));
    }

    /// <summary>装下 <paramref name="colorCount"/> 种颜色所需的调色板位数（1…8）。</summary>
    private static int PaletteBits(int colorCount)
    {
        var bits = 1;
        while (1 << bits < colorCount) bits++;
        return bits;
    }

    // —— 选色 ——

    /// <summary>
    /// 把一帧变成「调色板 + 每像素的调色板索引」。不超过 256 种颜色时原样保留（无损）；
    /// 超过时用中位切分选出 256 色。
    /// </summary>
    internal static (byte[] Palette, byte[] Indices) Quantize(RgbaImage image)
    {
        var pixels = image.Pixels;
        var count = image.Width * image.Height;
        var indices = new byte[count];

        var exact = new Dictionary<int, byte>();
        var exactPalette = new List<byte>(256 * 3);
        var fitsExactly = true;
        for (int i = 0, o = 0; i < count; i++, o += 4)
        {
            var rgb = (pixels[o] << 16) | (pixels[o + 1] << 8) | pixels[o + 2];
            if (!exact.TryGetValue(rgb, out var index))
            {
                if (exact.Count == 256) { fitsExactly = false; break; }
                index = (byte)exact.Count;
                exact[rgb] = index;
                exactPalette.Add(pixels[o]); exactPalette.Add(pixels[o + 1]); exactPalette.Add(pixels[o + 2]);
            }
            indices[i] = index;
        }
        if (fitsExactly) return (exactPalette.ToArray(), indices);

        // 颜色太多：先把颜色归到 32×32×32 的格子里（每通道取高 5 位），再对有像素的格子做中位切分。
        const int binCount = 1 << 15;
        var binPixels = new int[binCount];
        var sumR = new long[binCount];
        var sumG = new long[binCount];
        var sumB = new long[binCount];
        for (int i = 0, o = 0; i < count; i++, o += 4)
        {
            var bin = BinOf(pixels[o], pixels[o + 1], pixels[o + 2]);
            binPixels[bin]++;
            sumR[bin] += pixels[o]; sumG[bin] += pixels[o + 1]; sumB[bin] += pixels[o + 2];
        }

        var boxes = new List<List<int>> { Enumerable.Range(0, binCount).Where(b => binPixels[b] > 0).ToList() };
        while (boxes.Count < 256)
        {
            // 每次切「颜色跨度最大」的那一盒，沿跨度最大的通道、在像素数的中位处一分为二。
            var target = -1;
            var targetRange = 0;
            var targetChannel = 0;
            for (var b = 0; b < boxes.Count; b++)
            {
                if (boxes[b].Count < 2) continue;
                var (range, channel) = WidestChannel(boxes[b]);
                if (range <= targetRange) continue;
                target = b; targetRange = range; targetChannel = channel;
            }
            if (target < 0) break;

            var box = boxes[target];
            var shift = targetChannel * 5;
            box.Sort((x, y) => ((x >> shift) & 31).CompareTo((y >> shift) & 31) is var c and not 0 ? c : x.CompareTo(y));
            long total = box.Sum(b => (long)binPixels[b]);
            long running = 0;
            var cut = 1;
            for (var k = 0; k < box.Count - 1; k++)
            {
                running += binPixels[box[k]];
                cut = k + 1;
                if (running * 2 >= total) break;
            }
            boxes[target] = box.GetRange(0, cut);
            boxes.Add(box.GetRange(cut, box.Count - cut));
        }

        var palette = new byte[boxes.Count * 3];
        var paletteIndexOfBin = new byte[binCount];
        for (var b = 0; b < boxes.Count; b++)
        {
            long n = 0, r = 0, g = 0, bl = 0;
            foreach (var bin in boxes[b])
            {
                n += binPixels[bin]; r += sumR[bin]; g += sumG[bin]; bl += sumB[bin];
                paletteIndexOfBin[bin] = (byte)b;
            }
            palette[b * 3] = (byte)((r + n / 2) / n);
            palette[b * 3 + 1] = (byte)((g + n / 2) / n);
            palette[b * 3 + 2] = (byte)((bl + n / 2) / n);
        }
        for (int i = 0, o = 0; i < count; i++, o += 4)
            indices[i] = paletteIndexOfBin[BinOf(pixels[o], pixels[o + 1], pixels[o + 2])];
        return (palette, indices);
    }

    private static int BinOf(byte r, byte g, byte b) => ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);

    /// <summary>一盒格子里跨度最大的通道：返回（跨度，通道序号——0 蓝、1 绿、2 红，对应格子编号里的位移）。</summary>
    private static (int Range, int Channel) WidestChannel(List<int> box)
    {
        Span<int> min = [31, 31, 31];
        Span<int> max = [0, 0, 0];
        foreach (var bin in box)
        for (var c = 0; c < 3; c++)
        {
            var v = (bin >> (c * 5)) & 31;
            if (v < min[c]) min[c] = v;
            if (v > max[c]) max[c] = v;
        }
        // 跨度相同时优先绿、再红、再蓝（人眼对绿最敏感）。
        var best = 1;
        if (max[2] - min[2] > max[best] - min[best]) best = 2;
        if (max[0] - min[0] > max[best] - min[best]) best = 0;
        return (max[best] - min[best], best);
    }

    // —— LZW ——

    /// <summary>GIF 的变长码 LZW：码宽从 <c>minCodeSize + 1</c> 位起，最多 12 位，码表满了就发清除码重来。</summary>
    private static void WriteLzw(Stream stream, byte[] indices, int minCodeSize)
    {
        stream.WriteByte((byte)minCodeSize);
        var output = new SubBlockWriter(stream);

        var clearCode = 1 << minCodeSize;
        var endCode = clearCode + 1;
        var nextCode = endCode + 1;
        var codeSize = minCodeSize + 1;
        var table = new Dictionary<int, int>();

        output.WriteCode(clearCode, codeSize);
        int prefix = indices[0];
        for (var i = 1; i < indices.Length; i++)
        {
            var k = indices[i];
            var key = (prefix << 8) | k;
            if (table.TryGetValue(key, out var code))
            {
                prefix = code;
                continue;
            }

            output.WriteCode(prefix, codeSize);
            if (nextCode < 4096)
            {
                table[key] = nextCode;
                if (nextCode == 1 << codeSize && codeSize < 12) codeSize++;
                nextCode++;
            }
            else
            {
                output.WriteCode(clearCode, codeSize);
                table.Clear();
                nextCode = endCode + 1;
                codeSize = minCodeSize + 1;
            }
            prefix = k;
        }
        output.WriteCode(prefix, codeSize);
        output.WriteCode(endCode, codeSize);
        output.Finish();
    }

    /// <summary>把变长码按低位在前拼成字节流，再切成 GIF 的数据子块（每块最多 255 字节，以 0 长度块收尾）。</summary>
    private sealed class SubBlockWriter(Stream stream)
    {
        private readonly byte[] _block = new byte[255];
        private int _blockLength;
        private int _bitBuffer;
        private int _bitCount;

        public void WriteCode(int code, int codeSize)
        {
            _bitBuffer |= code << _bitCount;
            _bitCount += codeSize;
            while (_bitCount >= 8)
            {
                WriteByte((byte)(_bitBuffer & 0xFF));
                _bitBuffer >>= 8;
                _bitCount -= 8;
            }
        }

        public void Finish()
        {
            if (_bitCount > 0) WriteByte((byte)(_bitBuffer & 0xFF));
            FlushBlock();
            stream.WriteByte(0);
        }

        private void WriteByte(byte value)
        {
            _block[_blockLength++] = value;
            if (_blockLength == 255) FlushBlock();
        }

        private void FlushBlock()
        {
            if (_blockLength == 0) return;
            stream.WriteByte((byte)_blockLength);
            stream.Write(_block, 0, _blockLength);
            _blockLength = 0;
        }
    }
}
