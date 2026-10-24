using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Crafting;

/// <summary>Something made at a workbench or an anvil: what it takes, how long, and what comes out.</summary>
/// <param name="Id">The recipe's id, the same as the item it makes.</param>
/// <param name="Station">Where it is made: <see cref="Items.Workbench"/> or <see cref="Items.Anvil"/>.</param>
public sealed record Recipe(
    string Id, int Quantity, TimeSpan Time, IReadOnlyList<(string Item, int Quantity)> Ingredients, int Xp, string Station = Items.Workbench);

/// <summary>
/// At a workbench (the one in the garage or one put on a plot) or an anvil, which forges the tools,
/// the player picks a recipe and orders it. Both share one queue. The ingredients are taken at once; the item is made after the recipe's time, one
/// order after another, and lands in the inventory even when the player has walked away.
/// </summary>
public static class Workshop
{
    /// <summary>Orders that can wait in the queue, the one being made included.</summary>
    public const int MaxQueue = 5;

    public static readonly IReadOnlyList<Recipe> Recipes =
    [
        new(Items.Workbench, 1, TimeSpan.FromSeconds(30), [(Items.Wood, 20), (Items.Nails, 5)], 10),
        new(Items.Furnace, 1, TimeSpan.FromSeconds(45), [(Items.Stone, 20)], 15),
        new(Items.Nails, 5, TimeSpan.FromSeconds(10), [(Items.IronIngot, 1)], 2),
        new(Items.Belt, 4, TimeSpan.FromSeconds(10), [(Items.IronIngot, 2), (Items.Wood, 1)], 3),
        new(Items.Inserter, 1, TimeSpan.FromSeconds(15), [(Items.IronIngot, 2), (Items.CopperIngot, 1), (Items.Nails, 5)], 5),
        new(Items.Splitter, 1, TimeSpan.FromSeconds(20), [(Items.Belt, 2), (Items.IronIngot, 4), (Items.CopperIngot, 2)], 6),
        new(Items.WoodenChest, 1, TimeSpan.FromSeconds(10), [(Items.Wood, 10), (Items.Nails, 5)], 3),
        new(Items.IronChest, 1, TimeSpan.FromSeconds(20), [(Items.IronIngot, 8)], 6),
        new(Items.WoodPile, 1, TimeSpan.FromSeconds(5), [(Items.Wood, 4)], 1),
        new(Items.Heap, 1, TimeSpan.FromSeconds(10), [(Items.Stone, 10), (Items.Wood, 4)], 2),
        new(Items.GrainSilo, 1, TimeSpan.FromSeconds(40), [(Items.IronIngot, 10), (Items.Stone, 20), (Items.Nails, 10)], 10),
        new(Items.Mill, 1, TimeSpan.FromSeconds(60), [(Items.Stone, 30), (Items.Wood, 10), (Items.IronIngot, 2)], 20),
        new(Items.OilPress, 1, TimeSpan.FromSeconds(60), [(Items.Wood, 15), (Items.IronIngot, 4), (Items.Nails, 10)], 20),
        new(Items.PicklingBarrel, 1, TimeSpan.FromSeconds(30), [(Items.Wood, 12), (Items.Nails, 5)], 10),
        new(Items.Bakery, 1, TimeSpan.FromSeconds(90), [(Items.Stone, 40), (Items.IronIngot, 3), (Items.Sand, 10)], 30),
        new(Items.Kitchen, 1, TimeSpan.FromSeconds(90), [(Items.Stone, 20), (Items.IronIngot, 5), (Items.CopperIngot, 2)], 30),
        new(Items.Anvil, 1, TimeSpan.FromSeconds(60), [(Items.IronIngot, 15), (Items.Stone, 10)], 20),
        new(Items.Axe, 1, TimeSpan.FromSeconds(20), [(Items.IronIngot, 3), (Items.Wood, 2)], 5, Items.Anvil),
        new(Items.Shovel, 1, TimeSpan.FromSeconds(20), [(Items.IronIngot, 2), (Items.Wood, 2)], 5, Items.Anvil),
        new(Items.Pickaxe, 1, TimeSpan.FromSeconds(20), [(Items.IronIngot, 3), (Items.Wood, 2)], 5, Items.Anvil),
        new(Items.Hoe, 1, TimeSpan.FromSeconds(20), [(Items.IronIngot, 2), (Items.Wood, 2)], 5, Items.Anvil),
    ];

