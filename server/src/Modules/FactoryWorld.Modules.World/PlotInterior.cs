using System.IO.Compression;
using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using NpgsqlTypes;

namespace FactoryWorld.Modules.World;

/// <summary>What stands on one tile inside a plot. Sent to the client, so never renumber.</summary>
public enum TileObject : byte
{
    None = 0,
    Tree = 1,
    Rock = 2,
    Dune = 3,
    Rail = 4,
    Station = 5,
    Bush = 6,
    Mine = 7,
    Water = 8,
    Flotsam = 9,

    /// <summary>A block of the glacier's ice, cut with a pickaxe; it freezes again after a blizzard.</summary>
    IceBlock = 10,

    /// <summary>A dark stone fallen from the sky onto the ice, broken with a pickaxe for meteoric iron and now and then iridium.</summary>
    Meteorite = 11,

    /// <summary>A crack in the glacier: nothing stands on it until a bridge of beams is laid over it.</summary>
    Crevasse = 12,

    /// <summary>A crevasse a bridge was laid over: anything may stand on it.</summary>
    Bridge = 13,

    /// <summary>Snow an avalanche left in a blizzard, dug away with a shovel; whatever stands under it is buried until then.</summary>
    Snowdrift = 14,

    /// <summary>Trees of other kinds than the pine (<see cref="Tree"/>), see <see cref="Trees"/>.</summary>
    SpruceTree = 15,
    BirchTree = 16,
    OakTree = 17,
    LindenTree = 18,

    /// <summary>Mushrooms on the floor of an old forest, picked by hand; they come up again after <see cref="Forestry.MushroomRegrow"/>.</summary>
    Mushrooms = 19,
}

/// <summary>
/// The inside of a plot: Size × Size tiles of 20 m. Every plot is generated the same way from its
/// position, so only what players changed (harvested trees, rocks...) is stored. Along the top
/// edge runs the railway with the plot's station; the rest is covered by the biome's nature.
/// </summary>
public static class PlotLayout
{
    public const int Size = 250;

    public const int TileMeters = PlotRules.SideKm * 1000 / Size;

    /// <summary>The track runs across the whole plot on this row.</summary>
    public const int RailRow = 9;

    /// <summary>The station building, standing on the track's north side.</summary>
    public static readonly (int X, int Y, int Width, int Height) Station = (119, 3, 12, 6);

    /// <summary>Where the player appears, in front of the station, on the cleared strip south of the track.</summary>
    public static readonly (int X, int Y) Spawn = (125, 11);

    /// <summary>Rows kept clear around the railway.</summary>
    public const int ClearRows = 12;

    /// <summary>Chance (per mille) of each object on a tile, by biome; scaled by a patchy noise.</summary>
    private static readonly IReadOnlyDictionary<Biome, (TileObject Object, int PerMille)[]> Nature = new Dictionary<Biome, (TileObject, int)[]>
    {
        [Biome.Forest] = [(TileObject.Tree, 380), (TileObject.Rock, 8), (TileObject.Bush, 30)],
        [Biome.Farmland] = [(TileObject.Tree, 25), (TileObject.Bush, 25), (TileObject.Rock, 4)],
        [Biome.Grassland] = [(TileObject.Tree, 15), (TileObject.Bush, 40), (TileObject.Rock, 10)],
        [Biome.Desert] = [(TileObject.Dune, 90), (TileObject.Rock, 18), (TileObject.Bush, 6)],
        // No trees grow in the mountains; the gap they left keeps every rock and bush where it stood.
        [Biome.Mountains] = [(TileObject.Rock, 260), (TileObject.None, 45), (TileObject.Bush, 10)],
        [Biome.Tundra] = [(TileObject.Rock, 40), (TileObject.Bush, 35), (TileObject.Tree, 8)],
        [Biome.Ice] = [(TileObject.Rock, 25), (TileObject.IceBlock, 70), (TileObject.Crevasse, 8), (TileObject.Meteorite, 2)],
        [Biome.City] = [],
        [Biome.Coast] = [(TileObject.Tree, 50), (TileObject.Dune, 30), (TileObject.Rock, 15)],
        [Biome.Lakeshore] = [(TileObject.Tree, 90), (TileObject.Bush, 40), (TileObject.Rock, 10)],
        // Date palms around the pond of an oasis, on sand.
        [Biome.Oasis] = [(TileObject.Dune, 60), (TileObject.Tree, 45), (TileObject.Bush, 25), (TileObject.Rock, 8)],
    };

    public static bool Inside(int x, int y) => x >= 0 && y >= 0 && x < Size && y < Size;

    /// <summary>One byte per tile (row by row): the <see cref="TileObject"/> standing there before anyone touched it.</summary>
    public static byte[] Generate(int plotX, int plotY, Biome biome)
    {
        var tiles = new byte[Size * Size];
        var nature = Nature.GetValueOrDefault(biome, []);
        var seed = (uint)(plotX * 73856093) ^ (uint)(plotY * 19349663);
        for (var y = ClearRows; y < Size; y++)
        {
            for (var x = 0; x < Size; x++)
            {
                // Objects grow in patches with clearings between them.
                var patch = 0.3 + 1.4 * Noise(seed, x / 14.0, y / 14.0);
                var roll = Hash(seed, x, y) % 1000;
                var at = 0.0;
                foreach (var (obj, perMille) in nature)
                {
                    at += perMille * patch;
                    if (roll < at)
                    {
                        tiles[y * Size + x] = (byte)obj;
                        break;
                    }
                }
            }
        }

        Coast.AddWater(tiles, seed, biome);
        Trees.Assign(tiles, seed, biome);
        Forestry.AddMushrooms(tiles, seed, biome);
        for (var x = 0; x < Size; x++)
        {
            tiles[RailRow * Size + x] = (byte)TileObject.Rail;
        }

        // Each mine stands on cleared ground with an open strip in front of its entrance.
        foreach (var mine in Mines(plotX, plotY, biome))
        {
            for (var y = mine.Y - 1; y < mine.Y + MineSite.Height + 3; y++)
            {
                for (var x = mine.X - 1; x < mine.X + MineSite.Width + 1; x++)
                {
                    var inside = x >= mine.X && x < mine.X + MineSite.Width && y >= mine.Y && y < mine.Y + MineSite.Height;
                    tiles[y * Size + x] = (byte)(inside ? TileObject.Mine : TileObject.None);
                }
            }
        }

        var (sx, sy, sw, sh) = Station;
        for (var y = sy; y < sy + sh; y++)
        {
            for (var x = sx; x < sx + sw; x++)
            {
                tiles[y * Size + x] = (byte)TileObject.Station;
            }
        }

        return tiles;
    }

