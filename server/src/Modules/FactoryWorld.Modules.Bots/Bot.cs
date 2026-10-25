using System.IO.Compression;
using System.Text.Json;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.Logging;

namespace FactoryWorld.Modules.Bots;

/// <summary>What one step of a bot happens in: the time and the dice.</summary>
/// <remarks>
/// A bot does not hold back for the XP cap: it keeps working and trading, and the engine cuts whatever it earns
/// over the cap away after the step. Bots that stopped short of the cap (as they used to) did nothing at all
/// once they caught up with the best player, so nothing reached the market.
/// </remarks>
public sealed record BotWorld(DateTimeOffset Now, Random Random);

/// <summary>A plot the bot owns, with what it has seen on it this session.</summary>
internal sealed class BotPlot(int x, int y, int biome)
{
    public int X { get; } = x;

    public int Y { get; } = y;

    public int Biome { get; } = biome;

    /// <summary>Tiles as plot.enter sent them; null until the bot has been on the plot this session.</summary>
    public byte[]? Tiles { get; set; }

    public int Size { get; set; }

    public (int X, int Y) Spawn { get; set; }

    /// <summary>Tiles with something to gather, nearest to the spawn first.</summary>
    public List<(int X, int Y)> Targets { get; } = [];

    /// <summary>Tiles found empty, nearest first, for fields and saplings.</summary>
    public List<(int X, int Y)> Free { get; } = [];

    public List<(int Id, int Units, DateTimeOffset? RefillAt, long UpgradeIron, long UpgradeWood, bool Upgradable)> Mines { get; } = [];

    public List<(int X, int Y, string? Crop, DateTimeOffset? ReadyAt)> Fields { get; } = [];

    public int Planted { get; set; }

    /// <summary>What stands on the plot (workbenches, furnaces, chests...), as plot.enter sent it.</summary>
    public List<(Guid Id, string Kind)> Objects { get; } = [];
}

/// <summary>
/// One bot: plays through <see cref="BotClient"/> like a player at the keyboard would, one action per step.
/// It remembers between steps what it saw (its inventory, its plots, the prices) and refreshes all of it
/// when a session starts. Every action that gives XP is skipped while it would carry the bot over its cap.
/// </summary>
/// <param name="grant">Credits the bot's wallet with this many cents (the server's allowance, see <see cref="BotRules.Allowance"/>).</param>
public sealed class Bot(BotProfile profile, BotRow row, BotClient client, ILogger logger, Func<long, CancellationToken, Task>? grant = null)
{
    private readonly Dictionary<string, long> _inventory = new(StringComparer.Ordinal);
    private readonly List<BotPlot> _plots = [];
    private readonly Dictionary<string, long> _floor = new(StringComparer.Ordinal);
    private readonly Dictionary<string, long> _traderSells = new(StringComparer.Ordinal);
    private readonly Dictionary<string, (long Xp, List<(string Item, long Quantity)> Ingredients, bool Locked, string Station)> _recipes = new(StringComparer.Ordinal);
    private readonly Dictionary<string, (string Status, long Xp, List<(string Item, long Quantity)> Cost)> _techs = new(StringComparer.Ordinal);
    private readonly Dictionary<string, (int Width, int Depth)> _footprints = new(StringComparer.Ordinal);
    private readonly List<(string Kind, int X, int Y, int Rotation)> _garage = [];

    private bool _fresh;
    private bool _broken;
    private long _xp;
    private long _money;
    private List<string> _tools = [];
    private int _mapWidth;
    private int _mapHeight;
    private long _nextPlotBaseCents;
    private readonly Dictionary<int, double> _priceFactors = [];
    private Guid? _workbench;
    private Guid? _furnace;
    private bool _bin;
    private int _sortQueue;
    private DateTimeOffset _sortDoneAt;
    private int _craftQueue;
    private int _openListings;
    private int _openOrders;
    private DateTimeOffset _lastListingAt;
    private readonly List<(long Id, string Item, bool Sold)> _listings = [];
    private int _searchRadius;
    private int _purchases;
    private int _steps;

    public BotProfile Profile { get; } = profile;

    public BotRow Row { get; } = row;

    public BotClient Client { get; } = client;

    /// <summary>The bot's XP as it last saw it.</summary>
    public long Xp => _xp;

    /// <summary>The session ended: whatever was seen is stale, and the next step looks around again first.</summary>
    public void EndSession()
    {
        _fresh = false;
        _purchases = 0;
        foreach (var plot in _plots)
        {
            plot.Tiles = null;
        }
    }

    /// <summary>One action, like a player's click; nothing when there is nothing worth doing.</summary>
    public async Task<string?> StepAsync(BotWorld world, CancellationToken cancellationToken)
    {
        if (_broken)
        {
            return null;
        }

        if (!_fresh)
        {
            await RefreshAsync(cancellationToken);
            if (_broken)
            {
                return null;
            }
        }

        // Money also comes without a reply that shows it (tutorial rewards, sales to other players), so look now and then.
        // Listings sell while the bot is busy elsewhere, so it looks at its offers then too.
        if (++_steps % 10 == 0)
        {
            _money = (await SendAsync("wallet.get", null, cancellationToken)).Payload.Long("balanceCents");
            await MyOffersAsync(cancellationToken);
        }

        var candidates = Candidates(world);
        if (candidates.Count == 0)
        {
            return null;
        }

        var total = candidates.Sum(c => c.Weight);
        var roll = world.Random.Next(total);
        foreach (var (weight, name, run) in candidates)
        {
            roll -= weight;
            if (roll < 0)
            {
                var done = await run(cancellationToken);
                return done ? name : null;
            }
        }

        return null;
    }

    private long Have(string item) => _inventory.GetValueOrDefault(item);

    private long Floor(string item) => _floor.GetValueOrDefault(item);

    private bool Has(IEnumerable<(string Item, long Quantity)> cost) => cost.All(c => Have(c.Item) >= c.Quantity);

