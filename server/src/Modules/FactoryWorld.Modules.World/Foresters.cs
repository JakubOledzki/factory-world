using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;
using NpgsqlTypes;

namespace FactoryWorld.Modules.World;

/// <summary>How a forester's building of one level works.</summary>
/// <param name="Radius">Its forest reaches this many tiles from its own tile each way: a square of 2 × Radius + 1.</param>
/// <param name="Capacity">Most wood it keeps; full, it stops cutting until wood is taken out.</param>
/// <param name="GrowSpeed">How many times faster than on its own a tree grows in its care.</param>
/// <param name="CutTime">How long it takes to cut one tree; it cuts one after another.</param>
public sealed record ForesterLevel(string Kind, int Level, int Radius, int Capacity, double GrowSpeed, TimeSpan CutTime);

/// <summary>
/// A forester's building stands on 3 × 3 tiles of a plot and keeps a forest in the square around it:
/// it plants a sapling on every free tile there, cuts each tree once it has grown and plants a new one
/// in its place. Trees that grew there by themselves it cuts first. It keeps a clearing one tile wide
/// around itself and a path three tiles wide from its door (the way it faces) to the edge of its forest,
/// so the player can walk up to it and belts can carry the wood away. The wood waits in it until taken out
/// by hand or by an inserter standing next to it. The lodge and the forestry station are the same,
/// only with a bigger forest that grows faster, quicker cutting and room for more wood.
/// </summary>
public static class Foresters
{
    public static readonly IReadOnlyList<ForesterLevel> Levels =
    [
        new(Items.ForesterHut, 1, 5, 100, 1, TimeSpan.FromSeconds(6)),
        new(Items.ForesterLodge, 2, 6, 200, 1.5, TimeSpan.FromSeconds(3)),
        new(Items.ForestryStation, 3, 7, 400, 2, TimeSpan.FromSeconds(1.5)),
    ];

    public static ForesterLevel? Level(string kind) => Levels.FirstOrDefault(l => l.Kind == kind);

    /// <summary>The clearing around the building reaches this far from its tile: the building itself and one tile more.</summary>
    public const int Clearing = 2;

    /// <summary>Wood taken out by hand gives one experience point for every this many.</summary>
    public const int WoodPerXp = 4;

    /// <summary>How long a sapling grows in its care on a plot of <paramref name="biome"/>; null where nothing grows.</summary>
    public static TimeSpan? GrowTime(ForesterLevel level, Biome biome) => Forestry.GrowTime(biome) / level.GrowSpeed;

    /// <summary>The way the door faces, as (dx, dy): 0 south, 1 east, 2 north, 3 west.</summary>
    public static (int Dx, int Dy) Facing(int rotation) => (rotation & 3) switch
    {
        0 => (0, 1),
        1 => (1, 0),
        2 => (0, -1),
        _ => (-1, 0),
    };

    /// <summary>Whether it plants on the tile (dx, dy) away from its own: inside its square, outside its clearing and path.</summary>
    public static bool Plants(ForesterLevel level, int rotation, int dx, int dy)
    {
        if (!Claims(level, dx, dy) || (Math.Abs(dx) <= Clearing && Math.Abs(dy) <= Clearing))
        {
            return false;
        }

        var (fx, fy) = Facing(rotation);
        return !(dx * fx + dy * fy > 0 && Math.Abs(dx * fy - dy * fx) <= Footprints.Reach(level.Kind));
    }

    /// <summary>Whether the tile (dx, dy) away from its own is in its square at all.</summary>
    public static bool Claims(ForesterLevel level, int dx, int dy) => Math.Abs(dx) <= level.Radius && Math.Abs(dy) <= level.Radius;

