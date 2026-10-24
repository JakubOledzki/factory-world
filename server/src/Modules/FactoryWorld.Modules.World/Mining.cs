using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.World;

/// <summary>What a mine of one level gives, and what it takes to build it up to that level.</summary>
/// <param name="Units">How many times it can be worked before it runs dry.</param>
/// <param name="Refill">How long it takes to fill up again when dry, counted from its last load.</param>
/// <param name="Time">How long one load takes with the pickaxe.</param>
/// <param name="Cost">Items the owner spends to build the mine up to this level from the one below.</param>
public sealed record MineLevel(int Level, int Units, TimeSpan Refill, TimeSpan Time, IReadOnlyList<(string Item, int Quantity)> Cost, int Xp);

/// <summary>
/// Every mountain plot has 1-5 mines. A player with a pickaxe in hand works a mine for 5 s and
/// gets up to two ores. A mine gives 50 loads in a row; 10 minutes after the last one it is full again.
/// The owner can build a mine up twice, with ingots and timber: it then gives more loads, quicker,
/// and fills up again sooner.
/// </summary>
public static class Mining
{
    public static readonly IReadOnlyList<MineLevel> Levels =
    [
        new(1, 50, TimeSpan.FromMinutes(10), TimeSpan.FromSeconds(5), [], 0),
        new(2, 100, TimeSpan.FromMinutes(5), TimeSpan.FromSeconds(4), [(Items.IronIngot, 30), (Items.Wood, 40)], 30),
        new(3, 200, TimeSpan.FromSeconds(150), TimeSpan.FromSeconds(3), [(Items.IronIngot, 80), (Items.CopperIngot, 30), (Items.TinIngot, 10)], 80),
    ];

    /// <summary>A mine's level by number; out of range counts as the nearest one.</summary>
    public static MineLevel Level(int level) => Levels[Math.Clamp(level, 1, Levels.Count) - 1];

    /// <summary>How long a load takes in a mine nobody has built up.</summary>
    public static TimeSpan Time => Levels[0].Time;

    /// <summary>How many times a mine nobody has built up can be worked before it runs dry.</summary>
    public static int Units => Levels[0].Units;

    /// <summary>How long a dry mine nobody has built up takes to fill up again, counted from its last load.</summary>
    public static TimeSpan Refill => Levels[0].Refill;

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
public sealed record MineState(MineSite Site, int Units, DateTimeOffset? RefillAt, MineLevel Level);

public sealed record MineLoad(MineState Mine, IReadOnlyList<(string Item, int Quantity)> Items, XpGain Xp);

public sealed record MineUpgrade(MineState Mine, XpGain Xp);

public sealed class MineService(GameDb db, PlotService plots, IInventory inventory, ICharacterProgress progress, TimeProvider time)
{
    /// <summary>The mines of a plot and how many loads each has left.</summary>
    public async Task<IReadOnlyList<MineState>> MinesAsync(int x, int y, Biome biome, CancellationToken cancellationToken)
    {
        var used = new Dictionary<int, (int Used, DateTimeOffset? EmptyAt, int Level)>();
        await using (var command = await db.CommandAsync(
            "SELECT mine, used, empty_at, level FROM world.plot_mines WHERE x = @x AND y = @y", cancellationToken))
        {
            command.Parameters.AddWithValue("x", x);
            command.Parameters.AddWithValue("y", y);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                used[reader.GetInt32(0)] = (reader.GetInt32(1), reader.IsDBNull(2) ? null : reader.GetFieldValue<DateTimeOffset>(2), reader.GetInt32(3));
            }
        }

        return PlotLayout.Mines(x, y, biome)
            .Select(site => used.TryGetValue(site.Id, out var row) ? State(site, row.Used, row.EmptyAt, row.Level) : State(site, 0, null, 1))
            .ToList();
    }

