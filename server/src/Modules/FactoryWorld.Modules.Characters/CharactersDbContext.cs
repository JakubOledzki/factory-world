using FactoryWorld.Modules.Abstractions;
using Microsoft.EntityFrameworkCore;

namespace FactoryWorld.Modules.Characters;

public sealed class Character
{
    public Guid Id { get; set; }

    /// <summary>One character per account for now.</summary>
    public Guid AccountId { get; set; }

    public required string Name { get; set; }

    /// <summary>Lower-cased name, unique, so "Kuba" and "kuba" cannot both exist.</summary>
    public required string NormalizedName { get; set; }

    public required Appearance Appearance { get; set; }

    public long Xp { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
}

public sealed class CharactersDbContext(DbContextOptions<CharactersDbContext> options, GameDb gameDb) : ModuleDbContext(options, gameDb)
{
    public const string Schema = "characters";

    public DbSet<Character> Characters => Set<Character>();

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.HasDefaultSchema(Schema);

        model.Entity<Character>(e =>
        {
            e.ToTable("characters");
            e.HasIndex(c => c.AccountId).IsUnique();
            e.HasIndex(c => c.NormalizedName).IsUnique();
            e.Property(c => c.Name).HasMaxLength(CharacterRules.MaxNameLength);
            e.Property(c => c.NormalizedName).HasMaxLength(CharacterRules.MaxNameLength);
            e.ComplexProperty(c => c.Appearance, a => a.ToJson());
        });
    }
}
