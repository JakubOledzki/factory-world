using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Research;

/// <summary>One node of the technology tree.</summary>
/// <param name="Id">Stored in the database, so never rename one.</param>
/// <param name="Requires">Technologies that must be researched first.</param>
/// <param name="Cost">Items used up when the research starts.</param>
/// <param name="Unlocks">Items (workbench recipes, machines, machine recipes) the player may make and buy once it is done.</param>
public sealed record Technology(
    string Id, string Name, string Description, IReadOnlyList<string> Requires,
    IReadOnlyList<(string Item, int Quantity)> Cost, TimeSpan Time, int Xp, IReadOnlyList<string> Unlocks);

/// <summary>
/// The technology tree. A new player can make the workbench, the stone furnace and nails, and
/// everything else that no technology lists; belts, inserters, storage and the food machines
/// are researched first. Research uses up its cost at once and takes time, one technology at a
/// time, and goes on while the player is away. Trading between players is never locked, so a
/// player may buy from others what they have not researched yet.
/// </summary>
public static class TechTree
{
    public const string Logistics = "logistics";
    public const string Automation = "automation";
    public const string Sorting = "sorting";
    public const string Storage = "storage";
    public const string Milling = "milling";
    public const string OilPressing = "oil_pressing";
    public const string Pickling = "pickling";
    public const string Baking = "baking";
    public const string GrainStorage = "grain_storage";
    public const string Cooking = "cooking";
    public const string Confectionery = "confectionery";
    public const string ForestryIndustry = "forestry_industry";
    public const string Woodworking = "woodworking";
    public const string IndustrialForestry = "industrial_forestry";
    public const string MiningAutomation = "mining_automation";
    public const string Crushing = "crushing";
    public const string Stonemasonry = "stonemasonry";
    public const string Hydropower = "hydropower";
    public const string Metallurgy = "metallurgy";
    public const string Explosives = "explosives";
    public const string DeepMining = "deep_mining";
    public const string HydroPlant = "hydro_plant";
    public const string CableTransport = "cable_transport";

