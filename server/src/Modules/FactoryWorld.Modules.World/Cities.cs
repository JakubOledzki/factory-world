using System.IO.Compression;
using System.Text;
using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.World;

/// <summary>A town of the map, which the city plots around it belong to; its centre is the plot (<paramref name="X"/>, <paramref name="Y"/>).</summary>
public sealed record Town(int X, int Y, long Population, string Name);

/// <summary>The towns the city plots belong to, made by tools/build_cities.py from the map's towns.</summary>
public sealed class Towns
{
    private readonly Dictionary<(int, int), Town> _ofPlot;

    public Towns(IReadOnlyList<Town> all, IReadOnlyDictionary<(int X, int Y), int> plots)
    {
        All = all;
        _ofPlot = plots.ToDictionary(p => p.Key, p => all[p.Value]);
    }

    public IReadOnlyList<Town> All { get; }

    /// <summary>The town a city plot belongs to; a city plot no town is near is a town of its own.</summary>
    public Town Of(int x, int y) => _ofPlot.TryGetValue((x, y), out var town) ? town : new Town(x, y, CityRules.LoneTownPopulation, "Miasto");

    /// <summary>Reads the file: the number of towns, the towns ("column, row, population, name"), then "column, row, town" for each city plot.</summary>
    public static Towns Read(Stream gzipped)
    {
        using var reader = new StreamReader(new GZipStream(gzipped, CompressionMode.Decompress), Encoding.UTF8);
        var count = int.Parse(reader.ReadLine()!);
        var towns = new List<Town>(count);
        for (var i = 0; i < count; i++)
        {
            var parts = reader.ReadLine()!.Split('\t');
            towns.Add(new Town(int.Parse(parts[0]), int.Parse(parts[1]), long.Parse(parts[2]), parts[3]));
        }

        var plots = new Dictionary<(int, int), int>();
        while (reader.ReadLine() is { Length: > 0 } line)
        {
            var parts = line.Split('\t');
            plots[(int.Parse(parts[0]), int.Parse(parts[1]))] = int.Parse(parts[2]);
        }

        return new Towns(towns, plots);
    }

    public static Towns Load()
    {
        using var resource = typeof(Towns).Assembly.GetManifestResourceStream("cities.tsv.gz")
            ?? throw new InvalidOperationException("The towns resource is missing.");
        return Read(resource);
    }
}

/// <summary>
/// Cities. A city plot belongs to a town of the map (<see cref="Towns"/>), and only the ground by its station can be built on
/// (<see cref="InBuildArea"/>), so it builds up: high-bay stores and multi-storey factories. Every day a town wants a few goods
/// (<see cref="Needs"/>) and pays better than the trader for them; what the players deliver makes it grow from a village to a
/// metropolis (<see cref="LevelCents"/>), and a bigger town wants more and dearer goods. Players keep shops that sell to the
/// townspeople, take the town's rubbish away for a fee, sell the services of their offices to other players, and the players
/// who own plots in the town elect a mayor every week, who sets a tax on shops and services and one bonus for the town.
/// </summary>
public static class CityRules
{
    /// <summary>The ground of a city plot that can be built on: this many tiles either side of the station's middle, and the first rows.</summary>
    public const int BuildHalfWidth = 30;

    public const int BuildRows = 60;

    public static bool InBuildArea(int tileX, int tileY) => Math.Abs(tileX - PlotLayout.Spawn.X) <= BuildHalfWidth && tileY < BuildRows;

    /// <summary>The people of a city plot no town of the map is near.</summary>
    public const long LoneTownPopulation = 20_000;

    public static readonly IReadOnlyList<string> LevelNames = ["Wieś", "Miasteczko", "Miasto", "Duże miasto", "Metropolia"];

    /// <summary>The value of goods delivered (in cents) that makes a town grow to each level.</summary>
    public static readonly IReadOnlyList<long> LevelCents = [0, 20_000_00, 100_000_00, 500_000_00, 2_500_000_00];

    public static int Level(long deliveredCents)
    {
        var level = 0;
        while (level + 1 < LevelCents.Count && deliveredCents >= LevelCents[level + 1])
        {
            level++;
        }

        return level;
    }

    /// <summary>How much a town's size counts: 1 for 10 000 people, more for a bigger town (up to 3), less for a village (down to a half).</summary>
    public static double PopulationFactor(long population) => Math.Clamp(Math.Log10(Math.Max(population, 1) / 10_000.0) + 1, 0.5, 3);

    public static readonly TimeSpan Day = TimeSpan.FromDays(1);

    public static int DayOf(DateTimeOffset at) => (int)Math.Floor((at - SeaWeather.Epoch) / Day);

    public static DateTimeOffset DayStart(int day) => SeaWeather.Epoch + Day * day;

    /// <summary>Weeks of the town halls: a mayor elected in one week rules the next.</summary>
    public static int WeekOf(DateTimeOffset at) => (int)Math.Floor(DayOf(at) / 7.0);

    public static DateTimeOffset WeekStart(int week) => DayStart(week * 7);

    /// <summary>The goods towns want, from which level on, and how many a town of 10 000 people wants a day.</summary>
    public static readonly IReadOnlyList<(string Item, int Level, int Quantity)> Goods =
    [
        (Items.Bread, 0, 40), (Items.Sauerkraut, 0, 20), (Items.VegetableSoup, 0, 20), (Items.ScrambledEggs, 0, 20), (Items.Fries, 0, 20),
        (Items.SmokedFish, 0, 15), (Items.CannedFish, 0, 15), (Items.Planks, 0, 60), (Items.Bricks, 0, 80), (Items.Coal, 0, 60),
        (Items.Milk, 0, 30), (Items.Egg, 0, 30), (Items.Wool, 0, 20), (Items.GlassBottles, 0, 30), (Items.WoodPellets, 0, 40),
        (Items.CarrotCake, 1, 15), (Items.Bigos, 1, 15), (Items.FishSoup, 1, 15), (Items.FriedCarp, 1, 10), (Items.WindowPane, 1, 20),
        (Items.Concrete, 1, 40), (Items.Cement, 1, 30), (Items.IceCream, 1, 20), (Items.FrozenFish, 1, 15), (Items.Plywood, 1, 20),
        (Items.Gasoline, 1, 30), (Items.Diesel, 1, 30), (Items.SaltedHerring, 1, 15), (Items.CornBread, 1, 20),
        (Items.Bicycle, 2, 4), (Items.Radio, 2, 6), (Items.SmokedSalmon, 2, 10), (Items.FrozenSalmon, 2, 8), (Items.Plastic, 2, 30),
        (Items.CircuitBoard, 2, 10), (Items.ElectricMotor, 2, 5), (Items.Tyres, 2, 3),
        (Items.WashingMachine, 3, 3), (Items.OpticalFiber, 3, 10), (Items.Amber, 3, 5), (Items.Mirror, 3, 8),
        (Items.Car, 4, 2),
        // Forestry: paper, furniture, honey and what the forest floor gives.
        (Items.Paper, 0, 40), (Items.Honey, 0, 20), (Items.Charcoal, 0, 30), (Items.MushroomSoup, 0, 15), (Items.BerryPierogi, 0, 15),
        (Items.Cardboard, 1, 30), (Items.Chair, 1, 8), (Items.Table, 1, 5), (Items.Candles, 1, 15), (Items.Gingerbread, 1, 15), (Items.HerbalTea, 1, 20),
        (Items.Wardrobe, 2, 3), (Items.Turpentine, 2, 10),
        (Items.OakDresser, 3, 2),
    ];

