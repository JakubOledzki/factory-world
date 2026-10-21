using System.IO.Compression;
using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

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
    private const int ClearRows = 12;

    /// <summary>Chance (per mille) of each object on a tile, by biome; scaled by a patchy noise.</summary>
    private static readonly IReadOnlyDictionary<Biome, (TileObject Object, int PerMille)[]> Nature = new Dictionary<Biome, (TileObject, int)[]>
    {
        [Biome.Forest] = [(TileObject.Tree, 380), (TileObject.Rock, 8), (TileObject.Bush, 30)],
        [Biome.Farmland] = [(TileObject.Tree, 25), (TileObject.Bush, 25), (TileObject.Rock, 4)],
        [Biome.Grassland] = [(TileObject.Tree, 15), (TileObject.Bush, 40), (TileObject.Rock, 10)],
        [Biome.Desert] = [(TileObject.Dune, 90), (TileObject.Rock, 18), (TileObject.Bush, 6)],
        [Biome.Mountains] = [(TileObject.Rock, 260), (TileObject.Tree, 45), (TileObject.Bush, 10)],
        [Biome.Tundra] = [(TileObject.Rock, 40), (TileObject.Bush, 35), (TileObject.Tree, 8)],
        [Biome.Ice] = [(TileObject.Rock, 25)],
        [Biome.City] = [],
        [Biome.Coast] = [(TileObject.Tree, 50), (TileObject.Dune, 30), (TileObject.Rock, 15)],
        [Biome.Lakeshore] = [(TileObject.Tree, 90), (TileObject.Bush, 40), (TileObject.Rock, 10)],
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

        for (var x = 0; x < Size; x++)
        {
            tiles[RailRow * Size + x] = (byte)TileObject.Rail;
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

    /// <summary>Which tool a player needs to gather an object, or null when it cannot be gathered.</summary>
    public static string? ToolFor(TileObject obj) => obj switch
    {
        TileObject.Tree => Items.Axe,
        TileObject.Rock => Items.Pickaxe,
        TileObject.Dune => Items.Shovel,
        _ => null,
    };

    /// <summary>The tool a player gets with a newly bought plot of a biome, or null.</summary>
    public static string? StarterTool(Biome biome) => biome switch
    {
        Biome.Forest => Items.Axe,
        Biome.Desert => Items.Shovel,
        Biome.Mountains => Items.Pickaxe,
        Biome.Farmland => Items.Hoe,
        _ => null,
    };

    /// <summary>What gathering an object gives, for a roll of 0-99.</summary>
    public static IReadOnlyList<(string Item, int Quantity)> Yield(TileObject obj, int roll) => obj switch
    {
        TileObject.Tree => [(Items.Wood, 3)],
        TileObject.Dune => [(Items.Sand, 3)],
        TileObject.Rock => roll switch
        {
            < 5 => [(Items.Stone, 2), (Items.CopperOre, 1)],
            < 15 => [(Items.Stone, 2), (Items.IronOre, 1)],
            < 30 => [(Items.Stone, 2), (Items.Coal, 1)],
            _ => [(Items.Stone, 2)],
        },
        _ => [],
    };

    private static uint Hash(uint seed, int x, int y)
    {
        var h = seed ^ (uint)x * 0x27d4eb2du ^ (uint)y * 0x165667b1u;
        h ^= h >> 15;
        h *= 0x85ebca6bu;
        h ^= h >> 13;
        h *= 0xc2b2ae35u;
        return h ^ (h >> 16);
    }

    /// <summary>Smooth value noise in 0..1.</summary>
    private static double Noise(uint seed, double x, double y)
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

    public const int XpPerHarvest = 2;
}

public sealed record Harvest(TileObject Object, IReadOnlyList<(string Item, int Quantity)> Items, XpGain Xp);

public sealed class PlotService(GameDb db, WorldMap map, IInventory inventory, IEquipment equipment, ICharacterProgress progress)
{
    /// <summary>The tiles of a plot as they are now; only its owner may enter.</summary>
    public async Task<byte[]> TilesAsync(Guid player, int x, int y, CancellationToken cancellationToken)
    {
        var biome = await RequireOwnerAsync(player, x, y, cancellationToken);
        var tiles = PlotLayout.Generate(x, y, biome);
        await using var command = await db.CommandAsync(
            "SELECT tile_x, tile_y FROM world.plot_harvests WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            tiles[reader.GetInt32(1) * PlotLayout.Size + reader.GetInt32(0)] = (byte)TileObject.None;
        }

        return tiles;
    }

    /// <summary>Cuts a tree, breaks a rock or digs a dune with the tool in the player's slot.</summary>
    public Task<Harvest> HarvestAsync(Guid player, int x, int y, int tileX, int tileY, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var biome = await RequireOwnerAsync(player, x, y, cancellationToken);
            if (!PlotLayout.Inside(tileX, tileY))
            {
                throw new GameException("nothing_here", "There is nothing to gather here.");
            }

            var obj = (TileObject)PlotLayout.Generate(x, y, biome)[tileY * PlotLayout.Size + tileX];
            var tool = PlotLayout.ToolFor(obj) ?? throw new GameException("nothing_here", "There is nothing to gather here.");
            if (await equipment.ToolAsync(player, cancellationToken) != tool)
            {
                throw new GameException("wrong_tool", $"You need {Items.Names[tool]} in your hand.");
            }

            await using (var insert = await db.CommandAsync(
                "INSERT INTO world.plot_harvests (x, y, tile_x, tile_y) VALUES (@x, @y, @tx, @ty) ON CONFLICT DO NOTHING", cancellationToken))
            {
                insert.Parameters.AddWithValue("x", x);
                insert.Parameters.AddWithValue("y", y);
                insert.Parameters.AddWithValue("tx", tileX);
                insert.Parameters.AddWithValue("ty", tileY);
                if (await insert.ExecuteNonQueryAsync(cancellationToken) == 0)
                {
                    throw new GameException("nothing_here", "This has already been gathered.");
                }
            }

            var items = PlotLayout.Yield(obj, Random.Shared.Next(100));
            foreach (var (item, quantity) in items)
            {
                await inventory.AddAsync(player, item, quantity, cancellationToken);
            }

            var xp = await progress.AddXpAsync(player, HarvestRules.XpPerHarvest, cancellationToken);
            return new Harvest(obj, items, xp);
        }, cancellationToken);

    public async Task<Biome> RequireOwnerAsync(Guid player, int x, int y, CancellationToken cancellationToken)
    {
        if (!map.Contains(x, y))
        {
            throw new GameException("bad_plot", "There is no such plot.");
        }

        await using var command = await db.CommandAsync("SELECT owner_id FROM world.plots WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        if (await command.ExecuteScalarAsync(cancellationToken) is not Guid owner || owner != player)
        {
            throw new GameException("not_owner", "This is not your plot.");
        }

        return map.BiomeAt(x, y);
    }
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
        var tiles = await scope.ServiceProvider.GetRequiredService<PlotService>()
            .TilesAsync(client.RequireAccount(), request.X, request.Y, cancellationToken);
        var tool = await scope.ServiceProvider.GetRequiredService<IEquipment>().ToolAsync(client.RequireAccount(), cancellationToken);
        var fields = await scope.ServiceProvider.GetRequiredService<FarmService>().FieldsAsync(request.X, request.Y, cancellationToken);
        var biome = map.BiomeAt(request.X, request.Y);

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
            size = PlotLayout.Size,
            tileMeters = PlotLayout.TileMeters,
            tiles = Convert.ToBase64String(packed.ToArray()),
            railRow = PlotLayout.RailRow,
            station = new { x = sx, y = sy, width = sw, height = sh },
            spawn = new { x = PlotLayout.Spawn.X, y = PlotLayout.Spawn.Y },
            tool = tool is null ? null : new { id = tool, name = Items.Names[tool] },
            harvestSeconds = HarvestRules.Time.TotalSeconds,
            fertile = Farming.Fertile(biome),
            fields = fields.Select(FieldHandler.FieldJson),
            crops = Farming.Crops.Select(c => new
            {
                id = c.Item,
                name = Items.Names[c.Item],
                growSeconds = c.Grow.TotalSeconds,
                yield = c.Yield,
                xp = c.Xp,
            }),
            serverTime = time.GetUtcNow().ToUnixTimeMilliseconds(),
        });
    }
}

