using System.IO.Compression;
using System.Text.Json;
using FactoryWorld.Modules.Abstractions.Contracts;
using FactoryWorld.Modules.Logistics;
using FactoryWorld.Modules.Power;
using FactoryWorld.Modules.World;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Server.Tests;

public sealed class PowerTests(ServerFactory factory) : IClassFixture<ServerFactory>
{
    private static readonly WorldMap Map = WorldMap.Load();
    private static int _plots;

    // --- The rules, without a database ----------------------------------------------------------

    private static readonly DateTimeOffset Start = DateTimeOffset.UnixEpoch + TimeSpan.FromDays(1);

    private static PlotObject Obj(string kind, int x, int y, int rotation = 1) => new(Guid.NewGuid(), kind, x, y, rotation, Guid.Empty);

    private static PowerGrid Grid(IReadOnlyList<PlotObject> objects, GridData? data = null) =>
        new(0, 0, objects, data ?? new GridData(), Start, (_, _, _) => Task.CompletedTask);

    private static GridData Fuelled(PlotObject generator, string item, int quantity) =>
        new() { Generators = { [generator.Id] = new GeneratorState(item, quantity, 0) } };

    [Fact]
    public void Poles_in_reach_of_each_other_make_one_network_with_what_they_cover()
    {
        var a = Obj(Items.Pole, 0, 0);
        var b = Obj(Items.Pole, 7, 0);
        var far = Obj(Items.Pole, 30, 0);
        var mill = Obj(Items.Mill, 9, 2);
        var generator = Obj(Items.Generator, -2, -2);
        var alone = Obj(Items.Mill, 20, 0);
        var networks = PowerRules.Networks([a, b, far, mill, generator, alone]);

        Assert.Equal(2, networks.Count);
        Assert.Equal([a.Id, b.Id], networks[0].Poles);
        Assert.Equal([mill.Id], networks[0].Consumers);
        Assert.Equal([generator.Id], networks[0].Generators);
        Assert.Equal(30, networks[0].DemandKw);
        Assert.Empty(networks[1].Consumers);
    }

    [Fact]
    public void A_machine_works_at_full_speed_until_the_generator_burns_its_fuel_then_stops()
    {
        var pole = Obj(Items.Pole, 0, 0);
        var mill = Obj(Items.Mill, 1, 0);
        var generator = Obj(Items.Generator, -1, 0);
        var grid = Grid([pole, mill, generator], Fuelled(generator, Items.Coal, 1));
        var clock = grid.Clock(mill.Id);

        // One coal is 20 MJ; the mill draws 30 kW, so it lasts 666.7 s.
        Assert.Equal(1, clock.Speed(Start + TimeSpan.FromSeconds(600)));
        Assert.Equal(30, grid.Output(generator.Id, Start));
        Assert.Equal(Start + TimeSpan.FromSeconds(600), clock.At(Start + TimeSpan.FromSeconds(600)));
        var out_ = grid.RunsOutAt(generator.Id)!.Value;
        Assert.InRange((out_ - Start).TotalSeconds, 666.6, 666.7);
        Assert.Equal(0, clock.Speed(out_ + TimeSpan.FromSeconds(1)));

        // Its own time stands still from then on.
        Assert.Equal(clock.At(out_), clock.At(out_ + TimeSpan.FromHours(1)));
        Assert.Null(clock.When(clock.At(out_) + TimeSpan.FromSeconds(1), out_));
        Assert.False(grid.Generator(generator.Id, out_ + TimeSpan.FromSeconds(1)).Running);
    }

    [Fact]
    public void Too_little_power_slows_every_machine_on_the_network_down()
    {
        var pole = Obj(Items.Pole, 0, 0);
        var generator = Obj(Items.Generator, 0, 1);
        var mills = Enumerable.Range(-2, 5).Select(x => Obj(Items.Mill, x, -1)).ToList();
        var grid = Grid([pole, generator, .. mills], Fuelled(generator, Items.Coal, 10));

        // Five mills draw 150 kW from a 100 kW generator.
        var clock = grid.Clock(mills[0].Id);
        Assert.Equal(100.0 / 150, clock.Speed(Start), 6);
        Assert.Equal(Start + TimeSpan.FromSeconds(20), clock.At(Start + TimeSpan.FromSeconds(30)));
        Assert.Equal(Start + TimeSpan.FromSeconds(30), clock.When(Start + TimeSpan.FromSeconds(20), Start));
    }

