using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.World;

/// <summary>
/// Things a player carries out of the inventory and puts on a free tile of their plot, e.g. a
/// workbench or an anvil to craft at far from the garage, a research table, a furnace, a machine that processes crops (mill, oil
/// press, pickling barrel, bakery, field kitchen), belts, inserters, chests, a generator and the
/// poles that carry its power, a computer to trade on the market from the plot, a forester's building
/// that grows and cuts a forest around itself, a sawmill, or the mountain industry: a drill at a mine,
/// a quarry, a crusher, a stonemason, a foundry, water power and cable car stations, or on the shore boats,
/// a smokehouse, a cannery, a salt pan, a fish farm, a shipyard, a port, a breakwater, a lighthouse and a tidal plant. Each stands on one tile (a forester's
/// building on 3 × 3, see <see cref="Footprints"/>), turned by quarter turns like furniture in the garage.
/// </summary>
public static class PlotObjects
{
    /// <summary>Items that can be put on a plot.</summary>
    public static readonly IReadOnlySet<string> Placeable = new HashSet<string>
    {
        Items.Workbench, Items.Anvil, Items.ResearchTable, Items.Furnace, Items.BrickFurnace, Items.BlastFurnace,
        Items.Mill, Items.OilPress, Items.PicklingBarrel, Items.Bakery, Items.Kitchen,
        Items.Belt, Items.FastBelt, Items.ExpressBelt, Items.Inserter, Items.FastInserter, Items.ExpressInserter, Items.Splitter,
        Items.WoodenChest, Items.IronChest, Items.WoodPile, Items.Heap, Items.GrainSilo,
        Items.Generator, Items.Pole,
        Items.Computer,
        Items.ForesterHut, Items.ForesterLodge, Items.ForestryStation,
        Items.Sawmill, Items.ElectricSawmill, Items.IndustrialSawmill,
        Items.Drill, Items.HeavyDrill, Items.Quarry, Items.Crusher, Items.Stonemason, Items.Foundry,
        Items.WaterWheel, Items.HydroPlant, Items.CableStation,
        Items.FishingBoat, Items.RowingBoat, Items.Smokehouse, Items.Cannery, Items.SaltPan, Items.FishFarm,
        Items.Shipyard, Items.Port, Items.Breakwater, Items.Lighthouse, Items.TidalPlant,
        Items.Pumpjack, Items.GasWell, Items.OffshorePlatform, Items.WaterInjector, Items.OilSeparator,
        Items.Distillery, Items.Refinery, Items.Cracker, Items.ChemicalPlant, Items.GasPlant, Items.DieselGenerator,
        Items.Pipe, Items.Pump, Items.Tank, Items.Road,
        Items.Glassworks, Items.ArcFurnace, Items.WaterWell, Items.Desalinator, Items.DryingYard, Items.CementKiln, Items.ConcreteMixer,
        Items.ReedFence, Items.SolarPanel, Items.SolarTower, Items.Battery,
        Items.WindTurbine, Items.LargeWindTurbine, Items.Heater, Items.IceMelter, Items.ColdStore, Items.ServerRoom,
        Items.IceCoreDrill, Items.PolarStation, Items.IceHotel, Items.Viewpoint, Items.DogKennel, Items.SnowmobileGarage, Items.TrackFoundation,
        Items.AssemblyHall, Items.MultistoreyFactory, Items.Shop, Items.HighBay, Items.CitySorter, Items.FreightTerminal, Items.CompanyHq,
        Items.DesignOffice, Items.Laboratory, Items.ServiceWorkshop, Items.Tailor,
        Items.PaperMill, Items.Carpentry, Items.CharcoalKiln, Items.TarKiln, Items.Beehive, Items.Watchtower, Items.FireStation,
        Items.MachineShop, Items.RoboticHall, Items.OxygenConverter, Items.RollingMill, Items.ControlCenter, Items.ContinuousCaster,
        Items.AutomatedWarehouse, Items.SteelCombine, Items.Megafactory, Items.FusionPlant,
    };

