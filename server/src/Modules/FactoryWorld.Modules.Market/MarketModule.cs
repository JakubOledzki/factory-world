using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Market;

/// <summary>
/// The NPC trader: always sells trash, saplings, nails, belts, inserters, wooden chests, machines, the computer, flour, oil and bread and always buys raw materials.
/// These are its usual prices (cents); <see cref="TraderPrices"/> moves them with the day's drift and the market's events.
/// What it pays is the floor of the market: a quick sale gets it at once, players' listings usually pay more.
/// </summary>
public static class NpcPrices
{
    /// <summary>What the NPC charges the player.</summary>
    public static readonly IReadOnlyDictionary<string, long> Sells = new Dictionary<string, long>
    {
        [Items.Trash] = 100,
        [Items.SortingMachine] = 100_000,
        [Items.Sapling] = 200,
        [Items.Nails] = 100,
        [Items.Workbench] = 50_000,
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
        [Items.Axe] = 500,
        [Items.Shovel] = 500,
        [Items.Pickaxe] = 500,
        [Items.Hoe] = 500,
        [Items.Belt] = 200,
        [Items.Inserter] = 1200,
        [Items.Splitter] = 1600,
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
    };

    public const int MaxQuantity = 1000;
}

public sealed record TradeRequest(string Item, int Quantity);

public sealed class MarketService(GameDb db, IInventory inventory, IWallet wallet, TraderMarket trader)
{
    /// <summary>The player buys from the NPC: money out, items in, both or neither.</summary>
    public Task<long> BuyAsync(Guid owner, string item, int quantity, CancellationToken cancellationToken)
    {
        var price = Price(trader.Prices().Sells, item, quantity, "The trader doesn't sell this item.");
        return db.InTransactionAsync(async () =>
        {
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
public sealed class PricesHandler(TraderMarket trader) : IMessageHandler
{
    public string Type => "market.prices";

    public Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var prices = trader.Prices();
        return Task.FromResult(new Reply("market.prices", new
        {
            items = Items.Names.Keys
                .Where(id => prices.Sells.ContainsKey(id) || prices.Buys.ContainsKey(id))
                .Select(id => new
                {
                    id,
                    name = Items.Names[id],
                    buyCents = prices.Sells.TryGetValue(id, out var buy) ? buy : (long?)null,
                    buyChange = prices.Sells.ContainsKey(id) ? TraderPrices.Change(buy, NpcPrices.Sells[id]) : (int?)null,
                    sellCents = prices.Buys.TryGetValue(id, out var sell) ? sell : (long?)null,
                    sellChange = prices.Buys.ContainsKey(id) ? TraderPrices.Change(sell, NpcPrices.Buys[id]) : (int?)null,
                }),
            @event = Describe(prices.Event),
            next = Describe(trader.NextEvent()),
            serverTime = trader.Now.ToUnixTimeMilliseconds(),
        }));
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
