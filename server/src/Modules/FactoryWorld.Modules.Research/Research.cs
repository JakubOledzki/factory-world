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
/// <param name="CompanyOnly">Only a company researches it, for all its members (<see cref="CompanyTechs"/>).</param>
public sealed record Technology(
    string Id, string Name, string Description, IReadOnlyList<string> Requires,
    IReadOnlyList<(string Item, int Quantity)> Cost, TimeSpan Time, int Xp, IReadOnlyList<string> Unlocks, bool CompanyOnly = false);

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
    public const string Fishing = "fishing";
    public const string FishProcessing = "fish_processing";
    public const string Seafaring = "seafaring";
    public const string Aquaculture = "aquaculture";
    public const string SaltWorks = "salt_works";
    public const string TidalPower = "tidal_power";
    public const string OilExtraction = "oil_extraction";
    public const string Refining = "refining";
    public const string Cracking = "cracking";
    public const string Petrochemistry = "petrochemistry";
    public const string Combustion = "combustion";
    public const string Roads = "roads";
    public const string OffshoreDrilling = "offshore_drilling";
    public const string EnhancedRecovery = "enhanced_recovery";
    public const string Glassmaking = "glassmaking";
    public const string SiliconWorks = "silicon";
    public const string SolarPower = "solar_power";
    public const string SolarTower = "solar_tower";
    public const string WaterSupply = "water_supply";
    public const string BuildingMaterials = "building_materials";
    public const string WindPower = "wind_power";
    public const string LargeWind = "large_wind";
    public const string Heating = "heating";
    public const string Refrigeration = "refrigeration";
    public const string Glaciology = "glaciology";
    public const string DataCenter = "data_center";
    public const string PolarTourism = "polar_tourism";
    public const string PolarTransport = "polar_transport";
    public const string Assembly = "assembly";
    public const string Commerce = "commerce";
    public const string UrbanConstruction = "urban_construction";
    public const string CityServices = "city_services";
    public const string WasteManagement = "waste_management";
    public const string FreightHub = "freight_hub";
    public const string Headquarters = "headquarters";
    public const string Tailoring = "tailoring";
    public const string Silviculture = "silviculture";
    public const string Papermaking = "papermaking";
    public const string Furniture = "furniture";
    public const string Charring = "charring";
    public const string Beekeeping = "beekeeping";
    public const string ForestFoods = "forest_foods";
    public const string FireProtection = "fire_protection";

    // The crafting tree: one technology for each of its items, named after it.
    public const string Lubricant = "lubricant";
    public const string ElectricWire = "electric_wire";
    public const string GlassLaminate = "glass_laminate";
    public const string Paint = "paint";
    public const string CaseinGlue = "casein_glue";
    public const string InsulationBoard = "insulation_board";
    public const string Firebrick = "firebrick";
    public const string PrecastConcrete = "precast_concrete";
    public const string Coolant = "coolant";
    public const string IridiumAlloy = "iridium_alloy";
    public const string Provisions = "provisions";
    public const string Bearing = "bearing";
    public const string PaintedSheet = "painted_sheet";
    public const string Coil = "coil";
    public const string WiringHarness = "wiring_harness";
    public const string RefractoryLining = "refractory_lining";
    public const string CarbonComposite = "carbon_composite";
    public const string SuperconductingWire = "superconducting_wire";
    public const string RocketFuel = "rocket_fuel";
    public const string Gearbox = "gearbox";
    public const string Rotor = "rotor";
    public const string MachineHousing = "machine_housing";
    public const string CombustionChamber = "combustion_chamber";
    public const string CompositePanel = "composite_panel";
    public const string SuperconductingMagnet = "superconducting_magnet";
    public const string Alternator = "alternator";
    public const string ControlModule = "control_module";
    public const string HydraulicActuator = "hydraulic_actuator";
    public const string RocketNozzle = "rocket_nozzle";
    public const string PressureVessel = "pressure_vessel";
    public const string ComputingCore = "computing_core";
    public const string RobotArm = "robot_arm";
    public const string Turbopump = "turbopump";
    public const string TurbineSet = "turbine_set";
    public const string CryogenicTank = "cryogenic_tank";
    public const string IndustrialRobot = "industrial_robot";
    public const string NavigationSystem = "navigation_system";
    public const string RocketEngine = "rocket_engine";
    public const string PlasmaChamber = "plasma_chamber";
    public const string Avionics = "avionics";
    public const string PlasmaControl = "plasma_control";
    public const string RocketStage = "rocket_stage";
    public const string Satellite = "satellite";
    public const string FusionReactor = "fusion_reactor";
    public const string LaunchRocket = "launch_rocket";
    public const string MachineShop = "machine_shop";
    public const string RoboticHall = "robotic_hall";
    public const string OxygenConverter = "oxygen_converter";
    public const string RollingMill = "rolling_mill";
    public const string ControlCenter = "control_center";
    public const string ContinuousCaster = "continuous_caster";
    public const string AutomatedWarehouse = "automated_warehouse";
    public const string SteelCombine = "steel_combine";
    public const string Megafactory = "megafactory";
    public const string FusionPlant = "fusion_plant";

    public const string Megaprojects = CompanyTechs.Megaprojects;
    public const string CorporateFinance = CompanyTechs.CorporateFinance;

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
        new(Fishing, "Rybołówstwo", "Stocznia buduje kutry i łodzie, które same łowią ryby z brzegu, a wędzarnia wędzi dorsza.",
            [], [(Items.Herring, 20), (Items.Wood, 40), (Items.IronIngot, 10)], TimeSpan.FromSeconds(90), 30,
            [Items.Shipyard, Items.FishingBoat, Items.RowingBoat, Items.Smokehouse, Items.SmokedFish]),
        new(FishProcessing, "Przetwórstwo ryb", "Konserwiarnia puszkuje śledzie i mieli resztki na mączkę i olej; śledzie się soli, karpia smaży, a z szczupaka gotuje zupę.",
            [Fishing, OilPressing], [(Items.Herring, 40), (Items.TinIngot, 5), (Items.SunflowerOil, 5)], TimeSpan.FromMinutes(2), 50,
            [Items.Cannery, Items.CannedFish, Items.FishMeal, Items.FishOil, Items.SaltedHerring, Items.FriedCarp, Items.FishSoup]),
        new(Seafaring, "Żegluga", "Przystań wysyła towary statkiem do przystani innej działki, a falochron pozwala łowić w sztorm; latarnia skraca rejsy.",
            [Fishing, Logistics], [(Items.Planks, 40), (Items.Beams, 20), (Items.Stone, 60)], TimeSpan.FromMinutes(3), 60,
            [Items.Port, Items.Breakwater, Items.Lighthouse]),
        new(Aquaculture, "Akwakultura", "Farma ryb hoduje łososie na mączce rybnej i małże na linach; wędzarnia wędzi też łososia.",
            [FishProcessing], [(Items.FishMeal, 20), (Items.Beams, 10), (Items.IronIngot, 20)], TimeSpan.FromMinutes(3), 60,
            [Items.FishFarm, Items.SmokedSalmon]),
        new(SaltWorks, "Warzelnictwo", "Warzelnia na brzegu morza odparowuje sól z wody morskiej.",
            [], [(Items.Stone, 40), (Items.Sand, 20)], TimeSpan.FromSeconds(60), 20,
            [Items.SaltPan]),
        new(TidalPower, "Energia pływów", "Elektrownia pływowa na brzegu morza daje prąd bez paliwa, dzień i noc.",
            [Hydropower, Seafaring], [(Items.SteelIngot, 20), (Items.CopperIngot, 30), (Items.Bricks, 40)], TimeSpan.FromMinutes(5), 100,
            [Items.TidalPlant]),
        new(OilExtraction, "Wydobycie ropy", "Żuraw pompowy i głowica gazowa pompują to, co badanie znalazło pod działką; rury, pompy i zbiorniki przenoszą płyny.",
            [Metallurgy, Automation], [(Items.SteelIngot, 500), (Items.IronIngot, 1_500), (Items.CopperIngot, 1_000)], TimeSpan.FromMinutes(150), 80,
            [Items.Pumpjack, Items.GasWell, Items.Pipe, Items.Pump, Items.Tank, Items.Gasket]),
        new(Refining, "Rafinacja", "Destylarnia i rafineria rozdzielają ropę na benzynę, olej napędowy, naftę i asfalt.",
            [OilExtraction], [(Items.CrudeOil, 2_500), (Items.SteelIngot, 1_000), (Items.Bricks, 1_000)], TimeSpan.FromMinutes(200), 100,
            [Items.Distillery, Items.Refinery, Items.Gasoline, Items.Diesel, Items.Kerosene, Items.Asphalt]),
        new(Cracking, "Kraking", "Instalacja krakingu rozbija ciężkie paliwa na benzynę.",
            [Refining], [(Items.Diesel, 1_500), (Items.Kerosene, 1_500), (Items.SteelIngot, 1_000)], TimeSpan.FromMinutes(250), 120,
            [Items.Cracker]),
        new(Petrochemistry, "Petrochemia", "Zakład chemiczny robi z gazu tworzywo sztuczne i nawóz, a z nafty i siarki kauczuk na opony.",
            [Refining], [(Items.NaturalGas, 2_000), (Items.Kerosene, 1_000), (Items.SteelIngot, 1_000)], TimeSpan.FromMinutes(250), 120,
            [Items.ChemicalPlant, Items.Plastic, Items.SyntheticRubber, Items.Fertilizer]),
        new(Combustion, "Silniki spalinowe", "Elektrownia gazowa i agregat spalinowy dają dużo prądu z gazu, oleju napędowego albo benzyny.",
            [Refining], [(Items.Diesel, 1_000), (Items.SteelIngot, 1_000), (Items.CopperIngot, 1_000)], TimeSpan.FromMinutes(200), 100,
            [Items.GasPlant, Items.DieselGenerator]),
        new(Roads, "Drogi", "Z asfaltu i kamienia układa się drogę: po asfalcie chodzi się szybciej.",
            [Refining], [(Items.Asphalt, 1_000), (Items.Stone, 2_000)], TimeSpan.FromMinutes(100), 40,
            [Items.Road]),
        new(OffshoreDrilling, "Wiercenia morskie", "Platforma wiertnicza na brzegu morza pompuje ropę spod dna, z dużego złoża.",
            [OilExtraction, Seafaring], [(Items.SteelIngot, 2_000), (Items.CrudeOil, 5_000), (Items.Beams, 1_000)], TimeSpan.FromHours(5), 150,
            [Items.OffshorePlatform]),
        new(EnhancedRecovery, "Wspomagane wydobycie", "Tłocznia wody wyciska ze złoża o połowę więcej ropy, a separator zbiera wycieki.",
            [OilExtraction], [(Items.CrudeOil, 4_000), (Items.SteelIngot, 1_000), (Items.Gasket, 500)], TimeSpan.FromMinutes(200), 100,
            [Items.WaterInjector, Items.OilSeparator]),
        new(Glassmaking, "Hutnictwo szkła", "Huta szkła topi piasek na szkło (na piasku o 30% szybciej), dmucha butelki ze stłuczki i robi szyby i lustra.",
            [], [(Items.Sand, 60), (Items.Stone, 20), (Items.Wood, 20)], TimeSpan.FromSeconds(90), 30,
            [Items.Glassworks, Items.Glass, Items.GlassBottles, Items.WindowPane, Items.Mirror]),
        new(SiliconWorks, "Krzem", "Piec łukowy na prąd robi krzem z kwarcu i tnie go na płytki, a huta szkła ciągnie światłowód.",
            [Glassmaking, Metallurgy], [(Items.Quartz, 20), (Items.Coal, 20), (Items.CopperIngot, 20)], TimeSpan.FromMinutes(3), 80,
            [Items.ArcFurnace, Items.Silicon, Items.SiliconWafer, Items.OpticalFiber]),
        new(SolarPower, "Energia słoneczna", "Panele słoneczne dają prąd za dnia, akumulatory go przechowują, a płot trzcinowy chroni przed burzą piaskową.",
            [SiliconWorks], [(Items.SiliconWafer, 10), (Items.Glass, 20), (Items.CopperIngot, 20)], TimeSpan.FromMinutes(4), 100,
            [Items.SolarPanel, Items.Battery, Items.ReedFence]),
        new(SolarTower, "Elektrownia słoneczna", "Wieża z lustrami na pustyni albo w oazie daje za dnia 600 kW.",
            [SolarPower], [(Items.Mirror, 20), (Items.SteelIngot, 30), (Items.StoneBlocks, 20)], TimeSpan.FromMinutes(6), 150,
            [Items.SolarTower]),
        new(WaterSupply, "Wodociągi", "Studnia głębinowa pompuje wodę spod ziemi, a odsalarka na wybrzeżu robi ją z morza.",
            [Automation], [(Items.IronIngot, 20), (Items.CopperIngot, 10), (Items.Stone, 30)], TimeSpan.FromMinutes(2), 50,
            [Items.WaterWell, Items.Desalinator]),
        new(BuildingMaterials, "Materiały budowlane", "Suszarnia robi cegłę z piasku, gliny i wody, piec cementowy cement, a betoniarka beton.",
            [WaterSupply], [(Items.Clay, 20), (Items.Stone, 40), (Items.Sand, 40)], TimeSpan.FromMinutes(3), 60,
            [Items.DryingYard, Items.CementKiln, Items.ConcreteMixer, Items.AdobeBricks, Items.Cement, Items.Concrete]),
        new(WindPower, "Energia wiatrowa", "Turbina wiatrowa daje prąd bez paliwa, tyle, ile wieje wiatr: najwięcej na lodowcu, stepie i tundrze.",
            [Automation], [(Items.IronIngot, 30), (Items.CopperIngot, 20), (Items.Planks, 20)], TimeSpan.FromMinutes(2), 50,
            [Items.WindTurbine]),
        new(LargeWind, "Duże turbiny wiatrowe", "Duża turbina na 3 × 3 kafelkach daje w pełnym wietrze 400 kW.",
            [WindPower, BuildingMaterials], [(Items.SteelIngot, 40), (Items.Concrete, 20), (Items.Iridium, 2)], TimeSpan.FromMinutes(6), 150,
            [Items.LargeWindTurbine]),
        new(Heating, "Ogrzewanie", "Kocioł grzewczy na drewno, węgiel albo pellet grzeje maszyny wokół siebie, a topielnik zamienia lód w wodę.",
            [], [(Items.IronIngot, 15), (Items.Stone, 30), (Items.Coal, 20)], TimeSpan.FromSeconds(90), 30,
            [Items.Heater, Items.IceMelter]),
        new(Refrigeration, "Chłodnictwo", "Chłodnia mrozi ryby i robi lody: na lodowcu za darmo, gdzie indziej na bloku lodu za każdą partię.",
            [Heating], [(Items.Ice, 30), (Items.IronIngot, 20), (Items.CopperIngot, 10)], TimeSpan.FromMinutes(2), 50,
            [Items.ColdStore, Items.FrozenFish, Items.FrozenSalmon, Items.IceCream]),
        new(Glaciology, "Glacjologia", "Wiertnica lodowa wyciąga rdzenie z lodowca, a stacja polarna robi z nich dane naukowe, które przyspieszają badania.",
            [Heating, Automation], [(Items.Ice, 40), (Items.SteelIngot, 15), (Items.CopperIngot, 15)], TimeSpan.FromMinutes(3), 80,
            [Items.IceCoreDrill, Items.PolarStation, Items.IceCore, Items.ResearchData]),
        new(DataCenter, "Centrum danych", "Serwerownia na prąd liczy dla badań; na lodowcu chłodzi ją powietrze, gdzie indziej lód.",
            [SiliconWorks], [(Items.SiliconWafer, 20), (Items.OpticalFiber, 10), (Items.CopperIngot, 30)], TimeSpan.FromMinutes(5), 120,
            [Items.ServerRoom, Items.ComputingPower]),
        new(PolarTourism, "Turystyka polarna", "Hotel lodowy i punkt widokowy na lodowcu albo w tundrze zarabiają na turystach, trzy razy więcej przy zorzy.",
            [Heating], [(Items.Ice, 60), (Items.Planks, 30), (Items.Wool, 10)], TimeSpan.FromMinutes(3), 60,
            [Items.IceHotel, Items.Viewpoint]),
        new(PolarTransport, "Transport polarny", "Psi zaprzęg i skuter śnieżny wiozą ładunki z lodowca bez torów, a fundament pozwala pociągom jeździć po lodzie pełną prędkością.",
            [], [(Items.Planks, 30), (Items.Wool, 10), (Items.IronIngot, 20)], TimeSpan.FromMinutes(2), 40,
            [Items.DogKennel, Items.SnowmobileGarage, Items.TrackFoundation]),
        new(Assembly, "Montaż", "Hala montażowa na prąd składa płytki drukowane i silniki z towarów innych biomów; w mieście o 25% szybciej.",
            [Automation, Petrochemistry], [(Items.SteelIngot, 30), (Items.Plastic, 20), (Items.CopperIngot, 20)], TimeSpan.FromMinutes(4), 100,
            [Items.AssemblyHall, Items.CircuitBoard, Items.ElectricMotor]),
        new(Commerce, "Handel", "Sklep w mieście sprzedaje twoje towary mieszkańcom przez całą dobę, po cenach, które sam ustawisz.",
            [], [(Items.Planks, 20), (Items.Bread, 20), (Items.Glass, 10)], TimeSpan.FromMinutes(2), 40,
            [Items.Shop]),
        new(UrbanConstruction, "Budownictwo miejskie", "Działka w mieście jest ciasna, więc buduje się w górę: magazyn wysokiego składowania i fabryka wielopiętrowa.",
            [BuildingMaterials, Assembly], [(Items.Concrete, 40), (Items.SteelIngot, 30), (Items.Glass, 20)], TimeSpan.FromMinutes(6), 150,
            [Items.HighBay, Items.MultistoreyFactory]),
        new(CityServices, "Usługi", "Biuro projektowe, laboratorium i warsztat serwisowy pracują dla ciebie i sprzedają usługi innym graczom w mieście.",
            [], [(Items.Glass, 20), (Items.Planks, 30), (Items.CopperIngot, 10)], TimeSpan.FromMinutes(3), 60,
            [Items.DesignOffice, Items.Laboratory, Items.ServiceWorkshop, Items.Blueprint]),
        new(WasteManagement, "Gospodarka odpadami", "Odbierasz śmieci z miasta za opłatę, a sortownia miejska na prąd rozdziela je na surowce wtórne.",
            [Sorting], [(Items.IronIngot, 20), (Items.Trash, 50)], TimeSpan.FromMinutes(2), 40,
            [Items.CitySorter]),
        new(FreightHub, "Centrum logistyczne", "Dworzec towarowy w mieście obniża opłaty kolejowe działki o 25% i pozwala jej wysyłać 10 kursów zamiast 5.",
            [Logistics, BuildingMaterials], [(Items.Concrete, 30), (Items.SteelIngot, 20), (Items.Bricks, 30)], TimeSpan.FromMinutes(4), 80,
            [Items.FreightTerminal]),
        new(Headquarters, "Siedziba spółki", "Siedziba w mieście pozwala spółce przyjąć 30 członków zamiast 20 i potraja jej wspólny magazyn.",
            [CityServices], [(Items.Concrete, 40), (Items.MarbleSlabs, 20), (Items.Blueprint, 2)], TimeSpan.FromMinutes(5), 100,
            [Items.CompanyHq]),
        new(Tailoring, "Krawiectwo", "Pracownia krawiecka w mieście szyje ubrania, które przyspieszają pracę w leśnictwie, górnictwie, rolnictwie, rybołówstwie i rzemiośle albo poprawiają ceny u handlarza.",
            [], [(Items.Wool, 40), (Items.Planks, 20), (Items.IronIngot, 10)], TimeSpan.FromMinutes(3), 60,
            [Items.Tailor, .. Items.Clothes.Keys]),
        new(Silviculture, "Hodowla lasu", "Sadzonki świerku, brzozy, dębu i lipy u handlarza i wieża obserwacyjna, z której widać pożar, zanim się rozprzestrzeni.",
            [ForestryIndustry], [(Items.Sapling, 20), (Items.Wood, 40)], TimeSpan.FromSeconds(90), 30,
            [Items.SaplingSpruce, Items.SaplingBirch, Items.SaplingOak, Items.SaplingLinden, Items.Watchtower]),
        new(Papermaking, "Papiernictwo", "Papiernia na prąd robi masę celulozową z pelletu i wody, z niej papier, a z makulatury karton.",
            [Woodworking], [(Items.WoodPellets, 40), (Items.IronIngot, 20), (Items.CopperIngot, 10)], TimeSpan.FromMinutes(3), 60,
            [Items.PaperMill, Items.Pulp, Items.Paper, Items.Cardboard]),
        new(Furniture, "Meblarstwo", "Stolarnia robi krzesła, stoły i szafy, a z drewna dębowego komody, na które czekają miasta.",
            [ForestryIndustry], [(Items.Planks, 40), (Items.Nails, 30)], TimeSpan.FromMinutes(2), 40,
            [Items.Carpentry, Items.Chair, Items.Table, Items.Wardrobe, Items.OakDresser]),
        new(Charring, "Węglarstwo i smolarstwo", "Mielerz wypala z drewna węgiel drzewny, który pali się jak kopalny, a smolarnia warzy z żywicy smołę, terpentynę i kalafonię.",
            [ForestryIndustry], [(Items.Wood, 60), (Items.Stone, 40)], TimeSpan.FromMinutes(2), 40,
            [Items.CharcoalKiln, Items.Charcoal, Items.TarKiln, Items.Tar, Items.Turpentine, Items.Rosin]),
        new(Beekeeping, "Pszczelarstwo", "Ul daje miód i wosk, szybciej przy kwitnących lipach; z miodu pieczesz pierniki, z wosku robisz świece.",
            [], [(Items.Planks, 20), (Items.Sapling, 5)], TimeSpan.FromSeconds(90), 30,
            [Items.Beehive, Items.Gingerbread, Items.Candles]),
        new(ForestFoods, "Leśna spiżarnia", "Kuchnia gotuje zupę grzybową, pierogi z jagodami i herbatę z ziół zebranych w lesie.",
            [Cooking], [(Items.Mushrooms, 20), (Items.Berries, 20)], TimeSpan.FromSeconds(90), 30,
            [Items.MushroomSoup, Items.BerryPierogi, Items.HerbalTea]),
        new(FireProtection, "Ochrona lasu", "Strażnica chroni drzewa wokół siebie przed ogniem, a zakłady chemiczne robią z terpentyny środek na kornika.",
            [Silviculture, Charring], [(Items.Bricks, 20), (Items.IronIngot, 20), (Items.Turpentine, 5)], TimeSpan.FromMinutes(3), 60,
            [Items.FireStation, Items.Insecticide]),
        // The crafting tree, level by level: each technology unlocks one item and needs the technologies of its ingredients first.
        new(Lubricant, "Smar techniczny", "Smaruje łożyska, przekładnie i siłowniki.",
            [Refining], [(Items.Kerosene, 10), (Items.Wax, 5)], TimeSpan.FromMinutes(2), 20,
            [Items.Lubricant]),
        new(ElectricWire, "Przewód elektryczny", "Miedź w izolacji z tworzywa: z niej są cewki, wiązki i drut nadprzewodzący.",
            [MachineShop], [(Items.CopperIngot, 5), (Items.Plastic, 5)], TimeSpan.FromMinutes(2), 20,
            [Items.ElectricWire]),
        new(GlassLaminate, "Laminat szklany", "Włókno szklane w żywicy: lekki i twardy, na cewki i kompozyty.",
            [Petrochemistry], [(Items.Glass, 10), (Items.Resin, 5), (Items.Plastic, 5)], TimeSpan.FromMinutes(2), 20,
            [Items.GlassLaminate]),
        new(Paint, "Farba", "Terpentyna, olej i glina na pigment; chroni blachę przed rdzą.",
            [Charring], [(Items.Turpentine, 5), (Items.SunflowerOil, 5), (Items.Clay, 5)], TimeSpan.FromMinutes(2), 20,
            [Items.Paint]),
        new(CaseinGlue, "Klej kazeinowy", "Klej z mleka i kalafonii: skleja kompozyty, wiązki i panele.",
            [Charring], [(Items.Milk, 10), (Items.Rosin, 5)], TimeSpan.FromMinutes(2), 20,
            [Items.CaseinGlue]),
        new(InsulationBoard, "Płyta izolacyjna", "Wełna między sklejką: trzyma ciepło i zimno, na obudowy i zbiorniki.",
            [Furniture], [(Items.Wool, 10), (Items.Plywood, 5)], TimeSpan.FromMinutes(2), 20,
            [Items.InsulationBoard]),
        new(Firebrick, "Cegła szamotowa", "Cegła z gliny i kwarcu, która wytrzymuje ogień pieców i dysz.",
            [Metallurgy], [(Items.Clay, 10), (Items.Quartz, 5)], TimeSpan.FromMinutes(2), 20,
            [Items.Firebrick]),
        new(PrecastConcrete, "Prefabrykat żelbetowy", "Beton ze stalowym zbrojeniem: fundament wielkich budynków.",
            [BuildingMaterials], [(Items.Concrete, 20), (Items.SteelIngot, 5)], TimeSpan.FromMinutes(2), 20,
            [Items.PrecastConcrete]),
        new(Coolant, "Płyn chłodniczy", "Schłodzony lodem glikol z gazu: chłodzi rdzenie, magnesy i reaktor.",
            [Petrochemistry], [(Items.NaturalGas, 10), (Items.Water, 10), (Items.Ice, 10)], TimeSpan.FromMinutes(2), 20,
            [Items.Coolant]),
        new(IridiumAlloy, "Stop irydowy", "Iryd i żelazo meteorytowe z lodowca stopione ze stalą.",
            [SiliconWorks], [(Items.Iridium, 5), (Items.MeteoricIron, 10), (Items.SteelIngot, 10)], TimeSpan.FromMinutes(2), 20,
            [Items.IridiumAlloy]),
        new(Provisions, "Prowiant", "Paczka jedzenia na długą drogę: dla załogi stacji orbitalnej.",
            [Cooking], [(Items.CannedFish, 5), (Items.Bread, 10), (Items.Cardboard, 5)], TimeSpan.FromMinutes(2), 20,
            [Items.Provisions]),
        new(Bearing, "Łożysko", "Stalowe kulki w smarze: bez nich nic się nie kręci.",
            [Lubricant, MachineShop], [(Items.SteelIngot, 5), (Items.Lubricant, 5)], TimeSpan.FromMinutes(3), 40,
            [Items.Bearing]),
        new(PaintedSheet, "Blacha lakierowana", "Stalowa blacha pomalowana na obudowy i zbiorniki.",
            [Paint, MachineShop], [(Items.SteelIngot, 5), (Items.Paint, 5)], TimeSpan.FromMinutes(3), 40,
            [Items.PaintedSheet]),
        new(Coil, "Cewka", "Przewód nawinięty na laminat: serce wirnika i magnesu.",
            [ElectricWire, GlassLaminate, MachineShop], [(Items.ElectricWire, 30), (Items.GlassLaminate, 5)], TimeSpan.FromMinutes(3), 40,
            [Items.Coil]),
        new(WiringHarness, "Wiązka kablowa", "Przewody związane w jedną wiązkę, która łączy maszynę w całość.",
            [ElectricWire, CaseinGlue, MachineShop], [(Items.ElectricWire, 40), (Items.SyntheticRubber, 5), (Items.CaseinGlue, 5)], TimeSpan.FromMinutes(3), 40,
            [Items.WiringHarness]),
        new(RefractoryLining, "Okładzina ogniotrwała", "Wyłożenie z cegły szamotowej na komory spalania i plazmy.",
            [Firebrick, PrecastConcrete, Stonemasonry], [(Items.Firebrick, 40), (Items.PrecastConcrete, 5)], TimeSpan.FromMinutes(3), 40,
            [Items.RefractoryLining]),
        new(CarbonComposite, "Kompozyt węglowy", "Laminat z węglem drzewnym: lżejszy od stali i równie mocny.",
            [GlassLaminate, CaseinGlue, Petrochemistry], [(Items.GlassLaminate, 10), (Items.Charcoal, 10), (Items.CaseinGlue, 5)], TimeSpan.FromMinutes(3), 40,
            [Items.CarbonComposite]),
        new(SuperconductingWire, "Drut nadprzewodzący", "Drut ze stopu irydowego, który w zimnie przewodzi bez strat.",
            [IridiumAlloy, ElectricWire, Coolant, MachineShop], [(Items.IridiumAlloy, 5), (Items.ElectricWire, 20), (Items.Coolant, 10)], TimeSpan.FromMinutes(3), 40,
            [Items.SuperconductingWire]),
        new(RocketFuel, "Paliwo rakietowe", "Schłodzona nafta: rakieta wynosi na orbitę satelitę na dwustu porcjach.",
            [Coolant, Refining], [(Items.Kerosene, 15), (Items.Coolant, 5)], TimeSpan.FromMinutes(3), 40,
            [Items.RocketFuel]),
        new(Gearbox, "Przekładnia", "Koła zębate z brązu na łożyskach: zmienia obroty na siłę.",
            [Bearing, Lubricant, MachineShop], [(Items.BronzeIngot, 6), (Items.Bearing, 6), (Items.Lubricant, 3)], TimeSpan.FromMinutes(4), 60,
            [Items.Gearbox]),
        new(Rotor, "Wirnik", "Cewki na stalowym wale: kręci się w prądnicy i turbopompie.",
            [Coil, Bearing, MachineShop], [(Items.Coil, 6), (Items.Bearing, 6), (Items.SteelIngot, 6)], TimeSpan.FromMinutes(4), 60,
            [Items.Rotor]),
        new(MachineHousing, "Obudowa przemysłowa", "Szczelna, ocieplona skrzynia na prądnice i moduły sterujące.",
            [PaintedSheet, InsulationBoard, MachineShop], [(Items.PaintedSheet, 12), (Items.InsulationBoard, 3), (Items.Gasket, 6)], TimeSpan.FromMinutes(4), 60,
            [Items.MachineHousing]),
        new(CombustionChamber, "Komora spalania", "Stalowa komora wyłożona szamotem, w której pali się paliwo rakietowe.",
            [RefractoryLining, MachineShop], [(Items.RefractoryLining, 6), (Items.SteelIngot, 12), (Items.Gasket, 6)], TimeSpan.FromMinutes(4), 60,
            [Items.CombustionChamber]),
        new(CompositePanel, "Panel kompozytowy", "Lekka i sztywna płyta na kadłuby, zbiorniki i turbiny.",
            [CarbonComposite, InsulationBoard, CaseinGlue, Assembly], [(Items.CarbonComposite, 9), (Items.InsulationBoard, 3), (Items.CaseinGlue, 3)], TimeSpan.FromMinutes(4), 60,
            [Items.CompositePanel]),
        new(SuperconductingMagnet, "Elektromagnes nadprzewodzący", "Magnes, który utrzymuje plazmę w reaktorze i satelitę na kursie.",
            [SuperconductingWire, Coil, Coolant, MachineShop], [(Items.SuperconductingWire, 12), (Items.Coil, 6), (Items.Coolant, 6)], TimeSpan.FromMinutes(4), 60,
            [Items.SuperconductingMagnet]),
        new(Alternator, "Prądnica", "Wirnik w obudowie: zamienia obroty w prąd.",
            [Rotor, MachineHousing, WiringHarness, Assembly], [(Items.Rotor, 3), (Items.MachineHousing, 3), (Items.WiringHarness, 3)], TimeSpan.FromMinutes(6), 80,
            [Items.Alternator]),
        new(ControlModule, "Moduł sterujący", "Płytki drukowane z wyświetlaczem w obudowie: mózg każdej maszyny.",
            [WiringHarness, MachineHousing, Assembly], [(Items.CircuitBoard, 6), (Items.WiringHarness, 3), (Items.WindowPane, 3), (Items.MachineHousing, 3)], TimeSpan.FromMinutes(6), 80,
            [Items.ControlModule]),
        new(HydraulicActuator, "Siłownik hydrauliczny", "Tłok na przekładni, który podnosi i przesuwa ciężary.",
            [Gearbox, Lubricant, MachineShop], [(Items.Gearbox, 3), (Items.Gasket, 6), (Items.Lubricant, 6), (Items.SteelIngot, 6)], TimeSpan.FromMinutes(6), 80,
            [Items.HydraulicActuator]),
        new(RocketNozzle, "Dysza rakietowa", "Rozszerzająca się dysza, przez którą komora spalania pcha rakietę.",
            [CombustionChamber, Firebrick, MachineShop], [(Items.CombustionChamber, 3), (Items.SteelIngot, 6), (Items.Firebrick, 12)], TimeSpan.FromMinutes(6), 80,
            [Items.RocketNozzle]),
        new(PressureVessel, "Zbiornik ciśnieniowy", "Szczelny zbiornik z kompozytu i blachy na gaz pod ciśnieniem.",
            [CompositePanel, PaintedSheet, Assembly], [(Items.CompositePanel, 6), (Items.PaintedSheet, 12), (Items.Gasket, 12)], TimeSpan.FromMinutes(6), 80,
            [Items.PressureVessel]),
        new(ComputingCore, "Rdzeń obliczeniowy", "Moduły sterujące połączone światłowodem: liczy za roboty i rakiety.",
            [ControlModule, Coolant, Assembly], [(Items.ControlModule, 4), (Items.OpticalFiber, 8), (Items.SiliconWafer, 8), (Items.Coolant, 4)], TimeSpan.FromMinutes(8), 100,
            [Items.ComputingCore]),
        new(RobotArm, "Ramię robotyczne", "Ramię z siłownikami, które samo chwyta, przenosi i skręca.",
            [HydraulicActuator, ControlModule, WiringHarness, Assembly], [(Items.HydraulicActuator, 4), (Items.ControlModule, 2), (Items.WiringHarness, 4)], TimeSpan.FromMinutes(8), 100,
            [Items.RobotArm]),
        new(Turbopump, "Turbopompa", "Pompa napędzana własną turbiną: tłoczy paliwo do silnika rakietowego.",
            [Rotor, Gearbox, CombustionChamber, ControlModule, Assembly], [(Items.Rotor, 4), (Items.Gearbox, 2), (Items.CombustionChamber, 2), (Items.ControlModule, 2)], TimeSpan.FromMinutes(8), 100,
            [Items.Turbopump]),
        new(TurbineSet, "Turbozespół", "Turbina z prądnicą: zamienia ciepło reaktora w prąd.",
            [CompositePanel, Alternator, Gearbox, Assembly], [(Items.CompositePanel, 8), (Items.Alternator, 2), (Items.Gearbox, 2)], TimeSpan.FromMinutes(8), 100,
            [Items.TurbineSet]),
        new(CryogenicTank, "Zbiornik kriogeniczny", "Zbiornik, który trzyma paliwo i chłodziwo w głębokim mrozie.",
            [PressureVessel, InsulationBoard, Coolant, ControlModule, Assembly], [(Items.PressureVessel, 2), (Items.InsulationBoard, 8), (Items.Coolant, 8), (Items.ControlModule, 2)], TimeSpan.FromMinutes(8), 100,
            [Items.CryogenicTank]),
        new(IndustrialRobot, "Robot przemysłowy", "Dwa ramiona z własnym rdzeniem i prądnicą: pracuje bez przerwy.",
            [RobotArm, ComputingCore, Alternator, Assembly], [(Items.RobotArm, 4), (Items.ComputingCore, 2), (Items.Alternator, 2)], TimeSpan.FromMinutes(12), 120,
            [Items.IndustrialRobot]),
        new(NavigationSystem, "System nawigacji", "Żyroskop laserowy z luster i rdzeń, który liczy kurs.",
            [ComputingCore, Coil, Assembly], [(Items.ComputingCore, 2), (Items.Mirror, 8), (Items.Coil, 4), (Items.OpticalFiber, 8)], TimeSpan.FromMinutes(12), 120,
            [Items.NavigationSystem]),
        new(RocketEngine, "Silnik rakietowy", "Komora, dysza i turbopompy: cztery takie unoszą człon rakiety.",
            [Turbopump, RocketNozzle, CombustionChamber, ControlModule, Assembly], [(Items.Turbopump, 4), (Items.RocketNozzle, 2), (Items.CombustionChamber, 2), (Items.ControlModule, 2)], TimeSpan.FromMinutes(12), 120,
            [Items.RocketEngine]),
        new(PlasmaChamber, "Komora plazmowa", "Pierścień magnesów, w którym płonie plazma reaktora fuzyjnego.",
            [SuperconductingMagnet, RefractoryLining, PressureVessel, ComputingCore, Assembly], [(Items.SuperconductingMagnet, 16), (Items.RefractoryLining, 8), (Items.PressureVessel, 4), (Items.ComputingCore, 2)], TimeSpan.FromMinutes(12), 120,
            [Items.PlasmaChamber]),
        new(Avionics, "Awionika", "Nawigacja i rdzenie rakiety: prowadzą ją na orbitę.",
            [NavigationSystem, ComputingCore, WiringHarness, RoboticHall], [(Items.NavigationSystem, 1), (Items.ComputingCore, 2), (Items.WiringHarness, 4)], TimeSpan.FromMinutes(20), 140,
            [Items.Avionics]),
        new(PlasmaControl, "Układ sterowania plazmą", "Rdzenie i magnesy, które co chwilę poprawiają kształt plazmy.",
            [ComputingCore, SuperconductingMagnet, ControlModule, IndustrialRobot, RoboticHall], [(Items.ComputingCore, 2), (Items.SuperconductingMagnet, 4), (Items.ControlModule, 2), (Items.IndustrialRobot, 1)], TimeSpan.FromMinutes(20), 140,
            [Items.PlasmaControl]),
        new(RocketStage, "Człon rakiety", "Cztery silniki pod zbiornikami paliwa: rakieta ma dwa takie człony.",
            [RocketEngine, CryogenicTank, Avionics, CompositePanel, RoboticHall], [(Items.RocketEngine, 4), (Items.CryogenicTank, 2), (Items.Avionics, 1), (Items.CompositePanel, 8)], TimeSpan.FromMinutes(30), 160,
            [Items.RocketStage]),
        new(Satellite, "Satelita", "Satelita z panelami słonecznymi: ładunek misji orbitalnej.",
            [Avionics, CompositePanel, SuperconductingMagnet, RoboticHall], [(Items.SolarPanel, 8), (Items.Avionics, 1), (Items.CompositePanel, 4), (Items.SuperconductingMagnet, 1)], TimeSpan.FromMinutes(30), 160,
            [Items.Satellite]),
        new(FusionReactor, "Reaktor fuzyjny", "Dwie komory plazmowe z turbozespołami: serce elektrowni fuzyjnej.",
            [PlasmaChamber, PlasmaControl, TurbineSet, CryogenicTank, RoboticHall], [(Items.PlasmaChamber, 2), (Items.PlasmaControl, 1), (Items.TurbineSet, 2), (Items.CryogenicTank, 2)], TimeSpan.FromMinutes(30), 160,
            [Items.FusionReactor]),
        new(LaunchRocket, "Rakieta nośna", "Dwa człony pod owiewką z kompozytu: wynosi satelitę z kosmodromu spółki.",
            [RocketStage, Avionics, CompositePanel, RoboticHall], [(Items.RocketStage, 2), (Items.Avionics, 1), (Items.CompositePanel, 6)], TimeSpan.FromMinutes(45), 180,
            [Items.LaunchRocket]),
        new(MachineShop, "Warsztat mechaniczny", "Na prąd (40 kW): robi przewody, łożyska, cewki, przekładnie, wirniki, siłowniki i inne części maszyn.",
            [Assembly], [(Items.SteelIngot, 6), (Items.ElectricMotor, 2), (Items.CopperIngot, 10)], TimeSpan.FromMinutes(2), 60,
            [Items.MachineShop]),
        new(RoboticHall, "Zrobotyzowana hala", "Na 3 × 3 polach, na prąd (300 kW): roboty składają awionikę, człony rakiet, satelity i reaktory fuzyjne.",
            [IndustrialRobot, ComputingCore, PrecastConcrete], [(Items.IndustrialRobot, 3), (Items.ExpressBelt, 10), (Items.ComputingCore, 1), (Items.PrecastConcrete, 20)], TimeSpan.FromMinutes(20), 180,
            [Items.RoboticHall]),
        new(OxygenConverter, "Konwerter tlenowy", "Na 3 × 3 polach, na prąd (100 kW): przedmuchuje żelazo tlenem i robi 2 sztabki stali z 3 sztabek żelaza.",
            [RefractoryLining, HydraulicActuator, ControlModule], [(Items.RefractoryLining, 8), (Items.HydraulicActuator, 2), (Items.ControlModule, 1), (Items.SteelIngot, 20)], TimeSpan.FromMinutes(8), 140,
            [Items.OxygenConverter]),
        new(RollingMill, "Walcownia", "Na 3 × 3 polach, na prąd (120 kW): walcuje blachę i ciągnie przewody dwa razy wydajniej niż warsztat.",
            [Gearbox, Alternator, ControlModule, PrecastConcrete], [(Items.Gearbox, 4), (Items.Alternator, 2), (Items.ControlModule, 1), (Items.PrecastConcrete, 20)], TimeSpan.FromMinutes(8), 140,
            [Items.RollingMill]),
        new(ControlCenter, "Centrum sterowania", "Na prąd (60 kW): wszystkie maszyny przetwórcze na działce pracują o 20% szybciej. Jedno na działkę.",
            [ComputingCore, ControlModule, MachineHousing], [(Items.ComputingCore, 4), (Items.ControlModule, 4), (Items.OpticalFiber, 20), (Items.MachineHousing, 1)], TimeSpan.FromMinutes(12), 160,
            [Items.ControlCenter]),
        new(ContinuousCaster, "Odlewnia ciągła", "Na 3 × 3 polach, na prąd (150 kW): odlewa brąz i stop irydowy wydajniej niż odlewnia i piec łukowy.",
            [IndustrialRobot, RefractoryLining, Coolant], [(Items.IndustrialRobot, 1), (Items.RefractoryLining, 10), (Items.Coolant, 20), (Items.SteelIngot, 20)], TimeSpan.FromMinutes(20), 180,
            [Items.ContinuousCaster]),
        new(AutomatedWarehouse, "Magazyn zautomatyzowany", "Na 3 × 3 polach: 120 miejsc po 500 sztuk, roboty same układają wszystko, co przywiozą taśmy.",
            [IndustrialRobot, ComputingCore, PrecastConcrete], [(Items.IndustrialRobot, 2), (Items.ComputingCore, 2), (Items.ExpressBelt, 20), (Items.PrecastConcrete, 30)], TimeSpan.FromMinutes(20), 180,
            [Items.AutomatedWarehouse]),
        new(SteelCombine, "Kombinat hutniczy", "Na 5 × 5 polach, na prąd (600 kW): robi wszystko, co konwerter, walcownia i odlewnia ciągła, trzy razy szybciej.",
            [OxygenConverter, RollingMill, ContinuousCaster, ControlCenter], [(Items.OxygenConverter, 1), (Items.RollingMill, 1), (Items.ContinuousCaster, 1), (Items.ControlCenter, 1)], TimeSpan.FromMinutes(30), 200,
            [Items.SteelCombine]),
        new(Megafactory, "Megafabryka", "Na 5 × 5 polach, na prąd (1 MW): robi wszystko, co warsztat mechaniczny, hala montażowa i zrobotyzowana hala, trzy razy szybciej.",
            [RoboticHall, ControlCenter, AutomatedWarehouse, PrecastConcrete], [(Items.RoboticHall, 1), (Items.ControlCenter, 1), (Items.AutomatedWarehouse, 1), (Items.PrecastConcrete, 50)], TimeSpan.FromMinutes(30), 200,
            [Items.Megafactory]),
        new(FusionPlant, "Elektrownia fuzyjna", "Na 3 × 3 polach: daje 5 MW, a za paliwo zużywa tylko płyn chłodniczy, jedną porcję na minutę pełnej mocy.",
            [FusionReactor, PrecastConcrete, Alternator, IndustrialRobot], [(Items.FusionReactor, 1), (Items.PrecastConcrete, 25), (Items.Alternator, 2), (Items.IndustrialRobot, 1)], TimeSpan.FromMinutes(45), 220,
            [Items.FusionPlant]),
        new(Megaprojects, "Wielkie budowy", "Tylko dla spółek: członkowie razem stawiają platformę wiertniczą, port, pole lustrzane, kolej międzykontynentalną, a na końcu kosmodrom, misję i stację orbitalną.",
            [BuildingMaterials, Headquarters], [(Items.Concrete, 500), (Items.SteelIngot, 500), (Items.Blueprint, 10)], TimeSpan.FromMinutes(30), 300,
            [], CompanyOnly: true),
        new(CorporateFinance, "Finanse korporacyjne", "Tylko dla spółek: spółka wchodzi na giełdę, a gracze spoza niej kupują jej akcje.",
            [Commerce, Headquarters], [(Items.Paper, 500), (Items.Blueprint, 10), (Items.CircuitBoard, 50)], TimeSpan.FromMinutes(20), 200,
            [], CompanyOnly: true),
    ];

    /// <summary>
    /// The branches of industry, each a tree of its own in the client: a tab per branch, in this order.
    /// A technology may need one from another branch; the client shows that one at the side of the tree.
    /// </summary>
    public static readonly IReadOnlyList<Branch> Branches =
    [
        new("logistics", "Logistyka", Items.Belt, [Logistics, Automation, Storage, Sorting, CableTransport]),
        new("mining", "Górnictwo", Items.IronOre,
            [Stonemasonry, Metallurgy, MiningAutomation, Crushing, Explosives, DeepMining]),
        new("forestry", "Leśnictwo", Items.Wood,
            [ForestryIndustry, Silviculture, Woodworking, IndustrialForestry, Papermaking, Furniture, Charring, FireProtection, Beekeeping, ForestFoods]),
        new("food", "Przetwórstwo", Items.Bread,
            [Milling, OilPressing, Pickling, Baking, GrainStorage, Cooking, Confectionery]),
        new("energy", "Energia", Items.WindTurbine, [Hydropower, HydroPlant, WindPower, LargeWind]),
        new("oil", "Ropa i gaz", Items.CrudeOil,
            [OilExtraction, Refining, EnhancedRecovery, OffshoreDrilling, Cracking, Petrochemistry, Combustion, Roads]),
        new("coast", "Nabrzeże", Items.Herring, [Fishing, SaltWorks, FishProcessing, Seafaring, Aquaculture, TidalPower]),
        new("desert", "Pustynia", Items.SolarPanel,
            [Glassmaking, WaterSupply, SiliconWorks, BuildingMaterials, SolarPower, SolarTower]),
        new("glacier", "Lodowiec", Items.Ice,
            [Heating, PolarTransport, Refrigeration, Glaciology, PolarTourism, DataCenter]),
        new("city", "Miasta", Items.Shop,
            [Commerce, CityServices, WasteManagement, FreightHub, Assembly, UrbanConstruction, Headquarters]),
        new("materials", "Materiały", Items.CarbonComposite,
            [Lubricant, Paint, CaseinGlue, InsulationBoard, Firebrick, PrecastConcrete, GlassLaminate, Coolant, IridiumAlloy, Provisions,
             ElectricWire, PaintedSheet, RefractoryLining, CarbonComposite, SuperconductingWire, RocketFuel]),
        new("components", "Podzespoły", Items.Gearbox,
            [MachineShop, Bearing, Coil, WiringHarness, Gearbox, Rotor, MachineHousing, CombustionChamber, CompositePanel,
             SuperconductingMagnet, Alternator, ControlModule, HydraulicActuator, RocketNozzle, PressureVessel, ComputingCore,
             RobotArm, Turbopump, TurbineSet, CryogenicTank, IndustrialRobot, NavigationSystem]),
        new("factories", "Fabryki", Items.Megafactory,
            [RoboticHall, OxygenConverter, RollingMill, ControlCenter, ContinuousCaster, AutomatedWarehouse, SteelCombine, Megafactory]),
        new("space", "Kosmos i fuzja", Items.LaunchRocket,
            [RocketEngine, PlasmaChamber, Avionics, PlasmaControl, RocketStage, Satellite, FusionReactor, LaunchRocket, FusionPlant]),
        new("company", "Spółki", Items.CompanyHq, [Megaprojects, CorporateFinance]),
    ];

    /// <summary>The branch each technology belongs to.</summary>
    public static readonly IReadOnlyDictionary<string, Branch> BranchOf =
        Branches.SelectMany(b => b.Technologies.Select(t => (t, b))).ToDictionary(p => p.t, p => p.b);

    public static readonly IReadOnlyDictionary<string, Technology> ById = Technologies.ToDictionary(t => t.Id);

    /// <summary>The technology that unlocks each item it lists.</summary>
    public static readonly IReadOnlyDictionary<string, Technology> ByItem =
        Technologies.SelectMany(t => t.Unlocks.Select(item => (item, t))).ToDictionary(p => p.item, p => p.t);

    /// <summary>How deep in the tree a technology lies: 0 for the ones with no requirements. The client draws a column for each.</summary>
    public static int Tier(Technology technology) =>
        technology.Requires.Count == 0 ? 0 : 1 + technology.Requires.Max(r => Tier(ById[r]));
}

