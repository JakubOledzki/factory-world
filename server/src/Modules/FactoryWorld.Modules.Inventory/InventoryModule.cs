using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Inventory;

/// <summary>How many of one item a player owns.</summary>
public sealed class Stack
{
    public Guid OwnerId { get; set; }

    public required string ItemId { get; set; }

    public long Quantity { get; set; }

    /// <summary>The tile of the inventory grid the player put the item on; null until it is shown.</summary>
    public int? Slot { get; set; }
}

public sealed class InventoryDbContext(DbContextOptions<InventoryDbContext> options, GameDb gameDb) : ModuleDbContext(options, gameDb)
{
    public const string Schema = "inventory";

    public DbSet<Stack> Stacks => Set<Stack>();

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.HasDefaultSchema(Schema);
        model.Entity<Stack>(e =>
        {
            e.ToTable("stacks", t => t.HasCheckConstraint("ck_stacks_quantity", "quantity >= 0"));
            e.HasKey(s => new { s.OwnerId, s.ItemId });
            e.Property(s => s.OwnerId).HasColumnName("owner_id");
            e.Property(s => s.ItemId).HasColumnName("item_id").HasMaxLength(64);
            e.Property(s => s.Quantity).HasColumnName("quantity");
            e.Property(s => s.Slot).HasColumnName("slot");
        });
    }
}

/// <summary>The player's items. Each kind takes one tile of the grid, however many there are; the grid
/// has <see cref="IInventorySize"/> tiles. More kinds than tiles can be there (things given back),
/// but nothing new comes in through <see cref="ReceiveAsync"/> until a tile is free.</summary>
public sealed class InventoryService(GameDb db, IInventorySize size) : IInventory
{