    [Fact]
    public void A_machine_without_a_pole_near_has_no_power_and_settling_keeps_its_lag()
    {
        var generator = Obj(Items.Generator, 0, 0);
        var mill = Obj(Items.Mill, 1, 0);
        var grid = Grid([generator, mill], Fuelled(generator, Items.Wood, 5));
        Assert.Equal(0, grid.Clock(mill.Id).Speed(Start));
        Assert.Equal(Start, grid.Clock(mill.Id).At(Start + TimeSpan.FromMinutes(5)));

        // The generator gives nothing to nobody, so it keeps its wood.
        grid.Settle(Start + TimeSpan.FromMinutes(5));
        Assert.Equal(5, grid.Data.Generators[generator.Id].Fuel);
        Assert.Equal(TimeSpan.FromMinutes(5).Ticks, grid.Data.Lags[mill.Id]);
        Assert.Equal(Start, grid.Clock(mill.Id).At(Start + TimeSpan.FromMinutes(10)));
    }

    [Fact]
    public void Inserters_stand_still_without_power_and_swing_slower_on_too_little()
    {
        PlotObject[] Line(int y) => [Obj(Items.WoodenChest, 0, y), Obj(Items.Inserter, 1, y), Obj(Items.WoodenChest, 2, y)];
        (PlotLogistics, Dictionary<Guid, Contents>) Build(PlotObject[] line, PowerGrid grid)
        {
            var contents = new Dictionary<Guid, Contents> { [line[0].Id] = new() { Items = [new() { Item = Items.Stone, Quantity = 100 }] } };
            var ports = new Dictionary<Guid, IMachinePort>();
            foreach (var chest in new[] { line[0], line[2] })
            {
                contents.TryAdd(chest.Id, new Contents());
                ports[chest.Id] = new StoragePort(Storages.Find(chest.Kind)!, contents[chest.Id], () => { });
            }

            return (new PlotLogistics(line, contents, ports, grid), contents);
        }

        int Moved(Dictionary<Guid, Contents> contents, PlotObject chest) => contents[chest.Id].Items?.Sum(s => s.Quantity) ?? 0;

        var dark = Line(0);
        var (logistics, contents) = Build(dark, Grid(dark));
        logistics.Run(Start, Start + TimeSpan.FromMinutes(1));
        Assert.Equal(0, Moved(contents, dark[2]));

        // At full power one item takes 10 ticks: picking it up, 4 ticks over, dropping it, 4 ticks back.
        var lit = Line(0);
        var generator = Obj(Items.Generator, 1, 1);
        var pole = Obj(Items.Pole, 1, 2);
        (logistics, contents) = Build(lit, Grid([.. lit, generator, pole], Fuelled(generator, Items.Coal, 1)));
        logistics.Run(Start, Start + TimeSpan.FromSeconds(16));
        var full = Moved(contents, lit[2]);
        Assert.Equal(8, full);

        // Twenty-one inserters draw 105 kW from 100: each works at 95%.
        var crowd = Enumerable.Range(0, 20).Select(i => Obj(Items.Inserter, 10 + i % 4, i / 4)).ToList();
        var poles = new[] { Obj(Items.Pole, 1, 2), Obj(Items.Pole, 7, 2), Obj(Items.Pole, 11, 2) };
        (logistics, contents) = Build(lit, Grid([.. lit, generator, .. poles, .. crowd], Fuelled(generator, Items.Coal, 1)));
        logistics.Run(Start, Start + TimeSpan.FromSeconds(160));
        Assert.InRange(Moved(contents, lit[2]), 74, 77);
    }