    public static readonly IReadOnlyList<Technology> Technologies =
    [
        new(Logistics, "Logistyka", "Taśmociągi przewożą przedmioty po działce, a skrzynie i stosy drewna je przechowują.",
            [], [(Items.IronIngot, 10), (Items.Wood, 20)], TimeSpan.FromSeconds(60), 20,
            [Items.Belt, Items.WoodenChest, Items.WoodPile]),
        new(Milling, "Młynarstwo", "Młyn miele pszenicę i kukurydzę na mąkę.",
            [], [(Items.Wheat, 40), (Items.Stone, 20)], TimeSpan.FromSeconds(60), 20,
            [Items.Mill]),
        new(OilPressing, "Tłoczenie oleju", "Tłocznia wyciska olej ze słonecznika.",
            [], [(Items.Sunflower, 30), (Items.IronIngot, 5)], TimeSpan.FromSeconds(90), 20,
            [Items.OilPress]),
        new(Pickling, "Kiszenie", "Beczka do kiszenia zamienia kapustę w kapustę kiszoną.",
            [], [(Items.Cabbage, 20), (Items.Wood, 20), (Items.Nails, 10)], TimeSpan.FromSeconds(60), 20,
            [Items.PicklingBarrel]),
        new(Automation, "Automatyzacja", "Podajniki same przekładają przedmioty między taśmami, maszynami i magazynami.",
            [Logistics], [(Items.IronIngot, 20), (Items.CopperIngot, 10), (Items.Nails, 20)], TimeSpan.FromMinutes(2), 40,
            [Items.Inserter]),
        new(Storage, "Magazynowanie", "Skrzynia żelazna mieści trzy razy więcej niż drewniana, a hałda 1000 sztuk jednego surowca.",
            [Logistics], [(Items.IronIngot, 20), (Items.Stone, 50)], TimeSpan.FromSeconds(90), 30,
            [Items.IronChest, Items.Heap]),
        new(Baking, "Piekarnictwo", "Piec piekarski wypieka chleb z mąki.",
            [Milling], [(Items.Flour, 20), (Items.Stone, 40), (Items.Sand, 10)], TimeSpan.FromMinutes(2), 40,
            [Items.Bakery]),
        new(Sorting, "Sortowanie", "Rozdzielacz dzieli taśmę na dwie i odsyła wybrane przedmioty na jedną stronę.",
            [Automation], [(Items.Belt, 10), (Items.Inserter, 4), (Items.CopperIngot, 10)], TimeSpan.FromMinutes(3), 60,
            [Items.Splitter]),
        new(GrainStorage, "Silosy zbożowe", "Silos mieści 2000 pszenicy, kukurydzy albo słonecznika.",
            [Storage, Milling], [(Items.Wheat, 100), (Items.IronIngot, 20)], TimeSpan.FromMinutes(2), 40,
            [Items.GrainSilo]),
        new(Cooking, "Kuchnia polowa", "Kuchnia gotuje frytki, zupę jarzynową i bigos.",
            [OilPressing, Pickling], [(Items.Sauerkraut, 20), (Items.SunflowerOil, 10), (Items.Potato, 30)], TimeSpan.FromSeconds(150), 60,
            [Items.Kitchen]),
        new(Confectionery, "Cukiernictwo", "Piec piekarski piecze też ciasto marchewkowe.",
            [Baking, OilPressing], [(Items.Bread, 10), (Items.SunflowerOil, 10), (Items.Carrot, 30)], TimeSpan.FromMinutes(3), 60,
            [Items.CarrotCake]),
        new(ForestryIndustry, "Gospodarka leśna", "Chata leśnika sama sadzi i ścina las wokół siebie, a tartak tnie drewno na deski, belki i pellet.",
            [], [(Items.Sapling, 20), (Items.Wood, 50)], TimeSpan.FromSeconds(90), 30,
            [Items.ForesterHut, Items.Sawmill, Items.Planks, Items.Beams, Items.WoodPellets]),
        new(Woodworking, "Przemysł drzewny", "Leśniczówka ma większy las, który rośnie szybciej; tartak elektryczny tnie dwa razy szybciej i skleja sklejkę z desek.",
            [ForestryIndustry, Automation], [(Items.Planks, 40), (Items.Beams, 20), (Items.IronIngot, 20)], TimeSpan.FromMinutes(3), 60,
            [Items.ForesterLodge, Items.ElectricSawmill, Items.Plywood]),
        new(IndustrialForestry, "Leśnictwo przemysłowe", "Nadleśnictwo prowadzi największy las, a tartak przemysłowy robi z kłody trzy deski.",
            [Woodworking], [(Items.Plywood, 20), (Items.Beams, 40), (Items.CopperIngot, 20)], TimeSpan.FromMinutes(5), 100,
            [Items.ForestryStation, Items.IndustrialSawmill]),
        new(Stonemasonry, "Kamieniarstwo", "Warsztat kamieniarski ciosa z kamienia bloki, a z marmuru płyty.",
            [], [(Items.Stone, 100), (Items.IronIngot, 10)], TimeSpan.FromSeconds(90), 30,
            [Items.Stonemason]),
        new(Hydropower, "Energia wodna", "Koło wodne nad wodą albo w górach daje prąd bez paliwa.",
            [], [(Items.Wood, 40), (Items.IronIngot, 20), (Items.CopperIngot, 10)], TimeSpan.FromMinutes(2), 40,
            [Items.WaterWheel]),
        new(MiningAutomation, "Automatyzacja górnictwa", "Wiertło przy kopalni samo wydobywa rudę, a kamieniołom w górach łamie kamień.",
            [Automation], [(Items.IronIngot, 40), (Items.CopperIngot, 20), (Items.Inserter, 4)], TimeSpan.FromMinutes(3), 60,
            [Items.Drill, Items.Quarry]),
        new(Metallurgy, "Metalurgia", "Odlewnia stapia brąz i stal i wypala cegły; z brązu wykujesz lepszy kilof.",
            [], [(Items.CopperIngot, 30), (Items.TinIngot, 10), (Items.IronIngot, 30), (Items.Coal, 30)], TimeSpan.FromMinutes(3), 60,
            [Items.Foundry, Items.BronzePickaxe]),
        new(Crushing, "Kruszenie", "Kruszarka mieli kamień na piasek, a rudę na kruszywo, z którego wytopisz więcej sztabek.",
            [MiningAutomation], [(Items.Stone, 100), (Items.IronIngot, 30)], TimeSpan.FromMinutes(3), 60,
            [Items.Crusher]),
        new(Explosives, "Materiały wybuchowe", "Dynamit wydobywa z kopalni pięć urobków naraz.",
            [Metallurgy], [(Items.Sulfur, 20), (Items.Coal, 20)], TimeSpan.FromMinutes(2), 50,
            [Items.Dynamite]),
        new(DeepMining, "Głębokie górnictwo", "Obudowa górnicza pozwala pogłębić kopalnię do poziomu 4 i 5; wiertło udarowe i kilof stalowy kopią szybciej.",
            [MiningAutomation, Metallurgy], [(Items.SteelIngot, 30), (Items.Beams, 20), (Items.BronzeIngot, 20)], TimeSpan.FromMinutes(5), 100,
            [Items.MineSupport, Items.HeavyDrill, Items.SteelPickaxe]),
        new(HydroPlant, "Elektrownia wodna", "Mała elektrownia wodna daje pięć razy więcej prądu niż koło wodne.",
            [Hydropower, Metallurgy], [(Items.SteelIngot, 20), (Items.Bricks, 40), (Items.CopperIngot, 30)], TimeSpan.FromMinutes(5), 100,
            [Items.HydroPlant]),
        new(CableTransport, "Kolejka linowa", "Stacje kolejki linowej wożą przedmioty po linie nad wszystkim, co stoi po drodze, do 24 pól.",
            [Logistics, Metallurgy], [(Items.SteelIngot, 10), (Items.CopperIngot, 20), (Items.Belt, 10)], TimeSpan.FromMinutes(3), 60,
            [Items.CableStation]),
    ];