    /// <summary>
    /// The mines of a plot: 1-5 on a mining plot, none elsewhere. The first stands near the
    /// station, the others anywhere, never touching each other. Always the same for a plot.
    /// </summary>
    public static IReadOnlyList<MineSite> Mines(int plotX, int plotY, Biome biome)
    {
        if (!Mining.HasMines(biome))
        {
            return [];
        }

        var seed = (uint)(plotX * 83492791) ^ (uint)(plotY * 2654435761);
        var count = 1 + (int)(Hash(seed, 0, 0) % 5);
        var mines = new List<MineSite>();
        for (var attempt = 1; mines.Count < count && attempt < 500; attempt++)
        {
            var (x, y) = mines.Count == 0
                ? (Spawn.X - 20 + (int)(Hash(seed, attempt, 1) % 36), ClearRows + 6 + (int)(Hash(seed, attempt, 2) % 14))
                : (4 + (int)(Hash(seed, attempt, 1) % (Size - 8 - MineSite.Width)), ClearRows + 4 + (int)(Hash(seed, attempt, 2) % (Size - ClearRows - 12)));
            if (mines.All(m => Math.Abs(m.X - x) > MineSite.Width + 8 || Math.Abs(m.Y - y) > MineSite.Height + 8))
            {
                mines.Add(new MineSite(mines.Count, x, y));
            }
        }

        return mines;
    }

    /// <summary>Whether an object can be gathered: a bush and what the sea threw up are picked up by hand, the rest needs <see cref="ToolFor"/>.</summary>
    public static bool Gatherable(TileObject obj) => obj is TileObject.Bush or TileObject.Flotsam or TileObject.Mushrooms || ToolFor(obj) is not null;

    /// <summary>Beams a bridge over a crevasse takes.</summary>
    public const int BridgeBeams = 3;

    /// <summary>Which tool a player needs to gather an object, or null when none does (or it cannot be gathered).</summary>
    public static string? ToolFor(TileObject obj) => obj switch
    {
        _ when Trees.IsTree(obj) => Items.Axe,
        TileObject.Rock or TileObject.IceBlock or TileObject.Meteorite => Items.Pickaxe,
        TileObject.Dune or TileObject.Snowdrift => Items.Shovel,
        TileObject.Water => Items.FishingRod,
        _ => null,
    };

    /// <summary>The tool a player gets with a newly bought plot of a biome, or null.</summary>
    public static string? StarterTool(Biome biome) => biome switch
    {
        Biome.Forest => Items.Axe,
        Biome.Desert or Biome.Oasis => Items.Shovel,
        Biome.Mountains => Items.Pickaxe,
        Biome.Farmland => Items.Hoe,
        Biome.Grassland => Items.Shears,
        Biome.Coast or Biome.Lakeshore => Items.FishingRod,
        Biome.Ice => Items.Pickaxe,
        _ => null,
    };

    /// <summary>Of dunes dug, this many in a hundred give clay too.</summary>
    public const int ClayChance = 15;

    /// <summary>Of dunes dug, this many in a thousand give up a fossil: an ammonite, an ancient coin or a dinosaur bone.</summary>
    public const int FossilPerMille = 4;

    /// <summary>Of meteorites broken, this many in a hundred give iridium too.</summary>
    public const int IridiumChance = 5;

    /// <summary>A reed fence keeps the sand of a sandstorm off dug dunes this many tiles from it each way.</summary>
    public const int FenceShelter = 4;

    /// <summary>What gathering an object on a plot of <paramref name="biome"/> gives, for a roll of 0-99 and a <paramref name="rare"/> one of 0-999:
    /// a palm in an oasis gives dates, a dune on sand 30% more sand, and now and then clay or a fossil.</summary>
    public static IReadOnlyList<(string Item, int Quantity)> Yield(TileObject obj, int roll, Biome biome = Biome.Ocean, int rare = 999) => obj switch
    {
        TileObject.Tree when biome == Biome.Oasis => [(Items.Wood, 1), (Items.Dates, 2)],
        _ when Trees.ByTile.TryGetValue(obj, out var kind) => Trees.Yield(kind, roll, rare),
        TileObject.Mushrooms => roll < Forestry.HerbChance ? [(Items.Mushrooms, 2), (Items.Herbs, 1)] : [(Items.Mushrooms, 2)],
        TileObject.Bush => Forestry.BushYield(biome, roll),
        TileObject.Dune => [(Items.Sand, Oasis.Sandy((int)biome) ? 4 : 3), .. Dug(roll, rare)],
        TileObject.IceBlock => [(Items.Ice, 2)],
        TileObject.Snowdrift => [(Items.Ice, 1)],
        TileObject.Meteorite => roll < IridiumChance ? [(Items.MeteoricIron, 1), (Items.Iridium, 1)] : [(Items.MeteoricIron, 1)],
        TileObject.Rock => roll switch
        {
            < 5 => [(Items.Stone, 2), (Items.CopperOre, 1)],
            < 15 => [(Items.Stone, 2), (Items.IronOre, 1)],
            < 30 => [(Items.Stone, 2), (Items.Coal, 1)],
            _ => [(Items.Stone, 2)],
        },
        _ => [],
    };