    public static Recipe? Find(string id) => Recipes.FirstOrDefault(r => r.Id == id);

    /// <summary>Fails unless the player has an object of <paramref name="kind"/> with this id, in the garage or on a plot.</summary>
    public static async Task RequireAsync(IEnumerable<IPlacedObjects> places, Guid owner, Guid id, string kind, CancellationToken cancellationToken)
    {
        foreach (var place in places)
        {
            if (await place.KindAsync(owner, id, cancellationToken) is { } found)
            {
                if (found == kind)
                {
                    return;
                }

                break;
            }
        }

        throw new GameException("no_object", $"There is no {Items.Names[kind]} of yours here.");
    }
}

public sealed record CraftingJob(long Id, string Recipe, DateTimeOffset StartsAt, DateTimeOffset FinishesAt);

public sealed record CraftingState(
    IReadOnlyList<CraftingJob> Queue,
    DateTimeOffset ServerTime,
    IReadOnlyList<(string Item, int Quantity)> Done,
    XpGain? Xp);

public sealed class CraftingService(
    GameDb db, IEnumerable<IPlacedObjects> places, IInventory inventory, ICharacterProgress progress, IProductionStats stats, ITechnologies technologies, TimeProvider time)
{
    /// <summary>The queue as it is now, after handing out every order that is done.</summary>
    public Task<CraftingState> StateAsync(Guid owner, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var (done, xp) = await CompleteDueAsync(owner, cancellationToken);
            return new CraftingState(await QueueAsync(owner, cancellationToken), time.GetUtcNow(), done, xp);
        }, cancellationToken);

    /// <summary>Orders a recipe at one of the player's workbenches or anvils: ingredients out now, the item later.</summary>
    public Task<CraftingState> CraftAsync(Guid owner, Guid workbench, string recipeId, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var recipe = Workshop.Find(recipeId) ?? throw new GameException("no_recipe", "There is no such recipe.");
            await Workshop.RequireAsync(places, owner, workbench, recipe.Station, cancellationToken);
            await technologies.RequireUnlockedAsync(owner, recipe.Id, cancellationToken);
            var (done, xp) = await CompleteDueAsync(owner, cancellationToken);

            // One order at a time per player, so two at once cannot both take the last queue slot.
            await using (var lockOwner = await db.CommandAsync("SELECT pg_advisory_xact_lock(@key)", cancellationToken))
            {
                lockOwner.Parameters.AddWithValue("key", BitConverter.ToInt64(owner.ToByteArray()) ^ 0x6372616674);
                await lockOwner.ExecuteNonQueryAsync(cancellationToken);
            }

            var queue = await QueueAsync(owner, cancellationToken);
            if (queue.Count >= Workshop.MaxQueue)
            {
                throw new GameException("crafting_queue_full", $"At most {Workshop.MaxQueue} orders can wait at the workbench.");
            }

            foreach (var (item, quantity) in recipe.Ingredients)
            {
                await inventory.RemoveAsync(owner, item, quantity, cancellationToken);
            }

            var now = time.GetUtcNow();
            var start = queue.Count > 0 && queue[^1].FinishesAt > now ? queue[^1].FinishesAt : now;
            await using (var insert = await db.CommandAsync(
                "INSERT INTO crafting.jobs (owner_id, recipe, starts_at, finishes_at) VALUES (@owner, @recipe, @start, @end)", cancellationToken))
            {
                insert.Parameters.AddWithValue("owner", owner);
                insert.Parameters.AddWithValue("recipe", recipe.Id);
                insert.Parameters.AddWithValue("start", start);
                insert.Parameters.AddWithValue("end", start + recipe.Time);
                await insert.ExecuteNonQueryAsync(cancellationToken);
            }

            return new CraftingState(await QueueAsync(owner, cancellationToken), now, done, xp);
        }, cancellationToken);

    /// <summary>Calls off an order that is not done yet: its ingredients come back and the later orders move up.</summary>
    public Task<CraftingState> CancelAsync(Guid owner, long id, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var (done, xp) = await CompleteDueAsync(owner, cancellationToken);
            await using (var delete = await db.CommandAsync(
                "DELETE FROM crafting.jobs WHERE id = @id AND owner_id = @owner RETURNING recipe, starts_at, finishes_at", cancellationToken))
            {
                delete.Parameters.AddWithValue("id", id);
                delete.Parameters.AddWithValue("owner", owner);
                string recipeId;
                DateTimeOffset startsAt, finishesAt;
                await using (var reader = await delete.ExecuteReaderAsync(cancellationToken))
                {
                    if (!await reader.ReadAsync(cancellationToken))
                    {
                        throw new GameException("no_order", "There is no such order.");
                    }

                    recipeId = reader.GetString(0);
                    startsAt = reader.GetFieldValue<DateTimeOffset>(1);
                    finishesAt = reader.GetFieldValue<DateTimeOffset>(2);
                }

                var now = time.GetUtcNow();
                var shift = finishesAt - (startsAt > now ? startsAt : now);
                await using var move = await db.CommandAsync(
                    """
                    UPDATE crafting.jobs SET starts_at = starts_at - @shift, finishes_at = finishes_at - @shift
                    WHERE owner_id = @owner AND starts_at >= @end
                    """, cancellationToken);
                move.Parameters.AddWithValue("owner", owner);
                move.Parameters.AddWithValue("shift", shift);
                move.Parameters.AddWithValue("end", finishesAt);
                await move.ExecuteNonQueryAsync(cancellationToken);

                if (Workshop.Find(recipeId) is { } recipe)
                {
                    foreach (var (item, quantity) in recipe.Ingredients)
                    {
                        await inventory.AddAsync(owner, item, quantity, cancellationToken);
                    }
                }
            }

            return new CraftingState(await QueueAsync(owner, cancellationToken), time.GetUtcNow(), done, xp);
        }, cancellationToken);

    private async Task<(IReadOnlyList<(string Item, int Quantity)> Done, XpGain? Xp)> CompleteDueAsync(Guid owner, CancellationToken cancellationToken)
    {
        // DELETE ... RETURNING hands each finished order to exactly one request, so an item is never given twice.
        await using var command = await db.CommandAsync(
            "DELETE FROM crafting.jobs WHERE owner_id = @owner AND finishes_at <= @now RETURNING recipe, finishes_at", cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        command.Parameters.AddWithValue("now", time.GetUtcNow());
        var recipes = new List<Recipe>();
        var made = new List<ProductionEntry>();
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                if (Workshop.Find(reader.GetString(0)) is { } recipe)
                {
                    recipes.Add(recipe);
                    var at = reader.GetFieldValue<DateTimeOffset>(1);
                    made.Add(ProductionEntry.Made(recipe.Id, recipe.Quantity, at));
                    made.AddRange(recipe.Ingredients.Select(i => ProductionEntry.Used(i.Item, i.Quantity, at)));
                }
            }
        }

        if (recipes.Count == 0)
        {
            return ([], null);
        }

        await stats.RecordAsync(owner, made, cancellationToken);
        var done = recipes.GroupBy(r => r.Id).Select(g => (g.Key, g.Sum(r => r.Quantity))).ToList();
        foreach (var (item, quantity) in done)
        {
            await inventory.AddAsync(owner, item, quantity, cancellationToken);
        }

        var xp = await progress.AddXpAsync(owner, recipes.Sum(r => r.Xp), cancellationToken);
        return (done, xp);
    }

    private async Task<List<CraftingJob>> QueueAsync(Guid owner, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT id, recipe, starts_at, finishes_at FROM crafting.jobs WHERE owner_id = @owner ORDER BY finishes_at", cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var queue = new List<CraftingJob>();
        while (await reader.ReadAsync(cancellationToken))
        {
            queue.Add(new CraftingJob(reader.GetInt64(0), reader.GetString(1), reader.GetFieldValue<DateTimeOffset>(2), reader.GetFieldValue<DateTimeOffset>(3)));
        }

        return queue;
    }
}

