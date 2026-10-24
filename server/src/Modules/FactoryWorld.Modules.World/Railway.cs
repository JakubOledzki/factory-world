using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace FactoryWorld.Modules.World;

/// <summary>
/// Every plot has a station on the global railway. Goods loaded into a station can be sent to the
/// station of any other owned plot (the player's own or another player's factory); the train takes
/// time and costs a fee by distance, and the goods wait in the destination station until unloaded.
/// A route sends a train by itself every few minutes with whatever the station holds, and
/// inserters load and unload the station, so factories on different plots work together.
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

    /// <summary>Most items one train of a route carries.</summary>
    public const int RouteCapacity = 2000;

    /// <summary>How often a route's train may leave, in minutes.</summary>
    public static readonly IReadOnlyList<int> RouteMinutes = [1, 5, 15, 60];

    /// <summary>Most routes leaving one station.</summary>
    public const int MaxRoutes = 5;

    /// <summary>Most items a route can be limited to.</summary>
    public const int MaxRouteItems = 8;

    /// <summary>Inserters stop putting an item into the station when it holds this many of it.</summary>
    public const long InserterStockLimit = 10_000;

    /// <summary>The kind of the station as a fixture of the plot (see <see cref="IPlotObjects.FixturesAsync"/>).</summary>
    public const string StationKind = "rail_station";

    private const int IdMark = 0x57a7_1011;
    private static readonly byte[] IdTail = "station!"u8.ToArray();

    /// <summary>The station of a plot as one object, the same id every time.</summary>
    public static Guid StationId(int x, int y) => new(IdMark, (short)x, (short)y, IdTail);

    /// <summary>The plot of a station id made by <see cref="StationId"/>.</summary>
    public static (int X, int Y)? StationAt(Guid id)
    {
        var bytes = id.ToByteArray();
        if (BitConverter.ToInt32(bytes, 0) != IdMark || !bytes.AsSpan(8).SequenceEqual(IdTail))
        {
            return null;
        }

        return ((ushort)BitConverter.ToInt16(bytes, 4), (ushort)BitConverter.ToInt16(bytes, 6));
    }

    /// <summary>The tiles inserters reach the station on: the building and the platform track in front of it.</summary>
    public static IEnumerable<(int TileX, int TileY)> StationTiles()
    {
        var (sx, sy, sw, sh) = PlotLayout.Station;
        for (var y = sy; y < sy + sh; y++)
        {
            for (var x = sx; x < sx + sw; x++)
            {
                yield return (x, y);
            }
        }

        for (var x = sx; x < sx + sw; x++)
        {
            yield return (x, PlotLayout.RailRow);
        }
    }

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

    /// <summary>What a train of a route takes from the station's stock: only the route's items (all when
    /// it has none), in the route's order, then by name, up to <see cref="RouteCapacity"/>.</summary>
    public static IReadOnlyList<(string Item, long Quantity)> Cargo(IReadOnlyDictionary<string, long> stock, IReadOnlyList<string> items)
    {
        var order = items.Count > 0
            ? items.Where(stock.ContainsKey)
            : stock.Keys.Order(StringComparer.Ordinal);
        var cargo = new List<(string, long)>();
        long room = RouteCapacity;
        foreach (var item in order)
        {
            var take = Math.Min(room, stock[item]);
            if (take > 0)
            {
                cargo.Add((item, take));
                room -= take;
            }
        }

        return cargo;
    }
}

/// <param name="Sender">Who sent the train, when it was someone else.</param>
/// <param name="Receiver">Who owns the destination, when it is someone else.</param>
public sealed record Shipment(
    long Id, int FromX, int FromY, int ToX, int ToY, string Item, long Quantity, DateTimeOffset ArrivesAt, string? Sender = null, string? Receiver = null);

/// <summary>A train that leaves a station by itself every <see cref="EveryMinutes"/>.</summary>
/// <param name="Items">Only these leave with it; none means everything in the station.</param>
/// <param name="Problem">Why the last train did not leave: <c>empty</c>, <c>no_money</c> or <c>no_station</c>.</param>
public sealed record TrainRoute(
    long Id, int ToX, int ToY, IReadOnlyList<string> Items, int EveryMinutes, DateTimeOffset NextAt,
    DateTimeOffset? LastAt, long LastQuantity, string? Problem, string? Receiver);

