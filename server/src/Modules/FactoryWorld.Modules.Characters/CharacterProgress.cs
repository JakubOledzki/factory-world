using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;

namespace FactoryWorld.Modules.Characters;

public sealed class CharacterProgress(GameDb db) : ICharacterProgress
{
    public async Task<XpGain> AddXpAsync(Guid accountId, long xp, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """
            UPDATE characters.characters SET "Xp" = "Xp" + @xp
            WHERE "AccountId" = @account
            RETURNING "Xp"
            """, cancellationToken);
        command.Parameters.AddWithValue("xp", xp);
        command.Parameters.AddWithValue("account", accountId);

        if (await command.ExecuteScalarAsync(cancellationToken) is not long total)
        {
            throw new GameException("no_character", "Create a character first.");
        }

        var level = Leveling.LevelForXp(total);
        return new XpGain(total, level, level > Leveling.LevelForXp(total - xp));
    }
}
