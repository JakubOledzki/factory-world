using FactoryWorld.Modules.Abstractions.Contracts;

namespace FactoryWorld.Modules.Bots;

/// <summary>Biome numbers as the protocol sends them (world.info, world.plot); fixed, so safe to name here.</summary>
internal static class Biomes
{
    public const int Forest = 2;
    public const int Farmland = 3;
    public const int Desert = 5;
    public const int Mountains = 6;
}

/// <summary>Tile codes of plot.enter: what stands on a tile.</summary>
internal static class Tiles
{
    public const byte None = 0;
    public const byte Tree = 1;
    public const byte Rock = 2;
    public const byte Dune = 3;
}

/// <summary>How bots pace themselves, so that they feel like players and never swamp the market.</summary>
public static class BotRules
{
    /// <summary>Open sell listings one bot keeps at most (players may have 20).</summary>
    public const int MaxListings = 6;

    /// <summary>Open buy orders one bot keeps at most.</summary>
    public const int MaxOrders = 3;

    /// <summary>Open orders one bot gives on the contracts board at most.</summary>
    public const int MaxIssued = 1;

    /// <summary>Most pieces in one listing.</summary>
    public const long ListingSize = 40;

    /// <summary>A bot lists something at most this often.</summary>
    public static readonly TimeSpan ListEvery = TimeSpan.FromMinutes(3);

    /// <summary>With every listing slot taken and nothing new listed for this long, the bot takes its oldest unsold listing back to put it up cheaper.</summary>
    public static readonly TimeSpan RelistAfter = TimeSpan.FromMinutes(30);

    /// <summary>Purchases from players one bot makes in a session at most.</summary>
    public const int MaxPurchases = 12;

    /// <summary>Most pieces a bot buys from one listing at once.</summary>
    public const long PurchaseSize = 40;

    /// <summary>
    /// Money a bot has at least when a session starts: what it buys from players with. Sorting trash pays too
    /// little for a bot to ever buy much, so the server tops it up; a bot never pays a player more than the
    /// trader would charge, so this buys players' goods without printing an easy profit.
    /// </summary>
    public const long Allowance = 100_00;

    /// <summary>What a bot with no plot gets on top of its first plot's price, for tools and trash.</summary>
    public const long StartingExtra = 300_00;

    /// <summary>A bot's listing asks at least this much more than the trader pays.</summary>
    public const double MinMarkup = 1.15;

    /// <summary>Cents a bot does not spend on goods; a plot is the exception, saved up for on purpose.</summary>
    public const long Reserve = 10_00;

    /// <summary>Fields a farming bot works at once.</summary>
    public const int MaxFields = 24;

    /// <summary>Saplings a forestry bot has in the ground at once.</summary>
    public const int MaxPlanted = 40;

    /// <summary>
    /// Cents a bot takes from the NPC trader and NPC orders in one session at most. Selling to the trader makes new money
    /// (a sale between players only moves it), and two thousand bots selling all they gather swamped the economy, so past
    /// this a bot sells only to players and lets the rest wait in its inventory and on its listings.
    /// </summary>
    public const long MaxTraderIncome = 100_00;

    /// <summary>With this many pieces to sell piling up, a bot gathers less and works its line and the market more.</summary>
    public const long Glut = 600;

    /// <summary>How often a bot looks after its production line: empties the output, refills the input and the generator.</summary>
    public static readonly TimeSpan TendEvery = TimeSpan.FromMinutes(2);

    /// <summary>How often a bot opens the contracts board.</summary>
    public static readonly TimeSpan ContractsEvery = TimeSpan.FromMinutes(3);

    /// <summary>How long the market overview one bot fetched serves every bot (as long as the server keeps its own summary).</summary>
    public static readonly TimeSpan OverviewFor = TimeSpan.FromSeconds(10);

    /// <summary>What a bot pays a player who helps it on top of what the parts are worth (or alone, for setting a stalled line going).</summary>
    public const long HelpFee = 10_00;

    /// <summary>A bot pays for parts a player brings this many times what the trader pays for them, and the fee.</summary>
    public const double HelpMarkup = 1.25;

    /// <summary>A bot pays for parts at most this share of what the NPC trader charges for them, the fee included.</summary>
    public const double HelpBelowTrader = 0.95;

    /// <summary>A bot waits this long for help before it gives up and sets its line going itself.</summary>
    public static readonly TimeSpan HelpWait = TimeSpan.FromMinutes(30);

