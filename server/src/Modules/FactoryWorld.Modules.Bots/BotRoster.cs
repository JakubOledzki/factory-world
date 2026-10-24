namespace FactoryWorld.Modules.Bots;

/// <summary>What a bot is mostly up to; it decides the biome of its plots, what it makes and what it trades.</summary>
public enum BotTrade
{
    /// <summary>Buys forest, chops and plants trees, sells wood and saplings, makes wood piles and chests.</summary>
    Forester,

    /// <summary>Buys mountains, works the mines, smelts ore in a furnace, sells stone, coal, ore and ingots.</summary>
    Miner,

    /// <summary>Buys fertile soil, tills, sows and reaps, sells crops.</summary>
    Farmer,

    /// <summary>Buys ore and coal from other players, smelts and crafts nails, belts and chests for the market.</summary>
    Industrialist,

    /// <summary>Lives off the market: buys cheap listings, sells them on, fills buy orders and gives out orders.</summary>
    Trader,
}

/// <summary>One bot of the roster.</summary>
/// <param name="Name">Its character's name, as players see it in rankings and on the market.</param>
/// <param name="Latitude">Where on Earth it looks for its plots (a spiral out from here).</param>
/// <param name="Look">The character editor's choices: skin tone, hair style, hair colour, shirt style, shirt, pants and shoes colour.</param>
/// <param name="SessionMinutes">How long one of its play sessions lasts, give or take a half.</param>
/// <param name="RestHours">How long it stays away between sessions, give or take a half.</param>
public sealed record BotProfile(
    string Name, BotTrade Trade, double Latitude, double Longitude, int[] Look, int SessionMinutes, int RestHours);

/// <summary>
/// Every bot the server plays as, in one place: add a line here to add a bot. Each one gets an account and
/// a character on the first start and keeps them, so its name, plots, money and badges last like a player's.
/// Names must be free character names (3-16 letters, digits or _); a bot whose name a player took first
/// gets a digit added.
/// </summary>
public static class BotRoster
{
    public static readonly IReadOnlyList<BotProfile> All =
    [
        new("Kuba_Drwal", BotTrade.Forester, 52.70, 23.85, [1, 1, 1, 0, 5, 1, 1], 20, 3),
        new("Zosia_Las", BotTrade.Forester, 53.60, 17.90, [0, 3, 3, 2, 11, 8, 1], 15, 2),
        new("Bartosz99", BotTrade.Forester, 50.95, 22.75, [2, 2, 0, 0, 7, 1, 1], 25, 4),
        new("Wojtek_Kopalnia", BotTrade.Miner, 49.30, 19.95, [1, 1, 2, 1, 1, 8, 1], 25, 3),
        new("Majka_Huta", BotTrade.Miner, 50.90, 15.75, [0, 4, 4, 2, 2, 1, 0], 20, 4),
        new("Ola_Farma", BotTrade.Farmer, 52.25, 19.35, [0, 3, 6, 0, 5, 10, 1], 20, 3),
        new("Tomek_Rolnik", BotTrade.Farmer, 51.05, 20.95, [3, 0, 0, 1, 3, 1, 1], 15, 5),
        new("Piotrek_Stal", BotTrade.Industrialist, 50.25, 19.05, [1, 2, 1, 2, 8, 1, 1], 25, 3),
        new("Natalia_W", BotTrade.Industrialist, 51.10, 17.05, [0, 5, 2, 2, 9, 8, 0], 20, 4),
        new("Ewelina_Handel", BotTrade.Trader, 52.40, 16.95, [0, 4, 3, 0, 4, 1, 0], 15, 2),
    ];
}
