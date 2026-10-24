using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace FactoryWorld.Modules.Crafting;

/// <summary>Ore smelted into an ingot, one at a time.</summary>
public sealed record SmeltingRecipe(string Input, string Output, TimeSpan Time);

/// <summary>
/// A stone furnace, in the garage or on a plot, burns coal and smelts the ore put into it, one
/// piece after another, while the player is away too. One coal lasts for <see cref="SmeltsPerCoal"/>
/// smelts. It holds one kind of ore at a time; ingots wait in it until taken out.
/// </summary>
public static class Smelting
{
    public const int SmeltsPerCoal = 5;

    public const int MaxInput = 50;

    public const int MaxFuel = 50;

    /// <summary>Experience for each ingot taken out of the furnace.</summary>
    public const int XpPerIngot = 1;

    public static readonly IReadOnlyList<SmeltingRecipe> Recipes =
    [
        new(Items.IronOre, Items.IronIngot, TimeSpan.FromSeconds(10)),
        new(Items.CopperOre, Items.CopperIngot, TimeSpan.FromSeconds(10)),
        new(Items.TinOre, Items.TinIngot, TimeSpan.FromSeconds(10)),
        new(Items.SilverOre, Items.SilverIngot, TimeSpan.FromSeconds(15)),
        new(Items.GoldOre, Items.GoldIngot, TimeSpan.FromSeconds(20)),
    ];

    public static SmeltingRecipe? For(string? input) => Recipes.FirstOrDefault(r => r.Input == input);

    /// <summary>What the furnace holds after smelting until <paramref name="now"/>.</summary>
    public static FurnaceState Advance(FurnaceState s, DateTimeOffset now)
    {
        if (s.StartedAt is not { } started || For(s.Input) is not { } recipe)
        {
            return s with { StartedAt = null };
        }

        var possible = (int)Math.Min(int.MaxValue, Math.Max(0, (now - started).Ticks / recipe.Time.Ticks));
        var n = Math.Min(possible, Math.Min(s.InputQuantity, s.Heat + s.Fuel * SmeltsPerCoal));
        var coal = n > s.Heat ? (n - s.Heat + SmeltsPerCoal - 1) / SmeltsPerCoal : 0;
        var after = s with
        {
            InputQuantity = s.InputQuantity - n,
            Fuel = s.Fuel - coal,
            Heat = s.Heat + coal * SmeltsPerCoal - n,
            Output = n > 0 ? recipe.Output : s.Output,
            OutputQuantity = s.OutputQuantity + n,
        };
        if (after.InputQuantity == 0)
        {
            after = after with { Input = null };
        }

        return after.InputQuantity > 0 && after.Heat + after.Fuel > 0
            ? after with { StartedAt = started + recipe.Time * n }
            : after with { StartedAt = null };
    }

    /// <summary>Lights an idle furnace that has both ore and coal.</summary>
    public static FurnaceState Start(FurnaceState s, DateTimeOffset now) =>
        s.StartedAt is null && s.InputQuantity > 0 && s.Heat + s.Fuel > 0 ? s with { StartedAt = now } : s;
}

/// <param name="Heat">Smelts left from coal already burning.</param>
/// <param name="StartedAt">When the piece being smelted now went in; null while the furnace is cold.</param>
public sealed record FurnaceState(
    string? Input, int InputQuantity, int Fuel, int Heat, string? Output, int OutputQuantity, DateTimeOffset? StartedAt)
{
    public static readonly FurnaceState Empty = new(null, 0, 0, 0, null, 0, null);
}

public sealed record FurnaceReply(Guid Id, FurnaceState State, DateTimeOffset ServerTime, IReadOnlyList<(string Item, int Quantity)> Taken, XpGain? Xp);

