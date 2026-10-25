---
name: nowy-modul
description: Tworzy nowy moduł serwera Factory World (modularny monolit w C#/.NET 10) albo wydziela część istniejącego do osobnego modułu, z własnym schematem bazy, migracją, publicznym interfejsem, handlerami WebSocket i testami. Użyj przy "nowy moduł", "nowy system gry po stronie serwera", "wydziel X z modułu Y" albo gdy nowa funkcja nie pasuje do żadnego z 18 istniejących modułów.
---

# Nowy moduł serwera

Serwer to modularny monolit: jeden proces, jedna baza, ale każdy moduł ma własny schemat i rozmawia z innymi tylko przez interfejsy. Dzięki temu moduł da się kiedyś przenieść do osobnej usługi. Ten skill pilnuje, żeby nowy moduł trzymał te zasady.

## 0. Czy to na pewno nowy moduł?

Najpierw sprawdź listę modułów w `README.md` (sekcja Struktura). Nowy moduł ma sens, gdy ma własne dane i własne reguły. Gdy funkcja tylko rozszerza istniejący system (nowa maszyna to `Crafting`, nowy rodzaj magazynu to `Logistics`), dodaj ją tam i powiedz o tym graczowi.

## 1. Projekt

Wzór najprostszego modułu z bazą: `server/src/Modules/FactoryWorld.Modules.Wallet/`.

1. `server/src/Modules/FactoryWorld.Modules.<Nazwa>/FactoryWorld.Modules.<Nazwa>.csproj`: skopiuj z `Wallet` (referencja tylko do `FactoryWorld.Modules.Abstractions`, `net10.0`, `Nullable` włączone). **Moduł nie referuje innych modułów.**
2. Dodaj projekt do `server/FactoryWorld.slnx` i jako `ProjectReference` do `server/src/FactoryWorld.Server/FactoryWorld.Server.csproj`.
3. Dodaj `new <Nazwa>Module()` do listy w `server/src/FactoryWorld.Server/Program.cs`, za modułami, z których korzysta.

## 2. Klasa modułu

```csharp
/// <summary>Co moduł robi. Owns the <c>schemat</c> schema.</summary>
public sealed class <Nazwa>Module : IGameModule
{
    public string Name => "<Nazwa>";

    public void RegisterServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddModuleDbContext<<Nazwa>DbContext>(<Nazwa>DbContext.Schema);
        services.AddScoped<I<Usługa>, <Usługa>Service>();
        services.AddSingleton<IMessageHandler, Get<Coś>Handler>();
    }

    public Task InitializeAsync(IServiceProvider services, CancellationToken cancellationToken) =>
        services.MigrateModuleAsync<<Nazwa>DbContext>(cancellationToken);
}
```

- `DbContext` dziedziczy po `ModuleDbContext`, ustawia `model.HasDefaultSchema(Schema)`, tabele i kolumny w `snake_case` (`HasColumnName`), ograniczenia w bazie tam, gdzie chronią ekonomię (`HasCheckConstraint("ck_..._quantity", "quantity >= 0")`).
- Dane, których potrzebują inne moduły, wystaw jako interfejs w `server/src/FactoryWorld.Modules.Abstractions/Contracts/Services.cs` (z komentarzem `<summary>`, jakie błędy rzuca), a implementację zarejestruj w module.
- Z innych modułów korzystaj tylko przez ich interfejsy (`IInventory`, `IWallet`, `ICharacterProgress`, `IPlotRegistry`, `ICompanyPlots`...). **Żadnego SQL do cudzego schematu.**
- Operacja zmieniająca stan kilku modułów: całość w `GameDb.InTransactionAsync` (zagnieżdżone wywołania dołączają do zewnętrznej transakcji).
- Czas: `TimeProvider` z DI, nigdy `DateTime.Now`. Symulacja liczona "na żądanie" od zapisanego `startedAt` / `simulatedAt`, a nie w pętli w tle. Pętla w tle (`BackgroundService`) tylko wtedy, gdy coś musi się dziać bez graczy, jak dyspozytor pociągów.

## 3. Handlery WebSocket

- Jedna klasa na typ wiadomości, `IMessageHandler`, `Type => "<obszar>.<akcja>"` (małe litery, kropka, jak `market.buy`, `station.route`).
- Payload: `Payload.Read<Rekord>(payload)`. Sprawdź zakres każdej liczby i własność każdego `id`, `x, y` względem `client.RequireAccount()`.
- Błędy dla gracza: `throw new GameException("kod_snake_case", "English message.")`. Klient pokazuje tekst po polsku na podstawie kodu: nowy kod dopisz do słownika błędów w `client/autoload/game.gd`.
- Handler tworzy scope (`scopes.CreateAsyncScope()`) i bierze z niego serwisy, jak `GetWalletHandler`.
- Każdą nową wiadomość opisz w tabeli protokołu w `README.md` (wiadomość, payload, odpowiedź, kody błędów).

## 4. Migracja

```bash
cd server && dotnet tool restore && dotnet ef migrations add Initial --project src/Modules/FactoryWorld.Modules.<Nazwa> --startup-project src/FactoryWorld.Server --context <Nazwa>DbContext
```

Migracja trafia do `Migrations/` w module. Nie edytuj ręcznie istniejących migracji ani snapshotu.

## 5. Testy

- Nowy plik `server/tests/FactoryWorld.Server.Tests/<Nazwa>Tests.cs`, klasa `public sealed class <Nazwa>Tests(ServerFactory factory) : IClassFixture<ServerFactory>`. Gracz: `factory.ConnectAsync()` i `RegisterWithCharacterAsync()`, wiadomości przez `client.SendAsync("typ", payload)`. Wzór: `CraftingTests.cs`.
- Nazwy testów to zdania po angielsku z podkreślnikami, opisujące zachowanie z punktu widzenia gracza.
- Testy obowiązkowe: szczęśliwa ścieżka, błędny payload, cudza działka lub obiekt, za mało pieniędzy lub przedmiotów, dwa szybkie żądania pod rząd.
- Uruchomienie: `docker compose up db`, potem `cd server && dotnet test`.

## 6. Klient (jeśli moduł ma okno)

Okno w `client/ui/` w stylu sąsiednich okien, wysyłanie przez autoload sieci (`client/autoload/net.gd`). Teksty dla gracza po polsku, z obsługą dotyku (README, sekcja "Gra na telefonie").

## 7. Sprawdzenie

1. `cd server && dotnet build -warnaserror`.
2. `dotnet test` (z działającą bazą; bez niej napisz, że testy nie zostały uruchomione).
3. Moduł przenosi pieniądze lub przedmioty? Uruchom skill `audyt-ekonomii`.
4. Wpis w `client/data/changelog.json`, jeśli gracz coś zobaczy.