public sealed record StationState(
    int X, int Y, IReadOnlyDictionary<string, long> Items, IReadOnlyList<Shipment> Incoming, IReadOnlyList<Shipment> Outgoing,
    IReadOnlyList<TrainRoute> Routes, DateTimeOffset Now);

/// <summary>A player found by name, with the plots their station stands on.</summary>
public sealed record RailPartner(string Name, IReadOnlyList<(int X, int Y, Biome Biome)> Plots);

/// <summary>The goods in stations, shared by the station's window, its routes and the inserters that work it.</summary>
internal static class StationStock
{
    /// <summary>Locks one station until the transaction ends. Take the plot's logistics first, then this.</summary>
    public static async Task LockAsync(GameDb db, int x, int y, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync("SELECT pg_advisory_xact_lock(@key)", cancellationToken);
        command.Parameters.AddWithValue("key", ((long)x << 32 | (uint)y) ^ 0x73746174_696f6e21);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public static async Task<Dictionary<string, long>> ReadAsync(GameDb db, int x, int y, CancellationToken cancellationToken)
    {
        var items = new Dictionary<string, long>();
        await using var command = await db.CommandAsync(
            "SELECT item, quantity FROM world.station_items WHERE x = @x AND y = @y ORDER BY item", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            items[reader.GetString(0)] = reader.GetInt64(1);
        }

        return items;
    }

    public static async Task ChangeAsync(GameDb db, int x, int y, string item, long change, CancellationToken cancellationToken)
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

    /// <summary>Starts a train: the goods are already out of the station, they arrive after the trip.</summary>
    public static async Task DispatchAsync(
        GameDb db, int x, int y, int toX, int toY, string item, long quantity, Guid sender, DateTimeOffset arrivesAt, CancellationToken cancellationToken)
    {
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
        insert.Parameters.AddWithValue("sender", sender);
        insert.Parameters.AddWithValue("at", arrivesAt);
        await insert.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>The owner of a plot, or null when nobody bought it.</summary>
    public static async Task<Guid?> OwnerAsync(GameDb db, int x, int y, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync("SELECT owner_id FROM world.plots WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        return await command.ExecuteScalarAsync(cancellationToken) as Guid?;
    }
}

public sealed class StationService(
    GameDb db, WorldMap map, PlotService plots, IInventory inventory, IWallet wallet, ICharacterNames names,
    IEnumerable<IPlotAutomation> automation, TimeProvider time)
{
    /// <summary>The station of one of the player's plots, after unloading every train that has arrived.</summary>
    public Task<StationState> StateAsync(Guid player, int x, int y, CancellationToken cancellationToken) =>
        ChangeAsync(player, x, y, PlotRight.Work, () => Task.CompletedTask, cancellationToken);

    /// <summary>Moves items from the inventory into the station.</summary>
    public Task<StationState> LoadAsync(Guid player, int x, int y, string item, long quantity, CancellationToken cancellationToken) =>
        ChangeAsync(player, x, y, PlotRight.Work, async () =>
        {
            CheckQuantity(item, quantity);
            await inventory.RemoveAsync(player, item, quantity, cancellationToken);
            await StationStock.ChangeAsync(db, x, y, item, quantity, cancellationToken);
        }, cancellationToken);

    /// <summary>Moves items from the station into the inventory.</summary>
    public Task<StationState> UnloadAsync(Guid player, int x, int y, string item, long quantity, CancellationToken cancellationToken) =>
        ChangeAsync(player, x, y, PlotRight.Take, async () =>
        {
            CheckQuantity(item, quantity);
            await StationStock.ChangeAsync(db, x, y, item, -quantity, cancellationToken);
            await inventory.AddAsync(player, item, quantity, cancellationToken);
        }, cancellationToken);

    /// <summary>Sends items from this station by train to the station of another owned plot.</summary>
    public Task<StationState> SendAsync(Guid player, int x, int y, int toX, int toY, string item, long quantity, CancellationToken cancellationToken) =>
        ChangeAsync(player, x, y, PlotRight.Take, async () =>
        {
            CheckQuantity(item, quantity);
            await CheckDestinationAsync(x, y, toX, toY, cancellationToken);
            await StationStock.ChangeAsync(db, x, y, item, -quantity, cancellationToken);
            var km = RailRules.DistanceKm(map, x, y, toX, toY);
            await wallet.DebitAsync(player, RailRules.FeeCents(km, quantity), $"rail {quantity} {item} {x}:{y}->{toX}:{toY}", cancellationToken);
            await StationStock.DispatchAsync(db, x, y, toX, toY, item, quantity, player, time.GetUtcNow() + RailRules.TripTime(km), cancellationToken);
        }, cancellationToken);

    /// <summary>Sets up a train that leaves this station by itself every <paramref name="everyMinutes"/>,
    /// the first one now, with the chosen items (or everything) for another owned plot.</summary>
    public async Task<StationState> AddRouteAsync(
        Guid player, int x, int y, int toX, int toY, IReadOnlyList<string> items, int everyMinutes, CancellationToken cancellationToken)
    {
        await ChangeAsync(player, x, y, PlotRight.Owner, async () =>
        {
            if (!RailRules.RouteMinutes.Contains(everyMinutes))
            {
                throw new GameException("bad_interval", $"A train can leave every {string.Join(", ", RailRules.RouteMinutes)} minutes.");
            }

            if (items.Count > RailRules.MaxRouteItems || items.Any(i => !Items.Exists(i ?? "")))
            {
                throw new GameException("bad_items", $"Choose at most {RailRules.MaxRouteItems} items for a route.");
            }

            await CheckDestinationAsync(x, y, toX, toY, cancellationToken);
            await using (var count = await db.CommandAsync("SELECT count(*) FROM world.train_routes WHERE from_x = @x AND from_y = @y", cancellationToken))
            {
                count.Parameters.AddWithValue("x", x);
                count.Parameters.AddWithValue("y", y);
                if ((long)(await count.ExecuteScalarAsync(cancellationToken))! >= RailRules.MaxRoutes)
                {
                    throw new GameException("too_many_routes", $"A station runs at most {RailRules.MaxRoutes} routes.");
                }
            }

            await using var insert = await db.CommandAsync(
                """
                INSERT INTO world.train_routes (owner_id, from_x, from_y, to_x, to_y, items, every_minutes, next_departure_at, last_quantity)
                VALUES (@owner, @fx, @fy, @tx, @ty, @items, @every, @next, 0)
                """, cancellationToken);
            insert.Parameters.AddWithValue("owner", player);
            insert.Parameters.AddWithValue("fx", x);
            insert.Parameters.AddWithValue("fy", y);
            insert.Parameters.AddWithValue("tx", toX);
            insert.Parameters.AddWithValue("ty", toY);
            insert.Parameters.AddWithValue("items", items.Distinct().ToArray());
            insert.Parameters.AddWithValue("every", everyMinutes);
            insert.Parameters.AddWithValue("next", time.GetUtcNow());
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }, cancellationToken);

        // The first train leaves at once.
        return await StateAsync(player, x, y, cancellationToken);
    }

    /// <summary>Stops a route; trains already on their way still arrive.</summary>
    public Task<StationState> RemoveRouteAsync(Guid player, int x, int y, long id, CancellationToken cancellationToken) =>
        ChangeAsync(player, x, y, PlotRight.Owner, async () =>
        {
            await using var delete = await db.CommandAsync(
                "DELETE FROM world.train_routes WHERE id = @id AND from_x = @x AND from_y = @y", cancellationToken);
            delete.Parameters.AddWithValue("id", id);
            delete.Parameters.AddWithValue("x", x);
            delete.Parameters.AddWithValue("y", y);
            if (await delete.ExecuteNonQueryAsync(cancellationToken) == 0)
            {
                throw new GameException("no_route", "There is no such route at this station.");
            }
        }, cancellationToken);

    /// <summary>Other players by the start of their name, with their plots, to send trains to.</summary>
    public async Task<IReadOnlyList<RailPartner>> FindAsync(Guid player, string query, CancellationToken cancellationToken)
    {
        var found = await names.FindAsync(query ?? "", 9, cancellationToken);
        var owners = found.Keys.Where(id => id != player).ToArray();
        var plotsOf = owners.ToDictionary(id => id, _ => new List<(int, int, Biome)>());
        if (owners.Length > 0)
        {
            await using var command = await db.CommandAsync(
                "SELECT owner_id, x, y, biome FROM world.plots WHERE owner_id = ANY(@owners) ORDER BY bought_at", cancellationToken);
            command.Parameters.AddWithValue("owners", owners);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                plotsOf[reader.GetGuid(0)].Add((reader.GetInt32(1), reader.GetInt32(2), (Biome)reader.GetInt16(3)));
            }
        }

        // Only players with a station to send to.
        return owners.Where(id => plotsOf[id].Count > 0)
            .Select(id => new RailPartner(found[id], plotsOf[id]))
            .OrderBy(p => p.Name, StringComparer.OrdinalIgnoreCase)
            .Take(8)
            .ToList();
    }

    /// <summary>
    /// Sends the trains of every route that is due, each in its own transaction; the background
    /// <see cref="RailwayDispatcher"/> calls this every moment. Returns how many routes were due.
    /// </summary>
    public async Task<int> RunDueRoutesAsync(int limit, CancellationToken cancellationToken)
    {
        var due = new List<long>();
        await using (var command = await db.CommandAsync(
            "SELECT id FROM world.train_routes WHERE next_departure_at <= @now ORDER BY next_departure_at LIMIT @limit", cancellationToken))
        {
            command.Parameters.AddWithValue("now", time.GetUtcNow());
            command.Parameters.AddWithValue("limit", limit);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                due.Add(reader.GetInt64(0));
            }
        }

        foreach (var id in due)
        {
            await DepartAsync(id, cancellationToken);
        }

        return due.Count;
    }

    /// <summary>Sends the due trains of routes that leave from or go to this station, so a station
    /// shows what it should even when the background dispatcher has not come round yet.</summary>
    private async Task CatchUpRoutesAsync(int x, int y, CancellationToken cancellationToken)
    {
        var due = new List<long>();
        await using (var command = await db.CommandAsync(
            """
            SELECT id FROM world.train_routes
            WHERE ((from_x = @x AND from_y = @y) OR (to_x = @x AND to_y = @y)) AND next_departure_at <= @now
            """, cancellationToken))
        {
            command.Parameters.AddWithValue("x", x);
            command.Parameters.AddWithValue("y", y);
            command.Parameters.AddWithValue("now", time.GetUtcNow());
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                due.Add(reader.GetInt64(0));
            }
        }

        foreach (var id in due)
        {
            await DepartAsync(id, cancellationToken);
        }
    }

