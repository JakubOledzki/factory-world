using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;

namespace FactoryWorld.Modules.Characters;

public sealed class Equipment(GameDb db, IInventory inventory) : IEquipment
{
    public async Task<string?> ToolAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """SELECT "Tool" FROM characters.characters WHERE "AccountId" = @account""", cancellationToken);
        command.Parameters.AddWithValue("account", accountId);
        return await command.ExecuteScalarAsync(cancellationToken) as string;
    }

    public Task GiveToolAsync(Guid accountId, string tool, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            await using var command = await db.CommandAsync(
                """UPDATE characters.characters SET "Tool" = @tool WHERE "AccountId" = @account AND "Tool" IS NULL""", cancellationToken);
            command.Parameters.AddWithValue("tool", tool);
            command.Parameters.AddWithValue("account", accountId);
            if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
            {
                await inventory.AddAsync(accountId, tool, 1, cancellationToken);
            }
        }, cancellationToken);

    /// <summary>Swaps the tool in the slot for one from the inventory, or empties the slot when <paramref name="tool"/> is null.</summary>
    public Task EquipAsync(Guid accountId, string? tool, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (tool is not null && !Items.IsTool(tool))
            {
                throw new GameException("not_a_tool", "Only tools fit in the tool slot.");
            }

            await using var current = await db.CommandAsync(
                """SELECT "Tool" FROM characters.characters WHERE "AccountId" = @account FOR UPDATE""", cancellationToken);
            current.Parameters.AddWithValue("account", accountId);
            var held = await current.ExecuteScalarAsync(cancellationToken);
            if (held is null)
            {
                throw new GameException("no_character", "Create a character first.");
            }

            if (tool is not null)
            {
                await inventory.RemoveAsync(accountId, tool, 1, cancellationToken);
            }

            if (held is string old)
            {
                await inventory.AddAsync(accountId, old, 1, cancellationToken);
            }

            await using var update = await db.CommandAsync(
                """UPDATE characters.characters SET "Tool" = @tool WHERE "AccountId" = @account""", cancellationToken);
            update.Parameters.AddWithValue("tool", (object?)tool ?? DBNull.Value);
            update.Parameters.AddWithValue("account", accountId);
            await update.ExecuteNonQueryAsync(cancellationToken);
        }, cancellationToken);
}
