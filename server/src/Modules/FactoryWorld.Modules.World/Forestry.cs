using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.World;

/// <summary>
/// A sapling bought on the market is planted on a free tile of a plot and grows into a tree, which
/// is cut with an axe like the trees that grew there by themselves: wood and, usually, a new sapling.
/// </summary>
public static class Forestry
{
    /// <summary>How long a sapling grows on a plot without a forestry bonus.</summary>
    public static readonly TimeSpan Grow = TimeSpan.FromMinutes(10);

    /// <summary>Chance (percent) that a cut tree drops a sapling.</summary>
    public const int SaplingChance = 80;

    public const int XpPerPlanting = 1;

    /// <summary>
    /// The biome's forestry bonus in percent, as the map lists it: a forest grows trees 25% faster,
    /// a city 50% slower, and nothing grows on ice (null).
    /// </summary>
    public static int? BonusPercent(Biome biome) => biome switch
    {
        Biome.Forest => 25,
        Biome.City => -50,
        Biome.Ice => null,
        _ => 0,
    };

    /// <summary>How long a sapling grows on a plot of a biome; null when trees cannot be planted there.</summary>
    public static TimeSpan? GrowTime(Biome biome) => BonusPercent(biome) is { } bonus ? Grow * (100 - bonus) / 100.0 : null;
}

/// <param name="ReadyAt">When the tree can be cut.</param>
public sealed record PlantedTree(int TileX, int TileY, DateTimeOffset ReadyAt);

public sealed class ForestService(GameDb db, PlotService plots, IInventory inventory, ICharacterProgress progress, TimeProvider time)
{
    public async Task<IReadOnlyList<PlantedTree>> TreesAsync(int x, int y, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT tile_x, tile_y, ready_at FROM world.plot_trees WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var trees = new List<PlantedTree>();
        while (await reader.ReadAsync(cancellationToken))
        {
            trees.Add(new PlantedTree(reader.GetInt32(0), reader.GetInt32(1), reader.GetFieldValue<DateTimeOffset>(2)));
        }

        return trees;
    }

    /// <summary>Plants a sapling from the inventory on a free tile of the player's plot.</summary>
    public Task<(PlantedTree Tree, XpGain Xp)> PlantAsync(Guid player, int x, int y, int tileX, int tileY, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var biome = await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            var grow = Forestry.GrowTime(biome) ?? throw new GameException("no_forestry", "Nothing grows on ice.");
            if (!await plots.FreeAsync(player, x, y, tileX, tileY, cancellationToken))
            {
                throw new GameException("blocked", "Something stands here.");
            }

            await inventory.RemoveAsync(player, Items.Sapling, 1, cancellationToken);
            var tree = new PlantedTree(tileX, tileY, time.GetUtcNow() + grow);
            await using (var insert = await db.CommandAsync(
                "INSERT INTO world.plot_trees (x, y, tile_x, tile_y, ready_at) VALUES (@x, @y, @tx, @ty, @ready) ON CONFLICT DO NOTHING",
                cancellationToken))
            {
                insert.Parameters.AddWithValue("x", x);
                insert.Parameters.AddWithValue("y", y);
                insert.Parameters.AddWithValue("tx", tileX);
                insert.Parameters.AddWithValue("ty", tileY);
                insert.Parameters.AddWithValue("ready", tree.ReadyAt);
                if (await insert.ExecuteNonQueryAsync(cancellationToken) == 0)
                {
                    throw new GameException("blocked", "A tree is already growing here.");
                }
            }

            var xp = await progress.AddXpAsync(player, Forestry.XpPerPlanting, cancellationToken);
            return (tree, xp);
        }, cancellationToken);
}

public sealed record PlantTreeRequest(int X, int Y, int TileX, int TileY);

public sealed class PlantTreeHandler(IServiceScopeFactory scopes, TimeProvider time) : IMessageHandler
{
    public string Type => "plot.plantTree";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<PlantTreeRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var (tree, xp) = await scope.ServiceProvider.GetRequiredService<ForestService>()
            .PlantAsync(client.RequireAccount(), request.X, request.Y, request.TileX, request.TileY, cancellationToken);
        return new Reply("plot.tree", new
        {
            tree = TreeJson(tree),
            xp = new { xp = xp.Xp, level = xp.Level, leveledUp = xp.LeveledUp },
            serverTime = time.GetUtcNow().ToUnixTimeMilliseconds(),
        });
    }

    public static object TreeJson(PlantedTree tree) => new
    {
        tileX = tree.TileX,
        tileY = tree.TileY,
        readyAt = tree.ReadyAt.ToUnixTimeMilliseconds(),
    };
}