    private static IEnumerable<(string, int)> Dug(int roll, int rare)
    {
        if (roll < ClayChance)
        {
            yield return (Items.Clay, 1);
        }

        if (rare < FossilPerMille)
        {
            yield return (rare < 2 ? Items.Ammonite : rare < 3 ? Items.AncientCoin : Items.DinosaurBone, 1);
        }
    }

    internal static uint Hash(uint seed, int x, int y)
    {
        var h = seed ^ (uint)x * 0x27d4eb2du ^ (uint)y * 0x165667b1u;
        h ^= h >> 15;
        h *= 0x85ebca6bu;
        h ^= h >> 13;
        h *= 0xc2b2ae35u;
        return h ^ (h >> 16);
    }

    /// <summary>Smooth value noise in 0..1.</summary>
    internal static double Noise(uint seed, double x, double y)
    {
        int x0 = (int)Math.Floor(x), y0 = (int)Math.Floor(y);
        double fx = x - x0, fy = y - y0;
        double Corner(int cx, int cy) => (Hash(seed + 7919, cx, cy) & 0xffff) / 65535.0;
        double Smooth(double t) => t * t * (3 - 2 * t);
        var top = Corner(x0, y0) + (Corner(x0 + 1, y0) - Corner(x0, y0)) * Smooth(fx);
        var bottom = Corner(x0, y0 + 1) + (Corner(x0 + 1, y0 + 1) - Corner(x0, y0 + 1)) * Smooth(fx);
        return top + (bottom - top) * Smooth(fy);
    }
}

public static class HarvestRules
{
    /// <summary>How long one swing of a tool takes; the server refuses faster gathering.</summary>
    public static readonly TimeSpan Time = TimeSpan.FromSeconds(1.5);

    /// <summary>Cutting down a tree takes longer than any other work.</summary>
    public static readonly TimeSpan ChopTime = TimeSpan.FromSeconds(5);

    /// <summary>A chainsaw cuts a tree 70% faster than an axe.</summary>
    public static readonly TimeSpan SawTime = ChopTime * 0.3;

    /// <summary>How long gathering an object takes with the tool in hand on a plot of <paramref name="biome"/>: a rock
    /// breaks faster in the mountains and with a better pickaxe.</summary>
    public static TimeSpan TimeFor(TileObject obj, string? tool = null, Biome biome = Biome.Ocean) => obj switch
    {
        _ when Trees.IsTree(obj) => tool == Items.Chainsaw ? SawTime : ChopTime,
        TileObject.Water => Coast.FishTime(biome),
        TileObject.Rock or TileObject.IceBlock => Time / (Mining.Speed(biome) * Items.Pickaxes.GetValueOrDefault(tool ?? "", 1)),
        // A meteorite is twice as hard as a rock.
        TileObject.Meteorite => 2 * Time / (Mining.Speed(biome) * Items.Pickaxes.GetValueOrDefault(tool ?? "", 1)),
        _ => Time,
    };

    public const int XpPerHarvest = 2;

    /// <summary>The industry whose clothes make gathering an object faster, or null.</summary>
    public static string? Industry(TileObject obj) => obj switch
    {
        _ when Trees.IsTree(obj) => Industries.Forestry,
        TileObject.Bush or TileObject.Mushrooms => Industries.Forestry,
        TileObject.Rock or TileObject.IceBlock or TileObject.Meteorite or TileObject.Snowdrift => Industries.Mining,
        TileObject.Water => Industries.Fishing,
        _ => null,
    };
}

public sealed record Harvest(TileObject Object, IReadOnlyList<(string Item, int Quantity)> Items, XpGain Xp);

