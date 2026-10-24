using System.Text.Json.Serialization;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;

namespace FactoryWorld.Modules.Power;

/// <summary>
/// The rules of power on plots. A generator burns wood or coal and gives up to
/// <see cref="GeneratorKw"/>; a pole powers the tiles around it (<see cref="SupplyRadius"/> each way)
/// and is wired to every pole up to <see cref="WireReach"/> tiles away. Poles wired together make one
/// network: its generators share the load of all the machines on it. Machines draw their power
/// whenever they stand on a network, busy or not; with too little power they all work slower, and
/// without any they stop. A water wheel, a hydro plant and a tidal plant on the coast give their power all the time without fuel, on
/// plots by a river, a lake or the sea; the generators of their network burn only for what they lack.
/// </summary>
public static class PowerRules
{
    public const double GeneratorKw = 100;

    /// <summary>What each water power plant gives (kW), before the biome's bonus.</summary>
    public static readonly IReadOnlyDictionary<string, double> Hydro = new Dictionary<string, double>
    {
        [Items.WaterWheel] = 30,
        [Items.HydroPlant] = 150,
        // The tide comes and goes twice a day, so a tidal plant gives what it gives all the time.
        [Items.TidalPlant] = 100,
    };


    /// <summary>Pieces of fuel a generator holds.</summary>
    public const int MaxFuel = 50;

    /// <summary>A pole powers a square of tiles this far from it each way: 5 × 5 tiles.</summary>
    public const int SupplyRadius = 2;

    /// <summary>Poles at most this many tiles apart are wired together.</summary>
    public const double WireReach = 7;

    /// <summary>What a generator burns, and the energy (kJ) in one piece: coal lasts 200 s at full power, wood 50 s, a pellet 40 s.</summary>
    public static readonly IReadOnlyDictionary<string, double> Fuels = new Dictionary<string, double>
    {
        [Items.Coal] = 20_000,
        [Items.Wood] = 5_000,
        [Items.WoodPellets] = 4_000,
    };

    /// <summary>Machines that run on power, and what they draw (kW).</summary>
    public static readonly IReadOnlyDictionary<string, double> Demand = new Dictionary<string, double>
    {
        [Items.Inserter] = 5,
        [Items.FastInserter] = 8,
        [Items.ExpressInserter] = 12,
        [Items.Mill] = 30,
        [Items.OilPress] = 30,
        [Items.ElectricSawmill] = 40,
        [Items.IndustrialSawmill] = 80,
        [Items.Crusher] = 40,
        [Items.Drill] = 40,
        [Items.HeavyDrill] = 100,
        [Items.Cannery] = 30,
    };

    public static bool Covers(PlotObject pole, int tileX, int tileY) =>
        Math.Abs(pole.TileX - tileX) <= SupplyRadius && Math.Abs(pole.TileY - tileY) <= SupplyRadius;

    public static bool Wired(PlotObject a, PlotObject b)
    {
        var (dx, dy) = (a.TileX - b.TileX, a.TileY - b.TileY);
        return dx * dx + dy * dy <= WireReach * WireReach;
    }

    /// <summary>The networks of a plot: poles wired together, with the generators and machines they power.
    /// Something within reach of poles of two networks belongs to the one of the first pole (north to south, west to east).</summary>
    public static IReadOnlyList<Network> Networks(IEnumerable<PlotObject> objects)
    {
        var all = objects.ToList();
        var poles = all.Where(o => o.Kind == Items.Pole).OrderBy(o => o.TileY).ThenBy(o => o.TileX).ToList();
        var component = new int[poles.Count];
        Array.Fill(component, -1);
        var count = 0;
        for (var i = 0; i < poles.Count; i++)
        {
            if (component[i] >= 0)
            {
                continue;
            }

            component[i] = count;
            var queue = new Queue<int>([i]);
            while (queue.TryDequeue(out var at))
            {
                for (var j = 0; j < poles.Count; j++)
                {
                    if (component[j] < 0 && Wired(poles[at], poles[j]))
                    {
                        component[j] = count;
                        queue.Enqueue(j);
                    }
                }
            }

            count++;
        }

        var generators = Enumerable.Range(0, count).Select(_ => new List<Guid>()).ToList();
        var hydro = Enumerable.Range(0, count).Select(_ => new List<Guid>()).ToList();
        var consumers = Enumerable.Range(0, count).Select(_ => new List<Guid>()).ToList();
        var demand = new double[count];
        foreach (var o in all)
        {
            var isGenerator = o.Kind == Items.Generator;
            if (!isGenerator && !Items.IsHydro(o.Kind) && !Demand.ContainsKey(o.Kind))
            {
                continue;
            }

            var pole = poles.FindIndex(p => Covers(p, o.TileX, o.TileY));
            if (pole < 0)
            {
                continue;
            }

            if (isGenerator)
            {
                generators[component[pole]].Add(o.Id);
            }
            else if (Items.IsHydro(o.Kind))
            {
                hydro[component[pole]].Add(o.Id);
            }
            else
            {
                consumers[component[pole]].Add(o.Id);
                demand[component[pole]] += Demand[o.Kind];
            }
        }

        return Enumerable.Range(0, count)
            .Select(n => new Network(n, poles.Where((_, i) => component[i] == n).Select(p => p.Id).ToList(), generators[n], consumers[n], demand[n], hydro[n]))
            .ToList();
    }