    /// <summary>Everything the bot could do now, with how likely it is to pick each.</summary>
    private List<(int Weight, string Name, Func<CancellationToken, Task<bool>> Run)> Candidates(BotWorld world)
    {
        var trade = Profile.Trade;
        var list = new List<(int, string, Func<CancellationToken, Task<bool>>)>();
        void Add(int weight, string name, Func<CancellationToken, Task<bool>> run) => list.Add((weight, name, run));

        if (_sortQueue > 0 && _sortDoneAt <= world.Now)
        {
            Add(12, "garage", GarageAsync);
        }

        if (_sortQueue == 0 && _bin && Have(Items.Trash) > 0)
        {
            Add(_plots.Count == 0 ? 10 : 4, "sort", SortAsync);
        }

        if (Have(Items.Trash) < 5 && _sortQueue == 0 && _money >= 40_00 && _traderSells.ContainsKey(Items.Trash))
        {
            Add(3, "buy trash", ct => TradeAsync("market.buy", Items.Trash, 20, ct));
        }

        var waste = BotRules.Waste.FirstOrDefault(w => Have(w) >= 10);
        if (waste is not null)
        {
            Add(8, "sell waste", ct => TradeAsync("market.sell", waste, Have(waste), ct));
        }

        if (_plots.Count < BotRules.MaxPlots(trade) && _mapWidth > 0)
        {
            var biomes = BotRules.PlotBiomes(trade, _plots.Count);
            var cheapest = biomes.Min(b => PlotPrice(b));
            if (_money >= cheapest + BotRules.Reserve)
            {
                // The first plot is what a new player saves up for.
                Add(_plots.Count == 0 ? 40 : 10, "buy plot", ct => BuyPlotAsync(biomes, ct));
            }
        }

        var ore = BotRules.Ores.FirstOrDefault(o => Have(o) >= 5);
        foreach (var plot in _plots)
        {
            var mine = plot.Biome == Biomes.Mountains || plot.Biome == Biomes.Forest || plot.Biome == Biomes.Desert || plot.Biome == Biomes.Farmland;
            if (!mine)
            {
                continue;
            }

            var own = plot.Biome switch
            {
                Biomes.Forest => trade is BotTrade.Forester or BotTrade.Industrialist or BotTrade.Trader,
                Biomes.Mountains => trade is BotTrade.Miner or BotTrade.Industrialist,
                Biomes.Farmland => trade is BotTrade.Farmer,
                _ => false,
            };
            Add(own ? 16 : 6, "work plot", ct => WorkPlotAsync(plot, world, ct));

            if (plot.Biome is Biomes.Forest or Biomes.Farmland && Have(Items.Sapling) > 0 && plot.Planted < BotRules.MaxPlanted)
            {
                Add(trade == BotTrade.Forester ? 5 : 2, "plant tree", ct => PlantTreeAsync(plot, world, ct));
            }

            foreach (var kind in plot.Tiles is null ? [] : StillToBuild(plot))
            {
                if (Have(kind) > 0 && plot.Free.Count > 0)
                {
                    Add(6, "build", ct => BuildAsync(plot, kind, ct));
                    break;
                }

                if (_workbench is not null && _craftQueue < 5 && !IsLocked(kind) && Has(Recipe(kind)))
                {
                    Add(4, "craft to build", ct => CraftAsync(kind, ct));
                    break;
                }
            }

            foreach (var (id, kind) in plot.Objects)
            {
                if (kind == Items.Furnace)
                {
                    Add(ore is not null && Have(Items.Coal) >= 1 ? 6 : 2, "plot furnace", ct => FurnaceAsync(id, world, ct));
                }
            }

            if (plot.Biome == Biomes.Mountains && plot.Mines.Any(m => m.Upgradable && Have(Items.IronIngot) >= m.UpgradeIron && Have(Items.Wood) >= m.UpgradeWood))
            {
                Add(4, "upgrade mine", ct => UpgradeMineAsync(plot, ct));
            }
        }

        if (_furnace is { } furnace)
        {
            Add(ore is not null && Have(Items.Coal) >= 1 ? 8 : 5, "furnace", ct => FurnaceAsync(furnace, world, ct));
        }
        else if (Have(Items.Furnace) > 0)
        {
            Add(10, "place furnace", ct => PlaceInGarageAsync(Items.Furnace, ct));
        }
        else if (ore is not null && _workbench is not null && _craftQueue < 5 && Has(Recipe(Items.Furnace)) && !IsLocked(Items.Furnace))
        {
            Add(8, "craft furnace", ct => CraftAsync(Items.Furnace, ct));
        }

        if (_workbench is not null && _craftQueue < 5)
        {
            foreach (var product in BotRules.Products(trade))
            {
                if (!IsLocked(product) && Has(Recipe(product)) && Have(product) < 20)
                {
                    Add(5, "craft", ct => CraftAsync(product, ct));
                    break;
                }
            }
        }

        if (_craftQueue > 0)
        {
            Add(2, "collect crafting", CraftingAsync);
        }

        foreach (var tech in BotRules.Research(trade))
        {
            if (_techs.TryGetValue(tech, out var t) && t.Status == "available" && Has(t.Cost))
            {
                Add(4, "research", ct => ResearchAsync(tech, ct));
                break;
            }
        }

        if (_techs.Values.Any(t => t.Status == "active"))
        {
            Add(1, "check research", ct => ParseResearchAsync(ct));
        }

        if (_openListings < BotRules.MaxListings && _lastListingAt + BotRules.ListEvery <= world.Now && Surplus().Any())
        {
            Add(trade == BotTrade.Trader ? 10 : 7, "list", ct => ListAsync(world, ct));
        }

        if (_openListings >= BotRules.MaxListings && _lastListingAt + BotRules.RelistAfter <= world.Now && _listings.Any(l => !l.Sold))
        {
            Add(3, "relist", ct => UnlistOldestAsync(world, ct));
        }

        var glut = Surplus().FirstOrDefault(s => s.Quantity >= 150 && Floor(s.Item) > 0).Item;
        if (glut is not null)
        {
            Add(3, "quick sale", ct => TradeAsync("market.sell", glut, 50, ct));
        }

        if (_money > BotRules.Reserve + 5_00 && _purchases < BotRules.MaxPurchases)
        {
            Add(trade switch { BotTrade.Trader => 10, BotTrade.Industrialist => 8, _ => 6 }, "shop", ct => ShopAsync(world, ct));
        }

        Add(4, "fill order", ct => FillOrderAsync(world, ct));

        if (_openOrders < BotRules.MaxOrders && _money > BotRules.Reserve + 50_00 && BotRules.Buys(trade).Length > 0)
        {
            Add(2, "place order", ct => PlaceOrderAsync(world, ct));
        }

        Add(6, "contracts", ct => ContractsAsync(world, ct));

        return list;
    }

    // ----- Looking around -----