    [Fact]
    public void An_inserter_feeds_coal_from_a_chest_to_the_generator_that_powers_it()
    {
        var chest = Obj(Items.WoodenChest, 0, 0);
        var inserter = Obj(Items.Inserter, 1, 0);
        var generator = Obj(Items.Generator, 2, 0);
        var pole = Obj(Items.Pole, 1, 1);
        PlotObject[] objects = [chest, inserter, generator, pole];
        var grid = Grid(objects, Fuelled(generator, Items.Wood, 1));
        var contents = new Dictionary<Guid, Contents> { [chest.Id] = new() { Items = [new() { Item = Items.Coal, Quantity = 80 }] } };
        var ports = new Dictionary<Guid, IMachinePort>
        {
            [chest.Id] = new StoragePort(Storages.Find(Items.WoodenChest)!, contents[chest.Id], () => { }),
            [generator.Id] = grid.Port(generator.Id)!,
        };

        new PlotLogistics(objects, contents, ports, grid).Run(Start, Start + TimeSpan.FromMinutes(10));

        Assert.True(grid.Changed);
        Assert.Equal(PowerRules.MaxFuel, grid.Generator(generator.Id, Start + TimeSpan.FromMinutes(10)).Fuel);
        Assert.Equal(30, contents[chest.Id].Items![0].Quantity);
    }

    [Fact]
    public void An_inserter_keeps_a_full_generator_fed_while_nobody_looks_at_the_plot()
    {
        var chest = Obj(Items.WoodenChest, 0, 0);
        var inserter = Obj(Items.Inserter, 1, 0);
        var generator = Obj(Items.Generator, 2, 0);
        var pole = Obj(Items.Pole, 1, 1);
        PlotObject[] objects = [chest, inserter, generator, pole];
        var grid = Grid(objects, Fuelled(generator, Items.WoodPellets, PowerRules.MaxFuel));
        var contents = new Dictionary<Guid, Contents> { [chest.Id] = new() { Items = [new() { Item = Items.WoodPellets, Quantity = 200 }] } };
        var ports = new Dictionary<Guid, IMachinePort>
        {
            [chest.Id] = new StoragePort(Storages.Find(Items.WoodenChest)!, contents[chest.Id], () => { }),
            [generator.Id] = grid.Port(generator.Id)!,
        };

        // The inserter alone draws 5 kW: a pellet (4,000 kJ) lasts 800 s, the full fire about 11 hours. A day later,
        // in one catch-up, it still burns, refilled piece by piece as each one was lit.
        var later = Start + TimeSpan.FromDays(1);
        new PlotLogistics(objects, contents, ports, grid).Run(Start, later);

        var fire = grid.Generator(generator.Id, later);
        Assert.True(fire.Running);
        Assert.InRange(fire.Fuel, PowerRules.MaxFuel - 1, PowerRules.MaxFuel);
        Assert.InRange(contents[chest.Id].Items![0].Quantity, 90, 95);
    }

    [Fact]
    public void A_busy_generator_is_fed_for_days_while_nobody_looks_at_the_plot()
    {
        var chest = Obj(Items.WoodenChest, 0, 0);
        var inserter = Obj(Items.Inserter, 1, 0);
        var generator = Obj(Items.Generator, 2, 0);
        var pole = Obj(Items.Pole, 1, 1);
        PlotObject[] mills = [Obj(Items.Mill, 0, 1), Obj(Items.Mill, 2, 1), Obj(Items.Mill, 1, 2)];
        PlotObject[] objects = [chest, inserter, generator, pole, .. mills];
        var grid = Grid(objects, Fuelled(generator, Items.WoodPellets, PowerRules.MaxFuel));
        var contents = new Dictionary<Guid, Contents> { [chest.Id] = new() { Items = [new() { Item = Items.WoodPellets, Quantity = 7000 }] } };
        var ports = new Dictionary<Guid, IMachinePort>
        {
            [chest.Id] = new StoragePort(Storages.Find(Items.WoodenChest)!, contents[chest.Id], () => { }),
            [generator.Id] = grid.Port(generator.Id)!,
        };

        // Three mills and the inserter draw 95 kW: a pellet lasts about 42 s, so in three days the inserter swings
        // thousands of times, far more than one catch-up's ticks of work without a pause.
        var later = Start + TimeSpan.FromDays(3);
        new PlotLogistics(objects, contents, ports, grid).Run(Start, later);

        var fire = grid.Generator(generator.Id, later);
        Assert.True(fire.Running);
        Assert.InRange(fire.Fuel, PowerRules.MaxFuel - 1, PowerRules.MaxFuel);
        // 3 days × 95 kW ÷ 4,000 kJ: 6,156 pellets lit.
        Assert.InRange(contents[chest.Id].Items![0].Quantity, 835, 850);
    }

