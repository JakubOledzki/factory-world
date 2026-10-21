using Npgsql;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Accounts;
using FactoryWorld.Modules.Characters;
using FactoryWorld.Modules.Crafting;
using FactoryWorld.Modules.Inventory;
using FactoryWorld.Modules.Market;
using FactoryWorld.Modules.Recycling;
using FactoryWorld.Modules.Session;
using FactoryWorld.Modules.Wallet;
using FactoryWorld.Modules.World;
using FactoryWorld.Server;

var builder = WebApplication.CreateBuilder(args);

// Every module of the modular monolith is listed here, in one place.
IGameModule[] modules =
[
    new SessionModule(),
    new AccountsModule(),
    new CharactersModule(),
    new InventoryModule(),
    new WalletModule(),
    new MarketModule(),
    new RecyclingModule(),
    new WorldModule(),
    new CraftingModule(),
];

foreach (var module in modules)
{
    module.RegisterServices(builder.Services, builder.Configuration);
}

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<MessageDispatcher>();
builder.Services.AddCors(options => options.AddDefaultPolicy(policy =>
    policy.WithOrigins(builder.Configuration.GetSection("Cors:Origins").Get<string[]>() ?? [])
        .AllowAnyHeader()
        .AllowAnyMethod()));

var connectionString = builder.Configuration.GetConnectionString("Game");
if (string.IsNullOrWhiteSpace(connectionString))
{
    throw new InvalidOperationException("Set the ConnectionStrings:Game setting to a PostgreSQL connection string.");
}

builder.Services.AddHealthChecks().AddNpgSql(connectionString, name: "postgres");
builder.Services.AddSingleton(NpgsqlDataSource.Create(connectionString));
builder.Services.AddScoped<GameDb>();

var app = builder.Build();

foreach (var module in modules)
{
    await module.InitializeAsync(app.Services, app.Lifetime.ApplicationStopping);
}

app.UseCors();
app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = TimeSpan.FromSeconds(30) });

app.MapHealthChecks("/health");
app.MapGet("/", () => Results.Text("Factory World server"));
app.Map("/ws", GameSocketEndpoint.HandleAsync);

foreach (var module in modules)
{
    module.MapEndpoints(app);
}

app.Run();

// Exposed for WebApplicationFactory in tests.
public partial class Program;