    /// <summary>What a water power plant of <paramref name="kind"/> gives on a plot of <paramref name="biome"/> (kW); 0 where no water flows.</summary>
    public static double HydroKw(string kind, int biome) => Hydro.GetValueOrDefault(kind) * WaterPower.Biomes.GetValueOrDefault(biome);
}

/// <param name="DemandKw">What all its machines draw together.</param>
/// <param name="Hydro">Water wheels and hydro plants on it, which give their power without fuel.</param>
public sealed record Network(
    int Id, IReadOnlyList<Guid> Poles, IReadOnlyList<Guid> Generators, IReadOnlyList<Guid> Consumers, double DemandKw, IReadOnlyList<Guid> Hydro);

/// <param name="FuelItem">What lies by the fire, or null.</param>
/// <param name="Fuel">Pieces of it not burning yet.</param>
/// <param name="Energy">kJ left in the piece burning now.</param>
public sealed record GeneratorState(string? FuelItem, int Fuel, double Energy)
{
    public static readonly GeneratorState Empty = new(null, 0, 0);

    /// <summary>kJ left in it, the fuel not burning yet included.</summary>
    [JsonIgnore]
    public double Total => Energy + (FuelItem is { } fuel ? Fuel * PowerRules.Fuels.GetValueOrDefault(fuel) : 0);

    [JsonIgnore]
    public bool Running => Total > 0;

    /// <summary>After giving <paramref name="kj"/>: the burning piece first, then more pieces lit one by one.</summary>
    public GeneratorState Burn(double kj)
    {
        if (kj <= Energy)
        {
            return this with { Energy = Energy - kj };
        }

        var piece = FuelItem is { } fuel ? PowerRules.Fuels.GetValueOrDefault(fuel) : 0;
        var needed = kj - Energy;
        if (piece <= 0 || needed >= Fuel * piece)
        {
            return Empty;
        }

        var lit = (int)Math.Ceiling(needed / piece);
        var left = Fuel - lit;
        return new GeneratorState(left > 0 ? FuelItem : null, left, lit * piece - needed);
    }
}

/// <summary>What is saved of a plot's grid: the generators' fuel and how far each machine's own time
/// lags behind the clock (<see cref="IPowerClock"/>), both as they were at the moment it was settled.</summary>
public sealed class GridData
{
    public Dictionary<Guid, GeneratorState> Generators { get; set; } = [];

    /// <summary>Ticks of time each machine has gone without power.</summary>
    public Dictionary<Guid, long> Lags { get; set; } = [];
}

/// <summary>
/// One plot's power from the moment it was last settled on. Nothing changes the grid but fuel put
/// in or taken out and objects put on the plot or taken off, and each of those settles it first:
/// so how its generators burn down and how fast its machines work is known for any time after.
/// </summary>
public sealed class PowerGrid : IPowerGrid
{
    /// <summary>A stretch of time in which a network runs the same way.</summary>
    /// <param name="KwEach">What each running generator gives.</param>
    /// <param name="States">The network's generators as they were at <paramref name="Start"/>.</param>
    private sealed record Segment(DateTimeOffset Start, DateTimeOffset? End, double Speed, double KwEach, IReadOnlyDictionary<Guid, GeneratorState> States);