    /// <summary>A bot that could not put its line up three times tries again after this long.</summary>
    public static readonly TimeSpan RetryBuildAfter = TimeSpan.FromMinutes(30);

    /// <summary>A bot asks for parts once it has wanted them this long without getting them.</summary>
    public static readonly TimeSpan PartsWait = TimeSpan.FromMinutes(20);

    /// <summary>Looks after its line this many times in a row without anything coming out of it, and the bot calls the line stalled.</summary>
    public const int StalledAfter = 2;

    /// <summary>A bot buys a part of its line from the NPC trader, when it cannot make it, only for at most this many times what the trader pays.</summary>
    public const double MaxPartMarkup = 3;

    /// <summary>
    /// The production line the bot puts up on its plot once it has researched what it takes: miners, smelters and
    /// crafters smelt ore, farmers grind wheat, foresters saw planks. Traders live off the market alone.
    /// </summary>
    public static BotLine? Line(BotTrade trade) => trade switch
    {
        BotTrade.Miner or BotTrade.Smelter or BotTrade.Industrialist => new BotLine(Items.Furnace, null,
            Ores, [Items.Wood, Items.Coal],
            [Items.IronIngot, Items.CopperIngot, Items.TinIngot, Items.SilverIngot, Items.GoldIngot]),
        BotTrade.Farmer => new BotLine(Items.Mill, Items.Flour, [Items.Wheat], [Items.Wood, Items.Coal], [Items.Flour]),
        BotTrade.Forester => new BotLine(Items.Sawmill, Items.Planks, [Items.Wood], [Items.Wood], [Items.Planks]),
        _ => null,
    };

    /// <summary>Plots a bot buys over its life; the third costs 100 000 $, so few get that far.</summary>
    public static int MaxPlots(BotTrade trade) => trade switch
    {
        BotTrade.Trader => 1,
        _ => 3,
    };

    /// <summary>Biomes the bot's next plot may have, given how many it owns.</summary>
    public static int[] PlotBiomes(BotTrade trade, int owned) => trade switch
    {
        BotTrade.Forester => [Biomes.Forest],
        BotTrade.Miner => owned == 0 ? [Biomes.Mountains] : [Biomes.Mountains, Biomes.Forest],
        BotTrade.Farmer => owned == 0 ? [Biomes.Farmland] : [Biomes.Farmland, Biomes.Forest],
        BotTrade.Industrialist => owned == 0 ? [Biomes.Forest] : [Biomes.Mountains],
        BotTrade.Smelter => owned == 0 ? [Biomes.Forest] : [Biomes.Mountains, Biomes.Forest],
        _ => [Biomes.Forest],
    };

    /// <summary>
    /// What the bot puts up on a plot of a biome, in the order it gets to them: it crafts each piece
    /// (once the technology allows) and places it near where it appears. Furnaces on a plot it smelts in
    /// like in the garage; the rest is what a player's yard looks like to visitors.
    /// </summary>
    public static string[] Builds(BotTrade trade, int biome) => (trade, biome) switch
    {
        (BotTrade.Forester, Biomes.Forest) => [Items.Workbench, Items.WoodPile, Items.WoodPile, Items.WoodenChest],
        (BotTrade.Miner, Biomes.Mountains) => [Items.Furnace, Items.Furnace, Items.Heap, Items.WoodenChest],
        (BotTrade.Industrialist, Biomes.Mountains) => [Items.Furnace, Items.Furnace, Items.Anvil, Items.IronChest],
        (BotTrade.Farmer, Biomes.Farmland) => [Items.Workbench, Items.Mill, Items.WoodenChest, Items.GrainSilo],
        (_, Biomes.Forest) => [Items.WoodPile, Items.WoodenChest],
        _ => [Items.WoodenChest],
    };

    /// <summary>What the bot makes at the workbench for the market, when it has the ingredients and the technology; the dearest first.</summary>
    public static string[] Products(BotTrade trade) => trade switch
    {
        BotTrade.Forester => [Items.WoodenChest, Items.WoodPile],
        BotTrade.Miner => [Items.Nails],
        BotTrade.Smelter => [Items.Nails],
        BotTrade.Industrialist => [Items.Inserter, Items.IronChest, Items.WoodenChest, Items.Pole, Items.Belt, Items.Nails],
        _ => [],
    };

    /// <summary>How many of a product the bot makes ahead before it waits for them to sell.</summary>
    public static long Stock(string product) => product switch
    {
        Items.Inserter or Items.IronChest => 10,
        _ => 20,
    };

