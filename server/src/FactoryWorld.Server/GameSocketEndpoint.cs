using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using FactoryWorld.Modules.Abstractions;

namespace FactoryWorld.Server;

/// <summary>One WebSocket per player. Requests are handled in order, one at a time; each reply may be
/// followed by messages from <see cref="ClientContext.Outbox"/>, which have no id.</summary>
public static class GameSocketEndpoint
{
    private const int MaxMessageBytes = 64 * 1024;

    public static async Task HandleAsync(HttpContext context, MessageDispatcher dispatcher, ILogger<MessageDispatcher> logger)
    {
        if (!context.WebSockets.IsWebSocketRequest)
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            return;
        }

        using var socket = await context.WebSockets.AcceptWebSocketAsync();
        var client = new ClientContext { ConnectionId = Guid.NewGuid() };
        var cancellationToken = context.RequestAborted;
        logger.LogInformation("Client {ConnectionId} connected", client.ConnectionId);

        try
        {
            while (socket.State == WebSocketState.Open)
            {
                var frame = await ReceiveTextAsync(socket, cancellationToken);
                if (frame is null)
                {
                    break;
                }

                var reply = await dispatcher.DispatchAsync(frame, client, cancellationToken);
                var bytes = JsonSerializer.SerializeToUtf8Bytes(reply, MessageDispatcher.Json);
                await socket.SendAsync(bytes, WebSocketMessageType.Text, endOfMessage: true, cancellationToken);
                while (client.Outbox.TryDequeue(out var notice))
                {
                    bytes = JsonSerializer.SerializeToUtf8Bytes(notice, MessageDispatcher.Json);
                    await socket.SendAsync(bytes, WebSocketMessageType.Text, endOfMessage: true, cancellationToken);
                }
            }
        }
        catch (Exception ex) when (ex is OperationCanceledException or WebSocketException)
        {
            // The client went away; nothing to clean up yet.
        }

        if (socket.State is WebSocketState.Open or WebSocketState.CloseReceived)
        {
            await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, null, CancellationToken.None);
        }

        logger.LogInformation("Client {ConnectionId} disconnected", client.ConnectionId);
    }

    /// <summary>Reads one whole text message, or returns null when the client closes.</summary>
    private static async Task<string?> ReceiveTextAsync(WebSocket socket, CancellationToken cancellationToken)
    {
        var buffer = new byte[4096];
        using var message = new MemoryStream();

        while (true)
        {
            var result = await socket.ReceiveAsync(buffer, cancellationToken);
            if (result.MessageType == WebSocketMessageType.Close)
            {
                return null;
            }

            message.Write(buffer, 0, result.Count);
            if (message.Length > MaxMessageBytes)
            {
                await socket.CloseAsync(WebSocketCloseStatus.MessageTooBig, "Message too big", cancellationToken);
                return null;
            }

            if (result.EndOfMessage)
            {
                return Encoding.UTF8.GetString(message.GetBuffer(), 0, (int)message.Length);
            }
        }
    }
}