    private readonly IReadOnlyList<PlotObject> _objects;
    private readonly Dictionary<Guid, Network> _networkOf = [];
    private readonly Func<GridData, DateTimeOffset, CancellationToken, Task> _save;
    private List<Segment>[] _timelines = [];

    public PowerGrid(
        int x, int y, IReadOnlyList<PlotObject> objects, GridData data, DateTimeOffset settled, Func<GridData, DateTimeOffset, CancellationToken, Task> save, int biome = 0)
    {
        X = x;
        Y = y;
        Biome = biome;
        _objects = objects;
        _save = save;
        Data = data;
        Settled = settled;
        Networks = PowerRules.Networks(objects);
        foreach (var network in Networks)
        {
            foreach (var id in network.Generators.Concat(network.Consumers).Concat(network.Hydro))
            {
                _networkOf[id] = network;
            }
        }

        Plan();
    }

    public int X { get; }

    public int Y { get; }

    /// <summary>The plot's biome (as WorldMap numbers them), which decides what water power gives.</summary>
    public int Biome { get; }

    /// <summary>What a water power plant on the plot gives (kW), whether or not a pole reaches it.</summary>
    public double HydroKw(Guid id) => _objects.FirstOrDefault(o => o.Id == id) is { } o ? PowerRules.HydroKw(o.Kind, Biome) : 0;

    /// <summary>What all the water power of a network gives together (kW).</summary>
    public double HydroKw(Network network) => network.Hydro.Sum(HydroKw);

    /// <summary>What a network's power plants can give at <paramref name="at"/>: running generators and water power (kW).</summary>
    public double SupplyKw(Network network, DateTimeOffset at) =>
        network.Generators.Count(g => Generator(g, at).Running) * PowerRules.GeneratorKw + HydroKw(network);

    public IReadOnlyList<Network> Networks { get; }

    public GridData Data { get; private set; }

    /// <summary>The moment the grid is worked out from.</summary>
    public DateTimeOffset Settled { get; private set; }

    public IReadOnlyList<PlotObject> Objects => _objects;

    /// <summary>Whether something changed since it was read.</summary>
    public bool Changed { get; private set; }

    public Network? NetworkOf(Guid id) => _networkOf.GetValueOrDefault(id);

    /// <summary>Whether the grid knows of this object: it stands on the plot or did when the grid was last settled.</summary>
    public bool Knows(Guid id) => _objects.Any(o => o.Id == id) || Data.Lags.ContainsKey(id) || Data.Generators.ContainsKey(id);

    public GeneratorState Generator(Guid id, DateTimeOffset at)
    {
        if (_networkOf.TryGetValue(id, out var network) && SegmentAt(network, at) is { } segment)
        {
            var state = segment.States.GetValueOrDefault(id) ?? GeneratorState.Empty;
            return state.Running && segment.KwEach > 0 ? state.Burn(segment.KwEach * Seconds(segment.Start, Max(at, Settled))) : state;
        }

        return Data.Generators.GetValueOrDefault(id) ?? GeneratorState.Empty;
    }

    /// <summary>The power a generator gives at <paramref name="at"/> (kW); a water power plant gives its share of what its network draws.</summary>
    public double Output(Guid id, DateTimeOffset at)
    {
        if (!_networkOf.TryGetValue(id, out var network))
        {
            return 0;
        }

        if (network.Hydro.Contains(id))
        {
            var water = HydroKw(network);
            return water <= 0 ? 0 : HydroKw(id) * Math.Min(1, network.DemandKw / water);
        }

        return SegmentAt(network, at) is { } segment && segment.States.GetValueOrDefault(id)?.Running == true ? segment.KwEach : 0;
    }

    /// <summary>When a generator burns its last fuel, or null if it never does on what it powers now.</summary>
    public DateTimeOffset? RunsOutAt(Guid id)
    {
        if (!_networkOf.TryGetValue(id, out var network))
        {
            return null;
        }

        var timeline = _timelines[network.Id];
        for (var i = 0; i < timeline.Count; i++)
        {
            var running = timeline[i].States.GetValueOrDefault(id)?.Running == true;
            var after = i + 1 < timeline.Count && timeline[i + 1].States.GetValueOrDefault(id)?.Running == true;
            if (running && !after && timeline[i].End is { } end)
            {
                return end;
            }
        }

        return null;
    }

    /// <summary>How fast a network's machines work at <paramref name="at"/>.</summary>
    public double Speed(Network network, DateTimeOffset at) => SegmentAt(network, at)?.Speed ?? 0;

