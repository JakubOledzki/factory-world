using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Bots;

/// <summary>Why a bot asks players for help.</summary>
public static class HelpReasons
{
    /// <summary>Its production line stands still although it has everything it needs: a player sets it going again.</summary>
    public const string Stalled = "stalled";

    /// <summary>It lacks parts or fuel for its line that it cannot make or buy: a player brings them.</summary>
    public const string Parts = "parts";
}

/// <summary>
/// A bot's call for help, shown as an exclamation mark over its plot on the world map. Whoever helps gets
/// <see cref="PayCents"/> from the bot's wallet: what the parts are worth at the trader and a little more, or the
/// <see cref="BotRules.HelpFee"/> for setting a stalled line going.
/// </summary>
public sealed record HelpRequest(
    string Bot, string Character, Guid Account, int X, int Y, string Reason,
    IReadOnlyList<(string Item, long Quantity)> Needs, long PayCents, DateTimeOffset Since);

/// <summary>
/// The bots' calls for help, in memory: a bot puts one up when its line does not work, a player answers it, and the
/// bot sees the answer on its next step. After a restart the bots find out again what they need.
/// </summary>
public sealed class BotHelpBoard
{
    private readonly object _lock = new();
    private readonly Dictionary<(int X, int Y), HelpRequest> _open = [];
    private readonly Dictionary<string, HelpRequest> _answered = new(StringComparer.Ordinal);

    public IReadOnlyList<HelpRequest> Open()
    {
        lock (_lock)
        {
            return _open.Values.OrderBy(r => r.Since).ToList();
        }
    }

    /// <summary>Puts the bot's call up, in place of any it had.</summary>
    public void Post(HelpRequest request)
    {
        lock (_lock)
        {
            Remove(request.Bot);
            _open[(request.X, request.Y)] = request;
        }
    }

    /// <summary>Takes the bot's call down: it managed without help.</summary>
    public void Withdraw(string bot)
    {
        lock (_lock)
        {
            Remove(bot);
        }
    }

    /// <summary>Takes the call on a plot off the board for a player who answers it, so that no one else can.</summary>
    public HelpRequest? Take(int x, int y)
    {
        lock (_lock)
        {
            return _open.Remove((x, y), out var request) ? request : null;
        }
    }

    /// <summary>Puts a call back whose answer failed.</summary>
    public void Restore(HelpRequest request)
    {
        lock (_lock)
        {
            _open.TryAdd((request.X, request.Y), request);
        }
    }

    public void Answered(HelpRequest request)
    {
        lock (_lock)
        {
            _answered[request.Bot] = request;
        }
    }

    /// <summary>The help the bot got since it last looked, if any.</summary>
    public HelpRequest? TakeAnswer(string bot)
    {
        lock (_lock)
        {
            return _answered.Remove(bot, out var request) ? request : null;
        }
    }

    private void Remove(string bot)
    {
        foreach (var key in _open.Where(p => p.Value.Bot == bot).Select(p => p.Key).ToList())
        {
            _open.Remove(key);
        }
    }

    public static object Json(HelpRequest r) => new
    {
        x = r.X,
        y = r.Y,
        bot = r.Character,
        reason = r.Reason,
        needs = r.Needs.Select(n => new { id = n.Item, name = Items.Names.GetValueOrDefault(n.Item, n.Item), quantity = n.Quantity }),
        payCents = r.PayCents,
        sinceMs = r.Since.ToUnixTimeMilliseconds(),
    };
}

/// <summary>Every bot that asks for help now, for the exclamation marks on the world map.</summary>
public sealed class HelpWantedHandler(BotHelpBoard board) : IMessageHandler
{
    public string Type => "bots.helpWanted";

    public Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        client.RequireAccount();
        return Task.FromResult(new Reply("bots.helpWanted", new { requests = board.Open().Select(BotHelpBoard.Json) }));
    }
}

public sealed record HelpBotRequest(int X, int Y);

/// <summary>
/// A player helps the bot on a plot: the parts it asked for go from the player's inventory to the bot's, and the bot
/// pays the player, all in one transaction. Help with a stalled line takes no parts; the bot sets its line up anew
/// on its next step. Money only moves from the bot to the player, so helping makes none.
/// </summary>
public sealed class HelpBotHandler(IServiceScopeFactory scopes, BotHelpBoard board) : IMessageHandler
{
    public string Type => "bots.help";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var player = client.RequireAccount();
        var request = Payload.Read<HelpBotRequest>(payload);
        if (board.Take(request.X, request.Y) is not { } help)
        {
            throw new GameException("no_help_needed", "Nobody asks for help on this plot.");
        }

        if (help.Account == player)
        {
            board.Restore(help);
            throw new GameException("no_help_needed", "You cannot help yourself.");
        }

        await using var scope = scopes.CreateAsyncScope();
        var services = scope.ServiceProvider;
        long balance;
        try
        {
            balance = await services.GetRequiredService<GameDb>().InTransactionAsync(async () =>
            {
                var inventory = services.GetRequiredService<IInventory>();
                foreach (var (item, quantity) in help.Needs)
                {
                    await inventory.RemoveAsync(player, item, quantity, cancellationToken);
                    await inventory.AddAsync(help.Account, item, quantity, cancellationToken);
                }

                var wallet = services.GetRequiredService<IWallet>();
                try
                {
                    await wallet.DebitAsync(help.Account, help.PayCents, $"help paid by bot at {help.X}:{help.Y}", cancellationToken);
                }
                catch (GameException ex) when (ex.Code == "not_enough_money")
                {
                    throw new GameException("bot_cannot_pay", "The bot has no money left to pay for help.");
                }

                return await wallet.CreditAsync(player, help.PayCents, $"help to bot {help.Character}", cancellationToken);
            }, cancellationToken);
        }
        catch
        {
            board.Restore(help);
            throw;
        }

        board.Answered(help);
        return new Reply("bots.helped", new { x = help.X, y = help.Y, bot = help.Character, payCents = help.PayCents, balanceCents = balance });
    }
}
