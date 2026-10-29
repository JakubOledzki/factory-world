using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;

namespace FactoryWorld.Modules.World;

/// <summary>Until when a player has paid the tax on their plots. One row per player, made the first time it is looked at.</summary>
public sealed class PlotTaxRow
{
    public Guid OwnerId { get; set; }

    public DateTimeOffset PaidUntil { get; set; }
}

public static class PlotTaxRules
{
    /// <summary>Every plot but the first one bought costs this many thousandths of its price a day.</summary>
    public const int PerMillePerDay = 5;

    public static readonly TimeSpan Day = TimeSpan.FromDays(1);

    /// <summary>The tax a day on plots that cost <paramref name="taxedCents"/> together.</summary>
    public static long DailyCents(long taxedCents) => taxedCents * PerMillePerDay / 1000;
}

/// <param name="DailyCents">What the player's plots cost a day now.</param>
/// <param name="PaidUntil">The tax is paid up to here; whole days after it are owed.</param>
/// <param name="DaysOwed">Whole days the player had no money for; while any are owed, nothing can be built on their plots.</param>
public sealed record PlotTax(long DailyCents, DateTimeOffset PaidUntil, int DaysOwed)
{
    public long OwedCents => DailyCents * DaysOwed;

    public bool Due => DaysOwed > 0;
}

/// <summary>
/// The daily tax on plots. Nothing runs in the background: whenever a player's plot is entered or built on, or they open
/// the map or buy a plot, the whole days since <see cref="PlotTaxRow.PaidUntil"/> are paid from their wallet, as many as it covers.
/// </summary>
public sealed class PlotTaxService(GameDb db, IWallet wallet, TimeProvider time)
{
    public Task<PlotTax> SettleAsync(Guid owner, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var now = time.GetUtcNow();
            DateTimeOffset paidUntil;
            // Created on the first look, so the tax counts from then on; locked, so two requests at once pay a day once.
            await using (var create = await db.CommandAsync(
                "INSERT INTO world.plot_taxes (owner_id, paid_until) VALUES (@owner, @now) ON CONFLICT DO NOTHING", cancellationToken))
            {
                create.Parameters.AddWithValue("owner", owner);
                create.Parameters.AddWithValue("now", now);
                await create.ExecuteNonQueryAsync(cancellationToken);
            }

            await using (var row = await db.CommandAsync("SELECT paid_until FROM world.plot_taxes WHERE owner_id = @owner FOR UPDATE", cancellationToken))
            {
                row.Parameters.AddWithValue("owner", owner);
                await using var reader = await row.ExecuteReaderAsync(cancellationToken);
                await reader.ReadAsync(cancellationToken);
                paidUntil = reader.GetFieldValue<DateTimeOffset>(0);
            }

            var daily = PlotTaxRules.DailyCents(await TaxedCentsAsync(owner, cancellationToken));
            var days = (int)Math.Min(int.MaxValue, Math.Max(0, (now - paidUntil).Ticks / PlotTaxRules.Day.Ticks));
            if (days == 0)
            {
                return new PlotTax(daily, paidUntil, 0);
            }

            var paid = daily == 0 ? days : (int)Math.Min(days, await wallet.BalanceAsync(owner, cancellationToken) / daily);
            if (paid > 0 && daily > 0)
            {
                await wallet.DebitAsync(owner, paid * daily, $"plot tax {paid} days", cancellationToken);
            }

            paidUntil += PlotTaxRules.Day * paid;
            await using (var update = await db.CommandAsync("UPDATE world.plot_taxes SET paid_until = @until WHERE owner_id = @owner", cancellationToken))
            {
                update.Parameters.AddWithValue("owner", owner);
                update.Parameters.AddWithValue("until", paidUntil);
                await update.ExecuteNonQueryAsync(cancellationToken);
            }

            return new PlotTax(daily, paidUntil, days - paid);
        }, cancellationToken);

    /// <summary>Settles the tax of the owner of plot <paramref name="x"/>, <paramref name="y"/>, if somebody owns it.</summary>
    public async Task<PlotTax?> SettlePlotAsync(int x, int y, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync("SELECT owner_id FROM world.plots WHERE x = @x AND y = @y", cancellationToken);
        command.Parameters.AddWithValue("x", x);
        command.Parameters.AddWithValue("y", y);
        return await command.ExecuteScalarAsync(cancellationToken) is Guid owner ? await SettleAsync(owner, cancellationToken) : null;
    }

    /// <summary>Fails with <c>plot_tax_due</c> while the owner of the plot owes the tax.</summary>
    public async Task RequirePaidAsync(int x, int y, CancellationToken cancellationToken)
    {
        if (await SettlePlotAsync(x, y, cancellationToken) is { Due: true } tax)
        {
            throw Due(tax);
        }
    }

    public static GameException Due(PlotTax tax) =>
        new("plot_tax_due", $"The plot tax of {tax.OwedCents / 100.0:0.00} $ is due; nothing can be built until it is paid.");

    /// <summary>What the player paid for their plots, all but the first one they bought.</summary>
    private async Task<long> TaxedCentsAsync(Guid owner, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """
            SELECT COALESCE(SUM(price_cents), 0)::bigint FROM (
                SELECT price_cents FROM world.plots WHERE owner_id = @owner ORDER BY bought_at, x, y OFFSET 1) taxed
            """, cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        return (long)(await command.ExecuteScalarAsync(cancellationToken))!;
    }
}