    public async Task AddAsync(Guid owner, string item, long quantity, CancellationToken cancellationToken)
    {
        Check(item, quantity);
        await using var command = await db.CommandAsync(
            """
            INSERT INTO inventory.stacks (owner_id, item_id, quantity) VALUES (@owner, @item, @quantity)
            ON CONFLICT (owner_id, item_id) DO UPDATE SET quantity = stacks.quantity + excluded.quantity
            """, cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        command.Parameters.AddWithValue("item", item);
        command.Parameters.AddWithValue("quantity", quantity);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task ReceiveAsync(Guid owner, string item, long quantity, CancellationToken cancellationToken)
    {
        Check(item, quantity);
        if (await CountAsync(owner, item, cancellationToken) == 0)
        {
            await using var command = await db.CommandAsync(
                "SELECT count(*) FROM inventory.stacks WHERE owner_id = @owner AND quantity > 0", cancellationToken);
            command.Parameters.AddWithValue("owner", owner);
            if ((long)(await command.ExecuteScalarAsync(cancellationToken))! >= await size.SlotsAsync(owner, cancellationToken))
            {
                throw new GameException("inventory_full", "Your inventory is full: make room or put on a bigger backpack.");
            }
        }

        await AddAsync(owner, item, quantity, cancellationToken);
    }

    /// <summary>Tiles of the player's inventory grid; items can be moved to any of them.</summary>
    public Task<int> SlotsAsync(Guid owner, CancellationToken cancellationToken) => size.SlotsAsync(owner, cancellationToken);

    public async Task RemoveAsync(Guid owner, string item, long quantity, CancellationToken cancellationToken)
    {
        Check(item, quantity);
        // One conditional update: two requests at once can never take more than the player has.
        // An emptied stack frees its tile; the item gets a new one when the player gets it again.
        await using var command = await db.CommandAsync(
            """
            UPDATE inventory.stacks SET quantity = quantity - @quantity,
                slot = CASE WHEN quantity = @quantity THEN NULL ELSE slot END
            WHERE owner_id = @owner AND item_id = @item AND quantity >= @quantity
            """, cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        command.Parameters.AddWithValue("item", item);
        command.Parameters.AddWithValue("quantity", quantity);
        if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
        {
            throw new GameException("not_enough_items", "You don't have enough of this item.");
        }
    }

    public async Task<long> CountAsync(Guid owner, string item, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT quantity FROM inventory.stacks WHERE owner_id = @owner AND item_id = @item", cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        command.Parameters.AddWithValue("item", item);
        return await command.ExecuteScalarAsync(cancellationToken) is long n ? n : 0;
    }

    /// <summary>The player's items in tile order. Items without a tile get the first free ones, which are saved.</summary>
    public async Task<IReadOnlyList<Stack>> ListAsync(Guid owner, CancellationToken cancellationToken)
    {
        var stacks = new List<Stack>();
        await using (var command = await db.CommandAsync(
            "SELECT item_id, quantity, slot FROM inventory.stacks WHERE owner_id = @owner AND quantity > 0 ORDER BY slot NULLS LAST, item_id", cancellationToken))
        {
            command.Parameters.AddWithValue("owner", owner);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                stacks.Add(new Stack
                {
                    OwnerId = owner,
                    ItemId = reader.GetString(0),
                    Quantity = reader.GetInt64(1),
                    Slot = reader.IsDBNull(2) ? null : reader.GetInt32(2),
                });
            }
        }

        var slots = await size.SlotsAsync(owner, cancellationToken);
        var taken = new HashSet<int>();
        var placed = new List<Stack>();
        var overflow = slots;
        foreach (var stack in stacks)
        {
            // A tile out of the grid or taken twice (two requests at once) counts as no tile.
            if (stack.Slot is not { } slot || slot < 0 || slot >= slots || !taken.Add(slot))
            {
                stack.Slot = null;
            }
        }

        foreach (var stack in stacks.Where(s => s.Slot is null))
        {
            var free = Enumerable.Range(0, slots).FirstOrDefault(i => !taken.Contains(i), -1);
            if (free < 0)
            {
                // More items than tiles: the rest go after the grid, unsaved.
                stack.Slot = overflow++;
                continue;
            }

            taken.Add(free);
            stack.Slot = free;
            placed.Add(stack);
        }

        foreach (var stack in placed)
        {
            await using var command = await db.CommandAsync(
                "UPDATE inventory.stacks SET slot = @slot WHERE owner_id = @owner AND item_id = @item", cancellationToken);
            command.Parameters.AddWithValue("owner", owner);
            command.Parameters.AddWithValue("item", stack.ItemId);
            command.Parameters.AddWithValue("slot", stack.Slot!.Value);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        return stacks.OrderBy(s => s.Slot).ToList();
    }

    /// <summary>Puts an item on another tile; an item already there swaps places with it.</summary>
    public async Task MoveAsync(Guid owner, string item, int slot, CancellationToken cancellationToken)
    {
        if (!Items.Exists(item))
        {
            throw new GameException("unknown_item", $"Unknown item '{item}'.");
        }

        var slots = await size.SlotsAsync(owner, cancellationToken);
        if (slot < 0 || slot >= slots)
        {
            throw new GameException("bad_slot", $"The inventory has tiles 0 to {slots - 1}.");
        }

        // Tiles are given when the inventory is listed; this makes sure the moved item has one to swap.
        await ListAsync(owner, cancellationToken);
        // One statement: the sub-select sees the tiles from before the update, so the swap is atomic.
        await using var command = await db.CommandAsync(
            """
            UPDATE inventory.stacks SET slot = CASE WHEN item_id = @item THEN @slot
                ELSE (SELECT s.slot FROM inventory.stacks s WHERE s.owner_id = @owner AND s.item_id = @item) END
            WHERE owner_id = @owner AND quantity > 0 AND (item_id = @item OR slot = @slot)
                AND EXISTS (SELECT 1 FROM inventory.stacks s WHERE s.owner_id = @owner AND s.item_id = @item AND s.quantity > 0)
            """, cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        command.Parameters.AddWithValue("item", item);
        command.Parameters.AddWithValue("slot", slot);
        if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
        {
            throw new GameException("not_enough_items", "You don't have this item.");
        }
    }

    private static void Check(string item, long quantity)
    {
        if (!Items.Exists(item))
        {
            throw new GameException("unknown_item", $"Unknown item '{item}'.");
        }

        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(quantity);
    }
}

public sealed class GetInventoryHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "inventory.get";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        return await InventoryReply.CreateAsync(scope.ServiceProvider.GetRequiredService<InventoryService>(), client.RequireAccount(), cancellationToken);
    }
}

public sealed class MoveItemHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "inventory.move";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var account = client.RequireAccount();
        var request = Payload.Read<MoveItemRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var inventory = scope.ServiceProvider.GetRequiredService<InventoryService>();
        await inventory.MoveAsync(account, request.Item ?? "", request.Slot, cancellationToken);
        return await InventoryReply.CreateAsync(inventory, account, cancellationToken);
    }

    private sealed record MoveItemRequest(string? Item, int Slot);
}

internal static class InventoryReply
{
    public static async Task<Reply> CreateAsync(InventoryService inventory, Guid account, CancellationToken cancellationToken)
    {
        var stacks = await inventory.ListAsync(account, cancellationToken);
        return new Reply("inventory", new
        {
            slots = await inventory.SlotsAsync(account, cancellationToken),
            items = stacks.Select(s => new { id = s.ItemId, name = Items.Names[s.ItemId], quantity = s.Quantity, slot = s.Slot }),
        });
    }
}

/// <summary>Items players own. Owns the <c>inventory</c> schema.</summary>
public sealed class InventoryModule : IGameModule
{
    public string Name => "Inventory";

    public void RegisterServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddModuleDbContext<InventoryDbContext>(InventoryDbContext.Schema);
        services.AddScoped<InventoryService>();
        services.AddScoped<IInventory>(sp => sp.GetRequiredService<InventoryService>());
        services.AddSingleton<IMessageHandler, GetInventoryHandler>();
        services.AddSingleton<IMessageHandler, MoveItemHandler>();
    }

    public Task InitializeAsync(IServiceProvider services, CancellationToken cancellationToken) =>
        services.MigrateModuleAsync<InventoryDbContext>(cancellationToken);
}
