using System.IO.Compression;
using System.Text.Json;
using FactoryWorld.Modules.Abstractions.Contracts;
using FactoryWorld.Modules.Logistics;
using FactoryWorld.Modules.World;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Server.Tests;

public sealed class LogisticsTests(ServerFactory factory) : IClassFixture<ServerFactory>
{
    private static readonly WorldMap Map = WorldMap.Load();
    private static int _plots;

    // Rotations: 0 faces south, 1 east, 2 north, 3 west.
    private const int East = 1;
    private const int West = 3;

    // --- The rules, without a database ----------------------------------------------------------

    private static readonly DateTimeOffset Start = DateTimeOffset.UnixEpoch;

    private static PlotObject Obj(string kind, int x, int y, int rotation = East) =>
        new(Guid.NewGuid(), kind, x, y, rotation, Guid.Empty);

    private static (PlotLogistics Logistics, Dictionary<Guid, Contents> Contents) Build(
        IReadOnlyList<PlotObject> objects, Dictionary<Guid, Contents>? contents = null)
    {
        contents ??= [];
        var ports = new Dictionary<Guid, IMachinePort>();
        foreach (var o in objects)
        {
            if (Storages.Find(o.Kind) is { } kind)
            {
                if (!contents.TryGetValue(o.Id, out var c))
                {
                    contents[o.Id] = c = new Contents();
                }

                ports[o.Id] = new StoragePort(kind, c, () => { });
            }
        }

        return (new PlotLogistics(objects, contents, ports), contents);
    }

    private static int Stored(Contents c, string item) => c.Items?.FirstOrDefault(s => s.Item == item)?.Quantity ?? 0;

    [Fact]
    public void A_belt_moves_an_item_one_place_a_tick_onto_the_next_belt_and_stops_at_the_end()
    {
        var a = Obj(Items.Belt, 0, 0);
        var b = Obj(Items.Belt, 1, 0);
        var contents = new Dictionary<Guid, Contents> { [a.Id] = new() { Belt = [Items.Wood, null, null, null] } };
        var (logistics, _) = Build([a, b], contents);

        logistics.Run(Start, Start + LogisticsRules.Tick * 3);
        Assert.Equal(Items.Wood, contents[a.Id].Belt![3]);

        logistics.Run(Start, Start + LogisticsRules.Tick * 1);
        Assert.Equal(Items.Wood, contents[b.Id].Belt![0]);

        logistics.Run(Start, Start + LogisticsRules.Tick * 10);
        Assert.Equal(new string?[] { null, null, null, Items.Wood }, contents[b.Id].Belt!);
    }

    [Fact]
    public void Belts_facing_each_other_pass_nothing_but_one_from_the_side_feeds_into_the_middle()
    {
        var a = Obj(Items.Belt, 0, 0, East);
        var b = Obj(Items.Belt, 1, 0, West);
        var contents = new Dictionary<Guid, Contents> { [a.Id] = new() { Belt = [null, null, null, Items.Stone] } };
        Build([a, b], contents).Logistics.Run(Start, Start + TimeSpan.FromSeconds(5));
        Assert.Equal(Items.Stone, contents[a.Id].Belt![3]);

        var side = Obj(Items.Belt, 5, 4, 0);
        var line = Obj(Items.Belt, 5, 5, East);
        contents = new Dictionary<Guid, Contents> { [side.Id] = new() { Belt = [null, null, null, Items.Stone] } };
        Build([side, line], contents).Logistics.Run(Start, Start + LogisticsRules.Tick);
        Assert.Equal(Items.Stone, contents[line.Id].Belt![1]);
    }

    [Fact]
    public void A_full_line_of_belts_moves_together_and_waits_at_its_end()
    {
        var belts = Enumerable.Range(0, 3).Select(x => Obj(Items.Belt, x, 0)).ToList();
        var contents = belts.ToDictionary(b => b.Id, _ => new Contents { Belt = [Items.Coal, Items.Coal, Items.Coal, null] });
        var (logistics, _) = Build(belts, contents);

        logistics.Run(Start, Start + LogisticsRules.Tick);
        Assert.All(belts, b => Assert.Equal(new string?[] { null, Items.Coal, Items.Coal, Items.Coal }, contents[b.Id].Belt!));

        logistics.Run(Start, Start + TimeSpan.FromMinutes(1));
        Assert.Equal(9, belts.Sum(b => contents[b.Id].Belt!.Count(i => i is not null)));
        Assert.All(contents[belts[2].Id].Belt!, i => Assert.Equal(Items.Coal, i));
    }

