---
name: nowa-zawartosc
description: Dodaje do Factory World nowy przedmiot, przepis, maszynę, mebel albo narzędzie we wszystkich miejscach, które go potrzebują (serwer, ceny, badania, klient, ikona, changelog, testy). Użyj, gdy prośba brzmi "dodaj przedmiot/maszynę/przepis/narzędzie X", "nowy towar", "nowa receptura" albo gdy zmienia się koszt lub wynik istniejącego przepisu.
---

# Nowa zawartość

Przedmiot w tej grze żyje w kilku miejscach naraz. Pominięcie jednego daje przedmiot bez nazwy, bez ikony, niemożliwy do kupienia albo dostępny bez badania. Ten skill prowadzi przez wszystkie.

## 0. Ustal z graczem (jeśli prośba tego nie mówi)

- Id (angielski `snake_case`, z prefiksem rodzaju jak reszta: `furniture_`, `tool_`, `storage_`, `backpack_`, `clothes_`, `animal_`) i nazwa po polsku.
- Skąd pochodzi (przepis: stacja, składniki, czas, XP; albo wydobycie, drop, zbiory) i do czego służy.
- Czy handlarz go sprzedaje lub skupuje i za ile.
- Czy wymaga badania i którego.

Gdy czegoś brakuje, zaproponuj wartości (patrz punkt 6) i zapytaj o zgodę jednym pytaniem, zamiast zgadywać po cichu.

## 1. Serwer: definicja

`server/src/FactoryWorld.Modules.Abstractions/Contracts/Items.cs`:

- stała `public const string X = "id";` w grupie podobnych przedmiotów, z komentarzem w stylu sąsiednich. **Id trafia do bazy: nigdy nie zmieniaj istniejącego.**
- nazwa w słowniku `Names` (`[X] = "Nazwa po polsku"`).
- jeśli to narzędzie, plecak, ubranie lub posiłek: odpowiedni rekord (`Saw`, `Backpack`, `Garment`, `Meal`) i pomocnicze `Is...` tak jak dla podobnych przedmiotów.

Obiekt stawiany na działce: rozmiar w `Contracts/Footprints.cs` (`Sizes`; poziomy maszyn: 2 × 2, 3 × 3, 4 × 4) i zbiór `PlotObjects.Placeable` w `Modules/FactoryWorld.Modules.World/PlotObjects.cs`.

## 2. Serwer: skąd się bierze

- Przepis przy stole warsztatowym lub kowadle: `Recipes` w `Modules/FactoryWorld.Modules.Crafting/Crafting.cs`, `new(Items.X, ilość, TimeSpan..., [(składnik, ilość), ...], xp, Station)`.
- Maszyna przetwórcza, piec, stołówka: `Processing.cs`, `Furnace.cs`, `Canteen.cs` w tym samym module.
- Wydobycie, zbiory, dropy, las, wybrzeże: moduł `World` (`PlotInterior.cs`, `Mining.cs`, `Forestry.cs`, `Coast.cs`...). Losowanie zawsze na serwerze (`Random.Shared` przekazany do czystej funkcji).

## 3. Serwer: ekonomia

`Modules/FactoryWorld.Modules.Market/MarketModule.cs`, klasa `NpcPrices` (ceny w centach):

- `Buys`: ile handlarz płaci graczowi.
- `OwnSells`: ile handlarz bierze, gdy ma to sprzedawać po własnej cenie; reszta kosztuje `Markup` × cena skupu.
- Zasada: handlarz zawsze płaci mniej, niż bierze. Kup → przetwórz → sprzedaj u handlarza nie może dawać zysku bez pracy lub czasu.

Do tego, jeśli pasuje: `MarketEvents.cs` (wydarzenia rynkowe), `Contracts/NpcContracts.cs` (zlecenia NPC), `Bots/BotRules.cs` (czym handlują boty).

## 4. Serwer: badania

Maszyny, logistyka i towary handlarza dostępne są dopiero po badaniu: lista `unlocks` właściwej technologii w `Modules/FactoryWorld.Modules.Research/Research.cs`. Nowa technologia: `new(Id, "Nazwa", "Opis po polsku.", [wymagane], [koszt], czas, xp, [odblokowuje])` w odpowiedniej gałęzi.

## 5. Klient i grafika

- `client/ui/item_info.gd`: wpis `"id": ["Nazwa", "Opis.", "Skąd: stacja: składniki → ilość (czas)."]` i, jeśli wzorce id nie wystarczą, kategoria w `CATEGORIES`.
- Ikona `client/art/icons/item_<id>.png`: funkcja w `tools/render_plot_art.py` dodana do słownika ikon (`"item_<id>": funkcja`), render: `.venv-art/bin/python tools/render_plot_art.py item_<id>` (wymaga Blendera i `bpy`, opis w pliku). Obiekt na działce potrzebuje też sprite'a (i cienia) w `client/art/plot/` oraz wpisu w `client/art/plot/layout.json`.
- Nie mogę uruchomić Blendera? Napisz to wprost i zostaw funkcję renderującą gotową do uruchomienia przez gracza.
- Nowa wiadomość WebSocket albo nowe pole w odpowiedzi: obsługa w oknie w `client/ui/` lub scenie w `client/scenes/` i wiersz w tabeli protokołu w `README.md`.

## 6. Balans przed zapisaniem

Policz i pokaż w odpowiedzi (skill `balans` robi to dokładniej):

- koszt składników po cenach skupu handlarza i wartość produktu: przetworzenie powinno zarabiać, ale niewiele więcej niż sąsiednie przepisy tego samego poziomu;
- zarobek na minutę jednej maszyny w porównaniu z innymi maszynami tej samej gałęzi;
- czy nowy przedmiot nie omija istniejącego łańcucha (tańsza droga do tego samego).

## 7. Testy, changelog, README

- Test w `server/tests/FactoryWorld.Server.Tests/` obok podobnych (np. `CraftingTests.cs`, `ProcessingTests.cs`, `ResearchTests.cs`), nazwa testu jako zdanie: `The_<stacja>_makes_<co>_from_<składniki>_in_<czas>`. `CompendiumTests` sprawdza, że każdy przedmiot ma swoje miejsce w kompendium.
- `client/data/changelog.json`: nowy wpis na górze (data, tytuł, zmiany po polsku, językiem gracza).
- `README.md`: zaktualizuj opis modułu lub protokołu, jeśli się zmienił.

## 8. Sprawdzenie

1. `cd server && dotnet build -warnaserror` (tak jak CI).
2. `docker compose up db`, potem `cd server && dotnet test`. Bez działającej bazy napisz, że testy nie zostały uruchomione.
3. Zmiana przenosi pieniądze lub przedmioty w nowy sposób? Uruchom skill `audyt-ekonomii`.

Na koniec wypisz listę zmienionych plików pogrupowaną jak punkty 1–7 i to, czego nie zrobiono (np. render ikony).