    /// <summary>When the speed of a network next changes after <paramref name="at"/>, or null.</summary>
    public DateTimeOffset? NextChange(Network network, DateTimeOffset at) =>
        _timelines[network.Id].FirstOrDefault(s => s.End > at)?.End;

    public double Speed(Guid id, DateTimeOffset at) => _networkOf.TryGetValue(id, out var network) ? Speed(network, at) : 0;

    /// <summary>Ticks a machine has gone without power by <paramref name="at"/>.</summary>
    public long Lag(Guid id, DateTimeOffset at)
    {
        var lag = Data.Lags.GetValueOrDefault(id);
        if (at <= Settled)
        {
            return lag;
        }

        if (!_networkOf.TryGetValue(id, out var network) || !PowerRules.Demand.ContainsKey(KindOf(id)))
        {
            return lag + (at - Settled).Ticks;
        }

        foreach (var segment in _timelines[network.Id])
        {
            if (segment.Start >= at)
            {
                break;
            }

            var end = segment.End is { } e && e < at ? e : at;
            lag += Unpowered(segment.Speed, (end - segment.Start).Ticks);
        }

        return lag;
    }

    public IPowerClock Clock(Guid id) => new MachineClock(this, id);

    public object Summary(DateTimeOffset now) => PowerJson.Grid(this, now);

    public IMachinePort? Port(Guid id) => _objects.Any(o => o.Id == id && o.Kind == Items.Generator) ? new GeneratorPort(this, id) : null;

    public async Task SaveAsync(CancellationToken cancellationToken)
    {
        if (Changed)
        {
            await _save(Data, Settled, cancellationToken);
            Changed = false;
        }
    }

    /// <summary>Brings everything up to <paramref name="at"/> and works on from there, so the grid can change.</summary>
    public void Settle(DateTimeOffset at)
    {
        at = Max(at, Settled);
        var data = new GridData();
        foreach (var o in _objects)
        {
            if (o.Kind == Items.Generator && Generator(o.Id, at) is { Running: true } generator)
            {
                data.Generators[o.Id] = generator;
            }
            else if (PowerRules.Demand.ContainsKey(o.Kind))
            {
                data.Lags[o.Id] = Lag(o.Id, at);
            }
        }

        Data = data;
        Settled = at;
        Changed = true;
        Plan();
    }

    /// <summary>Puts fuel by a generator's fire, at <paramref name="at"/>; fails when it does not fit.</summary>
    public void Fuel(Guid id, string item, int quantity, DateTimeOffset at)
    {
        if (!PowerRules.Fuels.ContainsKey(item))
        {
            throw new GameException("not_fuel", "A generator burns only wood and coal.");
        }

        var state = Generator(id, at);
        if (state.FuelItem is { } fuel && fuel != item && state.Fuel > 0)
        {
            throw new GameException("generator_busy", $"{Items.Names[fuel]} lies by the fire; take it out first.");
        }

        if (state.Fuel + quantity > PowerRules.MaxFuel)
        {
            throw new GameException("generator_full", $"A generator holds at most {PowerRules.MaxFuel} pieces of fuel.");
        }

        Settle(at);
        Data.Generators[id] = state with { FuelItem = item, Fuel = state.Fuel + quantity };
        Plan();
    }

    /// <summary>Takes out the fuel not burning yet; the piece in the fire burns on.</summary>
    public (string Item, int Quantity)? Unfuel(Guid id, DateTimeOffset at)
    {
        var state = Generator(id, at);
        if (state.FuelItem is not { } fuel || state.Fuel == 0)
        {
            return null;
        }

        Settle(at);
        Data.Generators[id] = state with { FuelItem = null, Fuel = 0 };
        Plan();
        return (fuel, state.Fuel);
    }

    /// <summary>A generator taken off the plot: the grid goes on without it.</summary>
    public void Remove(Guid id, DateTimeOffset at)
    {
        Settle(at);
        Data.Generators.Remove(id);
        Data.Lags.Remove(id);
        Plan();
    }

