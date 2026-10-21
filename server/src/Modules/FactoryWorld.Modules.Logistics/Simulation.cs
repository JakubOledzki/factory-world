using FactoryWorld.Modules.Abstractions.Contracts;

namespace FactoryWorld.Modules.Logistics;

/// <summary>
/// The rules of belts and inserters. The logistics of a plot run in steps of <see cref="Tick"/>,
/// worked out when someone looks at the plot or changes it, for all the time since the last look.
/// </summary>
public static class LogisticsRules
{
    public static readonly TimeSpan Tick = TimeSpan.FromMilliseconds(200);

    /// <summary>Places for items along one belt tile; an item moves one place per tick.</summary>
    public const int BeltSlots = 4;

    /// <summary>Ticks an inserter's arm takes to swing from where it picks up to where it drops, and as many back.</summary>
    public const int SwingTicks = 4;

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
}

/// <summary>What a belt, an inserter or a storage holds; kept as JSON, one row per object.</summary>
public sealed class Contents
{
    /// <summary>A belt's places, from where items come on to where they leave; null is empty.</summary>
    public string?[]? Belt { get; set; }

    /// <summary>The item in an inserter's hand.</summary>
    public string? Hand { get; set; }

    /// <summary>How far the inserter's arm is, 0 (at the pick-up side) to <see cref="LogisticsRules.SwingTicks"/>.</summary>
    public int Swing { get; set; }

    /// <summary>What a storage holds.</summary>
    public List<ItemStack>? Items { get; set; }

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

    public string? Output(DateTimeOffset now, Func<string, bool> wanted) =>
        Stacks.FirstOrDefault(s => s.Quantity > 0 && wanted(s.Item))?.Item;

    public void Take(string item, DateTimeOffset now)
    {
        if (Storages.Remove(Stacks, item, 1) > 0)
        {
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
/// Belts move their items forward, onto the belt they face (from behind or from the side, not head
/// on); an inserter picks one item from the tile behind it (a belt, a machine's output or a storage),
/// swings round and drops it on the tile in front, when that takes it.
/// </summary>
public sealed class PlotLogistics
{
    private sealed class Belt(Guid id, int x, int y, int rotation, string?[] slots)
    {
        public Guid Id { get; } = id;
        public int X { get; } = x;
        public int Y { get; } = y;
        public int Rotation { get; } = rotation;
        public string?[] Slots { get; } = slots;
        public Belt? Next { get; set; }
        public int Entry { get; set; }
    }

    private sealed class Inserter(Guid id, Contents contents)
    {
        public Guid Id { get; } = id;
        public Contents Contents { get; } = contents;
        public Belt? FromBelt { get; set; }
        public IMachinePort? FromPort { get; set; }
        public Belt? ToBelt { get; set; }
        public IMachinePort? ToPort { get; set; }
    }

    // An inserter drops on a belt in the middle first, where the item has room to move on.
    private static readonly int[] DropOrder = [1, 2, 0, 3];

    private readonly List<Belt> _belts = [];
    private readonly List<Inserter> _inserters = [];
    private readonly List<IMachinePort> _ports = [];

    /// <summary>Objects whose contents changed and must be written back.</summary>
    public HashSet<Guid> Changed { get; } = [];

    /// <param name="objects">Every object on the plot.</param>
    /// <param name="contents">Contents of belts and inserters by object id; missing ones start empty and are added.</param>
    /// <param name="ports">Machines and storage inserters can reach, by object id.</param>
    public PlotLogistics(IReadOnlyList<PlotObject> objects, Dictionary<Guid, Contents> contents, IReadOnlyDictionary<Guid, IMachinePort> ports)
    {
        var at = objects.ToDictionary(o => (o.TileX, o.TileY));
        var belts = new Dictionary<(int, int), Belt>();
        foreach (var o in objects.Where(o => o.Kind == Items.Belt).OrderBy(o => o.TileY).ThenBy(o => o.TileX))
        {
            var c = Contents(contents, o.Id);
            if (c.Belt is not { Length: LogisticsRules.BeltSlots })
            {
                var slots = new string?[LogisticsRules.BeltSlots];
                c.Belt?.Take(LogisticsRules.BeltSlots).ToArray().CopyTo(slots, 0);
                c.Belt = slots;
            }

            belts[(o.TileX, o.TileY)] = new Belt(o.Id, o.TileX, o.TileY, o.Rotation, c.Belt);
        }

        foreach (var belt in belts.Values)
        {
            var (dx, dy) = LogisticsRules.Facing(belt.Rotation);
            if (belts.TryGetValue((belt.X + dx, belt.Y + dy), out var next) && (next.Rotation & 3) != ((belt.Rotation + 2) & 3))
            {
                belt.Next = next;
                // From behind onto the start of the next belt, from the side into its middle.
                belt.Entry = (next.Rotation & 3) == (belt.Rotation & 3) ? 0 : 1;
            }
        }

        // Downstream belts move first, so a full line of items moves all together.
        var state = new Dictionary<Belt, bool>();
        foreach (var start in belts.Values)
        {
            var path = new List<Belt>();
            for (var b = start; b is not null && !state.ContainsKey(b); b = b.Next)
            {
                state[b] = false;
                path.Add(b);
            }

            path.Reverse();
            _belts.AddRange(path);
        }

        foreach (var o in objects.Where(o => o.Kind == Items.Inserter).OrderBy(o => o.TileY).ThenBy(o => o.TileX))
        {
            var (dx, dy) = LogisticsRules.Facing(o.Rotation);
            var inserter = new Inserter(o.Id, Contents(contents, o.Id));
            var from = (o.TileX - dx, o.TileY - dy);
            var to = (o.TileX + dx, o.TileY + dy);
            inserter.FromBelt = belts.GetValueOrDefault(from);
            inserter.ToBelt = belts.GetValueOrDefault(to);
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

    /// <summary>The tiles that inserters pick up from and drop on, which the machines there must be opened for.</summary>
    public static IEnumerable<(int TileX, int TileY)> Reach(IEnumerable<PlotObject> objects)
    {
        foreach (var o in objects.Where(o => o.Kind == Items.Inserter))
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
        foreach (var belt in _belts)
        {
            var slots = belt.Slots;
            var end = slots.Length - 1;
            if (slots[end] is { } leaving && belt.Next is { } next && next.Slots[belt.Entry] is null)
            {
                next.Slots[belt.Entry] = leaving;
                slots[end] = null;
                Changed.Add(next.Id);
                Changed.Add(belt.Id);
                moved = true;
            }

            for (var i = end - 1; i >= 0; i--)
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

        foreach (var inserter in _inserters)
        {
            var c = inserter.Contents;
            if (c.Hand is { } hand)
            {
                if (c.Swing < LogisticsRules.SwingTicks)
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

            Changed.Add(inserter.Id);
            moved = true;
        }

        return moved;
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
            // The item furthest along goes first.
            for (var i = belt.Slots.Length - 1; i >= 0; i--)
            {
                if (belt.Slots[i] is { } item && wanted(item))
                {
                    belt.Slots[i] = null;
                    Changed.Add(belt.Id);
                    return item;
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
            foreach (var i in DropOrder)
            {
                if (belt.Slots[i] is null)
                {
                    belt.Slots[i] = item;
                    Changed.Add(belt.Id);
                    return true;
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
