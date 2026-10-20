using FactoryWorld.Modules.Recycling;

namespace FactoryWorld.Server.Tests;

public sealed class GarageTests(ServerFactory factory) : IClassFixture<ServerFactory>
{
    private static readonly string[] Waste = ["waste_paper", "waste_plastic", "waste_aluminium", "waste_glass", "waste_copper"];

    [Fact]
    public async Task New_garage_has_50_trash_and_no_money()
    {
        using var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();

        var garage = await client.SendAsync("garage.get");

        Assert.Equal("garage", garage.Type());
        Assert.Equal(50, garage.Payload().GetProperty("trash").GetInt64());
        Assert.Equal(0, garage.Payload().GetProperty("queue").GetArrayLength());
        Assert.Equal(0, await client.BalanceAsync());
        Assert.Equal(50, (await client.InventoryAsync())["trash"]);
    }

    [Fact]
    public async Task Starting_trash_is_given_only_once()
    {
        using var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();

        await client.SendAsync("garage.get");
        var again = await client.SendAsync("garage.get");

        Assert.Equal(50, again.Payload().GetProperty("trash").GetInt64());
    }

    [Fact]
    public async Task Sorting_takes_10_seconds_each_and_gives_waste_and_xp()
    {
        using var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();
        await client.SendAsync("garage.get");

        var queued = await client.SendAsync("recycling.sort", new { count = 3 });
        Assert.Equal(47, queued.Payload().GetProperty("trash").GetInt64());
        Assert.Equal(3, queued.Payload().GetProperty("queue").GetArrayLength());

        factory.Time.Advance(TimeSpan.FromSeconds(9));
        Assert.Equal(0, (await client.SendAsync("garage.get")).Payload().GetProperty("results").GetArrayLength());

        factory.Time.Advance(TimeSpan.FromSeconds(1));
        var first = await client.SendAsync("garage.get");
        Assert.Equal(1, first.Payload().GetProperty("results").GetArrayLength());
        Assert.Equal(5, first.Payload().GetProperty("xp").GetProperty("xp").GetInt64());
        Assert.Equal(2, first.Payload().GetProperty("queue").GetArrayLength());

        factory.Time.Advance(TimeSpan.FromSeconds(20));
        var rest = await client.SendAsync("garage.get");
        Assert.Equal(2, rest.Payload().GetProperty("results").GetArrayLength());
        Assert.Equal(15, rest.Payload().GetProperty("xp").GetProperty("xp").GetInt64());

        var inventory = await client.InventoryAsync();
        Assert.Equal(3, Waste.Sum(w => inventory.GetValueOrDefault(w)));
        Assert.Equal(47, inventory["trash"]);
    }

    [Fact]
    public async Task Finished_sortings_are_collected_once()
    {
        using var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();
        await client.SendAsync("recycling.sort", new { count = 1 });
        factory.Time.Advance(TimeSpan.FromSeconds(10));

        Assert.Equal(1, (await client.SendAsync("garage.get")).Payload().GetProperty("results").GetArrayLength());
        Assert.Equal(0, (await client.SendAsync("garage.get")).Payload().GetProperty("results").GetArrayLength());
    }

    [Fact]
    public async Task Queue_holds_at_most_10()
    {
        using var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();

        Assert.Equal("garage", (await client.SendAsync("recycling.sort", new { count = 10 })).Type());
        Assert.Equal("queue_full", (await client.SendAsync("recycling.sort", new { count = 1 })).ErrorCode());
        Assert.Equal("bad_quantity", (await client.SendAsync("recycling.sort", new { count = 11 })).ErrorCode());
        Assert.Equal("bad_quantity", (await client.SendAsync("recycling.sort", new { count = 0 })).ErrorCode());
    }

    [Fact]
    public async Task Cannot_sort_without_trash()
    {
        using var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();
        for (var i = 0; i < 5; i++)
        {
            await client.SendAsync("recycling.sort", new { count = 10 });
            factory.Time.Advance(TimeSpan.FromSeconds(100));
            await client.SendAsync("garage.get");
        }

        var reply = await client.SendAsync("recycling.sort", new { count = 1 });

        Assert.Equal("not_enough_items", reply.ErrorCode());
    }

