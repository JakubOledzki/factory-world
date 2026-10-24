using System.Diagnostics;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using FactoryWorld.LoadTest;

// Load test of the game server: many bot players over the real WebSocket protocol.
// Usage and options: tools/loadtest/README.md
var options = Options.Parse(args);
Console.WriteLine($"Factory World load test: {options.Players} players, {options.Url}");

ThreadPool.SetMinThreads(Math.Max(64, Environment.ProcessorCount * 8), 64);

var accounts = await Accounts.PrepareAsync(options);
if (options.PrepareOnly)
{
    return;
}

var recorder = new Recorder();
var sampler = new ResourceSampler(options.ServerPid);
var bots = accounts.Take(options.Players).Select((a, i) => new Bot(i, a, options, recorder)).ToList();

using var stop = new CancellationTokenSource();
var clock = Stopwatch.StartNew();
var timeline = new List<JsonObject>();
var timelineTask = Task.Run(async () =>
{
    using var timer = new PeriodicTimer(TimeSpan.FromSeconds(1));
    while (await timer.WaitForNextTickAsync())
    {
        var second = recorder.TakeSecond();
        var res = sampler.Sample();
        var row = new JsonObject
        {
            ["t"] = Math.Round(clock.Elapsed.TotalSeconds, 1),
            ["phase"] = recorder.Phase,
            ["connected"] = Bot.Connected,
            ["rps"] = second.Count,
            ["errors"] = second.Errors,
            ["p50"] = Stats.Percentile(second.Latencies, 50),
            ["p95"] = Stats.Percentile(second.Latencies, 95),
            ["p99"] = Stats.Percentile(second.Latencies, 99),
            ["pingP95"] = Stats.Percentile(second.Pings, 95),
        };
        foreach (var (k, v) in res)
        {
            row[k] = v;
        }

        lock (timeline)
        {
            timeline.Add(row);
        }

        Console.WriteLine($"[{clock.Elapsed.TotalSeconds,5:0}s] {recorder.Phase,-7} connected {Bot.Connected,6}  {second.Count,6} req/s  " +
            $"p95 {row["p95"],8} ms  errors {second.Errors,4}  server CPU {res.GetValueOrDefault("serverCpu")}%  " +
            $"db CPU {res.GetValueOrDefault("dbCpu")}%");
        if (stop.IsCancellationRequested)
        {
            break;
        }
    }
});

// Ramp-up: players join evenly over --ramp seconds, then everyone plays for --duration seconds.
recorder.Phase = "ramp";
var rampDelay = options.Players > 1 ? TimeSpan.FromSeconds(options.RampSeconds) / options.Players : TimeSpan.Zero;
var steadyStart = TimeSpan.FromSeconds(options.RampSeconds);
var end = steadyStart + TimeSpan.FromSeconds(options.DurationSeconds);
var botTasks = new List<Task>(bots.Count);
foreach (var bot in bots)
{
    botTasks.Add(Task.Run(() => bot.RunAsync(clock, end, stop.Token)));
    var due = rampDelay * botTasks.Count;
    var wait = due - clock.Elapsed;
    if (wait > TimeSpan.Zero)
    {
        await Task.Delay(wait);
    }
}

var rampFinished = clock.Elapsed;
if (clock.Elapsed < steadyStart)
{
    await Task.Delay(steadyStart - clock.Elapsed);
}

recorder.Phase = "steady";
recorder.SteadyFrom = clock.Elapsed;
await Task.WhenAll(botTasks);
recorder.SteadyTo = clock.Elapsed;
stop.Cancel();
await timelineTask;

var result = recorder.Summarize(options, timeline, rampFinished, Bot.Peak);
Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(options.Output))!);
await File.WriteAllTextAsync(options.Output, result.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
Console.WriteLine($"Saved {options.Output}");
Console.WriteLine(result["summary"]!.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));