    /// <summary>What stands on the glacier only, or on the glacier and the tundra.</summary>
    private static readonly IReadOnlyDictionary<string, Biome[]> Polar = new Dictionary<string, Biome[]>
    {
        [Items.IceCoreDrill] = [Biome.Ice],
        [Items.TrackFoundation] = [Biome.Ice],
        [Items.IceHotel] = [Biome.Ice, Biome.Tundra],
        [Items.Viewpoint] = [Biome.Ice, Biome.Tundra],
        [Items.DogKennel] = [Biome.Ice, Biome.Tundra],
        [Items.SnowmobileGarage] = [Biome.Ice, Biome.Tundra],
    };

    /// <summary>Fails unless an object of <paramref name="kind"/> may stand on (tileX, tileY) of a plot of
    /// <paramref name="biome"/>: a drill next to a mine that has none yet, a quarry in the mountains, water
    /// power by a river, a lake or the sea.</summary>
    public static void RequireSite(string kind, int x, int y, Biome biome, int tileX, int tileY, IEnumerable<PlacedOnPlot> others)
    {
        if (Items.IsDrill(kind))
        {
            var mines = PlotLayout.Mines(x, y, biome);
            var mine = Drills.MineAt(mines, tileX, tileY) ?? throw new GameException("no_mine_here", "A drill stands right next to a mine.");
            if (others.Any(o => Items.IsDrill(o.Kind) && Drills.MineAt(mines, o.TileX, o.TileY)?.Id == mine.Id))
            {
                throw new GameException("mine_has_drill", "This mine has a drill already.");
            }
        }

        if (kind == Items.Quarry && biome != Biome.Mountains)
        {
            throw new GameException("no_quarry", "A quarry is cut into the mountains only.");
        }

        if (Items.IsHydro(kind) && kind != Items.TidalPlant && !WaterPower.Allowed((int)biome))
        {
            throw new GameException("no_water", "Water power needs a mountain stream, a lake or the sea.");
        }

        if (kind == Items.SolarTower && !Oasis.Sandy((int)biome))
        {
            throw new GameException("no_sand", "A solar tower with mirrors stands on a desert or in an oasis.");
        }

        if (Polar.TryGetValue(kind, out var polar) && !polar.Contains(biome))
        {
            throw polar.Length == 1
                ? new GameException("no_glacier", "It stands on the glacier only.")
                : new GameException("no_polar", "It stands on the glacier or the tundra only.");
        }

        if (kind == Items.TrackFoundation && others.Any(o => o.Kind == Items.TrackFoundation))
        {
            throw new GameException("has_foundation", "The track of this plot has its foundation already.");
        }

        if (Items.IsCityOnly(kind) && biome != Biome.City)
        {
            throw new GameException("no_city", "It stands in a city only.");
        }

        if (biome == Biome.City && !Footprints.Tiles(kind, tileX, tileY).All(t => CityRules.InBuildArea(t.X, t.Y)))
        {
            throw new GameException("city_cramped", "In a city only the ground by the station can be built on.");
        }

        if (kind is Items.FreightTerminal or Items.CompanyHq or Items.ControlCenter && others.Any(o => o.Kind == kind))
        {
            throw new GameException("has_one", "A plot has room for one of these.");
        }

        if (kind == Items.Beehive && !Bees.Fly(biome))
        {
            throw new GameException("no_bees", "No bees fly on the glacier or in the mountains.");
        }

        Coast.RequireSite(kind, x, y, biome, tileX, tileY);
    }
}

public sealed record PlacedOnPlot(Guid Id, string Kind, int TileX, int TileY, int Rotation = 0);

/// <summary>Told about every object put on a plot, in the same transaction, e.g. so a forester starts its work then.</summary>
public interface IPlacedHook
{
    Task PlacedAsync(Guid owner, int x, int y, PlacedOnPlot placed, CancellationToken cancellationToken);
}

