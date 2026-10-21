using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;

namespace FactoryWorld.Modules.Characters;

public sealed class CharacterNames(GameDb db) : ICharacterNames
{
    public async Task<IReadOnlyDictionary<Guid, string>> NamesAsync(IReadOnlyCollection<Guid> accountIds, CancellationToken cancellationToken)
    {
        var names = new Dictionary<Guid, string>();
        if (accountIds.Count == 0)
        {
            return names;
        }

        await using var command = await db.CommandAsync(
            """SELECT "AccountId", "Name" FROM characters.characters WHERE "AccountId" = ANY(@accounts)""", cancellationToken);
        command.Parameters.AddWithValue("accounts", accountIds.ToArray());
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            names[reader.GetGuid(0)] = reader.GetString(1);
        }

        return names;
    }
}
