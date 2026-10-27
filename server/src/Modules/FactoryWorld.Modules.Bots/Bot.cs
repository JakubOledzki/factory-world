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
    public List<(Guid Id, string Kind, int X, int Y)> Objects { get; } = [];

    /// <summary>Tiles taken by objects (all the tiles a machine covers), fields, trees, mines, the railway and the station.</summary>
    public HashSet<(int X, int Y)> Busy { get; } = [];

    /// <summary>Trees, rocks and dunes the bot clears to make room for its line.</summary>
    public List<(int X, int Y)> Clearing { get; } = [];
}

/// <summary>Where the bot's production line stands, found by its machine with the chests and the generator in their places.</summary>
internal sealed record BotLineSite(
    BotPlot Plot, Guid Input, Guid Machine, Guid Output, Guid Generator, IReadOnlyList<(Guid Id, string Kind, int X, int Y)> Parts);

/// <summary>What all the bots share: who is a bot, the market overview one of them fetched, and the board of calls for help.</summary>
public sealed class BotCommons(BotHelpBoard help)
{
    private readonly HashSet<string> _names = new(StringComparer.Ordinal);

    public BotHelpBoard Help { get; } = help;

    /// <summary>The market overview as some bot last fetched it, and when.</summary>
    internal (JsonElement Overview, DateTimeOffset At)? Overview { get; set; }

    public void AddBot(string character)
    {
        lock (_names)
        {
            _names.Add(character);
        }
    }

    /// <summary>Whether a name on the market belongs to a bot: bots do not trade among themselves to sell on.</summary>
    public bool IsBot(string? character)
    {
        lock (_names)
        {
            return character is not null && _names.Contains(character);
        }
    }
}