public sealed class PlotService(
    GameDb db, WorldMap map, IInventory inventory, IEquipment equipment, ICharacterProgress progress, IProductionStats stats,
    IEnumerable<ICompanyPlots> companies, BeachService beach, PestService pests, ForestLedger ledger, IOutfit outfit, TimeProvider time)
{
    /// <summary>The tiles of a plot as they are now; only its owner and members of its company may enter.</summary>
    public async Task<byte[]> TilesAsync(Guid player, int x, int y, CancellationToken cancellationToken)
    {
        var biome = await RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Work);
        return await TilesAsync(x, y, biome, cancellationToken);
    }

    /// <summary>The tiles of a plot of <paramref name="biome"/> as they are now, whoever asks.</summary>
    public async Task<byte[]> TilesAsync(int x, int y, Biome biome, CancellationToken cancellationToken)
    {
        var tiles = PlotLayout.Generate(x, y, biome);
        // On sand the last sandstorm blew the dunes dug before it back, where nothing stands and no reed fence is near; on the
        // glacier the ice cut before the last blizzard froze again, and its avalanches left snow about.
        var blizzard = biome == Biome.Ice ? Blizzard.LastEnded(time.GetUtcNow()) : null;
        var storm = Oasis.Sandy((int)biome) ? SandWeather.LastEnded(time.GetUtcNow()) : blizzard?.End;
        var dug = new HashSet<int>();
        await using (var command = await db.CommandAsync(
            """
            SELECT h.tile_x, h.tile_y, COALESCE(h.harvested_at >= @storm, false), (COALESCE(h.harvested_at < @storm, false) OR h.harvested_at < @picked)
                AND NOT EXISTS (SELECT 1 FROM world.plot_objects o WHERE o.x = h.x AND o.y = h.y
                    AND ((o.tile_x = h.tile_x AND o.tile_y = h.tile_y)
                        OR (o.kind = ANY(@large) AND abs(o.tile_x - h.tile_x) <= 1 AND abs(o.tile_y - h.tile_y) <= 1)
                        OR (o.kind = @fence AND abs(o.tile_x - h.tile_x) <= @shelter AND abs(o.tile_y - h.tile_y) <= @shelter)))
                AND NOT EXISTS (SELECT 1 FROM world.plot_fields f WHERE f.x = h.x AND f.y = h.y AND f.tile_x = h.tile_x AND f.tile_y = h.tile_y)
                AND NOT EXISTS (SELECT 1 FROM world.plot_trees t WHERE t.x = h.x AND t.y = h.y AND t.tile_x = h.tile_x AND t.tile_y = h.tile_y)
                AND NOT EXISTS (SELECT 1 FROM world.plot_animals a WHERE a.x = h.x AND a.y = h.y AND a.tile_x = h.tile_x AND a.tile_y = h.tile_y),
                COALESCE(h.harvested_at < @storm, false)
            FROM world.plot_harvests h WHERE h.x = @x AND h.y = @y
            """, cancellationToken))
        {
            command.Parameters.AddWithValue("x", x);
            command.Parameters.AddWithValue("y", y);
            command.Parameters.Add(new NpgsqlParameter("storm", NpgsqlDbType.TimestampTz) { Value = (object?)storm ?? DBNull.Value });
            command.Parameters.AddWithValue("large", Footprints.Large);
            command.Parameters.AddWithValue("fence", Items.ReedFence);
            command.Parameters.AddWithValue("shelter", PlotLayout.FenceShelter);
            command.Parameters.AddWithValue("picked", time.GetUtcNow() - Forestry.MushroomRegrow);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                // A rock broken before the mines came may have stood where a mine is now, and the
                // lake or sea came over what had been gathered on the shore.
                var at = reader.GetInt32(1) * PlotLayout.Size + reader.GetInt32(0);
                // Sand and ice come back with the storm; mushrooms come up again by themselves.
                // Gathered before the storm or long enough ago, with nothing standing there since.
                var due = reader.GetBoolean(3);
                var regrown = due && ((reader.GetBoolean(4) && tiles[at] is (byte)TileObject.Dune or (byte)TileObject.IceBlock)
                    || tiles[at] == (byte)TileObject.Mushrooms);
                if (reader.GetBoolean(2))
                {
                    dug.Add(at);
                }

                if (tiles[at] == (byte)TileObject.Crevasse)
                {
                    tiles[at] = (byte)TileObject.Bridge;
                }
                else if (tiles[at] is not ((byte)TileObject.Mine or (byte)TileObject.Water) && !regrown)
                {
                    tiles[at] = (byte)TileObject.None;
                }
            }
        }

        // Snow the avalanches of the last blizzard left on open ice and on whatever stands there, where nobody dug it away since.
        if (blizzard is { } last)
        {
            for (var ty = PlotLayout.ClearRows; ty < PlotLayout.Size; ty++)
            {
                for (var tx = 0; tx < PlotLayout.Size; tx++)
                {
                    var at = ty * PlotLayout.Size + tx;
                    if (tiles[at] == (byte)TileObject.None && !dug.Contains(at) && Blizzard.Drift(last.Window, x, y, tx, ty))
                    {
                        tiles[at] = (byte)TileObject.Snowdrift;
                    }
                }
            }
        }

        // What the sea threw up today on the beach, where nothing stands.
        foreach (var (tx, ty) in await beach.FindsAsync(x, y, biome, tiles, time.GetUtcNow(), cancellationToken))
        {
            tiles[ty * PlotLayout.Size + tx] = (byte)TileObject.Flotsam;
        }

        return tiles;
    }

    /// <summary>Whether nothing stands on a tile of the plot: no nature, field, planted tree, animal or placed object
    /// (a forester's building covers the tiles around its own too).</summary>
    public async Task<bool> FreeAsync(Guid player, int x, int y, int tileX, int tileY, CancellationToken cancellationToken)
    {
        if (!PlotLayout.Inside(tileX, tileY)
            || (await TilesAsync(player, x, y, cancellationToken))[tileY * PlotLayout.Size + tileX] is not ((byte)TileObject.None or (byte)TileObject.Bridge))
        {
            return false;
        }

        await using var command = await db.CommandAsync(
            """
            SELECT EXISTS (SELECT 1 FROM world.plot_fields WHERE x = @x AND y = @y AND tile_x = @tx AND tile_y = @ty)
                OR EXISTS (SELECT 1 FROM world.plot_trees WHERE x = @x AND y = @y AND tile_x = @tx AND tile_y = @ty)
                OR EXISTS (SELECT 1 FROM world.plot_animals WHERE x = @x AND y = @y AND tile_x = @tx AND tile_y = @ty)
                OR EXISTS (SELECT 1 FROM world.plot_objects WHERE x = @x AND y = @y AND tile_x = @tx AND tile_y = @ty)
                OR EXISTS (SELECT 1 FROM world.plot_objects WHERE x = @x AND y = @y AND kind = ANY(@large)
                    AND abs(tile_x - @tx) <= 1 AND abs(tile_y - @ty) <= 1)
            """, cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        command.Parameters.AddWithValue("tx", tileX);
        command.Parameters.AddWithValue("ty", tileY);
        // Objects that cover 3 × 3 tiles around their own.
        command.Parameters.AddWithValue("large", Footprints.Large);
        return !(bool)(await command.ExecuteScalarAsync(cancellationToken))!;
    }

    /// <summary>
    /// Cuts a tree (grown by itself or planted), breaks a rock or digs a dune with the tool in the
    /// player's slot, or pulls out a bush by hand. <paramref name="pace"/> gets how long the work takes and refuses it if too quick.
    /// </summary>
    public Task<Harvest> HarvestAsync(
        Guid player, int x, int y, int tileX, int tileY, Action<TimeSpan> pace, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var biome = await RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Work);
            if (!PlotLayout.Inside(tileX, tileY))
            {
                throw new GameException("nothing_here", "There is nothing to gather here.");
            }

            if (await PlantedAtAsync(x, y, tileX, tileY, cancellationToken) is { } planted)
            {
                return await CutPlantedAsync(player, x, y, tileX, tileY, planted, pace, cancellationToken);
            }

            var obj = (TileObject)PlotLayout.Generate(x, y, biome)[tileY * PlotLayout.Size + tileX];
            var current = (TileObject)(await TilesAsync(x, y, biome, cancellationToken))[tileY * PlotLayout.Size + tileX];
            if (current == TileObject.Flotsam)
            {
                pace(HarvestRules.Time);
                return await beach.GatherAsync(player, x, y, tileX, tileY, async items => await GiveAsync(player, TileObject.Flotsam, items, cancellationToken), cancellationToken);
            }

            if (current == TileObject.Snowdrift)
            {
                // Snow dug away, maybe off something it buried; it comes back only with the next blizzard's avalanches.
                pace(HarvestRules.TimeFor(current, await RequireToolAsync(player, Items.Shovel, cancellationToken), biome)
                     / await SpeedAsync(player, Industries.Mining, cancellationToken));
                await MarkHarvestedAsync(x, y, tileX, tileY, always: true, cancellationToken);
                return await GiveAsync(player, current, PlotLayout.Yield(current, Random.Shared.Next(100), biome), cancellationToken);
            }

            if (current == TileObject.Crevasse)
            {
                pace(HarvestRules.Time);
                await inventory.RemoveAsync(player, Items.Beams, PlotLayout.BridgeBeams, cancellationToken);
                await MarkHarvestedAsync(x, y, tileX, tileY, always: false, cancellationToken);
                return new Harvest(TileObject.Bridge, [], await progress.AddXpAsync(player, HarvestRules.XpPerHarvest, cancellationToken));
            }

            if (current == TileObject.Bridge)
            {
                throw new GameException("nothing_here", "A bridge lies over the crevasse already.");
            }

            if (!PlotLayout.Gatherable(obj))
            {
                throw new GameException("nothing_here", "There is nothing to gather here.");
            }

            pace(HarvestRules.TimeFor(obj, PlotLayout.ToolFor(obj) is { } tool ? await RequireToolAsync(player, tool, cancellationToken) : null, biome)
                 / await SpeedAsync(player, HarvestRules.Industry(obj), cancellationToken));
            if (obj == TileObject.Water)
            {
                // The water is never fished out; a storm at sea or on a lake keeps everyone ashore but those on a breakwater.
                if (Coast.HasWater(biome))
                {
                    await beach.RequireCalmAsync(x, y, cancellationToken);
                }

                return await GiveAsync(player, obj, Coast.Catch(biome, Random.Shared.Next(100)), cancellationToken);
            }

            // A dune the sandstorm blew back is dug again, ice frozen again after a blizzard is cut again, and mushrooms come up again.
            await MarkHarvestedAsync(x, y, tileX, tileY, obj is TileObject.Dune or TileObject.IceBlock or TileObject.Mushrooms && current == obj, cancellationToken);
            if (Trees.IsTree(obj))
            {
                await ledger.RecordAsync(player, 0, 1, cancellationToken);
            }

            return await GiveAsync(player, obj, PlotLayout.Yield(obj, Random.Shared.Next(100), biome, Random.Shared.Next(1000)), cancellationToken);
        }, cancellationToken);

    /// <summary>Records that a tile was gathered now; <paramref name="always"/> also when it was before. Fails when it was and may not be again.</summary>
    private async Task MarkHarvestedAsync(int x, int y, int tileX, int tileY, bool always, CancellationToken cancellationToken)
    {
        await using var insert = await db.CommandAsync(
            """
            INSERT INTO world.plot_harvests (x, y, tile_x, tile_y, harvested_at) VALUES (@x, @y, @tx, @ty, @now)
            ON CONFLICT (x, y, tile_x, tile_y) DO UPDATE SET harvested_at = @now WHERE @regrown
            """, cancellationToken);
        insert.Parameters.AddWithValue("x", x);
        insert.Parameters.AddWithValue("y", y);
        insert.Parameters.AddWithValue("tx", tileX);
        insert.Parameters.AddWithValue("ty", tileY);
        insert.Parameters.AddWithValue("now", time.GetUtcNow());
        insert.Parameters.AddWithValue("regrown", always);
        if (await insert.ExecuteNonQueryAsync(cancellationToken) == 0)
        {
            throw new GameException("nothing_here", "This has already been gathered.");
        }
    }

    /// <summary>Whether snow an avalanche left on the glacier buries the tile an object stands on: it cannot be used until dug out.</summary>
    public async Task<bool> BuriedAsync(int x, int y, int tileX, int tileY, CancellationToken cancellationToken) =>
        map.BiomeAt(x, y) == Biome.Ice && PlotLayout.Inside(tileX, tileY)
        && (await TilesAsync(x, y, Biome.Ice, cancellationToken))[tileY * PlotLayout.Size + tileX] == (byte)TileObject.Snowdrift;

    /// <summary>Fails with <c>buried</c> when snow buries the object.</summary>
    public async Task RequireDugOutAsync(int x, int y, int tileX, int tileY, CancellationToken cancellationToken)
    {
        if (await BuriedAsync(x, y, tileX, tileY, cancellationToken))
        {
            throw new GameException("buried", "Snow buries it: dig it out with a shovel first.");
        }
    }

    /// <summary>The tree planted on a tile: when it is grown, its kind and whether a player planted it by hand (locked until the
    /// transaction ends), or null when none is.</summary>
    private async Task<(DateTimeOffset ReadyAt, TreeKind Kind, bool ByHand)?> PlantedAtAsync(int x, int y, int tileX, int tileY, CancellationToken cancellationToken)
    {
        await using var select = await db.CommandAsync(
            "SELECT ready_at, species, forester_id IS NULL FROM world.plot_trees WHERE x = @x AND y = @y AND tile_x = @tx AND tile_y = @ty FOR UPDATE",
            cancellationToken);
        select.Parameters.AddWithValue("x", x);
        select.Parameters.AddWithValue("y", y);
        select.Parameters.AddWithValue("tx", tileX);
        select.Parameters.AddWithValue("ty", tileY);
        await using var reader = await select.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)
            ? (reader.GetFieldValue<DateTimeOffset>(0), Trees.Of(reader.GetString(1)), reader.GetBoolean(2))
            : null;
    }

    private async Task<Harvest> CutPlantedAsync(
        Guid player, int x, int y, int tileX, int tileY, (DateTimeOffset ReadyAt, TreeKind Kind, bool ByHand) tree, Action<TimeSpan> pace,
        CancellationToken cancellationToken)
    {
        if (tree.ReadyAt > time.GetUtcNow())
        {
            throw new GameException("not_grown", "The tree has not grown yet.");
        }

        // The bark beetle may be in a tree of a monoculture planted by hand.
        var infested = tree.ByHand && (await pests.StateAsync(x, y, cancellationToken)).Infested.Contains((tileX, tileY));
        pace(HarvestRules.TimeFor(tree.Kind.Tile, await RequireToolAsync(player, Items.Axe, cancellationToken))
             / await SpeedAsync(player, Industries.Forestry, cancellationToken));
        await using (var delete = await db.CommandAsync(
            "DELETE FROM world.plot_trees WHERE x = @x AND y = @y AND tile_x = @tx AND tile_y = @ty", cancellationToken))
        {
            delete.Parameters.AddWithValue("x", x);
            delete.Parameters.AddWithValue("y", y);
            delete.Parameters.AddWithValue("tx", tileX);
            delete.Parameters.AddWithValue("ty", tileY);
            await delete.ExecuteNonQueryAsync(cancellationToken);
        }

        await ledger.RecordAsync(player, 0, 1, cancellationToken);
        return await GiveAsync(player, tree.Kind.Tile, Trees.Yield(tree.Kind, Random.Shared.Next(100), Random.Shared.Next(1000), infested), cancellationToken);
    }

    /// <summary>How many times faster the player's clothes make work in an industry (1 for none).</summary>
    public async Task<double> SpeedAsync(Guid player, string? industry, CancellationToken cancellationToken) =>
        industry is null ? 1 : Industries.Speed(await outfit.BonusAsync(player, industry, cancellationToken));

    /// <summary>The tool in the player's tool bar that does the work of <paramref name="tool"/>: a chainsaw does an axe's,
    /// and a bronze or steel pickaxe an iron one's, faster, so the fastest goes first.</summary>
    public async Task<string> RequireToolAsync(Guid player, string tool, CancellationToken cancellationToken)
    {
        var held = await equipment.ToolsAsync(player, cancellationToken);
        if (tool == Items.Axe && held.Contains(Items.Chainsaw))
        {
            return Items.Chainsaw;
        }

        if (tool == Items.Pickaxe && Items.Pickaxes.Where(p => held.Contains(p.Key)).OrderByDescending(p => p.Value).Select(p => p.Key).FirstOrDefault() is { } best)
        {
            return best;
        }

        return held.Contains(tool) ? tool : throw new GameException("wrong_tool", $"You need {Items.Names[tool]} in your hand.");
    }

    private async Task<Harvest> GiveAsync(Guid player, TileObject obj, IReadOnlyList<(string Item, int Quantity)> items, CancellationToken cancellationToken)
    {
        foreach (var (item, quantity) in items)
        {
            await inventory.ReceiveAsync(player, item, quantity, cancellationToken);
        }

        await stats.RecordAsync(player, items.Select(i => ProductionEntry.Made(i.Item, i.Quantity, time.GetUtcNow())).ToList(), cancellationToken);
        var xp = await progress.AddXpAsync(player, HarvestRules.XpPerHarvest, cancellationToken);
        return new Harvest(obj, items, xp);
    }

    /// <summary>Fails with <c>not_owner</c> unless the player owns the plot, or may do <paramref name="right"/>
    /// there as a member of the company the owner brought it into.</summary>
    public async Task<Biome> RequireOwnerAsync(
        Guid player, int x, int y, CancellationToken cancellationToken, PlotRight right = PlotRight.Build)
    {
        if (!(await RightsAsync(player, x, y, cancellationToken)).Contains(right))
        {
            throw new GameException("not_owner", "This is not your plot.");
        }

        return map.BiomeAt(x, y);
    }

    /// <summary>Everything for the owner; for anyone else what their role in the plot's company allows, if anything.</summary>
    public async Task<IReadOnlySet<PlotRight>> RightsAsync(Guid player, int x, int y, CancellationToken cancellationToken)
    {
        if (!map.Contains(x, y))
        {
            throw new GameException("bad_plot", "There is no such plot.");
        }

        await using (var command = await db.CommandAsync("SELECT owner_id FROM world.plots WHERE x = @x AND y = @y", cancellationToken))
        {
            command.Parameters.AddWithValue("x", x);
            command.Parameters.AddWithValue("y", y);
            switch (await command.ExecuteScalarAsync(cancellationToken))
            {
                case Guid owner when owner == player:
                    return AllRights;
                case not Guid:
                    return NoRights;
            }
        }

        var rights = new HashSet<PlotRight>();
        foreach (var company in companies)
        {
            rights.UnionWith(await company.RightsAsync(player, x, y, cancellationToken));
        }

        rights.Remove(PlotRight.Owner);
        return rights;
    }

    private static readonly IReadOnlySet<PlotRight> AllRights = Enum.GetValues<PlotRight>().ToHashSet();

    private static readonly IReadOnlySet<PlotRight> NoRights = new HashSet<PlotRight>();
}

