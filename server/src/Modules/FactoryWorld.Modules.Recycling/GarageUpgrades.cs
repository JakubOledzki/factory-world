using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Recycling;

/// <summary>One level of an upgrade: what it is called, what it costs and what must be done first
/// (besides the level before it on the same track).</summary>
public sealed record UpgradeStep(
    string Name, long PriceCents, IReadOnlyList<(string Item, int Quantity)> Materials, IReadOnlyList<(string Track, int Level)> Requires);

/// <summary>A way to upgrade the garage, bought level by level: each level costs money and materials
/// and gives <see cref="PerLevel"/> more of <see cref="Bonus"/>.</summary>
/// <param name="Start">What the garage has before the first level.</param>
/// <param name="Bonus">An industry (<see cref="Industries"/>), <see cref="PlayerBonus.Xp"/>,
/// <see cref="GarageUpgrades.ShelfSlots"/> or <see cref="GarageUpgrades.Sorting"/>.</param>
/// <param name="BonusName">How the client names the bonus, followed by the amount and <paramref name="Unit"/>.</param>
public sealed record UpgradeTrack(
    string Id, string Name, string Start, string Bonus, int PerLevel, string BonusName, string Unit, IReadOnlyList<UpgradeStep> Steps)
{
    public int MaxLevel => Steps.Count;
}

/// <summary>
/// The garage is upgraded along five tracks, from a dirty garage up to an office with glass walls
/// over the city. A level is bought only after the one before it, sometimes only once another
/// track is far enough too. Every level gives its track's bonus: faster crafting (floor), better
/// prices at the trader (walls), more experience (lighting), more room on the shelf (shelves) and
/// faster sorting of trash (heating).
/// </summary>
public static class GarageUpgrades
{
    public const string Floor = "floor";
    public const string Walls = "walls";
    public const string Lighting = "lighting";
    public const string Shelves = "shelves";
    public const string Heating = "heating";

    /// <summary>Extra slots of the shelf in the garage.</summary>
    public const string ShelfSlots = "shelf_slots";

    /// <summary>Percent less time to sort a bag of trash, by hand and in the sorting machine.</summary>
    public const string Sorting = "sorting";

    private static UpgradeStep Step(string name, long dollars, (string, int)[] materials, params (string, int)[] requires) =>
        new(name, dollars * 100, materials, requires);

    public static readonly IReadOnlyList<UpgradeTrack> Tracks =
    [
        new(Floor, "Podłoga", "Surowy beton w plamach", Industries.Crafting, 1, "Wytwarzanie szybsze o", "%",
        [
            Step("Oczyszczony beton", 150, [(Items.Sand, 20)]),
            Step("Beton szlifowany", 300, [(Items.Stone, 20), (Items.Sand, 10)]),
            Step("Posadzka żywiczna", 500, [(Items.Cement, 10), (Items.Paint, 5)]),
            Step("Płytki warsztatowe", 800, [(Items.Clay, 30), (Items.Cement, 15)]),
            Step("Gres", 1300, [(Items.StoneBlocks, 20), (Items.Cement, 20)]),
            Step("Panele", 2000, [(Items.Plywood, 40)]),
            Step("Deski sosnowe", 3000, [(Items.Planks, 60), (Items.Nails, 30)]),
            Step("Parkiet dębowy", 4500, [(Items.OakWood, 40), (Items.CaseinGlue, 10)]),
            Step("Lastryko", 7000, [(Items.MarbleSlabs, 20), (Items.Concrete, 30)]),
            Step("Marmur", 12_000, [(Items.MarbleSlabs, 40), (Items.Cement, 20)]),
        ]),
        new(Walls, "Ściany", "Gołe pustaki", Industries.Trade, 1, "Handlarz płaci więcej o", "%",
        [
            Step("Tynk", 200, [(Items.Cement, 20), (Items.Sand, 20)]),
            Step("Białe ściany", 350, [(Items.Paint, 5)]),
            Step("Boazeria", 600, [(Items.Planks, 30), (Items.Nails, 20)]),
            Step("Płytki do połowy", 900, [(Items.Clay, 30), (Items.Cement, 15)]),
            Step("Cegła klinkierowa", 1400, [(Items.Bricks, 120), (Items.Cement, 20)]),
            Step("Dębowe panele", 2200, [(Items.OakWood, 30), (Items.Paint, 10)], (Lighting, 2)),
            Step("Duże okna", 3300, [(Items.WindowPane, 4), (Items.SteelIngot, 10)], (Lighting, 3)),
            Step("Beton architektoniczny", 5000, [(Items.InsulationBoard, 10), (Items.PrecastConcrete, 10)], (Floor, 6)),
            Step("Przeszklenie", 8000, [(Items.WindowPane, 10), (Items.GlassLaminate, 10), (Items.SteelIngot, 10)], (Floor, 7)),
            Step("Biuro z widokiem na miasto", 15_000, [(Items.WindowPane, 20), (Items.GlassLaminate, 20), (Items.SteelIngot, 20)],
                (Floor, 8), (Lighting, 5)),
        ]),
        new(Lighting, "Oświetlenie", "Goła żarówka", PlayerBonus.Xp, 2, "Doświadczenie większe o", "%",
        [
            Step("Świetlówki", 200, [(Items.Glass, 5), (Items.CopperIngot, 5)]),
            Step("Lampy warsztatowe", 600, [(Items.Glass, 10), (Items.ElectricWire, 10)]),
            Step("Panele LED", 1500, [(Items.CircuitBoard, 5), (Items.ElectricWire, 10)]),
            Step("Oświetlenie biurowe", 4000, [(Items.CircuitBoard, 10), (Items.GlassLaminate, 10)]),
            Step("Inteligentne oświetlenie", 9000, [(Items.CircuitBoard, 20), (Items.Battery, 2)]),
        ]),
        new(Shelves, "Regały", "Drewniany regał", ShelfSlots, 8, "Regał mieści więcej o", " miejsc",
        [
            Step("Dodatkowe półki", 300, [(Items.Planks, 20), (Items.Nails, 10)]),
            Step("Regał metalowy", 800, [(Items.IronIngot, 10), (Items.Nails, 20)]),
            Step("Szuflady na drobiazgi", 1600, [(Items.Plywood, 20), (Items.SteelIngot, 5)]),
            Step("Regał wysokiego składowania", 3500, [(Items.SteelIngot, 15)]),
            Step("System magazynowy", 7000, [(Items.SteelIngot, 20), (Items.CircuitBoard, 10)]),
        ]),
        new(Heating, "Ogrzewanie", "Zimny garaż", Sorting, 8, "Segregacja szybsza o", "%",
        [
            Step("Koza na drewno", 250, [(Items.Bricks, 20), (Items.IronIngot, 10)]),
            Step("Kaloryfery", 700, [(Items.IronIngot, 15), (Items.CopperIngot, 5)]),
            Step("Ocieplenie", 1500, [(Items.InsulationBoard, 10)]),
            Step("Grzejnik elektryczny", 3000, [(Items.Heater, 1), (Items.ElectricWire, 10)]),
            Step("Pompa ciepła", 7000, [(Items.Heater, 2), (Items.Coil, 5)]),
        ]),
    ];