    /// <summary>What a player sees when they log in: character, garage, inventory, wallet, plots, prices.</summary>
    private async Task RefreshAsync(CancellationToken cancellationToken)
    {
        var character = await SendAsync("character.get", null, cancellationToken);
        if (!character.Is("character"))
        {
            logger.LogWarning("Bot {Bot} has no character; it stays idle", Row.CharacterName);
            _broken = true;
            return;
        }

        _tools = Tools(character.Payload);
        await GarageAsync(cancellationToken);
        await CraftingAsync(cancellationToken);
        await ParseResearchAsync(cancellationToken);

        var info = await SendAsync("world.info", null, cancellationToken);
        if (info.Ok)
        {
            _mapWidth = (int)info.Payload.Long("width");
            _mapHeight = (int)info.Payload.Long("height");
            _nextPlotBaseCents = info.Payload.Long("nextBasePriceCents");
            _priceFactors.Clear();
            foreach (var biome in info.Payload.Each("biomes"))
            {
                if (biome.True("buyable"))
                {
                    _priceFactors[(int)biome.Long("id")] = biome.Double("priceFactor");
                }
            }

            var known = _plots.ToDictionary(p => (p.X, p.Y));
            foreach (var plot in info.Payload.Each("plots"))
            {
                var key = ((int)plot.Long("x"), (int)plot.Long("y"));
                if (!known.ContainsKey(key))
                {
                    _plots.Add(new BotPlot(key.Item1, key.Item2, (int)plot.Long("biome")));
                }
            }
        }

        var prices = await SendAsync("market.prices", null, cancellationToken);
        if (prices.Ok)
        {
            _floor.Clear();
            _traderSells.Clear();
            foreach (var item in prices.Payload.Each("items"))
            {
                var id = item.Text("id")!;
                if (item.LongOrNull("sellCents") is { } floor)
                {
                    _floor[id] = floor;
                }

                if (item.LongOrNull("buyCents") is { } sells && item.Text("locked") is null)
                {
                    _traderSells[id] = sells;
                }
            }
        }

        await InventoryAsync(cancellationToken);
        var wallet = await SendAsync("wallet.get", null, cancellationToken);
        _money = wallet.Payload.Long("balanceCents");
        await AllowanceAsync(cancellationToken);
        await MyOffersAsync(cancellationToken);

        // Everything that is already finished has been handed out above.
        var again = await SendAsync("character.get", null, cancellationToken);
        _xp = again.Payload.Long("xp");
        _fresh = true;
    }

    private async Task<bool> GarageAsync(CancellationToken cancellationToken)
    {
        var reply = await SendAsync("garage.get", null, cancellationToken);
        if (!reply.Is("garage"))
        {
            return false;
        }

        ParseGarage(reply.Payload);
        return true;
    }

    private void ParseGarage(JsonElement garage)
    {
        var queue = garage.Each("queue").Select(q => q.GetInt64()).ToList();
        _sortQueue = queue.Count;
        _sortDoneAt = queue.Count > 0 ? DateTimeOffset.FromUnixTimeMilliseconds(queue.Min()) : default;
        _inventory[Items.Trash] = garage.Long("trash");
        _garage.Clear();
        _workbench = null;
        _furnace = null;
        _bin = false;
        foreach (var o in garage.Each("objects"))
        {
            var kind = o.Text("kind")!;
            _garage.Add((kind, (int)o.Long("x"), (int)o.Long("y"), (int)o.Long("rotation")));
            switch (kind)
            {
                case Items.Workbench:
                    _workbench ??= o.Id("id");
                    break;
                case Items.Furnace:
                    _furnace ??= o.Id("id");
                    break;
                case Items.TrashBin:
                    _bin = true;
                    break;
            }
        }

        if (garage.Get("furniture") is { ValueKind: JsonValueKind.Object } furniture)
        {
            _footprints.Clear();
            foreach (var f in furniture.EnumerateObject())
            {
                _footprints[f.Name] = ((int)f.Value.Long("width"), (int)f.Value.Long("depth"));
            }
        }

        foreach (var result in garage.Each("results"))
        {
            var id = result.Text("id")!;
            _inventory[id] = Have(id) + 1;
        }
    }

    private async Task<bool> CraftingAsync(CancellationToken cancellationToken)
    {
        var reply = await SendAsync("crafting.get", null, cancellationToken);
        if (!reply.Is("crafting"))
        {
            return false;
        }

        ParseCrafting(reply.Payload);
        if (reply.Payload.Each("done").Any())
        {
            await InventoryAsync(cancellationToken);
        }

        return true;
    }

    private void ParseCrafting(JsonElement crafting)
    {
        _recipes.Clear();
        foreach (var r in crafting.Each("recipes"))
        {
            _recipes[r.Text("id")!] = (
                r.Long("xp"),
                r.Each("ingredients").Select(i => (i.Text("id")!, i.Long("quantity"))).ToList(),
                r.Text("locked") is not null,
                r.Text("station") ?? Items.Workbench);
        }

        _craftQueue = crafting.Each("queue").Count();
    }

    private IEnumerable<(string Item, long Quantity)> Recipe(string id) =>
        _recipes.TryGetValue(id, out var r) ? r.Ingredients : [(id, long.MaxValue)];

    private long RecipeXp(string id) => _recipes.TryGetValue(id, out var r) ? r.Xp : 0;

    private bool IsLocked(string id) => !_recipes.TryGetValue(id, out var r) || r.Locked || r.Station != Items.Workbench;

    private async Task<bool> ParseResearchAsync(CancellationToken cancellationToken)
    {
        var reply = await SendAsync("research.get", null, cancellationToken);
        if (!reply.Is("research"))
        {
            return false;
        }

        _techs.Clear();
        foreach (var t in reply.Payload.Each("technologies"))
        {
            _techs[t.Text("id")!] = (
                t.Text("status") ?? "locked",
                t.Long("xp"),
                t.Each("cost").Select(c => (c.Text("id")!, c.Long("quantity"))).ToList());
        }

        if (reply.Payload.Each("finished").Any())
        {
            // Finished research unlocks recipes and what the trader sells.
            _recipes.Clear();
            await CraftingAsync(cancellationToken);
        }

        return true;
    }

    private async Task InventoryAsync(CancellationToken cancellationToken)
    {
        var reply = await SendAsync("inventory.get", null, cancellationToken);
        if (!reply.Is("inventory"))
        {
            return;
        }

        _inventory.Clear();
        foreach (var item in reply.Payload.Each("items"))
        {
            _inventory[item.Text("id")!] = item.Long("quantity");
        }
    }

    private async Task MyOffersAsync(CancellationToken cancellationToken)
    {
        var reply = await SendAsync("market.mine", null, cancellationToken);
        if (!reply.Is("market.mine"))
        {
            return;
        }

        _listings.Clear();
        _listings.AddRange(reply.Payload.Each("listings").Where(l => l.True("open"))
            .Select(l => (l.Long("id"), l.Text("item")!, l.Long("done") > 0)));
        _openListings = _listings.Count;
        _openOrders = reply.Payload.Each("orders").Count(o => o.True("open"));
    }