/// <summary>A branch of industry and its technologies, roots first.</summary>
/// <param name="Icon">The item whose icon the branch's tab shows.</param>
public sealed record Branch(string Id, string Name, string Icon, IReadOnlyList<string> Technologies);

public enum ResearchStatus { Locked, Available, Active, Done }

/// <summary>The player's research now, after handing out XP for what finished.</summary>
/// <param name="Started">Every technology the player started, done ones included.</param>
/// <param name="Finished">Technologies that finished since the player last asked.</param>
/// <param name="Shared">Technologies the player has because their company researched them.</param>
/// <param name="Company">The company's research, when the player is in a company.</param>
public sealed record ResearchState(
    IReadOnlyDictionary<string, (DateTimeOffset StartsAt, DateTimeOffset FinishesAt)> Started,
    DateTimeOffset ServerTime,
    IReadOnlyList<string> Finished,
    XpGain? Xp,
    IReadOnlySet<string>? Shared = null,
    CompanyResearch? Company = null)
{
    public bool IsDone(string id) => Started.TryGetValue(id, out var r) && r.FinishesAt <= ServerTime;

    public ResearchStatus Status(Technology technology) =>
        IsDone(technology.Id) ? ResearchStatus.Done
        : Started.ContainsKey(technology.Id) ? ResearchStatus.Active
        : technology.Requires.All(IsDone) ? ResearchStatus.Available
        : ResearchStatus.Locked;
}