public sealed class HarvestHandler(IServiceScopeFactory scopes, TimeProvider time) : IMessageHandler
{
    private const string LastHarvest = "world.lastHarvest";

    public string Type => "plot.harvest";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<HarvestRequest>(payload);
        CheckPace(client, time);
        await using var scope = scopes.CreateAsyncScope();
        var harvest = await scope.ServiceProvider.GetRequiredService<PlotService>()
            .HarvestAsync(client.RequireAccount(), request.X, request.Y, request.TileX, request.TileY, cancellationToken);
        Swung(client, time);
        return new Reply("plot.harvested", new
        {
            tileX = request.TileX,
            tileY = request.TileY,
            items = harvest.Items.Select(i => new { id = i.Item, name = Items.Names[i.Item], quantity = i.Quantity }),
            xp = new { xp = harvest.Xp.Xp, level = harvest.Xp.Level, leveledUp = harvest.Xp.LeveledUp },
        });
    }

    /// <summary>Refuses a swing of a tool that comes before the last one could be done.</summary>
    public static void CheckPace(ClientContext client, TimeProvider time)
    {
        // A small tolerance for network jitter between the client's swing and the request.
        if (client.Items.GetValueOrDefault(LastHarvest) is DateTimeOffset last && time.GetUtcNow() - last < HarvestRules.Time * 0.8)
        {
            throw new GameException("too_fast", "Wait until the last swing is done.");
        }
    }

    public static void Swung(ClientContext client, TimeProvider time) => client.Items[LastHarvest] = time.GetUtcNow();
}
