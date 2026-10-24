using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.EntityFrameworkCore;

namespace FactoryWorld.Modules.Characters;

public sealed class CharacterLooks(CharactersDbContext db) : ICharacterLooks
{
    public async Task<IReadOnlyDictionary<Guid, CharacterLook>> LooksAsync(IReadOnlyCollection<Guid> accountIds, CancellationToken cancellationToken)
    {
        if (accountIds.Count == 0)
        {
            return new Dictionary<Guid, CharacterLook>();
        }

        var ids = accountIds.ToArray();
        var characters = await db.Characters.AsNoTracking()
            .Where(c => ids.Contains(c.AccountId))
            .Select(c => new { c.AccountId, c.Name, c.Appearance })
            .ToListAsync(cancellationToken);
        return characters.ToDictionary(c => c.AccountId, c => new CharacterLook(c.Name, c.Appearance));
    }
}