    /// <summary>A town pays this many times the trader's price for what it wants, and more at each level.</summary>
    public const double Premium = 1.5;

    public const double PremiumPerLevel = 0.1;

    /// <summary>How much more a town pays with the mayor's "demand" bonus.</summary>
    public const double DemandBonus = 1.15;

    public static int NeedCount(int level) => 3 + level;

    /// <summary>What a town wants on a day: as many goods as its level allows, picked by the day, more of each the bigger and older the town.</summary>
    public static IReadOnlyList<(string Item, long Wanted)> Needs(Town town, int level, int day, Func<string, bool> priced)
    {
        var seed = (ulong)(uint)town.X * 0x9e3779b97f4a7c15UL ^ (ulong)(uint)town.Y * 0xbf58476d1ce4e5b9UL ^ (ulong)(uint)day * 0x94d049bb133111ebUL;
        ulong Hash(string item)
        {
            var h = seed;
            foreach (var c in item)
            {
                h = (h ^ c) * 0x100000001b3UL;
            }

            h ^= h >> 31;
            h *= 0xbf58476d1ce4e5b9UL;
            return h ^ (h >> 29);
        }

        // The newest goods of the town's level come first, so a town that grew asks for what it could not before.
        var open = Goods.Where(g => g.Level <= level && priced(g.Item)).ToList();
        var fresh = open.Where(g => g.Level == level).OrderBy(g => Hash(g.Item)).Take(level > 0 ? 1 : 0);
        var picked = fresh.Concat(open.Except(fresh).OrderBy(g => Hash(g.Item))).Take(NeedCount(level));
        var factor = PopulationFactor(town.Population) * (1 + 0.5 * level);
        return picked.Select(g => (g.Item, Math.Max(1, (long)Math.Round(g.Quantity * factor)))).ToList();
    }

    public static long NeedPriceCents(long traderCents, int level, bool demandBonus) =>
        (long)Math.Round(traderCents * (Premium + PremiumPerLevel * level) * (demandBonus ? DemandBonus : 1));

    /// <summary>What the town pays for each piece of rubbish taken away.</summary>
    public const long TrashFeeCents = 20;

    /// <summary>How much rubbish a town has to give away a day.</summary>
    public static long TrashPerDay(Town town, int level) => (long)Math.Round(300 * PopulationFactor(town.Population) * (1 + level));

    /// <summary>Customers who come into a shop in an hour, for a town of 10 000 people at its centre.</summary>
    public const double CustomersPerHour = 30;

    /// <summary>How many more customers the mayor's "shoppers" bonus brings.</summary>
    public const double ShoppersBonus = 1.3;

    /// <summary>Customers an hour of a shop <paramref name="distance"/> plots from its town's centre.</summary>
    public static double Customers(Town town, int level, double distance, bool shoppers) =>
        CustomersPerHour * PopulationFactor(town.Population) * (1 + 0.25 * level) / (1 + distance / 4) * (shoppers ? ShoppersBonus : 1);

    /// <summary>Chance that a customer buys a piece at <paramref name="priceCents"/>: always at the trader's price,
    /// half the time at twice that, never at three times.</summary>
    public static double Accepts(long priceCents, long traderCents) => Math.Clamp(1.5 - priceCents / (2.0 * traderCents), 0, 1);

    /// <summary>A shop's sales are worked out for at most a day back.</summary>
    public static readonly TimeSpan ShopCatchUp = TimeSpan.FromDays(1);

    /// <summary>Kinds of goods a shop holds, and most of each.</summary>
    public const int ShopKinds = 8;

    public const long ShopMaxStock = 1000;

    /// <summary>What each office sells to the players who come by: what they get and its price. One office sells so many a day.</summary>
    public static readonly IReadOnlyDictionary<string, (string Item, int Quantity, long PriceCents)> Services = new Dictionary<string, (string, int, long)>
    {
        [Items.DesignOffice] = (Items.Blueprint, 1, 30_00),
        [Items.Laboratory] = (Items.ResearchData, 1, 80_00),
        [Items.ServiceWorkshop] = (Items.Gasket, 4, 90_00),
    };

    public const int ServiceSalesPerDay = 20;

    /// <summary>Rail fees from a city plot (−10%), with a freight terminal on it (another −25%), with the mayor's "rail" bonus (another −20%).</summary>
    public const double CityRail = 0.9;

    public const double TerminalRail = 0.75;

    public const double MayorRail = 0.8;

    /// <summary>Routes a station with a freight terminal runs.</summary>
    public const int TerminalRoutes = 10;

    /// <summary>The highest tax a mayor sets on shops and services, in percent.</summary>
    public const int MaxTaxPercent = 10;

    /// <summary>The bonuses a mayor picks one of, for the week.</summary>
    public static readonly IReadOnlyDictionary<string, string> Bonuses = new Dictionary<string, string>
    {
        ["demand"] = "Popyt: miasto płaci za dostawy 15% więcej",
        ["shoppers"] = "Zakupy: o 30% więcej klientów w sklepach",
        ["rail"] = "Kolej: opłaty kolejowe z działek miasta o 20% niższe",
        ["plots"] = "Działki: działki w mieście o 20% tańsze",
    };

    public const double CheapPlots = 0.8;

    /// <summary>Plots between two, around the globe's seam too.</summary>
    public static double Distance(int width, int x, int y, int toX, int toY)
    {
        var dx = Math.Abs(x - toX);
        dx = Math.Min(dx, width - dx);
        return Math.Sqrt(dx * dx + (double)(y - toY) * (y - toY));
    }
}

/// <summary>How much a town has got delivered in all, for its level.</summary>
public sealed class TownProgressRow
{
    public int TownX { get; set; }

    public int TownY { get; set; }

    public long DeliveredCents { get; set; }
}

/// <summary>How much one player delivered to a town in all.</summary>
public sealed class TownContributionRow
{
    public int TownX { get; set; }

    public int TownY { get; set; }

    public Guid PlayerId { get; set; }

    public long DeliveredCents { get; set; }
}

/// <summary>How many pieces of an item a town got on a day; "trash" counts the rubbish taken away.</summary>
public sealed class TownDeliveryRow
{
    public int TownX { get; set; }

    public int TownY { get; set; }

    public int Day { get; set; }

    public required string Item { get; set; }