    [Fact]
    public void Inserters_carry_from_chest_over_belts_to_another_chest_until_it_is_empty()
    {
        // chest → inserter → belt → belt → belt → inserter → chest, along a row.
        var from = Obj(Items.WoodenChest, 0, 0);
        var objects = new List<PlotObject> { from, Obj(Items.Inserter, 1, 0) };
        objects.AddRange(Enumerable.Range(2, 3).Select(x => Obj(Items.Belt, x, 0)));
        var to = Obj(Items.IronChest, 6, 0);
        objects.AddRange([Obj(Items.Inserter, 5, 0), to]);
        var contents = new Dictionary<Guid, Contents> { [from.Id] = new() { Items = [new() { Item = Items.Wood, Quantity = 20 }] } };
        var (logistics, _) = Build(objects, contents);

        var end = logistics.Run(Start, Start + TimeSpan.FromSeconds(5));
        Assert.Equal(Start + TimeSpan.FromSeconds(5), end);
        Assert.InRange(Stored(contents[from.Id], Items.Wood), 15, 18);
        Assert.InRange(Stored(contents[to.Id], Items.Wood), 0, 2);

        logistics.Run(end, end + TimeSpan.FromHours(5));
        Assert.Equal(0, Stored(contents[from.Id], Items.Wood));
        Assert.Equal(20, Stored(contents[to.Id], Items.Wood));
    }

    [Fact]
    public void An_inserter_picks_only_what_the_storage_in_front_takes()
    {
        var chest = Obj(Items.WoodenChest, 0, 0);
        var pile = Obj(Items.WoodPile, 2, 0);
        var contents = new Dictionary<Guid, Contents>
        {
            [chest.Id] = new() { Items = [new() { Item = Items.Stone, Quantity = 5 }, new() { Item = Items.Wood, Quantity = 3 }] },
        };
        Build([chest, Obj(Items.Inserter, 1, 0), pile], contents).Logistics.Run(Start, Start + TimeSpan.FromMinutes(5));

        Assert.Equal(5, Stored(contents[chest.Id], Items.Stone));
        Assert.Equal(3, Stored(contents[pile.Id], Items.Wood));
    }

    [Fact]
    public void An_inserter_takes_mixed_goods_out_of_a_chest_in_turn()
    {
        var chest = Obj(Items.WoodenChest, 0, 0);
        var belt = Obj(Items.Belt, 2, 0);
        var contents = new Dictionary<Guid, Contents>
        {
            [chest.Id] = new() { Items = [new() { Item = Items.IronOre, Quantity = 10 }, new() { Item = Items.Coal, Quantity = 10 }] },
        };
        Build([chest, Obj(Items.Inserter, 1, 0), belt], contents).Logistics.Run(Start, Start + TimeSpan.FromMinutes(5));

        // Four items fill the belt and a fifth waits in the inserter's hand: ore, coal, ore, coal, ore.
        Assert.Equal(7, Stored(contents[chest.Id], Items.IronOre));
        Assert.Equal(8, Stored(contents[chest.Id], Items.Coal));
    }

    [Fact]
    public void Storages_take_their_goods_up_to_their_size()
    {
        var heap = Storages.Find(Items.Heap)!;
        Assert.Equal(1000, Storages.Room(heap, [], Items.IronOre));
        Assert.Equal(0, Storages.Room(heap, [], Items.Wood));
        Assert.Equal(0, Storages.Room(heap, [new() { Item = Items.Coal, Quantity = 1 }], Items.Stone));

        var chest = Storages.Find(Items.WoodenChest)!;
        List<ItemStack> stacks = [new() { Item = Items.Wood, Quantity = 650 }];
        Assert.Equal(150, Storages.Room(chest, stacks, Items.Wood));
        Assert.Equal(100, Storages.Room(chest, stacks, Items.Stone));
    }

    // --- In the game ---------------------------------------------------------------------------

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

    private static (int X, int Y) FreePlot(Biome biome)
    {
        var skip = Interlocked.Increment(ref _plots) + 3000;
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

    /// <summary>A plot of the player's with <paramref name="length"/> free tiles in a row from (tileX, tileY) east.</summary>
    private async Task<(int X, int Y, int TileX, int TileY)> PlotWithFreeRowAsync(GameClient client, int length)
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
        for (var ty = 20; ty < PlotLayout.Size; ty++)
        {
            for (var tx = 0; tx + length <= PlotLayout.Size; tx++)
            {
                if (Enumerable.Range(tx, length).All(i => bytes[ty * PlotLayout.Size + i] == (byte)TileObject.None))
                {
                    return (x, y, tx, ty);
                }
            }
        }

        throw new InvalidOperationException("No free row.");
    }

