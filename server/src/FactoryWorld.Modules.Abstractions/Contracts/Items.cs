namespace FactoryWorld.Modules.Abstractions.Contracts;

/// <summary>Every item in the game. Ids are stored in the database, so never rename one.</summary>
public static class Items
{
    public const string Trash = "trash";
    public const string WastePaper = "waste_paper";
    public const string WasteAluminium = "waste_aluminium";
    public const string WasteCopper = "waste_copper";
    public const string WastePlastic = "waste_plastic";
    public const string WasteGlass = "waste_glass";

    // Furniture: stands in the garage, can be picked up into the inventory and placed again.
    public const string TrashBin = "furniture_trash_bin";
    public const string Workbench = "furniture_workbench";
    public const string Shelf = "furniture_shelf";
    public const string BarrelBlue = "furniture_barrel_blue";
    public const string BarrelRed = "furniture_barrel_red";
    public const string Tyres = "furniture_tyres";
    public const string Pallet = "furniture_pallet";
    public const string GasCylinder = "furniture_gas_cylinder";
    public const string SortingMachine = "furniture_sorting_machine";
    public const string Furnace = "furniture_furnace";

    // Tools: one can be held in the character's tool slot.
    public const string Axe = "tool_axe";
    public const string Shovel = "tool_shovel";
    public const string Pickaxe = "tool_pickaxe";
    public const string Hoe = "tool_hoe";

    // Raw materials gathered on plots.
    public const string Wood = "wood";
    public const string Stone = "stone";
    public const string Sand = "sand";
    public const string Coal = "coal";
    public const string IronOre = "iron_ore";
    public const string CopperOre = "copper_ore";
    public const string TinOre = "tin_ore";
    public const string SilverOre = "silver_ore";
    public const string GoldOre = "gold_ore";

    // Smelted in a furnace from ores, and made at a workbench.
    public const string IronIngot = "iron_ingot";
    public const string CopperIngot = "copper_ingot";
    public const string TinIngot = "tin_ingot";
    public const string SilverIngot = "silver_ingot";
    public const string GoldIngot = "gold_ingot";
    public const string Nails = "nails";

    // Forestry: a sapling is planted on a plot and grows into a tree.
    public const string Sapling = "sapling";

    // Crops grown on fertile plots.
    public const string Wheat = "wheat";
    public const string Carrot = "carrot";
    public const string Cabbage = "cabbage";
    public const string Corn = "corn";
    public const string Potato = "potato";
    public const string Sunflower = "sunflower";

    // Logistics on plots: belts carry items, inserters move them between belts, machines and storage.
    public const string Belt = "logistics_belt";
    public const string Inserter = "logistics_inserter";
    public const string Splitter = "logistics_splitter";

    // Storage put on plots: chests take anything, piles, heaps and silos one kind of bulk goods.
    public const string WoodenChest = "storage_wooden_chest";
    public const string IronChest = "storage_iron_chest";
    public const string WoodPile = "storage_wood_pile";
    public const string Heap = "storage_heap";
    public const string GrainSilo = "storage_grain_silo";

    // Food processing: machines put on a plot turn crops into food, step by step.
    public const string Mill = "furniture_mill";
    public const string OilPress = "furniture_oil_press";
    public const string PicklingBarrel = "furniture_pickling_barrel";
    public const string Bakery = "furniture_bakery";
    public const string Kitchen = "furniture_kitchen";
    public const string Flour = "flour";
    public const string CornFlour = "corn_flour";
    public const string SunflowerOil = "sunflower_oil";
    public const string Sauerkraut = "sauerkraut";
    public const string Bread = "bread";
    public const string CornBread = "corn_bread";
    public const string CarrotCake = "carrot_cake";
    public const string Fries = "fries";
    public const string VegetableSoup = "vegetable_soup";
    public const string Bigos = "bigos";

    // Power on plots: a generator burns wood or coal, poles carry its power to machines near them.
    public const string Generator = "power_generator";
    public const string Pole = "power_pole";

    /// <summary>Display names in Polish, keyed by id.</summary>
    public static readonly IReadOnlyDictionary<string, string> Names = new Dictionary<string, string>
    {
        [Trash] = "Śmieci",
        [WastePaper] = "Makulatura",
        [WasteAluminium] = "Złom aluminium",
        [WasteCopper] = "Złom miedzi",
        [WastePlastic] = "Plastik z odzysku",
        [WasteGlass] = "Stłuczka szklana",
        [TrashBin] = "Kosz na śmieci",
        [Workbench] = "Stół warsztatowy",
        [Shelf] = "Regał",
        [BarrelBlue] = "Niebieska beczka",
        [BarrelRed] = "Czerwona beczka",
        [Tyres] = "Opony",
        [Pallet] = "Paleta",
        [GasCylinder] = "Butla gazowa",
        [SortingMachine] = "Automatyczna sortownia",
        [Furnace] = "Piec kamienny",
        [Axe] = "Siekiera",
        [Shovel] = "Łopata",
        [Pickaxe] = "Kilof",
        [Hoe] = "Motyka",
        [Wood] = "Drewno",
        [Stone] = "Kamień",
        [Sand] = "Piasek",
        [Coal] = "Węgiel",
        [IronOre] = "Ruda żelaza",
        [CopperOre] = "Ruda miedzi",
        [TinOre] = "Ruda cyny",
        [SilverOre] = "Ruda srebra",
        [GoldOre] = "Ruda złota",
        [IronIngot] = "Sztabka żelaza",
        [CopperIngot] = "Sztabka miedzi",
        [TinIngot] = "Sztabka cyny",
        [SilverIngot] = "Sztabka srebra",
        [GoldIngot] = "Sztabka złota",
        [Nails] = "Gwoździe",
        [Sapling] = "Sadzonka drzewa",
        [Wheat] = "Pszenica",
        [Carrot] = "Marchew",
        [Cabbage] = "Kapusta",
        [Corn] = "Kukurydza",
        [Potato] = "Ziemniaki",
        [Sunflower] = "Słonecznik",
        [Belt] = "Taśmociąg",
        [Inserter] = "Podajnik",
        [Splitter] = "Rozdzielacz",
        [WoodenChest] = "Skrzynia drewniana",
        [IronChest] = "Skrzynia żelazna",
        [WoodPile] = "Stos drewna",
        [Heap] = "Hałda",
        [GrainSilo] = "Silos zbożowy",
        [Mill] = "Młyn",
        [OilPress] = "Tłocznia oleju",
        [PicklingBarrel] = "Beczka do kiszenia",
        [Bakery] = "Piec piekarski",
        [Kitchen] = "Kuchnia polowa",
        [Flour] = "Mąka pszenna",
        [CornFlour] = "Mąka kukurydziana",
        [SunflowerOil] = "Olej słonecznikowy",
        [Sauerkraut] = "Kapusta kiszona",
        [Bread] = "Chleb",
        [CornBread] = "Chleb kukurydziany",
        [CarrotCake] = "Ciasto marchewkowe",
        [Fries] = "Frytki",
        [VegetableSoup] = "Zupa jarzynowa",
        [Bigos] = "Bigos",
        [Generator] = "Generator parowy",
        [Pole] = "Słup energetyczny",
    };

    public static bool Exists(string id) => Names.ContainsKey(id);

    public static bool IsTool(string id) => id is Axe or Shovel or Pickaxe or Hoe;
}