    public long Quantity { get; set; }
}

/// <summary>A shop's sales: until when they are worked out, the part of a customer carried over, and what it sold in all.</summary>
public sealed class ShopRow
{
    public Guid Id { get; set; }

    public DateTimeOffset SettledAt { get; set; }

    public double Carry { get; set; }

    public long SoldCents { get; set; }

    public long SoldItems { get; set; }
}

public sealed class ShopItemRow
{
    public Guid ShopId { get; set; }

    public required string Item { get; set; }

    public long Quantity { get; set; }

    public long PriceCents { get; set; }
}

/// <summary>Services an office sold on a day.</summary>
public sealed class ServiceSaleRow
{
    public Guid Id { get; set; }

    public int Day { get; set; }

    public int Count { get; set; }
}

public sealed class TownVoteRow
{
    public int TownX { get; set; }

    public int TownY { get; set; }

    public int Week { get; set; }

    public Guid VoterId { get; set; }

    public Guid CandidateId { get; set; }
}

/// <summary>A town's mayor for a week (elected the week before; null when nobody voted) and what they set.</summary>
public sealed class TownPolicyRow
{
    public int TownX { get; set; }

    public int TownY { get; set; }

    public int Week { get; set; }

    public Guid? MayorId { get; set; }

    public int TaxPercent { get; set; }

    public string? Bonus { get; set; }
}

public sealed record TownPolicy(Guid? Mayor, int TaxPercent, string? Bonus);

