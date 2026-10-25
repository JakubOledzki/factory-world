using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.World;

/// <summary>A bought plot. Plots nobody owns are not stored: their biome comes from the map.</summary>
public sealed class Plot
{
    public int X { get; set; }

    public int Y { get; set; }

    public Guid OwnerId { get; set; }

    public Biome Biome { get; set; }

    public long PriceCents { get; set; }

    public DateTimeOffset BoughtAt { get; set; }
}

/// <summary>A tile of a plot whose tree, rock or dune has been gathered.</summary>
public sealed class PlotHarvest
{
    public int X { get; set; }

    public int Y { get; set; }

    public int TileX { get; set; }

    public int TileY { get; set; }

    /// <summary>When it was gathered: on sand a dune dug before the last sandstorm has drifted back.</summary>
    public DateTimeOffset HarvestedAt { get; set; }
}

/// <summary>A tilled tile of a fertile plot, with what grows on it.</summary>
public sealed class PlotField
{
    public int X { get; set; }

    public int Y { get; set; }

    public int TileX { get; set; }

    public int TileY { get; set; }

    public string? Crop { get; set; }

    public DateTimeOffset? PlantedAt { get; set; }
}

/// <summary>A tree a player planted on a plot, growing until <see cref="ReadyAt"/>.</summary>
public sealed class PlotTree
{
    public int X { get; set; }

    public int Y { get; set; }

    public int TileX { get; set; }

    public int TileY { get; set; }

    public DateTimeOffset ReadyAt { get; set; }

    /// <summary>The forester's building that planted it, or null for a tree a player planted.</summary>
    public Guid? ForesterId { get; set; }

    /// <summary>The kind of tree, see <see cref="Trees"/>.</summary>
    public string Species { get; set; } = Trees.Pine;
}

/// <summary>An animal a player let out on a plot; fed, it gives its product at <see cref="ReadyAt"/>.</summary>
public sealed class PlotAnimalRow
{
    public int X { get; set; }

    public int Y { get; set; }

    public int TileX { get; set; }

    public int TileY { get; set; }

    public string Kind { get; set; } = "";

    public DateTimeOffset? ReadyAt { get; set; }
}

/// <summary>A mine of a plot that has been worked: loads taken since it was last full, and when it ran dry.</summary>
public sealed class PlotMine
{
    public int X { get; set; }

    public int Y { get; set; }

    public int Mine { get; set; }

    public int Used { get; set; }

    public DateTimeOffset? EmptyAt { get; set; }

    /// <summary>How far the owner has built the mine up: 1 to <see cref="Mining.Levels"/>.</summary>
    public int Level { get; set; } = 1;
}

/// <summary>Something a player put on a tile of their plot, e.g. a workbench or a furnace.</summary>
public sealed class PlotObjectRow
{
    public Guid Id { get; set; }

    public int X { get; set; }

    public int Y { get; set; }

    public int TileX { get; set; }

    public int TileY { get; set; }

    public Guid OwnerId { get; set; }

    public string Kind { get; set; } = "";

    /// <summary>Quarter turns anticlockwise seen from above; 0 faces south.</summary>
    public int Rotation { get; set; }
}

/// <summary>A forester's building on a plot: the wood it keeps and when it can start cutting the next tree.</summary>
public sealed class PlotForesterRow
{
    public Guid ObjectId { get; set; }

    public int X { get; set; }

    public int Y { get; set; }

    public Guid OwnerId { get; set; }

    public int Wood { get; set; }

    public DateTimeOffset BusyUntil { get; set; }
}

/// <summary>A well pumping oil or gas: what it holds, how far it is with its unit and the state of its seals.</summary>
public sealed class PlotWellRow
{
    public Guid ObjectId { get; set; }

    public int X { get; set; }

    public int Y { get; set; }

    public Guid OwnerId { get; set; }

    public string Kind { get; set; } = "";

    public int Stored { get; set; }

    public DateTimeOffset? StartedAt { get; set; }

    public int Wear { get; set; }

    public int Gaskets { get; set; }

    public bool Leaking { get; set; }
}

/// <summary>How much the wells of a plot have pumped from one of its deposits.</summary>
public sealed class OilFieldRow
{
    public int X { get; set; }

    public int Y { get; set; }

    public short Field { get; set; }

    public long Pumped { get; set; }
}

/// <summary>A drill standing at a mine: the mine it works, the ore it holds and how far it is with its load.</summary>
public sealed class PlotDrillRow
{
    public Guid ObjectId { get; set; }

    public int X { get; set; }

    public int Y { get; set; }

    public Guid OwnerId { get; set; }

    public int Mine { get; set; }

    /// <summary>Ore by item, as JSON.</summary>
    public string Ores { get; set; } = "{}";

    /// <summary>When, in the drill's own time on the power grid, its load started; null while it stands idle.</summary>
    public DateTimeOffset? StartedAt { get; set; }

    /// <summary>Whether it waits for its dry mine to fill up again.</summary>
    public bool Waiting { get; set; }
}

/// <summary>What a geological survey found under a plot.</summary>
public sealed class SurveyRow
{
    public int X { get; set; }

    public int Y { get; set; }

    public short Oil { get; set; }

    public short Gas { get; set; }

    public DateTimeOffset SurveyedAt { get; set; }
}

