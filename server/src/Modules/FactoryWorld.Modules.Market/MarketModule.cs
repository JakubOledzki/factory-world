using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Market;

/// <summary>
/// The NPC trader: always sells trash, saplings, animals, nails, tools, an anvil, a chainsaw, belts, inserters, wooden chests, machines (a forester's hut and a sawmill among them), the computer, generators, poles, flour, oil, bread and planks and always buys raw materials.
/// Everything else it buys it sells too, but dear: <see cref="Markup"/> times what it pays, so buying is a last resort and never pays to sell back.
/// These are its usual prices (cents); <see cref="TraderPrices"/> moves them with the day's drift and the market's events.
/// What it pays is the floor of the market: a quick sale gets it at once, players' listings usually pay more.
/// </summary>
public static class NpcPrices
{
    /// <summary>What the NPC charges for an item it has no price of its own for, in times what it pays for it.</summary>
    public const int Markup = 10;

    /// <summary>What the NPC charges the player: its own prices, then <see cref="Markup"/> times what it pays for the rest.</summary>
    public static readonly IReadOnlyDictionary<string, long> Sells;

    /// <summary>What the NPC charges for the things it stocks on purpose, at prices of their own.</summary>
    private static readonly Dictionary<string, long> OwnSells = new()
    {
        [Items.Trash] = 100,
        [Items.SortingMachine] = 100_000,
        [Items.Sapling] = 200,
        [Items.Nails] = 100,
        [Items.Workbench] = 50_000,
        [Items.Anvil] = 50_000,
        [Items.Axe] = 10_000,
        [Items.Shovel] = 10_000,
        [Items.Pickaxe] = 10_000,
        [Items.Hoe] = 10_000,
        [Items.Chainsaw] = 50_000,
        [Items.Shears] = 10_000,
        [Items.Chicken] = 5000,
        [Items.Sheep] = 20_000,
        [Items.Cow] = 50_000,
        [Items.Belt] = 500,
        [Items.Inserter] = 3000,
        [Items.Splitter] = 4000,
        [Items.WoodenChest] = 2000,
        [Items.Mill] = 40_000,
        [Items.OilPress] = 40_000,
        [Items.PicklingBarrel] = 10_000,
        [Items.Bakery] = 60_000,
        [Items.Kitchen] = 60_000,
        [Items.Computer] = 80_000,
        [Items.Flour] = 400,
        [Items.SunflowerOil] = 1500,
        [Items.Bread] = 1500,
        [Items.Generator] = 60_000,
        [Items.Pole] = 300,
        [Items.ForesterHut] = 60_000,
        [Items.Sawmill] = 40_000,
        [Items.Planks] = 300,
    };

