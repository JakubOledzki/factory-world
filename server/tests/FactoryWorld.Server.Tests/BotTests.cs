using FactoryWorld.Modules.Abstractions.Contracts;
using FactoryWorld.Modules.Bots;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Server.Tests;

public sealed class BotTests(ServerFactory factory) : IClassFixture<ServerFactory>
{
    private BotEngine Engine => factory.Services.GetRequiredService<BotEngine>();

    private async Task<long> XpAsync(Guid account)
    {
        await using var scope = factory.Services.CreateAsyncScope();
        return await scope.ServiceProvider.GetRequiredService<ICharacterXp>().XpAsync(account, CancellationToken.None) ?? 0;
    }

    private async Task GiveMoneyAsync(Guid account, long cents)
    {
        await using var scope = factory.Services.CreateAsyncScope();
        await scope.ServiceProvider.GetRequiredService<IWallet>().CreditAsync(account, cents, "test", CancellationToken.None);
    }

    /// <summary>Lets every bot take <paramref name="steps"/> steps, the clock moving as a player's would between clicks.</summary>
    private async Task PlayAsync(int steps)
    {
        for (var i = 0; i < steps; i++)
        {
            factory.Time.Advance(TimeSpan.FromSeconds(11));
            foreach (var bot in Engine.Bots)
            {
                await Engine.StepAsync(bot.Profile.Name, CancellationToken.None);
            }
        }
    }

    [Fact]
    public async Task Bots_play_like_players_but_never_get_ahead_of_the_best_real_player()
    {
        await Engine.EnsureBotsAsync(CancellationToken.None);
        await Engine.EnsureBotsAsync(CancellationToken.None);
        Assert.Equal(BotRoster.All.Count, Engine.Bots.Count);
        Assert.Equal(BotRoster.All.Select(b => b.Name).Order(), Engine.Bots.Select(b => b.Row.CharacterName).Order());

        // With nobody to measure against, a bot may not earn any experience at all.
        Assert.Equal(0, await Engine.XpCapAsync(CancellationToken.None));
        await PlayAsync(10);
        foreach (var bot in Engine.Bots)
        {
            Assert.Equal(0, await XpAsync(bot.Row.AccountId));
        }

        // A real player is ahead; bots with money for a plot go and earn up to just below them.
        using var player = await factory.ConnectAsync();
        await player.RegisterWithCharacterAsync();
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            await scope.ServiceProvider.GetRequiredService<ICharacterProgress>().AddXpAsync(player.AccountId, 3000, CancellationToken.None);
        }

        foreach (var bot in Engine.Bots)
        {
            await GiveMoneyAsync(bot.Row.AccountId, 5_000_00);
        }

        await PlayAsync(120);
        var xps = new Dictionary<string, long>();
        foreach (var bot in Engine.Bots)
        {
            xps[bot.Profile.Name] = await XpAsync(bot.Row.AccountId);
            Assert.True(xps[bot.Profile.Name] < 3000, $"{bot.Profile.Name} has {xps[bot.Profile.Name]} XP");
        }

        Assert.True(xps.Values.Count(xp => xp > 0) >= BotRoster.All.Count / 2, string.Join(", ", xps));

        // Bots bought plots like players do, and show up on the map.
        var plots = 0;
        foreach (var bot in Engine.Bots)
        {
            var info = await bot.Client.SendAsync("world.info", null, CancellationToken.None);
            plots += info.Payload.GetProperty("plots").GetArrayLength();
        }

        Assert.True(plots >= BotRoster.All.Count / 2, $"{plots} plots");

        // The level ranking still has the real player on top.
        var ranking = (await player.SendAsync("rankings.get", new { ranking = "level" })).Payload();
        Assert.True(ranking.GetProperty("top")[0].GetProperty("mine").GetBoolean());

