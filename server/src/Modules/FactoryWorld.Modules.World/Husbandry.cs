using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.World;

/// <param name="Item">The animal as it lies in the inventory, so its id is the item's.</param>
/// <param name="Product">What a fed animal gives once <see cref="Time"/> has passed.</param>
/// <param name="Yield">Products one collection gives.</param>
/// <param name="Time">How long a fed animal takes to give its product on a plot without a husbandry bonus.</param>
/// <param name="Tool">The tool in hand needed to collect the product, or null for bare hands.</param>
public sealed record Animal(string Item, string Product, int Yield, TimeSpan Time, string? Tool, int Xp);

/// <summary>
/// Animals bought on the market are let out on a free tile of a pasture (a plot of a biome with
/// grass), fed a few crops and, after their time, give their product: a hen eggs, a sheep wool
/// (cut with shears), a cow milk. A fed animal gives once, then wants feeding again. The steppe
/// and fertile soils raise animals faster; nothing lives on a desert or a glacier. An animal is
/// taken back into the inventory with what it was going to give, if anything, lost.
/// </summary>
public static class Husbandry
{
    /// <summary>Every animal, in the order the client lists them.</summary>
    public static readonly IReadOnlyList<Animal> Animals =
    [
        new(Items.Chicken, Items.Egg, 2, TimeSpan.FromMinutes(4), null, 2),
        new(Items.Sheep, Items.Wool, 2, TimeSpan.FromMinutes(8), Items.Shears, 5),
        new(Items.Cow, Items.Milk, 3, TimeSpan.FromMinutes(12), null, 7),
    ];

    public static readonly IReadOnlyDictionary<string, Animal> ById = Animals.ToDictionary(a => a.Item);

    /// <summary>What any animal eats, <see cref="FeedPerMeal"/> of one kind per feeding: crops, and fish meal from the cannery.</summary>
    public static readonly IReadOnlyList<string> Feed = [Items.Wheat, Items.Corn, Items.Carrot, Items.Cabbage, Items.FishMeal];

    public const int FeedPerMeal = 2;

    public const int XpPerRelease = 1;

    /// <summary>
    /// The biome's husbandry bonus in percent, as the map lists it: the steppe raises animals 25%
    /// faster, fertile soils 20% faster, and no animal lives on a desert or a glacier (null).
    /// </summary>
    public static int? BonusPercent(Biome biome) => biome switch
    {
        Biome.Grassland => 25,
        Biome.Farmland => 20,
        Biome.Desert or Biome.Ice => null,
        _ => 0,
    };

    /// <summary>Whether animals can be kept on a plot of a biome.</summary>
    public static bool Pasture(Biome biome) => BonusPercent(biome) is not null;

    /// <summary>How long a fed animal takes to give its product on a plot of a biome; null where no animal lives.</summary>
    public static TimeSpan? Time(Animal animal, Biome biome) => BonusPercent(biome) is { } bonus ? animal.Time * (100 - bonus) / 100.0 : null;
}

/// <param name="ReadyAt">When the animal gives its product; null while it is hungry.</param>
public sealed record PlotAnimal(int TileX, int TileY, string Kind, DateTimeOffset? ReadyAt);

/// <param name="Animal">The animal after the action; null when it was taken off the plot.</param>
/// <param name="Items">What collecting gave; empty otherwise.</param>
/// <param name="Xp">Null when the action gives no experience.</param>
public sealed record AnimalChange(PlotAnimal? Animal, IReadOnlyList<(string Item, int Quantity)> Items, XpGain? Xp);