/// <summary>Goods waiting in a plot's railway station.</summary>
public sealed class StationItem
{
    public int X { get; set; }

    public int Y { get; set; }

    public required string Item { get; set; }

    public long Quantity { get; set; }
}

/// <summary>A train on its way from one plot's station to another's.</summary>
public sealed class ShipmentRow
{
    public long Id { get; set; }

    public int FromX { get; set; }

    public int FromY { get; set; }

    public int ToX { get; set; }

    public int ToY { get; set; }

    public required string Item { get; set; }

    public long Quantity { get; set; }

    public Guid SenderId { get; set; }

    public DateTimeOffset ArrivesAt { get; set; }
}

/// <summary>A train that leaves one plot's station for another's by itself, every few minutes.</summary>
public sealed class TrainRouteRow
{
    public long Id { get; set; }

    public Guid OwnerId { get; set; }

    public int FromX { get; set; }

    public int FromY { get; set; }

    public int ToX { get; set; }

    public int ToY { get; set; }

    /// <summary>The items it takes; empty for everything in the station.</summary>
    public string[] Items { get; set; } = [];

    public int EveryMinutes { get; set; }

    public DateTimeOffset NextDepartureAt { get; set; }

    public DateTimeOffset? LastDepartedAt { get; set; }

    public long LastQuantity { get; set; }

    public string? LastProblem { get; set; }
}

public sealed class WorldDbContext(DbContextOptions<WorldDbContext> options, GameDb gameDb) : ModuleDbContext(options, gameDb)
{
    public const string Schema = "world";

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.HasDefaultSchema(Schema);
        model.Entity<Plot>(e =>
        {
            e.ToTable("plots");
            // One row per plot, so two players can never both buy the same one.
            e.HasKey(p => new { p.X, p.Y });
            e.Property(p => p.X).HasColumnName("x");
            e.Property(p => p.Y).HasColumnName("y");
            e.Property(p => p.OwnerId).HasColumnName("owner_id");
            e.Property(p => p.Biome).HasColumnName("biome");
            e.Property(p => p.PriceCents).HasColumnName("price_cents");
            e.Property(p => p.BoughtAt).HasColumnName("bought_at");
            e.HasIndex(p => p.OwnerId);
        });
        model.Entity<PlotHarvest>(e =>
        {
            e.ToTable("plot_harvests");
            e.HasKey(h => new { h.X, h.Y, h.TileX, h.TileY });
            e.Property(h => h.X).HasColumnName("x");
            e.Property(h => h.Y).HasColumnName("y");
            e.Property(h => h.TileX).HasColumnName("tile_x");
            e.Property(h => h.TileY).HasColumnName("tile_y");
            e.Property(h => h.HarvestedAt).HasColumnName("harvested_at").HasDefaultValueSql("now()");
        });
        model.Entity<PlotField>(e =>
        {
            e.ToTable("plot_fields");
            e.HasKey(f => new { f.X, f.Y, f.TileX, f.TileY });
            e.Property(f => f.X).HasColumnName("x");
            e.Property(f => f.Y).HasColumnName("y");
            e.Property(f => f.TileX).HasColumnName("tile_x");
            e.Property(f => f.TileY).HasColumnName("tile_y");
            e.Property(f => f.Crop).HasColumnName("crop").HasMaxLength(32);
            e.Property(f => f.PlantedAt).HasColumnName("planted_at");
        });
        model.Entity<PlotTree>(e =>
        {
            e.ToTable("plot_trees");
            e.HasKey(t => new { t.X, t.Y, t.TileX, t.TileY });
            e.Property(t => t.X).HasColumnName("x");
            e.Property(t => t.Y).HasColumnName("y");
            e.Property(t => t.TileX).HasColumnName("tile_x");
            e.Property(t => t.TileY).HasColumnName("tile_y");
            e.Property(t => t.ReadyAt).HasColumnName("ready_at");
            e.Property(t => t.ForesterId).HasColumnName("forester_id");
            e.Property(t => t.Species).HasColumnName("species").HasMaxLength(16).HasDefaultValue(Trees.Pine);
            e.HasIndex(t => t.ForesterId);
        });
        model.Entity<PlotAnimalRow>(e =>
        {
            e.ToTable("plot_animals");
            e.HasKey(a => new { a.X, a.Y, a.TileX, a.TileY });
            e.Property(a => a.X).HasColumnName("x");
            e.Property(a => a.Y).HasColumnName("y");
            e.Property(a => a.TileX).HasColumnName("tile_x");
            e.Property(a => a.TileY).HasColumnName("tile_y");
            e.Property(a => a.Kind).HasColumnName("kind").HasMaxLength(32);
            e.Property(a => a.ReadyAt).HasColumnName("ready_at");
        });
        model.Entity<PlotMine>(e =>
        {
            e.ToTable("plot_mines");
            e.HasKey(m => new { m.X, m.Y, m.Mine });
            e.Property(m => m.X).HasColumnName("x");
            e.Property(m => m.Y).HasColumnName("y");
            e.Property(m => m.Mine).HasColumnName("mine");
            e.Property(m => m.Used).HasColumnName("used");
            e.Property(m => m.EmptyAt).HasColumnName("empty_at");
            e.Property(m => m.Level).HasColumnName("level").HasDefaultValue(1);
        });
        model.Entity<PlotObjectRow>(e =>
        {
            e.ToTable("plot_objects");
            e.HasKey(o => o.Id);
            e.Property(o => o.Id).HasColumnName("id");
            e.Property(o => o.X).HasColumnName("x");
            e.Property(o => o.Y).HasColumnName("y");
            e.Property(o => o.TileX).HasColumnName("tile_x");
            e.Property(o => o.TileY).HasColumnName("tile_y");
            e.Property(o => o.OwnerId).HasColumnName("owner_id");
            e.Property(o => o.Kind).HasColumnName("kind").HasMaxLength(32);
            e.Property(o => o.Rotation).HasColumnName("rotation");
            // One object per tile.
            e.HasIndex(o => new { o.X, o.Y, o.TileX, o.TileY }).IsUnique();
        });
        model.Entity<PlotForesterRow>(e =>
        {
            e.ToTable("plot_foresters");
            e.HasKey(f => f.ObjectId);
            e.Property(f => f.ObjectId).HasColumnName("object_id");
            e.Property(f => f.X).HasColumnName("x");
            e.Property(f => f.Y).HasColumnName("y");
            e.Property(f => f.OwnerId).HasColumnName("owner_id");
            e.Property(f => f.Wood).HasColumnName("wood");
            e.Property(f => f.BusyUntil).HasColumnName("busy_until");
            e.HasIndex(f => new { f.X, f.Y });
            e.HasIndex(f => f.OwnerId);
        });

