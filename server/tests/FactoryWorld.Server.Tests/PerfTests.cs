using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using FactoryWorld.Modules.Abstractions.Contracts;
using FactoryWorld.Modules.World;
using Microsoft.Extensions.DependencyInjection;
using Xunit.Abstractions;

namespace FactoryWorld.Server.Tests;

/// <summary>A test that runs only with FW_PERF=1: it measures, it does not check the rules.</summary>
public sealed class PerfFactAttribute : FactAttribute
{
    public PerfFactAttribute()
    {
        if (Environment.GetEnvironmentVariable("FW_PERF") != "1")
        {
            Skip = "Performance measurement; run with FW_PERF=1.";
        }
    }
}

/// <summary>
/// How much the server does for the requests a player in the game sends most often: the time, the
/// database commands and the memory allocated per request. Run before and after a change:
/// <c>FW_PERF=1 dotnet test -c Release --filter PerfTests --logger "console;verbosity=detailed"</c>;
/// with FW_PERF_OUT set the table is also written to that file, with FW_PERF_SQL=1 the commands of each request too.
/// KB allocated counts the test client as well (about 70 KB a request, see "ping").
/// </summary>
public sealed class PerfTests(ServerFactory factory, ITestOutputHelper output) : IClassFixture<ServerFactory>
{
    private static readonly WorldMap Map = WorldMap.Load();

    private const int East = 1;

    /// <summary>Furnace lines on the factory plot: chest → inserter → furnace → inserter → chest, each with a pole and a generator.</summary>
    private const int Lines = 8;

    private const int Rounds = 40;

    private sealed class Commands : IDisposable
    {
        private readonly ActivityListener _listener;
        private long _count;

        public Commands()
        {
            _listener = new ActivityListener
            {
                ShouldListenTo = s => s.Name == "Npgsql",
                Sample = (ref ActivityCreationOptions<ActivityContext> _) => ActivitySamplingResult.AllData,
                ActivityStarted = _ => Interlocked.Increment(ref _count),
                ActivityStopped = a =>
                {
                    if (Recording)
                    {
                        lock (Recorded)
                        {
                            Recorded.Add(a.GetTagItem("db.query.text")?.ToString() ?? a.DisplayName);
                        }
                    }
                },
            };
            ActivitySource.AddActivityListener(_listener);
        }

        public long Count => Interlocked.Read(ref _count);

        /// <summary>While set, the SQL of each command (a batch counts once) is kept in <see cref="Recorded"/>.</summary>
        public bool Recording { get; set; }

        public List<string> Recorded { get; } = [];

        public void Dispose() => _listener.Dispose();
    }

    private readonly record struct Result(string Name, double Ms, double Queries, double KbAllocated, double KbReply);

    /// <summary>With FW_PERF_SQL=1, the commands of each request are listed after the table.</summary>
    private static readonly bool ListCommands = Environment.GetEnvironmentVariable("FW_PERF_SQL") == "1";

    private readonly StringBuilder _commandLists = new();

    private async Task<Result> MeasureAsync(string name, Commands commands, Func<int, Task<string>> request, Action? between = null)
    {
        // Warm up: the first calls compile and prepare.
        for (var i = 0; i < 5; i++)
        {
            between?.Invoke();
            await request(i);
        }

        long queries = 0, allocated = 0, bytes = 0;
        var clock = new Stopwatch();
        for (var i = 0; i < Rounds; i++)
        {
            between?.Invoke();
            commands.Recording = ListCommands && i == Rounds - 1;
            var q = commands.Count;
            var a = GC.GetTotalAllocatedBytes(precise: false);
            clock.Start();
            var reply = await request(i);
            clock.Stop();
            allocated += GC.GetTotalAllocatedBytes(precise: false) - a;
            queries += commands.Count - q;
            bytes += Encoding.UTF8.GetByteCount(reply);
            commands.Recording = false;
        }

        if (commands.Recorded.Count > 0)
        {
            _commandLists.AppendLine($"{name}:");
            foreach (var g in commands.Recorded.GroupBy(t => t.ReplaceLineEndings(" ")).OrderByDescending(g => g.Count()))
            {
                _commandLists.AppendLine($"  {g.Count()}× {(g.Key.Length > 140 ? g.Key[..140] + "…" : g.Key)}");
            }

            commands.Recorded.Clear();
        }

        return new Result(name, clock.Elapsed.TotalMilliseconds / Rounds, (double)queries / Rounds, allocated / 1024.0 / Rounds, bytes / 1024.0 / Rounds);
    }

