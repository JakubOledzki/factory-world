using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace FactoryWorld.Modules.Crafting;

/// <summary>One batch of a processing machine: the ingredients it takes and what comes out.</summary>
/// <param name="Id">The recipe's id, the same as the item it makes.</param>
/// <param name="Xp">Experience for each item taken out of the machine.</param>
public sealed record ProcessingRecipe(string Id, int Quantity, TimeSpan Time, IReadOnlyList<(string Item, int Quantity)> Ingredients, int Xp);

/// <param name="Kind">The machine's item id.</param>
/// <param name="Fired">Whether it burns fuel: one batch takes heat from the fire.</param>
public sealed record ProcessingMachine(string Kind, bool Fired, IReadOnlyList<ProcessingRecipe> Recipes)
{
    public ProcessingRecipe? Recipe(string? id) => Recipes.FirstOrDefault(r => r.Id == id);
}

/// <summary>
/// Machines that turn crops into food, put on a plot like the furnace: a mill grinds grain into
/// flour, an oil press squeezes sunflowers, a barrel pickles cabbage, and the fired bakery and
/// field kitchen bake and cook from those. The player sets a recipe, then loads its ingredients
/// (and fuel, where the machine burns it); the machine makes one batch after another while the
/// player is away too, and the products wait in it until taken out.
/// </summary>
public static class Processing
{
    /// <summary>Of each ingredient, and of fuel.</summary>
    public const int MaxInput = 50;

    public const int MaxFuel = 50;

    /// <summary>A full machine stops until its products are taken out.</summary>
    public const int MaxOutput = 100;

    /// <summary>What a fired machine burns, and how many batches one piece lasts.</summary>
    public static readonly IReadOnlyDictionary<string, int> Fuels = new Dictionary<string, int>
    {
        [Items.Coal] = 4,
        [Items.Wood] = 1,
    };

    public static readonly IReadOnlyList<ProcessingMachine> Machines =
    [
        new(Items.Mill, false,
        [
            new(Items.Flour, 1, TimeSpan.FromSeconds(6), [(Items.Wheat, 2)], 1),
            new(Items.CornFlour, 1, TimeSpan.FromSeconds(6), [(Items.Corn, 2)], 1),
        ]),
        new(Items.OilPress, false,
        [
            new(Items.SunflowerOil, 1, TimeSpan.FromSeconds(10), [(Items.Sunflower, 2)], 2),
        ]),
        new(Items.PicklingBarrel, false,
        [
            new(Items.Sauerkraut, 2, TimeSpan.FromSeconds(60), [(Items.Cabbage, 2)], 1),
        ]),
        new(Items.Bakery, true,
        [
            new(Items.Bread, 1, TimeSpan.FromSeconds(20), [(Items.Flour, 2)], 3),
            new(Items.CornBread, 1, TimeSpan.FromSeconds(20), [(Items.CornFlour, 2)], 3),
            new(Items.CarrotCake, 1, TimeSpan.FromSeconds(30), [(Items.Flour, 2), (Items.Carrot, 3), (Items.SunflowerOil, 1)], 6),
        ]),
        new(Items.Kitchen, true,
        [
            new(Items.Fries, 2, TimeSpan.FromSeconds(15), [(Items.Potato, 3), (Items.SunflowerOil, 1)], 2),
            new(Items.VegetableSoup, 1, TimeSpan.FromSeconds(20), [(Items.Carrot, 2), (Items.Potato, 2), (Items.Cabbage, 1)], 4),
            new(Items.Bigos, 2, TimeSpan.FromSeconds(25), [(Items.Sauerkraut, 2), (Items.Potato, 2)], 3),
        ]),
    ];

    public static readonly IReadOnlyDictionary<string, ProcessingMachine> ByKind = Machines.ToDictionary(m => m.Kind);

    /// <summary>Batches the machine can still make from what it holds, ignoring time.</summary>
    public static int Batches(ProcessingMachine machine, MachineState s)
    {
        if (machine.Recipe(s.Recipe) is not { } recipe)
        {
            return 0;
        }

        var n = (MaxOutput - s.Output) / recipe.Quantity;
        for (var i = 0; i < recipe.Ingredients.Count; i++)
        {
            n = Math.Min(n, s.Input(i) / recipe.Ingredients[i].Quantity);
        }

        if (machine.Fired)
        {
            n = Math.Min(n, s.Heat + s.Fuel * FuelBatches(s.FuelItem));
        }

        return Math.Max(0, n);
    }

