using FactoryWorld.Modules.Abstractions.Contracts;

namespace FactoryWorld.Modules.Logistics;

/// <summary>
/// The rules of belts and inserters. The logistics of a plot run in steps of <see cref="Tick"/>,
/// worked out when someone looks at the plot or changes it, for all the time since the last look.
/// </summary>
public static class LogisticsRules
{
    public static readonly TimeSpan Tick = TimeSpan.FromMilliseconds(200);

    /// <summary>Places for items along one lane of a belt tile; an item moves one place per tick.</summary>
    public const int BeltSlots = 4;

    /// <summary>Lanes side by side on a belt, the left one (as the belt runs) first.</summary>
    public const int BeltLanes = 2;

    /// <summary>Ticks the arm of a plain inserter takes to swing from where it picks up to where it drops, and as many back.</summary>
    public const int SwingTicks = 4;

    /// <summary>Belts of every level and how many places an item moves along them in a tick.</summary>
    public static readonly IReadOnlyDictionary<string, int> BeltSpeeds = new Dictionary<string, int>
    {
        [Items.Belt] = 1,
        [Items.FastBelt] = 2,
        [Items.ExpressBelt] = 3,
        [Items.CableStation] = 2,
    };

    /// <summary>Tiles a cable runs at most from one station to the next one ahead.</summary>
    public const int CableSpan = 24;

    /// <summary>Which station each cable station sends its items to over the cable: the nearest one
    /// ahead of it, facing the same way, at least two tiles off and no further than <see cref="CableSpan"/>.</summary>
    public static Dictionary<Guid, Guid> CableLinks(IEnumerable<PlotObject> objects)
    {
        var stations = objects.Where(o => o.Kind == Items.CableStation).ToDictionary(o => (o.TileX, o.TileY));
        var links = new Dictionary<Guid, Guid>();
        foreach (var station in stations.Values)
        {
            var (dx, dy) = Facing(station.Rotation);
            for (var d = 2; d <= CableSpan; d++)
            {
                if (stations.TryGetValue((station.TileX + dx * d, station.TileY + dy * d), out var other) && other.Rotation == station.Rotation)
                {
                    links[station.Id] = other.Id;
                    break;
                }
            }
        }

        return links;
    }

    /// <summary>Inserters of every level and the ticks their arm takes to swing one way.</summary>
    public static readonly IReadOnlyDictionary<string, int> InserterSwings = new Dictionary<string, int>
    {
        [Items.Inserter] = SwingTicks,
        [Items.FastInserter] = 2,
        [Items.ExpressInserter] = 1,
    };

    /// <summary>Places a tick an item moves along a belt of this kind; a splitter's own speed comes from the belt feeding it.</summary>
    public static int BeltSpeed(string kind) => BeltSpeeds.GetValueOrDefault(kind, 1);

    public static int Swing(string kind) => InserterSwings.GetValueOrDefault(kind, SwingTicks);

    /// <summary>Ticks of work done in one catch-up: 30 minutes. Machinery that keeps busy for longer
    /// while nobody looks (e.g. items going round a loop of belts) rests for the rest of the time.</summary>
    public const int MaxTicks = 9000;

    /// <summary>The tile a rotation faces, as (dx, dy): 0 south, 1 east, 2 north, 3 west.</summary>
    public static (int Dx, int Dy) Facing(int rotation) => (rotation & 3) switch
    {
        0 => (0, 1),
        1 => (1, 0),
        2 => (0, -1),
        _ => (-1, 0),
    };

    /// <summary>The tile on the left of something going the way a rotation faces.</summary>
    public static (int Dx, int Dy) Left(int rotation)
    {
        var (dx, dy) = Facing(rotation);
        return (dy, -dx);
    }
}

/// <summary>What a belt, an inserter or a storage holds; kept as JSON, one row per object.</summary>
public sealed class Contents
{
    /// <summary>A belt's places, lane after lane (left, then right), each from where items come on
    /// to where they leave; null is empty.</summary>
    public string?[]? Belt { get; set; }

