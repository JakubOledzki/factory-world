using System.Collections.Concurrent;
using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.World;

/// <summary>
/// Who walks where on which plot right now, so the players sharing a plot (a company's, or the owner
/// with company members) see each other. Kept in memory only: every client inside a plot sends where
/// it stands a few times a second and gets the others back; a player who stops sending (left the plot,
/// lost the connection) is gone after <see cref="Timeout"/>.
/// </summary>
public sealed class PlotPresence(TimeProvider time)
{
    /// <summary>How long a player stays on the plot after the last word from their client.</summary>
    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(5);

    private static readonly string[] Facings = ["down", "left", "right", "up"];

    private sealed record Spot(int PlotX, int PlotY, string Name, object Appearance, double X, double Y, string Facing, bool Walking, DateTimeOffset Seen);

    private readonly ConcurrentDictionary<Guid, Spot> _spots = new();

    /// <summary>Whether a character's name and look are needed before <see cref="Update"/> (the player was not on this plot).</summary>
    public bool Knows(Guid player, int plotX, int plotY) =>
        _spots.TryGetValue(player, out var spot) && spot.PlotX == plotX && spot.PlotY == plotY;

    /// <summary>Puts the player at a position on a plot (and off any other plot).</summary>
    public void Update(Guid player, int plotX, int plotY, double x, double y, string? facing, bool walking, CharacterLook? look = null)
    {
        x = Math.Clamp(double.IsFinite(x) ? x : 0, 0, PlotLayout.Size);
        y = Math.Clamp(double.IsFinite(y) ? y : 0, 0, PlotLayout.Size);
        facing = Facings.Contains(facing) ? facing! : "down";
        var now = time.GetUtcNow();
        _spots.AddOrUpdate(player,
            _ => new Spot(plotX, plotY, look?.Name ?? "?", look?.Appearance ?? new { }, x, y, facing, walking, now),
            (_, old) => old with
            {
                PlotX = plotX,
                PlotY = plotY,
                Name = look?.Name ?? old.Name,
                Appearance = look?.Appearance ?? old.Appearance,
                X = x,
                Y = y,
                Facing = facing,
                Walking = walking,
                Seen = now,
            });
    }

    public void Leave(Guid player) => _spots.TryRemove(player, out _);

    /// <summary>The players on a plot other than <paramref name="viewer"/>, as the client draws them.</summary>
    public IReadOnlyList<object> Others(Guid viewer, int plotX, int plotY)
    {
        var now = time.GetUtcNow();
        var others = new List<object>();
        foreach (var (player, spot) in _spots)
        {
            if (now - spot.Seen > Timeout)
            {
                _spots.TryRemove(new KeyValuePair<Guid, Spot>(player, spot));
                continue;
            }

            if (player != viewer && spot.PlotX == plotX && spot.PlotY == plotY)
            {
                others.Add(new
                {
                    id = player,
                    name = spot.Name,
                    appearance = spot.Appearance,
                    x = Math.Round(spot.X, 3),
                    y = Math.Round(spot.Y, 3),
                    facing = spot.Facing,
                    walking = spot.Walking,
                });
            }
        }

        return others;
    }
}

public sealed record PresenceRequest(int X, int Y, double PosX, double PosY, string? Facing, bool Walking);

/// <summary>Where the player stands on the plot they are in; answers with the other players there.</summary>
public sealed class PresenceHandler(IServiceScopeFactory scopes, PlotPresence presence, TimeProvider time) : IMessageHandler
{
    /// <summary>The plot this connection may be seen on, and when its rights there were last checked.</summary>
    private const string Allowed = "world.presence";

    /// <summary>A player taken out of a company stops being seen on its plots within this long.</summary>
    private static readonly TimeSpan Recheck = TimeSpan.FromSeconds(30);

    public string Type => "plot.presence";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<PresenceRequest>(payload);
        var player = client.RequireAccount();
        var now = time.GetUtcNow();
        if (client.Items.GetValueOrDefault(Allowed) is not ValueTuple<int, int, DateTimeOffset> allowed
            || allowed.Item1 != request.X || allowed.Item2 != request.Y || now - allowed.Item3 > Recheck)
        {
            await using var scope = scopes.CreateAsyncScope();
            try
            {
                await scope.ServiceProvider.GetRequiredService<PlotService>()
                    .RequireOwnerAsync(player, request.X, request.Y, cancellationToken, PlotRight.Work);
            }
            catch (GameException)
            {
                client.Items.Remove(Allowed);
                presence.Leave(player);
                throw;
            }

            client.Items[Allowed] = (request.X, request.Y, now);
        }

        CharacterLook? look = null;
        if (!presence.Knows(player, request.X, request.Y))
        {
            await using var scope = scopes.CreateAsyncScope();
            var looks = await scope.ServiceProvider.GetRequiredService<ICharacterLooks>().LooksAsync([player], cancellationToken);
            look = looks.GetValueOrDefault(player);
        }

        presence.Update(player, request.X, request.Y, request.PosX, request.PosY, request.Facing, request.Walking, look);
        return new Reply("plot.presence", new { players = presence.Others(player, request.X, request.Y) });
    }
}

/// <summary>The player walked off the plot: the others stop seeing them at once.</summary>
public sealed class LeavePlotHandler(PlotPresence presence) : IMessageHandler
{
    public string Type => "plot.leave";

    public Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        presence.Leave(client.RequireAccount());
        return Task.FromResult(new Reply("plot.left"));
    }
}
