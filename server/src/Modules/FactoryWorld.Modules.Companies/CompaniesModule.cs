using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Companies;

public sealed record NameRequest(string? Name);

public sealed record CompanyRequest(Guid Company);

public sealed record RoleRequest(string? Name, string? Role);

public sealed record CompanyPlotRequest(int X, int Y);

public sealed record WarehouseRequest(string? Item, long Quantity);

/// <summary>Every company message answers with the player's company as it is now.</summary>
public abstract class CompanyHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var view = await RunAsync(scope.ServiceProvider.GetRequiredService<CompanyService>(), client.RequireAccount(), payload, cancellationToken);
        return new Reply("company", Json(view));
    }

    protected abstract Task<CompanyView> RunAsync(CompanyService companies, Guid player, JsonElement? payload, CancellationToken cancellationToken);

    public static object Json(CompanyView view) => new
    {
        company = view.Company is { } c ? new
        {
            id = c.Id,
            name = c.Name,
            role = c.Role,
            rights = Roles.Rights(c.Role).Order().Select(r => r.ToString().ToLowerInvariant()),
            members = c.Members.Select(m => new
            {
                name = m.Name,
                role = m.Role,
                you = m.AccountId == view.Player,
                joinedAt = m.JoinedAt.ToUnixTimeMilliseconds(),
                plots = c.Plots.Count(p => p.OwnerId == m.AccountId),
            }),
            invited = c.Invited,
            plots = c.Plots.Select(p => new { x = p.X, y = p.Y, biome = p.Biome, owner = p.OwnerName, mine = p.OwnerId == view.Player }),
            warehouse = new
            {
                capacity = CompanyRules.WarehouseCapacity,
                stored = c.Warehouse.Values.Sum(),
                items = c.Warehouse.Select(i => new { id = i.Key, name = Items.Names.GetValueOrDefault(i.Key, i.Key), quantity = i.Value }),
            },
            log = c.Log.Select(l => new
            {
                at = l.At.ToUnixTimeMilliseconds(),
                who = l.Who,
                action = l.Action,
                item = l.Item,
                name = l.Item is { } item ? Items.Names.GetValueOrDefault(item) : null,
                quantity = l.Quantity,
                other = l.Other,
            }),
        } : null,
        invitations = view.Invitations.Select(i => new { company = i.CompanyId, name = i.CompanyName, members = i.Members }),
        maxMembers = CompanyRules.MaxMembers,
        roles = Roles.All,
    };
}

public sealed class GetCompanyHandler(IServiceScopeFactory scopes) : CompanyHandler(scopes)
{
    public override string Type => "company.get";

    protected override Task<CompanyView> RunAsync(CompanyService companies, Guid player, JsonElement? payload, CancellationToken cancellationToken) =>
        companies.ViewAsync(player, cancellationToken);
}

public sealed class CreateCompanyHandler(IServiceScopeFactory scopes) : CompanyHandler(scopes)
{
    public override string Type => "company.create";

    protected override Task<CompanyView> RunAsync(CompanyService companies, Guid player, JsonElement? payload, CancellationToken cancellationToken) =>
        companies.CreateAsync(player, Payload.Read<NameRequest>(payload).Name, cancellationToken);
}

public sealed class InviteHandler(IServiceScopeFactory scopes) : CompanyHandler(scopes)
{
    public override string Type => "company.invite";

    protected override Task<CompanyView> RunAsync(CompanyService companies, Guid player, JsonElement? payload, CancellationToken cancellationToken) =>
        companies.InviteAsync(player, Payload.Read<NameRequest>(payload).Name, cancellationToken);
}

public sealed class UninviteHandler(IServiceScopeFactory scopes) : CompanyHandler(scopes)
{
    public override string Type => "company.uninvite";

    protected override Task<CompanyView> RunAsync(CompanyService companies, Guid player, JsonElement? payload, CancellationToken cancellationToken) =>
        companies.UninviteAsync(player, Payload.Read<NameRequest>(payload).Name, cancellationToken);
}

public sealed class AcceptHandler(IServiceScopeFactory scopes) : CompanyHandler(scopes)
{
    public override string Type => "company.accept";

    protected override Task<CompanyView> RunAsync(CompanyService companies, Guid player, JsonElement? payload, CancellationToken cancellationToken) =>
        companies.AcceptAsync(player, Payload.Read<CompanyRequest>(payload).Company, cancellationToken);
}

