using System.Security.Cryptography;
using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Recycling;

public static class RecyclingRules
{
    /// <summary>Trash in the bin of a brand new garage.</summary>
    public const int StartingTrash = 50;

    public static readonly TimeSpan SortTime = TimeSpan.FromSeconds(10);

    /// <summary>Sortings a player can queue; they keep running while the player is offline.</summary>
    public const int MaxQueue = 10;

    public const int XpPerSort = 5;

    /// <summary>What one sorting gives, by chance in percent (sums to 100).</summary>
    public static readonly (string Item, int Percent)[] Drops =
    [
        (Items.WastePaper, 30),
        (Items.WastePlastic, 25),
        (Items.WasteAluminium, 20),
        (Items.WasteGlass, 15),
        (Items.WasteCopper, 10),
    ];

    /// <summary>The item for a roll of 0-99.</summary>
    public static string DropForRoll(int roll)
    {
        foreach (var (item, percent) in Drops)
        {
            if (roll < percent)
            {
                return item;
            }

            roll -= percent;
        }

        throw new ArgumentOutOfRangeException(nameof(roll));
    }
}

/// <summary>The garage floor, a grid of square cells, and the furniture that can stand on it.
/// Cells are counted from the front-left corner of the floor: x to the right, y towards the back
/// wall. A piece of furniture stands on whole cells; its position is its front-left cell. Its
/// rotation (0-3) counts quarter turns anticlockwise seen from above; 0 faces the camera.</summary>
public static class GarageLayout
{
    /// <summary>Side of one cell, in metres.</summary>
    public const double CellSize = 0.5;

    public const int Width = 16;
    public const int Depth = 12;

    /// <summary>Cells taken (width along x, depth along y) by everything that can be placed.</summary>
    public static readonly IReadOnlyDictionary<string, (int Width, int Depth)> Footprints =
        new Dictionary<string, (int, int)>
        {
            [Items.TrashBin] = (2, 2),
            [Items.Workbench] = (5, 2),
            [Items.Shelf] = (4, 1),
            [Items.BarrelBlue] = (1, 1),
            [Items.BarrelRed] = (1, 1),
            [Items.Tyres] = (2, 2),
            [Items.Pallet] = (2, 2),
            [Items.GasCylinder] = (1, 1),
        };

    /// <summary>How a new garage is furnished.</summary>
    public static readonly (string Kind, int X, int Y)[] Starter =
    [
        (Items.TrashBin, 5, 8),
        (Items.Workbench, 10, 10),
        (Items.GasCylinder, 9, 11),
        (Items.Shelf, 1, 5),
        (Items.BarrelBlue, 15, 5),
        (Items.BarrelRed, 15, 3),
        (Items.Tyres, 12, 1),
        (Items.Pallet, 2, 1),
    ];

    /// <summary>Cells taken by a piece of furniture turned by `rotation` quarter turns.</summary>
    public static (int Width, int Depth) Size(string kind, int rotation)
    {
        var (w, d) = Footprints[kind];
        return rotation % 2 == 0 ? (w, d) : (d, w);
    }

    /// <summary>Whether a piece of furniture on cell (x, y) fits inside the walls.</summary>
    public static bool InsideRoom(string kind, int x, int y, int rotation = 0)
    {
        var (w, d) = Size(kind, rotation);
        return x >= 0 && y >= 0 && x + w <= Width && y + d <= Depth;
    }

    public static bool Overlaps(PlacedObject a, PlacedObject b)
    {
        var (aw, ad) = Size(a.Kind, a.Rotation);
        var (bw, bd) = Size(b.Kind, b.Rotation);
        return a.X < b.X + bw && b.X < a.X + aw && a.Y < b.Y + bd && b.Y < a.Y + ad;
    }
}

public sealed class Garage
{
    public Guid OwnerId { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>Set once the starter furniture has been put in, so it is never put in twice.</summary>
    public bool Furnished { get; set; }
}

public sealed class GarageObject
{
    public Guid Id { get; set; }

    public Guid OwnerId { get; set; }

    public string Kind { get; set; } = "";

    public int X { get; set; }

    public int Y { get; set; }

    public int Rotation { get; set; }
}

/// <summary>One queued sorting. The trash is taken when queued; the result is rolled when it finishes.</summary>
public sealed class SortingJob
{
    public long Id { get; set; }

    public Guid OwnerId { get; set; }