    public static readonly IReadOnlyDictionary<string, Technology> ById = Technologies.ToDictionary(t => t.Id);

    /// <summary>The technology that unlocks each item it lists.</summary>
    public static readonly IReadOnlyDictionary<string, Technology> ByItem =
        Technologies.SelectMany(t => t.Unlocks.Select(item => (item, t))).ToDictionary(p => p.item, p => p.t);

    /// <summary>How deep in the tree a technology lies: 0 for the ones with no requirements. The client draws a column for each.</summary>
    public static int Tier(Technology technology) =>
        technology.Requires.Count == 0 ? 0 : 1 + technology.Requires.Max(r => Tier(ById[r]));
}

public enum ResearchStatus { Locked, Available, Active, Done }

/// <summary>The player's research now, after handing out XP for what finished.</summary>
/// <param name="Started">Every technology the player started, done ones included.</param>
/// <param name="Finished">Technologies that finished since the player last asked.</param>
public sealed record ResearchState(
    IReadOnlyDictionary<string, (DateTimeOffset StartsAt, DateTimeOffset FinishesAt)> Started,
    DateTimeOffset ServerTime,
    IReadOnlyList<string> Finished,
    XpGain? Xp)
{
    public bool IsDone(string id) => Started.TryGetValue(id, out var r) && r.FinishesAt <= ServerTime;

    public ResearchStatus Status(Technology technology) =>
        IsDone(technology.Id) ? ResearchStatus.Done
        : Started.ContainsKey(technology.Id) ? ResearchStatus.Active
        : technology.Requires.All(IsDone) ? ResearchStatus.Available
        : ResearchStatus.Locked;
}