    /// <summary>
    /// One train of a route, at the latest time it was due: it takes what the station holds of the
    /// route's items, up to its capacity, and costs the usual fee. Without goods or money it stays.
    /// Runs in a transaction of its own unless one is open already.
    /// </summary>
    private Task DepartAsync(long id, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            int x, y;
            await using (var find = await db.CommandAsync("SELECT from_x, from_y FROM world.train_routes WHERE id = @id", cancellationToken))
            {
                find.Parameters.AddWithValue("id", id);
                await using var reader = await find.ExecuteReaderAsync(cancellationToken);
                if (!await reader.ReadAsync(cancellationToken))
                {
                    return;
                }

                (x, y) = (reader.GetInt32(0), reader.GetInt32(1));
            }

            // Inserters may have loaded the station up to now; then the station itself, then the route.
            await CatchUpPlotAsync(x, y, cancellationToken);
            await StationStock.LockAsync(db, x, y, cancellationToken);
            await DeliverAsync(x, y, cancellationToken);

            var now = time.GetUtcNow();
            Guid owner;
            int toX, toY, every;
            string[] items;
            DateTimeOffset next;
            await using (var route = await db.CommandAsync(
                """
                SELECT owner_id, to_x, to_y, items, every_minutes, next_departure_at FROM world.train_routes
                WHERE id = @id AND next_departure_at <= @now FOR UPDATE
                """, cancellationToken))
            {
                route.Parameters.AddWithValue("id", id);
                route.Parameters.AddWithValue("now", now);
                await using var reader = await route.ExecuteReaderAsync(cancellationToken);
                if (!await reader.ReadAsync(cancellationToken))
                {
                    // Sent by someone else meanwhile.
                    return;
                }

                (owner, toX, toY, items, every, next) = (reader.GetGuid(0), reader.GetInt32(1), reader.GetInt32(2),
                    reader.GetFieldValue<string[]>(3), reader.GetInt32(4), reader.GetFieldValue<DateTimeOffset>(5));
            }

            if (await StationStock.OwnerAsync(db, x, y, cancellationToken) != owner)
            {
                // The plot is no longer the route owner's.
                await using var delete = await db.CommandAsync("DELETE FROM world.train_routes WHERE id = @id", cancellationToken);
                delete.Parameters.AddWithValue("id", id);
                await delete.ExecuteNonQueryAsync(cancellationToken);
                return;
            }

            // Trains missed while nobody was around leave as one, at the last time one was due.
            var interval = TimeSpan.FromMinutes(every);
            var departure = next + interval * Math.Floor((now - next) / interval);
            string? problem = null;
            long sent = 0;
            if (await StationStock.OwnerAsync(db, toX, toY, cancellationToken) is null)
            {
                problem = "no_station";
            }
            else if (RailRules.Cargo(await StationStock.ReadAsync(db, x, y, cancellationToken), items) is not { Count: > 0 } cargo)
            {
                problem = "empty";
            }
            else
            {
                var km = RailRules.DistanceKm(map, x, y, toX, toY);
                var quantity = cargo.Sum(c => c.Quantity);
                var fee = RailRules.FeeCents(km, quantity);
                if (await wallet.BalanceAsync(owner, cancellationToken) < fee)
                {
                    problem = "no_money";
                }
                else
                {
                    await wallet.DebitAsync(owner, fee, $"rail route {id} {quantity} items {x}:{y}->{toX}:{toY}", cancellationToken);
                    foreach (var (item, count) in cargo)
                    {
                        await StationStock.ChangeAsync(db, x, y, item, -count, cancellationToken);
                        await StationStock.DispatchAsync(db, x, y, toX, toY, item, count, owner, departure + RailRules.TripTime(km), cancellationToken);
                    }

                    sent = quantity;
                }
            }

            await using var update = await db.CommandAsync(
                problem is null
                    ? """
                      UPDATE world.train_routes SET next_departure_at = @next, last_departed_at = @at, last_quantity = @sent, last_problem = NULL
                      WHERE id = @id
                      """
                    : "UPDATE world.train_routes SET next_departure_at = @next, last_problem = @problem WHERE id = @id",
                cancellationToken);
            update.Parameters.AddWithValue("id", id);
            update.Parameters.AddWithValue("next", departure + interval);
            update.Parameters.AddWithValue("at", departure);
            update.Parameters.AddWithValue("sent", sent);
            update.Parameters.AddWithValue("problem", (object?)problem ?? DBNull.Value);
            await update.ExecuteNonQueryAsync(cancellationToken);
        }, cancellationToken);

    /// <summary>
    /// Every station request: due trains leave first, then, in one transaction, the plot's inserters
    /// are brought up to now, the station is locked, arrived trains unload, <paramref name="change"/>
    /// runs and the station is read back.
    /// </summary>
    private async Task<StationState> ChangeAsync(
        Guid player, int x, int y, PlotRight right, Func<Task> change, CancellationToken cancellationToken)
    {
        await plots.RequireOwnerAsync(player, x, y, cancellationToken, right);
        await CatchUpRoutesAsync(x, y, cancellationToken);
        return await db.InTransactionAsync(async () =>
        {
            await plots.RequireOwnerAsync(player, x, y, cancellationToken, right);
            await CatchUpPlotAsync(x, y, cancellationToken);
            await StationStock.LockAsync(db, x, y, cancellationToken);
            await DeliverAsync(x, y, cancellationToken);
            await change();
            return await ReadAsync(player, x, y, cancellationToken);
        }, cancellationToken);
    }

    private async Task CatchUpPlotAsync(int x, int y, CancellationToken cancellationToken)
    {
        foreach (var machinery in automation)
        {
            await machinery.CatchUpAsync(x, y, cancellationToken);
        }
    }

    private async Task CheckDestinationAsync(int x, int y, int toX, int toY, CancellationToken cancellationToken)
    {
        if (!map.Contains(toX, toY) || (toX == x && toY == y))
        {
            throw new GameException("bad_destination", "Choose another plot to send to.");
        }

        if (await StationStock.OwnerAsync(db, toX, toY, cancellationToken) is null)
        {
            throw new GameException("no_station", "Nobody owns that plot, so it has no station yet.");
        }
    }

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
            await StationStock.ChangeAsync(db, x, y, item, quantity, cancellationToken);
        }
    }

    private async Task<StationState> ReadAsync(Guid player, int x, int y, CancellationToken cancellationToken)
    {
        var items = await StationStock.ReadAsync(db, x, y, cancellationToken);
        var shipments = new List<(Shipment Trip, Guid Sender)>();
        await using (var command = await db.CommandAsync(
            """
            SELECT id, from_x, from_y, to_x, to_y, item, quantity, arrives_at, sender_id FROM world.shipments
            WHERE (to_x = @x AND to_y = @y) OR (from_x = @x AND from_y = @y)
            ORDER BY arrives_at LIMIT 100
            """, cancellationToken))
        {
            command.Parameters.AddWithValue("x", x);
            command.Parameters.AddWithValue("y", y);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                shipments.Add((new Shipment(reader.GetInt64(0), reader.GetInt32(1), reader.GetInt32(2), reader.GetInt32(3), reader.GetInt32(4),
                    reader.GetString(5), reader.GetInt64(6), reader.GetFieldValue<DateTimeOffset>(7)), reader.GetGuid(8)));
            }
        }

        var routes = new List<TrainRoute>();
        await using (var command = await db.CommandAsync(
            """
            SELECT id, to_x, to_y, items, every_minutes, next_departure_at, last_departed_at, last_quantity, last_problem
            FROM world.train_routes WHERE from_x = @x AND from_y = @y ORDER BY id
            """, cancellationToken))
        {
            command.Parameters.AddWithValue("x", x);
            command.Parameters.AddWithValue("y", y);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                routes.Add(new TrainRoute(reader.GetInt64(0), reader.GetInt32(1), reader.GetInt32(2), reader.GetFieldValue<string[]>(3),
                    reader.GetInt32(4), reader.GetFieldValue<DateTimeOffset>(5),
                    reader.IsDBNull(6) ? null : reader.GetFieldValue<DateTimeOffset>(6), reader.GetInt64(7),
                    reader.IsDBNull(8) ? null : reader.GetString(8), null));
            }
        }

        // Who is on the other end, when it is not the player.
        var destinations = shipments.Where(s => s.Trip.FromX == x && s.Trip.FromY == y).Select(s => (s.Trip.ToX, s.Trip.ToY))
            .Concat(routes.Select(r => (r.ToX, r.ToY))).Distinct().ToList();
        var receivers = new Dictionary<(int, int), Guid>();
        foreach (var (tx, ty) in destinations)
        {
            if (await StationStock.OwnerAsync(db, tx, ty, cancellationToken) is { } owner && owner != player)
            {
                receivers[(tx, ty)] = owner;
            }
        }

        var others = shipments.Select(s => s.Sender).Concat(receivers.Values).Where(id => id != player).Distinct().ToList();
        var nameOf = await names.NamesAsync(others, cancellationToken);
        string? Receiver(int tx, int ty) => receivers.TryGetValue((tx, ty), out var owner) ? nameOf.GetValueOrDefault(owner, "?") : null;

        var incoming = shipments.Where(s => s.Trip.ToX == x && s.Trip.ToY == y)
            .Select(s => s.Trip with { Sender = s.Sender == player ? null : nameOf.GetValueOrDefault(s.Sender, "?") }).ToList();
        var outgoing = shipments.Where(s => s.Trip.FromX == x && s.Trip.FromY == y)
            .Select(s => s.Trip with { Receiver = Receiver(s.Trip.ToX, s.Trip.ToY) }).ToList();
        return new StationState(x, y, items, incoming, outgoing,
            routes.Select(r => r with { Receiver = Receiver(r.ToX, r.ToY) }).ToList(), time.GetUtcNow());
    }
}