    private static async Task<string> PlaceAsync(GameClient client, int x, int y, string kind, int tileX, int tileY, int rotation = East)
    {
        var reply = await client.SendAsync("plot.place", new { x, y, kind, tileX, tileY, rotation });
        Assert.Equal("plot.placed", reply.Type());
        return reply.Payload().GetProperty("object").GetProperty("id").GetString()!;
    }

    private static long StoredIn(JsonElement storage, string item) =>
        storage.GetProperty("items").EnumerateArray().Where(i => i.GetProperty("id").GetString() == item)
            .Sum(i => i.GetProperty("quantity").GetInt64());

    [Fact]
    public async Task Belts_inserters_and_storage_are_made_at_the_workbench()
    {
        using var client = await PlayerAsync();
        var crafting = await client.SendAsync("crafting.get");
        var recipes = crafting.Payload().GetProperty("recipes").EnumerateArray().Select(r => r.GetProperty("id").GetString()).ToList();
        Assert.Contains(Items.Belt, recipes);
        Assert.Contains(Items.Inserter, recipes);
        Assert.Contains(Items.WoodenChest, recipes);
        Assert.Contains(Items.IronChest, recipes);
        Assert.Contains(Items.WoodPile, recipes);
        Assert.Contains(Items.Heap, recipes);
        Assert.Contains(Items.GrainSilo, recipes);
    }

    [Fact]
    public async Task Objects_on_a_plot_keep_their_rotation_and_can_be_turned()
    {
        using var client = await PlayerAsync();
        var (x, y, tx, ty) = await PlotWithFreeRowAsync(client, 1);
        await GiveAsync(client, Items.Belt, 1);

        var belt = await PlaceAsync(client, x, y, Items.Belt, tx, ty, 2);
        var objects = (await client.SendAsync("plot.enter", new { x, y })).Payload().GetProperty("objects");
        Assert.Equal(2, objects[0].GetProperty("rotation").GetInt32());

        var turned = await client.SendAsync("plot.rotate", new { x, y, id = belt, rotation = 3 });
        Assert.Equal(3, turned.Payload().GetProperty("object").GetProperty("rotation").GetInt32());
        Assert.Equal("bad_rotation", (await client.SendAsync("plot.rotate", new { x, y, id = belt, rotation = 4 })).ErrorCode());
    }

    [Fact]
    public async Task A_chest_takes_items_in_and_gives_them_back_and_a_pile_takes_only_wood()
    {
        using var client = await PlayerAsync();
        var (x, y, tx, ty) = await PlotWithFreeRowAsync(client, 2);
        await GiveAsync(client, Items.WoodenChest, 1);
        await GiveAsync(client, Items.WoodPile, 1);
        await GiveAsync(client, Items.Wood, 30);
        await GiveAsync(client, Items.Stone, 10);
        var chest = await PlaceAsync(client, x, y, Items.WoodenChest, tx, ty);
        var pile = await PlaceAsync(client, x, y, Items.WoodPile, tx + 1, ty);

        var put = await client.SendAsync("storage.put", new { x, y, id = chest, item = Items.Stone, quantity = 10 });
        Assert.Equal("storage", put.Type());
        Assert.Equal(10, StoredIn(put.Payload(), Items.Stone));
        Assert.Equal("not_stored_here", (await client.SendAsync("storage.put", new { x, y, id = pile, item = Items.Stone, quantity = 1 })).ErrorCode());
        Assert.Equal("storage", (await client.SendAsync("storage.put", new { x, y, id = pile, item = Items.Wood, quantity = 30 })).Type());

        var taken = await client.SendAsync("storage.take", new { x, y, id = chest, item = Items.Stone, quantity = 4 });
        Assert.Equal(6, StoredIn(taken.Payload(), Items.Stone));
        var inventory = await client.InventoryAsync();
        Assert.Equal(4, inventory.GetValueOrDefault(Items.Stone));
        Assert.Equal(0, inventory.GetValueOrDefault(Items.Wood));

        // Picking a storage up hands back what is in it.
        Assert.Equal("plot.pickedUp", (await client.SendAsync("plot.pickup", new { x, y, id = pile })).Type());
        inventory = await client.InventoryAsync();
        Assert.Equal(30, inventory.GetValueOrDefault(Items.Wood));
        Assert.Equal(1, inventory.GetValueOrDefault(Items.WoodPile));
    }

