using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using NpgsqlTypes;

namespace FactoryWorld.Modules.Logistics;

/// <summary>Up to when a plot's belts and inserters have been worked out.</summary>
public sealed class LogisticsPlotRow
{
    public int X { get; set; }

    public int Y { get; set; }

    public DateTimeOffset SimulatedAt { get; set; }
}

/// <summary>What a belt, an inserter or a storage on a plot holds (<see cref="Contents"/> as JSON).</summary>
public sealed class ContentsRow
{
    public Guid ObjectId { get; set; }

    public int X { get; set; }

    public int Y { get; set; }

    public string Data { get; set; } = "{}";
}

public sealed class LogisticsDbContext(DbContextOptions<LogisticsDbContext> options, GameDb gameDb) : ModuleDbContext(options, gameDb)
{
    public const string Schema = "logistics";

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.HasDefaultSchema(Schema);
        model.Entity<LogisticsPlotRow>(e =>
        {
            e.ToTable("plots");
            e.HasKey(p => new { p.X, p.Y });
            e.Property(p => p.X).HasColumnName("x");
            e.Property(p => p.Y).HasColumnName("y");
            e.Property(p => p.SimulatedAt).HasColumnName("simulated_at");
        });
        model.Entity<ContentsRow>(e =>
        {
            e.ToTable("contents");
            e.HasKey(c => c.ObjectId);
            e.Property(c => c.ObjectId).HasColumnName("object_id");
            e.Property(c => c.X).HasColumnName("x");
            e.Property(c => c.Y).HasColumnName("y");
            e.Property(c => c.Data).HasColumnName("data").HasColumnType("jsonb");
            e.HasIndex(c => new { c.X, c.Y });
        });
    }
}

/// <summary>A plot's logistics just after being brought up to now, with the power grid that runs its inserters.</summary>
public sealed record LogisticsState(
    DateTimeOffset SimulatedAt, DateTimeOffset ServerTime, IReadOnlyList<PlotObject> Objects, IReadOnlyDictionary<Guid, Contents> Contents, IPowerGrid Power);

