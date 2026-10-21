using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.World;

/// <summary>How much oil or gas lies under a plot. Sent to the client, so never renumber.</summary>
public enum DepositSize : short
{
    None = 0,
    Small = 1,
    Medium = 2,
    Large = 3,
}

public sealed record Survey(DepositSize Oil, DepositSize Gas);

/// <summary>
/// Oil and gas under the plots. Nobody sees them on the map: only the owner of a plot can order a
/// geological survey, which reveals what lies under it. Deposits are fixed by the plot's position
/// and only the server knows the formula.
/// </summary>
public static class Deposits
{
    public const long SurveyPriceCents = 5_000_00;

    public const int XpPerSurvey = 50;

    /// <summary>Chance (per mille) of an oil and of a gas deposit, by biome.</summary>
    private static readonly IReadOnlyDictionary<Biome, (int Oil, int Gas)> Chance = new Dictionary<Biome, (int, int)>
    {
        [Biome.Forest] = (60, 80),
        [Biome.Farmland] = (80, 100),
        [Biome.Grassland] = (120, 120),
        [Biome.Desert] = (250, 200),
        [Biome.Mountains] = (40, 60),
        [Biome.Tundra] = (300, 300),
        [Biome.Ice] = (150, 200),
        [Biome.City] = (50, 50),
        [Biome.Coast] = (200, 150),
        [Biome.Lakeshore] = (60, 80),
    };

    public static Survey Under(int x, int y, Biome biome)
    {
        var (oil, gas) = Chance.GetValueOrDefault(biome);
        return new Survey(Roll(x, y, 0x0111u, oil), Roll(x, y, 0x6a50u, gas));
    }

    private static DepositSize Roll(int x, int y, uint salt, int chance)
    {
        var h = Hash((uint)x * 0x9e3779b1u ^ (uint)y * 0x85ebca77u ^ salt * 0xc2b2ae3du);
        if (h % 1000 >= chance)
        {
            return DepositSize.None;
        }

        // Of the deposits found, most are small and few are large.
        return ((h >> 10) % 10) switch
        {
            < 6 => DepositSize.Small,
            < 9 => DepositSize.Medium,
            _ => DepositSize.Large,
        };
    }

    private static uint Hash(uint h)
    {
        h ^= h >> 16;
        h *= 0x7feb352du;
        h ^= h >> 15;
        h *= 0x846ca68bu;
        return h ^ (h >> 16);
    }
}

public sealed record SurveyResult(Survey Survey, long BalanceCents);

public sealed class SurveyService(GameDb db, PlotService plots, IWallet wallet, ICharacterProgress progress, TimeProvider time)
{
    /// <summary>The survey the plot's owner ordered, or null.</summary>
    public async Task<Survey?> FindAsync(int x, int y, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync("SELECT oil, gas FROM world.surveys WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken) ? new Survey((DepositSize)reader.GetInt16(0), (DepositSize)reader.GetInt16(1)) : null;
    }

    /// <summary>Pays for a geological survey of one of the player's plots; a plot is surveyed once.</summary>
    public Task<SurveyResult> OrderAsync(Guid player, int x, int y, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var biome = await plots.RequireOwnerAsync(player, x, y, cancellationToken);
            var survey = Deposits.Under(x, y, biome);
            await using (var insert = await db.CommandAsync(
                "INSERT INTO world.surveys (x, y, oil, gas, surveyed_at) VALUES (@x, @y, @oil, @gas, @at) ON CONFLICT DO NOTHING", cancellationToken))
            {
                insert.Parameters.AddWithValue("x", x);
                insert.Parameters.AddWithValue("y", y);
                insert.Parameters.AddWithValue("oil", (short)survey.Oil);
                insert.Parameters.AddWithValue("gas", (short)survey.Gas);
                insert.Parameters.AddWithValue("at", time.GetUtcNow());
                if (await insert.ExecuteNonQueryAsync(cancellationToken) == 0)
                {
                    throw new GameException("already_surveyed", "This plot has been surveyed already.");
                }
            }

            var balance = await wallet.DebitAsync(player, Deposits.SurveyPriceCents, $"survey {x}:{y}", cancellationToken);
            await progress.AddXpAsync(player, Deposits.XpPerSurvey, cancellationToken);
            return new SurveyResult(survey, balance);
        }, cancellationToken);
}

public sealed class SurveyHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "world.survey";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<PlotRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var result = await scope.ServiceProvider.GetRequiredService<SurveyService>().OrderAsync(client.RequireAccount(), request.X, request.Y, cancellationToken);
        return new Reply("world.surveyed", new
        {
            x = request.X,
            y = request.Y,
            survey = SurveyJson(result.Survey),
            balanceCents = result.BalanceCents,
        });
    }

    public static object SurveyJson(Survey survey) => new { oil = (int)survey.Oil, gas = (int)survey.Gas };
}