public sealed class CityService(
    GameDb db, WorldMap map, Towns towns, PlotService plots, IInventory inventory, IWallet wallet, ICharacterProgress progress,
    ICharacterNames names, IMarketPrices prices, BeachService beach, TimeProvider time) : IMachineContents
{
    /// <summary>The town of a city plot; fails for any other plot.</summary>
    public Town RequireTown(int x, int y)
    {
        if (!map.Contains(x, y) || map.BiomeAt(x, y) != Biome.City)
        {
            throw new GameException("not_city", "This plot is not in a city.");
        }

        return towns.Of(x, y);
    }

    public Town? TownOf(int x, int y) => map.Contains(x, y) && map.BiomeAt(x, y) == Biome.City ? towns.Of(x, y) : null;

    public async Task<long> DeliveredAsync(Town town, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT delivered_cents FROM world.town_progress WHERE town_x = @x AND town_y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", town.X);
        command.Parameters.AddWithValue("y", town.Y);
        return await command.ExecuteScalarAsync(cancellationToken) is long cents ? cents : 0;
    }

    /// <summary>The mayor and their policy this week: the winner of last week's vote, worked out once and kept.</summary>
    public async Task<TownPolicy> PolicyAsync(Town town, CancellationToken cancellationToken)
    {
        var week = CityRules.WeekOf(time.GetUtcNow());
        if (await ReadPolicyAsync(town, week, cancellationToken) is { } policy)
        {
            return policy;
        }

        Guid? mayor = null;
        await using (var count = await db.CommandAsync(
            """
            SELECT candidate_id FROM world.town_votes WHERE town_x = @x AND town_y = @y AND week = @week
            GROUP BY candidate_id ORDER BY count(*) DESC, candidate_id LIMIT 1
            """, cancellationToken))
        {
            count.Parameters.AddWithValue("x", town.X);
            count.Parameters.AddWithValue("y", town.Y);
            count.Parameters.AddWithValue("week", week - 1);
            mayor = await count.ExecuteScalarAsync(cancellationToken) as Guid?;
        }

        await using (var insert = await db.CommandAsync(
            """
            INSERT INTO world.town_policies (town_x, town_y, week, mayor_id, tax_percent, bonus) VALUES (@x, @y, @week, @mayor, 0, NULL)
            ON CONFLICT DO NOTHING
            """, cancellationToken))
        {
            insert.Parameters.AddWithValue("x", town.X);
            insert.Parameters.AddWithValue("y", town.Y);
            insert.Parameters.AddWithValue("week", week);
            insert.Parameters.AddWithValue("mayor", (object?)mayor ?? DBNull.Value);
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }

        return (await ReadPolicyAsync(town, week, cancellationToken))!;
    }

    private async Task<TownPolicy?> ReadPolicyAsync(Town town, int week, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT mayor_id, tax_percent, bonus FROM world.town_policies WHERE town_x = @x AND town_y = @y AND week = @week", cancellationToken);
        command.Parameters.AddWithValue("x", town.X);
        command.Parameters.AddWithValue("y", town.Y);
        command.Parameters.AddWithValue("week", week);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)
            ? new TownPolicy(reader.IsDBNull(0) ? null : reader.GetGuid(0), reader.GetInt32(1), reader.IsDBNull(2) ? null : reader.GetString(2))
            : null;
    }

    /// <summary>What the town wants today, how much of it came already and what it pays a piece.</summary>
    public async Task<IReadOnlyList<(string Item, long Wanted, long Delivered, long PriceCents)>> NeedsAsync(
        Town town, int level, TownPolicy policy, CancellationToken cancellationToken)
    {
        var day = CityRules.DayOf(time.GetUtcNow());
        var delivered = await DayDeliveriesAsync(town, day, cancellationToken);
        return CityRules.Needs(town, level, day, item => prices.BuysCents(item) is not null)
            .Select(n => (n.Item, n.Wanted, delivered.GetValueOrDefault(n.Item),
                CityRules.NeedPriceCents(prices.BuysCents(n.Item)!.Value, level, policy.Bonus == "demand")))
            .ToList();
    }

    private async Task<Dictionary<string, long>> DayDeliveriesAsync(Town town, int day, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT item, quantity FROM world.town_deliveries WHERE town_x = @x AND town_y = @y AND day = @day", cancellationToken);
        command.Parameters.AddWithValue("x", town.X);
        command.Parameters.AddWithValue("y", town.Y);
        command.Parameters.AddWithValue("day", day);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var delivered = new Dictionary<string, long>();
        while (await reader.ReadAsync(cancellationToken))
        {
            delivered[reader.GetString(0)] = reader.GetInt64(1);
        }

        return delivered;
    }

    private async Task AddDayDeliveryAsync(Town town, int day, string item, long quantity, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """
            INSERT INTO world.town_deliveries (town_x, town_y, day, item, quantity) VALUES (@x, @y, @day, @item, @quantity)
            ON CONFLICT (town_x, town_y, day, item) DO UPDATE SET quantity = world.town_deliveries.quantity + excluded.quantity
            """, cancellationToken);
        command.Parameters.AddWithValue("x", town.X);
        command.Parameters.AddWithValue("y", town.Y);
        command.Parameters.AddWithValue("day", day);
        command.Parameters.AddWithValue("item", item);
        command.Parameters.AddWithValue("quantity", quantity);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>One town at a time changes, so two deliveries cannot both fill the same need.</summary>
    private async Task LockTownAsync(Town town, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync("SELECT pg_advisory_xact_lock(@key)", cancellationToken);
        command.Parameters.AddWithValue("key", 0x746f776eL << 32 | (long)(town.X & 0xffff) << 16 | (long)(town.Y & 0xffff));
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>Delivers goods the town wants, from the inventory or from the station of the city plot: the town pays for as many as it still
    /// wants today, grows on them, and the player gets experience.</summary>
    public Task<(long Quantity, long Cents, XpGain Xp, int Level)> DeliverAsync(
        Guid player, int x, int y, string item, long quantity, bool fromStation, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var town = RequireTown(x, y);
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, fromStation ? PlotRight.Take : PlotRight.Work);
            if (quantity < 1)
            {
                throw new GameException("bad_quantity", "Deliver at least one.");
            }

            await LockTownAsync(town, cancellationToken);
            var before = CityRules.Level(await DeliveredAsync(town, cancellationToken));
            var policy = await PolicyAsync(town, cancellationToken);
            var need = (await NeedsAsync(town, before, policy, cancellationToken)).FirstOrDefault(n => n.Item == item);
            if (need.Item is null)
            {
                throw new GameException("not_wanted", "The town does not want this today.");
            }

            var taken = Math.Min(quantity, need.Wanted - need.Delivered);
            if (taken <= 0)
            {
                throw new GameException("need_met", "The town has got all it wants of this today.");
            }

            if (fromStation)
            {
                await StationStock.ChangeAsync(db, x, y, item, -taken, cancellationToken);
            }
            else
            {
                await inventory.RemoveAsync(player, item, taken, cancellationToken);
            }

            var cents = taken * need.PriceCents;
            await AddDayDeliveryAsync(town, CityRules.DayOf(time.GetUtcNow()), item, taken, cancellationToken);
            await using (var grow = await db.CommandAsync(
                """
                INSERT INTO world.town_progress (town_x, town_y, delivered_cents) VALUES (@x, @y, @cents)
                ON CONFLICT (town_x, town_y) DO UPDATE SET delivered_cents = world.town_progress.delivered_cents + excluded.delivered_cents;
                INSERT INTO world.town_contributions (town_x, town_y, player_id, delivered_cents) VALUES (@x, @y, @player, @cents)
                ON CONFLICT (town_x, town_y, player_id) DO UPDATE SET delivered_cents = world.town_contributions.delivered_cents + excluded.delivered_cents
                """, cancellationToken))
            {
                grow.Parameters.AddWithValue("x", town.X);
                grow.Parameters.AddWithValue("y", town.Y);
                grow.Parameters.AddWithValue("cents", cents);
                grow.Parameters.AddWithValue("player", player);
                await grow.ExecuteNonQueryAsync(cancellationToken);
            }

            await wallet.CreditAsync(player, cents, $"town {town.Name}: {taken} {item}", cancellationToken);
            var xp = await progress.AddXpAsync(player, Math.Max(1, cents / 1000), cancellationToken);
            return (taken, cents, xp, CityRules.Level(await DeliveredAsync(town, cancellationToken)));
        }, cancellationToken);

    /// <summary>Takes rubbish away from the town into the city plot's station, for a fee the town pays; the town has only so much a day.</summary>
    public Task<(long Quantity, long Cents)> TakeTrashAsync(Guid player, int x, int y, long quantity, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var town = RequireTown(x, y);
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Take);
            if (quantity < 1)
            {
                throw new GameException("bad_quantity", "Take at least one.");
            }

            await LockTownAsync(town, cancellationToken);
            var day = CityRules.DayOf(time.GetUtcNow());
            var left = CityRules.TrashPerDay(town, CityRules.Level(await DeliveredAsync(town, cancellationToken)))
                - (await DayDeliveriesAsync(town, day, cancellationToken)).GetValueOrDefault(Items.Trash);
            var taken = Math.Min(quantity, left);
            if (taken <= 0)
            {
                throw new GameException("no_trash", "The town has no more rubbish today.");
            }

            await AddDayDeliveryAsync(town, day, Items.Trash, taken, cancellationToken);
            await StationStock.ChangeAsync(db, x, y, Items.Trash, taken, cancellationToken);
            var cents = taken * CityRules.TrashFeeCents;
            await wallet.CreditAsync(player, cents, $"town {town.Name}: {taken} rubbish taken away", cancellationToken);
            return (taken, cents);
        }, cancellationToken);

    /// <summary>The offices in the plots of a town that sell services.</summary>
    private async Task<IReadOnlyList<(Guid Id, int X, int Y, string Kind, Guid Owner)>> ServicesOfAsync(Town town, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """
            SELECT id, x, y, kind, owner_id FROM world.plot_objects
            WHERE kind = ANY(@kinds) AND x BETWEEN @x - 40 AND @x + 40 AND y BETWEEN @y - 40 AND @y + 40
            ORDER BY kind, id
            """, cancellationToken);
        command.Parameters.AddWithValue("kinds", CityRules.Services.Keys.ToArray());
        command.Parameters.AddWithValue("x", town.X);
        command.Parameters.AddWithValue("y", town.Y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var found = new List<(Guid, int, int, string, Guid)>();
        while (await reader.ReadAsync(cancellationToken))
        {
            found.Add((reader.GetGuid(0), reader.GetInt32(1), reader.GetInt32(2), reader.GetString(3), reader.GetGuid(4)));
        }

        return found.Where(s => TownOf(s.Item2, s.Item3) == town).ToList();
    }

    private async Task<int> SalesTodayAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync("SELECT count FROM world.service_sales WHERE id = @id AND day = @day", cancellationToken);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("day", CityRules.DayOf(time.GetUtcNow()));
        return await command.ExecuteScalarAsync(cancellationToken) is int count ? count : 0;
    }

    /// <summary>Pays an owner what came in, less the mayor's tax, which goes to the mayor (unless the mayor is the one who paid).</summary>
    private async Task PayAsync(Town town, Guid owner, Guid? payer, long cents, string reason, CancellationToken cancellationToken)
    {
        if (cents <= 0)
        {
            return;
        }

        var policy = await PolicyAsync(town, cancellationToken);
        var tax = policy.Mayor is { } mayor && mayor != owner && mayor != payer ? cents * policy.TaxPercent / 100 : 0;
        await wallet.CreditAsync(owner, cents - tax, reason, cancellationToken);
        if (tax > 0)
        {
            await wallet.CreditAsync(policy.Mayor!.Value, tax, $"tax of {town.Name}: {reason}", cancellationToken);
        }
    }

    /// <summary>Buys an office's service: the buyer pays its owner (and the mayor's tax) and gets what it makes.</summary>
    public Task<(string Item, int Quantity, long Cents)> BuyServiceAsync(Guid player, int x, int y, Guid id, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var town = RequireTown(x, y);
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Work);
            var office = (await ServicesOfAsync(town, cancellationToken)).FirstOrDefault(s => s.Id == id);
            if (office.Kind is null)
            {
                throw new GameException("no_service", "There is no such office in this town.");
            }

            if (office.Owner == player)
            {
                throw new GameException("own_service", "This office is yours: make it yourself.");
            }

            await using (var lockRow = await db.CommandAsync("SELECT pg_advisory_xact_lock(@key)", cancellationToken))
            {
                lockRow.Parameters.AddWithValue("key", BitConverter.ToInt64(id.ToByteArray()));
                await lockRow.ExecuteNonQueryAsync(cancellationToken);
            }

            if (await SalesTodayAsync(id, cancellationToken) >= CityRules.ServiceSalesPerDay)
            {
                throw new GameException("service_busy", $"An office serves {CityRules.ServiceSalesPerDay} customers a day; come back tomorrow.");
            }

            var (item, quantity, price) = CityRules.Services[office.Kind];
            await wallet.DebitAsync(player, price, $"service {office.Kind} in {town.Name}", cancellationToken);
            await inventory.ReceiveAsync(player, item, quantity, cancellationToken);
            await PayAsync(town, office.Owner, player, price, $"service {office.Kind} sold", cancellationToken);
            await using (var count = await db.CommandAsync(
                """
                INSERT INTO world.service_sales (id, day, count) VALUES (@id, @day, 1)
                ON CONFLICT (id, day) DO UPDATE SET count = world.service_sales.count + 1
                """, cancellationToken))
            {
                count.Parameters.AddWithValue("id", id);
                count.Parameters.AddWithValue("day", CityRules.DayOf(time.GetUtcNow()));
                await count.ExecuteNonQueryAsync(cancellationToken);
            }

            return (item, quantity, price);
        }, cancellationToken);

    /// <summary>The owners of plots in a town: who may vote and be elected there.</summary>
    private async Task<IReadOnlyList<Guid>> TownsfolkAsync(Town town, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """
            SELECT x, y, owner_id FROM world.plots
            WHERE biome = @city AND x BETWEEN @x - 40 AND @x + 40 AND y BETWEEN @y - 40 AND @y + 40
            """, cancellationToken);
        command.Parameters.AddWithValue("city", (short)Biome.City);
        command.Parameters.AddWithValue("x", town.X);
        command.Parameters.AddWithValue("y", town.Y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var owners = new List<Guid>();
        while (await reader.ReadAsync(cancellationToken))
        {
            if (TownOf(reader.GetInt32(0), reader.GetInt32(1)) == town)
            {
                owners.Add(reader.GetGuid(2));
            }
        }

        return owners.Distinct().ToList();
    }

    /// <summary>Votes for next week's mayor: a player who owns a plot in the town votes for one who does too, once a week (a new vote replaces the old).</summary>
    public Task VoteAsync(Guid player, int x, int y, string candidate, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var town = RequireTown(x, y);
            var folk = await TownsfolkAsync(town, cancellationToken);
            if (!folk.Contains(player))
            {
                throw new GameException("not_townsman", "Only players who own a plot in the town vote here.");
            }

            var chosen = await names.AccountAsync(candidate ?? "", cancellationToken);
            if (chosen is not { } id || !folk.Contains(id))
            {
                throw new GameException("not_candidate", "Vote for a player who owns a plot in the town.");
            }

            await using var vote = await db.CommandAsync(
                """
                INSERT INTO world.town_votes (town_x, town_y, week, voter_id, candidate_id) VALUES (@x, @y, @week, @voter, @candidate)
                ON CONFLICT (town_x, town_y, week, voter_id) DO UPDATE SET candidate_id = excluded.candidate_id
                """, cancellationToken);
            vote.Parameters.AddWithValue("x", town.X);
            vote.Parameters.AddWithValue("y", town.Y);
            vote.Parameters.AddWithValue("week", CityRules.WeekOf(time.GetUtcNow()));
            vote.Parameters.AddWithValue("voter", player);
            vote.Parameters.AddWithValue("candidate", id);
            await vote.ExecuteNonQueryAsync(cancellationToken);
        }, cancellationToken);

    /// <summary>The mayor sets this week's tax on shops and services and the town's bonus.</summary>
    public Task SetPolicyAsync(Guid player, int x, int y, int taxPercent, string? bonus, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var town = RequireTown(x, y);
            if ((await PolicyAsync(town, cancellationToken)).Mayor != player)
            {
                throw new GameException("not_mayor", "Only this week's mayor sets the town's policy.");
            }

            if (taxPercent < 0 || taxPercent > CityRules.MaxTaxPercent)
            {
                throw new GameException("bad_tax", $"The tax is 0-{CityRules.MaxTaxPercent}%.");
            }

            if (bonus is not null && !CityRules.Bonuses.ContainsKey(bonus))
            {
                throw new GameException("bad_bonus", "There is no such bonus.");
            }

            await using var update = await db.CommandAsync(
                "UPDATE world.town_policies SET tax_percent = @tax, bonus = @bonus WHERE town_x = @x AND town_y = @y AND week = @week", cancellationToken);
            update.Parameters.AddWithValue("x", town.X);
            update.Parameters.AddWithValue("y", town.Y);
            update.Parameters.AddWithValue("week", CityRules.WeekOf(time.GetUtcNow()));
            update.Parameters.AddWithValue("tax", taxPercent);
            update.Parameters.AddWithValue("bonus", (object?)bonus ?? DBNull.Value);
            await update.ExecuteNonQueryAsync(cancellationToken);
        }, cancellationToken);

    /// <summary>Everything the town window shows.</summary>
    public async Task<object> ViewAsync(Guid player, int x, int y, CancellationToken cancellationToken)
    {
        var town = RequireTown(x, y);
        await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Work);
        var now = time.GetUtcNow();
        var delivered = await DeliveredAsync(town, cancellationToken);
        var level = CityRules.Level(delivered);
        var policy = await PolicyAsync(town, cancellationToken);
        var needs = await NeedsAsync(town, level, policy, cancellationToken);
        var day = CityRules.DayOf(now);
        var trashTaken = (await DayDeliveriesAsync(town, day, cancellationToken)).GetValueOrDefault(Items.Trash);

        var contributors = new List<(Guid Id, long Cents)>();
        long mine = 0;
        await using (var command = await db.CommandAsync(
            """
            SELECT player_id, delivered_cents FROM world.town_contributions WHERE town_x = @x AND town_y = @y
            ORDER BY delivered_cents DESC, player_id LIMIT 5;
            SELECT delivered_cents FROM world.town_contributions WHERE town_x = @x AND town_y = @y AND player_id = @player
            """, cancellationToken))
        {
            command.Parameters.AddWithValue("x", town.X);
            command.Parameters.AddWithValue("y", town.Y);
            command.Parameters.AddWithValue("player", player);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                contributors.Add((reader.GetGuid(0), reader.GetInt64(1)));
            }

            await reader.NextResultAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                mine = reader.GetInt64(0);
            }
        }

        var offices = await ServicesOfAsync(town, cancellationToken);
        var sales = new Dictionary<Guid, int>();
        foreach (var office in offices)
        {
            sales[office.Id] = await SalesTodayAsync(office.Id, cancellationToken);
        }

        var folk = await TownsfolkAsync(town, cancellationToken);
        var votes = new Dictionary<Guid, int>();
        Guid? myVote = null;
        await using (var command = await db.CommandAsync(
            "SELECT voter_id, candidate_id FROM world.town_votes WHERE town_x = @x AND town_y = @y AND week = @week", cancellationToken))
        {
            command.Parameters.AddWithValue("x", town.X);
            command.Parameters.AddWithValue("y", town.Y);
            command.Parameters.AddWithValue("week", CityRules.WeekOf(now));
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var candidate = reader.GetGuid(1);
                votes[candidate] = votes.GetValueOrDefault(candidate) + 1;
                if (reader.GetGuid(0) == player)
                {
                    myVote = candidate;
                }
            }
        }

        var named = await names.NamesAsync(
            contributors.Select(c => c.Id).Concat(offices.Select(o => o.Owner)).Concat(folk).Concat(policy.Mayor is { } m ? [m] : []).Distinct().ToList(),
            cancellationToken);
        string Name(Guid id) => named.GetValueOrDefault(id, "?");
        var week = CityRules.WeekOf(now);
        return new
        {
            town = new
            {
                name = town.Name,
                x = town.X,
                y = town.Y,
                population = town.Population,
                level,
                levelName = CityRules.LevelNames[level],
                levelNames = CityRules.LevelNames,
                deliveredCents = delivered,
                levelCents = CityRules.LevelCents,
                distance = Math.Round(CityRules.Distance(map.Width, x, y, town.X, town.Y), 1),
            },
            dayEndsAt = CityRules.DayStart(day + 1).ToUnixTimeMilliseconds(),
            needs = needs.Select(n => new
            {
                id = n.Item,
                name = Items.Names.GetValueOrDefault(n.Item, n.Item),
                wanted = n.Wanted,
                delivered = n.Delivered,
                priceCents = n.PriceCents,
            }),
            contributors = contributors.Select(c => new { name = Name(c.Id), cents = c.Cents, mine = c.Id == player }),
            myCents = mine,
            trash = new
            {
                perDay = CityRules.TrashPerDay(town, level),
                taken = trashTaken,
                feeCents = CityRules.TrashFeeCents,
            },
            services = offices.Select(o => new
            {
                id = o.Id,
                kind = o.Kind,
                name = Items.Names[o.Kind],
                owner = Name(o.Owner),
                own = o.Owner == player,
                item = CityRules.Services[o.Kind].Item,
                itemName = Items.Names[CityRules.Services[o.Kind].Item],
                quantity = CityRules.Services[o.Kind].Quantity,
                priceCents = CityRules.Services[o.Kind].PriceCents,
                left = CityRules.ServiceSalesPerDay - sales[o.Id],
            }),
            hall = new
            {
                week,
                weekEndsAt = CityRules.WeekStart(week + 1).ToUnixTimeMilliseconds(),
                mayor = policy.Mayor is { } mayor ? Name(mayor) : null,
                isMayor = policy.Mayor == player,
                taxPercent = policy.TaxPercent,
                maxTaxPercent = CityRules.MaxTaxPercent,
                bonus = policy.Bonus,
                bonuses = CityRules.Bonuses.Select(b => new { id = b.Key, name = b.Value }),
                canVote = folk.Contains(player),
                myVote = myVote is { } v ? Name(v) : null,
                candidates = folk.Select(f => new { name = Name(f), votes = votes.GetValueOrDefault(f), me = f == player })
                    .OrderByDescending(c => c.votes).ThenBy(c => c.name),
            },
        };
    }

    // --- Shops ---------------------------------------------------------------------------------------

    /// <summary>A shop's plot, owner and kind, or a failure when the id is no shop.</summary>
    private async Task<(int X, int Y, Guid Owner)> ShopAtAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync("SELECT x, y, owner_id, kind FROM world.plot_objects WHERE id = @id", cancellationToken);
        command.Parameters.AddWithValue("id", id);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken) || reader.GetString(3) != Items.Shop)
        {
            throw new GameException("no_shop", "There is no such shop.");
        }

        return (reader.GetInt32(0), reader.GetInt32(1), reader.GetGuid(2));
    }

    private async Task<List<ShopItemRow>> ShopItemsAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT item, quantity, price_cents FROM world.shop_items WHERE shop_id = @id ORDER BY item", cancellationToken);
        command.Parameters.AddWithValue("id", id);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var items = new List<ShopItemRow>();
        while (await reader.ReadAsync(cancellationToken))
        {
            items.Add(new ShopItemRow { ShopId = id, Item = reader.GetString(0), Quantity = reader.GetInt64(1), PriceCents = reader.GetInt64(2) });
        }

        return items;
    }

    private async Task SaveShopItemAsync(ShopItemRow row, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            row.Quantity > 0
                ? """
                  INSERT INTO world.shop_items (shop_id, item, quantity, price_cents) VALUES (@id, @item, @quantity, @price)
                  ON CONFLICT (shop_id, item) DO UPDATE SET quantity = excluded.quantity, price_cents = excluded.price_cents
                  """
                : "DELETE FROM world.shop_items WHERE shop_id = @id AND item = @item",
            cancellationToken);
        command.Parameters.AddWithValue("id", row.ShopId);
        command.Parameters.AddWithValue("item", row.Item);
        command.Parameters.AddWithValue("quantity", row.Quantity);
        command.Parameters.AddWithValue("price", row.PriceCents);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private async Task<double> CustomersAsync(int x, int y, CancellationToken cancellationToken)
    {
        var town = towns.Of(x, y);
        var level = CityRules.Level(await DeliveredAsync(town, cancellationToken));
        var shoppers = (await PolicyAsync(town, cancellationToken)).Bonus == "shoppers";
        return CityRules.Customers(town, level, CityRules.Distance(map.Width, x, y, town.X, town.Y), shoppers);
    }

    /// <summary>Works out what the townspeople bought in the shop since it was last looked at: each customer picks one of its
    /// goods and buys a piece if the price is right. The money goes to the owner, less the mayor's tax.</summary>
    private async Task<(Guid Owner, int X, int Y)> SettleAsync(Guid id, CancellationToken cancellationToken)
    {
        var (x, y, owner) = await ShopAtAsync(id, cancellationToken);
        var now = time.GetUtcNow();
        await using (var create = await db.CommandAsync(
            "INSERT INTO world.shops (id, settled_at, carry, sold_cents, sold_items) VALUES (@id, @now, 0, 0, 0) ON CONFLICT DO NOTHING", cancellationToken))
        {
            create.Parameters.AddWithValue("id", id);
            create.Parameters.AddWithValue("now", now);
            await create.ExecuteNonQueryAsync(cancellationToken);
        }

        DateTimeOffset settled;
        double carry;
        await using (var read = await db.CommandAsync("SELECT settled_at, carry FROM world.shops WHERE id = @id FOR UPDATE", cancellationToken))
        {
            read.Parameters.AddWithValue("id", id);
            await using var reader = await read.ExecuteReaderAsync(cancellationToken);
            await reader.ReadAsync(cancellationToken);
            (settled, carry) = (reader.GetFieldValue<DateTimeOffset>(0), reader.GetDouble(1));
        }

        if (now <= settled)
        {
            return (owner, x, y);
        }

        var stock = await ShopItemsAsync(id, cancellationToken);
        var hours = (now - settled < CityRules.ShopCatchUp ? now - settled : CityRules.ShopCatchUp).TotalHours;
        var expected = carry + (stock.Count > 0 ? (await CustomersAsync(x, y, cancellationToken)) * hours : 0);
        var customers = (long)Math.Floor(expected);
        carry = expected - customers;
        var random = new Random(HashCode.Combine(id, settled.UtcTicks));
        long revenue = 0, sold = 0;
        var changed = new HashSet<ShopItemRow>();
        for (var i = 0; i < customers; i++)
        {
            var shelf = stock.Where(s => s.Quantity > 0).ToList();
            if (shelf.Count == 0)
            {
                carry = 0;
                break;
            }

            var pick = shelf[random.Next(shelf.Count)];
            var trader = prices.BuysCents(pick.Item) ?? 0;
            if (trader > 0 && random.NextDouble() < CityRules.Accepts(pick.PriceCents, trader))
            {
                pick.Quantity--;
                revenue += pick.PriceCents;
                sold++;
                changed.Add(pick);
            }
        }

        foreach (var row in changed)
        {
            await SaveShopItemAsync(row, cancellationToken);
        }

        await using (var update = await db.CommandAsync(
            """
            UPDATE world.shops SET settled_at = @now, carry = @carry, sold_cents = sold_cents + @revenue, sold_items = sold_items + @sold
            WHERE id = @id
            """, cancellationToken))
        {
            update.Parameters.AddWithValue("id", id);
            update.Parameters.AddWithValue("now", now);
            update.Parameters.AddWithValue("carry", carry);
            update.Parameters.AddWithValue("revenue", revenue);
            update.Parameters.AddWithValue("sold", sold);
            await update.ExecuteNonQueryAsync(cancellationToken);
        }

        await PayAsync(towns.Of(x, y), owner, null, revenue, $"shop sales: {sold} items", cancellationToken);
        return (owner, x, y);
    }

    private async Task<object> ShopStateAsync(Guid id, int x, int y, CancellationToken cancellationToken)
    {
        var stock = await ShopItemsAsync(id, cancellationToken);
        long soldCents = 0, soldItems = 0;
        await using (var command = await db.CommandAsync("SELECT sold_cents, sold_items FROM world.shops WHERE id = @id", cancellationToken))
        {
            command.Parameters.AddWithValue("id", id);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                (soldCents, soldItems) = (reader.GetInt64(0), reader.GetInt64(1));
            }
        }

        var town = towns.Of(x, y);
        return new
        {
            id,
            town = town.Name,
            customersPerHour = Math.Round(await CustomersAsync(x, y, cancellationToken), 1),
            soldCents,
            soldItems,
            maxKinds = CityRules.ShopKinds,
            maxStock = CityRules.ShopMaxStock,
            taxPercent = (await PolicyAsync(town, cancellationToken)).TaxPercent,
            items = stock.Select(s => new
            {
                id = s.Item,
                name = Items.Names.GetValueOrDefault(s.Item, s.Item),
                quantity = s.Quantity,
                priceCents = s.PriceCents,
                traderCents = prices.BuysCents(s.Item),
                buyPercent = prices.BuysCents(s.Item) is { } trader ? (int)Math.Round(100 * CityRules.Accepts(s.PriceCents, trader)) : 0,
            }),
        };
    }

    public Task<object> ShopAsync(Guid player, Guid id, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var (_, x, y) = await SettleAsync(id, cancellationToken);
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Work);
            return await ShopStateAsync(id, x, y, cancellationToken);
        }, cancellationToken);

    /// <summary>Puts goods from the inventory on the shop's shelves at a price (which then holds for all of that item there).</summary>
    public Task<object> StockShopAsync(Guid player, Guid id, string item, long quantity, long priceCents, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var (_, x, y) = await SettleAsync(id, cancellationToken);
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Take);
            if (prices.BuysCents(item ?? "") is null)
            {
                throw new GameException("not_sellable", "Nobody in town buys this.");
            }

            if (priceCents < 1)
            {
                throw new GameException("bad_price", "Set a price.");
            }

            var stock = await ShopItemsAsync(id, cancellationToken);
            var row = stock.FirstOrDefault(s => s.Item == item);
            if (row is null && stock.Count >= CityRules.ShopKinds)
            {
                throw new GameException("shop_full", $"A shop holds {CityRules.ShopKinds} kinds of goods.");
            }

            row ??= new ShopItemRow { ShopId = id, Item = item! };
            if (quantity < 0 || row.Quantity + quantity > CityRules.ShopMaxStock)
            {
                throw new GameException("bad_quantity", $"A shop holds at most {CityRules.ShopMaxStock} of each.");
            }

            if (quantity > 0)
            {
                await inventory.RemoveAsync(player, item!, quantity, cancellationToken);
            }

            row.Quantity += quantity;
            row.PriceCents = priceCents;
            if (row.Quantity == 0)
            {
                throw new GameException("bad_quantity", "Put at least one on the shelf.");
            }

            await SaveShopItemAsync(row, cancellationToken);
            return await ShopStateAsync(id, x, y, cancellationToken);
        }, cancellationToken);

    /// <summary>Takes goods off the shop's shelves back into the inventory.</summary>
    public Task<object> TakeFromShopAsync(Guid player, Guid id, string item, long quantity, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var (_, x, y) = await SettleAsync(id, cancellationToken);
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, PlotRight.Take);
            var row = (await ShopItemsAsync(id, cancellationToken)).FirstOrDefault(s => s.Item == item);
            if (row is null || quantity < 1 || quantity > row.Quantity)
            {
                throw new GameException("bad_quantity", "The shop has not so many.");
            }

            row.Quantity -= quantity;
            await SaveShopItemAsync(row, cancellationToken);
            await inventory.ReceiveAsync(player, item, quantity, cancellationToken);
            return await ShopStateAsync(id, x, y, cancellationToken);
        }, cancellationToken);

    /// <summary>A shop picked up (it is gone from the plot by now): what is left on its shelves goes back to the owner.</summary>
    public async Task ReleaseAsync(Guid owner, Guid id, CancellationToken cancellationToken)
    {
        foreach (var row in await ShopItemsAsync(id, cancellationToken))
        {
            await inventory.AddAsync(owner, row.Item, row.Quantity, cancellationToken);
        }

        await using var delete = await db.CommandAsync(
            "DELETE FROM world.shop_items WHERE shop_id = @id; DELETE FROM world.shops WHERE id = @id", cancellationToken);
        delete.Parameters.AddWithValue("id", id);
        await delete.ExecuteNonQueryAsync(cancellationToken);
    }

    // --- What cities change elsewhere -----------------------------------------------------------------

    /// <summary>What rail fees from a plot are multiplied by: less in a city, with a freight terminal and with the mayor's bonus.</summary>
    public async Task<double> RailFactorAsync(int x, int y, CancellationToken cancellationToken)
    {
        if (TownOf(x, y) is not { } town)
        {
            return 1;
        }

        var factor = CityRules.CityRail;
        if (await beach.HasAsync(x, y, Items.FreightTerminal, 0, cancellationToken))
        {
            factor *= CityRules.TerminalRail;
        }

        if ((await PolicyAsync(town, cancellationToken)).Bonus == "rail")
        {
            factor *= CityRules.MayorRail;
        }

        return factor;
    }

    public async Task<int> MaxRoutesAsync(int x, int y, CancellationToken cancellationToken) =>
        TownOf(x, y) is not null && await beach.HasAsync(x, y, Items.FreightTerminal, 0, cancellationToken) ? CityRules.TerminalRoutes : RailRules.MaxRoutes;

    /// <summary>What a city plot's price is multiplied by: less with the mayor's "plots" bonus.</summary>
    public async Task<double> PlotPriceFactorAsync(int x, int y, CancellationToken cancellationToken) =>
        TownOf(x, y) is { } town && (await PolicyAsync(town, cancellationToken)).Bonus == "plots" ? CityRules.CheapPlots : 1;
}

