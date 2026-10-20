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

    /// <summary>Display names in Polish, keyed by id.</summary>
    public static readonly IReadOnlyDictionary<string, string> Names = new Dictionary<string, string>
    {
        [Trash] = "Śmieci",
        [WastePaper] = "Papier (odpad)",
        [WasteAluminium] = "Aluminium (odpad)",
        [WasteCopper] = "Miedź (odpad)",
        [WastePlastic] = "Plastik (odpad)",
        [WasteGlass] = "Szkło (odpad)",
    };

    public static bool Exists(string id) => Names.ContainsKey(id);
}