    /// <summary>
    /// Tops the wallet up as a session starts: to the first plot (and some tools) while the bot has none, so it
    /// gets to its trade in its first session rather than after days of sorting trash, and to the
    /// <see cref="BotRules.Allowance"/> it buys from players with.
    /// </summary>
    private async Task AllowanceAsync(CancellationToken cancellationToken)
    {
        if (grant is null)
        {
            return;
        }

        var target = BotRules.Allowance;
        if (_plots.Count == 0 && _mapWidth > 0)
        {
            var first = BotRules.PlotBiomes(Profile.Trade, 0).Min(b => PlotPrice(b));
            target = Math.Max(target, first + BotRules.Reserve + BotRules.StartingExtra);
        }

        if (_money < target)
        {
            await grant(target - _money, cancellationToken);
            _money = (await SendAsync("wallet.get", null, cancellationToken)).Payload.Long("balanceCents");
        }
    }

    // ----- The garage -----

    private async Task<bool> SortAsync(CancellationToken cancellationToken)
    {
        var reply = await SendAsync("recycling.sort", new { count = 1 }, cancellationToken);
        if (!reply.Is("garage"))
        {
            return false;
        }

        ParseGarage(reply.Payload);
        return true;
    }

    private async Task<bool> PlaceInGarageAsync(string kind, CancellationToken cancellationToken)
    {
        if (FreeGarageCell(kind) is not { } cell)
        {
            return false;
        }

        var reply = await SendAsync("garage.place", new { kind, x = cell.X, y = cell.Y, rotation = 0 }, cancellationToken);
        if (!reply.Is("garage"))
        {
            return false;
        }

        ParseGarage(reply.Payload);
        _inventory[kind] = Math.Max(0, Have(kind) - 1);
        return true;
    }

    /// <summary>A cell where a piece of furniture fits without touching anything, scanning from the front-left corner.</summary>
    private (int X, int Y)? FreeGarageCell(string kind)
    {
        if (!_footprints.TryGetValue(kind, out var size))
        {
            return null;
        }

        var room = (Width: 16, Depth: 12);
        var taken = new bool[room.Width, room.Depth];
        foreach (var (k, x, y, rotation) in _garage)
        {
            var (w, d) = _footprints.TryGetValue(k, out var f) ? (rotation % 2 == 0 ? f : (f.Depth, f.Width)) : (1, 1);
            for (var i = x - 1; i <= x + w; i++)
            {
                for (var j = y - 1; j <= y + d; j++)
                {
                    if (i >= 0 && j >= 0 && i < room.Width && j < room.Depth)
                    {
                        taken[i, j] = true;
                    }
                }
            }
        }

        for (var y = 2; y + size.Depth <= room.Depth; y++)
        {
            for (var x = 0; x + size.Width <= room.Width; x++)
            {
                var fits = true;
                for (var i = x; i < x + size.Width && fits; i++)
                {
                    for (var j = y; j < y + size.Depth && fits; j++)
                    {
                        fits = !taken[i, j];
                    }
                }

                if (fits)
                {
                    return (x, y);
                }
            }
        }

        return null;
    }

    private async Task<bool> CraftAsync(string recipe, CancellationToken cancellationToken)
    {
        var reply = await SendAsync("crafting.craft", new { workbench = _workbench, recipe }, cancellationToken);
        if (!reply.Is("crafting"))
        {
            if (reply.Error == "locked")
            {
                _recipes[recipe] = _recipes[recipe] with { Locked = true };
            }

            return false;
        }

        ParseCrafting(reply.Payload);
        await InventoryAsync(cancellationToken);
        return true;
    }

    private async Task<bool> ResearchAsync(string technology, CancellationToken cancellationToken)
    {
        var reply = await SendAsync("research.start", new { technology }, cancellationToken);
        if (!reply.Is("research"))
        {
            _techs.Remove(technology);
            return false;
        }

        await ParseResearchAsync(cancellationToken);
        await InventoryAsync(cancellationToken);
        return true;
    }

    private async Task<bool> FurnaceAsync(Guid furnace, BotWorld world, CancellationToken cancellationToken)
    {
        var state = await SendAsync("furnace.get", new { furnace }, cancellationToken);
        if (!state.Is("furnace"))
        {
            if (furnace == _furnace)
            {
                _furnace = null;
            }

            return false;
        }

        var output = state.Payload.Get("output")?.Long("quantity") ?? 0;
        if (output > 0)
        {
            var taken = await SendAsync("furnace.take", new { furnace, what = "output" }, cancellationToken);
            if (taken.Ok)
            {
                await InventoryAsync(cancellationToken);
                return true;
            }
        }

        var fuel = state.Payload.Get("fuel")?.Long("quantity") ?? 0;
        var maxFuel = state.Payload.Long("maxFuel");
        if (fuel < 5 && Have(Items.Coal) > 0)
        {
            var coal = Math.Min(Have(Items.Coal), Math.Max(1, maxFuel - fuel));
            var loaded = await SendAsync("furnace.load", new { furnace, item = Items.Coal, quantity = Math.Min(coal, 10) }, cancellationToken);
            if (loaded.Ok)
            {
                await InventoryAsync(cancellationToken);
                return true;
            }
        }

        var input = state.Payload.Get("input");
        var inside = input?.Long("quantity") ?? 0;
        var ore = input?.Text("id") ?? BotRules.Ores.OrderByDescending(Have).FirstOrDefault(o => Have(o) > 0);
        if (ore is not null && Have(ore) > 0 && inside < state.Payload.Long("maxInput"))
        {
            var quantity = Math.Min(Have(ore), Math.Min(20, state.Payload.Long("maxInput") - inside));
            var loaded = await SendAsync("furnace.load", new { furnace, item = ore, quantity }, cancellationToken);
            if (loaded.Ok)
            {
                await InventoryAsync(cancellationToken);
                return true;
            }
        }

        return false;
    }

    // ----- Plots -----

    private long PlotPrice(int biome) => (long)Math.Round(_nextPlotBaseCents * _priceFactors.GetValueOrDefault(biome, 1.0));

    /// <summary>Looks for a free plot of a wanted biome in a spiral out from home and buys the first one found.</summary>
    private async Task<bool> BuyPlotAsync(int[] biomes, CancellationToken cancellationToken)
    {
        var (hx, hy) = Home();
        var looked = 0;
        for (var r = _searchRadius; r <= 80 && looked < 250; r++)
        {
            _searchRadius = r;
            for (var dy = -r; dy <= r; dy++)
            {
                for (var dx = -r; dx <= r; dx++)
                {
                    if (Math.Max(Math.Abs(dx), Math.Abs(dy)) != r)
                    {
                        continue;
                    }

                    var x = ((hx + dx) % _mapWidth + _mapWidth) % _mapWidth;
                    var y = hy + dy;
                    if (y < 0 || y >= _mapHeight)
                    {
                        continue;
                    }

                    looked++;
                    var plot = await SendAsync("world.plot", new { x, y }, cancellationToken);
                    if (!plot.Is("world.plot") || plot.Payload.Get("owner") is not null || plot.Payload.LongOrNull("priceCents") is not { } price)
                    {
                        continue;
                    }

                    var biome = (int)plot.Payload.Long("biome");
                    if (!biomes.Contains(biome) || price + BotRules.Reserve > _money)
                    {
                        continue;
                    }

                    var bought = await SendAsync("world.buy", new { x, y }, cancellationToken);
                    if (!bought.Is("world.bought"))
                    {
                        continue;
                    }

                    _plots.Add(new BotPlot(x, y, biome));
                    if (bought.Payload.Get("tool")?.Text("id") is { } given && _tools.Count == 0)
                    {
                        _tools = [given];
                    }

                    _nextPlotBaseCents = 0;
                    _fresh = false;
                    logger.LogInformation("Bot {Bot} bought plot {X}:{Y}", Row.CharacterName, x, y);
                    return true;
                }
            }
        }

        if (_searchRadius >= 80)
        {
            _searchRadius = 0;
        }

        return false;
    }