public sealed class PlotObjectService(
    GameDb db, PlotService plots, IInventory inventory, IEnumerable<IMachineContents> machines, IEnumerable<IPlotAutomation> automation,
    IEnumerable<IPlacedHook> placing, BeachService beach, OilService oil, IEnumerable<ICompanyPlots> companies)
    : IPlacedObjects
{
    public async Task<IReadOnlyList<PlacedOnPlot>> ObjectsAsync(int x, int y, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT id, kind, tile_x, tile_y, rotation FROM world.plot_objects WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var objects = new List<PlacedOnPlot>();
        while (await reader.ReadAsync(cancellationToken))
        {
            objects.Add(new PlacedOnPlot(reader.GetGuid(0), reader.GetString(1), reader.GetInt32(2), reader.GetInt32(3), reader.GetInt32(4)));
        }

        return objects;
    }

    /// <summary>Puts an object from the inventory on a free tile of the player's plot, turned by <paramref name="rotation"/> quarter turns.</summary>
    public Task<PlacedOnPlot> PlaceAsync(Guid player, int x, int y, string kind, int tileX, int tileY, int rotation, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (!PlotObjects.Placeable.Contains(kind))
            {
                throw new GameException("not_placeable", "This item cannot be put on a plot.");
            }

            if (rotation is < 0 or > 3)
            {
                throw new GameException("bad_rotation", "Rotation is 0, 1, 2 or 3 quarter turns.");
            }

            var biome = await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            foreach (var (tx, ty) in Footprints.Tiles(kind, tileX, tileY))
            {
                if ((tx, ty) == PlotLayout.Spawn || !await plots.FreeAsync(player, x, y, tx, ty, cancellationToken))
                {
                    throw new GameException("blocked", Footprints.Reach(kind) > 0 ? $"It needs {Footprints.Size(kind)} × {Footprints.Size(kind)} free tiles." : "Something stands here.");
                }
            }

            if (Items.IsForester(kind) && Forestry.GrowTime(biome) is null)
            {
                throw new GameException("no_forestry", "No trees grow here.");
            }

            await CatchUpAsync(x, y, cancellationToken);
            PlotObjects.RequireSite(kind, x, y, biome, tileX, tileY, await ObjectsAsync(x, y, cancellationToken));
            if (Items.IsBoat(kind))
            {
                await beach.RequireRoomForBoatAsync(x, y, biome, cancellationToken);
            }

            await oil.RequireSiteAsync(kind, x, y, await ObjectsAsync(x, y, cancellationToken), cancellationToken);
            if (kind == Items.CompanyHq)
            {
                // A company's headquarters stands on a plot brought into the company.
                PlotCompany? company = null;
                foreach (var c in companies)
                {
                    company ??= await c.CompanyAsync(player, x, y, cancellationToken);
                }

                if (company is not { Member: true })
                {
                    throw new GameException("hq_off_company", "Headquarters stand on a plot of your company.");
                }
            }

            await inventory.RemoveAsync(player, kind, 1, cancellationToken);
            var placed = new PlacedOnPlot(Guid.NewGuid(), kind, tileX, tileY, rotation);
            await using var insert = await db.CommandAsync(
                """
                INSERT INTO world.plot_objects (id, x, y, tile_x, tile_y, owner_id, kind, rotation)
                VALUES (@id, @x, @y, @tx, @ty, @owner, @kind, @rotation)
                ON CONFLICT DO NOTHING
                """, cancellationToken);
            insert.Parameters.AddWithValue("id", placed.Id);
            insert.Parameters.AddWithValue("x", x);
            insert.Parameters.AddWithValue("y", y);
            insert.Parameters.AddWithValue("tx", tileX);
            insert.Parameters.AddWithValue("ty", tileY);
            insert.Parameters.AddWithValue("owner", player);
            insert.Parameters.AddWithValue("kind", kind);
            insert.Parameters.AddWithValue("rotation", rotation);
            if (await insert.ExecuteNonQueryAsync(cancellationToken) == 0)
            {
                throw new GameException("blocked", "Something stands here.");
            }

            foreach (var hook in placing)
            {
                await hook.PlacedAsync(player, x, y, placed, cancellationToken);
            }

            return placed;
        }, cancellationToken);

    /// <summary>Turns an object on the player's plot to face another way, e.g. a belt to carry elsewhere.</summary>
    public Task<PlacedOnPlot> RotateAsync(Guid player, int x, int y, Guid id, int rotation, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (rotation is < 0 or > 3)
            {
                throw new GameException("bad_rotation", "Rotation is 0, 1, 2 or 3 quarter turns.");
            }

            await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            await CatchUpAsync(x, y, cancellationToken);
            await using var update = await db.CommandAsync(
                """
                UPDATE world.plot_objects SET rotation = @rotation WHERE id = @id AND x = @x AND y = @y
                RETURNING kind, tile_x, tile_y
                """, cancellationToken);
            update.Parameters.AddWithValue("rotation", rotation);
            update.Parameters.AddWithValue("id", id);
            update.Parameters.AddWithValue("x", x);
            update.Parameters.AddWithValue("y", y);
            await using var reader = await update.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                throw new GameException("no_object", "There is no such object on this plot.");
            }

            return new PlacedOnPlot(id, reader.GetString(0), reader.GetInt32(1), reader.GetInt32(2), rotation);
        }, cancellationToken);

    /// <summary>Takes an object off the player's plot back into the inventory, with whatever it holds. On a
    /// company's plot a member who may build picks up what they put there; the plot's owner picks up anything.</summary>
    public Task PickUpAsync(Guid player, int x, int y, Guid id, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var owner = (await plots.RightsAsync(player, x, y, cancellationToken)).Contains(PlotRight.Owner);
            await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            (int X, int Y)? tile = null;
            await using (var find = await db.CommandAsync("SELECT tile_x, tile_y FROM world.plot_objects WHERE id = @id AND x = @x AND y = @y", cancellationToken))
            {
                find.Parameters.AddWithValue("id", id);
                find.Parameters.AddWithValue("x", x);
                find.Parameters.AddWithValue("y", y);
                await using var reader = await find.ExecuteReaderAsync(cancellationToken);
                if (await reader.ReadAsync(cancellationToken))
                {
                    tile = (reader.GetInt32(0), reader.GetInt32(1));
                }
            }

            if (tile is { } t)
            {
                await plots.RequireDugOutAsync(x, y, t.X, t.Y, cancellationToken);
            }

            await CatchUpAsync(x, y, cancellationToken);
            await using var delete = await db.CommandAsync(
                """
                DELETE FROM world.plot_objects WHERE id = @id AND x = @x AND y = @y AND (owner_id = @player OR @owner)
                RETURNING kind
                """, cancellationToken);
            delete.Parameters.AddWithValue("id", id);
            delete.Parameters.AddWithValue("x", x);
            delete.Parameters.AddWithValue("y", y);
            delete.Parameters.AddWithValue("player", player);
            delete.Parameters.AddWithValue("owner", owner);
            var kind = await delete.ExecuteScalarAsync(cancellationToken) as string
                ?? throw new GameException(owner ? "no_object" : "not_yours", "There is no such object of yours on this plot.");
            foreach (var machine in machines)
            {
                await machine.ReleaseAsync(player, id, cancellationToken);
            }

            await inventory.AddAsync(player, kind, 1, cancellationToken);
        }, cancellationToken);

    /// <summary>Any object on a plot the player may work on: their own, or one of their company's.</summary>
    public async Task<string?> KindAsync(Guid owner, Guid id, CancellationToken cancellationToken)
    {
        int x, y, tileX, tileY;
        string kind;
        await using (var command = await db.CommandAsync("SELECT x, y, kind, tile_x, tile_y FROM world.plot_objects WHERE id = @id", cancellationToken))
        {
            command.Parameters.AddWithValue("id", id);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return null;
            }

            (x, y, kind, tileX, tileY) = (reader.GetInt32(0), reader.GetInt32(1), reader.GetString(2), reader.GetInt32(3), reader.GetInt32(4));
        }

        if (!(await plots.RightsAsync(owner, x, y, cancellationToken)).Contains(PlotRight.Work))
        {
            return null;
        }

        // Snow from an avalanche buries a machine on the glacier until it is dug out.
        await plots.RequireDugOutAsync(x, y, tileX, tileY, cancellationToken);
        return kind;
    }

    private async Task CatchUpAsync(int x, int y, CancellationToken cancellationToken)
    {
        foreach (var machinery in automation)
        {
            await machinery.CatchUpAsync(x, y, cancellationToken);
        }
    }
}

