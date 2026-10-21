using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.World;

/// <summary>
/// Every plot has a station on the global railway. Goods loaded into a station can be sent to the
/// station of any other owned plot (the player's own or another player's factory); the train takes
/// time and costs a fee by distance, and the goods wait in the destination station until unloaded.
/// </summary>
public static class RailRules
{
    /// <summary>Real seconds a train needs per 100 km, and the shortest trip.</summary>
    public const double SecondsPer100Km = 5;

    public static readonly TimeSpan MinTrip = TimeSpan.FromSeconds(10);

    /// <summary>Fee: a fixed part plus cents per item per 100 km.</summary>
    public const long BaseFeeCents = 100;

    public const long CentsPerItemPer100Km = 1;

    public const int MaxQuantity = 100_000;

    /// <summary>Distance between plot centres along the grid, wrapping east-west.</summary>
    public static double DistanceKm(WorldMap map, int fromX, int fromY, int toX, int toY)
    {
        var dx = Math.Abs(fromX - toX);
        dx = Math.Min(dx, map.Width - dx);
        return Math.Sqrt((double)dx * dx + (double)(fromY - toY) * (fromY - toY)) * PlotRules.SideKm;
    }

    public static TimeSpan TripTime(double km) =>
        TimeSpan.FromSeconds(Math.Max(MinTrip.TotalSeconds, km / 100 * SecondsPer100Km));

    public static long FeeCents(double km, long quantity) =>
        BaseFeeCents + (long)Math.Ceiling(km / 100 * quantity * CentsPerItemPer100Km);
}

public sealed record Shipment(long Id, int FromX, int FromY, int ToX, int ToY, string Item, long Quantity, DateTimeOffset ArrivesAt);

public sealed record StationState(
    int X, int Y, IReadOnlyDictionary<string, long> Items, IReadOnlyList<Shipment> Incoming, IReadOnlyList<Shipment> Outgoing, DateTimeOffset Now);

