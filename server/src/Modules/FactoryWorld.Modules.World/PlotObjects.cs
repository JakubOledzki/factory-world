using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.World;

/// <summary>
/// Things a player carries out of the inventory and puts on a free tile of their plot, e.g. a
/// workbench to craft at far from the garage, a furnace or a machine that processes crops
/// (mill, oil press, pickling barrel, bakery, field kitchen). Each stands on one tile.
/// </summary>
public static class PlotObjects
{
    /// <summary>Items that can be put on a plot.</summary>
    public static readonly IReadOnlySet<string> Placeable = new HashSet<string>
    {
        Items.Workbench, Items.Furnace,
        Items.Mill, Items.OilPress, Items.PicklingBarrel, Items.Bakery, Items.Kitchen,
    };
}

public sealed record PlacedOnPlot(Guid Id, string Kind, int TileX, int TileY);

public sealed class PlotObjectService(GameDb db, PlotService plots, IInventory inventory, IMachineContents machines) : IPlacedObjects
{
    public async Task<IReadOnlyList<PlacedOnPlot>> ObjectsAsync(int x, int y, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT id, kind, tile_x, tile_y FROM world.plot_objects WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var objects = new List<PlacedOnPlot>();
        while (await reader.ReadAsync(cancellationToken))
        {
            objects.Add(new PlacedOnPlot(reader.GetGuid(0), reader.GetString(1), reader.GetInt32(2), reader.GetInt32(3)));
        }

        return objects;
    }

    /// <summary>Puts an object from the inventory on a free tile of the player's plot.</summary>
    public Task<PlacedOnPlot> PlaceAsync(Guid player, int x, int y, string kind, int tileX, int tileY, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (!PlotObjects.Placeable.Contains(kind))
            {
                throw new GameException("not_placeable", "This item cannot be put on a plot.");
            }

            await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            if ((tileX, tileY) == PlotLayout.Spawn || !await plots.FreeAsync(player, x, y, tileX, tileY, cancellationToken))
            {
                throw new GameException("blocked", "Something stands here.");
            }

            await inventory.RemoveAsync(player, kind, 1, cancellationToken);
            var placed = new PlacedOnPlot(Guid.NewGuid(), kind, tileX, tileY);
            await using var insert = await db.CommandAsync(
                """
                INSERT INTO world.plot_objects (id, x, y, tile_x, tile_y, owner_id, kind)
                VALUES (@id, @x, @y, @tx, @ty, @owner, @kind)
                ON CONFLICT DO NOTHING
                """, cancellationToken);
            insert.Parameters.AddWithValue("id", placed.Id);
            insert.Parameters.AddWithValue("x", x);
            insert.Parameters.AddWithValue("y", y);
            insert.Parameters.AddWithValue("tx", tileX);
            insert.Parameters.AddWithValue("ty", tileY);
            insert.Parameters.AddWithValue("owner", player);
            insert.Parameters.AddWithValue("kind", kind);
            if (await insert.ExecuteNonQueryAsync(cancellationToken) == 0)
            {
                throw new GameException("blocked", "Something stands here.");
            }

            return placed;
        }, cancellationToken);

    /// <summary>Takes an object off the player's plot back into the inventory, with whatever it holds.</summary>
    public Task PickUpAsync(Guid player, int x, int y, Guid id, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            await using var delete = await db.CommandAsync(
                "DELETE FROM world.plot_objects WHERE id = @id AND x = @x AND y = @y AND owner_id = @owner RETURNING kind", cancellationToken);
            delete.Parameters.AddWithValue("id", id);
            delete.Parameters.AddWithValue("x", x);
            delete.Parameters.AddWithValue("y", y);
            delete.Parameters.AddWithValue("owner", player);
            var kind = await delete.ExecuteScalarAsync(cancellationToken) as string
                ?? throw new GameException("no_object", "There is no such object on this plot.");
            await machines.ReleaseAsync(player, id, cancellationToken);
            await inventory.AddAsync(player, kind, 1, cancellationToken);
        }, cancellationToken);

    public async Task<string?> KindAsync(Guid owner, Guid id, CancellationToken cancellationToken)
    {
        // A plot can change hands only by being bought, so the object is the player's while the plot is.
        await using var command = await db.CommandAsync(
            """
            SELECT o.kind FROM world.plot_objects o JOIN world.plots p ON p.x = o.x AND p.y = o.y
            WHERE o.id = @id AND o.owner_id = @owner AND p.owner_id = @owner
            """, cancellationToken);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("owner", owner);
        return await command.ExecuteScalarAsync(cancellationToken) as string;
    }
}

public sealed record PlaceOnPlotRequest(int X, int Y, string Kind, int TileX, int TileY);

public sealed record PickUpFromPlotRequest(int X, int Y, Guid Id);

public sealed class PlaceOnPlotHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "plot.place";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<PlaceOnPlotRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var placed = await scope.ServiceProvider.GetRequiredService<PlotObjectService>().PlaceAsync(
            client.RequireAccount(), request.X, request.Y, request.Kind ?? "", request.TileX, request.TileY, cancellationToken);
        return new Reply("plot.placed", new { @object = ObjectJson(placed) });
    }

    public static object ObjectJson(PlacedOnPlot placed) => new
    {
        id = placed.Id,
        kind = placed.Kind,
        name = Items.Names[placed.Kind],
        tileX = placed.TileX,
        tileY = placed.TileY,
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
