using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using FactoryWorld.Modules.Bots;
using FactoryWorld.Modules.Research;
using FactoryWorld.Modules.World;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Server.Tests;

/// <summary>Bots asking players to put up the parts of their lines they cannot get, on a database of their own.</summary>
public sealed class BotLineHelpTests(ServerFactory factory) : IClassFixture<ServerFactory>
{
    private static readonly WorldMap Map = WorldMap.Load();

    private BotEngine Engine => factory.Services.GetRequiredService<BotEngine>();

    /// <summary>
    /// A farmer of its own for each test, on a grassland plot (where it puts up nothing of its line for its yard), with
    /// money, the research its line takes and what it is given.
    /// </summary>
    private async Task<Bot> FarmerAsync(int which, params (string Item, long Quantity)[] given)
    {
        await Engine.EnsureBotsAsync(CancellationToken.None);
        var bot = Engine.Bots.Where(b => b.Profile.Trade == BotTrade.Farmer).ElementAt(which);
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            var services = scope.ServiceProvider;
            await services.GetRequiredService<IWallet>().CreditAsync(bot.Row.AccountId, 20_000_00, "test", CancellationToken.None);
            foreach (var tech in new[] { TechTree.Logistics, TechTree.Automation, TechTree.Milling })
            {
                await using var insert = await services.GetRequiredService<GameDb>().CommandAsync(
                    "INSERT INTO research.technologies (owner_id, technology, starts_at, finishes_at, rewarded) VALUES (@owner, @tech, @at, @at, true)",
                    CancellationToken.None);
                insert.Parameters.AddWithValue("owner", bot.Row.AccountId);
                insert.Parameters.AddWithValue("tech", tech);
                insert.Parameters.AddWithValue("at", factory.Time.GetUtcNow() - TimeSpan.FromHours(1));
                await insert.ExecuteNonQueryAsync(CancellationToken.None);
            }

            foreach (var (item, quantity) in given)
            {
                await services.GetRequiredService<IInventory>().AddAsync(bot.Row.AccountId, item, quantity, CancellationToken.None);
            }
        }

        var skip = 2000 + which * 50;
        for (var y = 0; y < Map.Height; y += 5)
        {
            for (var x = 0; x < Map.Width; x += 5)
            {
                if (Map.BiomeAt(x, y) == Biome.Grassland && skip-- <= 0
                    && (await bot.Client.SendAsync("world.buy", new { x, y }, CancellationToken.None)).Is("world.bought"))
                {
                    bot.EndSession();
                    return bot;
                }
            }
        }