public sealed class StationService(GameDb db, WorldMap map, PlotService plots, IInventory inventory, IWallet wallet, TimeProvider time)
{
    /// <summary>The station of one of the player's plots, after unloading every train that has arrived.</summary>
    public Task<StationState> StateAsync(Guid player, int x, int y, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            return await ReadAsync(x, y, cancellationToken);
        }, cancellationToken);

    /// <summary>Moves items from the inventory into the station.</summary>
    public Task<StationState> LoadAsync(Guid player, int x, int y, string item, long quantity, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            CheckQuantity(item, quantity);
            await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            await inventory.RemoveAsync(player, item, quantity, cancellationToken);
            await ChangeStockAsync(x, y, item, quantity, cancellationToken);
            return await ReadAsync(x, y, cancellationToken);
        }, cancellationToken);

    /// <summary>Moves items from the station into the inventory.</summary>
    public Task<StationState> UnloadAsync(Guid player, int x, int y, string item, long quantity, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            CheckQuantity(item, quantity);
            await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            await DeliverAsync(x, y, cancellationToken);
            await ChangeStockAsync(x, y, item, -quantity, cancellationToken);
            await inventory.AddAsync(player, item, quantity, cancellationToken);
            return await ReadAsync(x, y, cancellationToken);
        }, cancellationToken);

    /// <summary>Sends items from this station by train to the station of another owned plot.</summary>
    public Task<StationState> SendAsync(Guid player, int x, int y, int toX, int toY, string item, long quantity, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            CheckQuantity(item, quantity);
            await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            if (!map.Contains(toX, toY) || (toX == x && toY == y))
            {
                throw new GameException("bad_destination", "Choose another plot to send to.");
            }

            await using (var owned = await db.CommandAsync("SELECT 1 FROM world.plots WHERE x = @x AND y = @y", cancellationToken))
            {
                owned.Parameters.AddWithValue("x", toX);
                owned.Parameters.AddWithValue("y", toY);
                if (await owned.ExecuteScalarAsync(cancellationToken) is null)
                {
                    throw new GameException("no_station", "Nobody owns that plot, so it has no station yet.");
                }
            }

            await DeliverAsync(x, y, cancellationToken);
            await ChangeStockAsync(x, y, item, -quantity, cancellationToken);
            var km = RailRules.DistanceKm(map, x, y, toX, toY);
            await wallet.DebitAsync(player, RailRules.FeeCents(km, quantity), $"rail {quantity} {item} {x}:{y}->{toX}:{toY}", cancellationToken);

            await using var insert = await db.CommandAsync(
                """
                INSERT INTO world.shipments (from_x, from_y, to_x, to_y, item, quantity, sender_id, arrives_at)
                VALUES (@fx, @fy, @tx, @ty, @item, @quantity, @sender, @at)
                """, cancellationToken);
            insert.Parameters.AddWithValue("fx", x);
            insert.Parameters.AddWithValue("fy", y);
            insert.Parameters.AddWithValue("tx", toX);
            insert.Parameters.AddWithValue("ty", toY);
            insert.Parameters.AddWithValue("item", item);
            insert.Parameters.AddWithValue("quantity", quantity);
            insert.Parameters.AddWithValue("sender", player);
            insert.Parameters.AddWithValue("at", time.GetUtcNow() + RailRules.TripTime(km));
            await insert.ExecuteNonQueryAsync(cancellationToken);
            return await ReadAsync(x, y, cancellationToken);
        }, cancellationToken);

    private static void CheckQuantity(string item, long quantity)
    {
        if (!Items.Exists(item ?? ""))
        {
            throw new GameException("unknown_item", "Unknown item.");
        }

        if (quantity is < 1 or > RailRules.MaxQuantity)
        {
            throw new GameException("bad_quantity", $"Quantity must be 1-{RailRules.MaxQuantity}.");
        }
    }

    /// <summary>Puts the goods of every train that has arrived into the station.</summary>
    private async Task DeliverAsync(int x, int y, CancellationToken cancellationToken)
    {
        // DELETE ... RETURNING hands each arrived train to exactly one request.
        await using var command = await db.CommandAsync(
            """
            DELETE FROM world.shipments WHERE to_x = @x AND to_y = @y AND arrives_at <= @now
            RETURNING item, quantity
            """, cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        command.Parameters.AddWithValue("now", time.GetUtcNow());
        var arrived = new List<(string, long)>();
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                arrived.Add((reader.GetString(0), reader.GetInt64(1)));
            }
        }

        foreach (var (item, quantity) in arrived)
        {
            await ChangeStockAsync(x, y, item, quantity, cancellationToken);
        }
    }

    private async Task ChangeStockAsync(int x, int y, string item, long change, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """
            INSERT INTO world.station_items (x, y, item, quantity) VALUES (@x, @y, @item, @change)
            ON CONFLICT (x, y, item) DO UPDATE SET quantity = station_items.quantity + excluded.quantity
            RETURNING quantity
            """, cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        command.Parameters.AddWithValue("item", item);
        command.Parameters.AddWithValue("change", change);
        var left = (long)(await command.ExecuteScalarAsync(cancellationToken))!;
        if (left < 0)
        {
            throw new GameException("not_enough_items", "The station doesn't have that many.");
        }

        if (left == 0)
        {
            await using var delete = await db.CommandAsync(
                "DELETE FROM world.station_items WHERE x = @x AND y = @y AND item = @item", cancellationToken);
            delete.Parameters.AddWithValue("x", x);
            delete.Parameters.AddWithValue("y", y);
            delete.Parameters.AddWithValue("item", item);
            await delete.ExecuteNonQueryAsync(cancellationToken);
        }
    }

    private async Task<StationState> ReadAsync(int x, int y, CancellationToken cancellationToken)
    {
        await DeliverAsync(x, y, cancellationToken);
        var items = new Dictionary<string, long>();
        await using (var command = await db.CommandAsync(
            "SELECT item, quantity FROM world.station_items WHERE x = @x AND y = @y ORDER BY item", cancellationToken))
        {
            command.Parameters.AddWithValue("x", x);
            command.Parameters.AddWithValue("y", y);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                items[reader.GetString(0)] = reader.GetInt64(1);
            }
        }

        var shipments = new List<Shipment>();
        await using (var command = await db.CommandAsync(
            """
            SELECT id, from_x, from_y, to_x, to_y, item, quantity, arrives_at FROM world.shipments
            WHERE (to_x = @x AND to_y = @y) OR (from_x = @x AND from_y = @y)
            ORDER BY arrives_at LIMIT 100
            """, cancellationToken))
        {
            command.Parameters.AddWithValue("x", x);
            command.Parameters.AddWithValue("y", y);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                shipments.Add(new Shipment(reader.GetInt64(0), reader.GetInt32(1), reader.GetInt32(2), reader.GetInt32(3), reader.GetInt32(4),
                    reader.GetString(5), reader.GetInt64(6), reader.GetFieldValue<DateTimeOffset>(7)));
            }
        }

        return new StationState(x, y, items,
            shipments.Where(s => s.ToX == x && s.ToY == y).ToList(),
            shipments.Where(s => s.FromX == x && s.FromY == y).ToList(),
            time.GetUtcNow());
    }
}

