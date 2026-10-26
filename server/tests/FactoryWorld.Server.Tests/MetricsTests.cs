using FactoryWorld.Modules.Abstractions;

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
}