public sealed record EnterRequest(int X, int Y);

public sealed record HarvestRequest(int X, int Y, int TileX, int TileY);

/// <summary>Enters one of the player's plots: its tiles (gzip, base64) and where things stand.</summary>
public sealed class EnterPlotHandler(IServiceScopeFactory scopes, WorldMap map, TimeProvider time) : IMessageHandler
{
    public string Type => "plot.enter";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<EnterRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var rights = await scope.ServiceProvider.GetRequiredService<PlotService>()
            .RightsAsync(client.RequireAccount(), request.X, request.Y, cancellationToken);
        // A fire since the last visit burns its trees before anyone sees them; only those who may enter start the watch.
        var fire = rights.Contains(PlotRight.Work)
            ? await scope.ServiceProvider.GetRequiredService<FireService>().CatchUpAsync(request.X, request.Y, cancellationToken)
            : null;
        var tiles = await scope.ServiceProvider.GetRequiredService<PlotService>()
            .TilesAsync(client.RequireAccount(), request.X, request.Y, cancellationToken);
        var tools = await scope.ServiceProvider.GetRequiredService<IEquipment>().ToolsAsync(client.RequireAccount(), cancellationToken);
        var fields = await scope.ServiceProvider.GetRequiredService<FarmService>().FieldsAsync(request.X, request.Y, cancellationToken);
        var trees = await scope.ServiceProvider.GetRequiredService<ForestService>().TreesAsync(request.X, request.Y, cancellationToken);
        var animals = await scope.ServiceProvider.GetRequiredService<HusbandryService>().AnimalsAsync(request.X, request.Y, cancellationToken);
        var biome = map.BiomeAt(request.X, request.Y);
        var mines = await scope.ServiceProvider.GetRequiredService<MineService>().MinesAsync(request.X, request.Y, biome, cancellationToken);
        var objects = await scope.ServiceProvider.GetRequiredService<PlotObjectService>().ObjectsAsync(request.X, request.Y, cancellationToken);
        var pests = await scope.ServiceProvider.GetRequiredService<PestService>().StateAsync(request.X, request.Y, cancellationToken);
        var certificate = await scope.ServiceProvider.GetRequiredService<ForestLedger>().JsonAsync(client.RequireAccount(), cancellationToken);
        var cities = scope.ServiceProvider.GetRequiredService<CityService>();
        object? city = null;
        if (cities.TownOf(request.X, request.Y) is { } town)
        {
            var level = CityRules.Level(await cities.DeliveredAsync(town, cancellationToken));
            city = new { name = town.Name, population = town.Population, level, levelName = CityRules.LevelNames[level] };
        }