    /// <summary>What the NPC pays the player.</summary>
    public static readonly IReadOnlyDictionary<string, long> Buys = new Dictionary<string, long>
    {
        [Items.WastePaper] = 100,
        [Items.WastePlastic] = 200,
        [Items.WasteGlass] = 200,
        [Items.WasteAluminium] = 600,
        [Items.WasteCopper] = 1500,
        [Items.Sand] = 50,
        [Items.Stone] = 100,
        [Items.Wood] = 200,
        [Items.Sapling] = 100,
        [Items.Coal] = 400,
        [Items.IronOre] = 600,
        [Items.CopperOre] = 1200,
        [Items.TinOre] = 2500,
        [Items.SilverOre] = 6000,
        [Items.GoldOre] = 50_000,
        [Items.IronIngot] = 1000,
        [Items.CopperIngot] = 1800,
        [Items.TinIngot] = 3500,
        [Items.SilverIngot] = 8000,
        [Items.GoldIngot] = 60_000,
        [Items.Nails] = 25,
        [Items.Wheat] = 60,
        [Items.Carrot] = 90,
        [Items.Potato] = 150,
        [Items.Corn] = 220,
        [Items.Cabbage] = 250,
        [Items.Sunflower] = 300,
        [Items.SortingMachine] = 50_000,
        [Items.Workbench] = 3000,
        [Items.Furnace] = 1500,
        [Items.BrickFurnace] = 6000,
        [Items.BlastFurnace] = 30_000,
        [Items.Axe] = 500,
        [Items.Shovel] = 500,
        [Items.Pickaxe] = 500,
        [Items.Hoe] = 500,
        [Items.Chainsaw] = 10_000,
        [Items.Shears] = 500,
        [Items.Chicken] = 1000,
        [Items.Sheep] = 5000,
        [Items.Cow] = 12_000,
        [Items.Egg] = 80,
        [Items.Wool] = 500,
        [Items.Milk] = 250,
        [Items.Anvil] = 5000,
        [Items.Belt] = 200,
        [Items.Inserter] = 1200,
        [Items.Splitter] = 1600,
        [Items.FastBelt] = 900,
        [Items.ExpressBelt] = 2500,
        [Items.FastInserter] = 3500,
        [Items.ExpressInserter] = 12_000,
        [Items.WoodenChest] = 800,
        [Items.IronChest] = 2500,
        [Items.WoodPile] = 300,
        [Items.Heap] = 500,
        [Items.GrainSilo] = 6000,
        [Items.Mill] = 3000,
        [Items.OilPress] = 3000,
        [Items.PicklingBarrel] = 1000,
        [Items.Bakery] = 4000,
        [Items.Kitchen] = 5000,
        [Items.Computer] = 20_000,
        [Items.Flour] = 200,
        [Items.CornFlour] = 600,
        [Items.SunflowerOil] = 900,
        [Items.Sauerkraut] = 350,
        [Items.Bread] = 700,
        [Items.CornBread] = 1600,
        [Items.CarrotCake] = 2400,
        [Items.Fries] = 900,
        [Items.VegetableSoup] = 1100,
        [Items.Bigos] = 750,
        [Items.ScrambledEggs] = 450,
        [Items.Generator] = 4000,
        [Items.Pole] = 100,
        [Items.ForesterHut] = 4000,
        [Items.ForesterLodge] = 15_000,
        [Items.ForestryStation] = 40_000,
        [Items.Sawmill] = 3000,
        [Items.ElectricSawmill] = 10_000,
        [Items.IndustrialSawmill] = 35_000,
        [Items.Planks] = 150,
        [Items.Beams] = 500,
        [Items.WoodPellets] = 100,
        [Items.Plywood] = 600,
    };

    static NpcPrices()
    {
        var sells = new Dictionary<string, long>(OwnSells);
        foreach (var (item, pays) in Buys)
        {
            sells.TryAdd(item, pays * Markup);
        }

        Sells = sells;
    }

    public const int MaxQuantity = 1000;
}

public sealed record TradeRequest(string Item, int Quantity);

public sealed class MarketService(GameDb db, IInventory inventory, IWallet wallet, TraderMarket trader, ITechnologies technologies)
{
    /// <summary>The player buys from the NPC: money out, items in, both or neither.</summary>
    public Task<long> BuyAsync(Guid owner, string item, int quantity, CancellationToken cancellationToken)
    {
        var price = Price(trader.Prices().Sells, item, quantity, "The trader doesn't sell this item.");
        return db.InTransactionAsync(async () =>
        {
            // Machines and logistics come from the trader only once researched.
            await technologies.RequireUnlockedAsync(owner, item, cancellationToken);
            var balance = await wallet.DebitAsync(owner, price * quantity, $"buy {quantity} {item}", cancellationToken);
            await inventory.AddAsync(owner, item, quantity, cancellationToken);
            return balance;
        }, cancellationToken);
    }

    /// <summary>The player sells to the NPC: items out, money in, both or neither.</summary>
    public Task<long> SellAsync(Guid owner, string item, int quantity, CancellationToken cancellationToken)
    {
        var price = Price(trader.Prices().Buys, item, quantity, "The trader doesn't buy this item.");
        return db.InTransactionAsync(async () =>
        {
            await inventory.RemoveAsync(owner, item, quantity, cancellationToken);
            return await wallet.CreditAsync(owner, price * quantity, $"sell {quantity} {item}", cancellationToken);
        }, cancellationToken);
    }

    private static long Price(IReadOnlyDictionary<string, long> prices, string item, int quantity, string notTraded)
    {
        if (quantity is < 1 or > NpcPrices.MaxQuantity)
        {
            throw new GameException("bad_quantity", $"Quantity must be 1-{NpcPrices.MaxQuantity}.");
        }

        return prices.TryGetValue(item ?? "", out var price) ? price : throw new GameException("not_traded", notTraded);
    }
}

