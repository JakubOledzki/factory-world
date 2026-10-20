namespace FactoryWorld.Server.Tests;

public sealed class AccountTests(ServerFactory factory) : IClassFixture<ServerFactory>
{
    [Fact]
    public async Task Register_logs_in_and_token_resumes_on_a_new_connection()
    {
        string token;
        using (var first = await factory.ConnectAsync())
        {
            token = await first.RegisterAsync();
        }

        using var second = await factory.ConnectAsync();
        var resumed = await second.SendAsync("auth.resume", new { token });

        Assert.Equal("auth.ok", resumed.Type());
        Assert.Equal("character.none", (await second.SendAsync("character.get")).Type());
    }

    [Fact]
    public async Task Login_works_with_any_email_casing()
    {
        var email = $"{Guid.NewGuid():N}@example.com";
        using (var first = await factory.ConnectAsync())
        {
            await first.RegisterAsync(email);
        }

        using var second = await factory.ConnectAsync();
        var reply = await second.SendAsync("auth.login", new { email = email.ToUpperInvariant(), password = "secret-password" });

        Assert.Equal("auth.ok", reply.Type());
    }

    [Fact]
    public async Task Same_email_cannot_register_twice()
    {
        var email = $"{Guid.NewGuid():N}@example.com";
        using var client = await factory.ConnectAsync();
        await client.RegisterAsync(email);

        var reply = await client.SendAsync("auth.register", new { email, password = "another-password" });

        Assert.Equal("email_taken", reply.ErrorCode());
    }

    [Theory]
    [InlineData("not-an-email", "secret-password", "invalid_email")]
    [InlineData("a@b", "secret-password", "invalid_email")]
    [InlineData("ok@example.com", "short", "weak_password")]
    public async Task Register_validates_input(string email, string password, string code)
    {
        using var client = await factory.ConnectAsync();

        var reply = await client.SendAsync("auth.register", new { email, password });

        Assert.Equal(code, reply.ErrorCode());
    }

    [Fact]
    public async Task Wrong_password_and_unknown_email_get_the_same_error()
    {
        var email = $"{Guid.NewGuid():N}@example.com";
        using var client = await factory.ConnectAsync();
        await client.RegisterAsync(email);

        using var other = await factory.ConnectAsync();
        var wrongPassword = await other.SendAsync("auth.login", new { email, password = "wrong-password" });
        var unknownEmail = await other.SendAsync("auth.login", new { email = "nobody@example.com", password = "secret-password" });

        Assert.Equal("invalid_credentials", wrongPassword.ErrorCode());
        Assert.Equal("invalid_credentials", unknownEmail.ErrorCode());
    }

    [Fact]
    public async Task Too_many_failed_logins_lock_the_connection()
    {
        using var client = await factory.ConnectAsync();
        for (var i = 0; i < 5; i++)
        {
            await client.SendAsync("auth.login", new { email = "nobody@example.com", password = "wrong-password" });
        }

        var reply = await client.SendAsync("auth.login", new { email = "nobody@example.com", password = "wrong-password" });

        Assert.Equal("too_many_attempts", reply.ErrorCode());
    }

    [Fact]
    public async Task Logout_invalidates_the_token()
    {
        using var client = await factory.ConnectAsync();
        var token = await client.RegisterAsync();

        Assert.Equal("auth.loggedOut", (await client.SendAsync("auth.logout", new { token })).Type());
        Assert.Equal("not_logged_in", (await client.SendAsync("character.get")).ErrorCode());

        using var other = await factory.ConnectAsync();
        Assert.Equal("session_expired", (await other.SendAsync("auth.resume", new { token })).ErrorCode());
    }
}
