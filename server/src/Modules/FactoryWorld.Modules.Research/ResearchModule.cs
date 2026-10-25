using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Research;

/// <summary>A technology a player started researching; it is theirs from <see cref="FinishesAt"/> on.</summary>
public sealed class ResearchRow
{
    public Guid OwnerId { get; set; }

    public string Technology { get; set; } = "";

    public DateTimeOffset StartsAt { get; set; }

    public DateTimeOffset FinishesAt { get; set; }

    /// <summary>Whether the XP for it was handed out.</summary>
    public bool Rewarded { get; set; }
}

public sealed class ResearchDbContext(DbContextOptions<ResearchDbContext> options, GameDb gameDb) : ModuleDbContext(options, gameDb)
{
    public const string Schema = "research";

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.HasDefaultSchema(Schema);
        model.Entity<ResearchRow>(e =>
        {
            e.ToTable("technologies");
            e.HasKey(r => new { r.OwnerId, r.Technology });
            e.Property(r => r.OwnerId).HasColumnName("owner_id");
            e.Property(r => r.Technology).HasColumnName("technology").HasMaxLength(32);
            e.Property(r => r.StartsAt).HasColumnName("starts_at");
            e.Property(r => r.FinishesAt).HasColumnName("finishes_at");
            e.Property(r => r.Rewarded).HasColumnName("rewarded");
        });
    }
}

/// <summary>The technology tree: research that unlocks recipes, machines and the trader's goods. Owns the <c>research</c> schema.</summary>
public sealed class ResearchModule : IGameModule
{
    public string Name => "Research";

    public void RegisterServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddModuleDbContext<ResearchDbContext>(ResearchDbContext.Schema);
        services.AddScoped<ResearchService>();
        services.AddScoped<ITechnologies>(provider => provider.GetRequiredService<ResearchService>());
        services.AddSingleton<IMessageHandler, GetResearchHandler>();
        services.AddSingleton<IMessageHandler, StartResearchHandler>();
        services.AddSingleton<IMessageHandler, CancelResearchHandler>();
        services.AddSingleton<IMessageHandler, BoostResearchHandler>();
    }

    public Task InitializeAsync(IServiceProvider services, CancellationToken cancellationToken) =>
        services.MigrateModuleAsync<ResearchDbContext>(cancellationToken);
}