    [Fact]
    public async Task Inserters_feed_a_furnace_from_a_chest_and_take_its_ingots_to_another_chest_while_the_player_is_away()
    {
        using var client = await PlayerAsync();
        using var other = await PlayerAsync();
        var (x, y, tx, ty) = await PlotWithFreeRowAsync(client, 5);
        await GiveAsync(client, Items.WoodenChest, 2);
        await GiveAsync(client, Items.Inserter, 2);
        await GiveAsync(client, Items.Furnace, 1);
        await GiveAsync(client, Items.IronOre, 10);
        await GiveAsync(client, Items.Coal, 2);

        // chest → inserter → furnace → inserter → chest
        var source = await PlaceAsync(client, x, y, Items.WoodenChest, tx, ty);
        await PlaceAsync(client, x, y, Items.Inserter, tx + 1, ty);
        var furnace = await PlaceAsync(client, x, y, Items.Furnace, tx + 2, ty);
        await PlaceAsync(client, x, y, Items.Inserter, tx + 3, ty);
        var target = await PlaceAsync(client, x, y, Items.WoodenChest, tx + 4, ty);
        await client.SendAsync("storage.put", new { x, y, id = source, item = Items.IronOre, quantity = 10 });
        await client.SendAsync("storage.put", new { x, y, id = source, item = Items.Coal, quantity = 2 });

        factory.Time.Advance(TimeSpan.FromHours(3));
        var logistics = await client.SendAsync("logistics.get", new { x, y });
        Assert.Equal("logistics", logistics.Type());
        var storages = logistics.Payload().GetProperty("storages").EnumerateArray().ToDictionary(s => s.GetProperty("id").GetString()!);
        Assert.Equal(10, StoredIn(storages[target], Items.IronIngot));
        Assert.Equal(0, StoredIn(storages[source], Items.IronOre));
        Assert.Equal(0, StoredIn(storages[source], Items.Coal));
        var left = await client.SendAsync("furnace.get", new { furnace });
        Assert.Equal(0, left.Payload().GetProperty("fuel").GetInt32());
        Assert.Equal(JsonValueKind.Null, left.Payload().GetProperty("output").ValueKind);

        Assert.Equal("not_owner", (await other.SendAsync("logistics.get", new { x, y })).ErrorCode());
        Assert.Equal("not_owner", (await other.SendAsync("storage.take", new { x, y, id = target, item = Items.IronIngot, quantity = 0 })).ErrorCode());

        var taken = await client.SendAsync("storage.take", new { x, y, id = target, item = Items.IronIngot, quantity = 0 });
        Assert.Equal(0, StoredIn(taken.Payload(), Items.IronIngot));
        Assert.Equal(10, (await client.InventoryAsync()).GetValueOrDefault(Items.IronIngot));
    }

    [Fact]
    public async Task Picking_up_a_belt_or_inserter_gives_back_what_it_carries()
    {
        using var client = await PlayerAsync();
        var (x, y, tx, ty) = await PlotWithFreeRowAsync(client, 3);
        await GiveAsync(client, Items.WoodenChest, 1);
        await GiveAsync(client, Items.Inserter, 1);
        await GiveAsync(client, Items.Belt, 1);
        await GiveAsync(client, Items.Stone, 3);
        var chest = await PlaceAsync(client, x, y, Items.WoodenChest, tx, ty);
        var inserter = await PlaceAsync(client, x, y, Items.Inserter, tx + 1, ty);
        var belt = await PlaceAsync(client, x, y, Items.Belt, tx + 2, ty);
        await client.SendAsync("storage.put", new { x, y, id = chest, item = Items.Stone, quantity = 3 });

        factory.Time.Advance(TimeSpan.FromMinutes(1));
        var belts = (await client.SendAsync("logistics.get", new { x, y })).Payload().GetProperty("belts");
        Assert.Equal(3, belts[0].GetProperty("items").EnumerateArray().Count(i => i.ValueKind == JsonValueKind.String));

        Assert.Equal("plot.pickedUp", (await client.SendAsync("plot.pickup", new { x, y, id = belt })).Type());
        Assert.Equal("plot.pickedUp", (await client.SendAsync("plot.pickup", new { x, y, id = inserter })).Type());
        var inventory = await client.InventoryAsync();
        Assert.Equal(3, inventory.GetValueOrDefault(Items.Stone));
        Assert.Equal(1, inventory.GetValueOrDefault(Items.Belt));
        Assert.Equal(1, inventory.GetValueOrDefault(Items.Inserter));
    }
}
