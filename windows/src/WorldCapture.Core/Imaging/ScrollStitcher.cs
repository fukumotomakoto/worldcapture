namespace WorldCapture.Core.Imaging;

/// <summary>一次纵向对齐结果。</summary>
/// <param name="Shift">后一帧相对前一帧向下滚动的像素行数。</param>
/// <param name="Score">重叠区域的平均绝对差 / 255，越小越匹配。</param>
public readonly record struct VerticalAlignment(int Shift, double Score);

/// <summary>
/// 累积滚动帧并拼接为一张长图。逐帧求出新增行数，仅追加新增部分。
/// 移植自 macOS <c>ScrollStitcher.swift</c>。帧一律是 <see cref="RgbaImage"/>（左上角原点），
/// 抓帧和滚轮（<c>SendInput</c>）在 Windows 层。
/// </summary>
public sealed class ScrollStitcher
{
    public sealed record Options
    {
        /// <summary>重叠匹配分数超过此阈值则视为无法对齐（跳变/内容突变）。</summary>
        public double MatchThreshold { get; init; } = 0.08;
        /// <summary>小于此新增行数视为未滚动（重复帧）。</summary>
        public int MinNewRows { get; init; } = 2;
        public int Band { get; init; } = 160;
        public int ColumnStep { get; init; } = 4;
        /// <summary>
        /// 对齐时只用的水平列范围 <c>[x0, x1)</c>（像素）。设为检测到的<b>滚动列</b>可避开固定/吸顶侧栏
        /// 干扰位移估计。为 null 时回退到默认的左右排除（仅避滚动条/窄边）。
        /// </summary>
        public (int X0, int X1)? AlignColumns { get; init; }
        /// <summary>
        /// 收尾防抖阈值：接近底部时页面只滚一点点（小位移），若此时匹配不够干净（分数 &gt; 此值），
        /// 多半是回弹/半帧错位，判为到底、不追加，避免长图底部出现抖动接缝。
        /// 仅作用于小位移帧，正常大位移的滚动帧不受影响。
        /// </summary>
        public double EndCleanThreshold { get; init; } = 0.045;
    }

    public enum AppendKind
    {
        /// <summary>第一帧。</summary>
        First,
        /// <summary>对齐成功，追加了 <see cref="AppendResult.NewRows"/> 行。</summary>
        Appended,
        /// <summary>没滚动（或到底了），未追加。</summary>
        Duplicate,
        /// <summary>和上一帧对不上（内容跳变），未追加。</summary>
        NoOverlap,
        /// <summary>帧的尺寸与前面的不一致，未追加。</summary>
        Invalid,
    }

    public readonly record struct AppendResult(AppendKind Kind, int NewRows = 0)
    {
        public static readonly AppendResult First = new(AppendKind.First);
        public static readonly AppendResult Duplicate = new(AppendKind.Duplicate);
        public static readonly AppendResult NoOverlap = new(AppendKind.NoOverlap);
        public static readonly AppendResult Invalid = new(AppendKind.Invalid);
        public static AppendResult Appended(int newRows) => new(AppendKind.Appended, newRows);
    }

    public int FrameCount => _frames.Count;
    public int StitchedHeight { get; private set; }

    private readonly List<RgbaImage> _frames = [];
    private readonly List<int> _shifts = [];
    private GrayImage? _previous;
    private readonly Options _options;

    public ScrollStitcher(Options? options = null) => _options = options ?? new Options();

