using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;
using NpgsqlTypes;

namespace FactoryWorld.Modules.World;

/// <summary>
/// A feeder stands on one tile by the pasture and feeds every hungry animal within <see cref="Reach"/> tiles of it by itself,
/// <see cref="Husbandry.FeedPerMeal"/> pieces of a feed the animal eats, as if fed by hand. The feed goes in by hand or by an
/// inserter, up to <see cref="Capacity"/> pieces of any feed together. An animal is fed the moment it is hungry: when let out,
/// when its product is collected, or when feed comes in for it. Products are still collected by hand.
/// </summary>
public static class Feeders
{
    public const int Capacity = 60;

    public const int Reach = 3;

    public static bool Reaches(int feederX, int feederY, int tileX, int tileY) =>
        Math.Abs(tileX - feederX) <= Reach && Math.Abs(tileY - feederY) <= Reach;
}

/// <summary>One feeder in memory: where it stands and the feed in it.</summary>
public sealed class Trough(Guid id, Guid owner, int tileX, int tileY, IReadOnlyDictionary<string, int> store)
{
    public Guid Id { get; } = id;

    public Guid Owner { get; } = owner;

    public int TileX { get; } = tileX;

    public int TileY { get; } = tileY;

    public Dictionary<string, int> Store { get; } = store.Where(s => s.Value > 0).ToDictionary();

    public int Feed => Store.Values.Sum();

    public int Room => Math.Max(0, Feeders.Capacity - Feed);

    public bool Changed { get; set; }

    /// <summary>Puts feed in, as much as there is room for; returns how much went in.</summary>
    public int Add(string item, int quantity)
    {
        var added = Math.Clamp(quantity, 0, Room);
        if (added > 0)
        {
            Store[item] = Store.GetValueOrDefault(item) + added;
            Changed = true;
        }

        return added;
    }

    public IReadOnlyList<(string Item, int Quantity)> TakeAll()
    {
        var all = Store.OrderBy(s => s.Key).Select(s => (s.Key, s.Value)).ToList();
        Changed |= Store.Count > 0;
        Store.Clear();
        return all;
    }

    /// <summary>A meal for an animal that eats <paramref name="eats"/>, taken out of the feeder: the first feed it has enough of, in that order.</summary>
    public string? Serve(IReadOnlyList<string> eats)
    {
        var feed = eats.FirstOrDefault(f => Store.GetValueOrDefault(f) >= Husbandry.FeedPerMeal);
        if (feed is null)
        {
            return null;
        }

        Store[feed] -= Husbandry.FeedPerMeal;
        if (Store[feed] == 0)
        {
            Store.Remove(feed);
        }

        Changed = true;
        return feed;
    }
}

/// <summary>The feeders of a plot and its hungry animals, in memory: fed up to a moment, then written back.</summary>
public sealed class Yard(Biome biome, IReadOnlyList<Trough> troughs, IEnumerable<(int X, int Y, string Kind)> hungry)
{
    public IReadOnlyList<Trough> Troughs { get; } = troughs.OrderBy(t => t.TileY).ThenBy(t => t.TileX).ThenBy(t => t.Id).ToList();

    /// <summary>Hungry animals still waiting for a meal, from north to south, west to east.</summary>
    private readonly List<(int X, int Y, string Kind)> _hungry = hungry.OrderBy(a => a.Y).ThenBy(a => a.X).ToList();

    /// <summary>Animals fed since the yard was read, and when each will give its product.</summary>
    public Dictionary<(int X, int Y), DateTimeOffset> Fed { get; } = [];

    /// <summary>The feed eaten, by the owner of the feeder it came from.</summary>
    public List<(Guid Owner, ProductionEntry Entry)> Eaten { get; } = [];

    /// <summary>Feeds every hungry animal in reach of a feeder that has what it eats, at <paramref name="now"/>; the first feeder in reach serves.</summary>
    public void Feed(DateTimeOffset now)
    {
        if (Troughs.Count == 0)
        {
            return;
        }

        foreach (var (x, y, kind) in _hungry.ToList())
        {
            if (!Husbandry.ById.TryGetValue(kind, out var animal))
            {
                continue;
            }

            foreach (var trough in Troughs.Where(t => Feeders.Reaches(t.TileX, t.TileY, x, y)))
            {
                if (trough.Serve(animal.Eats) is { } feed)
                {
                    Fed[(x, y)] = now + (Husbandry.Time(animal, biome) ?? animal.Time);
                    Eaten.Add((trough.Owner, ProductionEntry.Used(feed, Husbandry.FeedPerMeal, now)));
                    _hungry.Remove((x, y, kind));
                    break;
                }
            }
        }
    }
}

