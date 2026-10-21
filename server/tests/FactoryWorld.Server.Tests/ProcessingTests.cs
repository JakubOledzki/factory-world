using System.IO.Compression;
using System.Text.Json;
using FactoryWorld.Modules.Abstractions.Contracts;
using FactoryWorld.Modules.Crafting;
using FactoryWorld.Modules.World;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Server.Tests;

public sealed class ProcessingTests(ServerFactory factory) : IClassFixture<ServerFactory>
{
    private static readonly WorldMap Map = WorldMap.Load();
    private static int _plots;

    private async Task<GameClient> PlayerAsync()
    {
        var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();
        return client;
    }

    private async Task GiveAsync(GameClient client, string item, long quantity)
    {
        await using var scope = factory.Services.CreateAsyncScope();
        await scope.ServiceProvider.GetRequiredService<IInventory>().AddAsync(client.AccountId, item, quantity, CancellationToken.None);
    }

    private static long Count(Dictionary<string, long> inventory, string item) => inventory.GetValueOrDefault(item);

    private static (int X, int Y) FreePlot(Biome biome)
    {
        var skip = Interlocked.Increment(ref _plots) + 6000;
        var found = 0;
        for (var y = 0; y < Map.Height; y += 5)
        {
            for (var x = 0; x < Map.Width; x += 5)
            {
                if (Map.BiomeAt(x, y) == biome && found++ >= skip)
                {
                    return (x, y);
                }
            }
        }

        throw new InvalidOperationException("No such plot.");
    }

    /// <summary>Buys a plot and puts a machine of <paramref name="kind"/> on its first free tile.</summary>
    private async Task<(int X, int Y, string Id)> MachineOnPlotAsync(GameClient client, string kind)
    {
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            await scope.ServiceProvider.GetRequiredService<IWallet>().CreditAsync(client.AccountId, 1_000_000, "test", CancellationToken.None);
        }

        var (x, y) = FreePlot(Biome.Grassland);
        Assert.Equal("world.bought", (await client.SendAsync("world.buy", new { x, y })).Type());
        var plot = await client.SendAsync("plot.enter", new { x, y });
        using var gzip = new GZipStream(new MemoryStream(Convert.FromBase64String(plot.Payload().GetProperty("tiles").GetString()!)), CompressionMode.Decompress);
        using var tiles = new MemoryStream();
        gzip.CopyTo(tiles);
        var bytes = tiles.ToArray();
        var free = Enumerable.Range(PlotLayout.Size * 20, bytes.Length - PlotLayout.Size * 20).First(i => bytes[i] == (byte)TileObject.None);