    public static UpgradeTrack? Find(string id) => Tracks.FirstOrDefault(t => t.Id == id);

    /// <summary>What the garage is called, by how far it is upgraded: an office once the walls are glass.</summary>
    public static string Rank(IReadOnlyDictionary<string, int> levels)
    {
        if (levels.GetValueOrDefault(Walls) >= Find(Walls)!.MaxLevel)
        {
            return "Biuro";
        }

        return levels.Values.Sum() switch
        {
            >= 24 => "Studio",
            >= 16 => "Pracownia",
            >= 8 => "Warsztat",
            _ => "Garaż",
        };
    }

    /// <summary>The bonus the levels give, by bonus key; keys no track gives are left out.</summary>
    public static int Bonus(IReadOnlyDictionary<string, int> levels, string bonus) =>
        Tracks.Where(t => t.Bonus == bonus).Sum(t => levels.GetValueOrDefault(t.Id) * t.PerLevel);

    /// <summary>How long sorting one bag takes with this much heating.</summary>
    public static TimeSpan SortTime(IReadOnlyDictionary<string, int> levels) =>
        RecyclingRules.SortTime * (100 - Bonus(levels, Sorting)) / 100;

    /// <summary>Slots of the shelf in the garage.</summary>
    public static int ShelfSize(IReadOnlyDictionary<string, int> levels) => GarageStorageRules.ShelfSlots + Bonus(levels, ShelfSlots);
}

/// <summary>A row of <c>recycling.garage_upgrades</c>: the level a player bought on one track.</summary>
public sealed class GarageUpgrade
{
    public Guid OwnerId { get; set; }

    public string Track { get; set; } = "";

    public int Level { get; set; }
}

internal static class GarageUpgradeRows
{
    /// <summary>Level by track; tracks never upgraded are left out.</summary>
    public static async Task<IReadOnlyDictionary<string, int>> LevelsAsync(GameDb db, Guid owner, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT track, level FROM recycling.garage_upgrades WHERE owner_id = @owner", cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var levels = new Dictionary<string, int>();
        while (await reader.ReadAsync(cancellationToken))
        {
            levels[reader.GetString(0)] = reader.GetInt32(1);
        }

        return levels;
    }
}

public sealed record UpgradesState(IReadOnlyDictionary<string, int> Levels, long BalanceCents);

public sealed class GarageUpgradeService(GameDb db, IInventory inventory, IWallet wallet, SorterService sorters)
{
    public Task<UpgradesState> StateAsync(Guid owner, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () => new UpgradesState(
            await GarageUpgradeRows.LevelsAsync(db, owner, cancellationToken),
            await wallet.BalanceAsync(owner, cancellationToken)), cancellationToken);

