using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using FactoryWorld.Modules.Bots;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Server.Tests;

/// <summary>The production line a bot builds, without a database.</summary>
public sealed class BotFactoryRulesTests
{
    [Fact]
    public void A_bot_line_is_a_chest_an_inserter_two_belts_an_inserter_the_machine_an_inserter_and_a_chest_on_power()
    {
        var layout = BotFactory.Layout(Items.Furnace);
        var row = layout.Where(p => p.Dy == 0).OrderBy(p => p.Dx).Select(p => p.Kind);
        Assert.Equal(
            [Items.WoodenChest, Items.Inserter, Items.Belt, Items.Belt, Items.Inserter, Items.Furnace, Items.Inserter, Items.WoodenChest],
            row);

        // Each pole powers 5 × 5 tiles: every inserter is in reach of one, and the poles reach each other.
        var poles = layout.Where(p => p.Kind == Items.Pole).ToList();
        Assert.Equal(2, poles.Count);
        Assert.All(layout.Where(p => p.Kind == Items.Inserter), i =>
            Assert.Contains(poles, p => Math.Abs(p.Dx - i.Dx) <= 2 && Math.Abs(p.Dy - i.Dy) <= 2));
        Assert.True(Math.Abs(poles[0].Dx - poles[1].Dx) <= 7);
        Assert.Single(layout, p => p.Kind == Items.Generator);

        // Nothing overlaps, the 2 × 2 machine included, and all of it fits in the line's rectangle.
        var tiles = layout.SelectMany(p => Footprints.Tiles(p.Kind, p.Dx, p.Dy)).ToList();
        Assert.Equal(tiles.Count, tiles.Distinct().Count());
        Assert.All(tiles, t => Assert.True(t.X is >= 0 and < BotFactory.Width && t.Y is >= 0 and < BotFactory.Depth, t.ToString()));

        var kit = new BotLine(Items.Mill, Items.Flour, [Items.Wheat], [Items.Wood], [Items.Flour]).Kit.ToDictionary(k => k.Item, k => k.Quantity);
        Assert.Equal(3, kit[Items.Inserter]);
        Assert.Equal(2, kit[Items.Belt]);
        Assert.Equal(1, kit[Items.Mill]);
    }

    [Fact]
    public void Every_trade_but_the_trader_has_a_line_and_researches_what_it_is_made_of_first()
    {
        Assert.Null(BotRules.Line(BotTrade.Trader));
        foreach (var trade in Enum.GetValues<BotTrade>().Where(t => t != BotTrade.Trader))
        {
            Assert.NotNull(BotRules.Line(trade));
            Assert.Contains("automation", BotRules.Research(trade));
        }

        Assert.Equal(Items.Sawmill, BotRules.Line(BotTrade.Forester)!.Machine);
        Assert.Equal(Items.Mill, BotRules.Line(BotTrade.Farmer)!.Machine);
        Assert.Equal(Items.Furnace, BotRules.Line(BotTrade.Smelter)!.Machine);
        // What the lines make goes to the players' market.
        Assert.Contains(Items.Planks, BotRules.Goods);
        Assert.Contains(Items.Flour, BotRules.Goods);
        Assert.Contains(Items.IronIngot, BotRules.Goods);
    }

    [Fact]
    public void A_line_goes_on_the_free_ground_nearest_to_the_spawn_with_room_all_round()
    {
        var blocked = new bool[40, 40];
        var spawn = (X: 20, Y: 2);
        var spot = BotFactory.FindSpot(blocked, spawn);
        Assert.NotNull(spot);
        Assert.True(spot.Value.Y > spawn.Y + 1);
        // Not across the path straight down from the spawn.
        Assert.True(spawn.X < spot.Value.X - 1 || spawn.X > spot.Value.X + BotFactory.Width);

        // A tree in the middle of that spot sends the line elsewhere, clear of the tree and a tile around it.
        var (tx, ty) = (spot.Value.X + 4, spot.Value.Y + 1);
        blocked[tx, ty] = true;
        var other = BotFactory.FindSpot(blocked, spawn)!.Value;
        Assert.False(tx >= other.X - 1 && tx <= other.X + BotFactory.Width && ty >= other.Y - 1 && ty <= other.Y + BotFactory.Depth);

        // No room at all: no line.
        var full = new bool[40, 40];
        for (var x = 0; x < 40; x += 4)
        {
            for (var y = 0; y < 40; y++)
            {
                full[x, y] = true;
            }
        }

        Assert.Null(BotFactory.FindSpot(full, spawn));
    }
}