    /// <summary>The plot at the bot's home, in the map's projection (Behrmann, as the world module draws it).</summary>
    private (int X, int Y) Home()
    {
        const double radius = 6371.0072;
        const int sideKm = 5;
        var cos30 = Math.Cos(Math.PI / 6);
        var x = (Profile.Longitude * Math.PI / 180 * radius * cos30 + _mapWidth * sideKm / 2.0) / sideKm;
        var y = (_mapHeight * sideKm / 2.0 - radius * Math.Sin(Profile.Latitude * Math.PI / 180) / cos30) / sideKm;
        return (Math.Clamp((int)Math.Floor(x), 0, _mapWidth - 1), Math.Clamp((int)Math.Floor(y), 0, _mapHeight - 1));
    }

    private async Task<bool> EnterAsync(BotPlot plot, BotWorld world, CancellationToken cancellationToken)
    {
        var reply = await SendAsync("plot.enter", new { x = plot.X, y = plot.Y }, cancellationToken);
        if (!reply.Is("plot"))
        {
            return false;
        }

        var p = reply.Payload;
        using var gzip = new GZipStream(new MemoryStream(Convert.FromBase64String(p.Text("tiles")!)), CompressionMode.Decompress);
        using var tiles = new MemoryStream();
        gzip.CopyTo(tiles);
        plot.Tiles = tiles.ToArray();
        plot.Size = (int)p.Long("size");
        plot.Spawn = ((int)(p.Get("spawn")?.Long("x") ?? 0), (int)(p.Get("spawn")?.Long("y") ?? 0));
        _tools = Tools(p);

        var wanted = plot.Biome switch
        {
            Biomes.Mountains => new[] { Tiles.Rock },
            Biomes.Desert => [Tiles.Dune, Tiles.Rock],
            _ => [Tiles.Tree, Tiles.Rock],
        };
        var busy = new HashSet<(int, int)>();
        plot.Objects.Clear();
        foreach (var o in p.Each("objects"))
        {
            busy.Add(((int)o.Long("tileX"), (int)o.Long("tileY")));
            plot.Objects.Add((o.Id("id") ?? Guid.Empty, o.Text("kind")!));
        }

        plot.Fields.Clear();
        foreach (var f in p.Each("fields"))
        {
            var at = ((int)f.Long("tileX"), (int)f.Long("tileY"));
            busy.Add(at);
            plot.Fields.Add((at.Item1, at.Item2, f.Text("crop"), f.LongOrNull("readyAt") is { } ready ? DateTimeOffset.FromUnixTimeMilliseconds(ready) : null));
        }

        var trees = new Dictionary<(int, int), DateTimeOffset>();
        foreach (var t in p.Each("trees"))
        {
            var at = ((int)t.Long("tileX"), (int)t.Long("tileY"));
            busy.Add(at);
            trees[at] = DateTimeOffset.FromUnixTimeMilliseconds(t.Long("readyAt"));
        }

        plot.Planted = trees.Count;
        plot.Mines.Clear();
        foreach (var m in p.Each("mines"))
        {
            var upgrade = m.Get("upgrade");
            var cost = upgrade?.Each("cost").ToDictionary(c => c.Text("id")!, c => c.Long("quantity")) ?? [];
            plot.Mines.Add((
                (int)m.Long("id"), (int)m.Long("units"),
                m.LongOrNull("refillAt") is { } refill ? DateTimeOffset.FromUnixTimeMilliseconds(refill) : null,
                cost.GetValueOrDefault(Items.IronIngot), cost.GetValueOrDefault(Items.Wood),
                upgrade is not null && cost.Keys.All(k => k is Items.IronIngot or Items.Wood)));
        }

        // Players work near where they appear; so does the bot.
        plot.Targets.Clear();
        plot.Free.Clear();
        var size = plot.Size;
        var near = Enumerable.Range(0, plot.Tiles.Length)
            .Select(i => (X: i % size, Y: i / size))
            .Where(t => t.Y > plot.Spawn.Y && !busy.Contains(t))
            .OrderBy(t => Math.Abs(t.X - plot.Spawn.X) + Math.Abs(t.Y - plot.Spawn.Y));
        foreach (var t in near)
        {
            var tile = plot.Tiles[t.Y * size + t.X];
            if (wanted.Contains(tile) && plot.Targets.Count < 300)
            {
                plot.Targets.Add(t);
            }
            else if (tile == Tiles.None && plot.Free.Count < 300)
            {
                plot.Free.Add(t);
            }

            if (plot.Targets.Count >= 300 && plot.Free.Count >= 300)
            {
                break;
            }
        }

        // A planted tree that has grown is cut like any other.
        foreach (var ((x, y), ready) in trees)
        {
            if (ready <= world.Now)
            {
                plot.Targets.Insert(0, (x, y));
            }
        }

        return true;
    }

    private async Task<bool> WorkPlotAsync(BotPlot plot, BotWorld world, CancellationToken cancellationToken)
    {
        if (plot.Tiles is null && !await EnterAsync(plot, world, cancellationToken))
        {
            return false;
        }

        if (plot.Biome == Biomes.Farmland)
        {
            return await FarmAsync(plot, world, cancellationToken);
        }

        if (plot.Biome == Biomes.Mountains)
        {
            var mine = plot.Mines.FirstOrDefault(m => m.Units > 0 || m.RefillAt is { } at && at <= world.Now);
            if (mine.Units > 0 || mine.RefillAt is not null)
            {
                if (!await HoldAsync(Items.Pickaxe, cancellationToken))
                {
                    return false;
                }

                var mined = await SendAsync("plot.mine", new { x = plot.X, y = plot.Y, mine = mine.Id }, cancellationToken);
                var index = plot.Mines.IndexOf(mine);
                if (mined.Is("plot.mined"))
                {
                    var m = mined.Payload.Get("mine")!.Value;
                    plot.Mines[index] = mine with { Units = (int)m.Long("units"), RefillAt = m.LongOrNull("refillAt") is { } r ? DateTimeOffset.FromUnixTimeMilliseconds(r) : null };
                    foreach (var item in mined.Payload.Each("items"))
                    {
                        _inventory[item.Text("id")!] = Have(item.Text("id")!) + item.Long("quantity");
                    }

                    return true;
                }

                if (mined.Error == "mine_empty")
                {
                    plot.Mines[index] = mine with { Units = 0, RefillAt = world.Now.AddMinutes(10) };
                }

                return false;
            }
        }

        return await HarvestAsync(plot, cancellationToken);
    }