/// <summary>The trader's prices now, how far they are from the usual ones, and its current and next event.</summary>
public sealed class PricesHandler(TraderMarket trader, IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "market.prices";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var prices = trader.Prices();
        await using var scope = scopes.CreateAsyncScope();
        var locked = await scope.ServiceProvider.GetRequiredService<ITechnologies>().LockedAsync(client.RequireAccount(), cancellationToken);
        // What this player hasn't researched yet the trader doesn't offer at all; it still buys it back.
        bool Sold(string id) => prices.Sells.ContainsKey(id) && !locked.ContainsKey(id);
        return new Reply("market.prices", new
        {
            items = Items.Names.Keys
                .Where(id => Sold(id) || prices.Buys.ContainsKey(id))
                .Select(id => new
                {
                    id,
                    name = Items.Names[id],
                    buyCents = Sold(id) ? prices.Sells[id] : (long?)null,
                    buyChange = Sold(id) ? TraderPrices.Change(prices.Sells[id], NpcPrices.Sells[id]) : (int?)null,
                    sellCents = prices.Buys.TryGetValue(id, out var sell) ? sell : (long?)null,
                    sellChange = prices.Buys.ContainsKey(id) ? TraderPrices.Change(sell, NpcPrices.Buys[id]) : (int?)null,
                }),
            @event = Describe(prices.Event),
            next = Describe(trader.NextEvent()),
            serverTime = trader.Now.ToUnixTimeMilliseconds(),
        });
    }

    private static object? Describe(ScheduledEvent? scheduled) => scheduled is not { Event: var e } ? null : new
    {
        id = e.Id,
        name = e.Name,
        description = e.Description,
        startsAtMs = scheduled.StartsAt.ToUnixTimeMilliseconds(),
        endsAtMs = scheduled.EndsAt.ToUnixTimeMilliseconds(),
        effects = e.Pays.Keys.Union(e.Charges.Keys)
            .Where(Items.Names.ContainsKey)
            .Select(item => new
            {
                item,
                name = Items.Names[item],
                sellChange = e.Pays.TryGetValue(item, out var pays) ? pays : (int?)null,
                buyChange = e.Charges.TryGetValue(item, out var charges) ? charges : (int?)null,
            }),
    };
}

public abstract class TradeHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<TradeRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var market = scope.ServiceProvider.GetRequiredService<MarketService>();
        var balance = await TradeAsync(market, client.RequireAccount(), request, cancellationToken);
        return new Reply("market.traded", new { item = request.Item, quantity = request.Quantity, balanceCents = balance });
    }

    protected abstract Task<long> TradeAsync(MarketService market, Guid owner, TradeRequest request, CancellationToken cancellationToken);
}

public sealed class BuyHandler(IServiceScopeFactory scopes) : TradeHandler(scopes)
{
    public override string Type => "market.buy";

    protected override Task<long> TradeAsync(MarketService market, Guid owner, TradeRequest request, CancellationToken cancellationToken) =>
        market.BuyAsync(owner, request.Item, request.Quantity, cancellationToken);
}

public sealed class SellHandler(IServiceScopeFactory scopes) : TradeHandler(scopes)
{
    public override string Type => "market.sell";

    protected override Task<long> TradeAsync(MarketService market, Guid owner, TradeRequest request, CancellationToken cancellationToken) =>
        market.SellAsync(owner, request.Item, request.Quantity, cancellationToken);
}

/// <summary>Buying from and selling to the NPC trader, and trading between players. Owns the <c>market</c> schema.</summary>
public sealed class MarketModule : IGameModule
{
    public string Name => "Market";

    public void RegisterServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddModuleDbContext<MarketDbContext>(MarketDbContext.Schema);
        services.AddSingleton<TraderMarket>();
        services.AddScoped<MarketService>();
        services.AddScoped<PlayerMarketService>();
        services.AddSingleton<IMessageHandler, PricesHandler>();
        services.AddSingleton<IMessageHandler, BuyHandler>();
        services.AddSingleton<IMessageHandler, SellHandler>();
        services.AddSingleton<IMessageHandler, OverviewHandler>();
        services.AddSingleton<IMessageHandler, ItemBoardHandler>();
        services.AddSingleton<IMessageHandler, MineHandler>();
        services.AddSingleton<IMessageHandler, ListHandler>();
        services.AddSingleton<IMessageHandler, UnlistHandler>();
        services.AddSingleton<IMessageHandler, PurchaseHandler>();
        services.AddSingleton<IMessageHandler, OrderHandler>();
        services.AddSingleton<IMessageHandler, CancelOrderHandler>();
        services.AddSingleton<IMessageHandler, FillHandler>();
    }

    public Task InitializeAsync(IServiceProvider services, CancellationToken cancellationToken) =>
        services.MigrateModuleAsync<MarketDbContext>(cancellationToken);
}