    /// <summary>The item in an inserter's hand.</summary>
    public string? Hand { get; set; }

    /// <summary>How far the inserter's arm is, 0 (at the pick-up side) to its swing ticks (<see cref="LogisticsRules.Swing"/>).</summary>
    public int Swing { get; set; }

    /// <summary>How much of its next move an inserter on too little power has the power for, 0 to 1.</summary>
    public double Charge { get; set; }

    /// <summary>What a storage holds.</summary>
    public List<ItemStack>? Items { get; set; }

    /// <summary>A splitter's filter: these items go out on <see cref="FilterSide"/> only, the rest on
    /// the other side. Without one it sends items left and right in turn.</summary>
    public List<string>? Filter { get; set; }

    /// <summary>The side a splitter sends filtered items to: 0 left, 1 right (as the splitter runs).</summary>
    public int FilterSide { get; set; }

    /// <summary>The side a splitter without a filter sends the next item to.</summary>
    public int Turn { get; set; }

    /// <summary>The stack of a storage inserters take from next: they go round all of them in turn,
    /// so ore and coal stored together both reach a furnace.</summary>
    public int Next { get; set; }

    /// <summary>Everything in it, for handing back to the player.</summary>
    public IEnumerable<(string Item, int Quantity)> All()
    {
        foreach (var item in Belt ?? [])
        {
            if (item is not null)
            {
                yield return (item, 1);
            }
        }

        if (Hand is not null)
        {
            yield return (Hand, 1);
        }

        foreach (var stack in Items ?? [])
        {
            yield return (stack.Item, stack.Quantity);
        }
    }
}

/// <summary>A storage as inserters see it: anything stored can come out, anything it takes can go in.</summary>
public sealed class StoragePort(StorageKind kind, Contents contents, Action changed) : IMachinePort
{
    private List<ItemStack> Stacks => contents.Items ??= [];

    public string? Output(DateTimeOffset now, Func<string, bool> wanted)
    {
        var stacks = Stacks;
        for (var i = 0; i < stacks.Count; i++)
        {
            var stack = stacks[(contents.Next + i) % stacks.Count];
            if (stack.Quantity > 0 && wanted(stack.Item))
            {
                return stack.Item;
            }
        }

        return null;
    }

    public void Take(string item, DateTimeOffset now)
    {
        var at = Stacks.FindIndex(s => s.Item == item);
        if (Storages.Remove(Stacks, item, 1) > 0)
        {
            // The next stack comes next; one that ran out has made room for it already.
            contents.Next = Stacks.Count == 0 ? 0 : (Stacks.Count > at && Stacks[at].Item == item ? at + 1 : at) % Stacks.Count;
            changed();
        }
    }

    public bool Accepts(string item, DateTimeOffset now) => Storages.Room(kind, Stacks, item) > 0;

    public void Put(string item, DateTimeOffset now)
    {
        Storages.Add(Stacks, item, 1);
        changed();
    }

    public DateTimeOffset? NextChange(DateTimeOffset now) => null;

    public Task SaveAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}

/// <summary>
/// One plot's belts and inserters, with the machines and storage they reach, run step by step.
/// Belts move their items forward along two lanes, onto the belt they face (not head on). A belt fed
/// from behind, or from one side only, carries both lanes on as they are, so belts can turn corners;
/// a belt that joins another from the side as well puts all it carries on the near lane of that one.
/// An inserter picks one item from the tile behind it (a belt, a machine's output or a storage),
/// swings round and drops it on the tile in front, when that takes it: on a belt, on the far lane
/// first. Faster belts move their items more places a tick, in turns within the tick, and faster
/// inserters swing in fewer ticks; a splitter keeps up with the belt that feeds it from behind.
/// Inserters run on power: on a grid short of it they swing slower, without any they stand still.
/// </summary>
public sealed class PlotLogistics
{
    /// <summary>A belt or a splitter: lanes of places that items move along.</summary>
    private sealed class Belt(Guid id, int x, int y, int rotation, Contents contents, bool splitter, int speed)
    {
        public Guid Id { get; } = id;
        public int X { get; } = x;
        public int Y { get; } = y;
        public int Rotation { get; } = rotation;
        public Contents Contents { get; } = contents;
        public string?[] Slots => Contents.Belt!;
        public bool IsSplitter { get; } = splitter;

