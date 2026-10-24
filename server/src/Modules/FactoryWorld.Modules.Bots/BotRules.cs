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
    public const int MaxListings = 3;

    /// <summary>Open buy orders one bot keeps at most.</summary>
    public const int MaxOrders = 2;

    /// <summary>Open orders one bot gives on the contracts board at most.</summary>
    public const int MaxIssued = 1;

    /// <summary>Most pieces in one listing.</summary>
    public const long ListingSize = 40;

    /// <summary>A bot lists something at most this often.</summary>
    public static readonly TimeSpan ListEvery = TimeSpan.FromMinutes(10);

    /// <summary>A bot's listing asks at least this much more than the trader pays.</summary>
    public const double MinMarkup = 1.15;

    /// <summary>
    /// A bot stays this many XP under its cap, so that experience it cannot see coming (a tutorial reward,
    /// a badge) does not carry it over. Whatever still gets over is taken away again right after.
    /// </summary>
    public const long XpMargin = 25;

    /// <summary>Cents a bot does not spend on goods; a plot is the exception, saved up for on purpose.</summary>
    public const long Reserve = 10_00;

    /// <summary>Fields a farming bot works at once.</summary>
    public const int MaxFields = 24;

    /// <summary>Saplings a forestry bot has in the ground at once.</summary>
    public const int MaxPlanted = 40;

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
        _ => [Biomes.Forest],
    };

    /// <summary>What the bot makes at the workbench, when it has the ingredients and the technology.</summary>
    public static string[] Products(BotTrade trade) => trade switch
    {
        BotTrade.Forester => [Items.WoodPile, Items.WoodenChest],
        BotTrade.Miner => [Items.Nails],
        BotTrade.Industrialist => [Items.Nails, Items.Belt, Items.WoodenChest, Items.IronChest],
        _ => [],
    };

    /// <summary>Technologies the bot researches, in order, when it can pay for them.</summary>
    public static string[] Research(BotTrade trade) => trade switch
    {
        BotTrade.Forester => ["logistics", "storage"],
        BotTrade.Miner => ["logistics", "storage"],
        BotTrade.Industrialist => ["logistics", "automation", "storage"],
        BotTrade.Farmer => ["milling"],
        _ => [],
    };

    /// <summary>What the bot looks for on the players' market.</summary>
    public static string[] Buys(BotTrade trade) => trade switch
    {
        BotTrade.Forester => [Items.Sapling, Items.Nails],
        BotTrade.Miner => [Items.Wood, Items.Coal],
        BotTrade.Farmer => [Items.Stone],
        BotTrade.Industrialist => [Items.IronOre, Items.CopperOre, Items.Coal, Items.Wood],
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
        Items.Nails, Items.Belt, Items.WoodenChest, Items.IronChest, Items.WoodPile,
        Items.Wheat, Items.Carrot, Items.Cabbage, Items.Corn, Items.Potato, Items.Sunflower,
    };

    /// <summary>What sorting trash gives; bots sell it to the trader like new players do.</summary>
    public static readonly string[] Waste =
        [Items.WastePaper, Items.WastePlastic, Items.WasteAluminium, Items.WasteGlass, Items.WasteCopper];

    public static readonly string[] Ores = [Items.IronOre, Items.CopperOre, Items.TinOre, Items.SilverOre, Items.GoldOre];

    /// <summary>Crops a farming bot sows, by weight: mostly wheat, now and then something slower.</summary>
    public static readonly (string Crop, int Weight)[] Crops =
        [(Items.Wheat, 5), (Items.Carrot, 3), (Items.Cabbage, 2), (Items.Corn, 2), (Items.Potato, 2), (Items.Sunflower, 1)];
}