/// <summary>The objects on plots for other modules; apart from <see cref="PlotObjectService"/>, which
/// brings the plot's machinery up to now first and so needs those modules itself.</summary>
public sealed class PlotObjectsQuery(GameDb db, PlotService plots) : IPlotObjects
{
    public async Task<IReadOnlyList<PlotObject>> ObjectsAsync(int x, int y, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT id, kind, tile_x, tile_y, rotation, owner_id FROM world.plot_objects WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var objects = new List<PlotObject>();
        while (await reader.ReadAsync(cancellationToken))
        {
            objects.Add(new PlotObject(reader.GetGuid(0), reader.GetString(1), reader.GetInt32(2), reader.GetInt32(3), reader.GetInt32(4), reader.GetGuid(5)));
        }

        return objects;
    }

    public async Task<IReadOnlyList<PlotObject>> FixturesAsync(int x, int y, CancellationToken cancellationToken)
    {
        if (await StationStock.OwnerAsync(db, x, y, cancellationToken) is not { } owner)
        {
            return [];
        }

        var station = RailRules.StationId(x, y);
        return RailRules.StationTiles().Select(t => new PlotObject(station, RailRules.StationKind, t.TileX, t.TileY, 0, owner)).ToList();
    }

    public Task RequireOwnerAsync(Guid player, int x, int y, CancellationToken cancellationToken, PlotRight right = PlotRight.Build) =>
        plots.RequireOwnerAsync(player, x, y, cancellationToken, right);

