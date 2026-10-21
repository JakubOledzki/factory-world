using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.World;

/// <param name="Item">The crop is harvested as this item, so its id is the item's.</param>
/// <param name="Yield">Items one ripe field gives.</param>
public sealed record Crop(string Item, TimeSpan Grow, int Yield, int Xp);

/// <summary>
/// Fertile plots can be farmed: the hoe tills a free tile into a field, a crop is sown on the field
/// and grows for its own time, then it is reaped by hand and the field can be sown again.
/// </summary>
public static class Farming
{
    /// <summary>Every crop, in the order the client lists them.</summary>
    public static readonly IReadOnlyList<Crop> Crops =
    [
        new(Items.Wheat, TimeSpan.FromMinutes(5), 4, 3),
        new(Items.Carrot, TimeSpan.FromMinutes(7), 4, 4),
        new(Items.Cabbage, TimeSpan.FromMinutes(8), 2, 4),
        new(Items.Corn, TimeSpan.FromMinutes(10), 3, 5),
        new(Items.Potato, TimeSpan.FromMinutes(15), 5, 7),
        new(Items.Sunflower, TimeSpan.FromMinutes(20), 3, 9),
    ];

    public static readonly IReadOnlyDictionary<string, Crop> ById = Crops.ToDictionary(c => c.Item);

    /// <summary>Only fertile soil can be tilled.</summary>
    public static bool Fertile(Biome biome) => biome == Biome.Farmland;

    public const int XpPerTill = 1;
}

/// <param name="Crop">Null on a tilled field nothing grows on yet.</param>
public sealed record Field(int TileX, int TileY, string? Crop, DateTimeOffset? ReadyAt);

/// <param name="Items">What reaping gave; empty when tilling or sowing.</param>
/// <param name="Xp">Null when the action gives no experience.</param>
public sealed record FieldChange(Field Field, IReadOnlyList<(string Item, int Quantity)> Items, XpGain? Xp);

public sealed class FarmService(GameDb db, PlotService plots, IInventory inventory, IEquipment equipment, ICharacterProgress progress, TimeProvider time)
{
    public async Task<IReadOnlyList<Field>> FieldsAsync(int x, int y, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT tile_x, tile_y, crop, planted_at FROM world.plot_fields WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var fields = new List<Field>();
        while (await reader.ReadAsync(cancellationToken))
        {
            fields.Add(Read(reader.GetInt32(0), reader.GetInt32(1),
                reader.IsDBNull(2) ? null : reader.GetString(2), reader.IsDBNull(3) ? null : reader.GetFieldValue<DateTimeOffset>(3)));
        }

        return fields;
    }

    /// <summary>Turns a free tile of a fertile plot into a field, with the hoe in hand.</summary>
    public Task<FieldChange> TillAsync(Guid player, int x, int y, int tileX, int tileY, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var biome = await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            if (!Farming.Fertile(biome))
            {
                throw new GameException("not_fertile", "Only fertile soil can be tilled.");
            }

            if (await equipment.ToolAsync(player, cancellationToken) != Items.Hoe)
            {
                throw new GameException("wrong_tool", "You need a hoe in your hand.");
            }

            if (!await plots.FreeAsync(player, x, y, tileX, tileY, cancellationToken))
            {
                throw new GameException("blocked", "Something stands here.");
            }

            await using (var insert = await db.CommandAsync(
                "INSERT INTO world.plot_fields (x, y, tile_x, tile_y) VALUES (@x, @y, @tx, @ty) ON CONFLICT DO NOTHING", cancellationToken))
            {
                Bind(insert, x, y, tileX, tileY);
                if (await insert.ExecuteNonQueryAsync(cancellationToken) == 0)
                {
                    throw new GameException("blocked", "This is already a field.");
                }
            }

            var xp = await progress.AddXpAsync(player, Farming.XpPerTill, cancellationToken);
            return new FieldChange(new Field(tileX, tileY, null, null), [], xp);
        }, cancellationToken);

    /// <summary>Sows a crop on an empty field.</summary>
    public Task<FieldChange> PlantAsync(Guid player, int x, int y, int tileX, int tileY, string crop, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (!Farming.ById.ContainsKey(crop))
            {
                throw new GameException("unknown_crop", "There is no such crop.");
            }

            await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            var now = time.GetUtcNow();
            await using var update = await db.CommandAsync(
                """
                UPDATE world.plot_fields SET crop = @crop, planted_at = @now
                WHERE x = @x AND y = @y AND tile_x = @tx AND tile_y = @ty AND crop IS NULL
                """, cancellationToken);
            Bind(update, x, y, tileX, tileY);
            update.Parameters.AddWithValue("crop", crop);
            update.Parameters.AddWithValue("now", now);
            if (await update.ExecuteNonQueryAsync(cancellationToken) == 0)
            {
                throw new GameException("no_field", "Till the ground first, or reap what grows here.");
            }

            return new FieldChange(Read(tileX, tileY, crop, now), [], null);
        }, cancellationToken);

    /// <summary>Gathers a ripe crop by hand; the field stays tilled.</summary>
    public Task<FieldChange> ReapAsync(Guid player, int x, int y, int tileX, int tileY, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            string crop;
            DateTimeOffset planted;
            await using (var select = await db.CommandAsync(
                """
                SELECT crop, planted_at FROM world.plot_fields
                WHERE x = @x AND y = @y AND tile_x = @tx AND tile_y = @ty AND crop IS NOT NULL
                FOR UPDATE
                """, cancellationToken))
            {
                Bind(select, x, y, tileX, tileY);
                await using var reader = await select.ExecuteReaderAsync(cancellationToken);
                if (!await reader.ReadAsync(cancellationToken))
                {
                    throw new GameException("nothing_here", "Nothing grows here.");
                }

                crop = reader.GetString(0);
                planted = reader.GetFieldValue<DateTimeOffset>(1);
            }

            var info = Farming.ById[crop];
            if (planted + info.Grow > time.GetUtcNow())
            {
                throw new GameException("not_ripe", "It is not ripe yet.");
            }

            await using (var clear = await db.CommandAsync(
                "UPDATE world.plot_fields SET crop = NULL, planted_at = NULL WHERE x = @x AND y = @y AND tile_x = @tx AND tile_y = @ty", cancellationToken))
            {
                Bind(clear, x, y, tileX, tileY);
                await clear.ExecuteNonQueryAsync(cancellationToken);
            }

            await inventory.AddAsync(player, crop, info.Yield, cancellationToken);
            var xp = await progress.AddXpAsync(player, info.Xp, cancellationToken);
            return new FieldChange(new Field(tileX, tileY, null, null), [(crop, info.Yield)], xp);
        }, cancellationToken);

    private static Field Read(int tileX, int tileY, string? crop, DateTimeOffset? planted) =>
        new(tileX, tileY, crop, crop is not null && planted is { } at && Farming.ById.TryGetValue(crop, out var info) ? at + info.Grow : null);

    private static void Bind(Npgsql.NpgsqlCommand command, int x, int y, int tileX, int tileY)
    {
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        command.Parameters.AddWithValue("tx", tileX);
        command.Parameters.AddWithValue("ty", tileY);
    }
}

