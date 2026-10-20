namespace FactoryWorld.Modules.Characters;

/// <summary>Total XP to reach level L is 200 × (L − 1)²: level 2 at 200 XP, level 10 at 16 200 XP.</summary>
public static class Leveling
{
    public const int MaxLevel = 100;

    public static long TotalXpForLevel(int level) => 200L * (level - 1) * (level - 1);

    public static int LevelForXp(long xp)
    {
        var level = 1 + (int)Math.Floor(Math.Sqrt(Math.Max(xp, 0) / 200.0));
        // Guard against floating point rounding just below a boundary.
        while (level < MaxLevel && TotalXpForLevel(level + 1) <= xp)
        {
            level++;
        }

        while (level > 1 && TotalXpForLevel(level) > xp)
        {
            level--;
        }

        return Math.Min(level, MaxLevel);
    }
}
