using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.World;

/// <summary>
/// Every mountain plot has 1-5 mines. A player with a pickaxe in hand works a mine for 5 s and
/// gets up to two ores. A mine gives 50 loads in a row; 10 minutes after the last one it is full again.
/// </summary>
public static class Mining
{
    public static readonly TimeSpan Time = TimeSpan.FromSeconds(5);

    /// <summary>How many times a mine can be worked before it runs dry.</summary>
    public const int Units = 50;

    /// <summary>How long a dry mine takes to fill up again, counted from its last load.</summary>
    public static readonly TimeSpan Refill = TimeSpan.FromMinutes(10);

    /// <summary>A load holds at most this many ores; when more drop, the rarest are kept.</summary>
    public const int MaxOres = 2;

    public const int XpPerLoad = 2;

    /// <summary>Each ore drops on its own roll, with this chance in thousandths; rarest first.</summary>
    public static readonly IReadOnlyList<(string Item, int PerMille)> Drops =
    [
        (Items.GoldOre, 1),
        (Items.SilverOre, 50),
        (Items.TinOre, 100),
        (Items.CopperOre, 200),
        (Items.IronOre, 200),
        (Items.Coal, 350),
        (Items.Stone, 990),
    ];

    /// <summary>Plots of these biomes have mines.</summary>
    public static bool HasMines(Biome biome) => biome == Biome.Mountains;

    /// <summary>What one load gives, for one roll (0-999) per entry of <see cref="Drops"/>.</summary>
    public static IReadOnlyList<(string Item, int Quantity)> Load(IReadOnlyList<int> rolls) =>
        Drops.Where((drop, i) => rolls[i] < drop.PerMille).Take(MaxOres).Select(drop => (drop.Item, 1)).ToList();

    public static IReadOnlyList<(string Item, int Quantity)> Load() =>
        Load(Drops.Select(_ => Random.Shared.Next(1000)).ToList());
}

/// <summary>A mine's place on its plot: it covers <see cref="Width"/> × <see cref="Height"/> tiles from (X, Y).</summary>
public sealed record MineSite(int Id, int X, int Y)
{
    public const int Width = 4;

    public const int Height = 3;
}

/// <param name="Units">Loads left until it runs dry.</param>
/// <param name="RefillAt">When a dry mine is full again; null while it is not dry.</param>
public sealed record MineState(MineSite Site, int Units, DateTimeOffset? RefillAt);

public sealed record MineLoad(MineState Mine, IReadOnlyList<(string Item, int Quantity)> Items, XpGain Xp);

public sealed class MineService(GameDb db, PlotService plots, IInventory inventory, ICharacterProgress progress, TimeProvider time)
{
    /// <summary>The mines of a plot and how many loads each has left.</summary>
    public async Task<IReadOnlyList<MineState>> MinesAsync(int x, int y, Biome biome, CancellationToken cancellationToken)
    {
        var used = new Dictionary<int, (int Used, DateTimeOffset? EmptyAt)>();
        await using (var command = await db.CommandAsync(
            "SELECT mine, used, empty_at FROM world.plot_mines WHERE x = @x AND y = @y", cancellationToken))
        {
            command.Parameters.AddWithValue("x", x);
            command.Parameters.AddWithValue("y", y);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                used[reader.GetInt32(0)] = (reader.GetInt32(1), reader.IsDBNull(2) ? null : reader.GetFieldValue<DateTimeOffset>(2));
            }
        }