        /// <summary>Places items move along it in a tick.</summary>
        public int Speed { get; set; } = speed;

        /// <summary>Where items go at the end of the lanes: a belt has one way on, a splitter two
        /// (its left and its right), either of which may lead nowhere.</summary>
        public Link?[] Out { get; } = splitter ? new Link?[2] : new Link?[1];
    }

    /// <summary>The belt items go on to, the lane each lane leads to and the place on it they come on at.</summary>
    private sealed record Link(Belt To, int[] Into, int Entry);

    private sealed class Inserter(Guid id, Contents contents, int swingTicks)
    {
        public Guid Id { get; } = id;
        public Contents Contents { get; } = contents;
        public int SwingTicks { get; } = swingTicks;

        /// <summary>Its time on the plot's power grid; null runs it as if it had all the power it needs.</summary>
        public IPowerClock? Clock { get; set; }
        public Belt? FromBelt { get; set; }
        public IMachinePort? FromPort { get; set; }
        public Belt? ToBelt { get; set; }
        public IMachinePort? ToPort { get; set; }

        /// <summary>The lanes of the belt in front to drop on, the far one first.</summary>
        public int[] Lanes { get; set; } = [1, 0];
    }

    // An inserter drops on a lane in the middle first, where the item has room to move on.
    private static readonly int[] DropOrder = [1, 2, 0, 3];

    private readonly List<Belt> _belts = [];
    private readonly List<Inserter> _inserters = [];
    private readonly List<IMachinePort> _ports = [];

    /// <summary>Turns belts take in a tick: as many as the fastest one moves places.</summary>
    private readonly int _phases;

    /// <summary>Objects whose contents changed and must be written back.</summary>
    public HashSet<Guid> Changed { get; } = [];