/// <summary>A bot building its line and working it, on a database of its own.</summary>
public sealed class BotLineTests(ServerFactory factory) : IClassFixture<ServerFactory>
{
    private BotEngine Engine => factory.Services.GetRequiredService<BotEngine>();

    private static long StoredIn(JsonElement storage, string item) =>
        storage.GetProperty("items").EnumerateArray().Where(i => i.GetProperty("id").GetString() == item)
            .Sum(i => i.GetProperty("quantity").GetInt64());

    private async Task GiveAsync(Bot bot, string item, long quantity)
    {
        await using var scope = factory.Services.CreateAsyncScope();
        await scope.ServiceProvider.GetRequiredService<IInventory>().AddAsync(bot.Row.AccountId, item, quantity, CancellationToken.None);
    }

    private static async Task<Dictionary<string, JsonElement>> StoragesAsync(Bot bot, int x, int y) =>
        (await bot.Client.SendAsync("logistics.get", new { x, y }, CancellationToken.None)).Payload
            .GetProperty("storages").EnumerateArray().ToDictionary(s => s.GetProperty("id").GetString()!);

    private static async Task<(int X, int Y, JsonElement Plot)?> LinePlotAsync(Bot bot)
    {
        var info = await bot.Client.SendAsync("world.info", null, CancellationToken.None);
        foreach (var plot in info.Payload.GetProperty("plots").EnumerateArray())
        {
            var (x, y) = (plot.GetProperty("x").GetInt32(), plot.GetProperty("y").GetInt32());
            var inside = await bot.Client.SendAsync("plot.enter", new { x, y }, CancellationToken.None);
            var kinds = inside.Payload.GetProperty("objects").EnumerateArray().Select(o => o.GetProperty("kind").GetString()).ToList();
            if (kinds.Count(k => k == Items.Inserter) >= 3 && kinds.Contains(Items.Generator) && kinds.Count(k => k == Items.Belt) >= 2)
            {
                return (x, y, inside.Payload);
            }
        }

        return null;
    }

    [Fact]
    public async Task A_smelter_bot_researches_builds_a_furnace_line_with_inserters_and_belts_and_it_smelts_while_the_bot_is_away()
    {
        await Engine.EnsureBotsAsync(CancellationToken.None);
        using var player = await factory.ConnectAsync();
        await player.RegisterWithCharacterAsync();
        var bot = Engine.Bots.First(b => b.Profile.Trade == BotTrade.Smelter);
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            await scope.ServiceProvider.GetRequiredService<ICharacterProgress>().AddXpAsync(player.AccountId, 100_000, CancellationToken.None);
            await scope.ServiceProvider.GetRequiredService<IWallet>().CreditAsync(bot.Row.AccountId, 20_000_00, "test", CancellationToken.None);
            var inventory = scope.ServiceProvider.GetRequiredService<IInventory>();
            // What a smelter would have bought from miners over a few sessions.
            foreach (var (item, quantity) in new[]
                     {
                         (Items.IronOre, 300L), (Items.Coal, 150L), (Items.Wood, 300L), (Items.Stone, 200L),
                         (Items.IronIngot, 120L), (Items.CopperIngot, 40L), (Items.Nails, 60L),
                     })
            {
                await inventory.AddAsync(bot.Row.AccountId, item, quantity, CancellationToken.None);
            }
        }

