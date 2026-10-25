namespace FactoryWorld.Modules.Abstractions.Contracts;

// Public services that modules offer each other. Call them inside GameDb.InTransactionAsync
// when several must succeed together.

/// <summary>Items a player owns (owner = account id).</summary>
public interface IInventory
{
    /// <summary>Adds items whether or not there is a free tile: for what comes back to the player
    /// (a machine picked up, an offer cancelled) or arrives without them doing anything.</summary>
    Task AddAsync(Guid owner, string item, long quantity, CancellationToken cancellationToken);

    /// <summary>Adds items the player takes (buys, gathers, takes out of something). Fails with
    /// <c>inventory_full</c> when the item is not in the inventory yet and every tile is taken.</summary>
    Task ReceiveAsync(Guid owner, string item, long quantity, CancellationToken cancellationToken);

    /// <summary>Fails with <c>not_enough_items</c> when the player has fewer.</summary>
    Task RemoveAsync(Guid owner, string item, long quantity, CancellationToken cancellationToken);

    Task<long> CountAsync(Guid owner, string item, CancellationToken cancellationToken);

    /// <summary>Whether <see cref="ReceiveAsync"/> would take the item now: it is in the inventory already or a tile is free.</summary>
    Task<bool> HasRoomAsync(Guid owner, string item, CancellationToken cancellationToken);
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

    /// <summary>The account whose character has this name (any letter case), or null.</summary>
    Task<Guid?> AccountAsync(string name, CancellationToken cancellationToken);

    /// <summary>Characters whose name starts with <paramref name="prefix"/> (any case), at most <paramref name="limit"/>, by account id.</summary>
    Task<IReadOnlyDictionary<Guid, string>> FindAsync(string prefix, int limit, CancellationToken cancellationToken);
}

/// <summary>How a character looks, e.g. to draw other players walking on the same plot.</summary>
public interface ICharacterLooks
{
    /// <summary>Name and appearance (as the character editor saved it) by account id; accounts without a character are left out.</summary>
    Task<IReadOnlyDictionary<Guid, CharacterLook>> LooksAsync(IReadOnlyCollection<Guid> accountIds, CancellationToken cancellationToken);
}

/// <summary>A character's name and appearance; the appearance is sent to clients as it is.</summary>
public sealed record CharacterLook(string Name, object Appearance);

/// <summary>Characters' experience as a whole, e.g. to keep the server's bots behind the real players.</summary>
public interface ICharacterXp
{
    /// <summary>The most XP any character has, leaving out the accounts in <paramref name="excluding"/>; 0 when there is none.</summary>
    Task<long> HighestAsync(IReadOnlyCollection<Guid> excluding, CancellationToken cancellationToken);

    /// <summary>The character's XP, or null when the account has no character.</summary>
    Task<long?> XpAsync(Guid accountId, CancellationToken cancellationToken);

    /// <summary>Takes experience away from a character that has more than <paramref name="maxXp"/>, so it has exactly that much.</summary>
    Task CapAsync(Guid accountId, long maxXp, CancellationToken cancellationToken);
}

/// <summary>The character's tool bar: tools (e.g. an axe) held in hand, outside the inventory.
/// One slot, more with a backpack on.</summary>
public interface IEquipment
{
    /// <summary>The tools in the tool bar, in slot order; empty slots left out.</summary>
    Task<IReadOnlyList<string>> ToolsAsync(Guid accountId, CancellationToken cancellationToken);

    /// <summary>Gives a new tool: into a free slot of the tool bar, otherwise into the inventory.</summary>
    Task GiveToolAsync(Guid accountId, string tool, CancellationToken cancellationToken);
}

/// <summary>The clothes a character wears and the level it has reached, and what they help with.</summary>
public interface IOutfit
{
    /// <summary>What the player gets in an industry (<see cref="Industries"/>), in percent: the worn clothes, the
    /// level, the last meal and every <see cref="IPlayerBonuses"/> (e.g. the garage's upgrades) together; 0 without any.</summary>
    Task<int> BonusAsync(Guid accountId, string industry, CancellationToken cancellationToken);

    /// <summary>The clothes worn by slot (<see cref="ClothingSlots.All"/>); empty when the account has no character.</summary>
    Task<IReadOnlyDictionary<string, string>> WornAsync(Guid accountId, CancellationToken cancellationToken);

    /// <summary>Puts <paramref name="item"/> (or nothing) on a slot as it is: the caller takes it from
    /// somewhere and keeps what was worn there. Fails with <c>no_character</c> without a character.</summary>
    Task SetWornAsync(Guid accountId, string slot, string? item, CancellationToken cancellationToken);
}