public sealed record CityRequest(int X, int Y);

public sealed record DeliverRequest(int X, int Y, string Item, long Quantity, bool FromStation = false);

public sealed record TrashRequest(int X, int Y, long Quantity);

public sealed record ServiceRequest(int X, int Y, Guid Id);

public sealed record VoteRequest(int X, int Y, string Candidate);

public sealed record PolicyRequest(int X, int Y, int TaxPercent, string? Bonus);

public sealed record ShopRequest(Guid Id, string? Item = null, long Quantity = 0, long PriceCents = 0);

public abstract class CityHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var cities = scope.ServiceProvider.GetRequiredService<CityService>();
        var player = client.RequireAccount();
        var done = await RunAsync(cities, player, payload, cancellationToken);
        var at = Payload.Read<CityRequest>(payload);
        return new Reply("city", new { result = done, state = await cities.ViewAsync(player, at.X, at.Y, cancellationToken) });
    }

    protected abstract Task<object?> RunAsync(CityService cities, Guid player, JsonElement? payload, CancellationToken cancellationToken);
}

public sealed class GetCityHandler(IServiceScopeFactory scopes) : CityHandler(scopes)
{
    public override string Type => "city.get";

    protected override Task<object?> RunAsync(CityService cities, Guid player, JsonElement? payload, CancellationToken cancellationToken) =>
        Task.FromResult<object?>(null);
}

