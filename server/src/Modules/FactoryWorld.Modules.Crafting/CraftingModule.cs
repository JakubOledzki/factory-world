using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Crafting;

/// <summary>An order at a workbench, made between <see cref="StartsAt"/> and <see cref="FinishesAt"/>.</summary>
public sealed class CraftingJobRow
{
    public long Id { get; set; }

    public Guid OwnerId { get; set; }

    public string Recipe { get; set; } = "";

    public DateTimeOffset StartsAt { get; set; }

    public DateTimeOffset FinishesAt { get; set; }
}

/// <summary>What a placed furnace holds; keyed by the id of the object in the garage or on the plot.</summary>
public sealed class FurnaceRow
{
    public Guid ObjectId { get; set; }

    public Guid OwnerId { get; set; }

    public string? InputItem { get; set; }

    public int InputQuantity { get; set; }

    public int Fuel { get; set; }

    public int Heat { get; set; }

    public string? OutputItem { get; set; }

    public int OutputQuantity { get; set; }

    public DateTimeOffset? StartedAt { get; set; }
}

public sealed class CraftingDbContext(DbContextOptions<CraftingDbContext> options, GameDb gameDb) : ModuleDbContext(options, gameDb)
{
    public const string Schema = "crafting";

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.HasDefaultSchema(Schema);
        model.Entity<CraftingJobRow>(e =>
        {
            e.ToTable("jobs");
            e.HasKey(j => j.Id);
            e.Property(j => j.Id).HasColumnName("id");
            e.Property(j => j.OwnerId).HasColumnName("owner_id");
            e.Property(j => j.Recipe).HasColumnName("recipe").HasMaxLength(32);
            e.Property(j => j.StartsAt).HasColumnName("starts_at");
            e.Property(j => j.FinishesAt).HasColumnName("finishes_at");
            e.HasIndex(j => new { j.OwnerId, j.FinishesAt });
        });
        model.Entity<FurnaceRow>(e =>
        {
            e.ToTable("furnaces");
            e.HasKey(f => f.ObjectId);
            e.Property(f => f.ObjectId).HasColumnName("object_id");
            e.Property(f => f.OwnerId).HasColumnName("owner_id");
            e.Property(f => f.InputItem).HasColumnName("input_item").HasMaxLength(32);
            e.Property(f => f.InputQuantity).HasColumnName("input_quantity");
            e.Property(f => f.Fuel).HasColumnName("fuel");
            e.Property(f => f.Heat).HasColumnName("heat");
            e.Property(f => f.OutputItem).HasColumnName("output_item").HasMaxLength(32);
            e.Property(f => f.OutputQuantity).HasColumnName("output_quantity");
            e.Property(f => f.StartedAt).HasColumnName("started_at");
        });
    }
}

/// <summary>Making things at a workbench and smelting ore in a furnace. Owns the <c>crafting</c> schema.</summary>
public sealed class CraftingModule : IGameModule
{
    public string Name => "Crafting";

    public void RegisterServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddModuleDbContext<CraftingDbContext>(CraftingDbContext.Schema);
        services.AddScoped<CraftingService>();
        services.AddScoped<FurnaceService>();
        services.AddScoped<IMachineContents, FurnaceContents>();
        services.AddSingleton<IMessageHandler, GetCraftingHandler>();
        services.AddSingleton<IMessageHandler, CraftHandler>();
        services.AddSingleton<IMessageHandler, CancelCraftHandler>();
        services.AddSingleton<IMessageHandler, GetFurnaceHandler>();
        services.AddSingleton<IMessageHandler, LoadFurnaceHandler>();
        services.AddSingleton<IMessageHandler, TakeFurnaceHandler>();
    }

    public Task InitializeAsync(IServiceProvider services, CancellationToken cancellationToken) =>
        services.MigrateModuleAsync<CraftingDbContext>(cancellationToken);
}