/// <summary>What a company researches together: one technology at a time, which starts once members brought its whole cost.</summary>
/// <param name="Technology">The one being collected for or researched; null when none.</param>
/// <param name="StartsAt">Null while members are still bringing its cost.</param>
/// <param name="Delivered">How much of each cost item members brought so far.</param>
/// <param name="Done">What the company researched, for every member.</param>
public sealed record CompanyResearch(
    string Name, bool Leads, string? Technology, DateTimeOffset? StartsAt, DateTimeOffset? FinishesAt,
    IReadOnlyDictionary<string, long> Delivered, IReadOnlySet<string> Done);

public sealed class ResearchService(GameDb db, IInventory inventory, ICharacterProgress progress, ICompanies companies, TimeProvider time)
    : ITechnologies, ICompanyTechnologies
{
    /// <summary>How long the research takes the player: the orbital station of their company shortens it.</summary>
    private async Task<TimeSpan> DurationAsync(Guid player, Technology technology, CancellationToken cancellationToken) =>
        technology.Time * CompanyPerks.ResearchFactor(await companies.ProjectsAsync(player, cancellationToken));

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
            if (technology.CompanyOnly)
            {
                throw new GameException("company_only", "Only a company researches this, together.");
            }

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
                insert.Parameters.AddWithValue("end", now + await DurationAsync(owner, technology, cancellationToken));
                await insert.ExecuteNonQueryAsync(cancellationToken);
            }

            return await ReadAsync(owner, finished, xp, cancellationToken);
        }, cancellationToken);

    /// <summary>Speeds the research being done now up: data from a polar station and a server room's computing power each take seconds off it (<see cref="Items.ResearchBoost"/>).</summary>
    public Task<ResearchState> BoostAsync(Guid owner, string item, int quantity, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (!Items.ResearchBoost.TryGetValue(item, out var seconds))
            {
                throw new GameException("not_boost", "Only research data and computing power speed research up.");
            }

            if (quantity < 1)
            {
                throw new GameException("bad_quantity", "Put in at least one.");
            }

            var (finished, xp) = await CompleteDueAsync(owner, cancellationToken);
            var now = time.GetUtcNow();
            DateTimeOffset finishes;
            await using (var select = await db.CommandAsync(
                "SELECT finishes_at FROM research.technologies WHERE owner_id = @owner AND finishes_at > @now FOR UPDATE", cancellationToken))
            {
                select.Parameters.AddWithValue("owner", owner);
                select.Parameters.AddWithValue("now", now);
                if (await select.ExecuteScalarAsync(cancellationToken) is not DateTime at)
                {
                    throw new GameException("no_research", "Nothing is being researched.");
                }

                finishes = new DateTimeOffset(at, TimeSpan.Zero);
            }

            // No more is used up than the research still needs.
            var left = finishes - now;
            var used = (int)Math.Min(quantity, Math.Ceiling(left.TotalSeconds / seconds));
            var cut = TimeSpan.FromSeconds((double)used * seconds);
            if (cut > left)
            {
                cut = left;
            }

            await inventory.RemoveAsync(owner, item, used, cancellationToken);
            await using (var update = await db.CommandAsync(
                """
                UPDATE research.technologies SET starts_at = starts_at - @cut, finishes_at = finishes_at - @cut
                WHERE owner_id = @owner AND finishes_at > @now
                """, cancellationToken))
            {
                update.Parameters.AddWithValue("owner", owner);
                update.Parameters.AddWithValue("now", now);
                update.Parameters.AddWithValue("cut", cut);
                await update.ExecuteNonQueryAsync(cancellationToken);
            }

            var (done, more) = await CompleteDueAsync(owner, cancellationToken);
            return await ReadAsync(owner, [.. finished, .. done], more ?? xp, cancellationToken);
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

        if (await companies.MembershipAsync(player, cancellationToken) is { } membership)
        {
            done.UnionWith(await CompanyDoneAsync(membership.Company, cancellationToken));
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

        var now = time.GetUtcNow();
        if (await companies.MembershipAsync(owner, cancellationToken) is not { } membership)
        {
            return new ResearchState(started, now, finished, xp);
        }

        var company = await CompanyStateAsync(membership, cancellationToken);
        var shared = new HashSet<string>();
        foreach (var id in company.Done)
        {
            if (!started.TryGetValue(id, out var own) || own.Item2 > now)
            {
                shared.Add(id);
                started[id] = (now, now);
            }
        }

        return new ResearchState(started, now, finished, xp, shared, company);
    }

    public async Task<bool> ResearchedAsync(Guid company, string technology, CancellationToken cancellationToken) =>
        (await CompanyDoneAsync(company, cancellationToken)).Contains(technology);

    /// <summary>The owner or a partner picks what the company researches next; members then bring its cost (<see cref="ContributeAsync"/>).</summary>
    public Task<ResearchState> StartCompanyAsync(Guid owner, string id, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var technology = TechTree.ById.GetValueOrDefault(id) ?? throw new GameException("no_technology", "There is no such technology.");
            await RequireCompanyAsync(owner, true, cancellationToken);
            var (finished, xp) = await CompleteDueAsync(owner, cancellationToken);
            var state = await ReadAsync(owner, finished, xp, cancellationToken);
            var company = state.Company!;
            if (company.Done.Contains(id))
            {
                throw new GameException("already_researched", "The company has researched this already.");
            }

            if (company.Technology is not null)
            {
                throw new GameException("research_busy", "The company is researching something else; finish or cancel it first.");
            }

            // What it needs counts when the company or this player has it.
            if (!technology.Requires.All(state.IsDone))
            {
                throw new GameException("research_locked", "Research the technologies it needs first.");
            }

            await using (var insert = await db.CommandAsync(
                "INSERT INTO research.company_technologies (company_id, technology) VALUES (@company, @technology)", cancellationToken))
            {
                insert.Parameters.AddWithValue("company", (await companies.MembershipAsync(owner, cancellationToken))!.Company);
                insert.Parameters.AddWithValue("technology", id);
                await insert.ExecuteNonQueryAsync(cancellationToken);
            }

            return await ReadAsync(owner, finished, xp, cancellationToken);
        }, cancellationToken);

    /// <summary>A member brings part of the cost of what the company researches; with the whole cost in, the research starts.</summary>
    public Task<ResearchState> ContributeAsync(Guid owner, string item, long quantity, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            if (quantity < 1)
            {
                throw new GameException("bad_quantity", "Bring at least one.");
            }

            var membership = await RequireCompanyAsync(owner, false, cancellationToken);
            var company = await CompanyStateAsync(membership, cancellationToken);
            if (company.Technology is not { } id || company.StartsAt is not null)
            {
                throw new GameException("no_research", "The company is not collecting for any research.");
            }

            var technology = TechTree.ById[id];
            var needed = technology.Cost.Where(c => c.Item == item).Sum(c => (long)c.Quantity) - company.Delivered.GetValueOrDefault(item);
            if (needed <= 0)
            {
                throw new GameException("not_needed", "The research needs no more of this.");
            }

            var used = Math.Min(quantity, needed);
            await inventory.RemoveAsync(owner, item, used, cancellationToken);
            await using (var upsert = await db.CommandAsync(
                """
                INSERT INTO research.company_contributions (company_id, technology, item, delivered) VALUES (@company, @technology, @item, @used)
                ON CONFLICT (company_id, technology, item) DO UPDATE SET delivered = company_contributions.delivered + excluded.delivered
                """, cancellationToken))
            {
                upsert.Parameters.AddWithValue("company", membership.Company);
                upsert.Parameters.AddWithValue("technology", id);
                upsert.Parameters.AddWithValue("item", item);
                upsert.Parameters.AddWithValue("used", used);
                await upsert.ExecuteNonQueryAsync(cancellationToken);
            }

            var delivered = new Dictionary<string, long>(company.Delivered) { [item] = company.Delivered.GetValueOrDefault(item) + used };
            if (technology.Cost.All(c => delivered.GetValueOrDefault(c.Item) >= c.Quantity))
            {
                var now = time.GetUtcNow();
                await using var start = await db.CommandAsync(
                    "UPDATE research.company_technologies SET starts_at = @start, finishes_at = @end WHERE company_id = @company AND technology = @technology",
                    cancellationToken);
                start.Parameters.AddWithValue("company", membership.Company);
                start.Parameters.AddWithValue("technology", id);
                start.Parameters.AddWithValue("start", now);
                start.Parameters.AddWithValue("end", now + await DurationAsync(owner, technology, cancellationToken));
                await start.ExecuteNonQueryAsync(cancellationToken);
            }

            return await ReadAsync(owner, [], null, cancellationToken);
        }, cancellationToken);

    /// <summary>The owner or a partner calls off the company's research that is not done; what members brought goes to the one who calls it off.</summary>
    public Task<ResearchState> CancelCompanyAsync(Guid owner, CancellationToken cancellationToken) =>
        db.InTransactionAsync(async () =>
        {
            var membership = await RequireCompanyAsync(owner, true, cancellationToken);
            var company = await CompanyStateAsync(membership, cancellationToken);
            if (company.Technology is not { } id)
            {
                throw new GameException("no_research", "The company is not researching anything.");
            }

            foreach (var (item, quantity) in company.Delivered.Where(d => d.Value > 0))
            {
                await inventory.AddAsync(owner, item, quantity, cancellationToken);
            }

            await using (var delete = await db.CommandAsync(
                """
                DELETE FROM research.company_contributions WHERE company_id = @company AND technology = @technology;
                DELETE FROM research.company_technologies WHERE company_id = @company AND technology = @technology;
                """, cancellationToken))
            {
                delete.Parameters.AddWithValue("company", membership.Company);
                delete.Parameters.AddWithValue("technology", id);
                await delete.ExecuteNonQueryAsync(cancellationToken);
            }

            return await ReadAsync(owner, [], null, cancellationToken);
        }, cancellationToken);

    /// <summary>The player's company, locked so its research changes one request at a time.</summary>
    private async Task<CompanyMembership> RequireCompanyAsync(Guid player, bool leads, CancellationToken cancellationToken)
    {
        var membership = await companies.MembershipAsync(player, cancellationToken)
            ?? throw new GameException("no_company", "You are not in a company.");
        if (leads && !membership.Leads)
        {
            throw new GameException("not_allowed", "Only the owner and partners choose the company's research.");
        }

        await using var lockCompany = await db.CommandAsync("SELECT pg_advisory_xact_lock(@key)", cancellationToken);
        lockCompany.Parameters.AddWithValue("key", BitConverter.ToInt64(membership.Company.ToByteArray()) ^ 0x636f6d70616e79);
        await lockCompany.ExecuteNonQueryAsync(cancellationToken);
        return membership;
    }

    private async Task<HashSet<string>> CompanyDoneAsync(Guid company, CancellationToken cancellationToken)
    {
        await using var command = await db.CommandAsync(
            "SELECT technology FROM research.company_technologies WHERE company_id = @company AND finishes_at <= @now", cancellationToken);
        command.Parameters.AddWithValue("company", company);
        command.Parameters.AddWithValue("now", time.GetUtcNow());
        var done = new HashSet<string>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            done.Add(reader.GetString(0));
        }

        return done;
    }

    private async Task<CompanyResearch> CompanyStateAsync(CompanyMembership membership, CancellationToken cancellationToken)
    {
        string? current = null;
        DateTimeOffset? startsAt = null, finishesAt = null;
        await using (var command = await db.CommandAsync(
            "SELECT technology, starts_at, finishes_at FROM research.company_technologies WHERE company_id = @company AND (finishes_at IS NULL OR finishes_at > @now)",
            cancellationToken))
        {
            command.Parameters.AddWithValue("company", membership.Company);
            command.Parameters.AddWithValue("now", time.GetUtcNow());
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                current = reader.GetString(0);
                startsAt = reader.IsDBNull(1) ? null : reader.GetFieldValue<DateTimeOffset>(1);
                finishesAt = reader.IsDBNull(2) ? null : reader.GetFieldValue<DateTimeOffset>(2);
            }
        }

        var delivered = new Dictionary<string, long>();
        if (current is not null)
        {
            await using var command = await db.CommandAsync(
                "SELECT item, delivered FROM research.company_contributions WHERE company_id = @company AND technology = @technology", cancellationToken);
            command.Parameters.AddWithValue("company", membership.Company);
            command.Parameters.AddWithValue("technology", current);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                delivered[reader.GetString(0)] = reader.GetInt64(1);
            }
        }

        return new CompanyResearch(membership.Name, membership.Leads, current, startsAt, finishesAt, delivered,
            await CompanyDoneAsync(membership.Company, cancellationToken));
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
                branch = TechTree.BranchOf[t.Id].Id,
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
                companyOnly = t.CompanyOnly,
                // Researched by the player's company, not by them.
                shared = state.Shared?.Contains(t.Id) == true,
            }),
            company = state.Company is { } c ? new
            {
                name = c.Name,
                leads = c.Leads,
                technology = c.Technology,
                startsAt = c.StartsAt?.ToUnixTimeMilliseconds(),
                finishesAt = c.FinishesAt?.ToUnixTimeMilliseconds(),
                delivered = c.Technology is { } id
                    ? TechTree.ById[id].Cost.Select(p => new { id = p.Item, name = Items.Names[p.Item], needed = p.Quantity, delivered = c.Delivered.GetValueOrDefault(p.Item) })
                    : null,
            } : null,
            // What speeds research up, and by how many seconds each piece.
            boosts = Items.ResearchBoost.Select(b => new { id = b.Key, name = Items.Names[b.Key], seconds = b.Value }),
            branches = TechTree.Branches.Select(b => new { id = b.Id, name = b.Name, icon = b.Icon }),
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

