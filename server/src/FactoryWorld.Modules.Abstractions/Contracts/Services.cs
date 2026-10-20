namespace FactoryWorld.Modules.Abstractions.Contracts;

// Public services that modules offer each other. Call them inside GameDb.InTransactionAsync
// when several must succeed together.

/// <summary>Items a player owns (owner = account id).</summary>
public interface IInventory
{
    Task AddAsync(Guid owner, string item, long quantity, CancellationToken cancellationToken);

    /// <summary>Fails with <c>not_enough_items</c> when the player has fewer.</summary>
    Task RemoveAsync(Guid owner, string item, long quantity, CancellationToken cancellationToken);

    Task<long> CountAsync(Guid owner, string item, CancellationToken cancellationToken);
}

/// <summary>A player's money, in cents, with every change recorded in a ledger.</summary>
public interface IWallet
{
    Task<long> CreditAsync(Guid owner, long cents, string reason, CancellationToken cancellationToken);

    /// <summary>Fails with <c>not_enough_money</c> when the balance is lower.</summary>
    Task<long> DebitAsync(Guid owner, long cents, string reason, CancellationToken cancellationToken);

    Task<long> BalanceAsync(Guid owner, CancellationToken cancellationToken);
}

public sealed record XpGain(long Xp, int Level, bool LeveledUp);

/// <summary>Character experience. Fails with <c>no_character</c> when the account has none yet.</summary>
public interface ICharacterProgress
{
    Task<XpGain> AddXpAsync(Guid accountId, long xp, CancellationToken cancellationToken);
}

/// <summary>Character names, e.g. to show who owns something.</summary>
public interface ICharacterNames
{
    /// <summary>Name by account id; accounts without a character are left out.</summary>
    Task<IReadOnlyDictionary<Guid, string>> NamesAsync(IReadOnlyCollection<Guid> accountIds, CancellationToken cancellationToken);
}

/// <summary>The character's tool slot: one tool (e.g. an axe) held in hand, outside the inventory.</summary>
public interface IEquipment
{
    /// <summary>The tool in the slot, or null.</summary>
    Task<string?> ToolAsync(Guid accountId, CancellationToken cancellationToken);

    /// <summary>Gives a new tool: into the slot when it is empty, otherwise into the inventory.</summary>
    Task GiveToolAsync(Guid accountId, string tool, CancellationToken cancellationToken);
}