        model.Entity<PlotDrillRow>(e =>
        {
            e.ToTable("plot_drills");
            e.HasKey(d => d.ObjectId);
            e.Property(d => d.ObjectId).HasColumnName("object_id");
            e.Property(d => d.X).HasColumnName("x");
            e.Property(d => d.Y).HasColumnName("y");
            e.Property(d => d.OwnerId).HasColumnName("owner_id");
            e.Property(d => d.Mine).HasColumnName("mine");
            e.Property(d => d.Ores).HasColumnName("ores").HasColumnType("jsonb");
            e.Property(d => d.StartedAt).HasColumnName("started_at");
            e.Property(d => d.Waiting).HasColumnName("waiting");
            e.HasIndex(d => new { d.X, d.Y });
            e.HasIndex(d => d.OwnerId);
        });

        model.Entity<PlotWellRow>(e =>
        {
            e.ToTable("plot_wells");
            e.HasKey(w => w.ObjectId);
            e.Property(w => w.ObjectId).HasColumnName("object_id");
            e.Property(w => w.X).HasColumnName("x");
            e.Property(w => w.Y).HasColumnName("y");
            e.Property(w => w.OwnerId).HasColumnName("owner_id");
            e.Property(w => w.Kind).HasColumnName("kind");
            e.Property(w => w.Stored).HasColumnName("stored");
            e.Property(w => w.StartedAt).HasColumnName("started_at");
            e.Property(w => w.Wear).HasColumnName("wear");
            e.Property(w => w.Gaskets).HasColumnName("gaskets");
            e.Property(w => w.Leaking).HasColumnName("leaking");
            e.HasIndex(w => new { w.X, w.Y });
            e.HasIndex(w => w.OwnerId);
        });

        model.Entity<OilFieldRow>(e =>
        {
            e.ToTable("oil_fields");
            e.HasKey(f => new { f.X, f.Y, f.Field });
            e.Property(f => f.X).HasColumnName("x");
            e.Property(f => f.Y).HasColumnName("y");
            e.Property(f => f.Field).HasColumnName("field");
            e.Property(f => f.Pumped).HasColumnName("pumped");
        });

        model.Entity<BeachFind>(e =>
        {
            e.ToTable("beach_finds");
            e.HasKey(f => new { f.X, f.Y, f.Day, f.TileX, f.TileY });
            e.Property(f => f.X).HasColumnName("x");
            e.Property(f => f.Y).HasColumnName("y");
            e.Property(f => f.Day).HasColumnName("day");
            e.Property(f => f.TileX).HasColumnName("tile_x");
            e.Property(f => f.TileY).HasColumnName("tile_y");
        });

