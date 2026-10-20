using System.Text.Json;
using FactoryWorld.Modules.Abstractions;
using FactoryWorld.Modules.Abstractions.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace FactoryWorld.Modules.Characters;

public sealed record CreateCharacterRequest(string Name, Appearance Appearance);

public sealed record EquipRequest(string Item);

internal static class CharacterView
{
    public static object From(Character c)
    {
        var level = Leveling.LevelForXp(c.Xp);
        return new
        {
            id = c.Id,
            name = c.Name,
            appearance = c.Appearance,
            level,
            xp = c.Xp,
            levelXp = Leveling.TotalXpForLevel(level),
            nextLevelXp = level < Leveling.MaxLevel ? Leveling.TotalXpForLevel(level + 1) : (long?)null,
            tool = c.Tool is { } tool ? new { id = tool, name = Items.Names[tool] } : null,
        };
    }
}

/// <summary>The editor's options; sent before login so the editor can be shown right after registering.</summary>
public sealed class OptionsHandler : IMessageHandler
{
    public string Type => "character.options";

    public bool RequiresAccount => false;

    public Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken) =>
        Task.FromResult(new Reply("character.options", new
        {
            skinTones = AppearanceCatalog.SkinTones,
            hairStyles = AppearanceCatalog.HairStyles,
            hairColors = AppearanceCatalog.HairColors,
            shirtStyles = AppearanceCatalog.ShirtStyles,
            clothColors = AppearanceCatalog.ClothColors,
        }));
}

public sealed class GetCharacterHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "character.get";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var character = await scope.ServiceProvider.GetRequiredService<CharacterService>()
            .FindAsync(client.RequireAccount(), cancellationToken);
        return character is null ? new Reply("character.none") : new Reply("character", CharacterView.From(character));
    }
}

public sealed class CreateCharacterHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "character.create";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<CreateCharacterRequest>(payload);
        if (request.Appearance is null)
        {
            throw new GameException("bad_payload", "Appearance is missing.");
        }

        await using var scope = scopes.CreateAsyncScope();
        var character = await scope.ServiceProvider.GetRequiredService<CharacterService>()
            .CreateAsync(client.RequireAccount(), request.Name ?? "", request.Appearance, cancellationToken);
        return new Reply("character", CharacterView.From(character));
    }
}

/// <summary>Puts a tool from the inventory into the tool slot; the tool held before goes back to the inventory.</summary>
public sealed class EquipHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "character.equip";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        var request = Payload.Read<EquipRequest>(payload);
        await using var scope = scopes.CreateAsyncScope();
        var equipment = scope.ServiceProvider.GetRequiredService<Equipment>();
        await equipment.EquipAsync(client.RequireAccount(), request.Item ?? "", cancellationToken);
        var character = await scope.ServiceProvider.GetRequiredService<CharacterService>().FindAsync(client.RequireAccount(), cancellationToken);
        return new Reply("character", CharacterView.From(character!));
    }
}

/// <summary>Puts the tool from the slot back into the inventory.</summary>
public sealed class UnequipHandler(IServiceScopeFactory scopes) : IMessageHandler
{
    public string Type => "character.unequip";

    public async Task<Reply> HandleAsync(JsonElement? payload, ClientContext client, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        await scope.ServiceProvider.GetRequiredService<Equipment>().EquipAsync(client.RequireAccount(), null, cancellationToken);
        var character = await scope.ServiceProvider.GetRequiredService<CharacterService>().FindAsync(client.RequireAccount(), cancellationToken);
        return new Reply("character", CharacterView.From(character!));
    }
}
