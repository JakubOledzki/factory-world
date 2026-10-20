using System.IO.Compression;
using System.Text.Json;
using FactoryWorld.Modules.Abstractions.Contracts;
using FactoryWorld.Modules.World;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Server.Tests;

public sealed class PlotTests(ServerFactory factory) : IClassFixture<ServerFactory>
{
    private static readonly WorldMap Map = WorldMap.Load();

    /// <summary>Plots of a biome nobody in this test class has used yet.</summary>
    private static readonly Dictionary<Biome, int> Used = [];

    private static (int X, int Y) FreePlot(Biome biome)
    {
        lock (Used)
        {
            var skip = Used.GetValueOrDefault(biome) + 1000;
            Used[biome] = Used.GetValueOrDefault(biome) + 1;
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
    }

    private async Task<GameClient> PlayerAsync(long cents = 1_000_000_00)
    {
        var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();
        await using var scope = factory.Services.CreateAsyncScope();
        await scope.ServiceProvider.GetRequiredService<IWallet>().CreditAsync(client.AccountId, cents, "test", CancellationToken.None);
        return client;
    }

    private static async Task<(int X, int Y)> BuyAsync(GameClient client, Biome biome)
    {
        var (x, y) = FreePlot(biome);
        var bought = await client.SendAsync("world.buy", new { x, y });
        Assert.Equal("world.bought", bought.Type());
        return (x, y);
    }

    private static async Task<(JsonElement Plot, byte[] Tiles)> EnterAsync(GameClient client, (int X, int Y) plot)
    {
        var reply = await client.SendAsync("plot.enter", new { x = plot.X, y = plot.Y });
        Assert.Equal("plot", reply.Type());
        using var gzip = new GZipStream(new MemoryStream(Convert.FromBase64String(reply.Payload().GetProperty("tiles").GetString()!)), CompressionMode.Decompress);
        using var tiles = new MemoryStream();
        gzip.CopyTo(tiles);
        return (reply.Payload(), tiles.ToArray());
    }

    private static (int X, int Y) Find(byte[] tiles, TileObject obj)
    {
        var i = Array.IndexOf(tiles, (byte)obj);
        Assert.True(i >= 0, $"No {obj} on the plot.");
        return (i % PlotLayout.Size, i / PlotLayout.Size);
    }

    private static string? Tool(JsonElement character) =>
        character.GetProperty("tool").ValueKind == JsonValueKind.Null ? null : character.GetProperty("tool").GetProperty("id").GetString();

    [Fact]
    public async Task A_forest_comes_with_an_axe_in_hand_and_the_next_tool_goes_to_the_inventory()
    {
        using var client = await PlayerAsync();
        await BuyAsync(client, Biome.Forest);
        Assert.Equal(Items.Axe, Tool((await client.SendAsync("character.get")).Payload()));

        var (x, y) = FreePlot(Biome.Desert);
        var desert = await client.SendAsync("world.buy", new { x, y });
        Assert.Equal(Items.Shovel, desert.Payload().GetProperty("tool").GetProperty("id").GetString());
        Assert.Equal(Items.Axe, Tool((await client.SendAsync("character.get")).Payload()));
        Assert.Equal(1, (await client.InventoryAsync())[Items.Shovel]);

        var (cx, cy) = FreePlot(Biome.City);
        var city = await client.SendAsync("world.buy", new { x = cx, y = cy });
        Assert.Equal(JsonValueKind.Null, city.Payload().GetProperty("tool").ValueKind);
    }

    [Fact]
    public async Task Equipping_swaps_the_tool_in_hand_with_one_from_the_inventory()
    {
        using var client = await PlayerAsync();
        await BuyAsync(client, Biome.Mountains);
        await BuyAsync(client, Biome.Desert);

        var swapped = await client.SendAsync("character.equip", new { item = Items.Shovel });
        Assert.Equal(Items.Shovel, Tool(swapped.Payload()));
        var inventory = await client.InventoryAsync();
        Assert.Equal(1, inventory[Items.Pickaxe]);
        Assert.False(inventory.ContainsKey(Items.Shovel));

        Assert.Equal("not_a_tool", (await client.SendAsync("character.equip", new { item = Items.Trash })).ErrorCode());
        Assert.Equal("not_enough_items", (await client.SendAsync("character.equip", new { item = Items.Axe })).ErrorCode());

        var empty = await client.SendAsync("character.unequip");
        Assert.Null(Tool(empty.Payload()));
        Assert.Equal(1, (await client.InventoryAsync())[Items.Shovel]);
    }

    [Fact]
    public async Task A_plot_has_its_biome_nature_a_railway_and_a_station_and_only_its_owner_may_enter()
    {
        using var owner = await PlayerAsync();
        var forest = await BuyAsync(owner, Biome.Forest);
        var (plot, tiles) = await EnterAsync(owner, forest);

        Assert.Equal(PlotLayout.Size * PlotLayout.Size, tiles.Length);
        Assert.Equal(20, plot.GetProperty("tileMeters").GetInt32());
        Assert.True(tiles.Count(t => t == (byte)TileObject.Tree) > tiles.Length / 5, "A forest is full of trees.");
        Assert.All(Enumerable.Range(0, PlotLayout.Size), x => Assert.Equal((byte)TileObject.Rail, tiles[PlotLayout.RailRow * PlotLayout.Size + x]));
        Assert.Contains((byte)TileObject.Station, tiles);

        var (_, again) = await EnterAsync(owner, forest);
        Assert.Equal(tiles, again);

        using var stranger = await PlayerAsync();
        Assert.Equal("not_owner", (await stranger.SendAsync("plot.enter", new { x = forest.X, y = forest.Y })).ErrorCode());
    }

    [Fact]
    public async Task Chopping_a_tree_needs_an_axe_gives_wood_and_removes_the_tree()
    {
        using var client = await PlayerAsync();
        var forest = await BuyAsync(client, Biome.Forest);
        var (_, tiles) = await EnterAsync(client, forest);
        var (tx, ty) = Find(tiles, TileObject.Tree);

        var chopped = await client.SendAsync("plot.harvest", new { x = forest.X, y = forest.Y, tileX = tx, tileY = ty });
        Assert.Equal("plot.harvested", chopped.Type());
        Assert.Equal(3, (await client.InventoryAsync())[Items.Wood]);

        factory.Time.Advance(HarvestRules.Time);
        Assert.Equal("nothing_here", (await client.SendAsync("plot.harvest", new { x = forest.X, y = forest.Y, tileX = tx, tileY = ty })).ErrorCode());
        var (_, after) = await EnterAsync(client, forest);
        Assert.Equal((byte)TileObject.None, after[ty * PlotLayout.Size + tx]);

        // Too quick after the last swing.
        var (nx, ny) = Find(after, TileObject.Tree);
        factory.Time.Advance(HarvestRules.Time);
        Assert.Equal("plot.harvested", (await client.SendAsync("plot.harvest", new { x = forest.X, y = forest.Y, tileX = nx, tileY = ny })).Type());
        var (mx, my) = Find((await EnterAsync(client, forest)).Tiles, TileObject.Tree);
        Assert.Equal("too_fast", (await client.SendAsync("plot.harvest", new { x = forest.X, y = forest.Y, tileX = mx, tileY = my })).ErrorCode());

        await client.SendAsync("character.unequip");
        factory.Time.Advance(HarvestRules.Time);
        Assert.Equal("wrong_tool", (await client.SendAsync("plot.harvest", new { x = forest.X, y = forest.Y, tileX = mx, tileY = my })).ErrorCode());
    }

    [Fact]
    public async Task Breaking_a_rock_with_a_pickaxe_gives_stone()
    {
        using var client = await PlayerAsync();
        var mountains = await BuyAsync(client, Biome.Mountains);
        var (tx, ty) = Find((await EnterAsync(client, mountains)).Tiles, TileObject.Rock);

        factory.Time.Advance(HarvestRules.Time);
        var broken = await client.SendAsync("plot.harvest", new { x = mountains.X, y = mountains.Y, tileX = tx, tileY = ty });

        Assert.Equal("plot.harvested", broken.Type());
        Assert.Equal(2, (await client.InventoryAsync())[Items.Stone]);
    }

    [Fact]
    public async Task Goods_go_by_train_to_another_players_station_for_a_fee()
    {
        using var sender = await PlayerAsync();
        var from = await BuyAsync(sender, Biome.Forest);
        var (_, tiles) = await EnterAsync(sender, from);
        var (tx, ty) = Find(tiles, TileObject.Tree);
        factory.Time.Advance(HarvestRules.Time);
        await sender.SendAsync("plot.harvest", new { x = from.X, y = from.Y, tileX = tx, tileY = ty });

        using var receiver = await PlayerAsync();
        var to = await BuyAsync(receiver, Biome.Grassland);

        var loaded = await sender.SendAsync("station.load", new { x = from.X, y = from.Y, item = Items.Wood, quantity = 3 });
        Assert.Equal(3, loaded.Payload().GetProperty("items")[0].GetProperty("quantity").GetInt64());
        Assert.False((await sender.InventoryAsync()).ContainsKey(Items.Wood));

        var balance = await sender.BalanceAsync();
        var sent = await sender.SendAsync("station.send", new { x = from.X, y = from.Y, toX = to.X, toY = to.Y, item = Items.Wood, quantity = 2 });
        Assert.Equal("station", sent.Type());
        Assert.Equal(1, sent.Payload().GetProperty("items")[0].GetProperty("quantity").GetInt64());
        Assert.Single(sent.Payload().GetProperty("outgoing").EnumerateArray());
        var km = RailRules.DistanceKm(Map, from.X, from.Y, to.X, to.Y);
        Assert.Equal(balance - RailRules.FeeCents(km, 2), await sender.BalanceAsync());

        var waiting = await receiver.SendAsync("station.get", new { x = to.X, y = to.Y });
        Assert.Equal(0, waiting.Payload().GetProperty("items").GetArrayLength());
        Assert.Single(waiting.Payload().GetProperty("incoming").EnumerateArray());

        factory.Time.Advance(RailRules.TripTime(km));
        var arrived = await receiver.SendAsync("station.get", new { x = to.X, y = to.Y });
        Assert.Equal(2, arrived.Payload().GetProperty("items")[0].GetProperty("quantity").GetInt64());
        Assert.Equal(0, arrived.Payload().GetProperty("incoming").GetArrayLength());

        await receiver.SendAsync("station.unload", new { x = to.X, y = to.Y, item = Items.Wood, quantity = 2 });
        Assert.Equal(2, (await receiver.InventoryAsync())[Items.Wood]);

        Assert.Equal("not_enough_items",
            (await sender.SendAsync("station.send", new { x = from.X, y = from.Y, toX = to.X, toY = to.Y, item = Items.Wood, quantity = 5 })).ErrorCode());
        Assert.Equal("not_owner", (await receiver.SendAsync("station.get", new { x = from.X, y = from.Y })).ErrorCode());
        var ocean = Map.PlotAt(0, -150);
        Assert.Equal("no_station",
            (await sender.SendAsync("station.send", new { x = from.X, y = from.Y, toX = ocean.X, toY = ocean.Y, item = Items.Wood, quantity = 1 })).ErrorCode());
    }
}