        // When the player moves on, so may the bots, and no further.
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            await scope.ServiceProvider.GetRequiredService<ICharacterProgress>().AddXpAsync(player.AccountId, 3000, CancellationToken.None);
        }

        await PlayAsync(60);
        var grew = false;
        foreach (var bot in Engine.Bots)
        {
            var xp = await XpAsync(bot.Row.AccountId);
            Assert.True(xp < 6000, $"{bot.Profile.Name} has {xp} XP");
            grew |= xp > xps[bot.Profile.Name];
        }

        Assert.True(grew);
    }
}

/// <summary>On a database of their own, so the first test above starts with no players.</summary>
public sealed class BotLimitTests(ServerFactory factory) : IClassFixture<ServerFactory>
{
    private BotEngine Engine => factory.Services.GetRequiredService<BotEngine>();

    private async Task<long> XpAsync(Guid account)
    {
        await using var scope = factory.Services.CreateAsyncScope();
        return await scope.ServiceProvider.GetRequiredService<ICharacterXp>().XpAsync(account, CancellationToken.None) ?? 0;
    }

    [Fact]
    public async Task A_bot_that_gets_over_the_cap_is_cut_back_and_bots_keep_few_market_offers()
    {
        await Engine.EnsureBotsAsync(CancellationToken.None);
        using var player = await factory.ConnectAsync();
        await player.RegisterWithCharacterAsync();
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            await scope.ServiceProvider.GetRequiredService<ICharacterProgress>().AddXpAsync(player.AccountId, 100_000, CancellationToken.None);
        }

        var bot = Engine.Bots.First(b => b.Profile.Trade == BotTrade.Forester);
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            // Experience from somewhere the bot could not foresee.
            await scope.ServiceProvider.GetRequiredService<ICharacterProgress>().AddXpAsync(bot.Row.AccountId, 500_000, CancellationToken.None);
            await scope.ServiceProvider.GetRequiredService<IInventory>().AddAsync(bot.Row.AccountId, Items.Wood, 2000, CancellationToken.None);
            await scope.ServiceProvider.GetRequiredService<IInventory>().AddAsync(bot.Row.AccountId, Items.Stone, 2000, CancellationToken.None);
        }

        await Engine.StepAsync(bot.Profile.Name, CancellationToken.None);
        Assert.True(await XpAsync(bot.Row.AccountId) < await XpAsync(player.AccountId));

        for (var i = 0; i < 200; i++)
        {
            factory.Time.Advance(TimeSpan.FromMinutes(3));
            await Engine.StepAsync(bot.Profile.Name, CancellationToken.None);
        }

        var mine = (await bot.Client.SendAsync("market.mine", null, CancellationToken.None)).Payload;
        var open = mine.GetProperty("listings").EnumerateArray().Count(l => l.GetProperty("open").GetBoolean());
        Assert.InRange(open, 1, BotRules.MaxListings);
        foreach (var listing in mine.GetProperty("listings").EnumerateArray())
        {
            Assert.True(listing.GetProperty("quantity").GetInt64() <= BotRules.ListingSize);
        }
    }

    [Fact]
    public async Task Bots_log_in_for_a_session_and_out_again_for_hours()
    {
        await Engine.EnsureBotsAsync(CancellationToken.None);
        factory.Time.Advance(TimeSpan.FromHours(BotRoster.All.Max(b => b.RestHours)));
        await Engine.TickAsync(CancellationToken.None);
        Assert.All(Engine.Bots, b => Assert.NotNull(b.Row.SessionUntil));

        factory.Time.Advance(TimeSpan.FromMinutes(BotRoster.All.Max(b => b.SessionMinutes) * 1.5 + 1));
        await Engine.TickAsync(CancellationToken.None);
        var now = factory.Time.GetUtcNow();
        Assert.All(Engine.Bots, b =>
        {
            Assert.Null(b.Row.SessionUntil);
            Assert.True(b.Row.NextSessionAt >= now + TimeSpan.FromHours(b.Profile.RestHours) * 0.5);
        });
    }
}