/// <summary>Rows of <c>crafting.furnaces</c>; a furnace gets one when it is first used.</summary>
internal static class FurnaceRows
{
    public static async Task<FurnaceState?> ReadAsync(GameDb db, Guid id, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """
            SELECT input_item, input_quantity, fuel, heat, output_item, output_quantity, started_at
            FROM crafting.furnaces WHERE object_id = @id FOR UPDATE
            """, cancellationToken);
        command.Parameters.AddWithValue("id", id);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new FurnaceState(
            reader.IsDBNull(0) ? null : reader.GetString(0), reader.GetInt32(1), reader.GetInt32(2), reader.GetInt32(3),
            reader.IsDBNull(4) ? null : reader.GetString(4), reader.GetInt32(5),
            reader.IsDBNull(6) ? null : reader.GetFieldValue<DateTimeOffset>(6));
    }

    public static async Task WriteAsync(GameDb db, Guid owner, Guid id, FurnaceState s, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """
            INSERT INTO crafting.furnaces (object_id, owner_id, input_item, input_quantity, fuel, heat, output_item, output_quantity, started_at)
            VALUES (@id, @owner, @input, @inputQuantity, @fuel, @heat, @output, @outputQuantity, @started)
            ON CONFLICT (object_id) DO UPDATE SET
                input_item = @input, input_quantity = @inputQuantity, fuel = @fuel, heat = @heat,
                output_item = @output, output_quantity = @outputQuantity, started_at = @started
            """, cancellationToken);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("owner", owner);
        command.Parameters.AddWithValue("input", (object?)s.Input ?? DBNull.Value);
        command.Parameters.AddWithValue("inputQuantity", s.InputQuantity);
        command.Parameters.AddWithValue("fuel", s.Fuel);
        command.Parameters.AddWithValue("heat", s.Heat);
        command.Parameters.AddWithValue("output", (object?)s.Output ?? DBNull.Value);
        command.Parameters.AddWithValue("outputQuantity", s.OutputQuantity);
        command.Parameters.Add(new NpgsqlParameter("started", NpgsqlTypes.NpgsqlDbType.TimestampTz) { Value = (object?)s.StartedAt ?? DBNull.Value });
        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}

public sealed class FurnaceService(
    GameDb db, IEnumerable<IPlacedObjects> places, IInventory inventory, ICharacterProgress progress, IProductionStats stats, TimeProvider time)
{
    public Task<FurnaceReply> StateAsync(Guid owner, Guid id, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var state = await OpenAsync(owner, id, cancellationToken);
            return new FurnaceReply(id, state, time.GetUtcNow(), [], null);
        }, cancellationToken);

    /// <summary>Puts items from the inventory into the furnace: coal on the fire, ore to smelt.
    /// Ingots of another ore still waiting inside are handed to the player first.</summary>
    public Task<FurnaceReply> LoadAsync(Guid owner, Guid id, string item, int quantity, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (quantity < 1)
            {
                throw new GameException("bad_quantity", "Put in at least one.");
            }

            var state = await OpenAsync(owner, id, cancellationToken);
            var taken = new List<(string, int)>();
            XpGain? xp = null;
            if (item == Items.Coal)
            {
                if (state.Fuel + quantity > Smelting.MaxFuel)
                {
                    throw new GameException("furnace_full", $"The furnace holds at most {Smelting.MaxFuel} coal.");
                }

                state = state with { Fuel = state.Fuel + quantity };
            }
            else if (Smelting.For(item) is { } recipe)
            {
                if (state.Input is { } input && input != item)
                {
                    throw new GameException("furnace_busy", $"{Items.Names[input]} is being smelted; take it out first.");
                }

                if (state.InputQuantity + quantity > Smelting.MaxInput)
                {
                    throw new GameException("furnace_full", $"The furnace holds at most {Smelting.MaxInput} ore.");
                }

                if (state.Output is { } output && output != recipe.Output && state.OutputQuantity > 0)
                {
                    (state, xp) = await TakeOutputAsync(owner, state, taken, cancellationToken);
                }

                state = state with { Input = item, InputQuantity = state.InputQuantity + quantity };
            }
            else
            {
                throw new GameException("not_smeltable", "This cannot go into the furnace.");
            }

            await inventory.RemoveAsync(owner, item, quantity, cancellationToken);
            state = Smelting.Start(state, time.GetUtcNow());
            await FurnaceRows.WriteAsync(db, owner, id, state, cancellationToken);
            return new FurnaceReply(id, state, time.GetUtcNow(), taken, xp);
        }, cancellationToken);

    /// <summary>Takes the ingots (<c>output</c>), the ore not smelted yet (<c>input</c>) or the coal (<c>fuel</c>) out.</summary>
    public Task<FurnaceReply> TakeAsync(Guid owner, Guid id, string what, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var state = await OpenAsync(owner, id, cancellationToken);
            var taken = new List<(string, int)>();
            XpGain? xp = null;
            switch (what)
            {
                case "output":
                    (state, xp) = await TakeOutputAsync(owner, state, taken, cancellationToken);
                    break;
                case "input" when state.Input is { } input:
                    await inventory.AddAsync(owner, input, state.InputQuantity, cancellationToken);
                    taken.Add((input, state.InputQuantity));
                    state = state with { Input = null, InputQuantity = 0, StartedAt = null };
                    break;
                case "fuel" when state.Fuel > 0:
                    await inventory.AddAsync(owner, Items.Coal, state.Fuel, cancellationToken);
                    taken.Add((Items.Coal, state.Fuel));
                    // The piece in the fire keeps burning on the coal already lit, if there is any.
                    state = state.Heat > 0 ? state with { Fuel = 0 } : state with { Fuel = 0, StartedAt = null };
                    break;
                case "input" or "fuel":
                    break;
                default:
                    throw new GameException("bad_payload", "Take out output, input or fuel.");
            }

            await FurnaceRows.WriteAsync(db, owner, id, state, cancellationToken);
            return new FurnaceReply(id, state, time.GetUtcNow(), taken, xp);
        }, cancellationToken);

    private async Task<(FurnaceState, XpGain?)> TakeOutputAsync(Guid owner, FurnaceState state, List<(string, int)> taken, CancellationToken cancellationToken)
    {
        if (state.Output is not { } output || state.OutputQuantity == 0)
        {
            return (state, null);
        }

        await inventory.AddAsync(owner, output, state.OutputQuantity, cancellationToken);
        taken.Add((output, state.OutputQuantity));
        var xp = await progress.AddXpAsync(owner, state.OutputQuantity * Smelting.XpPerIngot, cancellationToken);
        return (state with { Output = null, OutputQuantity = 0 }, xp);
    }

    /// <summary>The player's furnace, locked until the transaction ends and smelted up to now.</summary>
    private async Task<FurnaceState> OpenAsync(Guid owner, Guid id, CancellationToken cancellationToken)
    {
        await Workshop.RequireAsync(places, owner, id, Items.Furnace, cancellationToken);
        var stored = await FurnaceRows.ReadAsync(db, id, cancellationToken) ?? FurnaceState.Empty;
        var state = Smelting.Advance(stored, time.GetUtcNow());
        var made = MachineProduction.Smelted(stored, state);
        if (made.Count > 0)
        {
            await stats.RecordAsync(owner, made, cancellationToken);
            await FurnaceRows.WriteAsync(db, owner, id, state, cancellationToken);
        }

        return state;
    }
}