    /// <summary>Technologies the bot researches, in order, when it can pay for them; the line needs the first ones.</summary>
    public static string[] Research(BotTrade trade) => trade switch
    {
        BotTrade.Forester => ["logistics", "automation", "forestry_industry", "storage"],
        BotTrade.Miner or BotTrade.Smelter or BotTrade.Industrialist => ["logistics", "automation", "storage"],
        BotTrade.Farmer => ["milling", "logistics", "automation"],
        _ => [],
    };

    /// <summary>What the bot looks for on the players' market: the inputs of its trade. What it still lacks for its line and its
    /// research it looks for too (<see cref="Bot"/> adds that).</summary>
    public static string[] Buys(BotTrade trade) => trade switch
    {
        BotTrade.Forester => [Items.Sapling, Items.Nails],
        BotTrade.Miner => [Items.Wood, Items.Coal],
        BotTrade.Farmer => [Items.Wheat, Items.Wood, Items.Coal],
        BotTrade.Industrialist => [Items.IronIngot, Items.CopperIngot, Items.IronOre, Items.Coal, Items.Wood],
        BotTrade.Smelter => [Items.IronOre, Items.CopperOre, Items.TinOre, Items.Coal, Items.Wood],
        _ => [],
    };

    /// <summary>How many of an item the bot holds back from selling, for its own work.</summary>
    public static long Keep(BotTrade trade, string item) => (trade, item) switch
    {
        (BotTrade.Forester, Items.Wood) => 60,
        (BotTrade.Forester, Items.Sapling) => 10,
        (BotTrade.Forester, Items.Nails) => 30,
        (BotTrade.Miner, Items.IronOre or Items.CopperOre or Items.TinOre or Items.SilverOre or Items.GoldOre) => 1000,
        (BotTrade.Miner, Items.Coal) => 30,
        (BotTrade.Miner, Items.Stone) => 40,
        (BotTrade.Miner, Items.IronIngot) => 40,
        (BotTrade.Miner, Items.Wood) => 50,
        (BotTrade.Farmer, Items.Wheat) => 60,
        (BotTrade.Farmer, Items.Stone) => 30,
        (BotTrade.Farmer, Items.Wood or Items.Coal) => 20,
        (BotTrade.Smelter, Items.IronOre or Items.CopperOre or Items.TinOre or Items.SilverOre or Items.GoldOre) => 1000,
        (BotTrade.Smelter, Items.Coal or Items.Wood) => 30,
        (BotTrade.Smelter, Items.IronIngot) => 20,
        (BotTrade.Industrialist, Items.IronOre or Items.CopperOre or Items.TinOre or Items.SilverOre or Items.GoldOre) => 1000,
        (BotTrade.Industrialist, Items.Coal) => 30,
        (BotTrade.Industrialist, Items.IronIngot or Items.CopperIngot) => 30,
        (BotTrade.Industrialist, Items.Wood or Items.Nails) => 30,
        _ => 0,
    };

    /// <summary>Items bots sell on the market when they have more than they keep.</summary>
    public static readonly IReadOnlySet<string> Goods = new HashSet<string>
    {
        Items.Wood, Items.Stone, Items.Sand, Items.Coal, Items.Sapling,
        Items.IronOre, Items.CopperOre, Items.TinOre, Items.SilverOre, Items.GoldOre,
        Items.IronIngot, Items.CopperIngot, Items.TinIngot, Items.SilverIngot, Items.GoldIngot,
        Items.Nails, Items.Belt, Items.WoodenChest, Items.IronChest, Items.WoodPile, Items.Inserter, Items.Pole,
        Items.Wheat, Items.Carrot, Items.Cabbage, Items.Corn, Items.Potato, Items.Sunflower,
        Items.Flour, Items.Planks,
    };

    /// <summary>What sorting trash gives; bots sell it to the trader like new players do.</summary>
    public static readonly string[] Waste =
        [Items.WastePaper, Items.WastePlastic, Items.WasteAluminium, Items.WasteGlass, Items.WasteCopper];

    public static readonly string[] Ores = [Items.IronOre, Items.CopperOre, Items.TinOre, Items.SilverOre, Items.GoldOre];

    /// <summary>Crops a farming bot sows, by weight: mostly wheat, now and then something slower.</summary>
    public static readonly (string Crop, int Weight)[] Crops =
        [(Items.Wheat, 5), (Items.Carrot, 3), (Items.Cabbage, 2), (Items.Corn, 2), (Items.Potato, 2), (Items.Sunflower, 1)];
}