    private async Task<bool> HarvestAsync(BotPlot plot, CancellationToken cancellationToken)
    {
        while (plot.Targets.Count > 0)
        {
            var (x, y) = plot.Targets[0];
            var tool = plot.Tiles![y * plot.Size + x] switch
            {
                Tiles.Rock => Items.Pickaxe,
                Tiles.Dune => Items.Shovel,
                _ => Items.Axe,
            };
            if (!await HoldAsync(tool, cancellationToken))
            {
                // Without the tool, the rest of that kind is out of reach too.
                plot.Targets.RemoveAll(t => plot.Tiles[t.Y * plot.Size + t.X] == plot.Tiles[y * plot.Size + x]);
                continue;
            }

            var reply = await SendAsync("plot.harvest", new { x = plot.X, y = plot.Y, tileX = x, tileY = y }, cancellationToken);
            if (reply.Error == "too_fast")
            {
                return false;
            }

            plot.Targets.RemoveAt(0);
            plot.Tiles[y * plot.Size + x] = Tiles.None;
            if (reply.Is("plot.harvested"))
            {
                foreach (var item in reply.Payload.Each("items"))
                {
                    _inventory[item.Text("id")!] = Have(item.Text("id")!) + item.Long("quantity");
                }

                return true;
            }
        }

        return false;
    }

    private async Task<bool> FarmAsync(BotPlot plot, BotWorld world, CancellationToken cancellationToken)
    {
        var ripe = plot.Fields.FindIndex(f => f.Crop is not null && f.ReadyAt is { } at && at <= world.Now);
        if (ripe >= 0)
        {
            var f = plot.Fields[ripe];
            var reply = await SendAsync("plot.reap", new { x = plot.X, y = plot.Y, tileX = f.X, tileY = f.Y }, cancellationToken);
            if (!reply.Is("plot.field"))
            {
                plot.Fields.RemoveAt(ripe);
                return false;
            }

            plot.Fields[ripe] = (f.X, f.Y, null, null);
            foreach (var item in reply.Payload.Each("items"))
            {
                _inventory[item.Text("id")!] = Have(item.Text("id")!) + item.Long("quantity");
            }

            return true;
        }

        var empty = plot.Fields.FindIndex(f => f.Crop is null);
        if (empty >= 0)
        {
            var f = plot.Fields[empty];
            var crop = Pick(world.Random, BotRules.Crops);
            var reply = await SendAsync("plot.plant", new { x = plot.X, y = plot.Y, tileX = f.X, tileY = f.Y, crop }, cancellationToken);
            if (!reply.Is("plot.field"))
            {
                plot.Fields.RemoveAt(empty);
                return false;
            }

            var field = reply.Payload.Get("field");
            plot.Fields[empty] = (f.X, f.Y, crop, field?.LongOrNull("readyAt") is { } ready ? DateTimeOffset.FromUnixTimeMilliseconds(ready) : null);
            return true;
        }

        if (plot.Fields.Count < BotRules.MaxFields && plot.Free.Count > 0 && await HoldAsync(Items.Hoe, cancellationToken))
        {
            var (x, y) = plot.Free[0];
            plot.Free.RemoveAt(0);
            var reply = await SendAsync("plot.till", new { x = plot.X, y = plot.Y, tileX = x, tileY = y }, cancellationToken);
            if (reply.Is("plot.field"))
            {
                plot.Fields.Add((x, y, null, null));
                return true;
            }
        }

        return false;
    }

    private async Task<bool> PlantTreeAsync(BotPlot plot, BotWorld world, CancellationToken cancellationToken)
    {
        if (plot.Tiles is null && !await EnterAsync(plot, world, cancellationToken))
        {
            return false;
        }

        while (plot.Free.Count > 0)
        {
            var (x, y) = plot.Free[world.Random.Next(Math.Min(plot.Free.Count, 40))];
            plot.Free.Remove((x, y));
            var reply = await SendAsync("plot.plantTree", new { x = plot.X, y = plot.Y, tileX = x, tileY = y }, cancellationToken);
            if (reply.Is("plot.tree"))
            {
                plot.Planted++;
                _inventory[Items.Sapling] = Math.Max(0, Have(Items.Sapling) - 1);
                return true;
            }

            if (reply.Error != "blocked")
            {
                return false;
            }
        }

        return false;
    }

    /// <summary>What of the plot's plan in <see cref="BotRules.Builds"/> does not stand there yet, in the plan's order.</summary>
    private IEnumerable<string> StillToBuild(BotPlot plot)
    {
        var standing = plot.Objects.GroupBy(o => o.Kind).ToDictionary(g => g.Key, g => g.Count());
        foreach (var kind in BotRules.Builds(Profile.Trade, plot.Biome))
        {
            if (standing.GetValueOrDefault(kind) > 0)
            {
                standing[kind]--;
            }
            else
            {
                yield return kind;
            }
        }
    }

    /// <summary>Puts something from the inventory on a free tile near the spawn, off the path straight ahead of it.</summary>
    private async Task<bool> BuildAsync(BotPlot plot, string kind, CancellationToken cancellationToken)
    {
        foreach (var (x, y) in plot.Free.Where(t => t.X != plot.Spawn.X).Take(20).ToList())
        {
            plot.Free.Remove((x, y));
            var reply = await SendAsync("plot.place", new { x = plot.X, y = plot.Y, kind, tileX = x, tileY = y, rotation = 0 }, cancellationToken);
            if (reply.Is("plot.placed"))
            {
                // A machine covers more tiles than the one it stands on.
                plot.Free.RemoveAll(t => Footprints.Covers(kind, x, y, t.X, t.Y));
                plot.Objects.Add((reply.Payload.Get("object")?.Id("id") ?? Guid.Empty, kind));
                _inventory[kind] = Math.Max(0, Have(kind) - 1);
                return true;
            }

            if (reply.Error != "blocked")
            {
                return false;
            }
        }

        return false;
    }

    private async Task<bool> UpgradeMineAsync(BotPlot plot, CancellationToken cancellationToken)
    {
        var mine = plot.Mines.First(m => m.Upgradable && Have(Items.IronIngot) >= m.UpgradeIron && Have(Items.Wood) >= m.UpgradeWood);
        var reply = await SendAsync("plot.upgradeMine", new { x = plot.X, y = plot.Y, mine = mine.Id }, cancellationToken);
        plot.Tiles = null;
        if (!reply.Is("plot.mineUpgraded"))
        {
            return false;
        }

        await InventoryAsync(cancellationToken);
        return true;
    }

