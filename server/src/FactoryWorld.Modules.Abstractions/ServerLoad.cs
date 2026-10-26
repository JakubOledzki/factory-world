using System.Diagnostics;

namespace FactoryWorld.Modules.Abstractions;

/// <summary>
/// How long the server spends on each kind of message, from players and from bots, so the log can say once a
/// minute what keeps it busy and which messages were slow. Kept in memory; nothing is saved.
/// </summary>
public sealed class ServerLoad
{
    /// <summary>A single message taking longer than this is logged on its own.</summary>
    public static readonly TimeSpan Slow = TimeSpan.FromSeconds(1);

    private readonly object _lock = new();
    private Dictionary<string, Tally> _tallies = new(StringComparer.Ordinal);

    /// <summary>The time from now, to pass to <see cref="Record"/> when the work is done.</summary>
    public static long Start() => Stopwatch.GetTimestamp();

    /// <summary>Counts one message of <paramref name="type"/> that started at <paramref name="started"/>; returns how long it took.</summary>
    public TimeSpan Record(string type, long started)
    {
        var elapsed = Stopwatch.GetElapsedTime(started);
        lock (_lock)
        {
            if (!_tallies.TryGetValue(type, out var tally))
            {
                _tallies[type] = tally = new Tally(type);
            }

            tally.Count++;
            tally.Total += elapsed;
            if (elapsed > tally.Max)
            {
                tally.Max = elapsed;
            }
        }

        return elapsed;
    }

    /// <summary>What was counted since the last call, the busiest kinds first; starts counting anew.</summary>
    public IReadOnlyList<Tally> Take()
    {
        Dictionary<string, Tally> taken;
        lock (_lock)
        {
            taken = _tallies;
            _tallies = new Dictionary<string, Tally>(StringComparer.Ordinal);
        }

        return taken.Values.OrderByDescending(t => t.Total).ToList();
    }

    public sealed class Tally(string type)
    {
        public string Type { get; } = type;

        public long Count { get; set; }

        public TimeSpan Total { get; set; }

        public TimeSpan Max { get; set; }
    }
}
