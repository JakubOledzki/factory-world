using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Server.Tests;

public sealed class MetricsTests(ServerFactory factory) : IClassFixture<ServerFactory>
{
    [Fact]
    public async Task Metrics_count_answered_messages_by_kind_for_Prometheus()
    {
        using var client = await factory.ConnectAsync();
        await client.SendRawAsync("""{"type":"hello","id":"1","payload":{"protocol":1}}""");

        var text = await factory.CreateClient().GetStringAsync("/metrics");

        Assert.Contains("# TYPE factoryworld_message_duration_seconds histogram", text);
        Assert.Matches("""factoryworld_message_duration_seconds_count\{type="hello"\} [1-9]""", text);
        Assert.Contains("""factoryworld_message_duration_seconds_bucket{type="hello",le="+Inf"}""", text);
        Assert.Contains("factoryworld_players_online ", text);
        Assert.Contains("process_cpu_seconds_total ", text);
    }

    [Fact]
    public void Message_time_buckets_are_cumulative()
    {
        var load = new ServerLoad();
        load.Record("slow", ServerLoad.Start() - System.Diagnostics.Stopwatch.Frequency * 3);

        var total = Assert.Single(load.Totals());
        Assert.Equal(1, total.Count);
        Assert.InRange(total.Seconds, 3, 60);
        for (var i = 0; i < ServerLoad.Buckets.Length; i++)
        {
            Assert.Equal(ServerLoad.Buckets[i] >= 3 ? 1 : 0, total.InBucket[i]);
        }
    }

    [Fact]
    public async Task Metrics_count_items_made_and_money_paid_once_committed()
    {
        using var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();
        var counters = factory.Services.GetRequiredService<GameCounters>();
        long Made() => counters.Items().Where(t => t.Item == Items.Planks && !t.Bot).Sum(t => t.Produced);
        long Sold() => counters.MoneyTotals().Where(t => t.Reason == "sell" && !t.Bot).Sum(t => t.InCents);
        var (made, sold) = (Made(), Sold());

        await using (var scope = factory.Services.CreateAsyncScope())
        {
            var services = scope.ServiceProvider;
            await services.GetRequiredService<GameDb>().InTransactionAsync(async () =>
            {
                await services.GetRequiredService<IProductionStats>().RecordAsync(client.AccountId,
                    [ProductionEntry.Made(Items.Planks, 3, DateTimeOffset.UtcNow)], CancellationToken.None);
                await services.GetRequiredService<IWallet>().CreditAsync(client.AccountId, 250, "sell 3 planks", CancellationToken.None);
                Assert.Equal(made, Made());
            }, CancellationToken.None);
        }

        await using (var scope = factory.Services.CreateAsyncScope())
        {
            var services = scope.ServiceProvider;
            await Assert.ThrowsAsync<InvalidOperationException>(() => services.GetRequiredService<GameDb>().InTransactionAsync(async () =>
            {
                await services.GetRequiredService<IWallet>().CreditAsync(client.AccountId, 1000, "sell 1 planks", CancellationToken.None);
                throw new InvalidOperationException("rolled back");
            }, CancellationToken.None));
        }

        Assert.Equal(made + 3, Made());
        Assert.Equal(sold + 250, Sold());
        var text = await factory.CreateClient().GetStringAsync("/metrics");
        Assert.Matches($$"""factoryworld_items_produced_total\{item="{{Items.Planks}}",who="player"\} [1-9]""", text);
        Assert.Matches("""factoryworld_money_in_cents_total\{reason="sell",who="player"\} [1-9]""", text);
    }

    [Theory]
    [InlineData("sell 5 iron_ore", "sell")]
    [InlineData("tax of Wola: market sold 1 plank", "tax")]
    [InlineData("company Acme research steel", "company")]
    [InlineData("company research steel", "company_research")]
    [InlineData("bank deposit Lokata", "bank_deposit")]
    [InlineData("survey 3:4", "survey")]
    [InlineData("", "other")]
    public void Ledger_reasons_are_grouped_by_their_first_word(string reason, string kind) =>
        Assert.Equal(kind, GameCounters.ReasonKind(reason));
}