    private static int FuelBatches(string? fuel) => fuel is not null && Fuels.TryGetValue(fuel, out var batches) ? batches : 0;

    /// <summary>What the machine holds after working until <paramref name="now"/>.</summary>
    public static MachineState Advance(ProcessingMachine machine, MachineState s, DateTimeOffset now)
    {
        if (s.StartedAt is not { } started || machine.Recipe(s.Recipe) is not { } recipe)
        {
            return s with { StartedAt = null };
        }

        var possible = (int)Math.Min(int.MaxValue, Math.Max(0, (now - started).Ticks / recipe.Time.Ticks));
        var n = Math.Min(possible, Batches(machine, s));
        var inputs = s.Inputs.ToArray();
        for (var i = 0; i < recipe.Ingredients.Count; i++)
        {
            inputs[i] -= n * recipe.Ingredients[i].Quantity;
        }

        var after = s with { Inputs = inputs, Output = s.Output + n * recipe.Quantity };
        if (machine.Fired)
        {
            var perFuel = FuelBatches(s.FuelItem);
            var burnt = n > s.Heat ? (n - s.Heat + perFuel - 1) / perFuel : 0;
            after = after with { Fuel = s.Fuel - burnt, Heat = s.Heat + burnt * perFuel - n };
            if (after.Fuel == 0)
            {
                after = after with { FuelItem = null };
            }
        }

        return Batches(machine, after) > 0
            ? after with { StartedAt = started + recipe.Time * n }
            : after with { StartedAt = null };
    }

    /// <summary>Starts an idle machine that has everything for a batch.</summary>
    public static MachineState Start(ProcessingMachine machine, MachineState s, DateTimeOffset now) =>
        s.StartedAt is null && Batches(machine, s) > 0 ? s with { StartedAt = now } : s;
}

/// <param name="Recipe">The recipe the player set, or null.</param>
/// <param name="Inputs">How much of each of the recipe's ingredients is loaded, in the recipe's order.</param>
/// <param name="FuelItem">What lies by the fire (coal or wood), or null.</param>
/// <param name="Heat">Batches left from fuel already burning.</param>
/// <param name="Output">Products made from the recipe, waiting to be taken out.</param>
/// <param name="StartedAt">When the batch being made now started; null while the machine stands idle.</param>
public sealed record MachineState(
    string? Recipe, IReadOnlyList<int> Inputs, string? FuelItem, int Fuel, int Heat, int Output, DateTimeOffset? StartedAt)
{
    public static readonly MachineState Empty = new(null, [], null, 0, 0, 0, null);

    public int Input(int i) => i < Inputs.Count ? Inputs[i] : 0;
}

public sealed record MachineReply(
    Guid Id, ProcessingMachine Machine, MachineState State, DateTimeOffset ServerTime, IReadOnlyList<(string Item, int Quantity)> Taken, XpGain? Xp);