    // --- In the game ---------------------------------------------------------------------------

    private async Task GiveAsync(GameClient client, string item, long quantity)
    {
        await using var scope = factory.Services.CreateAsyncScope();
        await scope.ServiceProvider.GetRequiredService<IInventory>().AddAsync(client.AccountId, item, quantity, CancellationToken.None);
    }

    private static (int X, int Y) FreePlot()
    {
        var skip = Interlocked.Increment(ref _plots) + 9000;
        var found = 0;
        for (var y = 0; y < Map.Height; y += 5)
        {
            for (var x = 0; x < Map.Width; x += 5)
            {
                if (Map.BiomeAt(x, y) == Biome.Grassland && found++ >= skip)
                {
                    return (x, y);
                }
            }
        }

        throw new InvalidOperationException("No such plot.");
    }

    /// <summary>A player with a plot that has three free tiles in a row from (tileX, tileY) east.</summary>
    private async Task<(GameClient Client, int X, int Y, int TileX, int TileY)> PlotAsync()
    {
        var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            await scope.ServiceProvider.GetRequiredService<IWallet>().CreditAsync(client.AccountId, 1_000_000, "test", CancellationToken.None);
        }

        var (x, y) = FreePlot();
        Assert.Equal("world.bought", (await client.SendAsync("world.buy", new { x, y })).Type());
        var plot = await client.SendAsync("plot.enter", new { x, y });
        using var gzip = new GZipStream(new MemoryStream(Convert.FromBase64String(plot.Payload().GetProperty("tiles").GetString()!)), CompressionMode.Decompress);
        using var tiles = new MemoryStream();
        gzip.CopyTo(tiles);
        var bytes = tiles.ToArray();
        for (var ty = 20; ty < PlotLayout.Size; ty++)
        {
            for (var tx = 0; tx + 4 <= PlotLayout.Size; tx++)
            {
                // Room for a 2 × 2 machine and a pole and a generator east of it.
                if (Enumerable.Range(tx, 4).All(i => bytes[ty * PlotLayout.Size + i] == (byte)TileObject.None && bytes[(ty + 1) * PlotLayout.Size + i] == (byte)TileObject.None))
                {
                    return (client, x, y, tx, ty);
                }
            }
        }