        throw new InvalidOperationException("No plot.");
    }

    private static async Task<HelpRequest> StepUntilHelpAsync(BotEngine engine, Bot bot, ServerFactory factory)
    {
        var actions = new List<string?>();
        for (var i = 0; i < 200 && bot.Help is null; i++)
        {
            factory.Time.Advance(TimeSpan.FromMinutes(1));
            actions.Add(await engine.StepAsync(bot.Profile.Name, CancellationToken.None));
        }

        Assert.True(bot.Help is not null, "No call for help: " + string.Join(", ", actions.GroupBy(a => a ?? "-").Select(g => $"{g.Key} ×{g.Count()}")));
        return bot.Help!;
    }

    /// <summary>Where the parts of the line stand whose generator is to stand on the tile.</summary>
    private static List<(string Kind, int X, int Y)> LineAround(int generatorX, int generatorY) =>
        BotFactory.Layout(Items.Mill).Select(p => (p.Kind, generatorX - BotFactory.GeneratorX + p.Dx, generatorY - BotFactory.GeneratorY + p.Dy)).ToList();

    [Fact]
    public async Task A_bot_that_cannot_get_inserters_belts_poles_or_a_generator_puts_its_line_up_without_them_and_players_set_it_going()
    {
        // The mill and the chests it has; the rest takes iron and copper, which it has none of.
        var bot = await FarmerAsync(0, (Items.Mill, 1), (Items.WoodenChest, 3), (Items.Wheat, 200), (Items.Wood, 200));
        using var player = await factory.ConnectAsync();
        await player.RegisterWithCharacterAsync();

        var help = await StepUntilHelpAsync(Engine, bot, factory);
        Assert.Equal(HelpReasons.Parts, help.Reason);
        Assert.All(help.Tasks, t => Assert.Contains(t.Kind, BotRules.HelpParts));
        var generator = Assert.Single(help.Tasks, t => t.Kind == Items.Generator);
        var line = LineAround(generator.TileX, generator.TileY);
        Assert.All(help.Tasks, t => Assert.Contains((t.Kind, t.TileX, t.TileY), line));

        // The call shows over the plot on everyone's map, and pays no more than the trader charges for the parts.
        var call = Assert.Single((await player.SendAsync("bots.helpWanted")).Payload().GetProperty("requests").EnumerateArray(),
            c => c.GetProperty("bot").GetString() == bot.Row.CharacterName);
        Assert.Equal((help.X, help.Y), (call.GetProperty("x").GetInt32(), call.GetProperty("y").GetInt32()));
        Assert.Equal(help.Tasks.Count, call.GetProperty("tasks").GetArrayLength());
        var pay = call.GetProperty("payCents").GetInt64();
        var prices = factory.Services.GetRequiredService<IMarketPrices>();
        Assert.InRange(pay, BotRules.HelpFee, (long)(help.Tasks.Sum(t => prices.SellsCents(t.Kind)!.Value) * BotRules.HelpBelowTrader));

        // A player brings the parts, puts each where the bot wants it, and is paid once the last stands.
        foreach (var need in call.GetProperty("needs").EnumerateArray())
        {
            await using var scope = factory.Services.CreateAsyncScope();
            await scope.ServiceProvider.GetRequiredService<IInventory>()
                .AddAsync(player.AccountId, need.GetProperty("id").GetString()!, need.GetProperty("quantity").GetInt64(), CancellationToken.None);
        }

        var (x, y) = (help.X, help.Y);
        var before = await player.BalanceAsync();
        Assert.Equal("bots.helping", (await player.SendAsync("bots.help", new { x, y })).Type());
        JsonElement placed = default;
        foreach (var task in help.Tasks)
        {
            placed = await player.SendAsync("plot.place", new { x, y, kind = task.Kind, tileX = task.TileX, tileY = task.TileY, rotation = task.Rotation });
            Assert.True(placed.Type() == "plot.placed", placed.ToString());
        }

        Assert.True(placed.Payload().GetProperty("help").GetProperty("finished").GetBoolean());
        Assert.Equal(before + pay, await player.BalanceAsync());

        // The line works: flour comes out of the mill into the output chest.
        await Engine.StepAsync(bot.Profile.Name, CancellationToken.None);
        Assert.Null(bot.Help);
        var output = line.Single(p => p.Kind == Items.WoodenChest && p.X == line.Max(c => c.X));
        var chest = (await bot.Client.SendAsync("plot.enter", new { x, y }, CancellationToken.None)).Payload.GetProperty("objects").EnumerateArray()
            .Single(o => o.GetProperty("tileX").GetInt32() == output.X && o.GetProperty("tileY").GetInt32() == output.Y).GetProperty("id").GetString();
        long flour = 0;
        for (var i = 0; i < 40 && flour == 0; i++)
        {
            factory.Time.Advance(TimeSpan.FromMinutes(1));
            await Engine.StepAsync(bot.Profile.Name, CancellationToken.None);
            flour = (await bot.Client.SendAsync("storage.get", new { x, y, id = chest }, CancellationToken.None)).Payload.GetProperty("items").EnumerateArray()
                .Where(i => i.GetProperty("id").GetString() == Items.Flour).Sum(i => i.GetProperty("quantity").GetInt64());
        }

        Assert.True(flour > 0);
    }

    [Fact]
    public async Task After_a_restart_a_bot_sees_on_its_plot_what_its_line_lacks_and_asks_for_it_again()
    {
        var bot = await FarmerAsync(1,
            (Items.Mill, 1), (Items.WoodenChest, 3), (Items.Inserter, 3), (Items.Belt, 2), (Items.Pole, 2), (Items.Generator, 1),
            (Items.Wheat, 200), (Items.Wood, 200));
        for (var i = 0; i < 200 && !bot.HasLine; i++)
        {
            factory.Time.Advance(TimeSpan.FromMinutes(1));
            await Engine.StepAsync(bot.Profile.Name, CancellationToken.None);
        }

        Assert.True(bot.HasLine);
        Assert.Null(bot.Help);

        // The generator and an inserter are gone from its line, and from its hands: it lost them before the server restarted,
        // and with the restart what it meant to ask for.
        var (x, y) = (0, 0);
        List<JsonElement> objects = [];
        var info = (await bot.Client.SendAsync("world.info", null, CancellationToken.None)).Payload;
        foreach (var plot in info.GetProperty("plots").EnumerateArray())
        {
            (x, y) = (plot.GetProperty("x").GetInt32(), plot.GetProperty("y").GetInt32());
            objects = (await bot.Client.SendAsync("plot.enter", new { x, y }, CancellationToken.None)).Payload.GetProperty("objects").EnumerateArray().ToList();
            if (objects.Any(o => o.GetProperty("kind").GetString() == Items.Generator))
            {
                break;
            }
        }

        var generator = objects.Single(o => o.GetProperty("kind").GetString() == Items.Generator);
        var (gx, gy) = (generator.GetProperty("tileX").GetInt32(), generator.GetProperty("tileY").GetInt32());
        var feeder = LineAround(gx, gy).First(p => p.Kind == Items.Inserter);
        var inserter = objects.Single(o => o.GetProperty("kind").GetString() == Items.Inserter
            && o.GetProperty("tileX").GetInt32() == feeder.X && o.GetProperty("tileY").GetInt32() == feeder.Y);
        foreach (var part in new[] { generator, inserter })
        {
            Assert.Equal("plot.pickedUp", (await bot.Client.SendAsync("plot.pickup", new { x, y, id = part.GetProperty("id").GetString() }, CancellationToken.None)).Type);
        }

        await using (var scope = factory.Services.CreateAsyncScope())
        {
            var inventory = scope.ServiceProvider.GetRequiredService<IInventory>();
            await inventory.RemoveAsync(bot.Row.AccountId, Items.Generator, 1, CancellationToken.None);
            await inventory.RemoveAsync(bot.Row.AccountId, Items.Inserter, 1, CancellationToken.None);
        }

        var restarted = ActivatorUtilities.CreateInstance<BotEngine>(factory.Services);
        await restarted.EnsureBotsAsync(CancellationToken.None);
        var again = restarted.Bots.Single(b => b.Profile.Name == bot.Profile.Name);
        Assert.Null(again.Help);

        var help = await StepUntilHelpAsync(restarted, again, factory);
        Assert.Equal(HelpReasons.Parts, help.Reason);
        Assert.Equal((x, y), (help.X, help.Y));
        Assert.Equal(
            new[] { (Items.Generator, gx, gy), (Items.Inserter, feeder.X, feeder.Y) }.OrderBy(t => t.Item1),
            help.Tasks.Select(t => (t.Kind, t.TileX, t.TileY)).OrderBy(t => t.Kind));
        using var player = await factory.ConnectAsync();
        await player.RegisterWithCharacterAsync();
        Assert.Contains((await player.SendAsync("bots.helpWanted")).Payload().GetProperty("requests").EnumerateArray(),
            c => c.GetProperty("bot").GetString() == bot.Row.CharacterName);
    }

    [Fact]
    public async Task A_bot_whose_missing_part_has_something_in_its_place_takes_its_line_down_rather_than_ask_for_it()
    {
        var bot = await FarmerAsync(2,
            (Items.Mill, 1), (Items.WoodenChest, 3), (Items.Inserter, 3), (Items.Belt, 2), (Items.Pole, 2), (Items.Generator, 1),
            (Items.Wheat, 200), (Items.Wood, 200));
        for (var i = 0; i < 200 && !bot.HasLine; i++)
        {
            factory.Time.Advance(TimeSpan.FromMinutes(1));
            await Engine.StepAsync(bot.Profile.Name, CancellationToken.None);
        }

        Assert.True(bot.HasLine);

        // The generator is gone, and a chest stands where it stood; then the server restarts.
        var (x, y) = (0, 0);
        List<JsonElement> objects = [];
        foreach (var plot in (await bot.Client.SendAsync("world.info", null, CancellationToken.None)).Payload.GetProperty("plots").EnumerateArray())
        {
            (x, y) = (plot.GetProperty("x").GetInt32(), plot.GetProperty("y").GetInt32());
            objects = (await bot.Client.SendAsync("plot.enter", new { x, y }, CancellationToken.None)).Payload.GetProperty("objects").EnumerateArray().ToList();
            if (objects.Any(o => o.GetProperty("kind").GetString() == Items.Generator))
            {
                break;
            }
        }

        var generator = objects.Single(o => o.GetProperty("kind").GetString() == Items.Generator);
        var (gx, gy) = (generator.GetProperty("tileX").GetInt32(), generator.GetProperty("tileY").GetInt32());
        Assert.Equal("plot.pickedUp", (await bot.Client.SendAsync("plot.pickup", new { x, y, id = generator.GetProperty("id").GetString() }, CancellationToken.None)).Type);
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            var inventory = scope.ServiceProvider.GetRequiredService<IInventory>();
            await inventory.RemoveAsync(bot.Row.AccountId, Items.Generator, 1, CancellationToken.None);
            await inventory.AddAsync(bot.Row.AccountId, Items.WoodenChest, 1, CancellationToken.None);
        }

        var chest = await bot.Client.SendAsync("plot.place", new { x, y, kind = Items.WoodenChest, tileX = gx, tileY = gy, rotation = 0 }, CancellationToken.None);
        Assert.True(chest.Is("plot.placed"), chest.Error);
        var restarted = ActivatorUtilities.CreateInstance<BotEngine>(factory.Services);
        await restarted.EnsureBotsAsync(CancellationToken.None);
        var again = restarted.Bots.Single(b => b.Profile.Name == bot.Profile.Name);

        // Nobody could put the generator up: the bot does not ask for it, it takes its line down to build it elsewhere.
        var mills = 1;
        for (var i = 0; i < 30 && mills > 0; i++)
        {
            factory.Time.Advance(TimeSpan.FromMinutes(1));
            await restarted.StepAsync(again.Profile.Name, CancellationToken.None);
            Assert.Null(again.Help);
            mills = (await bot.Client.SendAsync("plot.enter", new { x, y }, CancellationToken.None)).Payload.GetProperty("objects").EnumerateArray()
                .Count(o => o.GetProperty("kind").GetString() == Items.Mill);
        }

        Assert.Equal(0, mills);
    }
}