public sealed class FeederService(
    GameDb db, WorldMap map, PlotService plots, IPlotObjects objects, IInventory inventory, IProductionStats stats, TimeProvider time)
    : IPlacedHook, IPlotAutomation, IMachineContents, IMachinePorts
{
    /// <summary>The feeder as it is now, its hungry animals in reach fed.</summary>
    public Task<(Trough Feeder, IReadOnlyList<PlotAnimal> Animals)> StateAsync(
        Guid player, int x, int y, Guid id, IEnumerable<IPlotAutomation> automation, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Work);
            await CatchUpAllAsync(x, y, automation, cancellationToken);
            var yard = await OpenAsync(x, y, cancellationToken);
            var feeder = Find(yard, id);
            yard.Feed(time.GetUtcNow());
            await SaveAsync(x, y, yard, cancellationToken);
            return (feeder, await AnimalsAsync(x, y, cancellationToken));
        }, cancellationToken);

    /// <summary>Puts up to <paramref name="quantity"/> pieces of a feed from the inventory into a feeder, as much as there is room for, and feeds the hungry animals.</summary>
    public Task<(Trough Feeder, IReadOnlyList<PlotAnimal> Animals)> FillAsync(
        Guid player, int x, int y, Guid id, string item, int quantity, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (!Husbandry.Feed.Contains(item))
            {
                throw new GameException("bad_feed", "Animals eat wheat, corn, carrots, cabbage, fish meal, dates and concentrate.");
            }

            if (quantity is < 1 or > Feeders.Capacity)
            {
                throw new GameException("bad_quantity", $"Put in 1 to {Feeders.Capacity} pieces.");
            }

            await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Work);
            var yard = await OpenAsync(x, y, cancellationToken);
            var feeder = Find(yard, id);
            var added = feeder.Add(item, quantity);
            if (added == 0)
            {
                throw new GameException("feeder_full", $"A feeder holds at most {Feeders.Capacity} pieces of feed.");
            }

            await inventory.RemoveAsync(player, item, added, cancellationToken);
            yard.Feed(time.GetUtcNow());
            await SaveAsync(x, y, yard, cancellationToken);
            return (feeder, await AnimalsAsync(x, y, cancellationToken));
        }, cancellationToken);

    /// <summary>Takes all the feed out of a feeder into the inventory.</summary>
    public Task<(Trough Feeder, IReadOnlyList<PlotAnimal> Animals, IReadOnlyList<(string Item, int Quantity)> Taken)> TakeAsync(
        Guid player, int x, int y, Guid id, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Take);
            var yard = await OpenAsync(x, y, cancellationToken);
            var feeder = Find(yard, id);
            yard.Feed(time.GetUtcNow());
            var taken = feeder.TakeAll();
            await SaveAsync(x, y, yard, cancellationToken);
            foreach (var (item, quantity) in taken)
            {
                await inventory.ReceiveAsync(player, item, quantity, cancellationToken);
            }

            return (feeder, await AnimalsAsync(x, y, cancellationToken), taken);
        }, cancellationToken);

    /// <summary>The plot's animals after its feeders fed the hungry ones; the client asks every few seconds while a feeder stands there.</summary>
    public Task<IReadOnlyList<PlotAnimal>> FeedAnimalsAsync(Guid player, int x, int y, IEnumerable<IPlotAutomation> automation, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Work);
            await CatchUpAllAsync(x, y, automation, cancellationToken);
            return await AnimalsAsync(x, y, cancellationToken);
        }, cancellationToken);

    /// <summary>Works the plot's machinery up to now, inserters filling feeders among it, then feeds the hungry animals.</summary>
    private async Task CatchUpAllAsync(int x, int y, IEnumerable<IPlotAutomation> automation, CancellationToken cancellationToken)
    {
        foreach (var machinery in automation)
        {
            await machinery.CatchUpAsync(x, y, cancellationToken);
        }

        await CatchUpAsync(x, y, cancellationToken);
    }

    /// <summary>
    /// Locks the plot's feeders before an animal there is locked, so that an inserter filling a feeder and a player
    /// collecting from an animal always lock in the same order.
    /// </summary>
    public async Task LockAsync(int x, int y, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT object_id FROM world.plot_feeders WHERE x = @x AND y = @y ORDER BY object_id FOR UPDATE", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
        }
    }

    /// <summary>Feeds the plot's hungry animals now; returns when each fed animal will give its product.</summary>
    public async Task<IReadOnlyDictionary<(int X, int Y), DateTimeOffset>> FeedAsync(int x, int y, CancellationToken cancellationToken)
    {
        var yard = await OpenAsync(x, y, cancellationToken);
        yard.Feed(time.GetUtcNow());
        var fed = yard.Fed.ToDictionary();
        await SaveAsync(x, y, yard, cancellationToken);
        return fed;
    }

    public async Task CatchUpAsync(int x, int y, CancellationToken cancellationToken) => await FeedAsync(x, y, cancellationToken);

    public async Task PlacedAsync(Guid owner, int x, int y, PlacedOnPlot placed, CancellationToken cancellationToken)
    {
        if (placed.Kind != Items.Feeder)
        {
            return;
        }

        await using var insert = await db.CommandAsync(
            "INSERT INTO world.plot_feeders (object_id, x, y, owner_id, store) VALUES (@id, @x, @y, @owner, '{}') ON CONFLICT DO NOTHING", cancellationToken);
        insert.Parameters.AddWithValue("id", placed.Id);
        insert.Parameters.AddWithValue("x", x);
        insert.Parameters.AddWithValue("y", y);
        insert.Parameters.AddWithValue("owner", owner);
        await insert.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>The feeder is being picked up: the feed in it goes back to the player.</summary>
    public async Task ReleaseAsync(Guid owner, Guid id, CancellationToken cancellationToken)
    {
        await using var delete = await db.CommandAsync("DELETE FROM world.plot_feeders WHERE object_id = @id RETURNING store", cancellationToken);
        delete.Parameters.AddWithValue("id", id);
        var back = new Dictionary<string, int>();
        await using (var reader = await delete.ExecuteReaderAsync(cancellationToken))
        {
            if (await reader.ReadAsync(cancellationToken))
            {
                back = ReadStore(reader.GetString(0));
            }
        }

        foreach (var (item, quantity) in back.Where(b => b.Value > 0))
        {
            await inventory.AddAsync(owner, item, quantity, cancellationToken);
        }
    }

    public async Task<IMachinePort?> OpenAsync(Guid owner, Guid id, string kind, CancellationToken cancellationToken)
    {
        if (kind != Items.Feeder || await objects.PlotOfAsync(id, cancellationToken) is not var (x, y))
        {
            return null;
        }

        var yard = _prepared is { } prepared && prepared.X == x && prepared.Y == y ? prepared.Yard : await OpenAsync(x, y, cancellationToken);
        _prepared = (x, y, yard);
        return yard.Troughs.FirstOrDefault(t => t.Id == id) is { } trough ? new Port(this, x, y, yard, trough) : null;
    }

    /// <summary>The plot's yard opened once for all the feeders of one run of its logistics, as they share its animals.</summary>
    private (int X, int Y, Yard Yard)? _prepared;

    public async Task PrepareAsync(IReadOnlyList<PlotObject> reached, CancellationToken cancellationToken)
    {
        _prepared = null;
        if (reached.FirstOrDefault(o => o.Kind == Items.Feeder) is { } first && await objects.PlotOfAsync(first.Id, cancellationToken) is var (x, y))
        {
            _prepared = (x, y, await OpenAsync(x, y, cancellationToken));
        }
    }

    private static Trough Find(Yard yard, Guid id) =>
        yard.Troughs.FirstOrDefault(t => t.Id == id) ?? throw new GameException("no_object", "There is no such feeder on this plot.");

    private static Dictionary<string, int> ReadStore(string json) =>
        JsonSerializer.Deserialize<Dictionary<string, int>>(json) is { } store ? store.Where(s => Items.Exists(s.Key)).ToDictionary() : [];

    /// <summary>The feeders of a plot and its hungry animals, both locked until the transaction ends (feeders first).</summary>
    private async Task<Yard> OpenAsync(int x, int y, CancellationToken cancellationToken)
    {
        var rows = new List<(Guid Id, Guid Owner, string Store)>();
        await using (var command = await db.CommandAsync(
            "SELECT object_id, owner_id, store FROM world.plot_feeders WHERE x = @x AND y = @y ORDER BY object_id FOR UPDATE", cancellationToken))
        {
            command.Parameters.AddWithValue("x", x);
            command.Parameters.AddWithValue("y", y);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                rows.Add((reader.GetGuid(0), reader.GetGuid(1), reader.GetString(2)));
            }
        }

        // Most plots have no feeder: then there is nothing more to read.
        var troughs = new List<Trough>();
        if (rows.Count > 0)
        {
            var placed = (await objects.ObjectsAsync(x, y, cancellationToken)).Where(o => o.Kind == Items.Feeder)
                .GroupBy(o => o.Id).ToDictionary(g => g.Key, g => g.First());
            troughs.AddRange(rows.Where(r => placed.ContainsKey(r.Id))
                .Select(r => new Trough(r.Id, r.Owner, placed[r.Id].TileX, placed[r.Id].TileY, ReadStore(r.Store))));
        }

        var hungry = new List<(int X, int Y, string Kind)>();
        if (troughs.Count > 0)
        {
            await using var command = await db.CommandAsync(
                """
                SELECT tile_x, tile_y, kind FROM world.plot_animals WHERE x = @x AND y = @y AND ready_at IS NULL
                ORDER BY tile_y, tile_x FOR UPDATE
                """, cancellationToken);
            command.Parameters.AddWithValue("x", x);
            command.Parameters.AddWithValue("y", y);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                hungry.Add((reader.GetInt32(0), reader.GetInt32(1), reader.GetString(2)));
            }
        }

        return new Yard(map.BiomeAt(x, y), troughs, hungry);
    }

    /// <summary>Writes back the feeders that changed and the animals they fed.</summary>
    private async Task SaveAsync(int x, int y, Yard yard, CancellationToken cancellationToken)
    {
        foreach (var trough in yard.Troughs.Where(t => t.Changed))
        {
            await using var update = await db.CommandAsync("UPDATE world.plot_feeders SET store = @store WHERE object_id = @id", cancellationToken);
            update.Parameters.AddWithValue("id", trough.Id);
            update.Parameters.AddWithValue("store", JsonSerializer.Serialize(trough.Store));
            await update.ExecuteNonQueryAsync(cancellationToken);
            trough.Changed = false;
        }

        if (yard.Fed.Count > 0)
        {
            var fed = yard.Fed.ToList();
            await using var update = await db.CommandAsync(
                """
                UPDATE world.plot_animals AS a SET ready_at = t.ready
                FROM unnest(@txs, @tys, @ready) AS t(tx, ty, ready)
                WHERE a.x = @x AND a.y = @y AND a.tile_x = t.tx AND a.tile_y = t.ty AND a.ready_at IS NULL
                """, cancellationToken);
            update.Parameters.AddWithValue("x", x);
            update.Parameters.AddWithValue("y", y);
            update.Parameters.AddWithValue("txs", fed.Select(f => f.Key.X).ToArray());
            update.Parameters.AddWithValue("tys", fed.Select(f => f.Key.Y).ToArray());
            update.Parameters.Add(new Npgsql.NpgsqlParameter("ready", NpgsqlDbType.Array | NpgsqlDbType.TimestampTz) { Value = fed.Select(f => f.Value).ToArray() });
            await update.ExecuteNonQueryAsync(cancellationToken);
            yard.Fed.Clear();
        }

        foreach (var owner in yard.Eaten.GroupBy(e => e.Owner))
        {
            await stats.RecordAsync(owner.Key, owner.Select(e => e.Entry).ToList(), cancellationToken);
        }

        yard.Eaten.Clear();
    }

    private async Task<IReadOnlyList<PlotAnimal>> AnimalsAsync(int x, int y, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT tile_x, tile_y, kind, ready_at, meals FROM world.plot_animals WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var animals = new List<PlotAnimal>();
        while (await reader.ReadAsync(cancellationToken))
        {
            animals.Add(new PlotAnimal(reader.GetInt32(0), reader.GetInt32(1), reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetFieldValue<DateTimeOffset>(3), reader.GetInt32(4)));
        }

        return animals;
    }

    /// <summary>A feeder as inserters see it: feed goes in and the hungry animals around it eat at once; nothing comes out.</summary>
    private sealed class Port(FeederService service, int x, int y, Yard yard, Trough trough) : IMachinePort
    {
        public string? Output(DateTimeOffset now, Func<string, bool> wanted) => null;

        public void Take(string item, DateTimeOffset now)
        {
        }

        public bool Accepts(string item, DateTimeOffset now) => Husbandry.Feed.Contains(item) && trough.Room > 0;

        public void Put(string item, DateTimeOffset now)
        {
            trough.Add(item, 1);
            yard.Feed(now);
        }

        public DateTimeOffset? NextChange(DateTimeOffset now) => null;

        public bool Predictable => true;

        public Task SaveAsync(CancellationToken cancellationToken) => service.SaveAsync(x, y, yard, cancellationToken);
    }
}

