using System.Text.Json;

namespace FactoryWorld.Modules.Abstractions;

/// <summary>
/// Every WebSocket frame is one JSON envelope: { "type": "...", "id": "...", "payload": { ... } }.
/// The client sets <c>id</c> on requests; the server echoes it on the reply.
/// </summary>
public sealed record Envelope(string Type, string? Id = null, JsonElement? Payload = null);

/// <summary>What the server knows about the connection a message arrived on.</summary>
public sealed class ClientContext
{
    public required Guid ConnectionId { get; init; }
    public Guid? AccountId { get; set; }
}

/// <summary>A reply to a client request: a message type and an optional payload.</summary>
public sealed record Reply(string Type, object? Payload = null);

/// <summary>
/// Handles one client message type. Modules register handlers as
/// <c>services.AddSingleton&lt;IMessageHandler, MyHandler&gt;()</c>.
/// </summary>
public interface IMessageHandler
{
    string Type { get; }

    Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken);
}

/// <summary>A failure the client may show to the player, e.g. "not enough money".</summary>
public sealed class GameException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