        return PlotLayout.Mines(x, y, biome)
            .Select(site => used.TryGetValue(site.Id, out var row) ? State(site, row.Used, row.EmptyAt) : State(site, 0, null))
            .ToList();
    }

    /// <summary>Works a mine of the player's plot with the pickaxe in hand: one load of ore.</summary>
    public Task<MineLoad> MineAsync(Guid player, int x, int y, int mine, Action<TimeSpan> pace, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var biome = await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            var site = PlotLayout.Mines(x, y, biome).FirstOrDefault(m => m.Id == mine)
                ?? throw new GameException("no_mine", "There is no such mine on this plot.");
            await plots.RequireToolAsync(player, Items.Pickaxe, cancellationToken);

            await using (var insert = await db.CommandAsync(
                "INSERT INTO world.plot_mines (x, y, mine, used) VALUES (@x, @y, @mine, 0) ON CONFLICT DO NOTHING", cancellationToken))
            {
                insert.Parameters.AddWithValue("x", x);
                insert.Parameters.AddWithValue("y", y);
                insert.Parameters.AddWithValue("mine", mine);
                await insert.ExecuteNonQueryAsync(cancellationToken);
            }

            int used;
            DateTimeOffset? emptyAt;
            await using (var select = await db.CommandAsync(
                "SELECT used, empty_at FROM world.plot_mines WHERE x = @x AND y = @y AND mine = @mine FOR UPDATE", cancellationToken))
            {
                select.Parameters.AddWithValue("x", x);
                select.Parameters.AddWithValue("y", y);
                select.Parameters.AddWithValue("mine", mine);
                await using var reader = await select.ExecuteReaderAsync(cancellationToken);
                await reader.ReadAsync(cancellationToken);
                used = reader.GetInt32(0);
                emptyAt = reader.IsDBNull(1) ? null : reader.GetFieldValue<DateTimeOffset>(1);
            }

            var before = State(site, used, emptyAt);
            if (before.Units == 0)
            {
                throw new GameException("mine_empty", "The mine is worked out; it fills up again in a while.");
            }

            pace(Mining.Time);
            used = Mining.Units - before.Units + 1;
            emptyAt = used == Mining.Units ? time.GetUtcNow() : null;
            await using (var update = await db.CommandAsync(
                "UPDATE world.plot_mines SET used = @used, empty_at = @empty WHERE x = @x AND y = @y AND mine = @mine", cancellationToken))
            {
                update.Parameters.AddWithValue("x", x);
                update.Parameters.AddWithValue("y", y);
                update.Parameters.AddWithValue("mine", mine);
                update.Parameters.AddWithValue("used", used);
                update.Parameters.AddWithValue("empty", (object?)emptyAt ?? DBNull.Value);
                await update.ExecuteNonQueryAsync(cancellationToken);
            }

            var items = Mining.Load();
            foreach (var (item, quantity) in items)
            {
                await inventory.AddAsync(player, item, quantity, cancellationToken);
            }

            var xp = await progress.AddXpAsync(player, Mining.XpPerLoad, cancellationToken);
            return new MineLoad(State(site, used, emptyAt), items, xp);
        }, cancellationToken);

    /// <summary>A mine with <paramref name="used"/> loads taken; a dry one is full again once it has rested.</summary>
    private MineState State(MineSite site, int used, DateTimeOffset? emptyAt)
    {
        if (emptyAt is { } at)
        {
            return at + Mining.Refill <= time.GetUtcNow() ? new MineState(site, Mining.Units, null) : new MineState(site, 0, at + Mining.Refill);
        }

        return new MineState(site, Math.Max(Mining.Units - used, 0), null);
    }
}

public sealed record MineRequest(int X, int Y, int Mine);

public sealed class MineHandler(IServiceScopeFactory scopes, TimeProvider time) : IMessageHandler
{
    public string Type => "plot.mine";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<MineRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var load = await scope.ServiceProvider.GetRequiredService<MineService>().MineAsync(
            client.RequireAccount(), request.X, request.Y, request.Mine, work => HarvestHandler.CheckPace(client, time, work), cancellationToken);
        HarvestHandler.Swung(client, time);
        return new Reply("plot.mined", new
        {
            mine = MineJson(load.Mine),
            items = load.Items.Select(i => new { id = i.Item, name = Items.Names[i.Item], quantity = i.Quantity }),
            xp = new { xp = load.Xp.Xp, level = load.Xp.Level, leveledUp = load.Xp.LeveledUp },
            serverTime = time.GetUtcNow().ToUnixTimeMilliseconds(),
        });
    }

    public static object MineJson(MineState mine) => new
    {
        id = mine.Site.Id,
        x = mine.Site.X,
        y = mine.Site.Y,
        width = MineSite.Width,
        height = MineSite.Height,
        units = mine.Units,
        refillAt = mine.RefillAt?.ToUnixTimeMilliseconds(),
    };
}