public sealed record StationRequest(int X, int Y);

public sealed record StockRequest(int X, int Y, string Item, long Quantity);

public sealed record SendRequest(int X, int Y, int ToX, int ToY, string Item, long Quantity);

public abstract class StationHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var state = await RunAsync(scope.ServiceProvider.GetRequiredService<StationService>(), client.RequireAccount(), payload, cancellationToken);
        object Trip(Shipment s) => new
        {
            fromX = s.FromX,
            fromY = s.FromY,
            toX = s.ToX,
            toY = s.ToY,
            item = s.Item,
            name = Items.Names.GetValueOrDefault(s.Item, s.Item),
            quantity = s.Quantity,
            arrivesAt = s.ArrivesAt.ToUnixTimeMilliseconds(),
        };
        return new Reply("station", new
        {
            x = state.X,
            y = state.Y,
            items = state.Items.Select(i => new { id = i.Key, name = Items.Names.GetValueOrDefault(i.Key, i.Key), quantity = i.Value }),
            incoming = state.Incoming.Select(Trip),
            outgoing = state.Outgoing.Select(Trip),
            serverTime = state.Now.ToUnixTimeMilliseconds(),
            rates = new
            {
                baseFeeCents = RailRules.BaseFeeCents,
                centsPerItemPer100Km = RailRules.CentsPerItemPer100Km,
                secondsPer100Km = RailRules.SecondsPer100Km,
                minTripSeconds = RailRules.MinTrip.TotalSeconds,
            },
        });
    }

    protected abstract Task<StationState> RunAsync(StationService station, Guid player, JsonElement? payload, CancellationToken cancellationToken);
}

public sealed class GetStationHandler(IServiceScopeFactory scopes) : StationHandler(scopes)
{
    public override string Type => "station.get";

    protected override Task<StationState> RunAsync(StationService station, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var r = Payload.Read<StationRequest>(payload);
        return station.StateAsync(player, r.X, r.Y, cancellationToken);
    }
}

public sealed class LoadStationHandler(IServiceScopeFactory scopes) : StationHandler(scopes)
{
    public override string Type => "station.load";

    protected override Task<StationState> RunAsync(StationService station, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var r = Payload.Read<StockRequest>(payload);
        return station.LoadAsync(player, r.X, r.Y, r.Item, r.Quantity, cancellationToken);
    }
}

public sealed class UnloadStationHandler(IServiceScopeFactory scopes) : StationHandler(scopes)
{
    public override string Type => "station.unload";

    protected override Task<StationState> RunAsync(StationService station, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var r = Payload.Read<StockRequest>(payload);
        return station.UnloadAsync(player, r.X, r.Y, r.Item, r.Quantity, cancellationToken);
    }
}

public sealed class SendHandler(IServiceScopeFactory scopes) : StationHandler(scopes)
{
    public override string Type => "station.send";

    protected override Task<StationState> RunAsync(StationService station, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var r = Payload.Read<SendRequest>(payload);
        return station.SendAsync(player, r.X, r.Y, r.ToX, r.ToY, r.Item, r.Quantity, cancellationToken);
    }
}