public sealed class DeliverToCityHandler(IServiceScopeFactory scopes) : CityHandler(scopes)
{
    public override string Type => "city.deliver";

    protected override async Task<object?> RunAsync(CityService cities, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var r = Payload.Read<DeliverRequest>(payload);
        var (quantity, cents, xp, level) = await cities.DeliverAsync(player, r.X, r.Y, r.Item ?? "", r.Quantity, r.FromStation, cancellationToken);
        return new { item = r.Item, quantity, cents, level, xp = new { xp = xp.Xp, level = xp.Level, leveledUp = xp.LeveledUp } };
    }
}

public sealed class CityTrashHandler(IServiceScopeFactory scopes) : CityHandler(scopes)
{
    public override string Type => "city.trash";

    protected override async Task<object?> RunAsync(CityService cities, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var r = Payload.Read<TrashRequest>(payload);
        var (quantity, cents) = await cities.TakeTrashAsync(player, r.X, r.Y, r.Quantity, cancellationToken);
        return new { quantity, cents };
    }
}

public sealed class CityServiceHandler(IServiceScopeFactory scopes) : CityHandler(scopes)
{
    public override string Type => "city.service";

    protected override async Task<object?> RunAsync(CityService cities, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var r = Payload.Read<ServiceRequest>(payload);
        var (item, quantity, cents) = await cities.BuyServiceAsync(player, r.X, r.Y, r.Id, cancellationToken);
        return new { item, name = Items.Names[item], quantity, cents };
    }
}