    /// <summary>
    /// The tiles of the plot each forester plants on. Where the squares of two meet, a tile belongs to the
    /// one that comes first from north to south, west to east; no forester plants on another's clearing or path.
    /// </summary>
    public static IReadOnlyDictionary<Guid, List<(int X, int Y)>> Areas(IReadOnlyList<PlotObject> foresters)
    {
        var ordered = foresters.OrderBy(f => f.TileY).ThenBy(f => f.TileX).ThenBy(f => f.Id).ToList();
        var areas = new Dictionary<Guid, List<(int, int)>>();
        var taken = new HashSet<(int, int)>();
        foreach (var f in ordered)
        {
            var level = Level(f.Kind)!;
            var tiles = new List<(int, int)>();
            for (var dy = -level.Radius; dy <= level.Radius; dy++)
            {
                for (var dx = -level.Radius; dx <= level.Radius; dx++)
                {
                    var (x, y) = (f.TileX + dx, f.TileY + dy);
                    if (!PlotLayout.Inside(x, y) || !Plants(level, f.Rotation, dx, dy) || taken.Contains((x, y)))
                    {
                        continue;
                    }

                    var kept = ordered.Any(o => o.Id != f.Id && Level(o.Kind) is { } other
                        && Claims(other, x - o.TileX, y - o.TileY) && !Plants(other, o.Rotation, x - o.TileX, y - o.TileY));
                    if (!kept)
                    {
                        tiles.Add((x, y));
                        taken.Add((x, y));
                    }
                }
            }

            areas[f.Id] = tiles;
        }

        return areas;
    }
}

/// <summary>
/// One forester's forest as it works through time, in memory: worked out up to a moment from the trees
/// standing in it, then written back. Times only ever move forward.
/// </summary>
/// <param name="busyUntil">When it is done with the tree it cuts now, or could start the next one.</param>
public sealed class ForestPatch(ForesterLevel level, TimeSpan grow, int wood, DateTimeOffset busyUntil)
{
    public ForesterLevel ForesterLevel { get; } = level;

    public int Wood { get; private set; } = wood;

    public DateTimeOffset BusyUntil { get; private set; } = busyUntil;

    /// <summary>Planted trees in its forest and when each has grown.</summary>
    public Dictionary<(int X, int Y), DateTimeOffset> Trees { get; } = [];

    /// <summary>Trees that grew in its forest by themselves and stand there still.</summary>
    public HashSet<(int X, int Y)> Wild { get; } = [];

    /// <summary>Free tiles of its forest, to be planted the next time it works.</summary>
    public HashSet<(int X, int Y)> Open { get; } = [];

    /// <summary>Tiles whose tree it planted, as rows to write.</summary>
    public HashSet<(int X, int Y)> Planted { get; } = [];

    /// <summary>Tiles whose wild tree it cut, to be marked as gathered.</summary>
    public HashSet<(int X, int Y)> Cleared { get; } = [];

    /// <summary>Wood it cut, for the production statistics.</summary>
    public List<ProductionEntry> Made { get; } = [];

    public bool Changed { get; private set; }

    public bool Full => Wood >= ForesterLevel.Capacity;

    /// <summary>Plants the free tiles at <paramref name="now"/>, then cuts every tree it could have cut by then.</summary>
    public void Advance(DateTimeOffset now)
    {
        foreach (var tile in Open)
        {
            Trees[tile] = now + grow;
            Planted.Add(tile);
            Changed = true;
        }

        Open.Clear();
        if (Full || NextCut() is not { } next || next > now)
        {
            return;
        }

        // Wild trees are ready from the start, so they come first.
        var queue = new PriorityQueue<(int X, int Y), DateTimeOffset>();
        foreach (var tile in Wild)
        {
            queue.Enqueue(tile, DateTimeOffset.MinValue);
        }

        foreach (var (tile, ready) in Trees)
        {
            if (ready + ForesterLevel.CutTime <= now)
            {
                queue.Enqueue(tile, ready);
            }
        }

        while (!Full && queue.TryPeek(out var tile, out var ready))
        {
            var done = (ready > BusyUntil ? ready : BusyUntil) + ForesterLevel.CutTime;
            if (done > now)
            {
                break;
            }

            queue.Dequeue();
            Wood++;
            BusyUntil = done;
            Made.Add(ProductionEntry.Made(Items.Wood, 1, done));
            if (Wild.Remove(tile))
            {
                Cleared.Add(tile);
            }

            // A new sapling goes in at once where the tree stood.
            var grown = done + grow;
            Trees[tile] = grown;
            Planted.Add(tile);
            if (grown + ForesterLevel.CutTime <= now)
            {
                queue.Enqueue(tile, grown);
            }
        }

        Changed = true;
    }

