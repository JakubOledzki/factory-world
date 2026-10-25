namespace FactoryWorld.Modules.Abstractions.Contracts;

/// <summary>
/// The tiles an object covers on a plot. Most stand on one tile; a forester's building, a solar tower, a large wind turbine, an ice hotel and an assembly hall cover a
/// square of 3 × 3 around the tile it stands on (its <see cref="PlotObject.TileX"/>, <see cref="PlotObject.TileY"/>).
/// </summary>
public static class Footprints
{
    /// <summary>How many tiles the object reaches out from its own tile each way: 0 for one tile, 1 for 3 × 3.</summary>
    public static int Reach(string kind) => Items.IsForester(kind) || kind is Items.SolarTower or Items.LargeWindTurbine or Items.IceHotel or Items.AssemblyHall ? 1 : 0;

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

    /// <summary>Kinds that cover more than one tile, for queries.</summary>
    public static readonly string[] Large = [Items.ForesterHut, Items.ForesterLodge, Items.ForestryStation, Items.SolarTower, Items.LargeWindTurbine, Items.IceHotel, Items.AssemblyHall];
}