public sealed class LogisticsService(GameDb db, IPlotObjects plots, IEnumerable<IMachinePorts> machines, IPlotPower power, IInventory inventory, TimeProvider time)
    : IPlotAutomation
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingDefault,
    };

    public async Task CatchUpAsync(int x, int y, CancellationToken cancellationToken) =>
        await db.InTransactionAsync(() => RunAsync(x, y, cancellationToken), cancellationToken);

    /// <summary>The player's plot with its belts, inserters and storage as they are now.</summary>
    public Task<LogisticsState> StateAsync(Guid player, int x, int y, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Work);
            return await RunAsync(x, y, cancellationToken);
        }, cancellationToken);

    /// <summary>Puts items from the inventory into a storage on the player's plot.</summary>
    public Task<(LogisticsState State, PlotObject Storage)> PutAsync(
        Guid player, int x, int y, Guid id, string item, int quantity, CancellationToken cancellationToken) =>
        ChangeStorageAsync(player, x, y, id, PlotRight.Work, async (kind, stacks) =>
        {
            if (quantity < 1)
            {
                throw new GameException("bad_quantity", "Put in at least one.");
            }

            if (!kind.Takes(item))
            {
                throw new GameException("not_stored_here", $"{Items.Names[kind.Id]} does not take this.");
            }

            if (Storages.Room(kind, stacks, item) < quantity)
            {
                throw new GameException("storage_full", $"There is no room for that much in the {Items.Names[kind.Id].ToLowerInvariant()}.");
            }

            await inventory.RemoveAsync(player, item, quantity, cancellationToken);
            Storages.Add(stacks, item, quantity);
        }, cancellationToken);

    /// <summary>Takes items out of a storage into the inventory: <paramref name="quantity"/> of them, or all when 0.</summary>
    public Task<(LogisticsState State, PlotObject Storage)> TakeAsync(
        Guid player, int x, int y, Guid id, string item, int quantity, CancellationToken cancellationToken) =>
        ChangeStorageAsync(player, x, y, id, PlotRight.Take, async (_, stacks) =>
        {
            if (quantity < 0)
            {
                throw new GameException("bad_quantity", "Take out at least one.");
            }

            var taken = Storages.Remove(stacks, item, quantity == 0 ? int.MaxValue : quantity);
            if (taken == 0 || (quantity > 0 && taken < quantity))
            {
                throw new GameException("not_enough_items", "There is not that much in it.");
            }

            await inventory.ReceiveAsync(player, item, taken, cancellationToken);
        }, cancellationToken);

    /// <summary>Most items a splitter can be set to sort out.</summary>
    public const int MaxFilter = 8;

    /// <summary>Sets which items a splitter on the player's plot sends to one side (0 left, 1 right) and
    /// the rest to the other; no items, and it sends items left and right in turn.</summary>
    public Task<LogisticsState> SetSplitterAsync(
        Guid player, int x, int y, Guid id, int side, IReadOnlyList<string> items, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (side is not (0 or 1))
            {
                throw new GameException("bad_side", "A splitter sends items left (0) or right (1).");
            }

            if (items.Count > MaxFilter || items.Any(i => !Items.Names.ContainsKey(i)))
            {
                throw new GameException("bad_filter", $"Choose at most {MaxFilter} items to sort out.");
            }

            await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            var state = await RunAsync(x, y, cancellationToken);
            if (!state.Objects.Any(o => o.Id == id && o.Kind == Items.Splitter))
            {
                throw new GameException("no_object", "There is no such splitter on this plot.");
            }

            var contents = state.Contents.GetValueOrDefault(id) ?? new Contents();
            contents.Filter = items.Count == 0 ? null : items.Distinct().ToList();
            contents.FilterSide = side;
            await WriteAsync(id, x, y, contents, cancellationToken);
            var all = new Dictionary<Guid, Contents>(state.Contents) { [id] = contents };
            return state with { Contents = all };
        }, cancellationToken);

    private Task<(LogisticsState, PlotObject)> ChangeStorageAsync(
        Guid player, int x, int y, Guid id, PlotRight right, Func<StorageKind, List<ItemStack>, Task> change, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, right);
            var state = await RunAsync(x, y, cancellationToken);
            var storage = state.Objects.FirstOrDefault(o => o.Id == id);
            if (storage is null || Storages.Find(storage.Kind) is not { } kind)
            {
                throw new GameException("no_object", "There is no such storage on this plot.");
            }

            var contents = state.Contents.GetValueOrDefault(id) ?? new Contents();
            await change(kind, contents.Items ??= []);
            await WriteAsync(id, x, y, contents, cancellationToken);
            var all = new Dictionary<Guid, Contents>(state.Contents) { [id] = contents };
            return (state with { Contents = all }, storage);
        }, cancellationToken);

    /// <summary>Works out the plot's logistics from where they were left up to now, under a lock on the plot.</summary>
    private async Task<LogisticsState> RunAsync(int x, int y, CancellationToken cancellationToken)
    {
        await using (var lockPlot = await db.CommandAsync("SELECT pg_advisory_xact_lock(@key)", cancellationToken))
        {
            lockPlot.Parameters.AddWithValue("key", ((long)x << 32 | (uint)y) ^ 0x6c6f6769_73746963);
            await lockPlot.ExecuteNonQueryAsync(cancellationToken);
        }

        var now = time.GetUtcNow();
        var objects = await plots.ObjectsAsync(x, y, cancellationToken);
        var from = await SimulatedAtAsync(x, y, cancellationToken) ?? now;
        var contents = await ReadAsync(x, y, cancellationToken);
        var grid = await power.OpenAsync(x, y, cancellationToken);

        // Storages are this module's own; every other machine within an inserter's reach comes from its
        // module, and so does the plot's station, which inserters can load and unload too.
        // A forester's building covers 3 × 3 tiles, and an inserter next to any of them reaches it.
        var reachable = objects.SelectMany(Footprints.Spread).Concat(await plots.FixturesAsync(x, y, cancellationToken)).ToList();
        var at = reachable.ToDictionary(o => (o.TileX, o.TileY));
        var ports = new Dictionary<Guid, IMachinePort>();
        var opened = new List<IMachinePort>();
        var storageChanged = new HashSet<Guid>();
        foreach (var tile in PlotLogistics.Reach(objects).Distinct())
        {
            if (!at.TryGetValue(tile, out var o) || ports.ContainsKey(o.Id))
            {
                continue;
            }

            if (Storages.Find(o.Kind) is { } kind)
            {
                if (!contents.TryGetValue(o.Id, out var c))
                {
                    contents[o.Id] = c = new Contents();
                }

                ports[o.Id] = new StoragePort(kind, c, () => storageChanged.Add(o.Id));
                continue;
            }

            if (grid.Port(o.Id) is { } generator)
            {
                ports[o.Id] = generator;
                continue;
            }

            foreach (var module in machines)
            {
                if (await module.OpenAsync(o.Owner, o.Id, o.Kind, cancellationToken) is { } port)
                {
                    ports[o.Id] = port;
                    opened.Add(port);
                    break;
                }
            }
        }

        var logistics = new PlotLogistics(reachable, contents, ports, grid);
        var simulated = logistics.Run(from, now);
        foreach (var id in logistics.Changed.Concat(storageChanged).Distinct())
        {
            await WriteAsync(id, x, y, contents[id], cancellationToken);
        }

        foreach (var port in opened)
        {
            await port.SaveAsync(cancellationToken);
        }

        await grid.SaveAsync(cancellationToken);

        await using (var save = await db.CommandAsync(
            """
            INSERT INTO logistics.plots (x, y, simulated_at) VALUES (@x, @y, @at)
            ON CONFLICT (x, y) DO UPDATE SET simulated_at = @at
            """, cancellationToken))
        {
            save.Parameters.AddWithValue("x", x);
            save.Parameters.AddWithValue("y", y);
            save.Parameters.AddWithValue("at", simulated);
            await save.ExecuteNonQueryAsync(cancellationToken);
        }

        return new LogisticsState(simulated, now, objects, contents, grid);
    }

    private async Task<DateTimeOffset?> SimulatedAtAsync(int x, int y, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync("SELECT simulated_at FROM logistics.plots WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        return await command.ExecuteScalarAsync(cancellationToken) is DateTime at ? new DateTimeOffset(at, TimeSpan.Zero) : null;
    }

    private async Task<Dictionary<Guid, Contents>> ReadAsync(int x, int y, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync("SELECT object_id, data FROM logistics.contents WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var contents = new Dictionary<Guid, Contents>();
        while (await reader.ReadAsync(cancellationToken))
        {
            contents[reader.GetGuid(0)] = JsonSerializer.Deserialize<Contents>(reader.GetString(1), Json) ?? new Contents();
        }

        return contents;
    }

    private async Task WriteAsync(Guid id, int x, int y, Contents contents, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """
            INSERT INTO logistics.contents (object_id, x, y, data) VALUES (@id, @x, @y, @data)
            ON CONFLICT (object_id) DO UPDATE SET data = @data
            """, cancellationToken);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        command.Parameters.AddWithValue("data", NpgsqlDbType.Jsonb, JsonSerializer.Serialize(contents, Json));
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    internal static Contents Parse(string data) => JsonSerializer.Deserialize<Contents>(data, Json) ?? new Contents();
}

/// <summary>Empties a belt, inserter or storage that is being picked up into the owner's inventory.</summary>
public sealed class LogisticsContents(GameDb db, IInventory inventory) : IMachineContents
{
    public async Task ReleaseAsync(Guid owner, Guid id, CancellationToken cancellationToken)
    {
        await using var delete = await db.CommandAsync("DELETE FROM logistics.contents WHERE object_id = @id RETURNING data", cancellationToken);
        delete.Parameters.AddWithValue("id", id);
        if (await delete.ExecuteScalarAsync(cancellationToken) is not string data)
        {
            return;
        }

        foreach (var stack in LogisticsService.Parse(data).All().GroupBy(i => i.Item, i => i.Quantity))
        {
            await inventory.AddAsync(owner, stack.Key, stack.Sum(), cancellationToken);
        }
    }
}

public sealed record LogisticsRequest(int X, int Y);

public sealed record StorageRequest(int X, int Y, Guid Id);

public sealed record SplitterRequest(int X, int Y, Guid Id, int Side, List<string>? Items);

public sealed record StorageItemRequest(int X, int Y, Guid Id, string Item, int Quantity);

/// <summary>The belts, inserters and storage of a plot; the client asks again every moment it watches them.</summary>
public sealed class GetLogisticsHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "logistics.get";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<LogisticsRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var state = await scope.ServiceProvider.GetRequiredService<LogisticsService>()
            .StateAsync(client.RequireAccount(), request.X, request.Y, cancellationToken);
        return new Reply("logistics", Json(request.X, request.Y, state));
    }

    public static object Json(int x, int y, LogisticsState state)
    {
        Contents Of(Guid id) => state.Contents.GetValueOrDefault(id) ?? new Contents();
        return new
        {
            x,
            y,
            // Unix milliseconds: the client goes on from simulatedAt with the same rules for its animation.
            simulatedAt = state.SimulatedAt.ToUnixTimeMilliseconds(),
            serverTime = state.ServerTime.ToUnixTimeMilliseconds(),
            tickMs = LogisticsRules.Tick.TotalMilliseconds,
            beltSlots = LogisticsRules.BeltSlots,
            beltLanes = LogisticsRules.BeltLanes,
            swingTicks = LogisticsRules.SwingTicks,
            belts = state.Objects.Where(o => Items.IsBelt(o.Kind) || o.Kind == Items.Splitter)
                .Select(o => new
                {
                    id = o.Id,
                    // Places an item moves along it a tick; a splitter goes as fast as the belt behind it, which the client works out.
                    speed = LogisticsRules.BeltSpeed(o.Kind),
                    items = Of(o.Id).Belt ?? new string?[LogisticsRules.BeltSlots * LogisticsRules.BeltLanes],
                    // Splitters only: the items sorted out and the side they go to.
                    filter = o.Kind == Items.Splitter ? Of(o.Id).Filter ?? [] : null,
                    filterSide = Of(o.Id).FilterSide,
                    turn = Of(o.Id).Turn,
                }),
            // What every item is called, for choosing a splitter's filter.
            names = state.Objects.Any(o => o.Kind == Items.Splitter) ? Items.Names : null,
            inserters = state.Objects.Where(o => Items.IsInserter(o.Kind))
                .Select(o => new
                {
                    id = o.Id,
                    hand = Of(o.Id).Hand,
                    swing = Of(o.Id).Swing,
                    swingTicks = LogisticsRules.Swing(o.Kind),
                    // How fast it works on the power it has (0 stands still), and the power gathered for its next move.
                    speed = state.Power.Clock(o.Id).Speed(state.SimulatedAt),
                    charge = Of(o.Id).Charge,
                }),
            storages = state.Objects.Where(o => Storages.Find(o.Kind) is not null)
                .Select(o => StorageSummary(Storages.Find(o.Kind)!, o, Of(o.Id))),
            power = state.Power.Summary(state.ServerTime),
        };
    }

    public static object StorageSummary(StorageKind kind, PlotObject o, Contents contents)
    {
        var stacks = contents.Items ?? [];
        return new
        {
            id = o.Id,
            kind = o.Kind,
            name = Items.Names[o.Kind],
            slots = kind.Slots,
            slotSize = kind.SlotSize,
            usedSlots = Storages.UsedSlots(kind, stacks),
            capacity = kind.Capacity,
            stored = stacks.Sum(s => s.Quantity),
            only = kind.Only?.Select(i => new { id = i, name = Items.Names[i] }),
            items = stacks.Select(s => new { id = s.Item, name = Items.Names.GetValueOrDefault(s.Item, s.Item), quantity = s.Quantity }),
        };
    }
}

