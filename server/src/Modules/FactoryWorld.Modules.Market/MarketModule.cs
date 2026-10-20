using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Market;

/// <summary>
/// The NPC trader: always sells trash and always buys waste, at fixed prices (cents).
/// Trading between players comes later; these prices are its floor and ceiling.
/// </summary>
public static class NpcPrices
{
    /// <summary>What the NPC charges the player.</summary>
    public static readonly IReadOnlyDictionary<string, long> Sells = new Dictionary<string, long>
    {
        [Items.Trash] = 200,
    };

    /// <summary>What the NPC pays the player.</summary>
    public static readonly IReadOnlyDictionary<string, long> Buys = new Dictionary<string, long>
    {
        [Items.WastePaper] = 100,
        [Items.WastePlastic] = 200,
        [Items.WasteGlass] = 200,
        [Items.WasteAluminium] = 600,
        [Items.WasteCopper] = 1500,
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

/// <summary>Buying from and selling to the NPC trader. Has no tables of its own yet.</summary>
public sealed class MarketModule : IGameModule
{
    public string Name => "Market";

    public void RegisterServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddScoped<MarketService>();
        services.AddSingleton<IMessageHandler, PricesHandler>();
        services.AddSingleton<IMessageHandler, BuyHandler>();
        services.AddSingleton<IMessageHandler, SellHandler>();
    }
}