/// <summary>Bonuses a player earned apart from their clothes, e.g. by upgrading the garage.</summary>
public interface IPlayerBonuses
{
    /// <summary>Percent the player gets for <paramref name="bonus"/>: an industry (<see cref="Industries"/>)
    /// or <see cref="PlayerBonus.Xp"/>; 0 without any.</summary>
    Task<int> PercentAsync(Guid player, string bonus, CancellationToken cancellationToken);
}

public static class PlayerBonus
{
    /// <summary>More experience for everything the character does.</summary>
    public const string Xp = "xp";
}

/// <summary>The delivery pallet in the player's garage: what they buy waits there when the inventory is full.</summary>
public interface IGarageDeliveries
{
    /// <summary>Puts items on the pallet; false, with nothing done, when no pallet stands in the garage.</summary>
    Task<bool> DeliverAsync(Guid player, string item, long quantity, CancellationToken cancellationToken);
}

/// <summary>How many tiles a player's inventory has: <see cref="Items.InventorySlots"/>, more with a backpack on.</summary>
public interface IInventorySize
{
    Task<int> SlotsAsync(Guid accountId, CancellationToken cancellationToken);
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

    /// <summary>The plot an object stands on, or null when it stands on none.</summary>
    Task<(int X, int Y)?> PlotOfAsync(Guid id, CancellationToken cancellationToken);

    /// <summary>Fails with <c>not_owner</c> unless the player owns the plot, or may do <paramref name="right"/>
    /// there as a member of the company the plot belongs to.</summary>
    Task RequireOwnerAsync(Guid player, int x, int y, CancellationToken cancellationToken, PlotRight right = PlotRight.Build);
}

/// <summary>What a player does on a plot. Its owner may do everything; members of a company the
/// owner brought the plot into may do what their role allows.</summary>
public enum PlotRight
{
    /// <summary>Enter, gather, mine, farm, plant, work machines, put into storage and the station.</summary>
    Work,

    /// <summary>Take out of storage and the station, send trains.</summary>
    Take,

    /// <summary>Put objects on the plot, turn and pick them up, set splitters.</summary>
    Build,

    /// <summary>Only the owner, e.g. a geological survey.</summary>
    Owner,
    /// <summary>Set up and stop the station's train routes: the owner, and a company's partners and logistician.</summary>
    Routes,
}

/// <summary>A bought plot, for modules outside the world.</summary>
/// <param name="PriceCents">What its owner paid for it.</param>
public sealed record OwnedPlot(int X, int Y, Guid Owner, int Biome, long PriceCents = 0);

/// <summary>Who owns which plot.</summary>
public interface IPlotRegistry
{
    /// <summary>The plot if somebody bought it, otherwise null.</summary>
    Task<OwnedPlot?> FindAsync(int x, int y, CancellationToken cancellationToken);
}

/// <summary>The company a plot belongs to, as one player sees it.</summary>
public sealed record PlotCompany(string Name, bool Member);

/// <summary>Plots that owners brought into a company, so its members work on them together.</summary>
public interface ICompanyPlots
{
    /// <summary>What the player may do on the plot as a member of its company; empty when it is in none of theirs.</summary>
    Task<IReadOnlySet<PlotRight>> RightsAsync(Guid player, int x, int y, CancellationToken cancellationToken);

    /// <summary>The company the plot is in, or null.</summary>
    Task<PlotCompany?> CompanyAsync(Guid viewer, int x, int y, CancellationToken cancellationToken);

    /// <summary>Plots of the player's company that other members own.</summary>
    Task<IReadOnlyList<(int X, int Y)>> SharedWithAsync(Guid player, CancellationToken cancellationToken);
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

    /// <summary>About to open the machines among <paramref name="objects"/>: a module can read all of its own
    /// at once here, so that each <see cref="OpenAsync"/> after needs no query of its own.</summary>
    Task PrepareAsync(IReadOnlyList<PlotObject> objects, CancellationToken cancellationToken) => Task.CompletedTask;

    /// <summary>Saves the ports this module opened; a module can write them all at once.</summary>
    async Task SaveAsync(IReadOnlyList<IMachinePort> ports, CancellationToken cancellationToken)
    {
        foreach (var port in ports)
        {
            await port.SaveAsync(cancellationToken);
        }
    }
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

/// <summary>What the trader usually pays for items, before its events move the prices.</summary>
public interface IMarketPrices
{
    /// <summary>The usual price the trader pays for one piece, in cents, or null when it buys none.</summary>
    long? BuysCents(string item);

    /// <summary>The usual price the trader asks for one piece, in cents, or null when it sells none.</summary>
    long? SellsCents(string item);
}

/// <summary>The forest certificate: a player who planted at least as many trees as they cut over the last week, and
/// enough of them, sells timber dearer.</summary>
public interface IForestCertificate
{
    Task<bool> CertifiedAsync(Guid player, CancellationToken cancellationToken);
}

public static class ForestCertificate
{
    /// <summary>How much more the trader pays a certified player for timber, in percent.</summary>
    public const int BonusPercent = 15;
}