public sealed class ResearchService(GameDb db, IInventory inventory, ICharacterProgress progress, TimeProvider time) : ITechnologies
{
    public Task<ResearchState> StateAsync(Guid owner, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var (finished, xp) = await CompleteDueAsync(owner, cancellationToken);
            return await ReadAsync(owner, finished, xp, cancellationToken);
        }, cancellationToken);

    /// <summary>Starts researching a technology whose requirements are done: its cost is used up now, the unlock comes later.</summary>
    public Task<ResearchState> StartAsync(Guid owner, string id, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var technology = TechTree.ById.GetValueOrDefault(id) ?? throw new GameException("no_technology", "There is no such technology.");

            // One start at a time per player, so two at once cannot both pass the check below.
            await using (var lockOwner = await db.CommandAsync("SELECT pg_advisory_xact_lock(@key)", cancellationToken))
            {
                lockOwner.Parameters.AddWithValue("key", BitConverter.ToInt64(owner.ToByteArray()) ^ 0x7265736561726368);
                await lockOwner.ExecuteNonQueryAsync(cancellationToken);
            }

            var (finished, xp) = await CompleteDueAsync(owner, cancellationToken);
            var state = await ReadAsync(owner, finished, xp, cancellationToken);
            switch (state.Status(technology))
            {
                case ResearchStatus.Done:
                    throw new GameException("already_researched", "This technology is already researched.");
                case ResearchStatus.Active:
                case ResearchStatus.Available when state.Started.Keys.Any(t => !state.IsDone(t)):
                    throw new GameException("research_busy", "Another technology is being researched; wait for it or cancel it.");
                case ResearchStatus.Locked:
                    throw new GameException("research_locked", "Research the technologies it needs first.");
            }

            foreach (var (item, quantity) in technology.Cost)
            {
                await inventory.RemoveAsync(owner, item, quantity, cancellationToken);
            }

            var now = time.GetUtcNow();
            await using (var insert = await db.CommandAsync(
                """
                INSERT INTO research.technologies (owner_id, technology, starts_at, finishes_at, rewarded)
                VALUES (@owner, @technology, @start, @end, false)
                """, cancellationToken))
            {
                insert.Parameters.AddWithValue("owner", owner);
                insert.Parameters.AddWithValue("technology", technology.Id);
                insert.Parameters.AddWithValue("start", now);
                insert.Parameters.AddWithValue("end", now + technology.Time);
                await insert.ExecuteNonQueryAsync(cancellationToken);
            }

            return await ReadAsync(owner, finished, xp, cancellationToken);
        }, cancellationToken);

    /// <summary>Calls off the research that is not done yet; its cost comes back.</summary>
    public Task<ResearchState> CancelAsync(Guid owner, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var (finished, xp) = await CompleteDueAsync(owner, cancellationToken);
            await using (var delete = await db.CommandAsync(
                "DELETE FROM research.technologies WHERE owner_id = @owner AND finishes_at > @now RETURNING technology", cancellationToken))
            {
                delete.Parameters.AddWithValue("owner", owner);
                delete.Parameters.AddWithValue("now", time.GetUtcNow());
                if (await delete.ExecuteScalarAsync(cancellationToken) is not string id)
                {
                    throw new GameException("no_research", "Nothing is being researched.");
                }

                if (TechTree.ById.TryGetValue(id, out var technology))
                {
                    foreach (var (item, quantity) in technology.Cost)
                    {
                        await inventory.AddAsync(owner, item, quantity, cancellationToken);
                    }
                }
            }

            return await ReadAsync(owner, finished, xp, cancellationToken);
        }, cancellationToken);

    public async Task<IReadOnlyDictionary<string, string>> LockedAsync(Guid player, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT technology FROM research.technologies WHERE owner_id = @owner AND finishes_at <= @now", cancellationToken);
        command.Parameters.AddWithValue("owner", player);
        command.Parameters.AddWithValue("now", time.GetUtcNow());
        var done = new HashSet<string>();
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                done.Add(reader.GetString(0));
            }
        }

        return TechTree.ByItem.Where(p => !done.Contains(p.Value.Id)).ToDictionary(p => p.Key, p => p.Value.Name);
    }

    public async Task RequireUnlockedAsync(Guid player, string item, CancellationToken cancellationToken)
    {
        if (TechTree.ByItem.ContainsKey(item) && (await LockedAsync(player, cancellationToken)).TryGetValue(item, out var technology))
        {
            throw new GameException("locked", $"Research {technology} first.");
        }
    }

    private async Task<(IReadOnlyList<string> Finished, XpGain? Xp)> CompleteDueAsync(Guid owner, CancellationToken cancellationToken)
    {
        // UPDATE ... RETURNING hands each finished technology's XP to exactly one request.
        await using var command = await db.CommandAsync(
            """
            UPDATE research.technologies SET rewarded = true
            WHERE owner_id = @owner AND NOT rewarded AND finishes_at <= @now
            RETURNING technology
            """, cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        command.Parameters.AddWithValue("now", time.GetUtcNow());
        var finished = new List<string>();
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                finished.Add(reader.GetString(0));
            }
        }

        var xp = finished.Sum(id => TechTree.ById.TryGetValue(id, out var t) ? t.Xp : 0);
        return xp > 0 ? (finished, await progress.AddXpAsync(owner, xp, cancellationToken)) : (finished, null);
    }

    private async Task<ResearchState> ReadAsync(Guid owner, IReadOnlyList<string> finished, XpGain? xp, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT technology, starts_at, finishes_at FROM research.technologies WHERE owner_id = @owner", cancellationToken);
        command.Parameters.AddWithValue("owner", owner);
        var started = new Dictionary<string, (DateTimeOffset, DateTimeOffset)>();
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                started[reader.GetString(0)] = (reader.GetFieldValue<DateTimeOffset>(1), reader.GetFieldValue<DateTimeOffset>(2));
            }
        }

        return new ResearchState(started, time.GetUtcNow(), finished, xp);
    }
}