    [Fact]
    public void Drop_chances_match_the_design()
    {
        var counts = Enumerable.Range(0, 100).GroupBy(RecyclingRules.DropForRoll).ToDictionary(g => g.Key, g => g.Count());

        Assert.Equal(30, counts["waste_paper"]);
        Assert.Equal(25, counts["waste_plastic"]);
        Assert.Equal(20, counts["waste_aluminium"]);
        Assert.Equal(15, counts["waste_glass"]);
        Assert.Equal(10, counts["waste_copper"]);
    }
}

public sealed class MarketTests(ServerFactory factory) : IClassFixture<ServerFactory>
{
    private static readonly Dictionary<string, long> SellPrices = new()
    {
        ["waste_paper"] = 100, ["waste_plastic"] = 200, ["waste_aluminium"] = 600, ["waste_glass"] = 200, ["waste_copper"] = 1500,
    };

    [Fact]
    public async Task Selling_sorted_waste_pays_npc_prices()
    {
        using var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();
        await client.SendAsync("recycling.sort", new { count = 5 });
        factory.Time.Advance(TimeSpan.FromSeconds(50));
        await client.SendAsync("garage.get");

        long expected = 0;
        foreach (var (item, quantity) in (await client.InventoryAsync()).Where(i => i.Key != "trash"))
        {
            var reply = await client.SendAsync("market.sell", new { item, quantity });
            Assert.Equal("market.traded", reply.Type());
            expected += SellPrices[item] * quantity;
        }

        Assert.Equal(expected, await client.BalanceAsync());
        Assert.Equal(["trash"], (await client.InventoryAsync()).Keys);
    }

    [Fact]
    public async Task Buying_trash_costs_2_dollars_each()
    {
        using var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();
        await client.SendAsync("recycling.sort", new { count = 10 });
        factory.Time.Advance(TimeSpan.FromSeconds(100));
        await client.SendAsync("garage.get");
        foreach (var (item, quantity) in (await client.InventoryAsync()).Where(i => i.Key != "trash"))
        {
            await client.SendAsync("market.sell", new { item, quantity });
        }

        // 10 sortings earn at least 10 × 1 $, enough for 5 trash.
        var before = await client.BalanceAsync();

        var reply = await client.SendAsync("market.buy", new { item = "trash", quantity = before / 200 });

        Assert.Equal("market.traded", reply.Type());
        Assert.Equal(before % 200, await client.BalanceAsync());
        Assert.Equal(40 + before / 200, (await client.InventoryAsync())["trash"]);
    }

    [Fact]
    public async Task Failed_trades_change_nothing()
    {
        using var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();
        await client.SendAsync("garage.get");

        Assert.Equal("not_enough_money", (await client.SendAsync("market.buy", new { item = "trash", quantity = 1 })).ErrorCode());
        Assert.Equal("not_enough_items", (await client.SendAsync("market.sell", new { item = "waste_copper", quantity = 1 })).ErrorCode());
        Assert.Equal("not_traded", (await client.SendAsync("market.sell", new { item = "trash", quantity = 1 })).ErrorCode());
        Assert.Equal("not_traded", (await client.SendAsync("market.buy", new { item = "waste_copper", quantity = 1 })).ErrorCode());
        Assert.Equal("bad_quantity", (await client.SendAsync("market.buy", new { item = "trash", quantity = 0 })).ErrorCode());

        Assert.Equal(0, await client.BalanceAsync());
        Assert.Equal(new Dictionary<string, long> { ["trash"] = 50 }, await client.InventoryAsync());
    }

    [Fact]
    public async Task Prices_list_trash_and_waste()
    {
        using var client = await factory.ConnectAsync();
        await client.RegisterAsync();

        var items = (await client.SendAsync("market.prices")).Payload().GetProperty("items").EnumerateArray().ToList();

        Assert.Equal(200, items.Single(i => i.GetProperty("id").GetString() == "trash").GetProperty("buyCents").GetInt64());
        Assert.Equal(1500, items.Single(i => i.GetProperty("id").GetString() == "waste_copper").GetProperty("sellCents").GetInt64());
    }
}