    /// <summary>When it will next have a tree cut, if it has room for the wood; null when its forest is empty.</summary>
    public DateTimeOffset? NextCut()
    {
        DateTimeOffset? first = Wild.Count > 0 ? DateTimeOffset.MinValue : null;
        foreach (var ready in Trees.Values)
        {
            if (first is null || ready < first)
            {
                first = ready;
            }
        }

        return first is { } at ? (at > BusyUntil ? at : BusyUntil) + ForesterLevel.CutTime : null;
    }

    /// <summary>Takes wood out at <paramref name="now"/>; one that stood full starts cutting again only from then.</summary>
    public int Take(int quantity, DateTimeOffset now)
    {
        var taken = Math.Min(quantity, Wood);
        if (taken == 0)
        {
            return 0;
        }

        if (Full && BusyUntil < now)
        {
            BusyUntil = now;
        }

        Wood -= taken;
        Changed = true;
        return taken;
    }
}

/// <summary>A forester on its plot with its forest.</summary>
public sealed record ForesterOnPlot(PlotObject Object, ForestPatch Patch);

/// <summary>All the foresters of one plot, read and locked until the transaction ends.</summary>
public sealed record PlotForests(int X, int Y, IReadOnlyList<ForesterOnPlot> Foresters, IReadOnlyList<PlantedTree> Trees, IReadOnlyList<(int X, int Y)> Cleared);

