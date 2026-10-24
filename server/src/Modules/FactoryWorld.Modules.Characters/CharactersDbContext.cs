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

    /// <summary>The item in the first slot of the tool bar, or null.</summary>
    public string? Tool { get; set; }

    /// <summary>The item in the second slot of the tool bar (there with a backpack), or null.</summary>
    public string? Tool2 { get; set; }

    /// <summary>The item in the third slot of the tool bar (there with the best backpack), or null.</summary>
    public string? Tool3 { get; set; }

    /// <summary>The backpack worn, or null.</summary>
    public string? Backpack { get; set; }

    /// <summary>What is in each slot of the tool bar the character has now.</summary>
    public IReadOnlyList<string?> Tools => new[] { Tool, Tool2, Tool3 }[..Equipment.ToolSlots(Backpack)];

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
            e.Property(c => c.Tool).HasMaxLength(32);
            e.Property(c => c.Tool2).HasMaxLength(32);
            e.Property(c => c.Tool3).HasMaxLength(32);
            e.Property(c => c.Backpack).HasMaxLength(32);
            e.Ignore(c => c.Tools);
            e.ComplexProperty(c => c.Appearance, a => a.ToJson());
        });
    }
}