    /// <param name="objects">Every object on the plot.</param>
    /// <param name="contents">Contents of belts and inserters by object id; missing ones start empty and are added.</param>
    /// <param name="ports">Machines and storage inserters can reach, by object id.</param>
    /// <param name="power">The plot's power grid; without one inserters work as if they had all the power they need.</param>
    public PlotLogistics(IReadOnlyList<PlotObject> objects, Dictionary<Guid, Contents> contents, IReadOnlyDictionary<Guid, IMachinePort> ports, IPowerGrid? power = null)
    {
        var at = objects.ToDictionary(o => (o.TileX, o.TileY));
        var belts = new Dictionary<(int, int), Belt>();
        foreach (var o in objects.Where(o => Items.IsBelt(o.Kind) || o.Kind is Items.Splitter or Items.CableStation).OrderBy(o => o.TileY).ThenBy(o => o.TileX))
        {
            var c = Contents(contents, o.Id);
            if (c.Belt is not { Length: LogisticsRules.BeltSlots * LogisticsRules.BeltLanes })
            {
                // A belt from before there were two lanes keeps what it had on the left one.
                var slots = new string?[LogisticsRules.BeltSlots * LogisticsRules.BeltLanes];
                c.Belt?.Take(slots.Length).ToArray().CopyTo(slots, 0);
                c.Belt = slots;
            }

            belts[(o.TileX, o.TileY)] = new Belt(o.Id, o.TileX, o.TileY, o.Rotation, c, o.Kind == Items.Splitter, LogisticsRules.BeltSpeed(o.Kind));
        }

        foreach (var belt in belts.Values.Where(b => b.IsSplitter))
        {
            var (dx, dy) = LogisticsRules.Facing(belt.Rotation);
            if (belts.GetValueOrDefault((belt.X - dx, belt.Y - dy)) is { IsSplitter: false } feeder && feeder.Rotation == belt.Rotation)
            {
                belt.Speed = feeder.Speed;
            }
        }

        _phases = belts.Count == 0 ? 0 : belts.Values.Max(b => b.Speed);

        // Only belts turn corners; a splitter always runs straight.
        var rotations = belts.Where(b => !b.Value.IsSplitter).ToDictionary(b => b.Key, b => b.Value.Rotation);
        var byId = belts.Values.ToDictionary(b => b.Id);
        var cables = LogisticsRules.CableLinks(objects);
        foreach (var belt in belts.Values)
        {
            if (cables.TryGetValue(belt.Id, out var station))
            {
                // Over the cable onto the start of the station ahead.
                belt.Out[0] = new Link(byId[station], [0, 1], 0);
            }
            else if (belt.IsSplitter)
            {
                var left = LogisticsRules.Left(belt.Rotation);
                belt.Out[0] = Connect(belts, rotations, belt, left);
                belt.Out[1] = Connect(belts, rotations, belt, (-left.Dx, -left.Dy));
            }
            else
            {
                belt.Out[0] = Connect(belts, rotations, belt, LogisticsRules.Facing(belt.Rotation));
            }
        }

        // Downstream belts move first, so a full line of items moves all together.
        var seen = new HashSet<Belt>();
        foreach (var start in belts.Values)
        {
            Downstream(start, seen);
        }

        foreach (var o in objects.Where(o => Items.IsInserter(o.Kind)).OrderBy(o => o.TileY).ThenBy(o => o.TileX))
        {
            var (dx, dy) = LogisticsRules.Facing(o.Rotation);
            var inserter = new Inserter(o.Id, Contents(contents, o.Id), LogisticsRules.Swing(o.Kind)) { Clock = power?.Clock(o.Id) };
            var from = (o.TileX - dx, o.TileY - dy);
            var to = (o.TileX + dx, o.TileY + dy);
            inserter.FromBelt = belts.GetValueOrDefault(from);
            inserter.ToBelt = belts.GetValueOrDefault(to);
            if (inserter.ToBelt is { } onto && LogisticsRules.Left(onto.Rotation) == (dx, dy))
            {
                // Standing on the belt's right, it reaches over to the left lane first.
                inserter.Lanes = [0, 1];
            }
            if (at.TryGetValue(from, out var source))
            {
                inserter.FromPort = ports.GetValueOrDefault(source.Id);
            }

            if (at.TryGetValue(to, out var target))
            {
                inserter.ToPort = ports.GetValueOrDefault(target.Id);
            }

            _inserters.Add(inserter);
        }

        _ports.AddRange(ports.Values.Distinct());
    }

    /// <summary>How items leave <paramref name="belt"/> towards <paramref name="way"/>: onto the belt
    /// there, unless that one runs head on into it.</summary>
    private static Link? Connect(Dictionary<(int, int), Belt> belts, Dictionary<(int, int), int> rotations, Belt belt, (int Dx, int Dy) way)
    {
        if (!belts.TryGetValue((belt.X + way.Dx, belt.Y + way.Dy), out var next) || LogisticsRules.Facing(next.Rotation) == (-way.Dx, -way.Dy))
        {
            return null;
        }

        if (LogisticsRules.Facing(next.Rotation) == way)
        {
            // From behind onto the start of it.
            return new Link(next, [0, 1], 0);
        }

        if (!next.IsSplitter && Bend(rotations, next.X, next.Y, next.Rotation) is not 0)
        {
            // From the side of a belt fed from that side only: it is a corner, the lanes go round it.
            return new Link(next, [0, 1], 0);
        }

        // From the side into the middle of the near lane.
        var near = LogisticsRules.Left(next.Rotation) == (-way.Dx, -way.Dy) ? 0 : 1;
        return new Link(next, [near, near], 1);
    }

    private void Downstream(Belt belt, HashSet<Belt> seen)
    {
        if (!seen.Add(belt))
        {
            return;
        }

        foreach (var link in belt.Out)
        {
            if (link is not null)
            {
                Downstream(link.To, seen);
            }
        }

        _belts.Add(belt);
    }