/// <summary>Rows of <c>crafting.machines</c>; a machine gets one when it is first used.</summary>
internal static class MachineRows
{
    /// <summary>The machine's kind and what it holds, locked until the transaction ends.</summary>
    public static async Task<(string Kind, MachineState State)?> ReadAsync(GameDb db, Guid id, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """
            SELECT kind, recipe, inputs, fuel_item, fuel, heat, output, started_at
            FROM crafting.machines WHERE object_id = @id FOR UPDATE
            """, cancellationToken);
        command.Parameters.AddWithValue("id", id);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return (reader.GetString(0), new MachineState(
            reader.IsDBNull(1) ? null : reader.GetString(1), reader.GetFieldValue<int[]>(2),
            reader.IsDBNull(3) ? null : reader.GetString(3), reader.GetInt32(4), reader.GetInt32(5), reader.GetInt32(6),
            reader.IsDBNull(7) ? null : reader.GetFieldValue<DateTimeOffset>(7)));
    }

    public static async Task WriteAsync(GameDb db, Guid owner, Guid id, string kind, MachineState s, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            """
            INSERT INTO crafting.machines (object_id, owner_id, kind, recipe, inputs, fuel_item, fuel, heat, output, started_at)
            VALUES (@id, @owner, @kind, @recipe, @inputs, @fuelItem, @fuel, @heat, @output, @started)
            ON CONFLICT (object_id) DO UPDATE SET
                recipe = @recipe, inputs = @inputs, fuel_item = @fuelItem, fuel = @fuel, heat = @heat,
                output = @output, started_at = @started
            """, cancellationToken);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("owner", owner);
        command.Parameters.AddWithValue("kind", kind);
        command.Parameters.AddWithValue("recipe", (object?)s.Recipe ?? DBNull.Value);
        command.Parameters.AddWithValue("inputs", s.Inputs.ToArray());
        command.Parameters.AddWithValue("fuelItem", (object?)s.FuelItem ?? DBNull.Value);
        command.Parameters.AddWithValue("fuel", s.Fuel);
        command.Parameters.AddWithValue("heat", s.Heat);
        command.Parameters.AddWithValue("output", s.Output);
        command.Parameters.Add(new NpgsqlParameter("started", NpgsqlTypes.NpgsqlDbType.TimestampTz) { Value = (object?)s.StartedAt ?? DBNull.Value });
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>Everything the machine holds, as item stacks.</summary>
    public static IEnumerable<(string Item, int Quantity)> Contents(ProcessingMachine machine, MachineState s)
    {
        if (machine.Recipe(s.Recipe) is { } recipe)
        {
            if (s.Output > 0)
            {
                yield return (recipe.Id, s.Output);
            }

            for (var i = 0; i < recipe.Ingredients.Count; i++)
            {
                if (s.Input(i) > 0)
                {
                    yield return (recipe.Ingredients[i].Item, s.Input(i));
                }
            }
        }

        if (s.FuelItem is { } fuel && s.Fuel > 0)
        {
            yield return (fuel, s.Fuel);
        }
    }

    /// <summary>The machine is being picked up: what it holds goes to the owner's inventory.</summary>
    public static async Task ReleaseAsync(
        GameDb db, IInventory inventory, IProductionStats stats, Guid owner, Guid id, DateTimeOffset now, CancellationToken cancellationToken)
    {
        if (await ReadAsync(db, id, cancellationToken) is not { } row || !Processing.ByKind.TryGetValue(row.Kind, out var machine))
        {
            return;
        }

        var state = Processing.Advance(machine, row.State, now);
        await stats.RecordAsync(owner, MachineProduction.Processed(machine, row.State, state), cancellationToken);
        foreach (var (item, quantity) in Contents(machine, state))
        {
            await inventory.AddAsync(owner, item, quantity, cancellationToken);
        }

        await using var delete = await db.CommandAsync("DELETE FROM crafting.machines WHERE object_id = @id", cancellationToken);
        delete.Parameters.AddWithValue("id", id);
        await delete.ExecuteNonQueryAsync(cancellationToken);
    }
}

