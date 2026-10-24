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

    /// <summary>Characters whose name starts with <paramref name="prefix"/> (any case), at most <paramref name="limit"/>, by account id.</summary>
    Task<IReadOnlyDictionary<Guid, string>> FindAsync(string prefix, int limit, CancellationToken cancellationToken);
}

/// <summary>The character's tool slot: one tool (e.g. an axe) held in hand, outside the inventory.</summary>
public interface IEquipment
{
    /// <summary>The tool in the slot, or null.</summary>
    Task<string?> ToolAsync(Guid accountId, CancellationToken cancellationToken);

    /// <summary>Gives a new tool: into the slot when it is empty, otherwise into the inventory.</summary>
    Task GiveToolAsync(Guid accountId, string tool, CancellationToken cancellationToken);
}

/// <summary>Things a player has put somewhere: furniture in the garage, objects on a plot.
/// Each module that keeps such objects offers one of these.</summary>
public interface IPlacedObjects
{
    /// <summary>The kind (item id) of the player's object with this id, or null when it is not theirs or not here.</summary>
    Task<string?> KindAsync(Guid owner, Guid id, CancellationToken cancellationToken);
}

/// <summary>What a placed machine (e.g. a furnace) holds.</summary>
public interface IMachineContents
{
    /// <summary>The object is being picked up: everything in it goes back to the owner's inventory.</summary>
    Task ReleaseAsync(Guid owner, Guid id, CancellationToken cancellationToken);
}

/// <summary>An object standing on a plot. <paramref name="Rotation"/> (0-3) counts quarter turns
/// anticlockwise seen from above, as in the garage: 0 faces south (the camera), 1 east, 2 north, 3 west.</summary>
public sealed record PlotObject(Guid Id, string Kind, int TileX, int TileY, int Rotation, Guid Owner);

/// <summary>What stands on plots, for modules that run machinery there.</summary>
public interface IPlotObjects
{
    Task<IReadOnlyList<PlotObject>> ObjectsAsync(int x, int y, CancellationToken cancellationToken);

    /// <summary>What every plot has built in and inserters can work with too (the railway station): one
    /// object per tile it covers, all with the same id, owned by the plot's owner.</summary>
    Task<IReadOnlyList<PlotObject>> FixturesAsync(int x, int y, CancellationToken cancellationToken);

    /// <summary>Fails with <c>not_owner</c> unless the player owns the plot.</summary>
    Task RequireOwnerAsync(Guid player, int x, int y, CancellationToken cancellationToken);

    /// <summary>The plot an object stands on, or null when it stands on none.</summary>
    Task<(int X, int Y)?> PlotOfAsync(Guid id, CancellationToken cancellationToken);
}

/// <summary>Machinery that runs on a plot by itself (belts, inserters). It is brought up to now
/// before an object is put on the plot or taken off, so it never works with objects that were not there.</summary>
public interface IPlotAutomation
{
    Task CatchUpAsync(int x, int y, CancellationToken cancellationToken);
}

/// <summary>
/// A placed machine's inputs and outputs as an inserter sees them, during one run of a plot's
/// logistics. Every call gives the moment of the simulation, which only moves forward; the machine
/// does its own work (e.g. smelting) up to that moment first.
/// </summary>
public interface IMachinePort
{
    /// <summary>One item an inserter may take out now and that <paramref name="wanted"/> accepts, or null.</summary>
    string? Output(DateTimeOffset now, Func<string, bool> wanted);

    /// <summary>Takes out one piece of an item <see cref="Output"/> offered.</summary>
    void Take(string item, DateTimeOffset now);

    /// <summary>Whether one more piece of the item can go in now.</summary>
    bool Accepts(string item, DateTimeOffset now);

    /// <summary>Puts in one piece of an item the machine <see cref="Accepts"/>.</summary>
    void Put(string item, DateTimeOffset now);

    /// <summary>When the machine will next have something new to take out on its own (e.g. its next ingot), or null.</summary>
    DateTimeOffset? NextChange(DateTimeOffset now);

    /// <summary>Writes the machine back, if anything changed.</summary>
    Task SaveAsync(CancellationToken cancellationToken);
}

/// <summary>Offered by each module that keeps machines with inputs and outputs (the furnace, the mill...),
/// so inserters work with any of them.</summary>
public interface IMachinePorts
{
    /// <summary>The machine, locked until the transaction ends; null when this module keeps no machine of this kind.</summary>
    Task<IMachinePort?> OpenAsync(Guid owner, Guid id, string kind, CancellationToken cancellationToken);
}

/// <summary>
/// The time of a machine that runs on power: it goes with the clock while the machine has all the
/// power it needs, slower on too little and not at all without. A machine works out what it made
/// in its own time, so it needs to know nothing else about the grid.
/// </summary>
public interface IPowerClock
{
    /// <summary>The machine's time at <paramref name="now"/>; never ahead of it.</summary>
    DateTimeOffset At(DateTimeOffset now);

    /// <summary>When, from <paramref name="now"/> on, the machine's time reaches <paramref name="machineTime"/>; null if never on the power it has.</summary>
    DateTimeOffset? When(DateTimeOffset machineTime, DateTimeOffset now);

    /// <summary>How fast the machine works at <paramref name="now"/>: 1 with all its power, 0 without.</summary>
    double Speed(DateTimeOffset now);
}

/// <summary>One plot's power: generators, poles and the machines they reach.</summary>
public interface IPowerGrid
{
    /// <summary>The clock of a machine on the plot.</summary>
    IPowerClock Clock(Guid id);

    /// <summary>A generator as inserters see it (fuel goes in), or null when <paramref name="id"/> is none.</summary>
    IMachinePort? Port(Guid id);

    /// <summary>The grid as the client draws it (poles, wires, networks and how well each is powered), ready for JSON.</summary>
    object Summary(DateTimeOffset now);

    /// <summary>Writes the grid back, if fuel went into it.</summary>
    Task SaveAsync(CancellationToken cancellationToken);
}

/// <summary>Power on plots, for modules whose machines run on it. Within one request the same grid
/// is handed out until it is saved, so inserters feeding a generator power the machines at once.</summary>
public interface IPlotPower
{
    /// <summary>The plot's grid, locked until the transaction ends.</summary>
    Task<IPowerGrid> OpenAsync(int x, int y, CancellationToken cancellationToken);

    /// <summary>The clock of a machine on whatever plot it stands; one that has no power ever if it stands on none.</summary>
    Task<IPowerClock> ClockAsync(Guid id, CancellationToken cancellationToken);
}

/// <summary>The player's technology tree: research unlocks recipes, machines and what the trader sells.
/// An item no technology covers is open to everyone from the start.</summary>
public interface ITechnologies
{
    /// <summary>Every item the player cannot make or buy from the trader yet, with the name of the technology that unlocks it.</summary>
    Task<IReadOnlyDictionary<string, string>> LockedAsync(Guid player, CancellationToken cancellationToken);

    /// <summary>Fails with <c>locked</c> while the item is still to be researched.</summary>
    Task RequireUnlockedAsync(Guid player, string item, CancellationToken cancellationToken);
}