    [PerfFact]
    public async Task Requests_a_player_sends_most_often()
    {
        using var commands = new Commands();
        using var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();
        var (x, y) = await FactoryPlotAsync(client);

        async Task<string> Send(string type, object? payload = null) => (await client.SendAsync(type, payload)).GetRawText();

        // Others on the plot, as when a company works it together; presence only keeps them in memory.
        var presence = factory.Services.GetRequiredService<PlotPresence>();
        for (var i = 0; i < 2000; i++)
        {
            presence.Update(Guid.NewGuid(), i % 50 == 0 ? x : x + 1 + i % 7, y, 10, 10, "down", false);
        }

        // FW_PERF_PROFILE=logistics.get (or another request type): that request over and over for a minute first,
        // for a profiler to attach to (dotnet-trace ps).
        if (Environment.GetEnvironmentVariable("FW_PERF_PROFILE") is { Length: > 0 } profiled)
        {
            var until = Stopwatch.StartNew();
            while (until.Elapsed < TimeSpan.FromSeconds(60))
            {
                factory.Time.Advance(TimeSpan.FromSeconds(1));
                await Send(profiled, new { x, y });
            }
        }

        var results = new List<Result>
        {
            await MeasureAsync("plot.presence", commands, _ => Send("plot.presence", new { x, y, posX = 12.5, posY = 30.25, facing = "left", walking = true })),
            await MeasureAsync("logistics.get (1 s later)", commands, _ => Send("logistics.get", new { x, y }), () => factory.Time.Advance(TimeSpan.FromSeconds(1))),
            await MeasureAsync("plot.enter", commands, _ => Send("plot.enter", new { x, y })),
            await MeasureAsync("inventory.get", commands, _ => Send("inventory.get")),
            await MeasureAsync("garage.get", commands, _ => Send("garage.get")),
            await MeasureAsync("wallet.get", commands, _ => Send("wallet.get")),
            await MeasureAsync("market.prices", commands, _ => Send("market.prices")),
            await MeasureAsync("world.area", commands, i => Send("world.area", new { x = 1000 + i * 37 % 4000, y = 800 + i * 53 % 1500, width = 100, height = 60 })),
            await MeasureAsync("world.plot", commands, i => Send("world.plot", new { x = 1000 + i * 37 % 4000, y = 800 + i * 53 % 1500 })),
            await MeasureAsync("crafting.get", commands, _ => Send("crafting.get")),
            await MeasureAsync("research.get", commands, _ => Send("research.get")),
            await MeasureAsync("ping", commands, _ => Send("ping")),
        };

        var table = new StringBuilder();
        table.AppendLine($"| Request | ms | DB commands | KB allocated | KB reply |");
        table.AppendLine("| --- | ---: | ---: | ---: | ---: |");
        foreach (var r in results)
        {
            table.AppendLine($"| {r.Name} | {r.Ms:0.00} | {r.Queries:0.0} | {r.KbAllocated:0} | {r.KbReply:0.0} |");
        }

        table.Append(_commandLists);
        output.WriteLine(table.ToString());
        if (Environment.GetEnvironmentVariable("FW_PERF_OUT") is { Length: > 0 } file)
        {
            await File.WriteAllTextAsync(file, table.ToString());
        }
    }

