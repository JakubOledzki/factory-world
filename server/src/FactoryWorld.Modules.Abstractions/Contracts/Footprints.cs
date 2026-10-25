namespace FactoryWorld.Modules.Abstractions.Contracts;

/// <summary>
/// The tiles an object covers on a plot. Most stand on one tile; a forester's building, a solar tower, a large wind turbine, an ice hotel, an assembly hall,
/// a robotic hall, the steelworks, an automated warehouse and a fusion plant cover a square of 3 × 3 around the tile it stands on (its
/// <see cref="PlotObject.TileX"/>, <see cref="PlotObject.TileY"/>), the steel combine and the megafactory one of 5 × 5, a rail port one of 9 × 9.
/// </summary>
public static class Footprints
{
    /// <summary>How many tiles the object reaches out from its own tile each way: 0 for one tile, 1 for 3 × 3, 2 for 5 × 5, 4 for 9 × 9.</summary>
    public static int Reach(string kind) => Giant.Contains(kind) ? GiantReach : Huge.Contains(kind) ? 2 : Large.Contains(kind) ? 1 : 0;

    /// <summary>How many tiles wide (and deep) the object is.</summary>
    public static int Size(string kind) => 2 * Reach(kind) + 1;

    /// <summary>Every tile an object of <paramref name="kind"/> standing on (x, y) covers.</summary>
    public static IEnumerable<(int X, int Y)> Tiles(string kind, int x, int y)
    {
        var r = Reach(kind);
        for (var dy = -r; dy <= r; dy++)
        {
            for (var dx = -r; dx <= r; dx++)
            {
                yield return (x + dx, y + dy);
            }
        }
    }

    public static bool Covers(string kind, int x, int y, int tileX, int tileY) =>
        Math.Abs(tileX - x) <= Reach(kind) && Math.Abs(tileY - y) <= Reach(kind);

    /// <summary>The object once on every tile it covers, all with its id: for whatever looks objects up by tile.</summary>
    public static IEnumerable<PlotObject> Spread(PlotObject o) =>
        Reach(o.Kind) == 0 ? [o] : Tiles(o.Kind, o.TileX, o.TileY).Select(t => o with { TileX = t.X, TileY = t.Y });

    /// <summary>Kinds that cover 3 × 3 tiles, for queries.</summary>
    public static readonly string[] Large =
    [
        Items.ForesterHut, Items.ForesterLodge, Items.ForestryStation, Items.SolarTower, Items.LargeWindTurbine, Items.IceHotel, Items.AssemblyHall,
        Items.RoboticHall, Items.OxygenConverter, Items.RollingMill, Items.ContinuousCaster, Items.AutomatedWarehouse, Items.FusionPlant,
        Items.Canteen, Items.BiogasPlant, Items.Farmstead, Items.ManorFarm, Items.BuyMarket,
    ];

    /// <summary>Kinds that cover 5 × 5 tiles, for queries.</summary>
    public static readonly string[] Huge = [Items.SteelCombine, Items.Megafactory];

    /// <summary>Kinds that cover 9 × 9 tiles (<see cref="GiantReach"/> each way), for queries: the rail port with its tracks and ferry ramp.</summary>
    public static readonly string[] Giant = [Items.RailPort];

    public const int GiantReach = 4;
}