/// <summary>Sets a splitter's filter; answers with the plot's logistics like "logistics.get".</summary>
public sealed class SetSplitterHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "splitter.set";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<SplitterRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var state = await scope.ServiceProvider.GetRequiredService<LogisticsService>().SetSplitterAsync(
            client.RequireAccount(), request.X, request.Y, request.Id, request.Side, request.Items ?? [], cancellationToken);
        return new Reply("logistics", GetLogisticsHandler.Json(request.X, request.Y, state));
    }
}

public abstract class StorageHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var (state, storage) = await RunAsync(scope.ServiceProvider.GetRequiredService<LogisticsService>(), client.RequireAccount(), payload, cancellationToken);
        return new Reply("storage", GetLogisticsHandler.StorageSummary(
            Storages.Find(storage.Kind)!, storage, state.Contents.GetValueOrDefault(storage.Id) ?? new Contents()));
    }

    protected abstract Task<(LogisticsState, PlotObject)> RunAsync(LogisticsService logistics, Guid player, JsonElement? payload, CancellationToken cancellationToken);
}

/// <summary>What a storage holds now.</summary>
public sealed class GetStorageHandler(IServiceScopeFactory scopes) : StorageHandler(scopes)
{
    public override string Type => "storage.get";

    protected override Task<(LogisticsState, PlotObject)> RunAsync(LogisticsService logistics, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<StorageRequest>(payload);
        return ReadAsync(logistics, player, request, cancellationToken);
    }

