using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Market;

/// <summary>
/// The NPC trader: always sells trash, saplings, nails and the sorting machine and always buys raw materials, at fixed prices (cents).
/// What it pays is the floor of the market: a quick sale gets it at once, players' listings usually pay more.
/// </summary>
public static class NpcPrices
{
    /// <summary>What the NPC charges the player.</summary>
    public static readonly IReadOnlyDictionary<string, long> Sells = new Dictionary<string, long>
    {
        [Items.Trash] = 200,
        [Items.SortingMachine] = 100_000,
        [Items.Sapling] = 200,
        [Items.Nails] = 100,
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
        [Items.Axe] = 500,
        [Items.Shovel] = 500,
        [Items.Pickaxe] = 500,
        [Items.Hoe] = 500,
    };

    public const int MaxQuantity = 1000;
}

public sealed record TradeRequest(string Item, int Quantity);

public sealed class MarketService(GameDb db, IInventory inventory, IWallet wallet)
{
    /// <summary>The player buys from the NPC: money out, items in, both or neither.</summary>
    public Task<long> BuyAsync(Guid owner, string item, int quantity, CancellationToken cancellationToken)
    {
        var price = Price(NpcPrices.Sells, item, quantity, "The trader doesn't sell this item.");
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
        var price = Price(NpcPrices.Buys, item, quantity, "The trader doesn't buy this item.");
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

public sealed class PricesHandler : IMessageHandler
{
    public string Type => "market.prices";

    public Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken) =>
        Task.FromResult(new Reply("market.prices", new
        {
            items = Items.Names.Keys
                .Where(id => NpcPrices.Sells.ContainsKey(id) || NpcPrices.Buys.ContainsKey(id))
                .Select(id => new
                {
                    id,
                    name = Items.Names[id],
                    buyCents = NpcPrices.Sells.TryGetValue(id, out var buy) ? buy : (long?)null,
                    sellCents = NpcPrices.Buys.TryGetValue(id, out var sell) ? sell : (long?)null,
                }),
        }));
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
