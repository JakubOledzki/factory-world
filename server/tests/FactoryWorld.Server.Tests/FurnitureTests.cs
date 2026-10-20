using System.Text.Json;
using FactoryWorld.Modules.Recycling;

namespace FactoryWorld.Server.Tests;

public sealed class FurnitureTests(ServerFactory factory) : IClassFixture<ServerFactory>
{
    private static JsonElement Find(JsonElement garage, string kind) =>
        garage.Payload().GetProperty("objects").EnumerateArray().First(o => o.GetProperty("kind").GetString() == kind);

    [Fact]
    public void Starter_furniture_fits_in_the_room_without_overlapping()
    {
        var starter = GarageLayout.Starter;
        foreach (var (kind, x, y) in starter)
        {
            Assert.True(GarageLayout.InsideRoom(kind, x, y), kind);
        }

        for (var i = 0; i < starter.Length; i++)
        {
            for (var j = i + 1; j < starter.Length; j++)
            {
                var (a, b) = (starter[i], starter[j]);
                Assert.False(GarageLayout.Overlaps(a.Kind, a.X, a.Y, b.Kind, b.X, b.Y), $"{a.Kind} / {b.Kind}");
            }
        }
    }

    [Fact]
    public async Task New_garage_is_furnished_once()
    {
        using var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();

        var garage = await client.SendAsync("garage.get");
        var again = await client.SendAsync("garage.get");

        Assert.Equal(GarageLayout.Starter.Length, garage.Payload().GetProperty("objects").GetArrayLength());
        Assert.Equal(GarageLayout.Starter.Length, again.Payload().GetProperty("objects").GetArrayLength());
        Assert.Equal(8.0, garage.Payload().GetProperty("room").GetProperty("width").GetDouble());
        Assert.True(garage.Payload().GetProperty("furniture").TryGetProperty("furniture_trash_bin", out _));
    }

    [Fact]
    public async Task Furniture_can_be_picked_up_and_placed_elsewhere()
    {
        using var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();
        var garage = await client.SendAsync("garage.get");
        var tyres = Find(garage, "furniture_tyres");

        var picked = await client.SendAsync("garage.pickup", new { id = tyres.GetProperty("id").GetGuid() });
        Assert.Equal(GarageLayout.Starter.Length - 1, picked.Payload().GetProperty("objects").GetArrayLength());
        Assert.Equal(1, (await client.InventoryAsync())["furniture_tyres"]);

        var placed = await client.SendAsync("garage.place", new { kind = "furniture_tyres", x = 4.0, y = 1.0 });
        var moved = Find(placed, "furniture_tyres");
        Assert.Equal(4.0, moved.GetProperty("x").GetDouble());
        Assert.False((await client.InventoryAsync()).ContainsKey("furniture_tyres"));
    }

    [Fact]
    public async Task Furniture_cannot_overlap_or_leave_the_room_or_be_placed_twice()
    {
        using var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();
        var garage = await client.SendAsync("garage.get");
        await client.SendAsync("garage.pickup", new { id = Find(garage, "furniture_gas_cylinder").GetProperty("id").GetGuid() });

        // On top of the trash bin, half outside the wall, then fine.
        Assert.Equal("blocked", (await client.SendAsync("garage.place", new { kind = "furniture_gas_cylinder", x = 2.6, y = 4.2 })).ErrorCode());
        Assert.Equal("bad_position", (await client.SendAsync("garage.place", new { kind = "furniture_gas_cylinder", x = 0.05, y = 3.0 })).ErrorCode());
        Assert.Equal("garage", (await client.SendAsync("garage.place", new { kind = "furniture_gas_cylinder", x = 4.0, y = 3.0 })).Type());
        // It is no longer in the inventory.
        Assert.Equal("not_enough_items", (await client.SendAsync("garage.place", new { kind = "furniture_gas_cylinder", x = 5.0, y = 3.0 })).ErrorCode());
        Assert.Equal("not_placeable", (await client.SendAsync("garage.place", new { kind = "trash", x = 5.0, y = 3.0 })).ErrorCode());
        Assert.Equal("no_object", (await client.SendAsync("garage.pickup", new { id = Guid.NewGuid() })).ErrorCode());
    }

    [Fact]
    public async Task Sorting_needs_the_bin_in_the_garage()
    {
        using var client = await factory.ConnectAsync();
        await client.RegisterWithCharacterAsync();
        var garage = await client.SendAsync("garage.get");
        await client.SendAsync("garage.pickup", new { id = Find(garage, "furniture_trash_bin").GetProperty("id").GetGuid() });

        Assert.Equal("no_bin", (await client.SendAsync("recycling.sort", new { count = 1 })).ErrorCode());

        await client.SendAsync("garage.place", new { kind = "furniture_trash_bin", x = 4.0, y = 3.0 });
        Assert.Equal("garage", (await client.SendAsync("recycling.sort", new { count = 1 })).Type());
    }

    [Fact]
    public async Task Players_cannot_pick_up_each_others_furniture()
    {
        using var owner = await factory.ConnectAsync();
        await owner.RegisterWithCharacterAsync();
        var id = Find(await owner.SendAsync("garage.get"), "furniture_pallet").GetProperty("id").GetGuid();

        using var thief = await factory.ConnectAsync();
        await thief.RegisterWithCharacterAsync();

        Assert.Equal("no_object", (await thief.SendAsync("garage.pickup", new { id })).ErrorCode());
    }
}