/// <summary>
/// The station as inserters see it: anything can be put in (up to <see cref="RailRules.InserterStockLimit"/>
/// of one item) and anything taken out, every kind in turn. Trains that arrive while the plot's
/// machinery runs unload at the moment they arrive.
/// </summary>
public sealed class StationPorts(GameDb db, TimeProvider time) : IMachinePorts
{
    public async Task<IMachinePort?> OpenAsync(Guid owner, Guid id, string kind, CancellationToken cancellationToken)
    {
        if (kind != RailRules.StationKind || RailRules.StationAt(id) is not var (x, y))
        {
            return null;
        }

        await StationStock.LockAsync(db, x, y, cancellationToken);
        var stock = await StationStock.ReadAsync(db, x, y, cancellationToken);
        var arriving = new List<(long Id, string Item, long Quantity, DateTimeOffset At)>();
        await using (var command = await db.CommandAsync(
            "SELECT id, item, quantity, arrives_at FROM world.shipments WHERE to_x = @x AND to_y = @y AND arrives_at <= @now ORDER BY arrives_at",
            cancellationToken))
        {
            command.Parameters.AddWithValue("x", x);
            command.Parameters.AddWithValue("y", y);
            command.Parameters.AddWithValue("now", time.GetUtcNow());
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                arriving.Add((reader.GetInt64(0), reader.GetString(1), reader.GetInt64(2), reader.GetFieldValue<DateTimeOffset>(3)));
            }
        }