    /// <summary>Gets the tool into the bot's hand: from the inventory, or bought from the trader.</summary>
    private async Task<bool> HoldAsync(string tool, CancellationToken cancellationToken)
    {
        if (_tools.Contains(tool) || tool == Items.Axe && _tools.Contains(Items.Chainsaw))
        {
            return true;
        }

        if (Have(tool) == 0)
        {
            if (!_traderSells.TryGetValue(tool, out var price) || _money < price + BotRules.Reserve)
            {
                return false;
            }

            if (!await TradeAsync("market.buy", tool, 1, cancellationToken))
            {
                return false;
            }
        }

        var reply = await SendAsync("character.equip", new { item = tool }, cancellationToken);
        if (!reply.Is("character"))
        {
            return false;
        }

        _tools = Tools(reply.Payload);
        await InventoryAsync(cancellationToken);
        return _tools.Contains(tool);
    }

    /// <summary>The tools in a character's (or a plot's) tool bar.</summary>
    private static List<string> Tools(JsonElement payload) =>
        payload.Each("tools").Where(t => t.ValueKind == JsonValueKind.Object).Select(t => t.Text("id")).OfType<string>().ToList();

    // ----- The market -----

    private async Task<bool> TradeAsync(string type, string item, long quantity, CancellationToken cancellationToken)
    {
        var reply = await SendAsync(type, new { item, quantity = Math.Min(quantity, 1000) }, cancellationToken);
        if (!reply.Is("market.traded"))
        {
            return false;
        }

        await InventoryAsync(cancellationToken);
        return true;
    }

    /// <summary>What the bot has more of than it keeps, worth the most first.</summary>
    private IEnumerable<(string Item, long Quantity)> Surplus() =>
        _inventory
            .Where(i => (BotRules.Goods.Contains(i.Key) || Profile.Trade == BotTrade.Trader && Floor(i.Key) > 0) && i.Value > Keep(i.Key))
            .Select(i => (Item: i.Key, Quantity: i.Value - Keep(i.Key)))
            .OrderByDescending(s => s.Quantity * Math.Max(Floor(s.Item), 1));

    /// <summary>What the bot holds back: what its trade keeps, and whatever it still means to build on its plots.</summary>
    private long Keep(string item) =>
        BotRules.Keep(Profile.Trade, item) + _plots.Where(p => p.Tiles is not null).Sum(p => StillToBuild(p).Count(k => k == item));

    private async Task<bool> ListAsync(BotWorld world, CancellationToken cancellationToken)
    {
        var surplus = Surplus().Take(3).ToList();
        var (item, quantity) = surplus[world.Random.Next(surplus.Count)];
        quantity = Math.Min(quantity, BotRules.ListingSize);
        var floor = Math.Max(Floor(item), 1);
        var price = (long)Math.Round(floor * (1.4 + world.Random.NextDouble() * 0.8));

        // Undercut the cheapest listing a little, but never sell for near what the trader pays.
        var board = await SendAsync("market.item", new { item }, cancellationToken);
        if (board.Is("market.item"))
        {
            var cheapest = board.Payload.Each("listings").Where(l => !l.True("mine")).Select(l => l.Long("priceCents")).DefaultIfEmpty(0).First();
            if (cheapest > 0)
            {
                price = Math.Min(price, (long)Math.Round(cheapest * (0.93 + world.Random.NextDouble() * 0.07)));
            }
        }

        price = Math.Max(price, (long)Math.Ceiling(floor * BotRules.MinMarkup));
        var reply = await SendAsync("market.list", new { item, quantity, priceCents = price }, cancellationToken);
        if (!reply.Is("market.done"))
        {
            return false;
        }

        _openListings++;
        _lastListingAt = world.Now;
        _inventory[item] = Have(item) - quantity;
        return true;
    }

    /// <summary>Takes back the oldest listing nobody bought from, so it can go up again at the price players pay now.</summary>
    private async Task<bool> UnlistOldestAsync(BotWorld world, CancellationToken cancellationToken)
    {
        var oldest = _listings.Where(l => !l.Sold).MinBy(l => l.Id);
        var reply = await SendAsync("market.unlist", new { id = oldest.Id }, cancellationToken);
        _listings.Remove(oldest);
        if (!reply.Ok)
        {
            return false;
        }

        _openListings = _listings.Count;
        _lastListingAt = world.Now - BotRules.ListEvery;
        await InventoryAsync(cancellationToken);
        return true;
    }

    /// <summary>Buys from other players: what the bot needs for its work, or, as a trader, anything cheap enough to sell on.</summary>
    private async Task<bool> ShopAsync(BotWorld world, CancellationToken cancellationToken)
    {
        var overview = await SendAsync("market.overview", null, cancellationToken);
        if (!overview.Is("market.overview"))
        {
            return false;
        }

        var wanted = BotRules.Buys(Profile.Trade);
        var deals = new List<(string Item, long Price)>();
        foreach (var entry in overview.Payload.Each("items"))
        {
            var id = entry.Text("id")!;
            if (entry.LongOrNull("lowestCents") is not { } lowest || entry.Long("listed") == 0)
            {
                continue;
            }

            if (Limit(id, entry.LongOrNull("quickSaleCents") ?? Floor(id)) is { } limit && lowest <= limit)
            {
                deals.Add((id, lowest));
            }
        }

        if (deals.Count == 0)
        {
            return false;
        }

        var (item, _) = deals[world.Random.Next(deals.Count)];
        var board = await SendAsync("market.item", new { item }, cancellationToken);
        if (!board.Is("market.item"))
        {
            return false;
        }

        var most = Limit(item, Floor(item)) ?? 0;
        foreach (var listing in board.Payload.Each("listings").Where(l => !l.True("mine") && l.Long("priceCents") <= most))
        {
            var price = listing.Long("priceCents");
            var budget = (_money - BotRules.Reserve) / Math.Max(price, 1);
            var quantity = Math.Min(Math.Min(listing.Long("quantity"), BotRules.PurchaseSize), budget);
            if (quantity <= 0)
            {
                return false;
            }

            var reply = await SendAsync("market.purchase", new { id = listing.Long("id"), quantity }, cancellationToken);
            if (reply.Is("market.done"))
            {
                _purchases++;
                _inventory[item] = Have(item) + quantity;
                return true;
            }
        }

        return false;
    }