        model.Entity<SurveyRow>(e =>
        {
            e.ToTable("surveys");
            e.HasKey(s => new { s.X, s.Y });
            e.Property(s => s.X).HasColumnName("x");
            e.Property(s => s.Y).HasColumnName("y");
            e.Property(s => s.Oil).HasColumnName("oil");
            e.Property(s => s.Gas).HasColumnName("gas");
            e.Property(s => s.SurveyedAt).HasColumnName("surveyed_at");
        });
        model.Entity<StationItem>(e =>
        {
            e.ToTable("station_items");
            e.HasKey(i => new { i.X, i.Y, i.Item });
            e.Property(i => i.X).HasColumnName("x");
            e.Property(i => i.Y).HasColumnName("y");
            e.Property(i => i.Item).HasColumnName("item").HasMaxLength(32);
            e.Property(i => i.Quantity).HasColumnName("quantity");
        });
        model.Entity<ShipmentRow>(e =>
        {
            e.ToTable("shipments");
            e.Property(s => s.Id).HasColumnName("id");
            e.Property(s => s.FromX).HasColumnName("from_x");
            e.Property(s => s.FromY).HasColumnName("from_y");
            e.Property(s => s.ToX).HasColumnName("to_x");
            e.Property(s => s.ToY).HasColumnName("to_y");
            e.Property(s => s.Item).HasColumnName("item").HasMaxLength(32);
            e.Property(s => s.Quantity).HasColumnName("quantity");
            e.Property(s => s.SenderId).HasColumnName("sender_id");
            e.Property(s => s.ArrivesAt).HasColumnName("arrives_at");
            e.HasIndex(s => new { s.ToX, s.ToY, s.ArrivesAt });
            e.HasIndex(s => new { s.FromX, s.FromY });
        });
        model.Entity<TrainRouteRow>(e =>
        {
            e.ToTable("train_routes");
            e.Property(r => r.Id).HasColumnName("id");
            e.Property(r => r.OwnerId).HasColumnName("owner_id");
            e.Property(r => r.FromX).HasColumnName("from_x");
            e.Property(r => r.FromY).HasColumnName("from_y");
            e.Property(r => r.ToX).HasColumnName("to_x");
            e.Property(r => r.ToY).HasColumnName("to_y");
            e.Property(r => r.Items).HasColumnName("items");
            e.Property(r => r.EveryMinutes).HasColumnName("every_minutes");
            e.Property(r => r.NextDepartureAt).HasColumnName("next_departure_at");
            e.Property(r => r.LastDepartedAt).HasColumnName("last_departed_at");
            e.Property(r => r.LastQuantity).HasColumnName("last_quantity");
            e.Property(r => r.LastProblem).HasColumnName("last_problem").HasMaxLength(32);
            e.HasIndex(r => r.NextDepartureAt);
            e.HasIndex(r => new { r.FromX, r.FromY });
            e.HasIndex(r => new { r.ToX, r.ToY });
        });
        model.Entity<TownProgressRow>(e =>
        {
            e.ToTable("town_progress");
            e.HasKey(t => new { t.TownX, t.TownY });
            e.Property(t => t.TownX).HasColumnName("town_x");
            e.Property(t => t.TownY).HasColumnName("town_y");
            e.Property(t => t.DeliveredCents).HasColumnName("delivered_cents");
        });
        model.Entity<TownContributionRow>(e =>
        {
            e.ToTable("town_contributions");
            e.HasKey(t => new { t.TownX, t.TownY, t.PlayerId });
            e.Property(t => t.TownX).HasColumnName("town_x");
            e.Property(t => t.TownY).HasColumnName("town_y");
            e.Property(t => t.PlayerId).HasColumnName("player_id");
            e.Property(t => t.DeliveredCents).HasColumnName("delivered_cents");
        });
        model.Entity<TownDeliveryRow>(e =>
        {
            e.ToTable("town_deliveries");
            e.HasKey(t => new { t.TownX, t.TownY, t.Day, t.Item });
            e.Property(t => t.TownX).HasColumnName("town_x");
            e.Property(t => t.TownY).HasColumnName("town_y");
            e.Property(t => t.Day).HasColumnName("day");
            e.Property(t => t.Item).HasColumnName("item").HasMaxLength(64);
            e.Property(t => t.Quantity).HasColumnName("quantity");
        });
        model.Entity<ShopRow>(e =>
        {
            e.ToTable("shops");
            e.HasKey(s => s.Id);
            e.Property(s => s.Id).HasColumnName("id");
            e.Property(s => s.SettledAt).HasColumnName("settled_at");
            e.Property(s => s.Carry).HasColumnName("carry");
            e.Property(s => s.SoldCents).HasColumnName("sold_cents");
            e.Property(s => s.SoldItems).HasColumnName("sold_items");
        });
        model.Entity<ShopItemRow>(e =>
        {
            e.ToTable("shop_items");
            e.HasKey(s => new { s.ShopId, s.Item });
            e.Property(s => s.ShopId).HasColumnName("shop_id");
            e.Property(s => s.Item).HasColumnName("item").HasMaxLength(64);
            e.Property(s => s.Quantity).HasColumnName("quantity");
            e.Property(s => s.PriceCents).HasColumnName("price_cents");
        });
        model.Entity<ServiceSaleRow>(e =>
        {
            e.ToTable("service_sales");
            e.HasKey(s => new { s.Id, s.Day });
            e.Property(s => s.Id).HasColumnName("id");
            e.Property(s => s.Day).HasColumnName("day");
            e.Property(s => s.Count).HasColumnName("count");
        });
        model.Entity<TownVoteRow>(e =>
        {
            e.ToTable("town_votes");
            e.HasKey(v => new { v.TownX, v.TownY, v.Week, v.VoterId });
            e.Property(v => v.TownX).HasColumnName("town_x");
            e.Property(v => v.TownY).HasColumnName("town_y");
            e.Property(v => v.Week).HasColumnName("week");
            e.Property(v => v.VoterId).HasColumnName("voter_id");
            e.Property(v => v.CandidateId).HasColumnName("candidate_id");
        });
        model.Entity<TownPolicyRow>(e =>
        {
            e.ToTable("town_policies");
            e.HasKey(p => new { p.TownX, p.TownY, p.Week });
            e.Property(p => p.TownX).HasColumnName("town_x");
            e.Property(p => p.TownY).HasColumnName("town_y");
            e.Property(p => p.Week).HasColumnName("week");
            e.Property(p => p.MayorId).HasColumnName("mayor_id");
            e.Property(p => p.TaxPercent).HasColumnName("tax_percent");
            e.Property(p => p.Bonus).HasColumnName("bonus").HasMaxLength(16);
        });
        model.Entity<PlotFireRow>(e =>
        {
            e.ToTable("plot_fires");
            e.HasKey(f => new { f.X, f.Y });
            e.Property(f => f.X).HasColumnName("x");
            e.Property(f => f.Y).HasColumnName("y");
            e.Property(f => f.CheckedAt).HasColumnName("checked_at");
            e.Property(f => f.LastAt).HasColumnName("last_at");
            e.Property(f => f.LastX).HasColumnName("last_x");
            e.Property(f => f.LastY).HasColumnName("last_y");
            e.Property(f => f.LastBurnt).HasColumnName("last_burnt");
            e.Property(f => f.LastStopped).HasColumnName("last_stopped");
        });
        model.Entity<PlotSprayRow>(e =>
        {
            e.ToTable("plot_sprays");
            e.HasKey(s => new { s.X, s.Y });
            e.Property(s => s.X).HasColumnName("x");
            e.Property(s => s.Y).HasColumnName("y");
            e.Property(s => s.Until).HasColumnName("until");
        });
        model.Entity<HiveRow>(e =>
        {
            e.ToTable("hives");
            e.HasKey(h => h.ObjectId);
            e.Property(h => h.ObjectId).HasColumnName("object_id");
            e.Property(h => h.X).HasColumnName("x");
            e.Property(h => h.Y).HasColumnName("y");
            e.Property(h => h.OwnerId).HasColumnName("owner_id");
            e.Property(h => h.Honey).HasColumnName("honey");
            e.Property(h => h.Wax).HasColumnName("wax");
            e.Property(h => h.Made).HasColumnName("made");
            e.Property(h => h.Progress).HasColumnName("progress");
            e.Property(h => h.At).HasColumnName("at");
        });
        model.Entity<ForestLedgerRow>(e =>
        {
            e.ToTable("forest_ledger");
            e.HasKey(l => new { l.PlayerId, l.Day });
            e.Property(l => l.PlayerId).HasColumnName("player_id");
            e.Property(l => l.Day).HasColumnName("day");
            e.Property(l => l.Planted).HasColumnName("planted");
            e.Property(l => l.Cut).HasColumnName("cut");
        });
    }
}