/// <summary>
/// One bot: plays through <see cref="BotClient"/> like a player at the keyboard would, one action per step.
/// It remembers between steps what it saw (its inventory, its plots, the prices) and refreshes all of it
/// when a session starts. Every action that gives XP is skipped while it would carry the bot over its cap.
/// </summary>
/// <param name="grant">Credits the bot's wallet with this many cents (the server's allowance, see <see cref="BotRules.Allowance"/>).</param>
/// <param name="commons">What the bots share; a bot on its own has its own.</param>
public sealed class Bot(
    BotProfile profile, BotRow row, BotClient client, ILogger logger, Func<long, CancellationToken, Task>? grant = null, BotCommons? commons = null)
{
    private readonly BotCommons _commons = commons ?? new BotCommons(new BotHelpBoard());
    private readonly BotLine? _line = BotRules.Line(profile.Trade);
    private BotLineSite? _site;
    private DateTimeOffset _tendAt;
    private bool _recipeSet;
    private long _lastInputs = -1;
    private int _stalls;
    private int _placeFailures;
    private DateTimeOffset _gaveUpAt;
    private DateTimeOffset _wantingSince;
    private HelpRequest? _help;
    private DateTimeOffset _helpUntil;
    private long _traderIncome;
    private DateTimeOffset _contractsAt;
    private Dictionary<string, long> _needs = new(StringComparer.Ordinal);
    private Dictionary<string, long> _reserved = new(StringComparer.Ordinal);

    private readonly Dictionary<string, long> _inventory = new(StringComparer.Ordinal);
    private readonly List<BotPlot> _plots = [];
    private readonly Dictionary<string, long> _floor = new(StringComparer.Ordinal);
    private readonly Dictionary<string, long> _traderSells = new(StringComparer.Ordinal);
    private readonly Dictionary<string, (long Xp, List<(string Item, long Quantity)> Ingredients, bool Locked, string Station, long Makes)> _recipes = new(StringComparer.Ordinal);
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

    /// <summary>Whether the bot has its production line standing (as far as it saw this session).</summary>
    public bool HasLine => _site is not null;

    /// <summary>The bot's call for help, while players may answer it.</summary>
    public HelpRequest? Help => _help;

    /// <summary>The session ended: whatever was seen is stale, and the next step looks around again first.</summary>
    public void EndSession()
    {
        _fresh = false;
        _purchases = 0;
        _traderIncome = 0;
        _help = null;
        _recipeSet = false;
        _lastInputs = -1;
        _placeFailures = 0;
        _gaveUpAt = default;
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

        if (_commons.Help.TakeAnswer(Row.Name) is { } answered)
        {
            return await HelpedAsync(answered, world, cancellationToken);
        }

        if (_help is not null && _helpUntil <= world.Now)
        {
            // Nobody came: the bot sets about it itself.
            _commons.Help.Withdraw(Row.Name);
            var reason = _help.Reason;
            _help = null;
            if (reason == HelpReasons.Stalled && _site is { } stalled)
            {
                await RepairAsync(stalled, cancellationToken);
                return "repair line";
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

    /// <summary>How many of <paramref name="quantity"/> pieces the bot sells to the trader, so as to stay within what it may take from NPCs in a session.</summary>
    private long TraderMay(string item, long quantity) =>
        Math.Clamp((BotRules.MaxTraderIncome - _traderIncome) / Math.Max(Floor(item), 1), 1, quantity);

    private long Floor(string item) => _floor.GetValueOrDefault(item);

    private bool Has(IEnumerable<(string Item, long Quantity)> cost) => cost.All(c => Have(c.Item) >= c.Quantity);

    /// <summary>Everything the bot could do now, with how likely it is to pick each.</summary>
    private List<(int Weight, string Name, Func<CancellationToken, Task<bool>> Run)> Candidates(BotWorld world)
    {
        var trade = Profile.Trade;
        var list = new List<(int, string, Func<CancellationToken, Task<bool>>)>();
        void Add(int weight, string name, Func<CancellationToken, Task<bool>> run) => list.Add((weight, name, run));
        _needs = Needs();
        _reserved = Reserved();
        var toSell = Surplus().Sum(s => s.Quantity);
        var traderPays = _traderIncome < BotRules.MaxTraderIncome;

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
        if (waste is not null && traderPays)
        {
            Add(8, "sell waste", ct => TradeAsync("market.sell", waste, TraderMay(waste, Have(waste)), ct));
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
            // With goods piling up unsold, the bot gathers less and sees to its line and the market instead.
            Add(toSell >= BotRules.Glut ? 2 : own ? 16 : 6, "work plot", ct => WorkPlotAsync(plot, world, ct));

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

            foreach (var (id, kind, _, _) in plot.Objects)
            {
                // The furnace of the line is the inserters' to work.
                if (kind == Items.Furnace && id != _site?.Machine)
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
                if (!IsLocked(product) && Has(Recipe(product)) && Have(product) < BotRules.Stock(product) && !UsesNeeded(product))
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

        if (_line is not null && _help is null)
        {
            LineCandidates(_line, world, Add);
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
        if (glut is not null && traderPays)
        {
            Add(3, "quick sale", ct => TradeAsync("market.sell", glut, TraderMay(glut, 50), ct));
        }

        if (_money > BotRules.Reserve + 5_00 && _purchases < BotRules.MaxPurchases)
        {
            Add(trade switch { BotTrade.Trader => 10, BotTrade.Industrialist => 8, _ => 6 }, "shop", ct => ShopAsync(world, ct));
        }

        Add(4, "fill order", ct => FillOrderAsync(world, ct));

        if (_openOrders < BotRules.MaxOrders && _money > BotRules.Reserve + 50_00 && Wanted().Any())
        {
            Add(2, "place order", ct => PlaceOrderAsync(world, ct));
        }

        if (_contractsAt <= world.Now)
        {
            Add(6, "contracts", ct => ContractsAsync(world, ct));
        }

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
                    // Anyone may come and look at how a bot plays.
                    await SendAsync("plot.setPublic", new { x = key.Item1, y = key.Item2, @public = true }, cancellationToken);
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
                r.Text("station") ?? Items.Workbench,
                Math.Max(1, r.Long("quantity")));
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

        // A furnace shows its coal as a number.
        var fuel = state.Payload.Long("fuel");
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
                    await SendAsync("plot.setPublic", new { x, y, @public = true }, cancellationToken);
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
        plot.Busy.Clear();
        foreach (var o in p.Each("objects"))
        {
            var (kind, ox, oy) = (o.Text("kind")!, (int)o.Long("tileX"), (int)o.Long("tileY"));
            busy.Add((ox, oy));
            plot.Busy.UnionWith(Footprints.Tiles(kind, ox, oy));
            plot.Objects.Add((o.Id("id") ?? Guid.Empty, kind, ox, oy));
        }

        foreach (var m in p.Each("mines"))
        {
            var (mx, my) = ((int)m.Long("x"), (int)m.Long("y"));
            for (var dx = 0; dx < Math.Max(1, m.Long("width")); dx++)
            {
                for (var dy = 0; dy < Math.Max(1, m.Long("height")); dy++)
                {
                    plot.Busy.Add((mx + dx, my + dy));
                }
            }
        }

        if (p.Get("station") is { } station)
        {
            var (sx, sy) = ((int)station.Long("x"), (int)station.Long("y"));
            for (var dx = -1; dx <= station.Long("width"); dx++)
            {
                for (var dy = -1; dy <= station.Long("height"); dy++)
                {
                    plot.Busy.Add((sx + dx, sy + dy));
                }
            }
        }

        if (p.LongOrNull("railRow") is { } rail)
        {
            for (var x = 0; x < plot.Size; x++)
            {
                for (var dy = -1; dy <= 1; dy++)
                {
                    plot.Busy.Add((x, (int)rail + dy));
                }
            }
        }

        plot.Busy.Add(plot.Spawn);
        FindSite(plot);

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
        plot.Busy.UnionWith(busy);
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

                // A saw may have felled the trees next to it too.
                foreach (var tile in reply.Payload.Each("felled"))
                {
                    var (tx, ty) = ((int)tile.Long("tileX"), (int)tile.Long("tileY"));
                    plot.Targets.Remove((tx, ty));
                    plot.Tiles[ty * plot.Size + tx] = Tiles.None;
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
                plot.Objects.Add((reply.Payload.Get("object")?.Id("id") ?? Guid.Empty, kind, x, y));
                plot.Busy.UnionWith(Footprints.Tiles(kind, x, y));
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
        if (_tools.Contains(tool) || tool == Items.Axe && Items.BestSaw(_tools) is not null)
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

    // ----- The production line -----

    /// <summary>What the bot looks for on the market: what its trade works with, and what it lacks for its line and its next research.</summary>
    private IEnumerable<string> Wanted() => BotRules.Buys(Profile.Trade).Concat(_needs.Keys).Distinct(StringComparer.Ordinal);

    /// <summary>Whether the bot has researched everything its line is made of.</summary>
    private bool LineReady(BotLine line) => line.Kit.All(k => !IsLocked(k.Item) || Have(k.Item) >= k.Quantity);

    /// <summary>Parts of the line the bot still lacks, while none stands.</summary>
    private List<(string Item, long Quantity)> Missing(BotLine line) =>
        _site is not null ? [] : line.Kit.Select(k => (k.Item, Quantity: k.Quantity - Have(k.Item))).Where(k => k.Quantity > 0).ToList();

    /// <summary>What making the missing parts at the workbench takes, in all.</summary>
    private Dictionary<string, long> Makings(BotLine line)
    {
        var makings = new Dictionary<string, long>(StringComparer.Ordinal);
        foreach (var (part, quantity) in Missing(line))
        {
            // Locked recipes too: what a part not yet researched will take is kept back for it already.
            if (!_recipes.TryGetValue(part, out var recipe) || recipe.Station != Items.Workbench)
            {
                continue;
            }

            var crafts = (quantity + recipe.Makes - 1) / recipe.Makes;
            foreach (var (item, each) in recipe.Ingredients)
            {
                makings[item] = makings.GetValueOrDefault(item) + crafts * each;
            }
        }

        return makings;
    }

    /// <summary>What the bot lacks for its line and for the next technology on its list, to look for on the market.</summary>
    private Dictionary<string, long> Needs()
    {
        var needs = new Dictionary<string, long>(StringComparer.Ordinal);
        if (_line is { } line && _site is null && _plots.Count > 0 && LineReady(line))
        {
            foreach (var (item, quantity) in Makings(line))
            {
                if (quantity > Have(item))
                {
                    needs[item] = quantity - Have(item);
                }
            }
        }

        foreach (var tech in BotRules.Research(Profile.Trade))
        {
            if (_techs.TryGetValue(tech, out var t) && t.Status == "available")
            {
                foreach (var (item, quantity) in t.Cost.Where(c => c.Quantity > Have(c.Item)))
                {
                    needs[item] = needs.GetValueOrDefault(item) + quantity - Have(item);
                }

                break;
            }
        }

        return needs;
    }

    /// <summary>What the bot does not sell: the cost of the technologies it can research next, and while its line is not up,
    /// the parts and what it makes them of.</summary>
    private Dictionary<string, long> Reserved()
    {
        var reserved = _line is { } line && _site is null && _plots.Count > 0
            ? Makings(line)
            : new Dictionary<string, long>(StringComparer.Ordinal);
        if (_line is not null && _site is null && _plots.Count > 0)
        {
            foreach (var (item, quantity) in _line.Kit)
            {
                reserved[item] = reserved.GetValueOrDefault(item) + quantity;
            }
        }

        foreach (var tech in BotRules.Research(Profile.Trade))
        {
            if (_techs.TryGetValue(tech, out var t) && t.Status == "available")
            {
                foreach (var (item, quantity) in t.Cost)
                {
                    reserved[item] = reserved.GetValueOrDefault(item) + quantity;
                }
            }
        }

        return reserved;
    }

    /// <summary>Whether crafting <paramref name="product"/> for the market would eat into what the line needs.</summary>
    private bool UsesNeeded(string product) =>
        !_reserved.ContainsKey(product) && Recipe(product).Any(i => Have(i.Item) - i.Quantity < _reserved.GetValueOrDefault(i.Item));

    /// <summary>What the bot could do about its line: look at its plots, tend it, build it or get its parts together.</summary>
    private void LineCandidates(BotLine line, BotWorld world, Action<int, string, Func<CancellationToken, Task<bool>>> add)
    {
        if (_plots.Count == 0)
        {
            return;
        }

        if (_plots.Any(p => p.Tiles is null))
        {
            // Whether a line stands already shows only on the plot.
            add(10, "look over plots", ct => LookOverAsync(world, ct));
            return;
        }

        if (_site is { } site)
        {
            if (_tendAt <= world.Now)
            {
                add(10, "tend line", ct => TendAsync(line, site, world, ct));
            }

            return;
        }

        if (!LineReady(line))
        {
            return;
        }

        var missing = Missing(line);
        if (_placeFailures >= 3)
        {
            // After a while the bot tries again: the plot may have changed, and it may have the tools now.
            _gaveUpAt = _gaveUpAt == default ? world.Now : _gaveUpAt;
            if (world.Now - _gaveUpAt >= BotRules.RetryBuildAfter)
            {
                (_placeFailures, _gaveUpAt) = (0, default);
            }
        }

        if (missing.Count == 0)
        {
            if (_plots.FirstOrDefault(p => p.Clearing.Count > 0) is { } clearing)
            {
                add(14, "clear ground", ct => ClearAsync(clearing, ct));
            }
            else if (_placeFailures < 3)
            {
                add(12, "build line", ct => BuildLineAsync(line, world, ct));
            }

            return;
        }

        if (_wantingSince == default)
        {
            _wantingSince = world.Now;
        }

        var craftable = _workbench is not null && _craftQueue < 5;
        var part = missing.Select(m => m.Item).FirstOrDefault(p => craftable && !IsLocked(p) && Has(Recipe(p)));
        if (part is not null)
        {
            add(10, "craft line part", ct => CraftAsync(part, ct));
        }
        else if (craftable && _needs.ContainsKey(Items.Nails) && !_needs.ContainsKey(Items.IronIngot) && !IsLocked(Items.Nails) && Has(Recipe(Items.Nails)))
        {
            add(6, "craft nails", ct => CraftAsync(Items.Nails, ct));
        }

        // A part it cannot make it may buy from the trader, dear: money leaves the game that way.
        var dear = missing.Select(m => m.Item).FirstOrDefault(p =>
            _traderSells.TryGetValue(p, out var price) && price <= Floor(p) * BotRules.MaxPartMarkup && _money >= price + BotRules.Reserve + 20_00);
        if (dear is not null)
        {
            add(3, "buy line part", ct => TradeAsync("market.buy", dear, 1, ct));
        }

        if (world.Now - _wantingSince >= BotRules.PartsWait)
        {
            add(3, "ask for parts", ct => AskForPartsAsync(missing, world, ct));
        }
    }

    private async Task<bool> LookOverAsync(BotWorld world, CancellationToken cancellationToken)
    {
        var looked = false;
        foreach (var plot in _plots.Where(p => p.Tiles is null).ToList())
        {
            looked |= await EnterAsync(plot, world, cancellationToken);
        }

        return looked;
    }

    /// <summary>Finds the bot's line among what stands on the plot: its machine with the chests and the generator in their places.</summary>
    private void FindSite(BotPlot plot)
    {
        if (_line is not { } line || _site is not null && _site.Plot != plot)
        {
            return;
        }

        _site = null;
        foreach (var machine in plot.Objects.Where(o => o.Kind == line.Machine))
        {
            var (x, y) = (machine.X - BotFactory.MachineX, machine.Y);
            var input = plot.Objects.FirstOrDefault(o => o.Kind == Items.WoodenChest && o.X == x && o.Y == y);
            var output = plot.Objects.FirstOrDefault(o => o.Kind == Items.WoodenChest && o.X == x + BotFactory.OutputX && o.Y == y);
            var generator = plot.Objects.FirstOrDefault(o =>
                o.Kind == Items.Generator && o.X == x + BotFactory.GeneratorX && o.Y == y + BotFactory.GeneratorY);
            if (input.Kind is null || output.Kind is null || generator.Kind is null)
            {
                continue;
            }

            var parts = plot.Objects.Where(o => o.X >= x && o.X < x + BotFactory.Width && o.Y >= y && o.Y < y + BotFactory.Depth).ToList();
            _site = new BotLineSite(plot, input.Id, machine.Id, output.Id, generator.Id, parts);
            return;
        }
    }

    /// <summary>Tiles nothing may be built on: something stands, grows or lies there.</summary>
    private static bool[,] Blocked(BotPlot plot)
    {
        var blocked = new bool[plot.Size, plot.Size];
        for (var y = 0; y < plot.Size; y++)
        {
            for (var x = 0; x < plot.Size; x++)
            {
                blocked[x, y] = plot.Tiles![y * plot.Size + x] != Tiles.None || plot.Busy.Contains((x, y));
            }
        }

        return blocked;
    }

    /// <summary>Puts the whole line up at once, with a building plan, where it fits nearest to the spawn.</summary>
    private async Task<bool> BuildLineAsync(BotLine line, BotWorld world, CancellationToken cancellationToken)
    {
        foreach (var plot in _plots.Where(p => p.Tiles is not null))
        {
            if (BotFactory.FindSpot(Blocked(plot), plot.Spawn) is not { } spot)
            {
                continue;
            }

            var objects = BotFactory.Layout(line.Machine)
                .Select(p => new { kind = p.Kind, tileX = spot.X + p.Dx, tileY = spot.Y + p.Dy, rotation = BotFactory.East })
                .ToList();
            var reply = await SendAsync("plot.placeMany", new { x = plot.X, y = plot.Y, objects }, cancellationToken);
            if (!reply.Is("plot.placedMany"))
            {
                // Something the bot did not see is in the way: it looks again before the next try.
                _placeFailures++;
                plot.Tiles = null;
                return false;
            }

            foreach (var o in reply.Payload.Each("objects"))
            {
                var (kind, ox, oy) = (o.Text("kind")!, (int)o.Long("tileX"), (int)o.Long("tileY"));
                plot.Objects.Add((o.Id("id") ?? Guid.Empty, kind, ox, oy));
                plot.Busy.UnionWith(Footprints.Tiles(kind, ox, oy));
            }

            FindSite(plot);
            await InventoryAsync(cancellationToken);
            _wantingSince = default;
            _tendAt = world.Now;
            _recipeSet = false;
            logger.LogInformation("Bot {Bot} built a {Machine} line on {X}:{Y}", Row.CharacterName, line.Machine, plot.X, plot.Y);
            return true;
        }

        // No room anywhere: the bot makes some where the fewest trees and rocks stand in the way.
        foreach (var plot in _plots.Where(p => p.Tiles is not null))
        {
            var clearable = new bool[plot.Size, plot.Size];
            var blocked = Blocked(plot);
            for (var y = 0; y < plot.Size; y++)
            {
                for (var x = 0; x < plot.Size; x++)
                {
                    clearable[x, y] = blocked[x, y] && !plot.Busy.Contains((x, y)) && plot.Tiles![y * plot.Size + x] is Tiles.Tree or Tiles.Rock or Tiles.Dune;
                    blocked[x, y] &= !clearable[x, y];
                }
            }

            if (BotFactory.FindSpot(blocked, clearable, plot.Spawn) is { } spot)
            {
                plot.Clearing.Clear();
                plot.Clearing.AddRange(BotFactory.Ground(spot.X, spot.Y).Where(t => clearable[t.X, t.Y]));
                return true;
            }
        }

        _placeFailures++;
        return false;
    }

    /// <summary>Fells or breaks the next thing on the ground the line is to stand on.</summary>
    private async Task<bool> ClearAsync(BotPlot plot, CancellationToken cancellationToken)
    {
        plot.Clearing.RemoveAll(t => plot.Tiles![t.Y * plot.Size + t.X] == Tiles.None);
        if (plot.Clearing.Count == 0)
        {
            return false;
        }

        var next = plot.Clearing[0];
        plot.Targets.Remove(next);
        plot.Targets.Insert(0, next);
        if (await HarvestAsync(plot, cancellationToken))
        {
            return true;
        }

        if (plot.Tiles![next.Y * plot.Size + next.X] != Tiles.None && !plot.Targets.Contains(next))
        {
            // Out of the bot's reach (no tool for it): it gives the clearing up and looks for ground without it.
            plot.Clearing.Clear();
            plot.Busy.Add(next);
            _placeFailures++;
        }

        return false;
    }

    /// <summary>
    /// Looks after the line: takes the products out, fills the input chest, keeps the generator burning and sets the
    /// machine's recipe. When nothing came out twice in a row although everything was there, the line is stalled and the
    /// bot asks players for help; without fuel it cannot get, it asks for fuel.
    /// </summary>
    private async Task<bool> TendAsync(BotLine line, BotLineSite site, BotWorld world, CancellationToken cancellationToken)
    {
        _tendAt = world.Now + BotRules.TendEvery;
        var (x, y) = (site.Plot.X, site.Plot.Y);
        var output = await SendAsync("storage.get", new { x, y, id = site.Output }, cancellationToken);
        if (!output.Is("storage"))
        {
            // Gone (or taken down): the bot looks at the plot again.
            _site = null;
            site.Plot.Tiles = null;
            return false;
        }

        long taken = 0;
        foreach (var (item, quantity) in Stored(output.Payload))
        {
            if ((await SendAsync("storage.take", new { x, y, id = site.Output, item, quantity = 0 }, cancellationToken)).Ok)
            {
                taken += quantity;
            }
        }

        var input = await SendAsync("storage.get", new { x, y, id = site.Input }, cancellationToken);
        var inside = input.Is("storage") ? Stored(input.Payload) : [];
        var before = line.Inputs.Sum(i => inside.GetValueOrDefault(i));
        await InventoryAsync(cancellationToken);

        // The generator first: without power the inserters stand.
        var generator = await SendAsync("generator.get", new { x, y, id = site.Generator }, cancellationToken);
        var fuel = generator.Payload.Get("fuel")?.Long("quantity") ?? 0;
        var burning = generator.Payload.Get("fuel")?.Text("id");
        if (fuel < 10)
        {
            var spare = line.Fuels.FirstOrDefault(f => (burning is null || burning == f) && Have(f) > 0);
            if (spare is not null)
            {
                var loaded = await SendAsync("generator.load", new { x, y, id = site.Generator, item = spare, quantity = Math.Min(Have(spare), 20) }, cancellationToken);
                if (loaded.Ok)
                {
                    fuel += Math.Min(Have(spare), 20);
                    _inventory[spare] = Have(spare) - Math.Min(Have(spare), 20);
                }
            }
        }

        // A furnace gets its coal from the bot's hand: coal in the chest would sit behind the ore once the furnace is full of it.
        var heated = true;
        if (line.Machine == Items.Furnace)
        {
            var furnace = await SendAsync("furnace.get", new { furnace = site.Machine }, cancellationToken);
            var coal = furnace.Payload.Long("fuel");
            if (coal < 10 && Have(Items.Coal) > 0)
            {
                var quantity = Math.Min(Have(Items.Coal), 20);
                if ((await SendAsync("furnace.load", new { furnace = site.Machine, item = Items.Coal, quantity }, cancellationToken)).Ok)
                {
                    coal += quantity;
                    _inventory[Items.Coal] = Have(Items.Coal) - quantity;
                }
            }

            heated = coal > 0;
        }

        foreach (var (item, quantity) in Refill(line, inside))
        {
            if ((await SendAsync("storage.put", new { x, y, id = site.Input, item, quantity }, cancellationToken)).Ok)
            {
                inside[item] = inside.GetValueOrDefault(item) + quantity;
                _inventory[item] = Have(item) - quantity;
            }
        }

        if (line.Recipe is { } recipe && !_recipeSet)
        {
            _recipeSet = (await SendAsync("machine.recipe", new { machine = site.Machine, recipe }, cancellationToken)).Ok;
        }

        // Stalled: it had all it needs since the last look, and used none of it.
        var complete = heated && line.Inputs.Any(i => inside.GetValueOrDefault(i) > 0);
        _stalls = taken == 0 && fuel > 0 && complete && _lastInputs >= 0 && before >= _lastInputs ? _stalls + 1 : 0;
        _lastInputs = line.Inputs.Sum(i => inside.GetValueOrDefault(i));

        if (fuel == 0)
        {
            Ask(HelpReasons.Parts, [(line.Fuels[^1], 20L)], site.Plot, world);
        }
        else if (_stalls >= BotRules.StalledAfter)
        {
            Ask(HelpReasons.Stalled, [], site.Plot, world);
        }

        return true;
    }

    /// <summary>What to put into the input chest: one kind of ore at a time for a furnace (mixed, the inserter would jam with the
    /// other kind in its hand), the grain or the wood for the others.</summary>
    private List<(string Item, long Quantity)> Refill(BotLine line, Dictionary<string, long> inside)
    {
        var puts = new List<(string, long)>();
        if (line.Machine == Items.Furnace)
        {
            var ore = BotRules.Ores.FirstOrDefault(o => inside.GetValueOrDefault(o) > 0)
                ?? BotRules.Ores.Where(o => Have(o) > 0).OrderByDescending(Have).FirstOrDefault();
            if (ore is not null && inside.GetValueOrDefault(ore) < 20 && Have(ore) > 0)
            {
                puts.Add((ore, Math.Min(Have(ore), 40)));
            }

            return puts;
        }

        var input = line.Inputs[0];
        // Wood is the sawmill's fuel too: some stays back for the generator.
        var spare = Have(input) - (line.Fuels.Contains(input) ? 20 : 0);
        if (inside.GetValueOrDefault(input) < 30 && spare > 0)
        {
            puts.Add((input, Math.Min(spare, 60)));
        }

        return puts;
    }

    private static Dictionary<string, long> Stored(JsonElement storage) =>
        storage.Each("items").GroupBy(i => i.Text("id")!).ToDictionary(g => g.Key, g => g.Sum(i => i.Long("quantity")), StringComparer.Ordinal);

    /// <summary>Takes the belts and inserters up and puts them back: whatever jammed them comes back to the inventory.</summary>
    private async Task RepairAsync(BotLineSite site, CancellationToken cancellationToken)
    {
        var (x, y) = (site.Plot.X, site.Plot.Y);
        var moving = site.Parts.Where(p => p.Kind is Items.Inserter or Items.Belt).ToList();
        foreach (var part in moving)
        {
            await SendAsync("plot.pickup", new { x, y, id = part.Id }, cancellationToken);
        }

        var objects = moving.Select(p => new { kind = p.Kind, tileX = p.X, tileY = p.Y, rotation = BotFactory.East }).ToList();
        await SendAsync("plot.placeMany", new { x, y, objects }, cancellationToken);
        _site = null;
        site.Plot.Tiles = null;
        _stalls = 0;
        _lastInputs = -1;
        _tendAt = default;
        await InventoryAsync(cancellationToken);
        logger.LogInformation("Bot {Bot} set its line on {X}:{Y} up anew", Row.CharacterName, x, y);
    }

    /// <summary>Asks players for the parts it lacks, as many as it can pay for.</summary>
    private Task<bool> AskForPartsAsync(List<(string Item, long Quantity)> missing, BotWorld world, CancellationToken cancellationToken)
    {
        var plot = _plots[0];
        return Task.FromResult(Ask(HelpReasons.Parts, missing, plot, world));
    }

    /// <summary>Puts up a call for help over the plot: an exclamation mark on the world map, as long as the bot can pay.</summary>
    private bool Ask(string reason, IReadOnlyList<(string Item, long Quantity)> needs, BotPlot plot, BotWorld world)
    {
        if (_help is not null)
        {
            return false;
        }

        var pay = BotRules.HelpFee;
        var asked = new List<(string Item, long Quantity)>();
        foreach (var (item, quantity) in needs)
        {
            var worth = (long)Math.Ceiling(Math.Max(Floor(item), 1) * quantity * BotRules.HelpMarkup);
            if (pay + worth + BotRules.Reserve > _money)
            {
                break;
            }

            pay += worth;
            asked.Add((item, quantity));
        }

        if (pay + BotRules.Reserve > _money || needs.Count > 0 && asked.Count == 0)
        {
            return false;
        }

        // Never more than the trader charges for the same parts, so buying them from him to bring them here pays nobody.
        if (asked.Count > 0 && asked.All(a => _traderSells.ContainsKey(a.Item)))
        {
            pay = Math.Min(pay, (long)(asked.Sum(a => _traderSells[a.Item] * a.Quantity) * BotRules.HelpBelowTrader));
        }

        _help = new HelpRequest(Row.Name, Row.CharacterName, Row.AccountId, plot.X, plot.Y, reason, asked, pay, world.Now);
        _helpUntil = world.Now + BotRules.HelpWait;
        _commons.Help.Post(_help);
        logger.LogInformation("Bot {Bot} asks for help on {X}:{Y}: {Reason}", Row.CharacterName, plot.X, plot.Y, reason);
        return true;
    }

    /// <summary>A player answered the call: the parts are in the inventory, or the stalled line is to be set up anew.</summary>
    private async Task<string> HelpedAsync(HelpRequest answered, BotWorld world, CancellationToken cancellationToken)
    {
        _help = null;
        _wantingSince = default;
        await InventoryAsync(cancellationToken);
        _money = (await SendAsync("wallet.get", null, cancellationToken)).Payload.Long("balanceCents");
        if (answered.Reason == HelpReasons.Stalled && _site is { } site)
        {
            await RepairAsync(site, cancellationToken);
            return "helped: line set up anew";
        }

        _tendAt = world.Now;
        return "helped: got parts";
    }

    /// <summary>The market overview: one bot fetches it, and the others use it for a few seconds, as the server sums it up that often anyway.</summary>
    private async Task<JsonElement?> OverviewAsync(BotWorld world, CancellationToken cancellationToken)
    {
        if (_commons.Overview is { } kept && world.Now - kept.At < BotRules.OverviewFor && world.Now >= kept.At)
        {
            return kept.Overview;
        }

        var reply = await SendAsync("market.overview", null, cancellationToken);
        if (!reply.Is("market.overview"))
        {
            return null;
        }

        _commons.Overview = (reply.Payload, world.Now);
        return reply.Payload;
    }

    // ----- The market -----

    private async Task<bool> TradeAsync(string type, string item, long quantity, CancellationToken cancellationToken)
    {
        var before = _money;
        var reply = await SendAsync(type, new { item, quantity = Math.Min(quantity, 1000) }, cancellationToken);
        if (!reply.Is("market.traded"))
        {
            return false;
        }

        if (type == "market.sell")
        {
            _traderIncome += Math.Max(0, _money - before);
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

    /// <summary>What the bot holds back: what its trade keeps, whatever it still means to build on its plots, and its line's parts and their makings.</summary>
    private long Keep(string item) =>
        BotRules.Keep(Profile.Trade, item) + _plots.Where(p => p.Tiles is not null).Sum(p => StillToBuild(p).Count(k => k == item))
        + _reserved.GetValueOrDefault(item);

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
        if (await OverviewAsync(world, cancellationToken) is not { } overview)
        {
            return false;
        }

        var wanted = Wanted().ToHashSet(StringComparer.Ordinal);
        var deals = new List<(string Item, long Price)>();
        foreach (var entry in overview.Each("items"))
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
        // From other bots only what it needs itself: bots buying from bots to sell on only pushed money round in circles.
        var fromBots = wanted.Contains(item);
        foreach (var listing in board.Payload.Each("listings")
                     .Where(l => !l.True("mine") && l.Long("priceCents") <= most && (fromBots || !_commons.IsBot(l.Text("owner")))))
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

        var limit = (BotRules.Buys(Profile.Trade).Contains(item) || _needs.ContainsKey(item)) && Have(item) < 200 ? floor * 2.0
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

        if (await OverviewAsync(world, cancellationToken) is not { } overview)
        {
            return false;
        }

        var options = overview.Each("items")
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
        var wanted = Wanted().Where(i => Have(i) < 20 && Floor(i) > 0).ToList();
        if (wanted.Count == 0)
        {
            return false;
        }

        var item = wanted[world.Random.Next(wanted.Count)];
        var price = Math.Max(1, (long)Math.Round(Math.Max(Floor(item), 1) * (1.1 + world.Random.NextDouble() * 0.3)));
        var quantity = Math.Clamp(_needs.GetValueOrDefault(item, 20), 5, 40);
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
        _contractsAt = world.Now + BotRules.ContractsEvery;
        var view = await SendAsync("contracts.get", null, cancellationToken);
        if (!view.Is("contracts"))
        {
            return false;
        }

        // NPC orders pay new money like the trader does, so they count towards what the bot may take from NPCs in a session.
        var npc = _traderIncome < BotRules.MaxTraderIncome ? view.Payload.Each("npc") : [];
        foreach (var (c, isNpc) in npc.Select(c => (c, true)).Concat(view.Payload.Each("taken").Select(c => (c, false))))
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

            var before = _money;
            var reply = await SendAsync("contracts.deliver", new { id = c.Long("id"), quantity }, cancellationToken);
            if (reply.Is("contracts.done"))
            {
                _inventory[item] = Have(item) - quantity;
                if (isNpc)
                {
                    _traderIncome += Math.Max(0, _money - before);
                }

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