    /// <summary>Works a mine of the player's plot with the pickaxe in hand: one load of ore.</summary>
    public Task<MineLoad> MineAsync(Guid player, int x, int y, int mine, Action<TimeSpan> pace, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var site = await SiteAsync(player, x, y, mine, cancellationToken);
            await plots.RequireToolAsync(player, Items.Pickaxe, cancellationToken);
            var (used, emptyAt, level) = await LockAsync(x, y, mine, cancellationToken);
            var before = State(site, used, emptyAt, level);
            if (before.Units == 0)
            {
                throw new GameException("mine_empty", "The mine is worked out; it fills up again in a while.");
            }

            var units = before.Level.Units;
            pace(before.Level.Time);
            used = units - before.Units + 1;
            emptyAt = used == units ? time.GetUtcNow() : null;
            await WriteAsync(x, y, mine, used, emptyAt, level, cancellationToken);

            var items = Mining.Load();
            foreach (var (item, quantity) in items)
            {
                await inventory.AddAsync(player, item, quantity, cancellationToken);
            }

            var xp = await progress.AddXpAsync(player, Mining.XpPerLoad, cancellationToken);
            return new MineLoad(State(site, used, emptyAt, level), items, xp);
        }, cancellationToken);

    /// <summary>Builds a mine of the player's plot up one level with items from the inventory. What
    /// has been dug out stays dug out, so the mine has the extra loads of the new level left over.</summary>
    public Task<MineUpgrade> UpgradeAsync(Guid player, int x, int y, int mine, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var site = await SiteAsync(player, x, y, mine, cancellationToken);
            var (used, emptyAt, level) = await LockAsync(x, y, mine, cancellationToken);
            if (level >= Mining.Levels.Count)
            {
                throw new GameException("mine_max_level", "This mine is built up as far as it goes.");
            }

            var next = Mining.Level(level + 1);
            foreach (var (item, quantity) in next.Cost)
            {
                if (await inventory.CountAsync(player, item, cancellationToken) < quantity)
                {
                    throw new GameException("not_enough_items", $"Building the mine up takes {quantity} × {Items.Names[item]}.");
                }
            }

            foreach (var (item, quantity) in next.Cost)
            {
                await inventory.RemoveAsync(player, item, quantity, cancellationToken);
            }

            // A mine that has rested long enough counts as full from now on.
            var state = State(site, used, emptyAt, level);
            (used, emptyAt) = state.Units > 0 ? (state.Level.Units - state.Units, (DateTimeOffset?)null) : (used, emptyAt);
            await WriteAsync(x, y, mine, used, emptyAt, next.Level, cancellationToken);
            var xp = await progress.AddXpAsync(player, next.Xp, cancellationToken);
            return new MineUpgrade(State(site, used, emptyAt, next.Level), xp);
        }, cancellationToken);

    private async Task<MineSite> SiteAsync(Guid player, int x, int y, int mine, CancellationToken cancellationToken)
    {
        var biome = await plots.RequireOwnerAsync(player, x, y, cancellationToken);
        return PlotLayout.Mines(x, y, biome).FirstOrDefault(m => m.Id == mine)
            ?? throw new GameException("no_mine", "There is no such mine on this plot.");
    }

    /// <summary>The mine's row, made when it is first touched and locked until the transaction ends.</summary>
    private async Task<(int Used, DateTimeOffset? EmptyAt, int Level)> LockAsync(int x, int y, int mine, CancellationToken cancellationToken)
    {
        await using (var insert = await db.CommandAsync(
            "INSERT INTO world.plot_mines (x, y, mine, used) VALUES (@x, @y, @mine, 0) ON CONFLICT DO NOTHING", cancellationToken))
        {
            insert.Parameters.AddWithValue("x", x);
            insert.Parameters.AddWithValue("y", y);
            insert.Parameters.AddWithValue("mine", mine);
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }

        await using var select = await db.CommandAsync(
            "SELECT used, empty_at, level FROM world.plot_mines WHERE x = @x AND y = @y AND mine = @mine FOR UPDATE", cancellationToken);
        select.Parameters.AddWithValue("x", x);
        select.Parameters.AddWithValue("y", y);
        select.Parameters.AddWithValue("mine", mine);
        await using var reader = await select.ExecuteReaderAsync(cancellationToken);
        await reader.ReadAsync(cancellationToken);
        return (reader.GetInt32(0), reader.IsDBNull(1) ? null : reader.GetFieldValue<DateTimeOffset>(1), reader.GetInt32(2));
    }

    private async Task WriteAsync(int x, int y, int mine, int used, DateTimeOffset? emptyAt, int level, CancellationToken cancellationToken)
    {
        await using var update = await db.CommandAsync(
            "UPDATE world.plot_mines SET used = @used, empty_at = @empty, level = @level WHERE x = @x AND y = @y AND mine = @mine", cancellationToken);
        update.Parameters.AddWithValue("x", x);
        update.Parameters.AddWithValue("y", y);
        update.Parameters.AddWithValue("mine", mine);
        update.Parameters.AddWithValue("used", used);
        update.Parameters.AddWithValue("empty", (object?)emptyAt ?? DBNull.Value);
        update.Parameters.AddWithValue("level", level);
        await update.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>A mine with <paramref name="used"/> loads taken; a dry one is full again once it has rested.</summary>
    private MineState State(MineSite site, int used, DateTimeOffset? emptyAt, int level)
    {
        var l = Mining.Level(level);
        if (emptyAt is { } at)
        {
            return at + l.Refill <= time.GetUtcNow() ? new MineState(site, l.Units, null, l) : new MineState(site, 0, at + l.Refill, l);
        }

        return new MineState(site, Math.Max(l.Units - used, 0), null, l);
    }
}

public sealed record MineRequest(int X, int Y, int Mine);

/// <summary>Builds a mine up one level: "plot.mineUpgraded" with the mine and the experience gained.</summary>
public sealed class UpgradeMineHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "plot.upgradeMine";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<MineRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var upgrade = await scope.ServiceProvider.GetRequiredService<MineService>().UpgradeAsync(
            client.RequireAccount(), request.X, request.Y, request.Mine, cancellationToken);
        return new Reply("plot.mineUpgraded", new
        {
            mine = MineHandler.MineJson(upgrade.Mine),
            xp = new { xp = upgrade.Xp.Xp, level = upgrade.Xp.Level, leveledUp = upgrade.Xp.LeveledUp },
        });
    }
}

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
        level = mine.Level.Level,
        // What this level gives: loads when full, seconds a load takes and seconds to fill up again.
        capacity = mine.Level.Units,
        seconds = mine.Level.Time.TotalSeconds,
        refillSeconds = mine.Level.Refill.TotalSeconds,
        // The next level and what it takes, or null when the mine is built up all the way.
        upgrade = mine.Level.Level < Mining.Levels.Count && Mining.Level(mine.Level.Level + 1) is var next
            ? new
            {
                level = next.Level,
                capacity = next.Units,
                seconds = next.Time.TotalSeconds,
                refillSeconds = next.Refill.TotalSeconds,
                cost = next.Cost.Select(c => new { id = c.Item, name = Items.Names[c.Item], quantity = c.Quantity }),
            }
            : null,
    };
}
