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
        });
    }
}

public sealed class InventoryService(GameDb db) : IInventory
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

    public async Task RemoveAsync(Guid owner, string item, long quantity, CancellationToken cancellationToken)
    {
        Check(item, quantity);
        // One conditional update: two requests at once can never take more than the player has.
        await using var command = await db.CommandAsync(
            """
            UPDATE inventory.stacks SET quantity = quantity - @quantity
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

    public async Task<IReadOnlyList<Stack>> ListAsync(Guid owner, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT item_id, quantity FROM inventory.stacks WHERE owner_id = @owner AND quantity > 0 ORDER BY item_id", cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var stacks = new List<Stack>();
        while (await reader.ReadAsync(cancellationToken))
        {
            stacks.Add(new Stack { OwnerId = owner, ItemId = reader.GetString(0), Quantity = reader.GetInt64(1) });
        }

        return stacks;
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
        var stacks = await scope.ServiceProvider.GetRequiredService<InventoryService>().ListAsync(client.RequireAccount(), cancellationToken);
        return new Reply("inventory", new
        {
            items = stacks.Select(s => new { id = s.ItemId, name = Items.Names[s.ItemId], quantity = s.Quantity }),
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
    }

    public Task InitializeAsync(IServiceProvider services, CancellationToken cancellationToken) =>
        services.MigrateModuleAsync<InventoryDbContext>(cancellationToken);
}