        return new Port(db, x, y, stock, arriving);
    }

    private sealed class Port(
        GameDb db, int x, int y, Dictionary<string, long> stock, List<(long Id, string Item, long Quantity, DateTimeOffset At)> arriving)
        : IMachinePort
    {
        private readonly Dictionary<string, long> _changes = [];
        private readonly List<long> _arrived = [];
        private int _next;

        public string? Output(DateTimeOffset now, Func<string, bool> wanted)
        {
            Arrive(now);
            var kinds = stock.Where(s => s.Value > 0).Select(s => s.Key).Order(StringComparer.Ordinal).ToList();
            for (var i = 0; i < kinds.Count; i++)
            {
                var item = kinds[(_next + i) % kinds.Count];
                if (wanted(item))
                {
                    return item;
                }
            }

            return null;
        }

        public void Take(string item, DateTimeOffset now)
        {
            if (stock.GetValueOrDefault(item) > 0)
            {
                Change(item, -1);
                _next++;
            }
        }

        public bool Accepts(string item, DateTimeOffset now)
        {
            Arrive(now);
            return stock.GetValueOrDefault(item) < RailRules.InserterStockLimit;
        }

        public void Put(string item, DateTimeOffset now) => Change(item, 1);

        public DateTimeOffset? NextChange(DateTimeOffset now) =>
            arriving.Where(a => a.At > now).Select(a => (DateTimeOffset?)a.At).FirstOrDefault();

        public async Task SaveAsync(CancellationToken cancellationToken)
        {
            if (_arrived.Count > 0)
            {
                await using var delete = await db.CommandAsync("DELETE FROM world.shipments WHERE id = ANY(@ids)", cancellationToken);
                delete.Parameters.AddWithValue("ids", _arrived.ToArray());
                await delete.ExecuteNonQueryAsync(cancellationToken);
            }

            foreach (var (item, change) in _changes.Where(c => c.Value != 0))
            {
                await StationStock.ChangeAsync(db, x, y, item, change, cancellationToken);
            }
        }

        private void Arrive(DateTimeOffset now)
        {
            while (arriving.Count > 0 && arriving[0].At <= now)
            {
                Change(arriving[0].Item, arriving[0].Quantity);
                _arrived.Add(arriving[0].Id);
                arriving.RemoveAt(0);
            }
        }

        private void Change(string item, long change)
        {
            stock[item] = stock.GetValueOrDefault(item) + change;
            _changes[item] = _changes.GetValueOrDefault(item) + change;
        }
    }
}