public sealed record FeederRequest(int X, int Y, Guid Id, string? Item = null, int Quantity = 0);

/// <summary>feeder.get, feeder.fill and feeder.take answer with the feeder and the plot's animals.</summary>
public abstract class FeederHandler(IServiceScopeFactory scopes, TimeProvider time) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<FeederRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var (feeder, animals, taken) = await RunAsync(
            scope.ServiceProvider.GetRequiredService<FeederService>(), scope.ServiceProvider.GetServices<IPlotAutomation>(), client.RequireAccount(), request, cancellationToken);
        var reached = animals.Where(a => Feeders.Reaches(feeder.TileX, feeder.TileY, a.TileX, a.TileY)).ToList();
        return new Reply("feeder", new
        {
            x = request.X,
            y = request.Y,
            feeder = new
            {
                id = feeder.Id,
                tileX = feeder.TileX,
                tileY = feeder.TileY,
                store = feeder.Store.OrderBy(s => s.Key).Select(s => new { id = s.Key, name = Items.Names[s.Key], quantity = s.Value }),
                feed = feeder.Feed,
                capacity = Feeders.Capacity,
                reach = Feeders.Reach,
                feedPerMeal = Husbandry.FeedPerMeal,
                animals = reached.Count,
                hungry = reached.Count(a => a.ReadyAt is null),
            },
            animals = animals.Select(AnimalHandler.AnimalJson),
            taken = taken.Select(t => new { id = t.Item, name = Items.Names[t.Item], quantity = t.Quantity }),
            serverTime = time.GetUtcNow().ToUnixTimeMilliseconds(),
        });
    }

    protected abstract Task<(Trough, IReadOnlyList<PlotAnimal>, IReadOnlyList<(string Item, int Quantity)>)> RunAsync(
        FeederService feeders, IEnumerable<IPlotAutomation> automation, Guid player, FeederRequest request, CancellationToken cancellationToken);
}