    public DateTimeOffset FinishesAt { get; set; }
}

public sealed class RecyclingDbContext(DbContextOptions<RecyclingDbContext> options, GameDb gameDb) : ModuleDbContext(options, gameDb)
{
    public const string Schema = "recycling";

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.HasDefaultSchema(Schema);
        model.Entity<Garage>(e =>
        {
            e.ToTable("garages");
            e.HasKey(g => g.OwnerId);
            e.Property(g => g.OwnerId).HasColumnName("owner_id");
            e.Property(g => g.CreatedAt).HasColumnName("created_at");
            e.Property(g => g.Furnished).HasColumnName("furnished");
        });
        model.Entity<GarageObject>(e =>
        {
            e.ToTable("garage_objects");
            e.HasKey(o => o.Id);
            e.Property(o => o.Id).HasColumnName("id");
            e.Property(o => o.OwnerId).HasColumnName("owner_id");
            e.Property(o => o.Kind).HasColumnName("kind").HasMaxLength(32);
            e.Property(o => o.X).HasColumnName("x");
            e.Property(o => o.Y).HasColumnName("y");
            e.Property(o => o.Rotation).HasColumnName("rotation");
            e.HasIndex(o => o.OwnerId);
        });
        model.Entity<SortingJob>(e =>
        {
            e.ToTable("sorting_jobs");
            e.Property(j => j.Id).HasColumnName("id");
            e.Property(j => j.OwnerId).HasColumnName("owner_id");
            e.Property(j => j.FinishesAt).HasColumnName("finishes_at");
            e.HasIndex(j => new { j.OwnerId, j.FinishesAt });
        });
    }
}

public sealed record PlacedObject(Guid Id, string Kind, int X, int Y, int Rotation = 0);

public sealed record GarageState(
    long Trash,
    IReadOnlyList<DateTimeOffset> Queue,
    DateTimeOffset ServerTime,
    IReadOnlyList<string> Results,
    XpGain? Xp,
    IReadOnlyList<PlacedObject> Objects);