/// <summary>Empties a furnace that is being picked up: what it smelted, its ore and its coal go to the inventory.
/// Processing machines (mill, bakery, ...) are emptied the same way.</summary>
public sealed class FurnaceContents(GameDb db, IInventory inventory, IProductionStats stats, TimeProvider time) : IMachineContents
{
    public async Task ReleaseAsync(Guid owner, Guid id, CancellationToken cancellationToken)
    {
        await MachineRows.ReleaseAsync(db, inventory, stats, owner, id, time.GetUtcNow(), cancellationToken);
        if (await FurnaceRows.ReadAsync(db, id, cancellationToken) is not { } row)
        {
            return;
        }

        var state = Smelting.Advance(row, time.GetUtcNow());
        await stats.RecordAsync(owner, MachineProduction.Smelted(row, state), cancellationToken);
        if (state.Output is { } output && state.OutputQuantity > 0)
        {
            await inventory.AddAsync(owner, output, state.OutputQuantity, cancellationToken);
        }

        if (state.Input is { } input && state.InputQuantity > 0)
        {
            await inventory.AddAsync(owner, input, state.InputQuantity, cancellationToken);
        }

        if (state.Fuel > 0)
        {
            await inventory.AddAsync(owner, Items.Coal, state.Fuel, cancellationToken);
        }

        await using var delete = await db.CommandAsync("DELETE FROM crafting.furnaces WHERE object_id = @id", cancellationToken);
        delete.Parameters.AddWithValue("id", id);
        await delete.ExecuteNonQueryAsync(cancellationToken);
    }
}

/// <summary>Furnaces as inserters see them: coal and ore go in, ingots come out.</summary>
public sealed class FurnacePorts(GameDb db, IProductionStats stats) : IMachinePorts
{
    public async Task<IMachinePort?> OpenAsync(Guid owner, Guid id, string kind, CancellationToken cancellationToken)
    {
        if (kind != Items.Furnace)
        {
            return null;
        }

        return new Port(db, stats, owner, id, await FurnaceRows.ReadAsync(db, id, cancellationToken) ?? FurnaceState.Empty);
    }

    private sealed class Port(GameDb db, IProductionStats stats, Guid owner, Guid id, FurnaceState state) : IMachinePort
    {
        private readonly List<ProductionEntry> _made = [];
        private bool _changed;

        public string? Output(DateTimeOffset now, Func<string, bool> wanted)
        {
            Advance(now);
            return state.Output is { } output && state.OutputQuantity > 0 && wanted(output) ? output : null;
        }

        public void Take(string item, DateTimeOffset now)
        {
            Advance(now);
            if (state.Output == item && state.OutputQuantity > 0)
            {
                state = state.OutputQuantity == 1 ? state with { Output = null, OutputQuantity = 0 } : state with { OutputQuantity = state.OutputQuantity - 1 };
                _changed = true;
            }
        }