/// <summary>Sends the trains of routes when they are due, whether or not anyone looks at the stations.</summary>
public sealed class RailwayDispatcher(IServiceScopeFactory scopes, ILogger<RailwayDispatcher> logger) : BackgroundService
{
    public static readonly TimeSpan Period = TimeSpan.FromSeconds(2);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Period);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                // Many due at once (e.g. after a restart) go out a batch per moment.
                await using var scope = scopes.CreateAsyncScope();
                await scope.ServiceProvider.GetRequiredService<StationService>().RunDueRoutesAsync(200, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception e)
            {
                logger.LogWarning(e, "Sending route trains failed");
            }
        }
    }
}

public sealed record StationRequest(int X, int Y);

public sealed record StockRequest(int X, int Y, string Item, long Quantity);

public sealed record SendRequest(int X, int Y, int ToX, int ToY, string Item, long Quantity);

public sealed record RouteRequest(int X, int Y, int ToX, int ToY, List<string>? Items, int EveryMinutes);

public sealed record RemoveRouteRequest(int X, int Y, long Id);

public sealed record FindRequest(string? Query);

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
            sender = s.Sender,
            receiver = s.Receiver,
        };
        return new Reply("station", new
        {
            x = state.X,
            y = state.Y,
            items = state.Items.Select(i => new { id = i.Key, name = Items.Names.GetValueOrDefault(i.Key, i.Key), quantity = i.Value }),
            incoming = state.Incoming.Select(Trip),
            outgoing = state.Outgoing.Select(Trip),
            routes = state.Routes.Select(r => new
            {
                id = r.Id,
                toX = r.ToX,
                toY = r.ToY,
                receiver = r.Receiver,
                items = r.Items.Select(i => new { id = i, name = Items.Names.GetValueOrDefault(i, i) }),
                everyMinutes = r.EveryMinutes,
                nextAt = r.NextAt.ToUnixTimeMilliseconds(),
                lastAt = r.LastAt?.ToUnixTimeMilliseconds(),
                lastQuantity = r.LastQuantity,
                problem = r.Problem,
            }),
            serverTime = state.Now.ToUnixTimeMilliseconds(),
            rates = new
            {
                baseFeeCents = RailRules.BaseFeeCents,
                centsPerItemPer100Km = RailRules.CentsPerItemPer100Km,
                secondsPer100Km = RailRules.SecondsPer100Km,
                minTripSeconds = RailRules.MinTrip.TotalSeconds,
                routeCapacity = RailRules.RouteCapacity,
                routeMinutes = RailRules.RouteMinutes,
                maxRoutes = RailRules.MaxRoutes,
                maxRouteItems = RailRules.MaxRouteItems,
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

public sealed class AddRouteHandler(IServiceScopeFactory scopes) : StationHandler(scopes)
{
    public override string Type => "station.route";

    protected override Task<StationState> RunAsync(StationService station, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var r = Payload.Read<RouteRequest>(payload);
        return station.AddRouteAsync(player, r.X, r.Y, r.ToX, r.ToY, r.Items ?? [], r.EveryMinutes, cancellationToken);
    }
}

public sealed class RemoveRouteHandler(IServiceScopeFactory scopes) : StationHandler(scopes)
{
    public override string Type => "station.unroute";

    protected override Task<StationState> RunAsync(StationService station, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var r = Payload.Read<RemoveRouteRequest>(payload);
        return station.RemoveRouteAsync(player, r.X, r.Y, r.Id, cancellationToken);
    }
}

/// <summary>Other players by name, with their plots, to send trains to.</summary>
public sealed class FindPartnersHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "station.find";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var r = Payload.Read<FindRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var found = await scope.ServiceProvider.GetRequiredService<StationService>().FindAsync(client.RequireAccount(), r.Query ?? "", cancellationToken);
        return new Reply("station.found", new
        {
            query = r.Query ?? "",
            players = found.Select(p => new
            {
                name = p.Name,
                plots = p.Plots.Select(plot => new { x = plot.X, y = plot.Y, biome = (int)plot.Biome }),
            }),
        });
    }
}