public sealed class MachineService(
    GameDb db, IEnumerable<IPlacedObjects> places, IInventory inventory, ICharacterProgress progress, IProductionStats stats, ITechnologies technologies, TimeProvider time)
{
    public Task<MachineReply> StateAsync(Guid owner, Guid id, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var (machine, state) = await OpenAsync(owner, id, cancellationToken);
            return new MachineReply(id, machine, state, time.GetUtcNow(), [], null);
        }, cancellationToken);

    /// <summary>Sets what the machine makes. Ingredients and products of the old recipe go back to the inventory; the fire keeps burning.</summary>
    public Task<MachineReply> SetRecipeAsync(Guid owner, Guid id, string recipeId, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var (machine, state) = await OpenAsync(owner, id, cancellationToken);
            var recipe = machine.Recipe(recipeId) ?? throw new GameException("no_recipe", "This machine has no such recipe.");
            await technologies.RequireUnlockedAsync(owner, recipe.Id, cancellationToken);
            var taken = new List<(string, int)>();
            XpGain? xp = null;
            if (state.Recipe != recipe.Id)
            {
                (state, xp) = await TakeOutputAsync(owner, machine, state, taken, cancellationToken);
                state = await TakeInputsAsync(owner, machine, state, taken, cancellationToken);
                state = Processing.Start(machine, state with { Recipe = recipe.Id, Inputs = new int[recipe.Ingredients.Count] }, time.GetUtcNow());
                await MachineRows.WriteAsync(db, owner, id, machine.Kind, state, cancellationToken);
            }

            return new MachineReply(id, machine, state, time.GetUtcNow(), taken, xp);
        }, cancellationToken);

    /// <summary>Puts items from the inventory into the machine: fuel by the fire, an ingredient of the recipe in its place.</summary>
    public Task<MachineReply> LoadAsync(Guid owner, Guid id, string item, int quantity, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (quantity < 1)
            {
                throw new GameException("bad_quantity", "Put in at least one.");
            }

            var (machine, state) = await OpenAsync(owner, id, cancellationToken);
            var recipe = machine.Recipe(state.Recipe);
            var slot = recipe is null ? -1 : recipe.Ingredients.ToList().FindIndex(i => i.Item == item);
            if (slot >= 0)
            {
                if (state.Input(slot) + quantity > Processing.MaxInput)
                {
                    throw new GameException("machine_full", $"The machine holds at most {Processing.MaxInput} of each ingredient.");
                }

                var inputs = state.Inputs.ToArray();
                inputs[slot] += quantity;
                state = state with { Inputs = inputs };
            }
            else if (machine.Fired && Processing.Fuels.ContainsKey(item))
            {
                if (state.FuelItem is { } fuel && fuel != item && state.Fuel > 0)
                {
                    throw new GameException("machine_busy", $"{Items.Names[fuel]} lies by the fire; take it out first.");
                }

                if (state.Fuel + quantity > Processing.MaxFuel)
                {
                    throw new GameException("machine_full", $"The machine holds at most {Processing.MaxFuel} fuel.");
                }

                state = state with { FuelItem = item, Fuel = state.Fuel + quantity };
            }
            else
            {
                throw recipe is null
                    ? new GameException("choose_recipe", "Choose what the machine makes first.")
                    : new GameException("not_processable", "This does not go into the machine.");
            }

            await inventory.RemoveAsync(owner, item, quantity, cancellationToken);
            state = Processing.Start(machine, state, time.GetUtcNow());
            await MachineRows.WriteAsync(db, owner, id, machine.Kind, state, cancellationToken);
            return new MachineReply(id, machine, state, time.GetUtcNow(), [], null);
        }, cancellationToken);

    /// <summary>Takes the products (<c>output</c>), the ingredients not used yet (<c>input</c>) or the fuel (<c>fuel</c>) out.</summary>
    public Task<MachineReply> TakeAsync(Guid owner, Guid id, string what, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var (machine, state) = await OpenAsync(owner, id, cancellationToken);
            var taken = new List<(string, int)>();
            XpGain? xp = null;
            switch (what)
            {
                case "output":
                    (state, xp) = await TakeOutputAsync(owner, machine, state, taken, cancellationToken);
                    // Room again for what was waiting on a full machine.
                    state = Processing.Start(machine, state, time.GetUtcNow());
                    break;
                case "input":
                    state = await TakeInputsAsync(owner, machine, state, taken, cancellationToken);
                    break;
                case "fuel":
                    if (state.FuelItem is { } fuel && state.Fuel > 0)
                    {
                        await inventory.AddAsync(owner, fuel, state.Fuel, cancellationToken);
                        taken.Add((fuel, state.Fuel));
                    }

                    // The batch in the fire keeps going on the fuel already lit, if there is any.
                    state = state with { FuelItem = null, Fuel = 0 };
                    if (state.Heat == 0)
                    {
                        state = state with { StartedAt = null };
                    }

                    break;
                default:
                    throw new GameException("bad_payload", "Take out output, input or fuel.");
            }

            await MachineRows.WriteAsync(db, owner, id, machine.Kind, state, cancellationToken);
            return new MachineReply(id, machine, state, time.GetUtcNow(), taken, xp);
        }, cancellationToken);

    private async Task<(MachineState, XpGain?)> TakeOutputAsync(
        Guid owner, ProcessingMachine machine, MachineState state, List<(string, int)> taken, CancellationToken cancellationToken)
    {
        if (machine.Recipe(state.Recipe) is not { } recipe || state.Output == 0)
        {
            return (state, null);
        }

        await inventory.AddAsync(owner, recipe.Id, state.Output, cancellationToken);
        taken.Add((recipe.Id, state.Output));
        var xp = await progress.AddXpAsync(owner, (long)state.Output * recipe.Xp, cancellationToken);
        return (state with { Output = 0 }, xp);
    }

    private async Task<MachineState> TakeInputsAsync(
        Guid owner, ProcessingMachine machine, MachineState state, List<(string, int)> taken, CancellationToken cancellationToken)
    {
        if (machine.Recipe(state.Recipe) is not { } recipe)
        {
            return state;
        }

        for (var i = 0; i < recipe.Ingredients.Count; i++)
        {
            if (state.Input(i) > 0)
            {
                await inventory.AddAsync(owner, recipe.Ingredients[i].Item, state.Input(i), cancellationToken);
                taken.Add((recipe.Ingredients[i].Item, state.Input(i)));
            }
        }

        return state with { Inputs = new int[recipe.Ingredients.Count], StartedAt = null };
    }

    /// <summary>The player's machine, locked until the transaction ends and worked up to now.</summary>
    private async Task<(ProcessingMachine, MachineState)> OpenAsync(Guid owner, Guid id, CancellationToken cancellationToken)
    {
        ProcessingMachine? machine = null;
        foreach (var place in places)
        {
            if (await place.KindAsync(owner, id, cancellationToken) is { } kind)
            {
                machine = Processing.ByKind.GetValueOrDefault(kind);
                break;
            }
        }

        if (machine is null)
        {
            throw new GameException("no_object", "There is no machine of yours here.");
        }

        var stored = (await MachineRows.ReadAsync(db, id, cancellationToken))?.State ?? MachineState.Empty;
        var state = Processing.Advance(machine, stored, time.GetUtcNow());
        var made = MachineProduction.Processed(machine, stored, state);
        if (made.Count > 0)
        {
            await stats.RecordAsync(owner, made, cancellationToken);
            await MachineRows.WriteAsync(db, owner, id, machine.Kind, state, cancellationToken);
        }

        return (machine, state);
    }
}