    /// <summary>
    /// 在 <c>[minShift, maxShift]</c> 内寻找使 <paramref name="b"/>（从 <paramref name="bandOrigin"/> 行起的一段）
    /// 与 <paramref name="a"/>（下移 d 行后）最匹配的 d。
    /// <para>
    /// 语义：滚动向下 d 行后，a 的第 <c>bandOrigin+d+i</c> 行 ≈ b 的第 <c>bandOrigin+i</c> 行。
    /// 为控制开销，只比较从 <paramref name="bandOrigin"/> 起的 <paramref name="band"/> 行，并按 <paramref name="columnStep"/> 抽样列。
    /// <paramref name="bandOrigin"/> 可避开顶部吸顶页眉：页眉在滚动时不动，若从第 0 行比对，
    /// 会让 d=0 误判为最佳匹配（「未滚动」），导致长截图过早结束。
    /// </para>
    /// <para>
    /// <paramref name="sideInset"/> 排除左右各若干列不参与比对：滚动条、固定侧栏在滚动时不动，纳入比对会给 d=0
    /// 制造一个强匹配的竞争峰。<paramref name="columnRange"/> 给了就优先用它（显式的滚动列范围，避开宽侧栏）。
    /// </para>
    /// </summary>
    public static VerticalAlignment? BestVerticalShift(
        GrayImage a,
        GrayImage b,
        int minShift = 0,
        int? maxShift = null,
        int band = 160,
        int columnStep = 4,
        int bandOrigin = 0,
        int sideInset = 0,
        (int X0, int X1)? columnRange = null)
    {
        if (a.Width != b.Width) return null;

        var width = a.Width;
        int xStart, xEnd;
        if (columnRange is { } range)
        {
            xStart = Math.Max(0, Math.Min(range.X0, width - 1));
            xEnd = Math.Max(xStart + 1, Math.Min(range.X1, width));
        }
        else
        {
            var inset = Math.Max(0, Math.Min(sideInset, width / 3));
            xStart = inset;
            xEnd = width - inset;
        }
        if (xStart >= xEnd) return null;

        var origin = Math.Max(0, Math.Min(bandOrigin, b.Height - 1));
        var upper = Math.Min(maxShift ?? (a.Height - 1), a.Height - 1);
        var lower = Math.Max(0, minShift);
        if (lower > upper) return null;

        var step = Math.Max(1, columnStep);
        const int minimumOverlapRows = 4;
        var aPixels = a.Pixels;
        var bPixels = b.Pixels;

        VerticalAlignment? best = null;
        for (var d = lower; d <= upper; d++)
        {
            // b 取 [origin, origin+rows)；a 取 [origin+d, origin+d+rows)。
            var compareRows = Math.Min(band, Math.Min(b.Height - origin, a.Height - origin - d));
            if (compareRows < minimumOverlapRows) continue;

            long sum = 0;
            long count = 0;
            for (var i = 0; i < compareRows; i++)
            {
                var aRow = (origin + d + i) * width;
                var bRow = (origin + i) * width;
                for (var x = xStart; x < xEnd; x += step)
                {
                    sum += Math.Abs(aPixels[aRow + x] - bPixels[bRow + x]);
                    count++;
                }
            }
            if (count == 0) continue;

            var score = sum / (count * 255.0);
            if (best is null || score < best.Value.Score) best = new VerticalAlignment(d, score);
        }
        return best;
    }

    public AppendResult Append(RgbaImage frame)
    {
        var gray = GrayImage.From(frame);

        if (_previous is not { } previous)
        {
            _frames.Add(frame);
            _shifts.Add(0);
            _previous = gray;
            StitchedHeight = frame.Height;
            return AppendResult.First;
        }

        // macOS 版只查宽度；高度不同的帧到了合成那一步会被拉伸成首帧的高度，长图就错位了，这里直接拒收。
        if (previous.Width != gray.Width || _frames[0].Height != frame.Height) return AppendResult.Invalid;

        // 从画面上方约 12% 处开始比对，跳过常见的吸顶页眉（搜索栏/导航条），
        // 避免静止页眉把对齐结果拉到 d=0 而误判为「未滚动」导致提前结束。
        var bandOrigin = Math.Max(0, (int)(gray.Height * 0.12));
        // 有检测到的滚动列就用它（避开宽的固定侧栏）；否则左右各排除 max(50, 宽/20)（仅避滚动条）。
        var sideInset = Math.Min(gray.Width / 3, Math.Max(50, gray.Width / 20));
        if (BestVerticalShift(
                previous, gray,
                minShift: 0,
                maxShift: gray.Height - 1,
                band: _options.Band,
                columnStep: _options.ColumnStep,
                bandOrigin: bandOrigin,
                sideInset: sideInset,
                columnRange: _options.AlignColumns) is not { } alignment)
            return AppendResult.Invalid;

        if (alignment.Score > _options.MatchThreshold) return AppendResult.NoOverlap;
        if (alignment.Shift < _options.MinNewRows) return AppendResult.Duplicate;

        // 收尾防抖：位移很小（接近底部）且匹配不干净 → 判为到底，不追加这半帧抖动。
        var smallShift = alignment.Shift < Math.Max(_options.MinNewRows + 1, gray.Height / 20);
        if (smallShift && alignment.Score > _options.EndCleanThreshold) return AppendResult.Duplicate;

        _frames.Add(frame);
        _shifts.Add(alignment.Shift);
        _previous = gray;
        StitchedHeight += alignment.Shift;
        return AppendResult.Appended(alignment.Shift);
    }

    /// <summary>合成长图：各帧按累计位移自顶向下放置，后一帧盖住与前一帧重叠的部分。还没有帧时返回 null。</summary>
    public RgbaImage? MakeImage()
    {
        if (_frames.Count == 0 || StitchedHeight <= 0) return null;
        var width = _frames[0].Width;
        var frameHeight = _frames[0].Height;
        var result = new RgbaImage(width, StitchedHeight);
        var stride = width * 4;

        var top = 0;
        for (var i = 0; i < _frames.Count; i++)
        {
            top += _shifts[i]; // _shifts[0] == 0
            Buffer.BlockCopy(_frames[i].Pixels, 0, result.Pixels, top * stride, frameHeight * stride);
        }
        return result;
    }
}