public sealed record BoostResearchRequest(string Item, int Quantity);

/// <summary>Speeds the research being done up with research data or computing power.</summary>
public sealed class BoostResearchHandler(IServiceScopeFactory scopes) : ResearchHandler(scopes)
{
    public override string Type => "research.boost";

    protected override Task<ResearchState> RunAsync(ResearchService research, Guid owner, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<BoostResearchRequest>(payload);
        return research.BoostAsync(owner, request.Item ?? "", request.Quantity, cancellationToken);
    }
}

public sealed class CancelResearchHandler(IServiceScopeFactory scopes) : ResearchHandler(scopes)
{
    public override string Type => "research.cancel";

    protected override Task<ResearchState> RunAsync(ResearchService research, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        research.CancelAsync(owner, cancellationToken);
}

/// <summary>The company picks what it researches together.</summary>
public sealed class StartCompanyResearchHandler(IServiceScopeFactory scopes) : ResearchHandler(scopes)
{
    public override string Type => "research.companyStart";

    protected override Task<ResearchState> RunAsync(ResearchService research, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        research.StartCompanyAsync(owner, Payload.Read<StartResearchRequest>(payload).Technology ?? "", cancellationToken);
}

public sealed record ContributeRequest(string Item, long Quantity);

/// <summary>A member brings part of the cost of the company's research.</summary>
public sealed class ContributeResearchHandler(IServiceScopeFactory scopes) : ResearchHandler(scopes)
{
    public override string Type => "research.contribute";

    protected override Task<ResearchState> RunAsync(ResearchService research, Guid owner, JsonElement? payload, CancellationToken cancellationToken)
    {
        var request = Payload.Read<ContributeRequest>(payload);
        return research.ContributeAsync(owner, request.Item ?? "", request.Quantity, cancellationToken);
    }
}

public sealed class CancelCompanyResearchHandler(IServiceScopeFactory scopes) : ResearchHandler(scopes)
{
    public override string Type => "research.companyCancel";

    protected override Task<ResearchState> RunAsync(ResearchService research, Guid owner, JsonElement? payload, CancellationToken cancellationToken) =>
        research.CancelCompanyAsync(owner, cancellationToken);
}