public sealed class ForesterService(
    GameDb db, WorldMap map, PlotService plots, IPlotObjects objects, IInventory inventory, ICharacterProgress progress, IProductionStats stats,
    TimeProvider time) : IPlacedHook, IPlotAutomation, IMachineContents, IMachinePorts, IMachineStatuses
{
    /// <summary>The plot's foresters worked up to now, with every planted tree and the wild trees they cut.</summary>
    public Task<PlotForests> StateAsync(Guid player, int x, int y, IEnumerable<IPlotAutomation> automation, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Work);
            // Inserters take wood out of foresters; they go first so the wood they took is gone.
            foreach (var machinery in automation)
            {
                await machinery.CatchUpAsync(x, y, cancellationToken);
            }

            return await ReportAsync(x, y, cancellationToken);
        }, cancellationToken);

    /// <summary>Takes all the wood out of a forester on the player's plot into the inventory.</summary>
    public Task<(PlotForests State, int Taken, XpGain? Xp)> TakeAsync(
        Guid player, int x, int y, Guid id, IEnumerable<IPlotAutomation> automation, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Take);
            foreach (var machinery in automation)
            {
                await machinery.CatchUpAsync(x, y, cancellationToken);
            }

            var now = time.GetUtcNow();
            var forests = await OpenAsync(x, y, now, cancellationToken);
            var forester = forests.FirstOrDefault(f => f.Object.Id == id)
                ?? throw new GameException("no_object", "There is no such forester's building on this plot.");
            var taken = forester.Patch.Take(int.MaxValue, now);
            // Room again: what waited on the full store is cut from now on.
            forester.Patch.Advance(now);
            await SaveAsync(x, y, forests, cancellationToken);
            XpGain? xp = null;
            if (taken > 0)
            {
                await inventory.AddAsync(player, Items.Wood, taken, cancellationToken);
                xp = await progress.AddXpAsync(player, taken / Foresters.WoodPerXp, cancellationToken);
            }

            return (await ReportAsync(x, y, cancellationToken), taken, xp);
        }, cancellationToken);

    public async Task PlacedAsync(Guid owner, int x, int y, PlacedOnPlot placed, CancellationToken cancellationToken)
    {
        if (!Items.IsForester(placed.Kind))
        {
            return;
        }

        await using (var insert = await db.CommandAsync(
            """
            INSERT INTO world.plot_foresters (object_id, x, y, owner_id, wood, busy_until)
            VALUES (@id, @x, @y, @owner, 0, @now) ON CONFLICT DO NOTHING
            """, cancellationToken))
        {
            insert.Parameters.AddWithValue("id", placed.Id);
            insert.Parameters.AddWithValue("x", x);
            insert.Parameters.AddWithValue("y", y);
            insert.Parameters.AddWithValue("owner", owner);
            insert.Parameters.AddWithValue("now", time.GetUtcNow());
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }

        // It plants its forest at once.
        await CatchUpAsync(x, y, cancellationToken);
    }

    /// <summary>Works every forester of the plot up to now; called before anything is put on the plot or taken off.</summary>
    public async Task CatchUpAsync(int x, int y, CancellationToken cancellationToken)
    {
        var now = time.GetUtcNow();
        var forests = await OpenAsync(x, y, now, cancellationToken);
        foreach (var forester in forests)
        {
            forester.Patch.Advance(now);
        }

        await SaveAsync(x, y, forests, cancellationToken);
    }

    /// <summary>The forester is being picked up (worked up to now just before): its wood goes to the player,
    /// and the forest it planted goes with it.</summary>
    public async Task ReleaseAsync(Guid owner, Guid id, CancellationToken cancellationToken)
    {
        await using (var trees = await db.CommandAsync("DELETE FROM world.plot_trees WHERE forester_id = @id", cancellationToken))
        {
            trees.Parameters.AddWithValue("id", id);
            await trees.ExecuteNonQueryAsync(cancellationToken);
        }

        await using var delete = await db.CommandAsync("DELETE FROM world.plot_foresters WHERE object_id = @id RETURNING wood", cancellationToken);
        delete.Parameters.AddWithValue("id", id);
        if (await delete.ExecuteScalarAsync(cancellationToken) is int wood && wood > 0)
        {
            await inventory.AddAsync(owner, Items.Wood, wood, cancellationToken);
        }
    }

    public async Task<IMachinePort?> OpenAsync(Guid owner, Guid id, string kind, CancellationToken cancellationToken)
    {
        if (!Items.IsForester(kind) || await objects.PlotOfAsync(id, cancellationToken) is not var (x, y))
        {
            return null;
        }

        // Inserters run from where the plot's logistics were left, so the forester starts from its last state.
        var forests = await OpenAsync(x, y, null, cancellationToken);
        return forests.FirstOrDefault(f => f.Object.Id == id) is { } forester ? new Port(this, x, y, forests, forester.Patch) : null;
    }

    public async Task<IReadOnlyList<MachineStatus>> StatusesAsync(Guid owner, CancellationToken cancellationToken)
    {
        var plotsOf = new List<(int X, int Y)>();
        await using (var command = await db.CommandAsync(
            "SELECT DISTINCT x, y FROM world.plot_foresters WHERE owner_id = @owner", cancellationToken))
        {
            command.Parameters.AddWithValue("owner", owner);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                plotsOf.Add((reader.GetInt32(0), reader.GetInt32(1)));
            }
        }

        var statuses = new List<MachineStatus>();
        var now = time.GetUtcNow();
        foreach (var (x, y) in plotsOf)
        {
            var forests = await OpenAsync(x, y, now, cancellationToken);
            foreach (var forester in forests)
            {
                forester.Patch.Advance(now);
            }

            await SaveAsync(x, y, forests, cancellationToken);
            statuses.AddRange(forests.Where(f => f.Object.Owner == owner).Select(f => new MachineStatus(
                f.Object.Id, f.Object.Kind, Items.Wood, f.Patch.Full ? MachineActivity.OutputFull : MachineActivity.Working, [])));
        }

        return statuses;
    }

    /// <summary>The foresters of a plot with their forests, locked until the transaction ends. A forester
    /// whose row is missing starts empty from <paramref name="now"/> (or the time now when null).</summary>
    private async Task<List<ForesterOnPlot>> OpenAsync(int x, int y, DateTimeOffset? now, CancellationToken cancellationToken)
    {
        var all = await objects.ObjectsAsync(x, y, cancellationToken);
        var foresters = all.Where(o => Items.IsForester(o.Kind)).ToList();
        if (foresters.Count == 0)
        {
            return [];
        }

        var rows = new Dictionary<Guid, (int Wood, DateTimeOffset BusyUntil)>();
        await using (var command = await db.CommandAsync(
            "SELECT object_id, wood, busy_until FROM world.plot_foresters WHERE x = @x AND y = @y ORDER BY object_id FOR UPDATE", cancellationToken))
        {
            command.Parameters.AddWithValue("x", x);
            command.Parameters.AddWithValue("y", y);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                rows[reader.GetGuid(0)] = (reader.GetInt32(1), reader.GetFieldValue<DateTimeOffset>(2));
            }
        }

        var biome = map.BiomeAt(x, y);
        var tiles = await plots.TilesAsync(x, y, biome, cancellationToken);
        var trees = await PlantedAsync(x, y, cancellationToken);
        var taken = new HashSet<(int, int)>();
        foreach (var o in all)
        {
            taken.UnionWith(Footprints.Tiles(o.Kind, o.TileX, o.TileY));
        }

        foreach (var table in new[] { "plot_fields", "plot_animals" })
        {
            await using var command = await db.CommandAsync($"SELECT tile_x, tile_y FROM world.{table} WHERE x = @x AND y = @y", cancellationToken);
            command.Parameters.AddWithValue("x", x);
            command.Parameters.AddWithValue("y", y);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                taken.Add((reader.GetInt32(0), reader.GetInt32(1)));
            }
        }

        taken.Add(PlotLayout.Spawn);
        var areas = Foresters.Areas(foresters);
        var start = now ?? time.GetUtcNow();
        var result = new List<ForesterOnPlot>();
        foreach (var o in foresters)
        {
            var level = Foresters.Level(o.Kind)!;
            var (wood, busyUntil) = rows.GetValueOrDefault(o.Id, (0, start));
            var patch = new ForestPatch(level, Foresters.GrowTime(level, biome) ?? Forestry.Grow, wood, busyUntil);
            foreach (var tile in areas[o.Id])
            {
                if (trees.TryGetValue(tile, out var ready))
                {
                    patch.Trees[tile] = ready;
                }
                else if (taken.Contains(tile))
                {
                    continue;
                }
                else if (tiles[tile.Y * PlotLayout.Size + tile.X] == (byte)TileObject.Tree)
                {
                    patch.Wild.Add(tile);
                }
                else if (tiles[tile.Y * PlotLayout.Size + tile.X] == (byte)TileObject.None)
                {
                    patch.Open.Add(tile);
                }
            }

            result.Add(new ForesterOnPlot(o, patch));
        }

        return result;
    }

    private async Task<Dictionary<(int X, int Y), DateTimeOffset>> PlantedAsync(int x, int y, CancellationToken cancellationToken)
    {
        var trees = new Dictionary<(int, int), DateTimeOffset>();
        await using var command = await db.CommandAsync(
            "SELECT tile_x, tile_y, ready_at FROM world.plot_trees WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            trees[(reader.GetInt32(0), reader.GetInt32(1))] = reader.GetFieldValue<DateTimeOffset>(2);
        }

        return trees;
    }

    /// <summary>Writes back the foresters that worked: their wood, the trees they planted, the wild ones they cut.</summary>
    private async Task SaveAsync(int x, int y, IReadOnlyList<ForesterOnPlot> forests, CancellationToken cancellationToken)
    {
        foreach (var (o, patch) in forests.Where(f => f.Patch.Changed).Select(f => (f.Object, f.Patch)))
        {
            await using (var update = await db.CommandAsync(
                """
                INSERT INTO world.plot_foresters (object_id, x, y, owner_id, wood, busy_until) VALUES (@id, @x, @y, @owner, @wood, @busy)
                ON CONFLICT (object_id) DO UPDATE SET wood = @wood, busy_until = @busy
                """, cancellationToken))
            {
                update.Parameters.AddWithValue("id", o.Id);
                update.Parameters.AddWithValue("x", x);
                update.Parameters.AddWithValue("y", y);
                update.Parameters.AddWithValue("owner", o.Owner);
                update.Parameters.AddWithValue("wood", patch.Wood);
                update.Parameters.AddWithValue("busy", patch.BusyUntil);
                await update.ExecuteNonQueryAsync(cancellationToken);
            }

            if (patch.Planted.Count > 0)
            {
                var planted = patch.Planted.ToList();
                await using var trees = await db.CommandAsync(
                    """
                    INSERT INTO world.plot_trees (x, y, tile_x, tile_y, ready_at, forester_id)
                    SELECT @x, @y, t.tx, t.ty, t.ready, @forester FROM unnest(@txs, @tys, @readies) AS t(tx, ty, ready)
                    ON CONFLICT (x, y, tile_x, tile_y) DO UPDATE SET ready_at = EXCLUDED.ready_at, forester_id = EXCLUDED.forester_id
                    """, cancellationToken);
                trees.Parameters.AddWithValue("forester", o.Id);
                trees.Parameters.AddWithValue("x", x);
                trees.Parameters.AddWithValue("y", y);
                trees.Parameters.AddWithValue("txs", planted.Select(t => t.X).ToArray());
                trees.Parameters.AddWithValue("tys", planted.Select(t => t.Y).ToArray());
                trees.Parameters.Add(new Npgsql.NpgsqlParameter("readies", NpgsqlDbType.Array | NpgsqlDbType.TimestampTz)
                {
                    Value = planted.Select(t => patch.Trees[t]).ToArray(),
                });
                await trees.ExecuteNonQueryAsync(cancellationToken);
                patch.Planted.Clear();
            }

            if (patch.Cleared.Count > 0)
            {
                var cleared = patch.Cleared.ToList();
                await using var harvests = await db.CommandAsync(
                    """
                    INSERT INTO world.plot_harvests (x, y, tile_x, tile_y)
                    SELECT @x, @y, t.tx, t.ty FROM unnest(@txs, @tys) AS t(tx, ty) ON CONFLICT DO NOTHING
                    """, cancellationToken);
                harvests.Parameters.AddWithValue("x", x);
                harvests.Parameters.AddWithValue("y", y);
                harvests.Parameters.AddWithValue("txs", cleared.Select(t => t.X).ToArray());
                harvests.Parameters.AddWithValue("tys", cleared.Select(t => t.Y).ToArray());
                await harvests.ExecuteNonQueryAsync(cancellationToken);
                patch.Cleared.Clear();
            }

            if (patch.Made.Count > 0)
            {
                await stats.RecordAsync(o.Owner, patch.Made.ToList(), cancellationToken);
                patch.Made.Clear();
            }
        }
    }

    /// <summary>The foresters as they stand now, every planted tree of the plot and the wild trees cut in their squares.</summary>
    private async Task<PlotForests> ReportAsync(int x, int y, CancellationToken cancellationToken)
    {
        var now = time.GetUtcNow();
        var forests = await OpenAsync(x, y, now, cancellationToken);
        foreach (var forester in forests)
        {
            forester.Patch.Advance(now);
        }

        await SaveAsync(x, y, forests, cancellationToken);
        var trees = (await PlantedAsync(x, y, cancellationToken)).Select(t => new PlantedTree(t.Key.X, t.Key.Y, t.Value)).ToList();
        var cleared = new List<(int, int)>();
        if (forests.Count > 0)
        {
            var natural = PlotLayout.Generate(x, y, map.BiomeAt(x, y));
            await using var command = await db.CommandAsync("SELECT tile_x, tile_y FROM world.plot_harvests WHERE x = @x AND y = @y", cancellationToken);
            command.Parameters.AddWithValue("x", x);
            command.Parameters.AddWithValue("y", y);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var tile = (X: reader.GetInt32(0), Y: reader.GetInt32(1));
                if (natural[tile.Y * PlotLayout.Size + tile.X] == (byte)TileObject.Tree
                    && forests.Any(f => Foresters.Claims(f.Patch.ForesterLevel, tile.X - f.Object.TileX, tile.Y - f.Object.TileY)))
                {
                    cleared.Add(tile);
                }
            }
        }

        return new PlotForests(x, y, forests, trees, cleared);
    }

    /// <summary>A forester as inserters see it: wood comes out, nothing goes in. The other foresters of the
    /// plot are read with it, so the tiles where their squares meet are shared out the same way.</summary>
    private sealed class Port(ForesterService service, int x, int y, List<ForesterOnPlot> forests, ForestPatch patch) : IMachinePort
    {
        public string? Output(DateTimeOffset now, Func<string, bool> wanted)
        {
            patch.Advance(now);
            return patch.Wood > 0 && wanted(Items.Wood) ? Items.Wood : null;
        }

        public void Take(string item, DateTimeOffset now)
        {
            patch.Advance(now);
            if (item == Items.Wood && patch.Take(1, now) == 1)
            {
                patch.Advance(now);
            }
        }

        public bool Accepts(string item, DateTimeOffset now) => false;

        public void Put(string item, DateTimeOffset now)
        {
        }

        public DateTimeOffset? NextChange(DateTimeOffset now)
        {
            patch.Advance(now);
            return patch.Full ? null : patch.NextCut();
        }

        public Task SaveAsync(CancellationToken cancellationToken) =>
            service.SaveAsync(x, y, forests.Where(f => f.Patch == patch).ToList(), cancellationToken);
    }
}