        await GiveAsync(client, kind, 1);
        var placed = await client.SendAsync("plot.place", new { x, y, kind, tileX = free % PlotLayout.Size, tileY = free / PlotLayout.Size });
        Assert.Equal("plot.placed", placed.Type());
        return (x, y, placed.Payload().GetProperty("object").GetProperty("id").GetString()!);
    }

    [Fact]
    public async Task A_mill_grinds_two_wheat_into_one_flour_every_6_seconds()
    {
        using var client = await PlayerAsync();
        var (_, _, mill) = await MachineOnPlotAsync(client, Items.Mill);
        await GiveAsync(client, Items.Wheat, 7);

        Assert.Equal("no_recipe", (await client.SendAsync("machine.load", new { machine = mill, item = Items.Wheat, quantity = 7 })).ErrorCode());
        var set = (await client.SendAsync("machine.recipe", new { machine = mill, recipe = Items.Flour })).Payload();
        Assert.Equal(Items.Flour, set.GetProperty("recipe").GetString());
        Assert.False(set.GetProperty("fired").GetBoolean());
        Assert.Equal("no_recipe", (await client.SendAsync("machine.recipe", new { machine = mill, recipe = Items.Bread })).ErrorCode());

        var loaded = (await client.SendAsync("machine.load", new { machine = mill, item = Items.Wheat, quantity = 7 })).Payload();
        Assert.Equal(7, loaded.GetProperty("inputs")[0].GetProperty("quantity").GetInt32());
        Assert.Equal(3, loaded.GetProperty("batches").GetInt32());
        Assert.Equal(0, Count(await client.InventoryAsync(), Items.Wheat));

        factory.Time.Advance(TimeSpan.FromSeconds(13));
        var state = (await client.SendAsync("machine.get", new { machine = mill })).Payload();
        Assert.Equal(2, state.GetProperty("output").GetProperty("quantity").GetInt32());
        Assert.Equal(3, state.GetProperty("inputs")[0].GetProperty("quantity").GetInt32());

        factory.Time.Advance(TimeSpan.FromSeconds(60));
        var taken = (await client.SendAsync("machine.take", new { machine = mill, what = "output" })).Payload();
        Assert.Equal(3, taken.GetProperty("taken")[0].GetProperty("quantity").GetInt32());
        Assert.Equal(JsonValueKind.Null, taken.GetProperty("startedAt").ValueKind);
        var inventory = await client.InventoryAsync();
        Assert.Equal(3, Count(inventory, Items.Flour));

        // The odd wheat stays until taken out.
        await client.SendAsync("machine.take", new { machine = mill, what = "input" });
        Assert.Equal(1, Count(await client.InventoryAsync(), Items.Wheat));
    }

    [Fact]
    public async Task A_bakery_bakes_bread_only_while_it_has_fuel()
    {
        using var client = await PlayerAsync();
        var (_, _, bakery) = await MachineOnPlotAsync(client, Items.Bakery);
        await GiveAsync(client, Items.Flour, 10);
        await GiveAsync(client, Items.Wood, 1);
        await client.SendAsync("machine.recipe", new { machine = bakery, recipe = Items.Bread });

        var cold = (await client.SendAsync("machine.load", new { machine = bakery, item = Items.Flour, quantity = 10 })).Payload();
        Assert.Equal(JsonValueKind.Null, cold.GetProperty("startedAt").ValueKind);
        Assert.Equal("not_processable", (await client.SendAsync("machine.load", new { machine = bakery, item = Items.Stone, quantity = 1 })).ErrorCode());

        // One wood bakes one loaf.
        await client.SendAsync("machine.load", new { machine = bakery, item = Items.Wood, quantity = 1 });
        factory.Time.Advance(TimeSpan.FromSeconds(100));
        var state = (await client.SendAsync("machine.get", new { machine = bakery })).Payload();
        Assert.Equal(1, state.GetProperty("output").GetProperty("quantity").GetInt32());
        Assert.Equal(8, state.GetProperty("inputs")[0].GetProperty("quantity").GetInt32());
        Assert.Equal(JsonValueKind.Null, state.GetProperty("fuel").ValueKind);
        Assert.Equal(JsonValueKind.Null, state.GetProperty("startedAt").ValueKind);

        await GiveAsync(client, Items.Coal, 1);
        await client.SendAsync("machine.load", new { machine = bakery, item = Items.Coal, quantity = 1 });
        factory.Time.Advance(TimeSpan.FromSeconds(200));
        var after = (await client.SendAsync("machine.take", new { machine = bakery, what = "output" })).Payload();
        Assert.Equal(5, after.GetProperty("taken")[0].GetProperty("quantity").GetInt32());
        Assert.Equal(5, Count(await client.InventoryAsync(), Items.Bread));
    }

    [Fact]
    public async Task Changing_the_recipe_returns_ingredients_and_products()
    {
        using var client = await PlayerAsync();
        var (_, _, kitchen) = await MachineOnPlotAsync(client, Items.Kitchen);
        await GiveAsync(client, Items.Potato, 3);
        await GiveAsync(client, Items.SunflowerOil, 1);
        await GiveAsync(client, Items.Coal, 1);
        await client.SendAsync("machine.recipe", new { machine = kitchen, recipe = Items.Fries });
        await client.SendAsync("machine.load", new { machine = kitchen, item = Items.Potato, quantity = 3 });
        await client.SendAsync("machine.load", new { machine = kitchen, item = Items.SunflowerOil, quantity = 1 });
        await client.SendAsync("machine.load", new { machine = kitchen, item = Items.Coal, quantity = 1 });
        factory.Time.Advance(TimeSpan.FromSeconds(15));

        var changed = (await client.SendAsync("machine.recipe", new { machine = kitchen, recipe = Items.VegetableSoup })).Payload();

        Assert.Equal(Items.VegetableSoup, changed.GetProperty("recipe").GetString());
        Assert.Equal(3, changed.GetProperty("inputs").GetArrayLength());
        // The coal caught fire for the fries and still has heat for three more batches.
        Assert.Equal(JsonValueKind.Null, changed.GetProperty("fuel").ValueKind);
        Assert.Equal(3, changed.GetProperty("heat").GetInt32());
        var inventory = await client.InventoryAsync();
        Assert.Equal(2, Count(inventory, Items.Fries));
        Assert.Equal(0, Count(inventory, Items.Potato));
    }

    [Fact]
    public async Task Picking_up_a_machine_returns_what_it_holds_and_others_cannot_use_it()
    {
        using var client = await PlayerAsync();
        using var other = await PlayerAsync();
        var (x, y, press) = await MachineOnPlotAsync(client, Items.OilPress);
        await GiveAsync(client, Items.Sunflower, 5);
        await client.SendAsync("machine.recipe", new { machine = press, recipe = Items.SunflowerOil });
        await client.SendAsync("machine.load", new { machine = press, item = Items.Sunflower, quantity = 5 });
        factory.Time.Advance(TimeSpan.FromSeconds(10));

        Assert.Equal("no_object", (await other.SendAsync("machine.get", new { machine = press })).ErrorCode());
        Assert.Equal("plot.pickedUp", (await client.SendAsync("plot.pickup", new { x, y, id = press })).Type());

        var inventory = await client.InventoryAsync();
        Assert.Equal(1, Count(inventory, Items.OilPress));
        Assert.Equal(1, Count(inventory, Items.SunflowerOil));
        Assert.Equal(3, Count(inventory, Items.Sunflower));
    }

    [Fact]
    public async Task A_workbench_makes_the_machines_and_the_trader_deals_in_food()
    {
        using var client = await PlayerAsync();
        var recipes = (await client.SendAsync("crafting.get")).Payload().GetProperty("recipes").EnumerateArray()
            .Select(r => r.GetProperty("id").GetString()).ToHashSet();
        Assert.Superset(new HashSet<string?> { Items.Mill, Items.OilPress, Items.PicklingBarrel, Items.Bakery, Items.Kitchen }, recipes);

        await GiveAsync(client, Items.Bread, 2);
        var sold = await client.SendAsync("market.sell", new { item = Items.Bread, quantity = 2 });
        Assert.Equal("market.traded", sold.Type());
        Assert.Equal(1400, sold.Payload().GetProperty("balanceCents").GetInt64());
        Assert.Equal("market.traded", (await client.SendAsync("market.buy", new { item = Items.Flour, quantity = 3 })).Type());
        Assert.Equal(3, Count(await client.InventoryAsync(), Items.Flour));
    }

    [Fact]
    public void A_full_machine_stops_until_its_products_are_taken()
    {
        var barrel = Processing.ByKind[Items.PicklingBarrel];
        var start = DateTimeOffset.UnixEpoch;
        var s = Processing.Start(barrel, MachineState.Empty with { Recipe = Items.Sauerkraut, Inputs = [10], Output = Processing.MaxOutput - 4 }, start);

        var after = Processing.Advance(barrel, s, start + TimeSpan.FromMinutes(10));

        Assert.Equal(Processing.MaxOutput, after.Output);
        Assert.Equal(6, after.Inputs[0]);
        Assert.Null(after.StartedAt);
    }

    [Fact]
    public void Every_recipe_makes_a_known_item_from_known_items()
    {
        foreach (var machine in Processing.Machines)
        {
            Assert.True(Items.Exists(machine.Kind));
            Assert.Contains(machine.Kind, PlotObjects.Placeable);
            Assert.All(machine.Recipes, r =>
            {
                Assert.True(Items.Exists(r.Id));
                Assert.All(r.Ingredients, i => Assert.True(Items.Exists(i.Item)));
            });
        }
    }
}