        public bool Accepts(string item, DateTimeOffset now)
        {
            Advance(now);
            if (item == Items.Coal)
            {
                return state.Fuel < Smelting.MaxFuel;
            }

            // Ingots of another metal must be taken out before another ore goes in.
            return Smelting.For(item) is { } recipe
                && (state.Input is null || state.Input == item) && state.InputQuantity < Smelting.MaxInput
                && (state.Output is null || state.Output == recipe.Output || state.OutputQuantity == 0);
        }

        public void Put(string item, DateTimeOffset now)
        {
            state = item == Items.Coal
                ? state with { Fuel = state.Fuel + 1 }
                : state with { Input = item, InputQuantity = state.InputQuantity + 1 };
            state = Smelting.Start(state, now);
            _changed = true;
        }

        public DateTimeOffset? NextChange(DateTimeOffset now)
        {
            Advance(now);
            return state.StartedAt is { } started && Smelting.For(state.Input) is { } recipe ? started + recipe.Time : null;
        }

        public async Task SaveAsync(CancellationToken cancellationToken)
        {
            if (_changed)
            {
                await stats.RecordAsync(owner, _made, cancellationToken);
                await FurnaceRows.WriteAsync(db, owner, id, state, cancellationToken);
            }
        }

        private void Advance(DateTimeOffset now)
        {
            var before = state;
            state = Smelting.Advance(state, now);
            var made = MachineProduction.Smelted(before, state);
            if (made.Count > 0)
            {
                _made.AddRange(made);
                _changed = true;
            }
        }
    }
}

public sealed record FurnaceRequest(Guid Furnace);

public sealed record LoadFurnaceRequest(Guid Furnace, string Item, int Quantity);

public sealed record TakeFurnaceRequest(Guid Furnace, string What);

public abstract class FurnaceHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var reply = await RunAsync(scope.ServiceProvider.GetRequiredService<FurnaceService>(), client.RequireAccount(), payload, cancellationToken);
        var s = reply.State;
        return new Reply("furnace", new
        {
            id = reply.Id,
            input = Stack(s.Input, s.InputQuantity),
            output = Stack(s.Output, s.OutputQuantity),
            fuel = s.Fuel,
            heat = s.Heat,
            // Unix milliseconds of when the piece in the fire went in, and how long it takes.
            startedAt = s.StartedAt?.ToUnixTimeMilliseconds(),
            smeltSeconds = Smelting.For(s.Input)?.Time.TotalSeconds,
            serverTime = reply.ServerTime.ToUnixTimeMilliseconds(),
            recipes = Smelting.Recipes.Select(r => new
            {
                input = r.Input,
                inputName = Items.Names[r.Input],
                output = r.Output,
                outputName = Items.Names[r.Output],
                seconds = r.Time.TotalSeconds,
            }),
            smeltsPerCoal = Smelting.SmeltsPerCoal,
            maxInput = Smelting.MaxInput,
            maxFuel = Smelting.MaxFuel,
            taken = reply.Taken.Select(t => new { id = t.Item, name = Items.Names[t.Item], quantity = t.Quantity }),
            xp = reply.Xp is { } xp ? new { xp = xp.Xp, level = xp.Level, leveledUp = xp.LeveledUp } : null,
        });
    }

    private static object? Stack(string? item, int quantity) =>
        item is null || quantity == 0 ? null : new { id = item, name = Items.Names[item], quantity };

    protected abstract Task<FurnaceReply> RunAsync(FurnaceService furnaces, Guid owner, JsonElement? payload, CancellationToken cancellationToken);
}

/// <summary>What the furnace holds now; the client asks again when the next ingot is due.</summary>
public sealed class GetFurnaceHandler(IServiceScopeFactory scopes) : FurnaceHandler(scopes)
{
    public override string Type => "furnace.get";

    protected override Task<FurnaceReply> RunAsync(FurnaceService furnaces, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        furnaces.StateAsync(owner, Payload.Read<FurnaceRequest>(payload).Furnace, cancellationToken);
}

public sealed class LoadFurnaceHandler(IServiceScopeFactory scopes) : FurnaceHandler(scopes)
{
    public override string Type => "furnace.load";

    protected override Task<FurnaceReply> RunAsync(FurnaceService furnaces, Guid owner, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<LoadFurnaceRequest>(payload);
        return furnaces.LoadAsync(owner, request.Furnace, request.Item ?? "", request.Quantity, cancellationToken);
    }
}

public sealed class TakeFurnaceHandler(IServiceScopeFactory scopes) : FurnaceHandler(scopes)
{
    public override string Type => "furnace.take";

    protected override Task<FurnaceReply> RunAsync(FurnaceService furnaces, Guid owner, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<TakeFurnaceRequest>(payload);
        return furnaces.TakeAsync(owner, request.Furnace, request.What ?? "", cancellationToken);
    }
}