public sealed record ForestryRequest(int X, int Y);

public sealed record TakeFromForesterRequest(int X, int Y, Guid Id);

public abstract class ForestryHandler(IServiceScopeFactory scopes, TimeProvider time) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var (state, taken, xp) = await RunAsync(
            scope.ServiceProvider.GetRequiredService<ForesterService>(), scope.ServiceProvider.GetServices<IPlotAutomation>(),
            client.RequireAccount(), payload, cancellationToken);
        var biome = scope.ServiceProvider.GetRequiredService<WorldMap>().BiomeAt(state.X, state.Y);
        return new Reply("forestry", new
        {
            x = state.X,
            y = state.Y,
            foresters = state.Foresters.Select(f => ForesterJson(f, biome, time.GetUtcNow())),
            trees = state.Trees.Select(PlantTreeHandler.TreeJson),
            cleared = state.Cleared.Select(t => new { tileX = t.X, tileY = t.Y }),
            taken = taken > 0 ? new[] { new { id = Items.Wood, name = Items.Names[Items.Wood], quantity = taken } } : [],
            xp = xp is { } gain ? new { xp = gain.Xp, level = gain.Level, leveledUp = gain.LeveledUp } : null,
            serverTime = time.GetUtcNow().ToUnixTimeMilliseconds(),
        });
    }

    protected abstract Task<(PlotForests, int, XpGain?)> RunAsync(
        ForesterService foresters, IEnumerable<IPlotAutomation> automation, Guid player, JsonElement? payload, CancellationToken cancellationToken);

    public static object ForesterJson(ForesterOnPlot forester, Biome biome, DateTimeOffset now)
    {
        var (o, patch) = (forester.Object, forester.Patch);
        var level = patch.ForesterLevel;
        var next = Foresters.Levels.FirstOrDefault(l => l.Level == level.Level + 1);
        return new
        {
            id = o.Id,
            kind = o.Kind,
            name = Items.Names[o.Kind],
            level = level.Level,
            tileX = o.TileX,
            tileY = o.TileY,
            rotation = o.Rotation,
            radius = level.Radius,
            clearing = Foresters.Clearing,
            wood = patch.Wood,
            capacity = level.Capacity,
            cutSeconds = level.CutTime.TotalSeconds,
            growSeconds = Foresters.GrowTime(level, biome)?.TotalSeconds,
            trees = patch.Trees.Count + patch.Wild.Count,
            grown = patch.Wild.Count + patch.Trees.Values.Count(r => r <= now),
            full = patch.Full,
            // The next level: a building made at the workbench from this one.
            upgrade = next is null ? null : new
            {
                kind = next.Kind,
                name = Items.Names[next.Kind],
                radius = next.Radius,
                capacity = next.Capacity,
                cutSeconds = next.CutTime.TotalSeconds,
                growSeconds = Foresters.GrowTime(next, biome)?.TotalSeconds,
            },
        };
    }
}

/// <summary>The plot's foresters, their forests and every planted tree, worked up to now; the client asks every few seconds.</summary>
public sealed class GetForestryHandler(IServiceScopeFactory scopes, TimeProvider time) : ForestryHandler(scopes, time)
{
    public override string Type => "forestry.get";

    protected override async Task<(PlotForests, int, XpGain?)> RunAsync(
        ForesterService foresters, IEnumerable<IPlotAutomation> automation, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<ForestryRequest>(payload);
        return (await foresters.StateAsync(player, request.X, request.Y, automation, cancellationToken), 0, null);
    }
}

/// <summary>Takes all the wood out of a forester into the inventory.</summary>
public sealed class TakeFromForesterHandler(IServiceScopeFactory scopes, TimeProvider time) : ForestryHandler(scopes, time)
{
    public override string Type => "forester.take";

    protected override Task<(PlotForests, int, XpGain?)> RunAsync(
        ForesterService foresters, IEnumerable<IPlotAutomation> automation, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<TakeFromForesterRequest>(payload);
        return foresters.TakeAsync(player, request.X, request.Y, request.Id, automation, cancellationToken);
    }
}