public sealed class HusbandryService(
    GameDb db, PlotService plots, IInventory inventory, ICharacterProgress progress, IProductionStats stats, TimeProvider time)
{
    public async Task<IReadOnlyList<PlotAnimal>> AnimalsAsync(int x, int y, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT tile_x, tile_y, kind, ready_at FROM world.plot_animals WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var animals = new List<PlotAnimal>();
        while (await reader.ReadAsync(cancellationToken))
        {
            animals.Add(new PlotAnimal(reader.GetInt32(0), reader.GetInt32(1), reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetFieldValue<DateTimeOffset>(3)));
        }

        return animals;
    }

    /// <summary>Lets an animal from the inventory out on a free tile of a pasture.</summary>
    public Task<AnimalChange> ReleaseAsync(Guid player, int x, int y, int tileX, int tileY, string kind, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (!Husbandry.ById.ContainsKey(kind))
            {
                throw new GameException("unknown_animal", "There is no such animal.");
            }

            var biome = await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Work);
            if (!Husbandry.Pasture(biome))
            {
                throw new GameException("no_pasture", "No animal lives on a desert or a glacier.");
            }

            if ((tileX, tileY) == PlotLayout.Spawn || !await plots.FreeAsync(player, x, y, tileX, tileY, cancellationToken))
            {
                throw new GameException("blocked", "Something stands here.");
            }

            await inventory.RemoveAsync(player, kind, 1, cancellationToken);
            await stats.RecordAsync(player, [ProductionEntry.Used(kind, 1, time.GetUtcNow())], cancellationToken);
            await using (var insert = await db.CommandAsync(
                "INSERT INTO world.plot_animals (x, y, tile_x, tile_y, kind) VALUES (@x, @y, @tx, @ty, @kind) ON CONFLICT DO NOTHING", cancellationToken))
            {
                Bind(insert, x, y, tileX, tileY);
                insert.Parameters.AddWithValue("kind", kind);
                if (await insert.ExecuteNonQueryAsync(cancellationToken) == 0)
                {
                    throw new GameException("blocked", "An animal already stands here.");
                }
            }

            var xp = await progress.AddXpAsync(player, Husbandry.XpPerRelease, cancellationToken);
            return new AnimalChange(new PlotAnimal(tileX, tileY, kind, null), [], xp);
        }, cancellationToken);

    /// <summary>Feeds a hungry animal crops from the inventory; it then gives its product after its time.</summary>
    public Task<AnimalChange> FeedAsync(Guid player, int x, int y, int tileX, int tileY, string feed, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (!Husbandry.Feed.Contains(feed))
            {
                throw new GameException("bad_feed", "Animals eat wheat, corn, carrots and cabbage.");
            }

            var biome = await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Work);
            var (kind, readyAt) = await LockAsync(x, y, tileX, tileY, cancellationToken);
            if (readyAt is not null)
            {
                throw new GameException("already_fed", readyAt <= time.GetUtcNow() ? "Collect what it gives first." : "It has eaten already.");
            }

            var animal = Husbandry.ById[kind];
            var ready = time.GetUtcNow() + (Husbandry.Time(animal, biome) ?? animal.Time);
            await inventory.RemoveAsync(player, feed, Husbandry.FeedPerMeal, cancellationToken);
            await stats.RecordAsync(player, [ProductionEntry.Used(feed, Husbandry.FeedPerMeal, time.GetUtcNow())], cancellationToken);
            await using (var update = await db.CommandAsync(
                "UPDATE world.plot_animals SET ready_at = @ready WHERE x = @x AND y = @y AND tile_x = @tx AND tile_y = @ty", cancellationToken))
            {
                Bind(update, x, y, tileX, tileY);
                update.Parameters.AddWithValue("ready", ready);
                await update.ExecuteNonQueryAsync(cancellationToken);
            }

            return new AnimalChange(new PlotAnimal(tileX, tileY, kind, ready), [], null);
        }, cancellationToken);

    /// <summary>Takes what a fed animal gives, with the tool it needs in hand; the animal is hungry again.</summary>
    public Task<AnimalChange> CollectAsync(Guid player, int x, int y, int tileX, int tileY, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Work);
            var (kind, readyAt) = await LockAsync(x, y, tileX, tileY, cancellationToken);
            if (readyAt is null)
            {
                throw new GameException("hungry", "Feed it first.");
            }

            if (readyAt > time.GetUtcNow())
            {
                throw new GameException("not_ready", "It has nothing to give yet.");
            }

            var animal = Husbandry.ById[kind];
            if (animal.Tool is { } tool)
            {
                await plots.RequireToolAsync(player, tool, cancellationToken);
            }

            await using (var clear = await db.CommandAsync(
                "UPDATE world.plot_animals SET ready_at = NULL WHERE x = @x AND y = @y AND tile_x = @tx AND tile_y = @ty", cancellationToken))
            {
                Bind(clear, x, y, tileX, tileY);
                await clear.ExecuteNonQueryAsync(cancellationToken);
            }

            await inventory.ReceiveAsync(player, animal.Product, animal.Yield, cancellationToken);
            await stats.RecordAsync(player, [ProductionEntry.Made(animal.Product, animal.Yield, time.GetUtcNow())], cancellationToken);
            var xp = await progress.AddXpAsync(player, animal.Xp, cancellationToken);
            return new AnimalChange(new PlotAnimal(tileX, tileY, kind, null), [(animal.Product, animal.Yield)], xp);
        }, cancellationToken);

    /// <summary>Takes an animal back into the inventory; what it was going to give is lost.</summary>
    public Task<AnimalChange> TakeAsync(Guid player, int x, int y, int tileX, int tileY, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Build);
            var (kind, _) = await LockAsync(x, y, tileX, tileY, cancellationToken);
            await using (var delete = await db.CommandAsync(
                "DELETE FROM world.plot_animals WHERE x = @x AND y = @y AND tile_x = @tx AND tile_y = @ty", cancellationToken))
            {
                Bind(delete, x, y, tileX, tileY);
                await delete.ExecuteNonQueryAsync(cancellationToken);
            }

            await inventory.AddAsync(player, kind, 1, cancellationToken);
            return new AnimalChange(null, [(kind, 1)], null);
        }, cancellationToken);

    /// <summary>The animal on a tile, locked for the transaction; fails with <c>no_animal</c> when there is none.</summary>
    private async Task<(string Kind, DateTimeOffset? ReadyAt)> LockAsync(int x, int y, int tileX, int tileY, CancellationToken cancellationToken)
    {
        await using var select = await db.CommandAsync(
            "SELECT kind, ready_at FROM world.plot_animals WHERE x = @x AND y = @y AND tile_x = @tx AND tile_y = @ty FOR UPDATE", cancellationToken);
        Bind(select, x, y, tileX, tileY);
        await using var reader = await select.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new GameException("no_animal", "No animal stands here.");
        }

        return (reader.GetString(0), reader.IsDBNull(1) ? null : reader.GetFieldValue<DateTimeOffset>(1));
    }

    private static void Bind(Npgsql.NpgsqlCommand command, int x, int y, int tileX, int tileY)
    {
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        command.Parameters.AddWithValue("tx", tileX);
        command.Parameters.AddWithValue("ty", tileY);
    }
}