public sealed class RecyclingService(GameDb db, IInventory inventory, ICharacterProgress progress, TimeProvider time)
{
    /// <summary>The garage as it is now, after finishing every sorting whose time has come.</summary>
    public Task<GarageState> StateAsync(Guid owner, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            await EnsureGarageAsync(owner, cancellationToken);
            var (results, xp) = await CompleteDueAsync(owner, cancellationToken);
            return await ReadStateAsync(owner, results, xp, cancellationToken);
        }, cancellationToken);

    /// <summary>Queues <paramref name="count"/> sortings, taking one trash for each.</summary>
    public Task<GarageState> SortAsync(Guid owner, int count, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (count is < 1 or > RecyclingRules.MaxQueue)
            {
                throw new GameException("bad_quantity", $"You can sort 1-{RecyclingRules.MaxQueue} at once.");
            }

            await EnsureGarageAsync(owner, cancellationToken);
            var (results, xp) = await CompleteDueAsync(owner, cancellationToken);

            // Lock the garage row so two requests cannot both fill the last queue slots.
            await LockGarageAsync(owner, cancellationToken);

            if (!(await ObjectsAsync(owner, cancellationToken)).Any(o => o.Kind == Items.TrashBin))
            {
                throw new GameException("no_bin", "Put the trash bin in the garage first.");
            }

            var queue = await QueueAsync(owner, cancellationToken);
            if (queue.Count + count > RecyclingRules.MaxQueue)
            {
                throw new GameException("queue_full", $"At most {RecyclingRules.MaxQueue} sortings can wait in the queue.");
            }

            await inventory.RemoveAsync(owner, Items.Trash, count, cancellationToken);

            var now = time.GetUtcNow();
            var start = queue.Count > 0 && queue[^1] > now ? queue[^1] : now;
            for (var i = 1; i <= count; i++)
            {
                await using var insert = await db.CommandAsync(
                    "INSERT INTO recycling.sorting_jobs (owner_id, finishes_at) VALUES (@owner, @at)", cancellationToken);
                insert.Parameters.AddWithValue("owner", owner);
                insert.Parameters.AddWithValue("at", start + RecyclingRules.SortTime * i);
                await insert.ExecuteNonQueryAsync(cancellationToken);
            }

            return await ReadStateAsync(owner, results, xp, cancellationToken);
        }, cancellationToken);

    /// <summary>Puts a piece of furniture from the inventory on the floor, its front-left corner on cell (x, y).</summary>
    public Task<GarageState> PlaceAsync(Guid owner, string kind, int x, int y, int rotation, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (!GarageLayout.Footprints.ContainsKey(kind))
            {
                throw new GameException("not_placeable", "This item cannot be placed.");
            }

            if (rotation is < 0 or > 3 || !GarageLayout.InsideRoom(kind, x, y, rotation))
            {
                throw new GameException("bad_position", "It does not fit inside the garage there.");
            }

            await EnsureGarageAsync(owner, cancellationToken);
            var (results, xp) = await CompleteDueAsync(owner, cancellationToken);
            await LockGarageAsync(owner, cancellationToken);
            var placed = new PlacedObject(Guid.Empty, kind, x, y, rotation);
            if ((await ObjectsAsync(owner, cancellationToken)).Any(o => GarageLayout.Overlaps(placed, o)))
            {
                throw new GameException("blocked", "Something else already stands there.");
            }

            await inventory.RemoveAsync(owner, kind, 1, cancellationToken);
            await InsertObjectAsync(owner, kind, x, y, rotation, cancellationToken);
            return await ReadStateAsync(owner, results, xp, cancellationToken);
        }, cancellationToken);

    /// <summary>Takes a piece of furniture off the floor into the inventory.</summary>
    public Task<GarageState> PickUpAsync(Guid owner, Guid id, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            await EnsureGarageAsync(owner, cancellationToken);
            var (results, xp) = await CompleteDueAsync(owner, cancellationToken);
            await using var command = await db.CommandAsync(
                "DELETE FROM recycling.garage_objects WHERE id = @id AND owner_id = @owner RETURNING kind", cancellationToken);
            command.Parameters.AddWithValue("id", id);
            command.Parameters.AddWithValue("owner", owner);
            var kind = await command.ExecuteScalarAsync(cancellationToken) as string
                ?? throw new GameException("no_object", "There is no such object in your garage.");
            await inventory.AddAsync(owner, kind, 1, cancellationToken);
            return await ReadStateAsync(owner, results, xp, cancellationToken);
        }, cancellationToken);

    private async Task EnsureGarageAsync(Guid owner, CancellationToken cancellationToken)
    {
        await using (var command = await db.CommandAsync(
            "INSERT INTO recycling.garages (owner_id, created_at) VALUES (@owner, @at) ON CONFLICT DO NOTHING", cancellationToken))
        {
            command.Parameters.AddWithValue("owner", owner);
            command.Parameters.AddWithValue("at", time.GetUtcNow());
            if (await command.ExecuteNonQueryAsync(cancellationToken) == 1)
            {
                await inventory.AddAsync(owner, Items.Trash, RecyclingRules.StartingTrash, cancellationToken);
            }
        }

        // Garages made before furniture existed get theirs here too, exactly once.
        await using var furnish = await db.CommandAsync(
            "UPDATE recycling.garages SET furnished = TRUE WHERE owner_id = @owner AND NOT furnished", cancellationToken);
        furnish.Parameters.AddWithValue("owner", owner);
        if (await furnish.ExecuteNonQueryAsync(cancellationToken) == 1)
        {
            foreach (var (kind, x, y) in GarageLayout.Starter)
            {
                await InsertObjectAsync(owner, kind, x, y, 0, cancellationToken);
            }
        }
    }

    private async Task LockGarageAsync(Guid owner, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT 1 FROM recycling.garages WHERE owner_id = @owner FOR UPDATE", cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private async Task InsertObjectAsync(Guid owner, string kind, int x, int y, int rotation, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "INSERT INTO recycling.garage_objects (id, owner_id, kind, x, y, rotation) VALUES (@id, @owner, @kind, @x, @y, @rotation)", cancellationToken);
        command.Parameters.AddWithValue("id", Guid.NewGuid());
        command.Parameters.AddWithValue("owner", owner);
        command.Parameters.AddWithValue("kind", kind);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        command.Parameters.AddWithValue("rotation", rotation);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private async Task<List<PlacedObject>> ObjectsAsync(Guid owner, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT id, kind, x, y, rotation FROM recycling.garage_objects WHERE owner_id = @owner ORDER BY y DESC, x", cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var objects = new List<PlacedObject>();
        while (await reader.ReadAsync(cancellationToken))
        {
            objects.Add(new PlacedObject(reader.GetGuid(0), reader.GetString(1), reader.GetInt32(2), reader.GetInt32(3), reader.GetInt32(4)));
        }

        return objects;
    }

    private async Task<(IReadOnlyList<string> Results, XpGain? Xp)> CompleteDueAsync(Guid owner, CancellationToken cancellationToken)
    {
        // DELETE ... RETURNING hands each finished job to exactly one request, so a result is never given twice.
        await using var command = await db.CommandAsync(
            "DELETE FROM recycling.sorting_jobs WHERE owner_id = @owner AND finishes_at <= @now RETURNING id", cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        command.Parameters.AddWithValue("now", time.GetUtcNow());
        var finished = 0;
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                finished++;
            }
        }

        if (finished == 0)
        {
            return ([], null);
        }

        var results = Enumerable.Range(0, finished)
            .Select(_ => RecyclingRules.DropForRoll(RandomNumberGenerator.GetInt32(100)))
            .ToList();
        foreach (var group in results.GroupBy(r => r))
        {
            await inventory.AddAsync(owner, group.Key, group.Count(), cancellationToken);
        }

        var xp = await progress.AddXpAsync(owner, finished * RecyclingRules.XpPerSort, cancellationToken);
        return (results, xp);
    }

    private async Task<List<DateTimeOffset>> QueueAsync(Guid owner, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT finishes_at FROM recycling.sorting_jobs WHERE owner_id = @owner ORDER BY finishes_at", cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var queue = new List<DateTimeOffset>();
        while (await reader.ReadAsync(cancellationToken))
        {
            queue.Add(reader.GetFieldValue<DateTimeOffset>(0));
        }

        return queue;
    }

    private async Task<GarageState> ReadStateAsync(Guid owner, IReadOnlyList<string> results, XpGain? xp, CancellationToken cancellationToken) =>
        new(await inventory.CountAsync(owner, Items.Trash, cancellationToken),
            await QueueAsync(owner, cancellationToken),
            time.GetUtcNow(),
            results,
            xp,
            await ObjectsAsync(owner, cancellationToken));
}

