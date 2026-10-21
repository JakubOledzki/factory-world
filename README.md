# Factory World

Wieloosobowa gra fabryczna 2D w stylu pixelart, na Windows, Androida, iOS i przeglądarkę.
Projekt gry: [dokument projektowy](https://claude.ai/code/artifact/50d66faa-a0b4-40d8-ae3f-b46f451ab938).

## Struktura

| Katalog | Zawartość |
| --- | --- |
| `client/` | Klient gry w Godot 4.5 (GDScript) |
| `server/` | Serwer gry w C#/.NET 10, modularny monolit |
| `server/src/Modules/` | Moduły gry: `Session` (powitanie, ping), `Accounts` (rejestracja, logowanie, sesje), `Characters` (postać, wygląd, poziom), `Inventory` (przedmioty), `Wallet` (pieniądze i historia operacji), `Market` (handlarz NPC), `Recycling` (garaż, kosz na śmieci, segregacja), `World` (mapa Ziemi, działki 5 × 5 km, zakup działek) |
| `docker-compose.yml` | PostgreSQL i serwer do lokalnego uruchomienia |
| `tools/render_art.py` | Renderuje grafikę (pusty garaż, meble z cieniami, postać w 4 kierunkach z animacją chodu, ikony) w Blenderze do `client/art/`; modele są budowane w kodzie, a gra wyświetla gotowe obrazki 2D. Wymaga modułu `bpy` (instrukcja w pliku) |
| `tools/generate_ui.py` | Rysuje tekstury interfejsu (panele, przyciski, paski) do `client/art/ui/` |
| `tools/render_plot_art.py` | Renderuje grafikę wnętrza działek (podłogi biomów, drzewa, skały, krzaki, wydmy z cieniami, tory, stacja) do `client/art/plot/` i ikony narzędzi oraz surowców; korzysta z pomocników `render_art.py` |
| `tools/build_world.py` | Buduje mapę świata z otwartych danych: biom każdej działki 5 × 5 km (`client/world/biomes.bin.gz`, ta sama kopia w module `World` serwera) i miejscowości (`client/world/towns.tsv.gz`); źródła i zasady opisane w pliku |
| `deploy/` | Wdrożenie produkcyjne: Caddy (HTTPS + gra w przeglądarce), compose, `.env` |

## Uruchomienie lokalne

Wymagane: [.NET 10 SDK](https://dotnet.microsoft.com/download), [Godot 4.5](https://godotengine.org/download), Docker.

1. Baza danych: `docker compose up db`
2. Serwer: `cd server && dotnet run --project src/FactoryWorld.Server` (nasłuchuje na `http://localhost:5080`, WebSocket pod `/ws`)
3. Klient: otwórz `client/project.godot` w Godot i naciśnij F5. Po połączeniu pojawi się ekran logowania.

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
| `character.create` | `{ name, appearance }` | `character` `{ name, appearance, level, xp, levelXp, nextLevelXp, tool: { id, name } \| null }` |
| `garage.get` | | `garage` `{ trash, queue: [finishesAtMs], serverTime, sortSeconds, maxQueue, results: [{ id, name }], xp, room: { width, depth, cellSize }, objects: [{ id, kind, x, y, rotation }], furniture: { kind: { name, width, depth } } }`; przy okazji wydaje zakończone segregacje |
| `recycling.sort` | `{ count }` | `garage`; wymaga kosza stojącego w garażu. Bez automatycznej sortowni (`furniture_sorting_machine`, 1000 $ u handlarza) w kolejce może być tylko 1 worek, a klient zleca kolejny, dopóki postać stoi przy koszu; z sortownią kolejka mieści 10 worków i działa bez gracza |
| `recycling.stop` | | `garage`; bez sortowni przerywa segregację (niedokończony worek wraca do śmieci); z sortownią nic nie robi. Klient wysyła je, gdy postać odchodzi od kosza |
| `garage.pickup` | `{ id }` | `garage`; mebel trafia do ekwipunku |
| `garage.place` | `{ kind, x, y, rotation }` | `garage`; stawia mebel z ekwipunku na polu (x, y), obróconym o `rotation` × 90° (0–3) |
| `inventory.get` | | `inventory` `{ items: [{ id, name, quantity }] }` |
| `wallet.get` | | `wallet` `{ balanceCents }` |
| `market.prices` | | `market.prices` `{ items: [{ id, name, buyCents, sellCents }] }` |
| `market.buy` / `market.sell` | `{ item, quantity }` | `market.traded` `{ item, quantity, balanceCents }` |
| `world.info` | | `world.info` `{ width, height, plotKm, biomes: [{ id, name, buyable, priceFactor, bonuses: [{ text, good }] }], priceTiersCents, nextBasePriceCents, plots: [{ x, y, biome }] }` (`plots` to działki gracza) |
| `world.area` | `{ x, y, width, height }` | `world.area` `{ x, y, width, height, plots: [{ x, y, mine }] }`: kupione działki w prostokącie (do 10 000 × 10 000) |
| `world.plot` | `{ x, y }` | `world.plot` `{ x, y, biome, owner: { name, mine } \| null, priceCents, survey, surveyPriceCents }`; `priceCents` to cena dla pytającego gracza albo `null` (woda, działka zajęta) |
| `world.buy` | `{ x, y }` | `world.bought` `{ plot, balanceCents, xp, tool: { id, name } \| null }` |
| `character.equip` | `{ item }` | `character`: narzędzie z ekwipunku trafia do ręki, poprzednie wraca do ekwipunku |
| `character.unequip` | | `character`: narzędzie z ręki wraca do ekwipunku |
| `plot.enter` | `{ x, y }` | `plot` `{ x, y, biome, size, tileMeters, tiles, railRow, station: { x, y, width, height }, spawn: { x, y }, tool, harvestSeconds, fertile, fields, crops: [{ id, name, growSeconds, yield, xp }], serverTime }`; `tiles` to gzip w base64, bajt na pole (wiersz po wierszu): 0 nic, 1 drzewo, 2 skała, 3 wydma, 4 tory, 5 stacja, 6 krzak |
| `plot.harvest` | `{ x, y, tileX, tileY }` | `plot.harvested` `{ tileX, tileY, items: [{ id, name, quantity }], xp }` |
| `plot.till` | `{ x, y, tileX, tileY }` | `plot.field` `{ field: { tileX, tileY, crop, readyAt }, items, xp, serverTime }`: motyka w ręku zamienia wolne pole żyznej działki w zaorane pole |
| `plot.plant` | `{ x, y, tileX, tileY, crop }` | `plot.field`: zasiew na pustym zaoranym polu |
| `plot.reap` | `{ x, y, tileX, tileY }` | `plot.field` z `items`: zbiór dojrzałej rośliny, pole zostaje zaorane |
| `world.survey` | `{ x, y }` | `world.surveyed` `{ x, y, survey: { oil, gas }, balanceCents }`: płatne badanie geologiczne własnej działki (0 brak, 1 małe, 2 średnie, 3 duże złoże) |
| `station.get` | `{ x, y }` | `station` `{ x, y, items, incoming, outgoing, serverTime, rates }`; pociągi to `{ fromX, fromY, toX, toY, item, name, quantity, arrivesAt }` |
| `station.load` / `station.unload` | `{ x, y, item, quantity }` | `station`: z ekwipunku na stację albo ze stacji do ekwipunku |
| `station.send` | `{ x, y, toX, toY, item, quantity }` | `station`: pociąg jedzie na stację innej kupionej działki (swojej albo innego gracza) |

Czasy w `garage` to milisekundy uniksowe według zegara serwera; `xp` to `{ xp, level, leveledUp }` albo `null`.
Podłoga garażu to kratownica `room.width` × `room.depth` pól o boku `room.cellSize` metrów. Mebel zajmuje `width` × `depth` pól (po obrocie o 90° lub 270° na odwrót); `x`, `y` to jego lewe przednie pole. Meble nie mogą wystawać poza podłogę ani nachodzić na siebie.
Kwoty są w centach. `buyCents` to cena, za którą gracz kupuje od handlarza, `sellCents` to cena skupu.

Mapa świata to siatka działek 5 × 5 km w odwzorowaniu równopowierzchniowym Behrmanna (każda działka ma 25 km² na całym globie). Kolumna `x` liczy się od 180° W na wschód, wiersz `y` od bieguna północnego; mapa zawija się ze wschodu na zachód. Biomy mają stałe numery (0 ocean, 1 jezioro, 2 las, 3 żyzne gleby, 4 step i łąki, 5 pustynia, 6 góry, 7 tundra, 8 lodowiec, 9 miasto, 10 wybrzeże, 11 pojezierze). Wody nie można kupić. Cena n-tej działki gracza to 1 000 $, 10 000 $, 100 000 $, 1 000 000 $, a piątej i każdej kolejnej 1 000 000 000 $, razy mnożnik biomu (żyzne gleby, wybrzeże i pojezierze ×1,5, miasto ×2). Zakup daje 500 XP.

Za zakup lasu gracz dostaje siekierę, pustyni łopatę, gór kilof, żyznych gleb motykę (do pustej ręki, a jeśli coś już trzyma, do ekwipunku); pozostałe biomy nie dają narzędzia. Wnętrze działki to 250 × 250 pól po 20 m, generowane zawsze tak samo z położenia działki; serwer zapisuje tylko to, co gracze zebrali. Drzewo ścina się siekierą (3 drewna), skałę rozbija kilofem (2 kamienie i szansa na węgiel, rudę żelaza lub miedzi), wydmę przekopuje łopatą (3 piasku); jedno pole to 1,5 s pracy i 2 XP. Wzdłuż północnej krawędzi każdej działki biegną tory ze stacją. Pociąg jedzie 5 s na 100 km (najkrócej 10 s), opłata to 1 $ plus 1 cent za sztukę na każde 100 km.

Na żyznych glebach motyka orze wolne pola (1,5 s pracy, 1 XP). Na zaoranym polu sieje się jedną z roślin: pszenica 5 min, marchew 7 min, kapusta 8 min, kukurydza 10 min, ziemniaki 15 min, słonecznik 20 min; dojrzałą roślinę zbiera się ręką, a pole zostaje zaorane. Pod każdą działką mogą leżeć złoża ropy i gazu (stałe dla danego miejsca, częstsze na tundrze, pustyni i wybrzeżu), ale nie widać ich na mapie: właściciel działki może zlecić badanie geologiczne za 5 000 $, a wynik widzi tylko on.

Wszystko poza `hello`, `ping`, `auth.*` i `character.options` wymaga zalogowania.

Migracje bazy (EF Core) każdy moduł trzyma u siebie w `Migrations/` we własnym schemacie i uruchamia przy starcie serwera.
Nowa migracja: `cd server && dotnet tool restore && dotnet ef migrations add <Nazwa> --project src/Modules/FactoryWorld.Modules.<Moduł> --startup-project src/FactoryWorld.Server --context <Moduł>DbContext`.

## Nowy moduł serwera

1. Utwórz bibliotekę w `server/src/Modules/FactoryWorld.Modules.<Nazwa>` z referencją do `FactoryWorld.Modules.Abstractions`.
2. Zaimplementuj `IGameModule` i zarejestruj w nim handlery wiadomości (`IMessageHandler`).
3. Dodaj moduł do listy w `server/src/FactoryWorld.Server/Program.cs`.

Moduły nie czytają nawzajem swoich tabel; korzystają tylko z publicznych serwisów innych modułów.

## Dane mapy świata

Mapa powstaje z otwartych danych (`tools/build_world.py`): strefy klimatyczne Köppena-Geigera (Rubel i Kottek, przez pakiet [kgcpy](https://pypi.org/project/kgcpy/)), warstwy [Natural Earth](https://www.naturalearthdata.com/) (miasta, jeziora, lodowce, pasma górskie, polskie nazwy dużych miast) i miejscowości z [GeoNames](https://www.geonames.org/) (CC BY 4.0, przez pakiet [all-the-cities](https://www.npmjs.com/package/all-the-cities)). Podział lądu na las, pola i łąki w obrębie jednej strefy klimatycznej jest przybliżony szumem, bo nie ma darmowej mapy lasów dość małej, by trzymać ją w repozytorium.