public sealed class CityVoteHandler(IServiceScopeFactory scopes) : CityHandler(scopes)
{
    public override string Type => "city.vote";

    protected override async Task<object?> RunAsync(CityService cities, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var r = Payload.Read<VoteRequest>(payload);
        await cities.VoteAsync(player, r.X, r.Y, r.Candidate, cancellationToken);
        return null;
    }
}

public sealed class CityPolicyHandler(IServiceScopeFactory scopes) : CityHandler(scopes)
{
    public override string Type => "city.policy";

    protected override async Task<object?> RunAsync(CityService cities, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var r = Payload.Read<PolicyRequest>(payload);
        await cities.SetPolicyAsync(player, r.X, r.Y, r.TaxPercent, string.IsNullOrEmpty(r.Bonus) ? null : r.Bonus, cancellationToken);
        return null;
    }
}

public abstract class ShopHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var cities = scope.ServiceProvider.GetRequiredService<CityService>();
        var request = Payload.Read<ShopRequest>(payload);
        return new Reply("shop", await RunAsync(cities, client.RequireAccount(), request, cancellationToken));
    }

    protected abstract Task<object> RunAsync(CityService cities, Guid player, ShopRequest request, CancellationToken cancellationToken);
}

public sealed class GetShopHandler(IServiceScopeFactory scopes) : ShopHandler(scopes)
{
    public override string Type => "shop.get";

    protected override Task<object> RunAsync(CityService cities, Guid player, ShopRequest request, CancellationToken cancellationToken) =>
        cities.ShopAsync(player, request.Id, cancellationToken);
}

public sealed class StockShopHandler(IServiceScopeFactory scopes) : ShopHandler(scopes)
{
    public override string Type => "shop.stock";

    protected override Task<object> RunAsync(CityService cities, Guid player, ShopRequest request, CancellationToken cancellationToken) =>
        cities.StockShopAsync(player, request.Id, request.Item ?? "", request.Quantity, request.PriceCents, cancellationToken);
}

public sealed class TakeFromShopHandler(IServiceScopeFactory scopes) : ShopHandler(scopes)
{
    public override string Type => "shop.take";

    protected override Task<object> RunAsync(CityService cities, Guid player, ShopRequest request, CancellationToken cancellationToken) =>
        cities.TakeFromShopAsync(player, request.Id, request.Item ?? "", request.Quantity, cancellationToken);
}