        using var packed = new MemoryStream();
        using (var gzip = new GZipStream(packed, CompressionLevel.Optimal))
        {
            gzip.Write(tiles);
        }

        var (sx, sy, sw, sh) = PlotLayout.Station;
        return new Reply("plot", new
        {
            x = request.X,
            y = request.Y,
            biome = (int)biome,
            rights = rights.Order().Select(r => r.ToString().ToLowerInvariant()),
            size = PlotLayout.Size,
            tileMeters = PlotLayout.TileMeters,
            tiles = Convert.ToBase64String(packed.ToArray()),
            railRow = PlotLayout.RailRow,
            station = new { x = sx, y = sy, width = sw, height = sh },
            spawn = new { x = PlotLayout.Spawn.X, y = PlotLayout.Spawn.Y },
            // The town a city plot belongs to, with its level; null elsewhere.
            city,
            tools = tools.Select(t => new { id = t, name = Items.Names[t] }),
            harvestSeconds = HarvestRules.Time.TotalSeconds,
            // Rocks break and mines are worked this many percent faster here; better pickaxes are faster still.
            miningBonus = Mining.BonusPercent(biome),
            rockSeconds = HarvestRules.TimeFor(TileObject.Rock, Items.Pickaxe, biome).TotalSeconds,
            pickaxes = Items.Pickaxes,
            mineSeconds = (Mining.Time / Mining.Speed(biome)).TotalSeconds,
            mineUnits = Mining.Units,
            mines = mines.Select(MineHandler.MineJson),
            chopSeconds = HarvestRules.ChopTime.TotalSeconds,
            sawSeconds = HarvestRules.SawTime.TotalSeconds,
            treeGrowSeconds = Forestry.GrowTime(biome)?.TotalSeconds,
            trees = trees.Select(PlantTreeHandler.TreeJson),
            // The kinds of tree with their saplings and growing times here, the bark beetle in a monoculture planted by hand,
            // the last forest fire (if recent) with what keeps fires small, and the player's forest certificate.
            treeKinds = PlantTreeHandler.KindsJson(biome),
            pests = PestService.Json(pests),
            fire = fire is null ? null : FireService.Json(fire),
            fires = FireService.RulesJson(biome),
            certificate,
            mushroomRegrowSeconds = Forestry.MushroomRegrow.TotalSeconds,
            objects = objects.Select(PlaceOnPlotHandler.ObjectJson),
            placeable = PlotObjects.Placeable,
            fertile = Farming.Fertile(biome),
            fields = fields.Select(FieldHandler.FieldJson),
            pasture = Husbandry.Pasture(biome),
            husbandryBonus = Husbandry.BonusPercent(biome),
            animals = animals.Select(AnimalHandler.AnimalJson),
            animalKinds = AnimalHandler.KindsJson(biome),
            feed = Husbandry.Feed.Select(f => new { id = f, name = Items.Names[f] }),
            feedPerMeal = Husbandry.FeedPerMeal,
            crops = Farming.Crops.Select(c => new
            {
                id = c.Item,
                name = Items.Names[c.Item],
                growSeconds = c.Grow.TotalSeconds,
                yield = c.Yield,
                xp = c.Xp,
            }),
            // One cast of the rod here, faster on the coast and the lakeshore, and the storm blowing now or the next one.
            fishSeconds = Coast.FishTime(biome).TotalSeconds,
            fishingBonus = Coast.BonusPercent(biome),
            storm = StormJson(time.GetUtcNow()),
            storms = StormsJson(time.GetUtcNow(), 24),
            // The sun over every plot (a day of dayMs from epoch, the first daylightMs of it light), and on sand the sandstorms to come.
            sun = new
            {
                epoch = SeaWeather.Epoch.ToUnixTimeMilliseconds(),
                dayMs = (long)Sun.DayLength.TotalMilliseconds,
                daylightMs = (long)Sun.Daylight.TotalMilliseconds,
            },
            sandstorms = Oasis.Sandy((int)biome) ? SandstormsJson(time.GetUtcNow(), 12) : [],
            // On the glacier: the blizzards to come (turbines stop, ice freezes again, avalanches leave snow), the last one's window
            // for working out where its snow lies, and the frost that slows machines no heater warms.
            blizzards = biome == Biome.Ice ? BlizzardsJson(time.GetUtcNow(), 8) : [],
            frost = Frost.Freezes((int)biome) ? new { speed = Frost.Speed, heaterReach = Frost.HeaterReach } : null,
            bridgeBeams = PlotLayout.BridgeBeams,
            // On the glacier and the tundra: the nights the aurora shines, when tourists pay three times as much.
            auroras = Aurora.Seen((int)biome) ? AurorasJson(time.GetUtcNow(), 6) : [],
            serverTime = time.GetUtcNow().ToUnixTimeMilliseconds(),
        });
    }

    public static object StormJson(DateTimeOffset now)
    {
        var (start, end) = SeaWeather.Next(now);
        return new { start = start.ToUnixTimeMilliseconds(), end = end.ToUnixTimeMilliseconds() };
    }

    /// <summary>The storm blowing now (if any) and the next ones, <paramref name="count"/> in all, for the client's forecast.</summary>
    public static IReadOnlyList<object> StormsJson(DateTimeOffset now, int count)
    {
        var storms = new List<object>();
        var at = now;
        for (var i = 0; i < count; i++)
        {
            var (start, end) = SeaWeather.Next(at);
            storms.Add(new { start = start.ToUnixTimeMilliseconds(), end = end.ToUnixTimeMilliseconds() });
            at = end;
        }

        return storms;
    }

    /// <summary>The blizzard blowing now (if any) and the next ones, <paramref name="count"/> in all.</summary>
    public static IReadOnlyList<object> BlizzardsJson(DateTimeOffset now, int count)
    {
        var storms = new List<object>();
        var at = now;
        for (var i = 0; i < count; i++)
        {
            var (start, end) = Blizzard.Next(at);
            storms.Add(new { start = start.ToUnixTimeMilliseconds(), end = end.ToUnixTimeMilliseconds() });
            at = end;
        }

        return storms;
    }

    /// <summary>The aurora shining now (if it does) and the next ones, <paramref name="count"/> in all.</summary>
    public static IReadOnlyList<object> AurorasJson(DateTimeOffset now, int count)
    {
        var nights = new List<object>();
        var at = now;
        for (var i = 0; i < count; i++)
        {
            var (start, end) = Aurora.Next(at);
            nights.Add(new { start = start.ToUnixTimeMilliseconds(), end = end.ToUnixTimeMilliseconds() });
            at = end;
        }

        return nights;
    }

    /// <summary>The sandstorm blowing now (if any) and the next ones, <paramref name="count"/> in all.</summary>
    public static IReadOnlyList<object> SandstormsJson(DateTimeOffset now, int count)
    {
        var storms = new List<object>();
        var at = now;
        for (var i = 0; i < count; i++)
        {
            var (start, end) = SandWeather.Next(at);
            storms.Add(new { start = start.ToUnixTimeMilliseconds(), end = end.ToUnixTimeMilliseconds() });
            at = end;
        }

        return storms;
    }
}

