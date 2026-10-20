using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;

namespace FactoryWorld.Server.Tests;

public sealed class GameSocketTests(GameSocketTests.ServerFactory factory) : IClassFixture<GameSocketTests.ServerFactory>
{
    /// <summary>The server without a database, so tests run anywhere.</summary>
    public sealed class ServerFactory : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(Microsoft.AspNetCore.Hosting.IWebHostBuilder builder) =>
            builder.UseSetting("ConnectionStrings:Game", "");
    }

    [Fact]
    public async Task Health_is_ok()
    {
        var response = await factory.CreateClient().GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Hello_with_current_protocol_gets_welcome()
    {
        using var socket = await ConnectAsync();

        var reply = await RoundTripAsync(socket, """{"type":"hello","id":"1","payload":{"protocol":1}}""");

        Assert.Equal("welcome", reply.GetProperty("type").GetString());
        Assert.Equal("1", reply.GetProperty("id").GetString());
        Assert.Equal(1, reply.GetProperty("payload").GetProperty("protocol").GetInt32());
    }

    [Fact]
    public async Task Hello_with_old_protocol_is_rejected()
    {
        using var socket = await ConnectAsync();

        var reply = await RoundTripAsync(socket, """{"type":"hello","id":"1","payload":{"protocol":0}}""");

        Assert.Equal("error", reply.GetProperty("type").GetString());
        Assert.Equal("protocol_mismatch", reply.GetProperty("payload").GetProperty("code").GetString());
    }

    [Fact]
    public async Task Ping_gets_pong_with_server_time()
    {
        using var socket = await ConnectAsync();

        var reply = await RoundTripAsync(socket, """{"type":"ping","id":"7"}""");

        Assert.Equal("pong", reply.GetProperty("type").GetString());
        Assert.Equal("7", reply.GetProperty("id").GetString());
        Assert.True(reply.GetProperty("payload").TryGetProperty("serverTime", out _));
    }

    [Theory]
    [InlineData("not json", "bad_json")]
    [InlineData("""{"id":"1"}""", "bad_envelope")]
    [InlineData("""{"type":"teleport","id":"1"}""", "unknown_type")]
    public async Task Bad_messages_get_an_error_and_keep_the_connection(string frame, string code)
    {
        using var socket = await ConnectAsync();

        var reply = await RoundTripAsync(socket, frame);
        Assert.Equal(code, reply.GetProperty("payload").GetProperty("code").GetString());

        var pong = await RoundTripAsync(socket, """{"type":"ping"}""");
        Assert.Equal("pong", pong.GetProperty("type").GetString());
    }

    private Task<WebSocket> ConnectAsync() =>
        factory.Server.CreateWebSocketClient().ConnectAsync(new Uri(factory.Server.BaseAddress, "ws"), CancellationToken.None);

    private static async Task<JsonElement> RoundTripAsync(WebSocket socket, string frame)
    {
        await socket.SendAsync(Encoding.UTF8.GetBytes(frame), WebSocketMessageType.Text, true, CancellationToken.None);

        var buffer = new byte[16 * 1024];
        var result = await socket.ReceiveAsync(buffer, CancellationToken.None);
        Assert.True(result.EndOfMessage);
        return JsonDocument.Parse(buffer.AsMemory(0, result.Count)).RootElement.Clone();
    }
}