    /// <summary>Which side a belt turns in from: -1 when the only belt feeding it comes from its left,
    /// 1 from its right, 0 when it runs straight (fed from behind, from both sides or not at all).</summary>
    private static int Bend(Dictionary<(int, int), int> belts, int x, int y, int rotation)
    {
        bool Feeds((int Dx, int Dy) from)
        {
            if (!belts.TryGetValue((x + from.Dx, y + from.Dy), out var r))
            {
                return false;
            }

            var (dx, dy) = LogisticsRules.Facing(r);
            return (dx, dy) == (-from.Dx, -from.Dy);
        }

        var (fx, fy) = LogisticsRules.Facing(rotation);
        var left = LogisticsRules.Left(rotation);
        var (fromLeft, fromRight) = (Feeds(left), Feeds((-left.Dx, -left.Dy)));
        if (Feeds((-fx, -fy)) || fromLeft == fromRight)
        {
            return 0;
        }

        return fromLeft ? -1 : 1;
    }

    /// <summary>The tiles that inserters pick up from and drop on, which the machines there must be opened for.</summary>
    public static IEnumerable<(int TileX, int TileY)> Reach(IEnumerable<PlotObject> objects)
    {
        foreach (var o in objects.Where(o => Items.IsInserter(o.Kind)))
        {
            var (dx, dy) = LogisticsRules.Facing(o.Rotation);
            yield return (o.TileX - dx, o.TileY - dy);
            yield return (o.TileX + dx, o.TileY + dy);
        }
    }

    /// <summary>Runs from <paramref name="from"/> (on the grid of ticks) up to <paramref name="now"/>;
    /// returns the last tick worked out, the start of the next run.</summary>
    public DateTimeOffset Run(DateTimeOffset from, DateTimeOffset now)
    {
        var tick = LogisticsRules.Tick;
        var last = from + tick * Math.Max(0, (now - from).Ticks / tick.Ticks);
        if (_belts.Count == 0 && _inserters.Count == 0)
        {
            return last;
        }

        var t = from;
        var worked = 0;
        while (t < last)
        {
            t += tick;
            if (Step(t))
            {
                if (++worked >= LogisticsRules.MaxTicks)
                {
                    return last;
                }

                continue;
            }

            // Nothing moved, so nothing will until a machine makes something new by itself.
            var next = _ports.Select(p => p.NextChange(t)).Where(n => n > t).Min();
            if (next is not { } due || due > last)
            {
                return last;
            }

            // Next step on the first tick at or after it.
            var ticks = ((due - from).Ticks + tick.Ticks - 1) / tick.Ticks;
            t = from + tick * (ticks - 1);
        }

        return last;
    }

    /// <summary>One tick; true when anything moved.</summary>
    private bool Step(DateTimeOffset now)
    {
        var moved = false;
        for (var phase = 0; phase < _phases; phase++)
        {
            moved |= MoveBelts(phase);
        }

        foreach (var inserter in _inserters)
        {
            var c = inserter.Contents;
            var speed = inserter.Clock?.Speed(now) ?? 1;
            if (speed <= 0)
            {
                continue;
            }

            if (speed < 1)
            {
                // Short of power it gathers what one move takes over the ticks; one waiting for
                // something to do keeps no more than that.
                var charge = Math.Min(c.Charge, 1) + speed;
                if (charge != c.Charge)
                {
                    c.Charge = charge;
                    Changed.Add(inserter.Id);
                }

                if (charge < 1)
                {
                    moved = true;
                    continue;
                }
            }

            if (c.Hand is { } hand)
            {
                if (c.Swing < inserter.SwingTicks)
                {
                    c.Swing++;
                }
                else if (Drop(inserter, hand, now))
                {
                    c.Hand = null;
                }
                else
                {
                    continue;
                }
            }
            else if (c.Swing > 0)
            {
                c.Swing--;
            }
            else if (Pick(inserter, now) is { } picked)
            {
                c.Hand = picked;
            }
            else
            {
                continue;
            }

            if (speed < 1)
            {
                c.Charge -= 1;
            }

            Changed.Add(inserter.Id);
            moved = true;
        }

        return moved;
    }