        var actions = new List<string?>();
        for (var i = 0; i < 600 && !bot.HasLine; i++)
        {
            factory.Time.Advance(TimeSpan.FromMinutes(1));
            actions.Add(await Engine.StepAsync(bot.Profile.Name, CancellationToken.None));
        }

        Assert.True(bot.HasLine, "The bot built no line: " + string.Join(", ", actions.GroupBy(a => a ?? "-").Select(g => $"{g.Key} ×{g.Count()}")));
        var line = await LinePlotAsync(bot);
        Assert.NotNull(line);
        var (x, y, plot) = line.Value;
        var objects = plot.GetProperty("objects").EnumerateArray().ToList();
        var furnace = objects.First(o => o.GetProperty("kind").GetString() == Items.Furnace
            && objects.Count(c => c.GetProperty("kind").GetString() == Items.WoodenChest
                && c.GetProperty("tileY").GetInt32() == o.GetProperty("tileY").GetInt32()) >= 2);
        var (fx, fy) = (furnace.GetProperty("tileX").GetInt32(), furnace.GetProperty("tileY").GetInt32());
        string IdAt(string kind, int tx, int ty) => objects.First(o => o.GetProperty("kind").GetString() == kind
            && o.GetProperty("tileX").GetInt32() == tx && o.GetProperty("tileY").GetInt32() == ty).GetProperty("id").GetString()!;
        var input = IdAt(Items.WoodenChest, fx - BotFactory.MachineX, fy);
        var output = IdAt(Items.WoodenChest, fx - BotFactory.MachineX + BotFactory.OutputX, fy);

        // The ore it was given went into its furnaces meanwhile; miners have brought more.
        await GiveAsync(bot, Items.IronOre, 200);
        await GiveAsync(bot, Items.Coal, 60);

        // The bot fills the line on its next looks: ore in the chest, coal in the furnace, fuel in the generator.
        Dictionary<string, JsonElement> storages = [];
        for (var i = 0; i < 30; i++)
        {
            factory.Time.Advance(TimeSpan.FromMinutes(1));
            await Engine.StepAsync(bot.Profile.Name, CancellationToken.None);
            storages = await StoragesAsync(bot, x, y);
            if (StoredIn(storages[input], Items.IronOre) > 0 && StoredIn(storages[output], Items.IronIngot) == 0)
            {
                break;
            }
        }

        var ore = StoredIn(storages[input], Items.IronOre);
        Assert.True(ore > 0, storages[input].ToString());

        // Then it goes away, and the inserters, the belts and the furnace go on without it.
        factory.Time.Advance(TimeSpan.FromMinutes(5));
        storages = await StoragesAsync(bot, x, y);
        Assert.True(StoredIn(storages[output], Items.IronIngot) > 0, storages[output].ToString());
        Assert.True(StoredIn(storages[input], Items.IronOre) < ore, storages[input].ToString());

        // An inserter goes missing: the line stands still, and after a few looks the bot calls for help over its plot.
        await GiveAsync(bot, Items.IronOre, 200);
        var feeder = IdAt(Items.Inserter, fx - 1, fy);
        Assert.Equal("plot.pickedUp", (await bot.Client.SendAsync("plot.pickup", new { x, y, id = feeder }, CancellationToken.None)).Type);
        for (var i = 0; i < 120 && bot.Help is null; i++)
        {
            factory.Time.Advance(TimeSpan.FromMinutes(1));
            await Engine.StepAsync(bot.Profile.Name, CancellationToken.None);
        }

        Assert.NotNull(bot.Help);
        Assert.Equal(HelpReasons.Stalled, bot.Help.Reason);
        var wanted = (await player.SendAsync("bots.helpWanted")).Payload().GetProperty("requests").EnumerateArray().ToList();
        var call = Assert.Single(wanted);
        Assert.Equal(x, call.GetProperty("x").GetInt32());
        Assert.Equal(y, call.GetProperty("y").GetInt32());
        Assert.Equal(bot.Row.CharacterName, call.GetProperty("bot").GetString());

