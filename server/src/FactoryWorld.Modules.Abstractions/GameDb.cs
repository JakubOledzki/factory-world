using System.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace FactoryWorld.Modules.Abstractions;

/// <summary>
/// One database connection per request, shared by every module's DbContext, so that an operation
/// spanning modules (e.g. selling: remove items, add money) commits or fails as a whole.
/// </summary>
public sealed class GameDb(NpgsqlDataSource dataSource) : IAsyncDisposable
{
    public NpgsqlConnection Connection { get; } = dataSource.CreateConnection();

    /// <summary>The transaction of <see cref="InTransactionAsync{T}"/>, if one is running.</summary>
    public NpgsqlTransaction? Transaction { get; private set; }

    /// <summary>Runs <paramref name="work"/> in one transaction; a nested call joins the outer one.</summary>
    public async Task<T> InTransactionAsync<T>(Func<Task<T>> work, CancellationToken cancellationToken)
    {
        if (Transaction is not null)
        {
            return await work();
        }

        await OpenAsync(cancellationToken);
        await using var transaction = await Connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);
        Transaction = transaction;
        try
        {
            var result = await work();
            await transaction.CommitAsync(cancellationToken);
            return result;
        }
        finally
        {
            Transaction = null;
        }
    }

    public Task InTransactionAsync(Func<Task> work, CancellationToken cancellationToken) =>
        InTransactionAsync(async () => { await work(); return true; }, cancellationToken);

    /// <summary>A raw SQL command on the shared connection, inside the current transaction if any.</summary>
    public async Task<NpgsqlCommand> CommandAsync(string sql, CancellationToken cancellationToken)
    {
        await OpenAsync(cancellationToken);
        return new NpgsqlCommand(sql, Connection, Transaction);
    }

    public async ValueTask DisposeAsync() => await Connection.DisposeAsync();

    private async Task OpenAsync(CancellationToken cancellationToken)
    {
        if (Connection.State != ConnectionState.Open)
        {
            await Connection.OpenAsync(cancellationToken);
        }
    }
}

/// <summary>Base for module DbContexts: saves inside the shared <see cref="GameDb"/> transaction when one is running.</summary>
public abstract class ModuleDbContext(DbContextOptions options, GameDb gameDb) : DbContext(options)
{
    public override async Task<int> SaveChangesAsync(bool acceptAllChangesOnSuccess, CancellationToken cancellationToken = default)
    {
        var current = Database.CurrentTransaction?.GetDbTransaction();
        if (current != gameDb.Transaction)
        {
            await Database.UseTransactionAsync(gameDb.Transaction, cancellationToken);
        }

        return await base.SaveChangesAsync(acceptAllChangesOnSuccess, cancellationToken);
    }
}

public static class ModuleDbContextRegistration
{
    /// <summary>Registers a module's DbContext on the shared connection, with migrations kept in the module's own schema.</summary>
    public static IServiceCollection AddModuleDbContext<TContext>(this IServiceCollection services, string schema)
        where TContext : ModuleDbContext =>
        services.AddDbContext<TContext>((provider, options) => options.UseNpgsql(
            provider.GetRequiredService<GameDb>().Connection,
            npgsql => npgsql.MigrationsHistoryTable("__migrations", schema)));

    /// <summary>Applies the module's pending migrations; call from <see cref="IGameModule.InitializeAsync"/>.</summary>
    public static async Task MigrateModuleAsync<TContext>(this IServiceProvider services, CancellationToken cancellationToken)
        where TContext : ModuleDbContext
    {
        await using var scope = services.CreateAsyncScope();
        await scope.ServiceProvider.GetRequiredService<TContext>().Database.MigrateAsync(cancellationToken);
    }
}