namespace FactoryWorld.LoadTest
{
    public sealed record Options(
        string Url,
        int Players,
        double RampSeconds,
        double DurationSeconds,
        double ThinkMs,
        double TimeoutSeconds,
        string AccountsFile,
        int RegisterConcurrency,
        bool PasswordLogin,
        bool PrepareOnly,
        int? ServerPid,
        string Output,
        string Password)
    {
        public static Options Parse(string[] args)
        {
            var map = new Dictionary<string, string>();
            for (var i = 0; i < args.Length; i++)
            {
                if (!args[i].StartsWith("--"))
                {
                    continue;
                }

                var key = args[i][2..];
                map[key] = i + 1 < args.Length && !args[i + 1].StartsWith("--") ? args[++i] : "true";
            }

            string Get(string key, string fallback) => map.GetValueOrDefault(key, fallback);
            var players = int.Parse(Get("players", "10"));
            return new Options(
                Url: Get("url", "ws://127.0.0.1:5080/ws"),
                Players: players,
                RampSeconds: double.Parse(Get("ramp", "10")),
                DurationSeconds: double.Parse(Get("duration", "60")),
                ThinkMs: double.Parse(Get("think", "2000")),
                TimeoutSeconds: double.Parse(Get("timeout", "15")),
                AccountsFile: Get("accounts", "loadtest-accounts.tsv"),
                RegisterConcurrency: int.Parse(Get("register-concurrency", "8")),
                PasswordLogin: Get("login", "token") == "password",
                PrepareOnly: map.ContainsKey("prepare-only"),
                ServerPid: map.TryGetValue("server-pid", out var pid) ? int.Parse(pid) : null,
                Output: Get("out", $"results/{players}.json"),
                Password: Get("password", "LoadTest-12345"));
        }
    }

    /// <summary>One WebSocket in the request/reply style of the game: the server answers every message, in order.</summary>
    public sealed class GameSocket : IAsyncDisposable
    {
        private readonly ClientWebSocket _socket = new();
        private readonly byte[] _buffer = new byte[64 * 1024];
        private int _nextId;

        public static async Task<GameSocket> ConnectAsync(string url, CancellationToken cancellationToken)
        {
            var s = new GameSocket();
            s._socket.Options.KeepAliveInterval = TimeSpan.Zero;
            await s._socket.ConnectAsync(new Uri(url), cancellationToken);
            return s;
        }

        public async Task<JsonElement> SendAsync(string type, object? payload, TimeSpan timeout)
        {
            using var cts = new CancellationTokenSource(timeout);
            var id = (++_nextId).ToString();
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new { type, id, payload = payload ?? new { } });
            await _socket.SendAsync(bytes, WebSocketMessageType.Text, true, cts.Token);

            var length = 0;
            while (true)
            {
                var r = await _socket.ReceiveAsync(_buffer.AsMemory(length), cts.Token);
                if (r.MessageType == WebSocketMessageType.Close)
                {
                    throw new WebSocketException("Server closed the connection.");
                }

                length += r.Count;
                if (r.EndOfMessage)
                {
                    break;
                }
            }

            using var doc = JsonDocument.Parse(_buffer.AsMemory(0, length));
            return doc.RootElement.Clone();
        }