        // A player helps and is paid the fee; the bot sets its line up again and it smelts once more.
        var before = await player.BalanceAsync();
        var helped = await player.SendAsync("bots.help", new { x, y });
        Assert.Equal("bots.helped", helped.Type());
        Assert.Equal(before + BotRules.HelpFee, await player.BalanceAsync());
        Assert.Equal("no_help_needed", (await player.SendAsync("bots.help", new { x, y })).ErrorCode());

        await Engine.StepAsync(bot.Profile.Name, CancellationToken.None);
        Assert.Null(bot.Help);
        for (var i = 0; i < 10 && !bot.HasLine; i++)
        {
            factory.Time.Advance(TimeSpan.FromMinutes(1));
            await Engine.StepAsync(bot.Profile.Name, CancellationToken.None);
        }

        var again = await LinePlotAsync(bot);
        Assert.NotNull(again);
        Assert.Empty((await player.SendAsync("bots.helpWanted")).Payload().GetProperty("requests").EnumerateArray());
    }
}

/// <summary>Players helping bots with parts, on a database of their own.</summary>
public sealed class BotHelpTests(ServerFactory factory) : IClassFixture<ServerFactory>
{
    private BotEngine Engine => factory.Services.GetRequiredService<BotEngine>();

    private BotHelpBoard Board => factory.Services.GetRequiredService<BotHelpBoard>();

    [Fact]
    public async Task A_player_brings_a_bot_the_parts_it_asks_for_and_the_bot_pays_for_them_and_a_little_more()
    {
        await Engine.EnsureBotsAsync(CancellationToken.None);
        var bot = Engine.Bots.First(b => b.Profile.Trade == BotTrade.Farmer);
        using var player = await factory.ConnectAsync();
        await player.RegisterWithCharacterAsync();
        using var other = await factory.ConnectAsync();
        await other.RegisterWithCharacterAsync();
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            await scope.ServiceProvider.GetRequiredService<IWallet>().CreditAsync(bot.Row.AccountId, 500_00, "test", CancellationToken.None);
            await scope.ServiceProvider.GetRequiredService<IInventory>().AddAsync(player.AccountId, Items.Inserter, 3, CancellationToken.None);
        }

        Assert.Equal("no_help_needed", (await player.SendAsync("bots.help", new { x = 10, y = 10 })).ErrorCode());
        const long pay = 200_00;
        long botMoney;
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            botMoney = await scope.ServiceProvider.GetRequiredService<IWallet>().BalanceAsync(bot.Row.AccountId, CancellationToken.None);
        }

        Board.Post(new HelpRequest(bot.Row.Name, bot.Row.CharacterName, bot.Row.AccountId, 10, 10, HelpReasons.Parts,
            [(Items.Inserter, 2)], pay, factory.Time.GetUtcNow()));

        // Someone without the parts cannot answer, and the call stays up for others.
        Assert.Equal("not_enough_items", (await other.SendAsync("bots.help", new { x = 10, y = 10 })).ErrorCode());
        var call = Assert.Single((await other.SendAsync("bots.helpWanted")).Payload().GetProperty("requests").EnumerateArray());
        Assert.Equal(HelpReasons.Parts, call.GetProperty("reason").GetString());
        Assert.Equal(Items.Inserter, call.GetProperty("needs")[0].GetProperty("id").GetString());
        Assert.Equal(pay, call.GetProperty("payCents").GetInt64());

        var balance = await player.BalanceAsync();
        var helped = await player.SendAsync("bots.help", new { x = 10, y = 10 });
        Assert.Equal("bots.helped", helped.Type());
        Assert.Equal(balance + pay, helped.Payload().GetProperty("balanceCents").GetInt64());
        Assert.Equal(1, (await player.InventoryAsync()).GetValueOrDefault(Items.Inserter));
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            var services = scope.ServiceProvider;
            Assert.Equal(2, await services.GetRequiredService<IInventory>().CountAsync(bot.Row.AccountId, Items.Inserter, CancellationToken.None));
            Assert.Equal(botMoney - pay, await services.GetRequiredService<IWallet>().BalanceAsync(bot.Row.AccountId, CancellationToken.None));
        }

        // Answered once only; the map shows no mark any more.
        Assert.Equal("no_help_needed", (await other.SendAsync("bots.help", new { x = 10, y = 10 })).ErrorCode());
        Assert.Empty((await other.SendAsync("bots.helpWanted")).Payload().GetProperty("requests").EnumerateArray());

        // A bot that cannot pay is not helped, and nothing changes hands.
        Board.Post(new HelpRequest(bot.Row.Name, bot.Row.CharacterName, bot.Row.AccountId, 10, 10, HelpReasons.Parts,
            [(Items.Inserter, 1)], 1_000_000_00, factory.Time.GetUtcNow()));
        Assert.Equal("bot_cannot_pay", (await player.SendAsync("bots.help", new { x = 10, y = 10 })).ErrorCode());
        Assert.Equal(1, (await player.InventoryAsync()).GetValueOrDefault(Items.Inserter));
        Board.Withdraw(bot.Row.Name);
    }
}