public sealed record FieldRequest(int X, int Y, int TileX, int TileY, string? Crop);

/// <summary>plot.till, plot.plant and plot.reap all answer with the changed field.</summary>
public abstract class FieldHandler(IServiceScopeFactory scopes, TimeProvider time) : IMessageHandler
{
    public abstract string Type { get; }

    protected TimeProvider Time => time;

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<FieldRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var change = await RunAsync(scope.ServiceProvider.GetRequiredService<FarmService>(), client, request, cancellationToken);
        return new Reply("plot.field", new
        {
            field = FieldJson(change.Field),
            items = change.Items.Select(i => new { id = i.Item, name = Items.Names[i.Item], quantity = i.Quantity }),
            xp = change.Xp is { } xp ? new { xp = xp.Xp, level = xp.Level, leveledUp = xp.LeveledUp } : null,
            serverTime = time.GetUtcNow().ToUnixTimeMilliseconds(),
        });
    }

    protected abstract Task<FieldChange> RunAsync(FarmService farm, ClientContext client, FieldRequest request, CancellationToken cancellationToken);

    public static object FieldJson(Field field) => new
    {
        tileX = field.TileX,
        tileY = field.TileY,
        crop = field.Crop,
        readyAt = field.ReadyAt?.ToUnixTimeMilliseconds(),
    };
}

public sealed class TillHandler(IServiceScopeFactory scopes, TimeProvider time) : FieldHandler(scopes, time)
{
    public override string Type => "plot.till";

    protected override async Task<FieldChange> RunAsync(FarmService farm, ClientContext client, FieldRequest r, CancellationToken cancellationToken)
    {
        // Tilling is a swing of a tool like chopping, with the same pace.
        HarvestHandler.CheckPace(client, Time, HarvestRules.Time);
        var change = await farm.TillAsync(client.RequireAccount(), r.X, r.Y, r.TileX, r.TileY, cancellationToken);
        HarvestHandler.Swung(client, Time);
        return change;
    }
}

public sealed class PlantHandler(IServiceScopeFactory scopes, TimeProvider time) : FieldHandler(scopes, time)
{
    public override string Type => "plot.plant";

    protected override Task<FieldChange> RunAsync(FarmService farm, ClientContext client, FieldRequest r, CancellationToken cancellationToken) =>
        farm.PlantAsync(client.RequireAccount(), r.X, r.Y, r.TileX, r.TileY, r.Crop ?? "", cancellationToken);
}

public sealed class ReapHandler(IServiceScopeFactory scopes, TimeProvider time) : FieldHandler(scopes, time)
{
    public override string Type => "plot.reap";

    protected override Task<FieldChange> RunAsync(FarmService farm, ClientContext client, FieldRequest r, CancellationToken cancellationToken) =>
        farm.ReapAsync(client.RequireAccount(), r.X, r.Y, r.TileX, r.TileY, cancellationToken);
}
