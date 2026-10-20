using FactoryWorld.Modules.Abstractions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Characters;

/// <summary>The player's character: name, look, level and XP. Owns the <c>characters</c> schema.</summary>
public sealed class CharactersModule : IGameModule
{
    public string Name => "Characters";

    public void RegisterServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddDbContext<CharactersDbContext>(options => options.UseNpgsql(
            configuration.GetConnectionString("Game"),
            npgsql => npgsql.MigrationsHistoryTable("__migrations", CharactersDbContext.Schema)));
        services.AddScoped<CharacterService>();
        services.AddSingleton<IMessageHandler, OptionsHandler>();
        services.AddSingleton<IMessageHandler, GetCharacterHandler>();
        services.AddSingleton<IMessageHandler, CreateCharacterHandler>();
    }

    public async Task InitializeAsync(IServiceProvider services, CancellationToken cancellationToken)
    {
        await using var scope = services.CreateAsyncScope();
        await scope.ServiceProvider.GetRequiredService<CharactersDbContext>().Database.MigrateAsync(cancellationToken);
    }
}
