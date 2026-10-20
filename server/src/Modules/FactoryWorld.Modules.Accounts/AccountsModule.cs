using FactoryWorld.Modules.Abstractions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Accounts;

/// <summary>Registration, login and sessions. Owns the <c>accounts</c> database schema.</summary>
public sealed class AccountsModule : IGameModule
{
    public string Name => "Accounts";

    public void RegisterServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddDbContext<AccountsDbContext>(options => options.UseNpgsql(
            configuration.GetConnectionString("Game"),
            npgsql => npgsql.MigrationsHistoryTable("__migrations", AccountsDbContext.Schema)));
        services.AddScoped<AccountService>();
        services.AddSingleton<IMessageHandler, RegisterHandler>();
        services.AddSingleton<IMessageHandler, LoginHandler>();
        services.AddSingleton<IMessageHandler, ResumeHandler>();
        services.AddSingleton<IMessageHandler, LogoutHandler>();
    }

    public async Task InitializeAsync(IServiceProvider services, CancellationToken cancellationToken)
    {
        await using var scope = services.CreateAsyncScope();
        await scope.ServiceProvider.GetRequiredService<AccountsDbContext>().Database.MigrateAsync(cancellationToken);
    }
}
