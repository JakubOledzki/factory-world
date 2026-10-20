using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Abstractions;

/// <summary>
/// A self-contained part of the game server (accounts, market, production...).
/// Modules talk to each other only through their public services, never through
/// each other's tables, so any of them can later be moved to its own service.
/// </summary>
public interface IGameModule
{
    string Name { get; }

    void RegisterServices(IServiceCollection services, IConfiguration configuration);

    /// <summary>Optional HTTP endpoints. Gameplay goes through the WebSocket instead.</summary>
    void MapEndpoints(IEndpointRouteBuilder endpoints) { }
}