public sealed record PlotOwner(Guid AccountId, string? Name);

/// <param name="PriceCents">What the asking player would pay for it now; null when it cannot be bought.</param>
/// <param name="Survey">What lies under the plot, shown only to its owner once they paid for a survey.</param>
/// <param name="Company">The company its owner brought it into, if any.</param>
/// <param name="CanEnter">Whether the asking player may go onto it: its owner or a member of its company.</param>
public sealed record PlotState(
    int X, int Y, Biome Biome, PlotOwner? Owner, long? PriceCents, Survey? Survey = null, PlotCompany? Company = null, bool CanEnter = false);

/// <param name="Tool">The tool that came with the plot, or null.</param>
public sealed record Purchase(PlotState Plot, long BalanceCents, XpGain Xp, string? Tool);

public sealed class WorldService(
    GameDb db, WorldMap map, IWallet wallet, ICharacterProgress progress, ICharacterNames names, IEquipment equipment, SurveyService surveys,
    IEnumerable<ICompanyPlots> companies, CityService cities, TimeProvider time)
{
    /// <summary>Most owned plots one area request returns.</summary>
    public const int MaxAreaPlots = 5000;

    public async Task<long> CountOwnedAsync(Guid owner, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync("SELECT count(*) FROM world.plots WHERE owner_id = @owner", cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        return (long)(await command.ExecuteScalarAsync(cancellationToken))!;
    }

    public async Task<IReadOnlyList<(int X, int Y, Biome Biome)>> OwnedAsync(Guid owner, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT x, y, biome FROM world.plots WHERE owner_id = @owner ORDER BY bought_at", cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var plots = new List<(int, int, Biome)>();
        while (await reader.ReadAsync(cancellationToken))
        {
            plots.Add((reader.GetInt32(0), reader.GetInt32(1), (Biome)reader.GetInt16(2)));
        }

        return plots;
    }

    /// <summary>Owned plots inside a rectangle of the grid, with whose they are.</summary>
    /// <summary>Plots other members brought into the player's company.</summary>
    public async Task<IReadOnlyList<(int X, int Y, Biome Biome)>> SharedAsync(Guid player, CancellationToken cancellationToken)
    {
        var plots = new List<(int, int, Biome)>();
        foreach (var registry in companies)
        {
            plots.AddRange((await registry.SharedWithAsync(player, cancellationToken)).Select(p => (p.X, p.Y, map.BiomeAt(p.X, p.Y))));
        }

        return plots;
    }

    public async Task<IReadOnlyList<(int X, int Y, Guid Owner)>> AreaAsync(int x, int y, int width, int height, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """
            SELECT x, y, owner_id FROM world.plots
            WHERE x >= @x AND x < @x + @width AND y >= @y AND y < @y + @height
            LIMIT @limit
            """, cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        command.Parameters.AddWithValue("width", width);
        command.Parameters.AddWithValue("height", height);
        command.Parameters.AddWithValue("limit", MaxAreaPlots);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var plots = new List<(int, int, Guid)>();
        while (await reader.ReadAsync(cancellationToken))
        {
            plots.Add((reader.GetInt32(0), reader.GetInt32(1), reader.GetGuid(2)));
        }

        return plots;
    }

    public async Task<PlotState> PlotAsync(Guid viewer, int x, int y, CancellationToken cancellationToken)
    {
        var biome = BiomeAt(x, y);
        await using var command = await db.CommandAsync("SELECT owner_id FROM world.plots WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        if (await command.ExecuteScalarAsync(cancellationToken) is Guid owner)
        {
            var name = (await names.NamesAsync([owner], cancellationToken)).GetValueOrDefault(owner);
            // Deposits stay secret from everyone but the owner who paid for the survey.
            var survey = owner == viewer ? await surveys.FindAsync(x, y, cancellationToken) : null;
            PlotCompany? company = null;
            foreach (var registry in companies)
            {
                company ??= await registry.CompanyAsync(viewer, x, y, cancellationToken);
            }

            return new PlotState(x, y, biome, new PlotOwner(owner, name), null, survey, company, owner == viewer || company?.Member == true);
        }

        long? price = Biomes.All[biome].Buyable
            ? (long)Math.Round(PlotPrices.For(await CountOwnedAsync(viewer, cancellationToken), biome) * await cities.PlotPriceFactorAsync(x, y, cancellationToken))
            : null;
        return new PlotState(x, y, biome, null, price);
    }

    /// <summary>Buys a free plot: money out, plot in, both or neither. The price depends on how many plots the player has.</summary>
    public Task<Purchase> BuyAsync(Guid owner, int x, int y, CancellationToken cancellationToken)
    {
        var biome = BiomeAt(x, y);
        if (!Biomes.All[biome].Buyable)
        {
            throw new GameException("not_buyable", "Water cannot be bought.");
        }

        return db.InTransactionAsync(async () =>
        {
            // One purchase at a time per player, so two at once cannot both pay the lower price.
            await using (var lockOwner = await db.CommandAsync("SELECT pg_advisory_xact_lock(@key)", cancellationToken))
            {
                lockOwner.Parameters.AddWithValue("key", BitConverter.ToInt64(owner.ToByteArray()));
                await lockOwner.ExecuteNonQueryAsync(cancellationToken);
            }

            var price = (long)Math.Round(PlotPrices.For(await CountOwnedAsync(owner, cancellationToken), biome) * await cities.PlotPriceFactorAsync(x, y, cancellationToken));
            await using (var insert = await db.CommandAsync(
                """
                INSERT INTO world.plots (x, y, owner_id, biome, price_cents, bought_at)
                VALUES (@x, @y, @owner, @biome, @price, @at)
                ON CONFLICT DO NOTHING
                """, cancellationToken))
            {
                insert.Parameters.AddWithValue("x", x);
                insert.Parameters.AddWithValue("y", y);
                insert.Parameters.AddWithValue("owner", owner);
                insert.Parameters.AddWithValue("biome", (short)biome);
                insert.Parameters.AddWithValue("price", price);
                insert.Parameters.AddWithValue("at", time.GetUtcNow());
                if (await insert.ExecuteNonQueryAsync(cancellationToken) == 0)
                {
                    throw new GameException("plot_taken", "Someone already owns this plot.");
                }
            }

            var balance = await wallet.DebitAsync(owner, price, $"plot {x}:{y}", cancellationToken);
            var xp = await progress.AddXpAsync(owner, PlotRules.XpPerPlot, cancellationToken);
            // A forest comes with an axe, a desert with a shovel, mountains with a pickaxe, the steppe with shears.
            var tool = PlotLayout.StarterTool(biome);
            if (tool is not null)
            {
                await equipment.GiveToolAsync(owner, tool, cancellationToken);
            }

            var name = (await names.NamesAsync([owner], cancellationToken)).GetValueOrDefault(owner);
            return new Purchase(new PlotState(x, y, biome, new PlotOwner(owner, name), null, CanEnter: true), balance, xp, tool);
        }, cancellationToken);
    }

    private Biome BiomeAt(int x, int y) =>
        map.Contains(x, y) ? map.BiomeAt(x, y) : throw new GameException("bad_plot", "There is no such plot.");
}

/// <summary>Who owns a plot, for other modules (e.g. companies).</summary>
public sealed class PlotRegistry(GameDb db) : IPlotRegistry
{
    public async Task<OwnedPlot?> FindAsync(int x, int y, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync("SELECT owner_id, biome FROM world.plots WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken) ? new OwnedPlot(x, y, reader.GetGuid(0), reader.GetInt16(1)) : null;
    }
}

public sealed record PlotRequest(int X, int Y);

public sealed record AreaRequest(int X, int Y, int Width, int Height);

public abstract class WorldHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        return await RunAsync(scope.ServiceProvider.GetRequiredService<WorldService>(), client.RequireAccount(), payload, cancellationToken);
    }

    protected abstract Task<Reply> RunAsync(WorldService world, Guid player, JsonElement? payload, CancellationToken cancellationToken);

    protected static object PlotJson(PlotState plot, Guid player) => new
    {
        x = plot.X,
        y = plot.Y,
        biome = (int)plot.Biome,
        owner = plot.Owner is { } owner ? new { name = owner.Name, mine = owner.AccountId == player } : null,
        priceCents = plot.PriceCents,
        survey = plot.Survey is { } survey ? SurveyHandler.SurveyJson(survey) : null,
        surveyPriceCents = plot.Owner?.AccountId == player ? Deposits.SurveyPriceCents : (long?)null,
        company = plot.Company is { } company ? new { name = company.Name, member = company.Member } : null,
        canEnter = plot.CanEnter,
    };
}

/// <summary>The map's size, the biomes, the price list and the player's own plots.</summary>
public sealed class InfoHandler(IServiceScopeFactory scopes, WorldMap map) : WorldHandler(scopes)
{
    public override string Type => "world.info";

    protected override async Task<Reply> RunAsync(WorldService world, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var mine = await world.OwnedAsync(player, cancellationToken);
        var shared = await world.SharedAsync(player, cancellationToken);
        return new Reply("world.info", new
        {
            width = map.Width,
            height = map.Height,
            plotKm = PlotRules.SideKm,
            biomes = Biomes.All.Values.Select(b => new
            {
                id = (int)b.Id,
                name = b.Name,
                buyable = b.Buyable,
                priceFactor = b.PriceFactor,
                bonuses = b.Bonuses.Select(bonus => new { text = bonus.Text, good = bonus.Good }),
            }),
            priceTiersCents = PlotPrices.TierCents,
            nextBasePriceCents = PlotPrices.Base(mine.Count),
            plots = mine.Select(p => new { x = p.X, y = p.Y, biome = (int)p.Biome }),
            sharedPlots = shared.Select(p => new { x = p.X, y = p.Y, biome = (int)p.Biome }),
        });
    }
}

/// <summary>Owned plots in a rectangle of the map, to draw them.</summary>
public sealed class AreaHandler(IServiceScopeFactory scopes) : WorldHandler(scopes)
{
    public override string Type => "world.area";

    protected override async Task<Reply> RunAsync(WorldService world, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<AreaRequest>(payload);
        if (request.Width is < 1 or > 10_000 || request.Height is < 1 or > 10_000)
        {
            throw new GameException("bad_area", "Ask for at most 10000 × 10000 plots.");
        }

        var plots = await world.AreaAsync(request.X, request.Y, request.Width, request.Height, cancellationToken);
        return new Reply("world.area", new
        {
            request.X,
            request.Y,
            request.Width,
            request.Height,
            plots = plots.Select(p => new { x = p.X, y = p.Y, mine = p.Owner == player }),
        });
    }
}

public sealed class GetPlotHandler(IServiceScopeFactory scopes) : WorldHandler(scopes)
{
    public override string Type => "world.plot";

    protected override async Task<Reply> RunAsync(WorldService world, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<PlotRequest>(payload);
        return new Reply("world.plot", PlotJson(await world.PlotAsync(player, request.X, request.Y, cancellationToken), player));
    }
}

public sealed class BuyPlotHandler(IServiceScopeFactory scopes) : WorldHandler(scopes)
{
    public override string Type => "world.buy";

    protected override async Task<Reply> RunAsync(WorldService world, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<PlotRequest>(payload);
        var purchase = await world.BuyAsync(player, request.X, request.Y, cancellationToken);
        return new Reply("world.bought", new
        {
            plot = PlotJson(purchase.Plot, player),
            balanceCents = purchase.BalanceCents,
            xp = new { xp = purchase.Xp.Xp, level = purchase.Xp.Level, leveledUp = purchase.Xp.LeveledUp },
            tool = purchase.Tool is { } tool ? new { id = tool, name = Items.Names[tool] } : null,
        });
    }
}

/// <summary>The map of the Earth in 5 × 5 km plots and who owns which. Owns the <c>world</c> schema.</summary>
public sealed class WorldModule : IGameModule
{
    public string Name => "World";

    public void RegisterServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddModuleDbContext<WorldDbContext>(WorldDbContext.Schema);
        services.AddSingleton(_ => WorldMap.Load());
        services.AddScoped<WorldService>();
        services.AddScoped<PlotService>();
        services.AddScoped<BeachService>();
        services.AddScoped<StationService>();
        services.AddScoped<FarmService>();
        services.AddScoped<ForestService>();
        services.AddScoped<ForestLedger>();
        services.AddScoped<IForestCertificate>(provider => provider.GetRequiredService<ForestLedger>());
        services.AddScoped<IPlayerRanking, GreenestRanking>();
        services.AddScoped<PestService>();
        services.AddScoped<FireService>();
        services.AddScoped<BeeService>();
        services.AddScoped<IPlacedHook>(provider => provider.GetRequiredService<BeeService>());
        services.AddScoped<IMachineContents>(provider => provider.GetRequiredService<BeeService>());
        services.AddSingleton<IMessageHandler, GetHiveHandler>();
        services.AddSingleton<IMessageHandler, TakeFromHiveHandler>();
        services.AddSingleton<IMessageHandler, SprayHandler>();
        services.AddScoped<HusbandryService>();
        services.AddScoped<MineService>();
        services.AddScoped<SurveyService>();
        services.AddScoped<PlotObjectService>();
        services.AddScoped<IPlacedObjects>(provider => provider.GetRequiredService<PlotObjectService>());
        services.AddScoped<IPlotObjects, PlotObjectsQuery>();
        services.AddScoped<IPlotRegistry, PlotRegistry>();
        services.AddSingleton<IMessageHandler, InfoHandler>();
        services.AddSingleton<IMessageHandler, AreaHandler>();
        services.AddSingleton<IMessageHandler, GetPlotHandler>();
        services.AddSingleton<IMessageHandler, BuyPlotHandler>();
        services.AddSingleton<IMessageHandler, EnterPlotHandler>();
        services.AddSingleton<IMessageHandler, HarvestHandler>();
        services.AddSingleton<IMessageHandler, GetStationHandler>();
        services.AddSingleton<IMessageHandler, LoadStationHandler>();
        services.AddSingleton<IMessageHandler, UnloadStationHandler>();
        services.AddSingleton<IMessageHandler, SendHandler>();
        services.AddSingleton<IMessageHandler, AddRouteHandler>();
        services.AddSingleton<IMessageHandler, RemoveRouteHandler>();
        services.AddSingleton<IMessageHandler, FindPartnersHandler>();
        services.AddScoped<IMachinePorts, StationPorts>();
        services.AddScoped<ForesterService>();
        services.AddScoped<IPlacedHook>(provider => provider.GetRequiredService<ForesterService>());
        services.AddScoped<IPlotAutomation>(provider => provider.GetRequiredService<ForesterService>());
        services.AddScoped<IMachineContents>(provider => provider.GetRequiredService<ForesterService>());
        services.AddScoped<IMachinePorts>(provider => provider.GetRequiredService<ForesterService>());
        services.AddScoped<IMachineStatuses>(provider => provider.GetRequiredService<ForesterService>());
        services.AddScoped<OilService>();
        services.AddScoped<IPlacedHook>(provider => provider.GetRequiredService<OilService>());
        services.AddScoped<IPlotAutomation>(provider => provider.GetRequiredService<OilService>());
        services.AddScoped<IMachineContents>(provider => provider.GetRequiredService<OilService>());
        services.AddScoped<IMachinePorts>(provider => provider.GetRequiredService<OilService>());
        services.AddScoped<IMachineStatuses>(provider => provider.GetRequiredService<OilService>());
        services.AddSingleton<IMessageHandler, GetWellHandler>();
        services.AddSingleton<IMessageHandler, TakeFromWellHandler>();
        services.AddSingleton<IMessageHandler, SealWellHandler>();
        services.AddScoped<DrillService>();
        services.AddScoped<IPlacedHook>(provider => provider.GetRequiredService<DrillService>());
        services.AddScoped<IPlotAutomation>(provider => provider.GetRequiredService<DrillService>());
        services.AddScoped<IMachineContents>(provider => provider.GetRequiredService<DrillService>());
        services.AddScoped<IMachinePorts>(provider => provider.GetRequiredService<DrillService>());
        services.AddScoped<IMachineStatuses>(provider => provider.GetRequiredService<DrillService>());
        services.AddSingleton<IMessageHandler, GetDrillHandler>();
        services.AddSingleton<IMessageHandler, TakeFromDrillHandler>();
        services.AddSingleton<IMessageHandler, GetForestryHandler>();
        services.AddSingleton<IMessageHandler, TakeFromForesterHandler>();
        services.AddHostedService<RailwayDispatcher>();
        services.AddSingleton<IMessageHandler, TillHandler>();
        services.AddSingleton<IMessageHandler, PlantHandler>();
        services.AddSingleton<IMessageHandler, ReapHandler>();
        services.AddSingleton<IMessageHandler, PlantTreeHandler>();
        services.AddSingleton<IMessageHandler, ReleaseAnimalHandler>();
        services.AddSingleton<IMessageHandler, FeedAnimalHandler>();
        services.AddSingleton<IMessageHandler, CollectAnimalHandler>();
        services.AddSingleton<IMessageHandler, TakeAnimalHandler>();
        services.AddSingleton<IMessageHandler, MineHandler>();
        services.AddSingleton<IMessageHandler, UpgradeMineHandler>();
        services.AddSingleton<IMessageHandler, BlastMineHandler>();
        services.AddSingleton<IMessageHandler, SurveyHandler>();
        services.AddSingleton<IMessageHandler, PlaceOnPlotHandler>();
        services.AddSingleton<IMessageHandler, PickUpFromPlotHandler>();
        services.AddSingleton<IMessageHandler, RotateOnPlotHandler>();
        services.AddSingleton(_ => Towns.Load());
        services.AddScoped<CityService>();
        services.AddScoped<IMachineContents>(provider => provider.GetRequiredService<CityService>());
        services.AddSingleton<IMessageHandler, GetCityHandler>();
        services.AddSingleton<IMessageHandler, DeliverToCityHandler>();
        services.AddSingleton<IMessageHandler, CityTrashHandler>();
        services.AddSingleton<IMessageHandler, CityServiceHandler>();
        services.AddSingleton<IMessageHandler, CityVoteHandler>();
        services.AddSingleton<IMessageHandler, CityPolicyHandler>();
        services.AddSingleton<IMessageHandler, GetShopHandler>();
        services.AddSingleton<IMessageHandler, StockShopHandler>();
        services.AddSingleton<IMessageHandler, TakeFromShopHandler>();
    }

    public async Task InitializeAsync(IServiceProvider services, CancellationToken cancellationToken)
    {
        await services.MigrateModuleAsync<WorldDbContext>(cancellationToken);
        // Load the map before the first player asks for it.
        services.GetRequiredService<WorldMap>();
    }
}