/// <summary>Processing machines as inserters see them: ingredients of the chosen recipe and fuel go in, products come out.</summary>
public sealed class ProcessingPorts(GameDb db, IProductionStats stats) : IMachinePorts
{
    public async Task<IMachinePort?> OpenAsync(Guid owner, Guid id, string kind, CancellationToken cancellationToken)
    {
        if (!Processing.ByKind.TryGetValue(kind, out var machine))
        {
            return null;
        }

        var state = (await MachineRows.ReadAsync(db, id, cancellationToken))?.State ?? MachineState.Empty;
        return new Port(db, stats, owner, id, machine, state);
    }

    private sealed class Port(GameDb db, IProductionStats stats, Guid owner, Guid id, ProcessingMachine machine, MachineState state) : IMachinePort
    {
        private readonly List<ProductionEntry> _made = [];
        private bool _changed;

        private ProcessingRecipe? Recipe => machine.Recipe(state.Recipe);

        public string? Output(DateTimeOffset now, Func<string, bool> wanted)
        {
            Advance(now);
            return Recipe is { } recipe && state.Output > 0 && wanted(recipe.Id) ? recipe.Id : null;
        }

        public void Take(string item, DateTimeOffset now)
        {
            Advance(now);
            if (Recipe?.Id == item && state.Output > 0)
            {
                // Room again for what was waiting on a full machine.
                state = Processing.Start(machine, state with { Output = state.Output - 1 }, now);
                _changed = true;
            }
        }

        public bool Accepts(string item, DateTimeOffset now)
        {
            Advance(now);
            if (Slot(item) is var slot and >= 0)
            {
                return state.Input(slot) < Processing.MaxInput;
            }

            return machine.Fired && Processing.Fuels.ContainsKey(item)
                && (state.FuelItem is null || state.FuelItem == item || state.Fuel == 0) && state.Fuel < Processing.MaxFuel;
        }

        public void Put(string item, DateTimeOffset now)
        {
            if (Slot(item) is var slot and >= 0)
            {
                var inputs = new int[Recipe!.Ingredients.Count];
                for (var i = 0; i < inputs.Length; i++)
                {
                    inputs[i] = state.Input(i);
                }

                inputs[slot]++;
                state = state with { Inputs = inputs };
            }
            else
            {
                state = state with { FuelItem = item, Fuel = state.Fuel + 1 };
            }

            state = Processing.Start(machine, state, now);
            _changed = true;
        }

        public DateTimeOffset? NextChange(DateTimeOffset now)
        {
            Advance(now);
            return state.StartedAt is { } started && Recipe is { } recipe ? started + recipe.Time : null;
        }

        public async Task SaveAsync(CancellationToken cancellationToken)
        {
            if (_changed)
            {
                await stats.RecordAsync(owner, _made, cancellationToken);
                await MachineRows.WriteAsync(db, owner, id, machine.Kind, state, cancellationToken);
            }
        }

        private void Advance(DateTimeOffset now)
        {
            var before = state;
            state = Processing.Advance(machine, state, now);
            var made = MachineProduction.Processed(machine, before, state);
            if (made.Count > 0)
            {
                _made.AddRange(made);
                _changed = true;
            }
        }

        private int Slot(string item) => Recipe is { } recipe ? recipe.Ingredients.ToList().FindIndex(i => i.Item == item) : -1;
    }
}

public sealed record MachineRequest(Guid Machine);

