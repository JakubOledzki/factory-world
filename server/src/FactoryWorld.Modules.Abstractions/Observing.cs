using System.Text.Json;

namespace FactoryWorld.Modules.Abstractions;

/// <summary>A request that a handler answered without an error, as the player sent it and as it was answered.</summary>
public sealed record HandledMessage(string Type, JsonElement? Request, string ReplyType, JsonElement Reply);

/// <summary>
/// Sees every request that succeeded, after its reply is ready, e.g. to count what players do for
/// achievements. Modules register observers as <c>services.AddSingleton&lt;IMessageObserver, MyObserver&gt;()</c>.
/// An observer that fails is logged and the player still gets the reply.
/// </summary>
public interface IMessageObserver
{
    Task OnHandledAsync(HandledMessage message, ClientContext client, CancellationToken cancellationToken);
}
