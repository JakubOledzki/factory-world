using System.Text.RegularExpressions;

namespace FactoryWorld.Modules.Characters;

public static partial class CharacterRules
{
    public const int MinNameLength = 3;
    public const int MaxNameLength = 16;

    /// <summary>Letters (Polish ones too), digits and underscore.</summary>
    public static bool IsValidName(string name) => NamePattern().IsMatch(name);

    [GeneratedRegex(@"^[\p{L}0-9_]{3,16}$")]
    private static partial Regex NamePattern();
}
