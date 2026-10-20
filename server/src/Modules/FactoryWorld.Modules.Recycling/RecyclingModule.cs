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

public sealed class Garage
{
    public Guid OwnerId { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
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

public sealed record GarageState(
    long Trash,
    IReadOnlyList<DateTimeOffset> Queue,
    DateTimeOffset ServerTime,
    IReadOnlyList<string> Results,
    XpGain? Xp);

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
            await using (var lockGarage = await db.CommandAsync(
                "SELECT 1 FROM recycling.garages WHERE owner_id = @owner FOR UPDATE", cancellationToken))
            {
                lockGarage.Parameters.AddWithValue("owner", owner);
                await lockGarage.ExecuteNonQueryAsync(cancellationToken);
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

    private async Task EnsureGarageAsync(Guid owner, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "INSERT INTO recycling.garages (owner_id, created_at) VALUES (@owner, @at) ON CONFLICT DO NOTHING", cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        command.Parameters.AddWithValue("at", time.GetUtcNow());
        if (await command.ExecuteNonQueryAsync(cancellationToken) == 1)
        {
            await inventory.AddAsync(owner, Items.Trash, RecyclingRules.StartingTrash, cancellationToken);
        }
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
            xp);
}

public sealed record SortRequest(int Count);

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
            queue = state.Queue,
            serverTime = state.ServerTime,
            sortSeconds = RecyclingRules.SortTime.TotalSeconds,
            maxQueue = RecyclingRules.MaxQueue,
            results = state.Results.Select(id => new { id, name = Items.Names[id] }),
            xp = state.Xp is { } xp ? new { xp = xp.Xp, level = xp.Level, leveledUp = xp.LeveledUp } : null,
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

/// <summary>The garage with its trash bin and sorting. Owns the <c>recycling</c> schema.</summary>
public sealed class RecyclingModule : IGameModule
{
    public string Name => "Recycling";

    public void RegisterServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddModuleDbContext<RecyclingDbContext>(RecyclingDbContext.Schema);
        services.AddScoped<RecyclingService>();
        services.AddSingleton<IMessageHandler, GetGarageHandler>();
        services.AddSingleton<IMessageHandler, SortHandler>();
    }

    public Task InitializeAsync(IServiceProvider services, CancellationToken cancellationToken) =>
        services.MigrateModuleAsync<RecyclingDbContext>(cancellationToken);
}