    public async Task<(int X, int Y)?> PlotOfAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync("SELECT x, y FROM world.plot_objects WHERE id = @id", cancellationToken);
        command.Parameters.AddWithValue("id", id);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken) ? (reader.GetInt32(0), reader.GetInt32(1)) : null;
    }
}

public sealed record PlaceOnPlotRequest(int X, int Y, string Kind, int TileX, int TileY, int Rotation = 0);

public sealed record RotateOnPlotRequest(int X, int Y, Guid Id, int Rotation);

public sealed record PickUpFromPlotRequest(int X, int Y, Guid Id);

public sealed class PlaceOnPlotHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "plot.place";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<PlaceOnPlotRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var placed = await scope.ServiceProvider.GetRequiredService<PlotObjectService>().PlaceAsync(
            client.RequireAccount(), request.X, request.Y, request.Kind ?? "", request.TileX, request.TileY, request.Rotation, cancellationToken);
        return new Reply("plot.placed", new { @object = ObjectJson(placed) });
    }

    public static object ObjectJson(PlacedOnPlot placed) => new
    {
        id = placed.Id,
        kind = placed.Kind,
        name = Items.Names[placed.Kind],
        tileX = placed.TileX,
        tileY = placed.TileY,
        rotation = placed.Rotation,
    };
}

public sealed class PickUpFromPlotHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "plot.pickup";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<PickUpFromPlotRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        await scope.ServiceProvider.GetRequiredService<PlotObjectService>()
            .PickUpAsync(client.RequireAccount(), request.X, request.Y, request.Id, cancellationToken);
        return new Reply("plot.pickedUp", new { id = request.Id });
    }
}

public sealed class RotateOnPlotHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "plot.rotate";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<RotateOnPlotRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var turned = await scope.ServiceProvider.GetRequiredService<PlotObjectService>()
            .RotateAsync(client.RequireAccount(), request.X, request.Y, request.Id, request.Rotation, cancellationToken);
        return new Reply("plot.rotated", new { @object = PlaceOnPlotHandler.ObjectJson(turned) });
    }
}