public sealed class GetFeederHandler(IServiceScopeFactory scopes, TimeProvider time) : FeederHandler(scopes, time)
{
    public override string Type => "feeder.get";

    protected override async Task<(Trough, IReadOnlyList<PlotAnimal>, IReadOnlyList<(string Item, int Quantity)>)> RunAsync(
        FeederService feeders, IEnumerable<IPlotAutomation> automation, Guid player, FeederRequest r, CancellationToken cancellationToken)
    {
        var (feeder, animals) = await feeders.StateAsync(player, r.X, r.Y, r.Id, automation, cancellationToken);
        return (feeder, animals, []);
    }
}

public sealed class FillFeederHandler(IServiceScopeFactory scopes, TimeProvider time) : FeederHandler(scopes, time)
{
    public override string Type => "feeder.fill";

    protected override async Task<(Trough, IReadOnlyList<PlotAnimal>, IReadOnlyList<(string Item, int Quantity)>)> RunAsync(
        FeederService feeders, IEnumerable<IPlotAutomation> automation, Guid player, FeederRequest r, CancellationToken cancellationToken)
    {
        var (feeder, animals) = await feeders.FillAsync(player, r.X, r.Y, r.Id, r.Item ?? "", r.Quantity, cancellationToken);
        return (feeder, animals, []);
    }
}