/// <summary>What bots take out of the economy and put into it, on a database of their own.</summary>
public sealed class BotEconomyTests(ServerFactory factory) : IClassFixture<ServerFactory>
{
    private BotEngine Engine => factory.Services.GetRequiredService<BotEngine>();

    [Fact]
    public async Task A_bot_takes_little_from_the_npc_trader_in_a_session_and_bots_do_not_buy_from_bots_to_sell_on()
    {
        await Engine.EnsureBotsAsync(CancellationToken.None);
        var seller = Engine.Bots.First(b => b.Profile.Trade == BotTrade.Forester);
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            var inventory = scope.ServiceProvider.GetRequiredService<IInventory>();
            await inventory.AddAsync(seller.Row.AccountId, Items.WastePaper, 5000, CancellationToken.None);
            await inventory.AddAsync(seller.Row.AccountId, Items.Cabbage, 40, CancellationToken.None);
        }

        // A bot lists cabbage cheap, as a player could; no bot needs cabbage for its work.
        var cabbage = (await seller.Client.SendAsync("market.prices", null, CancellationToken.None)).Payload.GetProperty("items")
            .EnumerateArray().First(i => i.GetProperty("id").GetString() == Items.Cabbage).GetProperty("sellCents").GetInt64();
        Assert.Equal("market.done", (await seller.Client.SendAsync("market.list",
            new { item = Items.Cabbage, quantity = 40, priceCents = cabbage * 11 / 10 }, CancellationToken.None)).Type);

        var counters = factory.Services.GetRequiredService<GameCounters>();
        long Sold() => counters.MoneyTotals().Where(t => t.Bot && t.Reason == "sell").Sum(t => t.InCents);
        var sold = Sold();
        for (var i = 0; i < 100; i++)
        {
            factory.Time.Advance(TimeSpan.FromSeconds(11));
            foreach (var bot in Engine.Bots)
            {
                await Engine.StepAsync(bot.Profile.Name, CancellationToken.None);
            }
        }

        // One session for every bot: the trader paid each of them no more than the session's limit.
        Assert.True(Sold() - sold <= Engine.Bots.Count * (BotRules.MaxTraderIncome + 1_00), $"{Sold() - sold} cents");
        var mine = (await seller.Client.SendAsync("market.mine", null, CancellationToken.None)).Payload;
        var listing = mine.GetProperty("listings").EnumerateArray().First(l => l.GetProperty("item").GetString() == Items.Cabbage);
        Assert.Equal(0, listing.GetProperty("done").GetInt64());
    }
}