public sealed class HarvestHandler(IServiceScopeFactory scopes, TimeProvider time) : IMessageHandler
{
    private const string LastHarvest = "world.lastHarvest";

    public string Type => "plot.harvest";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<HarvestRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var harvest = await scope.ServiceProvider.GetRequiredService<PlotService>().HarvestAsync(
            client.RequireAccount(), request.X, request.Y, request.TileX, request.TileY, work => CheckPace(client, time, work), cancellationToken);
        Swung(client, time);
        return new Reply("plot.harvested", new
        {
            tileX = request.TileX,
            tileY = request.TileY,
            // What was gathered, e.g. "bridge" for a bridge laid over a crevasse.
            @object = harvest.Object.ToString().ToLowerInvariant(),
            items = harvest.Items.Select(i => new { id = i.Item, name = Items.Names[i.Item], quantity = i.Quantity }),
            xp = new { xp = harvest.Xp.Xp, level = harvest.Xp.Level, leveledUp = harvest.Xp.LeveledUp },
        });
    }

    /// <summary>Refuses work that ends before it could have been done since the last one ended.</summary>
    public static void CheckPace(ClientContext client, TimeProvider time, TimeSpan work)
    {
        // A small tolerance for network jitter between the client's swing and the request.
        if (client.Items.GetValueOrDefault(LastHarvest) is DateTimeOffset last && time.GetUtcNow() - last < work * 0.8)
        {
            throw new GameException("too_fast", "Wait until the last swing is done.");
        }
    }

    public static void Swung(ClientContext client, TimeProvider time) => client.Items[LastHarvest] = time.GetUtcNow();
}