public sealed class TakeFromFeederHandler(IServiceScopeFactory scopes, TimeProvider time) : FeederHandler(scopes, time)
{
    public override string Type => "feeder.take";

    protected override Task<(Trough, IReadOnlyList<PlotAnimal>, IReadOnlyList<(string Item, int Quantity)>)> RunAsync(
        FeederService feeders, IEnumerable<IPlotAutomation> automation, Guid player, FeederRequest r, CancellationToken cancellationToken) =>
        feeders.TakeAsync(player, r.X, r.Y, r.Id, cancellationToken);
}

public sealed record AnimalsRequest(int X, int Y);

/// <summary>The plot's animals once its feeders fed the hungry ones, for the client to redraw them while a feeder stands there.</summary>
public sealed class GetAnimalsHandler(IServiceScopeFactory scopes, TimeProvider time) : IMessageHandler
{
    public string Type => "plot.animals";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<AnimalsRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var animals = await scope.ServiceProvider.GetRequiredService<FeederService>().FeedAnimalsAsync(
            client.RequireAccount(), request.X, request.Y, scope.ServiceProvider.GetServices<IPlotAutomation>(), cancellationToken);
        return new Reply("plot.animals", new
        {
            x = request.X,
            y = request.Y,
            animals = animals.Select(AnimalHandler.AnimalJson),
            serverTime = time.GetUtcNow().ToUnixTimeMilliseconds(),
        });
    }
}