/// <param name="Item">The animal to let out (plot.release) or the crop to feed (plot.feed); unused otherwise.</param>
public sealed record AnimalRequest(int X, int Y, int TileX, int TileY, string? Item);

/// <summary>plot.release, plot.feed, plot.collect and plot.takeAnimal all answer with the changed animal.</summary>
public abstract class AnimalHandler(IServiceScopeFactory scopes, TimeProvider time) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<AnimalRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var change = await RunAsync(scope.ServiceProvider.GetRequiredService<HusbandryService>(), client.RequireAccount(), request, cancellationToken);
        return new Reply("plot.animal", new
        {
            tileX = request.TileX,
            tileY = request.TileY,
            animal = change.Animal is { } animal ? AnimalJson(animal) : null,
            items = change.Items.Select(i => new { id = i.Item, name = Items.Names[i.Item], quantity = i.Quantity }),
            xp = change.Xp is { } xp ? new { xp = xp.Xp, level = xp.Level, leveledUp = xp.LeveledUp } : null,
            serverTime = time.GetUtcNow().ToUnixTimeMilliseconds(),
        });
    }

    protected abstract Task<AnimalChange> RunAsync(HusbandryService husbandry, Guid player, AnimalRequest request, CancellationToken cancellationToken);

    public static object AnimalJson(PlotAnimal animal) => new
    {
        tileX = animal.TileX,
        tileY = animal.TileY,
        kind = animal.Kind,
        name = Items.Names[animal.Kind],
        readyAt = animal.ReadyAt?.ToUnixTimeMilliseconds(),
    };

    /// <summary>The animals a plot's biome can keep and how long each takes there, for the plot's window.</summary>
    public static IEnumerable<object> KindsJson(Biome biome) => Husbandry.Animals.Select(a => new
    {
        id = a.Item,
        name = Items.Names[a.Item],
        product = a.Product,
        productName = Items.Names[a.Product],
        yield = a.Yield,
        seconds = Husbandry.Time(a, biome)?.TotalSeconds,
        tool = a.Tool,
        toolName = a.Tool is { } tool ? Items.Names[tool] : null,
        xp = a.Xp,
    });
}

public sealed class ReleaseAnimalHandler(IServiceScopeFactory scopes, TimeProvider time) : AnimalHandler(scopes, time)
{
    public override string Type => "plot.release";

    protected override Task<AnimalChange> RunAsync(HusbandryService husbandry, Guid player, AnimalRequest r, CancellationToken cancellationToken) =>
        husbandry.ReleaseAsync(player, r.X, r.Y, r.TileX, r.TileY, r.Item ?? "", cancellationToken);
}

public sealed class FeedAnimalHandler(IServiceScopeFactory scopes, TimeProvider time) : AnimalHandler(scopes, time)
{
    public override string Type => "plot.feed";

    protected override Task<AnimalChange> RunAsync(HusbandryService husbandry, Guid player, AnimalRequest r, CancellationToken cancellationToken) =>
        husbandry.FeedAsync(player, r.X, r.Y, r.TileX, r.TileY, r.Item ?? "", cancellationToken);
}

public sealed class CollectAnimalHandler(IServiceScopeFactory scopes, TimeProvider time) : AnimalHandler(scopes, time)
{
    public override string Type => "plot.collect";

    protected override Task<AnimalChange> RunAsync(HusbandryService husbandry, Guid player, AnimalRequest r, CancellationToken cancellationToken) =>
        husbandry.CollectAsync(player, r.X, r.Y, r.TileX, r.TileY, cancellationToken);
}

public sealed class TakeAnimalHandler(IServiceScopeFactory scopes, TimeProvider time) : AnimalHandler(scopes, time)
{
    public override string Type => "plot.takeAnimal";

    protected override Task<AnimalChange> RunAsync(HusbandryService husbandry, Guid player, AnimalRequest r, CancellationToken cancellationToken) =>
        husbandry.TakeAsync(player, r.X, r.Y, r.TileX, r.TileY, cancellationToken);
}