public sealed record StartResearchRequest(string Technology);

public abstract class ResearchHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public abstract string Type { get; }

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var state = await RunAsync(scope.ServiceProvider.GetRequiredService<ResearchService>(), client.RequireAccount(), payload, cancellationToken);
        return new Reply("research", new
        {
            // Unix milliseconds: the client compares them with serverTime, not its own clock.
            technologies = TechTree.Technologies.Select(t => new
            {
                id = t.Id,
                name = t.Name,
                description = t.Description,
                tier = TechTree.Tier(t),
                requires = t.Requires,
                cost = t.Cost.Select(c => new { id = c.Item, name = Items.Names[c.Item], quantity = c.Quantity }),
                seconds = t.Time.TotalSeconds,
                xp = t.Xp,
                unlocks = t.Unlocks.Select(u => new { id = u, name = Items.Names[u] }),
                status = state.Status(t) switch
                {
                    ResearchStatus.Done => "done",
                    ResearchStatus.Active => "active",
                    ResearchStatus.Available => "available",
                    _ => "locked",
                },
                startsAt = state.Started.TryGetValue(t.Id, out var r) ? r.StartsAt.ToUnixTimeMilliseconds() : (long?)null,
                finishesAt = state.Started.TryGetValue(t.Id, out var f) ? f.FinishesAt.ToUnixTimeMilliseconds() : (long?)null,
            }),
            serverTime = state.ServerTime.ToUnixTimeMilliseconds(),
            finished = state.Finished.Where(TechTree.ById.ContainsKey).Select(id => new { id, name = TechTree.ById[id].Name }),
            xp = state.Xp is { } xp ? new { xp = xp.Xp, level = xp.Level, leveledUp = xp.LeveledUp } : null,
        });
    }

    protected abstract Task<ResearchState> RunAsync(ResearchService research, Guid owner, JsonElement? payload, CancellationToken cancellationToken);
}

/// <summary>The tree and the player's research; also hands out XP for finished research, so the client calls it when a timer runs out.</summary>
public sealed class GetResearchHandler(IServiceScopeFactory scopes) : ResearchHandler(scopes)
{
    public override string Type => "research.get";

    protected override Task<ResearchState> RunAsync(ResearchService research, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        research.StateAsync(owner, cancellationToken);
}

public sealed class StartResearchHandler(IServiceScopeFactory scopes) : ResearchHandler(scopes)
{
    public override string Type => "research.start";

    protected override Task<ResearchState> RunAsync(ResearchService research, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        research.StartAsync(owner, Payload.Read<StartResearchRequest>(payload).Technology ?? "", cancellationToken);
}

public sealed class CancelResearchHandler(IServiceScopeFactory scopes) : ResearchHandler(scopes)
{
    public override string Type => "research.cancel";

    protected override Task<ResearchState> RunAsync(ResearchService research, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        research.CancelAsync(owner, cancellationToken);
}