public sealed record MachineRecipeRequest(Guid Machine, string Recipe);

public sealed record LoadMachineRequest(Guid Machine, string Item, int Quantity);

public sealed record TakeMachineRequest(Guid Machine, string What);

public abstract class MachineHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var owner = client.RequireAccount();
        var reply = await RunAsync(scope.ServiceProvider.GetRequiredService<MachineService>(), owner, payload, cancellationToken);
        var locked = await scope.ServiceProvider.GetRequiredService<ITechnologies>().LockedAsync(owner, cancellationToken);
        var machine = reply.Machine;
        var s = reply.State;
        var recipe = machine.Recipe(s.Recipe);
        return new Reply("machine", new
        {
            id = reply.Id,
            kind = machine.Kind,
            name = Items.Names[machine.Kind],
            recipe = recipe?.Id,
            recipes = machine.Recipes.Select(r => new
            {
                id = r.Id,
                name = Items.Names[r.Id],
                quantity = r.Quantity,
                seconds = r.Time.TotalSeconds,
                ingredients = r.Ingredients.Select(i => new { id = i.Item, name = Items.Names[i.Item], quantity = i.Quantity }),
                xp = r.Xp,
                locked = locked.GetValueOrDefault(r.Id),
            }),
            inputs = recipe?.Ingredients.Select((ingredient, i) => new
            {
                id = ingredient.Item,
                name = Items.Names[ingredient.Item],
                quantity = s.Input(i),
                need = ingredient.Quantity,
            }) ?? [],
            output = recipe is null || s.Output == 0 ? null : new { id = recipe.Id, name = Items.Names[recipe.Id], quantity = s.Output },
            fired = machine.Fired,
            fuel = s.FuelItem is { } fuel && s.Fuel > 0 ? new { id = fuel, name = Items.Names[fuel], quantity = s.Fuel } : null,
            heat = s.Heat,
            fuels = machine.Fired
                ? Processing.Fuels.Select(f => new { id = f.Key, name = Items.Names[f.Key], batches = f.Value })
                : [],
            batches = Processing.Batches(machine, s),
            // Unix milliseconds of when the batch being made started, and how long one takes.
            startedAt = s.StartedAt?.ToUnixTimeMilliseconds(),
            seconds = recipe?.Time.TotalSeconds,
            serverTime = reply.ServerTime.ToUnixTimeMilliseconds(),
            maxInput = Processing.MaxInput,
            maxFuel = Processing.MaxFuel,
            maxOutput = Processing.MaxOutput,
            taken = reply.Taken.Select(t => new { id = t.Item, name = Items.Names[t.Item], quantity = t.Quantity }),
            xp = reply.Xp is { } xp ? new { xp = xp.Xp, level = xp.Level, leveledUp = xp.LeveledUp } : null,
        });
    }

    protected abstract Task<MachineReply> RunAsync(MachineService machines, Guid owner, JsonElement? payload, CancellationToken cancellationToken);
}

/// <summary>What the machine holds now; the client asks again when the next batch is due.</summary>
public sealed class GetMachineHandler(IServiceScopeFactory scopes) : MachineHandler(scopes)
{
    public override string Type => "machine.get";

    protected override Task<MachineReply> RunAsync(MachineService machines, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        machines.StateAsync(owner, Payload.Read<MachineRequest>(payload).Machine, cancellationToken);
}

public sealed class SetMachineRecipeHandler(IServiceScopeFactory scopes) : MachineHandler(scopes)
{
    public override string Type => "machine.recipe";

    protected override Task<MachineReply> RunAsync(MachineService machines, Guid owner, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<MachineRecipeRequest>(payload);
        return machines.SetRecipeAsync(owner, request.Machine, request.Recipe ?? "", cancellationToken);
    }
}

public sealed class LoadMachineHandler(IServiceScopeFactory scopes) : MachineHandler(scopes)
{
    public override string Type => "machine.load";

    protected override Task<MachineReply> RunAsync(MachineService machines, Guid owner, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<LoadMachineRequest>(payload);
        return machines.LoadAsync(owner, request.Machine, request.Item ?? "", request.Quantity, cancellationToken);
    }
}

public sealed class TakeMachineHandler(IServiceScopeFactory scopes) : MachineHandler(scopes)
{
    public override string Type => "machine.take";

    protected override Task<MachineReply> RunAsync(MachineService machines, Guid owner, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<TakeMachineRequest>(payload);
        return machines.TakeAsync(owner, request.Machine, request.What ?? "", cancellationToken);
    }
}