    /// <summary>A grassland plot of the player's with <see cref="Lines"/> powered furnace lines working on it.</summary>
    private async Task<(int X, int Y)> FactoryPlotAsync(GameClient client)
    {
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            await scope.ServiceProvider.GetRequiredService<IWallet>().CreditAsync(client.AccountId, 100_000_000, "test", CancellationToken.None);
            var inventory = scope.ServiceProvider.GetRequiredService<IInventory>();
            foreach (var (item, quantity) in new[]
                     {
                         (Items.WoodenChest, 2 * Lines), (Items.Inserter, 2 * Lines), (Items.Furnace, Lines), (Items.Pole, Lines),
                         (Items.Generator, Lines), (Items.Coal, 60 * Lines), (Items.IronOre, 200 * Lines),
                     })
            {
                await inventory.AddAsync(client.AccountId, item, quantity, CancellationToken.None);
            }
        }

        var (x, y) = FreePlot(Biome.Grassland);
        Assert.Equal("world.bought", (await client.SendAsync("world.buy", new { x, y })).Type());
        var plot = await client.SendAsync("plot.enter", new { x, y });
        using var gzip = new GZipStream(new MemoryStream(Convert.FromBase64String(plot.Payload().GetProperty("tiles").GetString()!)), CompressionMode.Decompress);
        using var tiles = new MemoryStream();
        gzip.CopyTo(tiles);
        var bytes = tiles.ToArray();
        bool Free(int tx, int ty) => Enumerable.Range(tx, 5).All(i => bytes[ty * PlotLayout.Size + i] == (byte)TileObject.None);

        var placed = 0;
        for (var ty = 20; ty + 1 < PlotLayout.Size && placed < Lines; ty++)
        {
            for (var tx = 2; tx + 6 <= PlotLayout.Size && placed < Lines; tx += 6)
            {
                if (!Free(tx, ty) || !Free(tx, ty + 1) || !Free(tx, ty - 1) || !Free(tx, ty + 2))
                {
                    continue;
                }

                var source = await PlaceAsync(client, x, y, Items.WoodenChest, tx, ty);
                await PlaceAsync(client, x, y, Items.Inserter, tx + 1, ty);
                await PlaceAsync(client, x, y, Items.Furnace, tx + 2, ty);
                await PlaceAsync(client, x, y, Items.Inserter, tx + 3, ty);
                await PlaceAsync(client, x, y, Items.WoodenChest, tx + 4, ty);
                await client.SendAsync("storage.put", new { x, y, id = source, item = Items.IronOre, quantity = 200 });
                await client.SendAsync("storage.put", new { x, y, id = source, item = Items.Coal, quantity = 40 });
                await PlaceAsync(client, x, y, Items.Pole, tx + 2, ty + 1);
                var generator = await PlaceAsync(client, x, y, Items.Generator, tx + 3, ty + 1);
                await client.SendAsync("generator.load", new { x, y, id = generator, item = Items.Coal, quantity = 20 });
                placed++;
                ty += 3;
                break;
            }
        }

        Assert.Equal(Lines, placed);
        return (x, y);
    }

    private static (int X, int Y) FreePlot(Biome biome)
    {
        var found = 0;
        for (var y = 0; y < Map.Height; y += 5)
        {
            for (var x = 0; x < Map.Width; x += 5)
            {
                if (Map.BiomeAt(x, y) == biome && found++ >= 4000)
                {
                    return (x, y);
                }
            }
        }

        throw new InvalidOperationException("No such plot.");
    }

    private static async Task<string> PlaceAsync(GameClient client, int x, int y, string kind, int tileX, int tileY, int rotation = East)
    {
        var reply = await client.SendAsync("plot.place", new { x, y, kind, tileX, tileY, rotation });
        Assert.True(reply.Type() == "plot.placed", reply.GetRawText());
        return reply.Payload().GetProperty("object").GetProperty("id").GetString()!;
    }
}
