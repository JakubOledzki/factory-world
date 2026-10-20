namespace FactoryWorld.Modules.Characters;

/// <summary>What the player picked in the character editor; each value is an index into <see cref="AppearanceCatalog"/>.</summary>
public sealed record Appearance(
    int SkinTone,
    int HairStyle,
    int HairColor,
    int ShirtStyle,
    int ShirtColor,
    int PantsColor,
    int ShoesColor);

/// <summary>
/// The options of the character editor. The client draws the character from these palettes,
/// so adding a colour here makes it available in the game without a client update.
/// </summary>
public static class AppearanceCatalog
{
    public static readonly string[] SkinTones = ["#f6d7c3", "#eac0a0", "#d9a07a", "#b97a55", "#8d5a3b", "#5e3b28"];

    /// <summary>0 = bald, then short, spiky, long, ponytail, curly.</summary>
    public const int HairStyles = 6;

    public static readonly string[] HairColors = ["#1f1a17", "#4a2f1d", "#7b4a26", "#b8792f", "#e3c16f", "#c7c2b8", "#a33b2b", "#3f5fa8"];

    /// <summary>0 = t-shirt, 1 = tank top, 2 = hoodie.</summary>
    public const int ShirtStyles = 3;

    public static readonly string[] ClothColors =
    [
        "#e8e4da", "#3a3a40", "#c0392b", "#e67e22", "#f1c40f", "#27ae60",
        "#16a085", "#2980b9", "#34495e", "#8e44ad", "#7f5539", "#d35d8b",
    ];

    public static bool IsValid(Appearance a) =>
        InRange(a.SkinTone, SkinTones.Length)
        && InRange(a.HairStyle, HairStyles)
        && InRange(a.HairColor, HairColors.Length)
        && InRange(a.ShirtStyle, ShirtStyles)
        && InRange(a.ShirtColor, ClothColors.Length)
        && InRange(a.PantsColor, ClothColors.Length)
        && InRange(a.ShoesColor, ClothColors.Length);

    private static bool InRange(int value, int count) => value >= 0 && value < count;
}