public sealed class DeclineHandler(IServiceScopeFactory scopes) : CompanyHandler(scopes)
{
    public override string Type => "company.decline";

    protected override Task<CompanyView> RunAsync(CompanyService companies, Guid player, JsonElement? payload, CancellationToken cancellationToken) =>
        companies.DeclineAsync(player, Payload.Read<CompanyRequest>(payload).Company, cancellationToken);
}

public sealed class LeaveHandler(IServiceScopeFactory scopes) : CompanyHandler(scopes)
{
    public override string Type => "company.leave";

    protected override Task<CompanyView> RunAsync(CompanyService companies, Guid player, JsonElement? payload, CancellationToken cancellationToken) =>
        companies.LeaveAsync(player, cancellationToken);
}

public sealed class KickHandler(IServiceScopeFactory scopes) : CompanyHandler(scopes)
{
    public override string Type => "company.kick";

    protected override Task<CompanyView> RunAsync(CompanyService companies, Guid player, JsonElement? payload, CancellationToken cancellationToken) =>
        companies.KickAsync(player, Payload.Read<NameRequest>(payload).Name, cancellationToken);
}

public sealed class RoleHandler(IServiceScopeFactory scopes) : CompanyHandler(scopes)
{
    public override string Type => "company.role";

    protected override Task<CompanyView> RunAsync(CompanyService companies, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<RoleRequest>(payload);
        return companies.SetRoleAsync(player, request.Name, request.Role, cancellationToken);
    }
}

public sealed class AddPlotHandler(IServiceScopeFactory scopes) : CompanyHandler(scopes)
{
    public override string Type => "company.addPlot";

    protected override Task<CompanyView> RunAsync(CompanyService companies, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<CompanyPlotRequest>(payload);
        return companies.AddPlotAsync(player, request.X, request.Y, cancellationToken);
    }
}

public sealed class RemovePlotHandler(IServiceScopeFactory scopes) : CompanyHandler(scopes)
{
    public override string Type => "company.removePlot";

    protected override Task<CompanyView> RunAsync(CompanyService companies, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<CompanyPlotRequest>(payload);
        return companies.RemovePlotAsync(player, request.X, request.Y, cancellationToken);
    }
}

public sealed class PutHandler(IServiceScopeFactory scopes) : CompanyHandler(scopes)
{
    public override string Type => "company.put";

    protected override Task<CompanyView> RunAsync(CompanyService companies, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<WarehouseRequest>(payload);
        return companies.PutAsync(player, request.Item, request.Quantity, cancellationToken);
    }
}

public sealed class TakeHandler(IServiceScopeFactory scopes) : CompanyHandler(scopes)
{
    public override string Type => "company.take";

    protected override Task<CompanyView> RunAsync(CompanyService companies, Guid player, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<WarehouseRequest>(payload);
        return companies.TakeAsync(player, request.Item, request.Quantity, cancellationToken);
    }
}

/// <summary>Companies: players running plots together, with roles and a shared warehouse. Owns the <c>companies</c> schema.</summary>
public sealed class CompaniesModule : IGameModule
{
    public string Name => "Companies";

    public void RegisterServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddModuleDbContext<CompaniesDbContext>(CompaniesDbContext.Schema);
        services.AddScoped<CompanyService>();
        services.AddScoped<ICompanyPlots, CompanyPlots>();
        services.AddSingleton<IMessageHandler, GetCompanyHandler>();
        services.AddSingleton<IMessageHandler, CreateCompanyHandler>();
        services.AddSingleton<IMessageHandler, InviteHandler>();
        services.AddSingleton<IMessageHandler, UninviteHandler>();
        services.AddSingleton<IMessageHandler, AcceptHandler>();
        services.AddSingleton<IMessageHandler, DeclineHandler>();
        services.AddSingleton<IMessageHandler, LeaveHandler>();
        services.AddSingleton<IMessageHandler, KickHandler>();
        services.AddSingleton<IMessageHandler, RoleHandler>();
        services.AddSingleton<IMessageHandler, AddPlotHandler>();
        services.AddSingleton<IMessageHandler, RemovePlotHandler>();
        services.AddSingleton<IMessageHandler, PutHandler>();
        services.AddSingleton<IMessageHandler, TakeHandler>();
    }

    public Task InitializeAsync(IServiceProvider services, CancellationToken cancellationToken) =>
        services.MigrateModuleAsync<CompaniesDbContext>(cancellationToken);
}