    /// <summary>Buys the next level of a track: money and materials out, the level in, all or nothing.</summary>
    public Task<UpgradesState> BuyAsync(Guid owner, string trackId, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var track = GarageUpgrades.Find(trackId ?? "") ?? throw new GameException("no_upgrade", "There is no such upgrade.");

            // Lock the garage so two purchases at once cannot both buy the same level.
            await using (var command = await db.CommandAsync(
                "SELECT 1 FROM recycling.garages WHERE owner_id = @owner FOR UPDATE", cancellationToken))
            {
                command.Parameters.AddWithValue("owner", owner);
                if (await command.ExecuteScalarAsync(cancellationToken) is null)
                {
                    throw new GameException("no_garage", "Open your garage first.");
                }
            }

            var levels = await GarageUpgradeRows.LevelsAsync(db, owner, cancellationToken);
            var level = levels.GetValueOrDefault(track.Id);
            if (level >= track.MaxLevel)
            {
                throw new GameException("max_level", "This is upgraded as far as it goes.");
            }

            var step = track.Steps[level];
            foreach (var (other, needed) in step.Requires)
            {
                if (levels.GetValueOrDefault(other) < needed)
                {
                    throw new GameException(
                        "upgrade_required", $"First upgrade {GarageUpgrades.Find(other)!.Name.ToLowerInvariant()} to level {needed}.");
                }
            }

            foreach (var (item, quantity) in step.Materials)
            {
                await inventory.RemoveAsync(owner, item, quantity, cancellationToken);
            }

            var balance = await wallet.DebitAsync(owner, step.PriceCents, $"garage {track.Id} {level + 1}", cancellationToken);

            // Sorting machines work out what they sorted at the old speed before the heating changes it.
            if (track.Bonus == GarageUpgrades.Sorting)
            {
                await sorters.CatchUpAllAsync(owner, cancellationToken);
            }

            await using (var command = await db.CommandAsync(
                """
                INSERT INTO recycling.garage_upgrades (owner_id, track, level) VALUES (@owner, @track, @level)
                ON CONFLICT (owner_id, track) DO UPDATE SET level = @level
                """, cancellationToken))
            {
                command.Parameters.AddWithValue("owner", owner);
                command.Parameters.AddWithValue("track", track.Id);
                command.Parameters.AddWithValue("level", level + 1);
                await command.ExecuteNonQueryAsync(cancellationToken);
            }

            return new UpgradesState(await GarageUpgradeRows.LevelsAsync(db, owner, cancellationToken), balance);
        }, cancellationToken);
}

/// <summary>What the garage's upgrades give the player outside the garage: crafting, trade and experience.</summary>
public sealed class GarageBonuses(GameDb db) : IPlayerBonuses
{
    public async Task<int> PercentAsync(Guid player, string bonus, CancellationToken cancellationToken) =>
        GarageUpgrades.Tracks.Any(t => t.Bonus == bonus)
            ? GarageUpgrades.Bonus(await GarageUpgradeRows.LevelsAsync(db, player, cancellationToken), bonus)
            : 0;
}

public sealed record UpgradeRequest(string Track);

public abstract class UpgradesHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var state = await RunAsync(scope.ServiceProvider.GetRequiredService<GarageUpgradeService>(), client.RequireAccount(), payload, cancellationToken);
        var levels = state.Levels;
        return new Reply("garage.upgrades", new
        {
            rank = GarageUpgrades.Rank(levels),
            balanceCents = state.BalanceCents,
            tracks = GarageUpgrades.Tracks.Select(t => new
            {
                id = t.Id,
                name = t.Name,
                start = t.Start,
                level = levels.GetValueOrDefault(t.Id),
                maxLevel = t.MaxLevel,
                bonusName = t.BonusName,
                unit = t.Unit,
                perLevel = t.PerLevel,
                bonus = levels.GetValueOrDefault(t.Id) * t.PerLevel,
                steps = t.Steps.Select((s, i) => new
                {
                    level = i + 1,
                    name = s.Name,
                    priceCents = s.PriceCents,
                    materials = s.Materials.Select(m => new { id = m.Item, name = Items.Names[m.Item], quantity = m.Quantity }),
                    requires = s.Requires.Select(r => new { track = r.Track, name = GarageUpgrades.Find(r.Track)!.Name, level = r.Level }),
                }),
            }),
        });
    }

    protected abstract Task<UpgradesState> RunAsync(GarageUpgradeService upgrades, Guid owner, JsonElement? payload, CancellationToken cancellationToken);
}

/// <summary>Every track with its levels, what each costs, and how far the player's garage is.</summary>
public sealed class GetUpgradesHandler(IServiceScopeFactory scopes) : UpgradesHandler(scopes)
{
    public override string Type => "garage.upgrades";

    protected override Task<UpgradesState> RunAsync(GarageUpgradeService upgrades, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        upgrades.StateAsync(owner, cancellationToken);
}

public sealed class BuyUpgradeHandler(IServiceScopeFactory scopes) : UpgradesHandler(scopes)
{
    public override string Type => "garage.upgrade";

    protected override Task<UpgradesState> RunAsync(GarageUpgradeService upgrades, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        upgrades.BuyAsync(owner, Payload.Read<UpgradeRequest>(payload).Track, cancellationToken);
}