    private static async Task<(LogisticsState, PlotObject)> ReadAsync(LogisticsService logistics, Guid player, StorageRequest request, CancellationToken cancellationToken)
    {
        var state = await logistics.StateAsync(player, request.X, request.Y, cancellationToken);
        var storage = state.Objects.FirstOrDefault(o => o.Id == request.Id && Storages.Find(o.Kind) is not null)
            ?? throw new GameException("no_object", "There is no such storage on this plot.");
        return (state, storage);
    }
}

public sealed class PutStorageHandler(IServiceScopeFactory scopes) : StorageHandler(scopes)
{
    public override string Type => "storage.put";

    protected override Task<(LogisticsState, PlotObject)> RunAsync(LogisticsService logistics, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<StorageItemRequest>(payload);
        return logistics.PutAsync(player, request.X, request.Y, request.Id, request.Item ?? "", request.Quantity, cancellationToken);
    }
}

public sealed class TakeStorageHandler(IServiceScopeFactory scopes) : StorageHandler(scopes)
{
    public override string Type => "storage.take";

    protected override Task<(LogisticsState, PlotObject)> RunAsync(LogisticsService logistics, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<StorageItemRequest>(payload);
        return logistics.TakeAsync(player, request.X, request.Y, request.Id, request.Item ?? "", request.Quantity, cancellationToken);
    }
}

/// <summary>Belts and inserters that move items around a plot, and chests, piles, heaps and silos
/// that store them. Owns the <c>logistics</c> schema.</summary>
public sealed class LogisticsModule : IGameModule
{
    public string Name => "Logistics";

    public void RegisterServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddModuleDbContext<LogisticsDbContext>(LogisticsDbContext.Schema);
        services.AddScoped<LogisticsService>();
        services.AddScoped<IPlotAutomation>(provider => provider.GetRequiredService<LogisticsService>());
        services.AddScoped<IMachineContents, LogisticsContents>();
        services.AddSingleton<IMessageHandler, GetLogisticsHandler>();
        services.AddSingleton<IMessageHandler, SetSplitterHandler>();
        services.AddSingleton<IMessageHandler, GetStorageHandler>();
        services.AddSingleton<IMessageHandler, PutStorageHandler>();
        services.AddSingleton<IMessageHandler, TakeStorageHandler>();
    }

    public Task InitializeAsync(IServiceProvider services, CancellationToken cancellationToken) =>
        services.MigrateModuleAsync<LogisticsDbContext>(cancellationToken);
}