        public async ValueTask DisposeAsync()
        {
            try
            {
                if (_socket.State == WebSocketState.Open)
                {
                    using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));
                    await _socket.CloseAsync(WebSocketCloseStatus.NormalClosure, null, cts.Token);
                }
            }
            catch
            {
                // Closing is best effort.
            }

            _socket.Dispose();
        }
    }

    public sealed record Account(int Index, string Email, string Token);

    /// <summary>Creates the bot accounts once (register + character) and keeps their tokens in a file for later runs.</summary>
    public static class Accounts
    {
        public static async Task<List<Account>> PrepareAsync(Options options)
        {
            var known = File.Exists(options.AccountsFile)
                ? File.ReadAllLines(options.AccountsFile)
                    .Select(l => l.Split('\t'))
                    .Where(p => p.Length == 2)
                    .Select(p => new Account(int.Parse(p[0].Split('@')[0][7..]), p[0], p[1]))
                    .ToDictionary(a => a.Index)
                : new Dictionary<int, Account>();

            var missing = Enumerable.Range(0, options.Players).Where(i => !known.ContainsKey(i)).ToList();
            if (missing.Count > 0)
            {
                Console.WriteLine($"Registering {missing.Count} bot accounts ({options.RegisterConcurrency} at a time)...");
                var created = 0;
                var clock = Stopwatch.StartNew();
                var gate = new SemaphoreSlim(options.RegisterConcurrency);
                var tasks = missing.Select(async i =>
                {
                    await gate.WaitAsync();
                    try
                    {
                        var account = await RegisterAsync(i, options);
                        lock (known)
                        {
                            known[i] = account;
                            File.AppendAllText(options.AccountsFile, $"{account.Email}\t{account.Token}\n");
                        }

                        var n = Interlocked.Increment(ref created);
                        if (n % 500 == 0)
                        {
                            Console.WriteLine($"  {n}/{missing.Count} ({n / clock.Elapsed.TotalSeconds:0.0} accounts/s)");
                        }
                    }
                    finally
                    {
                        gate.Release();
                    }
                });
                await Task.WhenAll(tasks);
                Console.WriteLine($"Registered {created} accounts in {clock.Elapsed.TotalSeconds:0.0}s");
            }

            return Enumerable.Range(0, options.Players).Select(i => known[i]).ToList();
        }

        private static async Task<Account> RegisterAsync(int i, Options options)
        {
            var timeout = TimeSpan.FromSeconds(60);
            await using var socket = await GameSocket.ConnectAsync(options.Url, CancellationToken.None);
            await socket.SendAsync("hello", new { protocol = 1 }, timeout);
            var email = $"loadbot{i}@loadtest.local";
            var reply = await socket.SendAsync("auth.register", new { email, password = options.Password }, timeout);
            if (reply.GetProperty("type").GetString() != "auth.ok")
            {
                // Already registered by an earlier run whose token file was lost.
                reply = await socket.SendAsync("auth.login", new { email, password = options.Password }, timeout);
            }

            if (reply.GetProperty("type").GetString() != "auth.ok")
            {
                throw new InvalidOperationException($"Cannot log in {email}: {reply}");
            }

            var token = reply.GetProperty("payload").GetProperty("token").GetString()!;
            var appearance = new { skinTone = i % 6, hairStyle = i % 6, hairColor = i % 8, shirtStyle = i % 3, shirtColor = i % 12, pantsColor = (i + 3) % 12, shoesColor = (i + 7) % 12 };
            await socket.SendAsync("character.create", new { name = $"lb{i}", appearance }, timeout);
            return new Account(i, email, token);
        }
    }

    /// <summary>
    /// One simulated player. It joins like the real client (hello, log in, load character, garage, inventory,
    /// wallet, prices) and then plays: every think time it does one action, chosen with the weights of
    /// <see cref="Mix"/>. It waits for each reply before the next action, like the client does.
    /// </summary>
    public sealed class Bot(int index, Account account, Options options, Recorder recorder)
    {
        public static int Connected;
        public static int Peak;

        /// <summary>What players do and how often (weights). Movement is drawn by the client only and never reaches the server.</summary>
        private static readonly (string Type, int Weight)[] Mix =
        [
            ("ping", 15),
            ("inventory.get", 12),
            ("wallet.get", 8),
            ("garage.get", 10),
            ("market.prices", 4),
            ("market.overview", 5),
            ("market.item", 8),
            ("market.mine", 3),
            ("world.area", 8),
            ("world.plot", 6),
            ("crafting.get", 5),
            ("inventory.move", 6),
            ("recycling.sort", 6),
            ("market.sell", 4),
        ];

        private static readonly int TotalWeight = Mix.Sum(m => m.Weight);
        private static readonly string[] MarketItems = ["wood", "stone", "iron_ingot", "copper_ingot", "sapling", "coal", "wheat", "nails"];

        private readonly Random _random = new(index * 7919 + 17);
        private readonly HashSet<string> _sellable = [];
        private List<(string Id, int Quantity, int Slot)> _items = [];
        private int _slots = 100;

        public async Task RunAsync(Stopwatch clock, TimeSpan end, CancellationToken cancellationToken)
        {
            var timeout = TimeSpan.FromSeconds(options.TimeoutSeconds);
            while (clock.Elapsed < end && !cancellationToken.IsCancellationRequested)
            {
                GameSocket? socket = null;
                var connected = false;
                try
                {
                    var joinStart = Stopwatch.GetTimestamp();
                    socket = await Timed("connect", () => ConnectAsync(timeout));
                    await Call(socket, "hello", new { protocol = 1 }, timeout);
                    var auth = options.PasswordLogin
                        ? await Call(socket, "auth.login", new { email = account.Email, password = options.Password }, timeout)
                        : await Call(socket, "auth.resume", new { token = account.Token }, timeout);
                    if (auth.GetProperty("type").GetString() != "auth.ok")
                    {
                        throw new InvalidOperationException("Login refused.");
                    }

                    await Call(socket, "character.get", null, timeout);
                    await Call(socket, "garage.get", null, timeout);
                    Remember(await Call(socket, "inventory.get", null, timeout));
                    await Call(socket, "wallet.get", null, timeout);
                    var prices = await Call(socket, "market.prices", null, timeout);
                    foreach (var item in prices.GetProperty("payload").GetProperty("items").EnumerateArray())
                    {
                        if (item.GetProperty("sellCents").ValueKind == JsonValueKind.Number)
                        {
                            _sellable.Add(item.GetProperty("id").GetString()!);
                        }
                    }

                    recorder.Record("join", Stopwatch.GetElapsedTime(joinStart).TotalMilliseconds, ok: true);
                    connected = true;
                    var now = Interlocked.Increment(ref Connected);
                    InterlockedMax(ref Peak, now);

                    while (clock.Elapsed < end)
                    {
                        var think = options.ThinkMs * (0.5 + _random.NextDouble());
                        await Task.Delay(TimeSpan.FromMilliseconds(think), cancellationToken);
                        if (clock.Elapsed >= end)
                        {
                            break;
                        }

                        await PlayAsync(socket, timeout);
                    }
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    break;
                }
                catch (Exception)
                {
                    // The failure is already recorded; a real player would reconnect after a moment.
                    Interlocked.Increment(ref recorder.Reconnects);
                    await Task.Delay(TimeSpan.FromSeconds(1 + _random.NextDouble() * 2));
                }
                finally
                {
                    if (connected)
                    {
                        Interlocked.Decrement(ref Connected);
                    }

                    if (socket is not null)
                    {
                        await socket.DisposeAsync();
                    }
                }
            }
        }

        private async Task PlayAsync(GameSocket socket, TimeSpan timeout)
        {
            var roll = _random.Next(TotalWeight);
            var type = Mix[0].Type;
            foreach (var (t, w) in Mix)
            {
                if (roll < w)
                {
                    type = t;
                    break;
                }

                roll -= w;
            }

            object? payload = null;
            switch (type)
            {
                case "market.item":
                    payload = new { item = MarketItems[_random.Next(MarketItems.Length)] };
                    break;
                case "world.area":
                    payload = new { x = _random.Next(6800), y = _random.Next(2800), width = 40 + _random.Next(80), height = 30 + _random.Next(50) };
                    break;
                case "world.plot":
                    payload = new { x = _random.Next(6900), y = _random.Next(2900) };
                    break;
                case "recycling.sort":
                    payload = new { count = 1 };
                    break;
                case "inventory.move":
                    if (_items.Count == 0)
                    {
                        type = "inventory.get";
                        break;
                    }

                    payload = new { item = _items[_random.Next(_items.Count)].Id, slot = _random.Next(Math.Min(_slots, 30)) };
                    break;
                case "market.sell":
                    var sellable = _items.Where(i => _sellable.Contains(i.Id)).ToList();
                    if (sellable.Count == 0)
                    {
                        type = "garage.get";
                        break;
                    }

                    payload = new { item = sellable[_random.Next(sellable.Count)].Id, quantity = 1 };
                    break;
            }

            var reply = await Call(socket, type, payload, timeout);
            var replyType = reply.GetProperty("type").GetString();
            if (replyType == "inventory")
            {
                Remember(reply);
            }
            else if (replyType is "garage" or "market.traded")
            {
                // Sorting and selling change the inventory; look at it again now and then, like the client.
                if (_random.Next(3) == 0)
                {
                    Remember(await Call(socket, "inventory.get", null, timeout));
                }
            }
        }

        private void Remember(JsonElement reply)
        {
            if (reply.GetProperty("type").GetString() != "inventory")
            {
                return;
            }

            var p = reply.GetProperty("payload");
            _slots = p.GetProperty("slots").GetInt32();
            _items = p.GetProperty("items").EnumerateArray()
                .Select(i => (i.GetProperty("id").GetString()!, i.GetProperty("quantity").GetInt32(), i.GetProperty("slot").GetInt32()))
                .ToList();
        }

        private async Task<GameSocket> ConnectAsync(TimeSpan timeout)
        {
            using var cts = new CancellationTokenSource(timeout);
            return await GameSocket.ConnectAsync(options.Url, cts.Token);
        }

        private async Task<T> Timed<T>(string type, Func<Task<T>> work)
        {
            var start = Stopwatch.GetTimestamp();
            try
            {
                var result = await work();
                recorder.Record(type, Stopwatch.GetElapsedTime(start).TotalMilliseconds, ok: true);
                return result;
            }
            catch (Exception ex)
            {
                recorder.Record(type, Stopwatch.GetElapsedTime(start).TotalMilliseconds, ok: false, code: Describe(ex));
                throw;
            }
        }

        private async Task<JsonElement> Call(GameSocket socket, string type, object? payload, TimeSpan timeout)
        {
            var start = Stopwatch.GetTimestamp();
            JsonElement reply;
            try
            {
                reply = await socket.SendAsync(type, payload, timeout);
            }
            catch (Exception ex)
            {
                recorder.Record(type, Stopwatch.GetElapsedTime(start).TotalMilliseconds, ok: false, code: Describe(ex));
                throw;
            }

            var ms = Stopwatch.GetElapsedTime(start).TotalMilliseconds;
            if (reply.GetProperty("type").GetString() == "error")
            {
                // Game rules saying no (queue full, nothing to sell) are normal answers; server faults are not.
                var code = reply.GetProperty("payload").GetProperty("code").GetString() ?? "error";
                recorder.Record(type, ms, ok: code != "internal", code: code);
            }
            else
            {
                recorder.Record(type, ms, ok: true);
            }

            return reply;
        }

        private static string Describe(Exception ex) => ex switch
        {
            OperationCanceledException => "timeout",
            WebSocketException => "socket",
            _ => ex.GetType().Name,
        };

        private static void InterlockedMax(ref int target, int value)
        {
            int seen;
            while (value > (seen = Volatile.Read(ref target)) && Interlocked.CompareExchange(ref target, value, seen) != seen)
            {
            }
        }
    }

    public sealed class Second
    {
        public List<double> Latencies { get; } = [];
        public List<double> Pings { get; } = [];
        public int Count;
        public int Errors;
    }

    /// <summary>Collects every response time: per message type for the whole run, and per second for the timeline.</summary>
    public sealed class Recorder
    {
        private readonly Dictionary<string, (List<double> Ramp, List<double> Steady, int Errors)> _ops = [];
        private readonly Dictionary<string, int> _codes = [];
        private readonly object _lock = new();
        private Second _second = new();

        public volatile string Phase = "prepare";
        public TimeSpan SteadyFrom;
        public TimeSpan SteadyTo;
        public int Reconnects;

        public void Record(string type, double ms, bool ok, string? code = null)
        {
            lock (_lock)
            {
                if (!_ops.TryGetValue(type, out var op))
                {
                    op = ([], [], 0);
                }

                if (Phase == "steady")
                {
                    op.Steady.Add(ms);
                }
                else
                {
                    op.Ramp.Add(ms);
                }

                if (!ok)
                {
                    op.Errors++;
                }

                _ops[type] = op;
                if (code is not null)
                {
                    _codes[$"{type}: {code}"] = _codes.GetValueOrDefault($"{type}: {code}") + 1;
                }

                if (type == "join")
                {
                    return;
                }

                _second.Count++;
                _second.Latencies.Add(ms);
                if (type == "ping")
                {
                    _second.Pings.Add(ms);
                }

                if (!ok)
                {
                    _second.Errors++;
                }
            }
        }

        public Second TakeSecond()
        {
            lock (_lock)
            {
                var s = _second;
                _second = new Second();
                return s;
            }
        }

        public JsonObject Summarize(Options options, List<JsonObject> timeline, TimeSpan rampFinished, int peak)
        {
            lock (_lock)
            {
                var ops = new JsonObject();
                var steadyAll = new List<double>();
                var requests = 0;
                var errors = 0;
                foreach (var (type, op) in _ops.OrderBy(o => o.Key))
                {
                    var all = op.Ramp.Concat(op.Steady).ToList();
                    var stats = Stats.Describe(op.Steady.Count > 0 ? op.Steady : all);
                    stats["count"] = all.Count;
                    stats["errors"] = op.Errors;
                    ops[type] = stats;
                    if (type is "join" or "connect")
                    {
                        continue;
                    }

                    steadyAll.AddRange(op.Steady);
                    requests += all.Count;
                    errors += op.Errors;
                }

                var steadySeconds = (SteadyTo - SteadyFrom).TotalSeconds;
                var steadyRows = timeline.Where(r => (string?)r["phase"] == "steady").ToList();
                double? Avg(string key) => steadyRows.Count == 0 || steadyRows.Any(r => r[key] is null) ? null
                    : Math.Round(steadyRows.Average(r => (double)r[key]!), 1);
                double? Max(string key) => steadyRows.Count == 0 || steadyRows.Any(r => r[key] is null) ? null
                    : Math.Round(steadyRows.Max(r => (double)r[key]!), 1);

                var summary = Stats.Describe(steadyAll);
                summary["players"] = options.Players;
                summary["peakConnected"] = peak;
                summary["throughput"] = steadySeconds > 0 ? Math.Round(steadyAll.Count / steadySeconds, 1) : 0;
                summary["offeredLoad"] = Math.Round(options.Players / (options.ThinkMs / 1000.0), 1);
                summary["requests"] = requests;
                summary["errors"] = errors;
                summary["errorRate"] = requests > 0 ? Math.Round(100.0 * errors / requests, 3) : 0;
                summary["reconnects"] = Reconnects;
                summary["rampSeconds"] = Math.Round(rampFinished.TotalSeconds, 1);
                summary["joinP50"] = ops["join"]?["p50"]?.DeepClone();
                summary["joinP95"] = ops["join"]?["p95"]?.DeepClone();
                summary["pingP50"] = ops["ping"]?["p50"]?.DeepClone();
                summary["pingP95"] = ops["ping"]?["p95"]?.DeepClone();
                summary["pingP99"] = ops["ping"]?["p99"]?.DeepClone();
                summary["serverCpuAvg"] = Avg("serverCpu");
                summary["serverCpuMax"] = Max("serverCpu");
                summary["serverRssMax"] = Max("serverRssMb");
                summary["serverThreadsMax"] = Max("serverThreads");
                summary["dbCpuAvg"] = Avg("dbCpu");
                summary["dbConnectionsMax"] = Max("dbProcesses");
                summary["loadgenCpuAvg"] = Avg("loadgenCpu");
                summary["machineCpuAvg"] = Avg("machineCpu");

                return new JsonObject
                {
                    ["config"] = JsonSerializer.SerializeToNode(options),
                    ["machine"] = new JsonObject { ["cores"] = Environment.ProcessorCount, ["os"] = Environment.OSVersion.ToString() },
                    ["summary"] = summary,
                    ["operations"] = ops,
                    ["errorCodes"] = JsonSerializer.SerializeToNode(_codes.OrderByDescending(c => c.Value).ToDictionary()),
                    ["timeline"] = new JsonArray(timeline.Select(r => (JsonNode)r.DeepClone()).ToArray()),
                };
            }
        }
    }

    public static class Stats
    {
        public static double? Percentile(List<double> values, double p)
        {
            if (values.Count == 0)
            {
                return null;
            }

            values.Sort();
            var rank = (int)Math.Ceiling(p / 100.0 * values.Count) - 1;
            return Math.Round(values[Math.Clamp(rank, 0, values.Count - 1)], 2);
        }

        public static JsonObject Describe(List<double> values) => new()
        {
            ["samples"] = values.Count,
            ["mean"] = values.Count == 0 ? null : Math.Round(values.Average(), 2),
            ["p50"] = Percentile(values, 50),
            ["p95"] = Percentile(values, 95),
            ["p99"] = Percentile(values, 99),
            ["max"] = values.Count == 0 ? null : Math.Round(values.Max(), 2),
        };
    }

    /// <summary>CPU and memory of the server, PostgreSQL and the load generator, read from /proc (Linux, same machine only).</summary>
    public sealed class ResourceSampler(int? serverPid)
    {
        private static readonly double Ticks = 100.0;
        private readonly Dictionary<string, double> _last = [];
        private DateTime _lastAt = DateTime.UtcNow;
        private (long Busy, long Total)? _lastMachine;

        public Dictionary<string, double?> Sample()
        {
            var now = DateTime.UtcNow;
            var seconds = Math.Max(0.001, (now - _lastAt).TotalSeconds);
            _lastAt = now;
            var result = new Dictionary<string, double?>();
            if (!OperatingSystem.IsLinux())
            {
                return result;
            }

            if (serverPid is { } pid && File.Exists($"/proc/{pid}/stat"))
            {
                result["serverCpu"] = Rate("server", CpuTicks(pid), seconds);
                var status = File.ReadAllLines($"/proc/{pid}/status");
                result["serverRssMb"] = Math.Round(StatusKb(status, "VmRSS:") / 1024.0, 1);
                result["serverThreads"] = StatusKb(status, "Threads:");
            }

            var pg = Directory.GetDirectories("/proc")
                .Select(d => int.TryParse(Path.GetFileName(d), out var p) ? p : -1)
                .Where(p => p > 0 && Comm(p) == "postgres")
                .ToList();
            if (pg.Count > 0)
            {
                result["dbCpu"] = Rate("db", pg.Sum(p => CpuTicks(p)), seconds);
                result["dbProcesses"] = pg.Count;
            }

            result["loadgenCpu"] = Rate("gen", Process.GetCurrentProcess().TotalProcessorTime.TotalSeconds * Ticks, seconds);

            var cpu = File.ReadLines("/proc/stat").First().Split(' ', StringSplitOptions.RemoveEmptyEntries).Skip(1).Select(long.Parse).ToArray();
            var total = cpu.Sum();
            var busy = total - cpu[3] - cpu[4];
            if (_lastMachine is { } m && total > m.Total)
            {
                result["machineCpu"] = Math.Round(100.0 * (busy - m.Busy) / (total - m.Total), 1);
            }

            _lastMachine = (busy, total);
            return result;
        }

        private double? Rate(string key, double ticks, double seconds)
        {
            var had = _last.TryGetValue(key, out var before);
            _last[key] = ticks;
            return had ? Math.Round(Math.Max(0, ticks - before) / Ticks / seconds * 100.0, 1) : null;
        }

        private static string? Comm(int pid)
        {
            try
            {
                return File.ReadAllText($"/proc/{pid}/comm").Trim();
            }
            catch
            {
                return null;
            }
        }

        private static double CpuTicks(int pid)
        {
            try
            {
                var stat = File.ReadAllText($"/proc/{pid}/stat");
                var fields = stat[(stat.LastIndexOf(')') + 2)..].Split(' ');
                return double.Parse(fields[11]) + double.Parse(fields[12]);
            }
            catch
            {
                return 0;
            }
        }

        private static double StatusKb(string[] status, string key) =>
            double.Parse(status.First(l => l.StartsWith(key))[key.Length..].Trim().Split(' ')[0]);
    }
}