public sealed record CraftRequest(Guid Workbench, string Recipe);

public sealed record CancelCraftRequest(long Id);

public abstract class CraftingHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var owner = client.RequireAccount();
        var state = await RunAsync(scope.ServiceProvider.GetRequiredService<CraftingService>(), owner, payload, cancellationToken);
        var locked = await scope.ServiceProvider.GetRequiredService<ITechnologies>().LockedAsync(owner, cancellationToken);
        return new Reply("crafting", new
        {
            recipes = Workshop.Recipes.Select(r => new
            {
                id = r.Id,
                name = Items.Names[r.Id],
                quantity = r.Quantity,
                seconds = r.Time.TotalSeconds,
                ingredients = r.Ingredients.Select(i => new { id = i.Item, name = Items.Names[i.Item], quantity = i.Quantity }),
                xp = r.Xp,
                // The technology still to research before the recipe can be ordered, or null.
                locked = locked.GetValueOrDefault(r.Id),
                station = r.Station,
            }),
            // Unix milliseconds: the client compares them with serverTime, not its own clock.
            queue = state.Queue.Select(j => new
            {
                id = j.Id,
                recipe = j.Recipe,
                name = Items.Names.GetValueOrDefault(j.Recipe, j.Recipe),
                startsAt = j.StartsAt.ToUnixTimeMilliseconds(),
                finishesAt = j.FinishesAt.ToUnixTimeMilliseconds(),
            }),
            maxQueue = Workshop.MaxQueue,
            serverTime = state.ServerTime.ToUnixTimeMilliseconds(),
            done = state.Done.Select(d => new { id = d.Item, name = Items.Names[d.Item], quantity = d.Quantity }),
            xp = state.Xp is { } xp ? new { xp = xp.Xp, level = xp.Level, leveledUp = xp.LeveledUp } : null,
        });
    }

    protected abstract Task<CraftingState> RunAsync(CraftingService crafting, Guid owner, JsonElement? payload, CancellationToken cancellationToken);
}

/// <summary>The recipes and the player's orders; also hands out the finished ones, so the client calls it when a timer runs out.</summary>
public sealed class GetCraftingHandler(IServiceScopeFactory scopes) : CraftingHandler(scopes)
{
    public override string Type => "crafting.get";

    protected override Task<CraftingState> RunAsync(CraftingService crafting, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        crafting.StateAsync(owner, cancellationToken);
}

public sealed class CraftHandler(IServiceScopeFactory scopes) : CraftingHandler(scopes)
{
    public override string Type => "crafting.craft";

    protected override Task<CraftingState> RunAsync(CraftingService crafting, Guid owner, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<CraftRequest>(payload);
        return crafting.CraftAsync(owner, request.Workbench, request.Recipe ?? "", cancellationToken);
    }
}

public sealed class CancelCraftHandler(IServiceScopeFactory scopes) : CraftingHandler(scopes)
{
    public override string Type => "crafting.cancel";

    protected override Task<CraftingState> RunAsync(CraftingService crafting, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        crafting.CancelAsync(owner, Payload.Read<CancelCraftRequest>(payload).Id, cancellationToken);
}