public sealed record SortRequest(int Count);

public sealed record PlaceRequest(string Kind, int X, int Y, int Rotation = 0);

public sealed record PickUpRequest(Guid Id);

public abstract class GarageHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var state = await RunAsync(scope.ServiceProvider.GetRequiredService<RecyclingService>(), client.RequireAccount(), payload, cancellationToken);
        return new Reply("garage", new
        {
            trash = state.Trash,
            // Unix milliseconds: the client compares them with serverTime, not its own clock.
            queue = state.Queue.Select(t => t.ToUnixTimeMilliseconds()),
            serverTime = state.ServerTime.ToUnixTimeMilliseconds(),
            sortSeconds = RecyclingRules.SortTime.TotalSeconds,
            maxQueue = RecyclingRules.MaxQueue,
            results = state.Results.Select(id => new { id, name = Items.Names[id] }),
            xp = state.Xp is { } xp ? new { xp = xp.Xp, level = xp.Level, leveledUp = xp.LeveledUp } : null,
            room = new { width = GarageLayout.Width, depth = GarageLayout.Depth, cellSize = GarageLayout.CellSize },
            objects = state.Objects.Select(o => new { id = o.Id, kind = o.Kind, x = o.X, y = o.Y, rotation = o.Rotation }),
            furniture = GarageLayout.Footprints.ToDictionary(
                f => f.Key, f => new { name = Items.Names[f.Key], width = f.Value.Width, depth = f.Value.Depth }),
        });
    }

    protected abstract Task<GarageState> RunAsync(RecyclingService recycling, Guid owner, JsonElement? payload, CancellationToken cancellationToken);
}

/// <summary>The garage's state; also collects finished sortings, so the client calls it when a timer runs out.</summary>
public sealed class GetGarageHandler(IServiceScopeFactory scopes) : GarageHandler(scopes)
{
    public override string Type => "garage.get";

    protected override Task<GarageState> RunAsync(RecyclingService recycling, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        recycling.StateAsync(owner, cancellationToken);
}

public sealed class SortHandler(IServiceScopeFactory scopes) : GarageHandler(scopes)
{
    public override string Type => "recycling.sort";

    protected override Task<GarageState> RunAsync(RecyclingService recycling, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        recycling.SortAsync(owner, Payload.Read<SortRequest>(payload).Count, cancellationToken);
}

public sealed class PlaceHandler(IServiceScopeFactory scopes) : GarageHandler(scopes)
{
    public override string Type => "garage.place";

    protected override Task<GarageState> RunAsync(RecyclingService recycling, Guid owner, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<PlaceRequest>(payload);
        return recycling.PlaceAsync(owner, request.Kind ?? "", request.X, request.Y, request.Rotation, cancellationToken);
    }
}

public sealed class PickUpHandler(IServiceScopeFactory scopes) : GarageHandler(scopes)
{
    public override string Type => "garage.pickup";

    protected override Task<GarageState> RunAsync(RecyclingService recycling, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        recycling.PickUpAsync(owner, Payload.Read<PickUpRequest>(payload).Id, cancellationToken);
}

/// <summary>The garage with its furniture, trash bin and sorting. Owns the <c>recycling</c> schema.</summary>
public sealed class RecyclingModule : IGameModule
{
    public string Name => "Recycling";

    public void RegisterServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddModuleDbContext<RecyclingDbContext>(RecyclingDbContext.Schema);
        services.AddScoped<RecyclingService>();
        services.AddSingleton<IMessageHandler, GetGarageHandler>();
        services.AddSingleton<IMessageHandler, SortHandler>();
        services.AddSingleton<IMessageHandler, PlaceHandler>();
        services.AddSingleton<IMessageHandler, PickUpHandler>();
    }

    public Task InitializeAsync(IServiceProvider services, CancellationToken cancellationToken) =>
        services.MigrateModuleAsync<RecyclingDbContext>(cancellationToken);
}
