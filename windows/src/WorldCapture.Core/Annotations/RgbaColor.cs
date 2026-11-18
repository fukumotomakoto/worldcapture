using System.Globalization;

namespace WorldCapture.Core.Annotations;

/// <summary>
/// 与平台 UI 解耦的标注颜色：以 <c>#RRGGBB</c> 或 <c>#RRGGBBAA</c> 十六进制存储，跨平台工程文件通用。
/// 移植自 macOS <c>RGBAColor.swift</c>，解析规则（含回退色）必须保持一致。
/// </summary>
public readonly record struct RgbaColor(double Red, double Green, double Blue, double Alpha = 1)
{
    /// <summary>无法解析时的回退色：系统红 #FF3B30。</summary>
    public static readonly RgbaColor DefaultRed = new(1, 0.231, 0.188, 1);

    /// <summary>解析 <c>#RGB</c>、<c>#RRGGBB</c>、<c>#RRGGBBAA</c>；无法解析时回退到 <see cref="DefaultRed"/>。</summary>
    public static RgbaColor FromHex(string hex)
    {
        var s = hex.Trim();
        if (s.StartsWith('#')) s = s[1..];

        static double Component(string pair) =>
            int.TryParse(pair, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var v) ? v / 255.0 : 0;

        return s.Length switch
        {
            3 => new RgbaColor(
                Component(new string(s[0], 2)),
                Component(new string(s[1], 2)),
                Component(new string(s[2], 2))),
            6 or 8 => new RgbaColor(
                Component(s[..2]),
                Component(s[2..4]),
                Component(s[4..6]),
                s.Length == 8 ? Component(s[6..8]) : 1),
            _ => DefaultRed,
        };
    }

    /// <summary><c>#RRGGBB</c>（alpha 为 1 时）或 <c>#RRGGBBAA</c>。</summary>
    public string HexString
    {
        get
        {
            static string Hex(double v) =>
                ((int)Math.Round(Math.Clamp(v, 0, 1) * 255, MidpointRounding.AwayFromZero)).ToString("X2", CultureInfo.InvariantCulture);
            var rgb = Hex(Red) + Hex(Green) + Hex(Blue);
            return "#" + (Alpha >= 0.999 ? rgb : rgb + Hex(Alpha));
        }
    }

    /// <summary>WCAG 相对明度（0 黑 ～ 1 白）。</summary>
    public double RelativeLuminance
    {
        get
        {
            static double Linear(double c) => c <= 0.03928 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4);
            return 0.2126 * Linear(Red) + 0.7152 * Linear(Green) + 0.0722 * Linear(Blue);
        }
    }
}
