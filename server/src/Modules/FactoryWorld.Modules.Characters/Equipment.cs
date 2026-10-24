using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;

namespace FactoryWorld.Modules.Characters;

/// <summary>What the character has on: tools in the tool bar and a backpack.</summary>
public sealed class Equipment(GameDb db, IInventory inventory) : IEquipment
{
    /// <summary>The columns of the tool bar's slots, in order.</summary>
    private static readonly string[] Slots = ["Tool", "Tool2", "Tool3"];

    /// <summary>Slots of the tool bar with this backpack worn (or none).</summary>
    public static int ToolSlots(string? backpack) =>
        backpack is not null && Items.Backpacks.TryGetValue(backpack, out var b) ? b.ToolSlots : Items.ToolSlots;

    public async Task<IReadOnlyList<string>> ToolsAsync(Guid accountId, CancellationToken cancellationToken) =>
        await ReadAsync(accountId, false, cancellationToken) is { } worn
            ? worn.Tools.Take(ToolSlots(worn.Backpack)).OfType<string>().ToList()
            : [];

    public Task GiveToolAsync(Guid accountId, string tool, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (await ReadAsync(accountId, true, cancellationToken) is { } worn
                && Array.FindIndex(worn.Tools, 0, ToolSlots(worn.Backpack), t => t is null) is var free and >= 0)
            {
                await SetAsync(accountId, Slots[free], tool, cancellationToken);
            }
            else
            {
                await inventory.AddAsync(accountId, tool, 1, cancellationToken);
            }
        }, cancellationToken);

    /// <summary>Takes a tool from the inventory into a slot of the tool bar (the first free one when
    /// <paramref name="slot"/> is null, the first one when none is free) or puts a backpack on.
    /// What was there goes back to the inventory.</summary>
    public Task EquipAsync(Guid accountId, string item, int? slot, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (Items.IsBackpack(item))
            {
                await WearAsync(accountId, item, cancellationToken);
                return;
            }

            if (!Items.IsTool(item))
            {
                throw new GameException("not_a_tool", "Only tools fit in the tool bar.");
            }

            var worn = await RequireAsync(accountId, cancellationToken);
            var slots = ToolSlots(worn.Backpack);
            var at = slot ?? Array.FindIndex(worn.Tools, 0, slots, t => t is null);
            if (at < 0)
            {
                at = 0;
            }

            if (at >= slots)
            {
                throw new GameException("bad_slot", slots == 1 ? "Without a backpack the tool bar has one slot." : $"The tool bar has slots 0 to {slots - 1}.");
            }

            await inventory.RemoveAsync(accountId, item, 1, cancellationToken);
            if (worn.Tools[at] is { } old)
            {
                await inventory.AddAsync(accountId, old, 1, cancellationToken);
            }

            await SetAsync(accountId, Slots[at], item, cancellationToken);
        }, cancellationToken);

    /// <summary>Puts the tool from a slot of the tool bar back into the inventory.</summary>
    public Task UnequipAsync(Guid accountId, int slot, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var worn = await RequireAsync(accountId, cancellationToken);
            if (slot < 0 || slot >= Slots.Length || worn.Tools[slot] is not { } tool)
            {
                return;
            }

            await inventory.AddAsync(accountId, tool, 1, cancellationToken);
            await SetAsync(accountId, Slots[slot], null, cancellationToken);
        }, cancellationToken);

    /// <summary>Takes the backpack off into the inventory, with the tools in the slots only it gave.</summary>
    public Task TakeOffBackpackAsync(Guid accountId, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var worn = await RequireAsync(accountId, cancellationToken);
            if (worn.Backpack is not { } backpack)
            {
                return;
            }

            await inventory.AddAsync(accountId, backpack, 1, cancellationToken);
            await SetAsync(accountId, "Backpack", null, cancellationToken);
            await DropToolsAsync(accountId, worn, Items.ToolSlots, cancellationToken);
        }, cancellationToken);

    private async Task WearAsync(Guid accountId, string backpack, CancellationToken cancellationToken)
    {
        var worn = await RequireAsync(accountId, cancellationToken);
        await inventory.RemoveAsync(accountId, backpack, 1, cancellationToken);
        if (worn.Backpack is { } old)
        {
            await inventory.AddAsync(accountId, old, 1, cancellationToken);
        }

        await SetAsync(accountId, "Backpack", backpack, cancellationToken);
        await DropToolsAsync(accountId, worn, ToolSlots(backpack), cancellationToken);
    }

    /// <summary>Puts the tools from slot <paramref name="from"/> on back into the inventory: the tool bar got shorter.</summary>
    private async Task DropToolsAsync(Guid accountId, Worn worn, int from, CancellationToken cancellationToken)
    {
        for (var i = from; i < Slots.Length; i++)
        {
            if (worn.Tools[i] is { } tool)
            {
                await inventory.AddAsync(accountId, tool, 1, cancellationToken);
                await SetAsync(accountId, Slots[i], null, cancellationToken);
            }
        }
    }

    private async Task<Worn> RequireAsync(Guid accountId, CancellationToken cancellationToken) =>
        await ReadAsync(accountId, true, cancellationToken) ?? throw new GameException("no_character", "Create a character first.");

    /// <summary>What the character has on, or null when the account has no character; locked with <paramref name="forUpdate"/>.</summary>
    private async Task<Worn?> ReadAsync(Guid accountId, bool forUpdate, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            $"""SELECT "Tool", "Tool2", "Tool3", "Backpack" FROM characters.characters WHERE "AccountId" = @account{(forUpdate ? " FOR UPDATE" : "")}""",
            cancellationToken);
        command.Parameters.AddWithValue("account", accountId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        string? Text(int i) => reader.IsDBNull(i) ? null : reader.GetString(i);
        return new Worn([Text(0), Text(1), Text(2)], Text(3));
    }

    /// <param name="column">One of <see cref="Slots"/> or "Backpack".</param>
    private async Task SetAsync(Guid accountId, string column, string? item, CancellationToken cancellationToken)
    {
        await using var update = await db.CommandAsync(
            $"""UPDATE characters.characters SET "{column}" = @item WHERE "AccountId" = @account""", cancellationToken);
        update.Parameters.AddWithValue("item", (object?)item ?? DBNull.Value);
        update.Parameters.AddWithValue("account", accountId);
        await update.ExecuteNonQueryAsync(cancellationToken);
    }

    private sealed record Worn(string?[] Tools, string? Backpack);
}

/// <summary>Tiles of the inventory: more with a backpack on. Apart from <see cref="Equipment"/>,
/// which needs the inventory itself.</summary>
public sealed class InventorySize(GameDb db) : IInventorySize
{
    public async Task<int> SlotsAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """SELECT "Backpack" FROM characters.characters WHERE "AccountId" = @account""", cancellationToken);
        command.Parameters.AddWithValue("account", accountId);
        return await command.ExecuteScalarAsync(cancellationToken) is string backpack && Items.Backpacks.TryGetValue(backpack, out var b)
            ? Items.InventorySlots + b.ExtraSlots
            : Items.InventorySlots;
    }
}