        throw new InvalidOperationException("No free row.");
    }

    private async Task<string> PlaceAsync(GameClient client, int x, int y, string kind, int tileX, int tileY)
    {
        await GiveAsync(client, kind, 1);
        var reply = await client.SendAsync("plot.place", new { x, y, kind, tileX, tileY });
        Assert.Equal("plot.placed", reply.Type());
        return reply.Payload().GetProperty("object").GetProperty("id").GetString()!;
    }

    private static int Flour(JsonElement machine) =>
        machine.GetProperty("output").ValueKind == JsonValueKind.Null ? 0 : machine.GetProperty("output").GetProperty("quantity").GetInt32();

    [Fact]
    public async Task A_mill_grinds_only_while_a_generator_on_a_pole_near_it_has_fuel()
    {
        var (client, x, y, tx, ty) = await PlotAsync();
        using var _ = client;
        var mill = await PlaceAsync(client, x, y, Items.Mill, tx, ty);
        await GiveAsync(client, Items.Wheat, 40);
        await client.SendAsync("machine.recipe", new { machine = mill, recipe = Items.Flour });
        var loaded = (await client.SendAsync("machine.load", new { machine = mill, item = Items.Wheat, quantity = 40 })).Payload();
        Assert.True(loaded.GetProperty("powered").GetBoolean());
        Assert.Equal(0, loaded.GetProperty("speed").GetDouble());

        factory.Time.Advance(TimeSpan.FromMinutes(1));
        Assert.Equal(0, Flour((await client.SendAsync("machine.get", new { machine = mill })).Payload()));
        var stall = Assert.Single((await client.SendAsync("stats.production", new { minutes = 10 })).Payload().GetProperty("stalls").EnumerateArray());
        Assert.Equal("no_power", stall.GetProperty("reason").GetString());

        // One wood is 5 MJ: 166.7 s for a mill drawing 30 kW, 27 batches of 6 s.
        await PlaceAsync(client, x, y, Items.Pole, tx + 2, ty);
        var generator = await PlaceAsync(client, x, y, Items.Generator, tx + 3, ty);
        await GiveAsync(client, Items.Wood, 1);
        Assert.Equal("not_fuel", (await client.SendAsync("generator.load", new { x, y, id = generator, item = Items.Stone, quantity = 1 })).ErrorCode());
        var fuelled = (await client.SendAsync("generator.load", new { x, y, id = generator, item = Items.Wood, quantity = 1 })).Payload();
        Assert.Equal(30, fuelled.GetProperty("outputKw").GetDouble());
        Assert.Equal(1, fuelled.GetProperty("network").GetProperty("machines").GetInt32());

        factory.Time.Advance(TimeSpan.FromSeconds(61));
        Assert.Equal(10, Flour((await client.SendAsync("machine.get", new { machine = mill })).Payload()));

        factory.Time.Advance(TimeSpan.FromHours(1));
        var state = (await client.SendAsync("machine.get", new { machine = mill })).Payload();
        Assert.Equal(20, Flour(state));
        Assert.Equal(0, state.GetProperty("speed").GetDouble());
        var logistics = (await client.SendAsync("logistics.get", new { x, y })).Payload().GetProperty("power").GetProperty("networks")[0];
        Assert.Equal(30, logistics.GetProperty("demandKw").GetDouble());
        Assert.Equal(0, logistics.GetProperty("supplyKw").GetDouble());

        // The statistics count flour when it was made on the plot, not in the mill's own time, which is a minute
        // behind: the first 10 sacks were made over an hour ago, the other 10 after them.
        async Task<long> Produced(int minutes) => (await client.SendAsync("stats.production", new { minutes })).Payload().GetProperty("items")
            .EnumerateArray().First(i => i.GetProperty("id").GetString() == Items.Flour).GetProperty("produced").GetInt64();
        Assert.Equal(10, await Produced(60));
        Assert.Equal(20, await Produced(1440));
    }

    [Fact]
    public async Task Fuel_comes_back_out_of_a_generator_and_with_it_when_it_is_picked_up()
    {
        var (client, x, y, tx, ty) = await PlotAsync();
        using var _ = client;
        var generator = await PlaceAsync(client, x, y, Items.Generator, tx, ty);
        await GiveAsync(client, Items.Coal, 12);
        await GiveAsync(client, Items.Wood, 1);
        Assert.Equal("generator", (await client.SendAsync("generator.load", new { x, y, id = generator, item = Items.Coal, quantity = 12 })).Type());
        Assert.Equal("generator_busy", (await client.SendAsync("generator.load", new { x, y, id = generator, item = Items.Wood, quantity = 1 })).ErrorCode());

        var taken = (await client.SendAsync("generator.take", new { x, y, id = generator })).Payload();
        Assert.Equal(12, taken.GetProperty("taken")[0].GetProperty("quantity").GetInt32());
        await client.SendAsync("generator.load", new { x, y, id = generator, item = Items.Coal, quantity = 5 });

        Assert.Equal("plot.pickedUp", (await client.SendAsync("plot.pickup", new { x, y, id = generator })).Type());
        var inventory = await client.InventoryAsync();
        Assert.Equal(12, inventory.GetValueOrDefault(Items.Coal));
        Assert.Equal(1, inventory.GetValueOrDefault(Items.Generator));
        Assert.Equal("no_object", (await client.SendAsync("generator.get", new { x, y, id = generator })).ErrorCode());
    }

    [Fact]
    public async Task Generators_and_poles_are_made_at_the_workbench_and_sold_by_the_trader()
    {
        var (client, _, _, _, _) = await PlotAsync();
        using var _ = client;
        var recipes = (await client.SendAsync("crafting.get")).Payload().GetProperty("recipes").EnumerateArray()
            .Select(r => r.GetProperty("id").GetString()).ToList();
        Assert.Contains(Items.Generator, recipes);
        Assert.Contains(Items.Pole, recipes);
        Assert.Equal("market.traded", (await client.SendAsync("market.buy", new { item = Items.Pole, quantity = 4 })).Type());
    }
}
