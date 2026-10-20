using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Time.Testing;
using Npgsql;

namespace FactoryWorld.Server.Tests;

/// <summary>
/// The real server on a fresh PostgreSQL database that is dropped afterwards.
/// Point FW_TEST_DB at a server where the user may create databases (default: local docker-compose db).
/// </summary>
public sealed class ServerFactory : WebApplicationFactory<Program>
{
    private readonly string _admin =
        Environment.GetEnvironmentVariable("FW_TEST_DB")
        ?? "Host=localhost;Port=5432;Database=postgres;Username=factory;Password=factory";

    private readonly string _database = $"fw_test_{Guid.NewGuid():N}";

    /// <summary>The server's clock; tests move it forward instead of waiting.</summary>
    public FakeTimeProvider Time { get; } = new(DateTimeOffset.UtcNow);

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseSetting("ConnectionStrings:Game",
            new NpgsqlConnectionStringBuilder(_admin) { Database = _database }.ConnectionString);
        builder.ConfigureTestServices(services => services.AddSingleton<TimeProvider>(Time));
    }

    public override async ValueTask DisposeAsync()
    {
        await base.DisposeAsync();
        NpgsqlConnection.ClearAllPools();
        await using var connection = new NpgsqlConnection(_admin);
        await connection.OpenAsync();
        await using var drop = new NpgsqlCommand($"DROP DATABASE IF EXISTS \"{_database}\" WITH (FORCE)", connection);
        await drop.ExecuteNonQueryAsync();
    }

    public async Task<GameClient> ConnectAsync()
    {
        var socket = await Server.CreateWebSocketClient().ConnectAsync(new Uri(Server.BaseAddress, "ws"), CancellationToken.None);
        return new GameClient(socket);
    }
}

/// <summary>A test player: sends one request and reads its reply.</summary>
public sealed class GameClient(WebSocket socket) : IDisposable
{
    private int _nextId;

    public async Task<JsonElement> SendRawAsync(string frame)
    {
        await socket.SendAsync(Encoding.UTF8.GetBytes(frame), WebSocketMessageType.Text, true, CancellationToken.None);

        var buffer = new byte[64 * 1024];
        var result = await socket.ReceiveAsync(buffer, CancellationToken.None);
        Assert.True(result.EndOfMessage);
        return JsonDocument.Parse(buffer.AsMemory(0, result.Count)).RootElement.Clone();
    }

    public Task<JsonElement> SendAsync(string type, object? payload = null) =>
        SendRawAsync(JsonSerializer.Serialize(new { type, id = (++_nextId).ToString(), payload }));

    /// <summary>Registers a new account with a unique e-mail and returns the session token.</summary>
    public async Task<string> RegisterAsync(string? email = null)
    {
        var reply = await SendAsync("auth.register", new { email = email ?? $"{Guid.NewGuid():N}@example.com", password = "secret-password" });
        Assert.Equal("auth.ok", reply.Type());
        return reply.Payload().GetProperty("token").GetString()!;
    }

    /// <summary>Registers and creates a character, so the player can earn XP.</summary>
    public async Task RegisterWithCharacterAsync()
    {
        await RegisterAsync();
        var look = new { skinTone = 0, hairStyle = 0, hairColor = 0, shirtStyle = 0, shirtColor = 0, pantsColor = 0, shoesColor = 0 };
        var reply = await SendAsync("character.create", new { name = "P" + Guid.NewGuid().ToString("N")[..10], appearance = look });
        Assert.Equal("character", reply.Type());
    }

    /// <summary>Item id → quantity from "inventory.get".</summary>
    public async Task<Dictionary<string, long>> InventoryAsync()
    {
        var reply = await SendAsync("inventory.get");
        return reply.Payload().GetProperty("items").EnumerateArray()
            .ToDictionary(i => i.GetProperty("id").GetString()!, i => i.GetProperty("quantity").GetInt64());
    }

    public async Task<long> BalanceAsync() =>
        (await SendAsync("wallet.get")).Payload().GetProperty("balanceCents").GetInt64();

    public void Dispose() => socket.Dispose();
}

public static class ReplyExtensions
{
    public static string? Type(this JsonElement reply) => reply.GetProperty("type").GetString();

    public static JsonElement Payload(this JsonElement reply) => reply.GetProperty("payload");

    public static string? ErrorCode(this JsonElement reply) =>
        reply.Type() == "error" ? reply.Payload().GetProperty("code").GetString() : null;
}