    /// <summary>One turn of the belts within a tick: those fast enough move their items one place on.</summary>
    private bool MoveBelts(int phase)
    {
        var moved = false;
        const int size = LogisticsRules.BeltSlots;
        foreach (var belt in _belts)
        {
            if (belt.Speed <= phase)
            {
                continue;
            }

            var slots = belt.Slots;
            for (var lane = 0; lane < LogisticsRules.BeltLanes; lane++)
            {
                var start = lane * size;
                var end = start + size - 1;
                if (slots[end] is { } leaving && Pass(belt, lane, leaving))
                {
                    slots[end] = null;
                    Changed.Add(belt.Id);
                    moved = true;
                }

                for (var i = end - 1; i >= start; i--)
                {
                    if (slots[i] is not null && slots[i + 1] is null)
                    {
                        slots[i + 1] = slots[i];
                        slots[i] = null;
                        Changed.Add(belt.Id);
                        moved = true;
                    }
                }
            }
        }

        return moved;
    }

    /// <summary>Puts the item at the end of a lane on the belt it goes on to, when there is room there.
    /// A splitter sends items left and right in turn, or filtered items one way and the rest the other.</summary>
    private bool Pass(Belt belt, int lane, string item)
    {
        var c = belt.Contents;
        int[] ways = !belt.IsSplitter ? [0]
            : c.Filter is { Count: > 0 } filter ? [filter.Contains(item) ? c.FilterSide : 1 - c.FilterSide]
            : [c.Turn, 1 - c.Turn];
        foreach (var way in ways)
        {
            if (belt.Out[way] is not { } link)
            {
                continue;
            }

            var at = link.Into[lane] * LogisticsRules.BeltSlots + link.Entry;
            if (link.To.Slots[at] is null)
            {
                link.To.Slots[at] = item;
                Changed.Add(link.To.Id);
                if (belt.IsSplitter)
                {
                    c.Turn = 1 - way;
                }

                return true;
            }
        }

        return false;
    }

    private string? Pick(Inserter inserter, DateTimeOffset now)
    {
        Func<string, bool> wanted;
        if (inserter.ToBelt is not null)
        {
            wanted = _ => true;
        }
        else if (inserter.ToPort is { } port)
        {
            wanted = item => port.Accepts(item, now);
        }
        else
        {
            return null;
        }

        if (inserter.FromBelt is { } belt)
        {
            // The item furthest along goes first, from either lane.
            for (var i = LogisticsRules.BeltSlots - 1; i >= 0; i--)
            {
                for (var lane = 0; lane < LogisticsRules.BeltLanes; lane++)
                {
                    var at = lane * LogisticsRules.BeltSlots + i;
                    if (belt.Slots[at] is { } item && wanted(item))
                    {
                        belt.Slots[at] = null;
                        Changed.Add(belt.Id);
                        return item;
                    }
                }
            }

            return null;
        }

        if (inserter.FromPort is { } from && from.Output(now, wanted) is { } output)
        {
            from.Take(output, now);
            return output;
        }

        return null;
    }

    private bool Drop(Inserter inserter, string item, DateTimeOffset now)
    {
        if (inserter.ToBelt is { } belt)
        {
            foreach (var lane in inserter.Lanes)
            {
                foreach (var i in DropOrder)
                {
                    var at = lane * LogisticsRules.BeltSlots + i;
                    if (belt.Slots[at] is null)
                    {
                        belt.Slots[at] = item;
                        Changed.Add(belt.Id);
                        return true;
                    }
                }
            }

            return false;
        }

        if (inserter.ToPort is { } port && port.Accepts(item, now))
        {
            port.Put(item, now);
            return true;
        }

        return false;
    }

    private static Contents Contents(Dictionary<Guid, Contents> contents, Guid id)
    {
        if (!contents.TryGetValue(id, out var c))
        {
            contents[id] = c = new Contents();
        }

        return c;
    }
}