    /// <summary>How each network runs from <see cref="Settled"/> on: until a generator burns out, then on the others.</summary>
    private void Plan()
    {
        _timelines = new List<Segment>[Networks.Count];
        foreach (var network in Networks)
        {
            var states = network.Generators.ToDictionary(g => g, g => Data.Generators.GetValueOrDefault(g) ?? GeneratorState.Empty);
            var timeline = new List<Segment>();
            var t = Settled;
            // Water power covers what it can; the generators burn only for the rest.
            var water = HydroKw(network);
            var lacking = network.DemandKw - water;
            while (true)
            {
                var running = states.Where(s => s.Value.Running).Select(s => s.Key).ToList();
                if (lacking <= 0 || running.Count == 0)
                {
                    var speed = network.DemandKw <= 0 || lacking <= 0 ? 1 : water / network.DemandKw;
                    timeline.Add(new Segment(t, null, speed, 0, states));
                    break;
                }

                var supply = running.Count * PowerRules.GeneratorKw;
                var each = Math.Min(lacking, supply) / running.Count;
                var first = running.MinBy(g => states[g].Total)!;
                var seconds = states[first].Total / each;
                var end = t + TimeSpan.FromTicks(Math.Max(1, (long)Math.Ceiling(seconds * TimeSpan.TicksPerSecond)));
                timeline.Add(new Segment(t, end, Math.Min(1, (supply + water) / network.DemandKw), each, states));
                states = states.ToDictionary(s => s.Key, s =>
                    s.Key == first ? GeneratorState.Empty : s.Value.Running ? s.Value.Burn(each * seconds) : s.Value);
                t = end;
            }

            _timelines[network.Id] = timeline;
        }
    }

    private Segment? SegmentAt(Network network, DateTimeOffset at)
    {
        var timeline = _timelines[network.Id];
        foreach (var segment in timeline)
        {
            if (segment.End is not { } end || at < end)
            {
                return segment;
            }
        }

        return timeline.LastOrDefault();
    }

    private string KindOf(Guid id) => _objects.FirstOrDefault(o => o.Id == id)?.Kind ?? "";

    private static long Unpowered(double speed, long ticks) => speed >= 1 ? 0 : speed <= 0 ? ticks : (long)Math.Round((1 - speed) * ticks);

    private static double Seconds(DateTimeOffset from, DateTimeOffset to) => Math.Max(0, (to - from).Ticks) / (double)TimeSpan.TicksPerSecond;

    private static DateTimeOffset Max(DateTimeOffset a, DateTimeOffset b) => a > b ? a : b;

    /// <summary>A machine's own time: the clock less the time it went without power.</summary>
    private sealed class MachineClock(PowerGrid grid, Guid id) : IPowerClock
    {
        public DateTimeOffset At(DateTimeOffset now) => now - TimeSpan.FromTicks(grid.Lag(id, now));

        public double Speed(DateTimeOffset now) => grid.Speed(id, now);

        public DateTimeOffset? When(DateTimeOffset machineTime, DateTimeOffset now)
        {
            if (At(now) >= machineTime)
            {
                return now;
            }

            if (grid._networkOf.GetValueOrDefault(id) is not { } network)
            {
                return null;
            }

            foreach (var segment in grid._timelines[network.Id])
            {
                var from = Max(segment.Start, Max(now, grid.Settled));
                if (segment.End is { } end && end <= from)
                {
                    continue;
                }

                if (segment.Speed > 0)
                {
                    var need = (machineTime - At(from)).Ticks;
                    var due = from + TimeSpan.FromTicks((long)Math.Ceiling(need / segment.Speed));
                    if (segment.End is not { } stop || due <= stop)
                    {
                        return due;
                    }
                }
            }

            return null;
        }
    }

    /// <summary>A generator as inserters see it: wood or coal goes in, nothing comes out.</summary>
    private sealed class GeneratorPort(PowerGrid grid, Guid id) : IMachinePort
    {
        public string? Output(DateTimeOffset now, Func<string, bool> wanted) => null;

        public void Take(string item, DateTimeOffset now)
        {
        }

        public bool Accepts(string item, DateTimeOffset now)
        {
            if (!PowerRules.Fuels.ContainsKey(item))
            {
                return false;
            }

            var state = grid.Generator(id, now);
            return (state.FuelItem is null || state.FuelItem == item || state.Fuel == 0) && state.Fuel < PowerRules.MaxFuel;
        }

        public void Put(string item, DateTimeOffset now) => grid.Fuel(id, item, 1, now);

        public DateTimeOffset? NextChange(DateTimeOffset now) => null;

        public Task SaveAsync(CancellationToken cancellationToken) => grid.SaveAsync(cancellationToken);
    }
}