    /// <summary>
    /// The most the bot pays a player for one piece, or null when it does not buy the item. What its trade needs it
    /// pays well for; anything else it takes when it is a bargain, and a trader buys to sell it on. Never more than
    /// the NPC trader charges, so buying from the trader to sell to a bot pays nobody.
    /// </summary>
    private double? Limit(string item, long floor)
    {
        if (floor <= 0)
        {
            return null;
        }

        var limit = BotRules.Buys(Profile.Trade).Contains(item) && Have(item) < 200 ? floor * 2.0
            : Profile.Trade == BotTrade.Trader ? floor * 1.5
            : BotRules.Goods.Contains(item) ? floor * 1.3
            : 0;
        if (_traderSells.TryGetValue(item, out var shop))
        {
            limit = Math.Min(limit, shop);
        }

        return limit > 0 ? limit : null;
    }

    /// <summary>Sells to a player's buy order that pays at least what the trader would.</summary>
    private async Task<bool> FillOrderAsync(BotWorld world, CancellationToken cancellationToken)
    {
        var surplus = Surplus().ToDictionary(s => s.Item, s => s.Quantity);
        if (surplus.Count == 0)
        {
            return false;
        }

        var overview = await SendAsync("market.overview", null, cancellationToken);
        if (!overview.Is("market.overview"))
        {
            return false;
        }

        var options = overview.Payload.Each("items")
            .Where(e => surplus.ContainsKey(e.Text("id")!) && e.Long("wanted") > 0 && e.LongOrNull("highestCents") is { } best && best >= Floor(e.Text("id")!))
            .Select(e => e.Text("id")!)
            .ToList();
        if (options.Count == 0)
        {
            return false;
        }

        var item = options[world.Random.Next(options.Count)];
        var board = await SendAsync("market.item", new { item }, cancellationToken);
        if (!board.Is("market.item"))
        {
            return false;
        }

        foreach (var order in board.Payload.Each("orders").Where(o => !o.True("mine") && o.Long("priceCents") >= Floor(item)))
        {
            var quantity = Math.Min(order.Long("quantity"), Math.Min(surplus[item], BotRules.ListingSize));
            var reply = await SendAsync("market.fill", new { id = order.Long("id"), quantity }, cancellationToken);
            if (reply.Is("market.done"))
            {
                _inventory[item] = Have(item) - quantity;
                return true;
            }
        }

        return false;
    }

    private async Task<bool> PlaceOrderAsync(BotWorld world, CancellationToken cancellationToken)
    {
        var wanted = BotRules.Buys(Profile.Trade).Where(i => Have(i) < 20).ToList();
        if (wanted.Count == 0)
        {
            return false;
        }

        var item = wanted[world.Random.Next(wanted.Count)];
        var price = Math.Max(1, (long)Math.Round(Math.Max(Floor(item), 1) * (1.1 + world.Random.NextDouble() * 0.3)));
        const long quantity = 20;
        if (price * quantity > (_money - BotRules.Reserve) / 3)
        {
            return false;
        }

        var reply = await SendAsync("market.order", new { item, quantity, priceCents = price }, cancellationToken);
        if (!reply.Is("market.done"))
        {
            return false;
        }

        _openOrders++;
        return true;
    }

    // ----- Contracts -----

    /// <summary>Delivers what it can to its NPC orders and to players' orders it has taken, takes one it can fill
    /// at once, and now and then gives one out for what it needs.</summary>
    private async Task<bool> ContractsAsync(BotWorld world, CancellationToken cancellationToken)
    {
        var view = await SendAsync("contracts.get", null, cancellationToken);
        if (!view.Is("contracts"))
        {
            return false;
        }

        foreach (var c in view.Payload.Each("npc").Concat(view.Payload.Each("taken")))
        {
            var item = c.Text("item")!;
            var left = c.Long("quantity") - c.Long("delivered");
            var have = Have(item) - (Profile.Trade == BotTrade.Trader ? 0 : Math.Min(BotRules.Keep(Profile.Trade, item), Have(item) / 2));
            if (have <= 0 || left <= 0)
            {
                continue;
            }

            var quantity = Math.Min(have, left);
            if (quantity < Math.Max(1, left / 4))
            {
                continue;
            }

            var reply = await SendAsync("contracts.deliver", new { id = c.Long("id"), quantity }, cancellationToken);
            if (reply.Is("contracts.done"))
            {
                _inventory[item] = Have(item) - quantity;
                return true;
            }
        }

        var taken = view.Payload.Each("taken").Count();
        if (taken < 2)
        {
            foreach (var c in view.Payload.Each("board"))
            {
                var item = c.Text("item")!;
                var quantity = c.Long("quantity");
                if (Have(item) - BotRules.Keep(Profile.Trade, item) < quantity || c.Long("rewardCents") < Floor(item) * quantity)
                {
                    continue;
                }

                var accepted = await SendAsync("contracts.accept", new { id = c.Long("id") }, cancellationToken);
                if (!accepted.Is("contracts.done"))
                {
                    continue;
                }

                var delivered = await SendAsync("contracts.deliver", new { id = c.Long("id"), quantity }, cancellationToken);
                if (delivered.Is("contracts.done"))
                {
                    _inventory[item] = Have(item) - quantity;
                }

                return true;
            }
        }

        var issued = view.Payload.Each("issued").Count(c => c.Text("state") is "open" or "taken");
        var wanted = BotRules.Buys(Profile.Trade).Where(i => Have(i) < 20 && Floor(i) > 0).ToList();
        if (issued < BotRules.MaxIssued && wanted.Count > 0 && world.Random.Next(4) == 0)
        {
            var item = wanted[world.Random.Next(wanted.Count)];
            const long quantity = 20;
            var reward = (long)Math.Round(Floor(item) * quantity * (1.2 + world.Random.NextDouble() * 0.4));
            if (reward <= (_money - BotRules.Reserve) / 3)
            {
                var reply = await SendAsync("contracts.create", new { item, quantity, rewardCents = reward, hours = 24 }, cancellationToken);
                return reply.Is("contracts.done");
            }
        }

        return false;
    }

    // ----- Plumbing -----

    private async Task<BotReply> SendAsync(string type, object? payload, CancellationToken cancellationToken)
    {
        var reply = await Client.SendAsync(type, payload, cancellationToken);
        if (!reply.Ok)
        {
            logger.LogDebug("Bot {Bot}: {Type} -> {Error}", Row.CharacterName, type, reply.Error);
            return reply;
        }

        if (reply.Payload.Xp() is { } xp)
        {
            _xp = xp;
        }

        if (reply.Payload.LongOrNull("balanceCents") is { } balance)
        {
            _money = balance;
        }

        return reply;
    }

    private static string Pick(Random random, (string Crop, int Weight)[] options)
    {
        var roll = random.Next(options.Sum(o => o.Weight));
        foreach (var (crop, weight) in options)
        {
            roll -= weight;
            if (roll < 0)
            {
                return crop;
            }
        }

        return options[0].Crop;
    }
}
