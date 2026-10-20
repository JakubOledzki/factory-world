using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
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

    protected override void ConfigureWebHost(IWebHostBuilder builder) =>
        builder.UseSetting("ConnectionStrings:Game",
            new NpgsqlConnectionStringBuilder(_admin) { Database = _database }.ConnectionString);

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

    public void Dispose() => socket.Dispose();
}

public static class ReplyExtensions
{
    public static string? Type(this JsonElement reply) => reply.GetProperty("type").GetString();

    public static JsonElement Payload(this JsonElement reply) => reply.GetProperty("payload");

    public static string? ErrorCode(this JsonElement reply) =>
        reply.Type() == "error" ? reply.Payload().GetProperty("code").GetString() : null;
}
