# Factory World

Wieloosobowa gra fabryczna 2D w stylu pixelart, na Windows, Androida, iOS i przeglądarkę.
Projekt gry: [dokument projektowy](https://claude.ai/code/artifact/50d66faa-a0b4-40d8-ae3f-b46f451ab938).

## Struktura

| Katalog | Zawartość |
| --- | --- |
| `client/` | Klient gry w Godot 4.5 (GDScript) |
| `server/` | Serwer gry w C#/.NET 10, modularny monolit |
| `server/src/Modules/` | Moduły gry: `Session` (powitanie, ping), `Accounts` (rejestracja, logowanie, sesje), `Characters` (postać, wygląd, poziom) |
| `docker-compose.yml` | PostgreSQL i serwer do lokalnego uruchomienia |
| `deploy/` | Wdrożenie produkcyjne: Caddy (HTTPS + gra w przeglądarce), compose, `.env` |

## Uruchomienie lokalne

Wymagane: [.NET 10 SDK](https://dotnet.microsoft.com/download), [Godot 4.5](https://godotengine.org/download), Docker.

1. Baza danych: `docker compose up db`
2. Serwer: `cd server && dotnet run --project src/FactoryWorld.Server` (nasłuchuje na `http://localhost:5080`, WebSocket pod `/ws`)
3. Klient: otwórz `client/project.godot` w Godot i naciśnij F5. Na ekranie powinno pojawić się „Połączono z serwerem” i ping.

Całość w Dockerze: `docker compose up --build`.

Testy serwera potrzebują PostgreSQL (`docker compose up db`), a potem: `cd server && dotnet test`.
Każdy przebieg tworzy własną bazę testową i usuwa ją na końcu. Inny serwer bazy wskażesz zmienną `FW_TEST_DB`.

Wdrożenie na serwer Linux: [docs/deploy.md](docs/deploy.md).

Adres serwera dla klienta ustawia się w Godot w *Project Settings → factory_world/server_url*.

## Protokół

Każda wiadomość WebSocket to jeden obiekt JSON:

```json
{ "type": "ping", "id": "7", "payload": {} }
```

Klient nadaje `id`, serwer odsyła je w odpowiedzi. Błędy mają typ `error` i payload `{ "code": "...", "message": "..." }`.
Pierwsza wiadomość po połączeniu to `hello` z `{ "protocol": 1 }`, odpowiedź `welcome`.

| Wiadomość | Payload | Odpowiedź |
| --- | --- | --- |
| `auth.register` / `auth.login` | `{ email, password }` | `auth.ok` `{ accountId, token }` |
| `auth.resume` | `{ token }` (zapisany na urządzeniu) | `auth.ok` |
| `auth.logout` | `{ token }` | `auth.loggedOut` |
| `character.options` | | palety i liczby opcji edytora |
| `character.get` | | `character` albo `character.none` |
| `character.create` | `{ name, appearance }` | `character` `{ name, appearance, level, xp, levelXp, nextLevelXp }` |

Wszystko poza `hello`, `ping`, `auth.*` i `character.options` wymaga zalogowania.

Migracje bazy (EF Core) każdy moduł trzyma u siebie w `Migrations/` we własnym schemacie i uruchamia przy starcie serwera.
Nowa migracja: `cd server && dotnet tool restore && dotnet ef migrations add <Nazwa> --project src/Modules/FactoryWorld.Modules.<Moduł> --startup-project src/FactoryWorld.Server --context <Moduł>DbContext`.

## Nowy moduł serwera

1. Utwórz bibliotekę w `server/src/Modules/FactoryWorld.Modules.<Nazwa>` z referencją do `FactoryWorld.Modules.Abstractions`.
2. Zaimplementuj `IGameModule` i zarejestruj w nim handlery wiadomości (`IMessageHandler`).
3. Dodaj moduł do listy w `server/src/FactoryWorld.Server/Program.cs`.

Moduły nie czytają nawzajem swoich tabel; korzystają tylko z publicznych serwisów innych modułów.
