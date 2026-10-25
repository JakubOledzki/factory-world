# Factory World

Wieloosobowa gra fabryczna 2D (pixelart): klient w Godot 4.5 (GDScript) w `client/`, serwer w C#/.NET 10 z PostgreSQL w `server/`. Pełny opis modułów i protokołu WebSocket jest w `README.md`; dokument projektowy gry jest podlinkowany na jego początku.

## Polecenia

- Baza: `docker compose up db`
- Serwer: `cd server && dotnet run --project src/FactoryWorld.Server` (http://localhost:5080, WebSocket `/ws`)
- Build jak w CI: `cd server && dotnet build -warnaserror`
- Testy (wymagają bazy): `cd server && dotnet test`; inny serwer bazy przez `FW_TEST_DB`
- Migracja: `cd server && dotnet tool restore && dotnet ef migrations add <Nazwa> --project src/Modules/FactoryWorld.Modules.<Moduł> --startup-project src/FactoryWorld.Server --context <Moduł>DbContext`
- Klient: `client/project.godot` w Godot, F5. CI sprawdza skrypty: `godot --headless --script res://tools/check_scripts.gd`
- Grafika: `tools/render_art.py`, `tools/render_plot_art.py` (Blender, `bpy`); gra wyświetla gotowe obrazki 2D

## Zasady, których nie wolno łamać

- **Serwer decyduje o wszystkim.** Klient wysyła tylko intencje; serwer losuje dropy (`Random.Shared` przekazany do czystej funkcji), liczy czas (`TimeProvider`) i księguje pieniądze. Nic z payloadu nie jest prawdą bez sprawdzenia: zakres liczb i własność `id` / działki względem `client.RequireAccount()`.
- **Moduły rozmawiają tylko przez interfejsy** z `server/src/FactoryWorld.Modules.Abstractions/Contracts/Services.cs`. Każdy moduł ma własny schemat bazy i nie czyta ani nie pisze cudzych tabel. Moduł nie referuje innych modułów.
- **Wszystko albo nic.** Operacja zmieniająca stan kilku modułów (pieniądze + przedmioty) idzie w jednym `GameDb.InTransactionAsync`. Zabieranie sprawdza stan w tym samym zapytaniu, które go zmienia.
- **Pieniądze tylko przez `IWallet`** (każda zmiana to wpis w księdze z `reason`), w centach (`long`).
- **Id przedmiotów trafiają do bazy:** nigdy nie zmieniaj istniejącego id w `Contracts/Items.cs`.
- **Symulacja na żądanie:** maszyny, piece i taśmy doganiają czas od `startedAt` / `simulatedAt`, a nie liczą się w pętli. W tle działa tylko to, co musi działać bez graczy (pociągi, eksport, banki, boty).
- **Handlarz zawsze płaci mniej, niż sam bierze** za ten sam towar, także przy wydarzeniach rynkowych i premiach.

## Styl

- Kod, komentarze, nazwy, komunikaty `GameException` i commity: po angielsku. Kody błędów w `snake_case`; polski tekst błędu dla gracza w `client/autoload/game.gd`.
- Teksty dla gracza (nazwy przedmiotów, opisy, changelog, README): po polsku.
- Testy: xUnit w `server/tests/FactoryWorld.Server.Tests/`, przez prawdziwy WebSocket (`ServerFactory`, `GameClient`), nazwy jako zdania: `The_workbench_makes_...`.
- Zmiana widoczna dla gracza: wpis na górze `client/data/changelog.json`. Nowa lub zmieniona wiadomość: tabela protokołu w `README.md`.

## Skille projektu (`.claude/skills/`)

- `nowa-zawartosc`: nowy przedmiot, przepis, maszyna, narzędzie we wszystkich miejscach naraz.
- `nowy-modul`: nowy moduł serwera według zasad modularnego monolitu.
- `audyt-ekonomii`: przed commitem zmian dotykających pieniędzy, przedmiotów, rynku, nagród.
- `balans`: zarobki, łańcuchy produkcji, czasy do celów, liczone z kodu.

Hook `Stop` (`.claude/settings.json`) buduje serwer z `-warnaserror`, gdy w `server/` są niezatwierdzone zmiany i jest zainstalowany .NET 10 SDK.
