using FactoryWorld.Modules.Abstractions;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace FactoryWorld.Modules.Characters;

public sealed class CharacterService(CharactersDbContext db, TimeProvider time)
{
    public Task<Character?> FindAsync(Guid accountId, CancellationToken cancellationToken) =>
        db.Characters.AsNoTracking().SingleOrDefaultAsync(c => c.AccountId == accountId, cancellationToken);

    public async Task<Character> CreateAsync(Guid accountId, string name, Appearance appearance, CancellationToken cancellationToken)
    {
        name = name.Trim();
        if (!CharacterRules.IsValidName(name))
        {
            throw new GameException("invalid_name",
                $"Name must be {CharacterRules.MinNameLength}-{CharacterRules.MaxNameLength} letters, digits or _.");
        }

        if (!AppearanceCatalog.IsValid(appearance))
        {
            throw new GameException("invalid_appearance", "Unknown appearance option.");
        }

        var character = new Character
        {
            Id = Guid.NewGuid(),
            AccountId = accountId,
            Name = name,
            NormalizedName = name.ToLowerInvariant(),
            Appearance = appearance,
            CreatedAt = time.GetUtcNow(),
        };
        db.Characters.Add(character);

        try
        {
            await db.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException ex) when (ex.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation } pg)
        {
            throw pg.ConstraintName?.Contains("account", StringComparison.OrdinalIgnoreCase) == true
                ? new GameException("character_exists", "This account already has a character.")
                : new GameException("name_taken", "This name is already taken.");
        }

        return character;
    }
}
