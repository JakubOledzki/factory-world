# Factory World

Wieloosobowa gra fabryczna 2D w stylu pixelart, na Windows, Androida, iOS i przeglądarkę.
Projekt gry: [dokument projektowy](https://claude.ai/code/artifact/50d66faa-a0b4-40d8-ae3f-b46f451ab938).

## Struktura

| Katalog | Zawartość |
| --- | --- |
| `client/` | Klient gry w Godot 4.5 (GDScript) |
| `server/` | Serwer gry w C#/.NET 10, modularny monolit |
| `server/src/Modules/` | Moduły gry: `Session` (powitanie, ping), `Accounts` (rejestracja, logowanie, sesje), `Characters` (postać, wygląd, poziom), `Inventory` (przedmioty), `Wallet` (pieniądze i historia operacji), `Market` (handlarz NPC, szybka sprzedaż, handel między graczami, wydarzenia rynkowe i zmienne ceny), `Recycling` (garaż, kosz na śmieci, segregacja), `World` (mapa Ziemi, działki 5 × 5 km, zakup działek), `Crafting` (stół warsztatowy, piec kamienny, maszyny przetwórcze: młyn, tłocznia oleju, beczka do kiszenia, piec piekarski, kuchnia polowa), `Logistics` (taśmociągi, rozdzielacze, podajniki, skrzynie, stosy, hałdy i silosy na działkach), `Contracts` (zlecenia firm NPC i graczy z nagrodą i terminem), `Achievements` (odznaki za kamienie milowe i rankingi graczy) |
| `docker-compose.yml` | PostgreSQL i serwer do lokalnego uruchomienia |
| `tools/render_art.py` | Renderuje grafikę (pusty garaż, meble z cieniami, postać w 4 kierunkach z animacją chodu, ikony) w Blenderze do `client/art/`; modele są budowane w kodzie, a gra wyświetla gotowe obrazki 2D. Wymaga modułu `bpy` (instrukcja w pliku) |
| `tools/generate_ui.py` | Rysuje tekstury interfejsu (panele, przyciski, paski) do `client/art/ui/` |
| `tools/render_plot_art.py` | Renderuje grafikę wnętrza działek (podłogi biomów, drzewa, skały, krzaki, wydmy z cieniami, tory, stacja, stół warsztatowy, piec, maszyny przetwórcze, taśmociągi z zakrętami, rozdzielacz, podajnik, skrzynie, stos drewna, hałda i silos) do `client/art/plot/` i ikony narzędzi, surowców, sztabek i żywności; korzysta z pomocników `render_art.py` |
| `tools/build_world.py` | Buduje mapę świata z otwartych danych: biom każdej działki 5 × 5 km (`client/world/biomes.bin.gz`, ta sama kopia w module `World` serwera) i miejscowości (`client/world/towns.tsv.gz`); źródła i zasady opisane w pliku |
| `tools/loadtest/` | Test obciążenia: boty grające przez WebSocket (10 … 10 000 graczy naraz), czasy odpowiedzi, przepustowość, błędy, CPU i RAM, raport z wykresami ([instrukcja](tools/loadtest/README.md)) |
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

## Wydarzenia rynkowe

Ceny handlarza nie stoją w miejscu. To, ile płaci za każdy przedmiot, co dzień zmierza do nowej wartości (najwyżej ±10% od zwykłej ceny) i zmienia się co godzinę.
Do tego doba dzieli się na 4 części po 6 godzin, a w mniej więcej połowie z nich trwa wydarzenie: susza (zboże i warzywa drożeją), urodzaj, boom na stal,
boom budowlany, sroga zima, gorączka miedzi, gorączka złota, akcja recyklingu, jarmark albo wyprzedaż maszyn. Handlarz pokazuje trwające wydarzenie
i zapowiada następne, żeby można było zawczasu zrobić zapasy. Kalendarz wynika z samego czasu (`MarketEvents`), więc nic nie trzeba zapisywać,
a każdy serwer liczy te same ceny. Handlarz zawsze płaci mniej, niż sam bierze za ten sam towar. Ustawienie `Market:PriceChanges=false` wyłącza zmiany
(testy serwera korzystają z niego, żeby liczyć na zwykłe ceny).

Adres serwera dla klienta ustawia się w Godot w *Project Settings → factory_world/server_url*.

## Gra na telefonie

Wersja przeglądarkowa działa też na telefonie i tablecie: wystarczy otworzyć adres gry w przeglądarce i obrócić telefon poziomo.
Na ekranie dotykowym gra pokazuje większe litery i przyciski, joystick do chodzenia (lewy dolny róg) i przyciski akcji
*Użyj*, *Obróć*, *Anuluj* (prawa strona), zamiast klawiszy E, R i Esc. Dotknięcie gry działa jak kliknięcie myszą,
dwoma palcami przybliża się mapę świata i działkę, a długie okna przewija się palcem. Przycisk *Pełny ekran* chowa pasek
przeglądarki (Android); na iPhonie ten sam efekt daje *Udostępnij → Do ekranu początkowego*.
Sterowanie dotykowe na komputerze włącza `?touch=1` w adresie (`?touch=0` je wyłącza).

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
| `inventory.get` | | `inventory` `{ slots, items: [{ id, name, quantity, slot }] }`; `slot` to kafelek ekwipunku (0 … `slots` − 1), przedmiot bez kafelka dostaje pierwszy wolny |
| `inventory.move` | `{ item, slot }` | `inventory`; przenosi przedmiot na kafelek `slot`, a przedmiot, który tam leżał, zamienia się z nim miejscami |
| `wallet.get` | | `wallet` `{ balanceCents }` |
| `market.prices` | | `market.prices` `{ items: [{ id, name, buyCents, buyChange, sellCents, sellChange }], event, next, serverTime }`: ceny handlarza teraz i ich zmiana w procentach względem zwykłych; `event` to trwające wydarzenie rynkowe, `next` najbliższe następne (albo `null`), każde `{ id, name, description, startsAtMs, endsAtMs, effects: [{ item, name, sellChange, buyChange }] }` |
| `market.buy` / `market.sell` | `{ item, quantity }` | `market.traded` `{ item, quantity, balanceCents }`; `market.sell` to szybka sprzedaż: handlarz płaci od razu najniższą cenę rynku (`sellCents`) |
| `market.overview` | | `market.overview` `{ items: [{ id, name, quickSaleCents, lowestCents, listed, highestCents, wanted }] }`: każdy przedmiot z ceną szybkiej sprzedaży (albo `null`), najtańszym ogłoszeniem i najlepszym zleceniem kupna graczy |
| `market.item` | `{ item }` | `market.item` `{ item, name, listings, orders }`, oferty `[{ id, quantity, priceCents, owner, mine }]`: ogłoszenia od najtańszego, zlecenia od najlepiej płacącego (po 50) |
| `market.mine` | | `market.mine` `{ listings, orders }`, oferty `[{ id, item, name, quantity, done, priceCents, open }]`: otwarte i zamknięte w ciągu doby |
| `market.list` | `{ item, quantity, priceCents }` | `market.done` `{ balanceCents }`; wystawia ogłoszenie sprzedaży, przedmioty od razu znikają z ekwipunku i czekają w ogłoszeniu |
| `market.unlist` | `{ id }` | `market.done`; zamyka własne ogłoszenie, niesprzedane przedmioty wracają do ekwipunku |
| `market.purchase` | `{ id, quantity }` | `market.done`; kupuje z ogłoszenia innego gracza: pieniądze idą do sprzedającego, przedmioty do kupującego |
| `market.order` | `{ item, quantity, priceCents }` | `market.done`; zleca kupno, cała kwota od razu schodzi z portfela i czeka w zleceniu |
| `market.cancelOrder` | `{ id }` | `market.done`; zamyka własne zlecenie, niewydane pieniądze wracają |
| `market.fill` | `{ id, quantity }` | `market.done`; wypełnia zlecenie innego gracza: przedmioty trafiają do zlecającego, zapłata do wypełniającego. Gracz ma najwyżej 20 otwartych ogłoszeń i 20 zleceń, oferta to 1–10 000 sztuk po 0,01–1 000 000 $ |
| `world.info` | | `world.info` `{ width, height, plotKm, biomes: [{ id, name, buyable, priceFactor, bonuses: [{ text, good }] }], priceTiersCents, nextBasePriceCents, plots: [{ x, y, biome }] }` (`plots` to działki gracza) |
| `world.area` | `{ x, y, width, height }` | `world.area` `{ x, y, width, height, plots: [{ x, y, mine }] }`: kupione działki w prostokącie (do 10 000 × 10 000) |
| `world.plot` | `{ x, y }` | `world.plot` `{ x, y, biome, owner: { name, mine } \| null, priceCents, survey, surveyPriceCents }`; `priceCents` to cena dla pytającego gracza albo `null` (woda, działka zajęta) |
| `world.buy` | `{ x, y }` | `world.bought` `{ plot, balanceCents, xp, tool: { id, name } \| null }` |
| `character.equip` | `{ item }` | `character`: narzędzie z ekwipunku trafia do ręki, poprzednie wraca do ekwipunku |
| `character.unequip` | | `character`: narzędzie z ręki wraca do ekwipunku |
| `plot.enter` | `{ x, y }` | `plot` `{ x, y, biome, size, tileMeters, tiles, railRow, station: { x, y, width, height }, spawn: { x, y }, tool, harvestSeconds, chopSeconds, mineSeconds, mineUnits, mines: [{ id, x, y, width, height, units, refillAt }], treeGrowSeconds, trees: [{ tileX, tileY, readyAt }], objects: [{ id, kind, name, tileX, tileY }], placeable, fertile, fields, crops: [{ id, name, growSeconds, yield, xp }], serverTime }`; `treeGrowSeconds` to czas wzrostu sadzonki na tej działce (`null` na lodowcu); `tiles` to gzip w base64, bajt na pole (wiersz po wierszu): 0 nic, 1 drzewo, 2 skała, 3 wydma, 4 tory, 5 stacja, 6 krzak, 7 kopalnia; `units` to jednostki kopalni, `refillAt` to chwila odnowienia wyczerpanej kopalni (albo `null`) |
| `plot.place` | `{ x, y, kind, tileX, tileY, rotation }` | `plot.placed` `{ object: { id, kind, name, tileX, tileY, rotation } }`: stawia stół warsztatowy, piec, maszynę przetwórczą, taśmociąg, rozdzielacz, podajnik albo magazyn z ekwipunku, obrócony o `rotation` × 90° (0 na południe, 1 na wschód, 2 na północ, 3 na zachód), na wolnym polu własnej działki (lista `placeable` w `plot`) |
| `plot.pickup` | `{ x, y, id }` | `plot.pickedUp` `{ id }`: obiekt wraca do ekwipunku, a z pieca, maszyny, taśmociągu, podajnika i magazynu wraca też to, co w nich było |
| `plot.rotate` | `{ x, y, id, rotation }` | `plot.rotated` `{ object }`: obraca obiekt na własnej działce |
| `splitter.set` | `{ x, y, id, side, items }` | `logistics` (jak wyżej): rozdzielacz wysyła `items` (najwyżej 8) na stronę `side` (0 lewa, 1 prawa), a resztę na drugą; pusta lista i dzieli na zmianę |
| `logistics.get` | `{ x, y }` | `logistics` `{ simulatedAt, serverTime, tickMs, beltSlots, beltLanes, swingTicks, belts: [{ id, items, filter, filterSide, turn }], inserters: [{ id, hand, swing }], storages: [magazyn], names }`: taśmociągi, rozdzielacze, podajniki i magazyny działki policzone do teraz; `items` to miejsca taśmy, tor po torze (lewy, potem prawy, każdy od wejścia do wyjścia, `null` to puste), u rozdzielacza `filter` to wybrane przedmioty, `filterSide` strona, na którą idą (0 lewa, 1 prawa), a `turn` strona następnego przedmiotu bez filtra; `names` (gdy na działce jest rozdzielacz) to nazwy wszystkich przedmiotów, `swing` to położenie ramienia podajnika (0 z tyłu … `swingTicks` z przodu), a od `simulatedAt` klient liczy dalej sam, tymi samymi zasadami |
| `storage.get` | `{ x, y, id }` | `storage` `{ id, kind, name, slots, slotSize, usedSlots, capacity, stored, only, items }`: co leży w magazynie; `only` to jedyne przedmioty, które przyjmuje (albo `null`) |
| `storage.put` / `storage.take` | `{ x, y, id, item, quantity }` | `storage`: z ekwipunku do magazynu albo z powrotem (`quantity` 0 przy `take` wyjmuje wszystko) |
| `crafting.get` | | `crafting` `{ recipes: [{ id, name, quantity, seconds, ingredients: [{ id, name, quantity }], xp }], queue: [{ id, recipe, name, startsAt, finishesAt }], maxQueue, serverTime, done: [{ id, name, quantity }], xp }`; przy okazji wydaje gotowe zamówienia |
| `crafting.craft` | `{ workbench, recipe }` | `crafting`: zamawia przedmiot przy stole warsztatowym gracza (`workbench` to id stołu w garażu albo na działce); składniki znikają od razu |
| `crafting.cancel` | `{ id }` | `crafting`: odwołuje zamówienie, składniki wracają, a kolejne zamówienia przesuwają się do przodu |
| `furnace.get` | `{ furnace }` | `furnace` `{ id, input, output, fuel, heat, startedAt, smeltSeconds, serverTime, recipes: [{ input, inputName, output, outputName, seconds }], smeltsPerCoal, maxInput, maxFuel, taken, xp }`; `input` i `output` to `{ id, name, quantity }` albo `null`, `heat` to przetopienia, na które starczy już rozpalonego węgla, `startedAt` to początek przetapiania bieżącej sztuki (albo `null`, gdy piec wygasł) |
| `furnace.load` | `{ furnace, item, quantity }` | `furnace`: węgiel trafia do paleniska, ruda do przetopienia (jeden rodzaj naraz; gotowe sztabki innego metalu wracają wtedy do ekwipunku) |
| `furnace.take` | `{ furnace, what }` | `furnace`: wyjmuje `output` (sztabki, 1 XP za sztukę), `input` (nieprzetopioną rudę) albo `fuel` (węgiel) |
| `machine.get` | `{ machine }` | `machine` `{ id, kind, name, recipe, recipes: [{ id, name, quantity, seconds, ingredients, xp }], inputs: [{ id, name, quantity, need }], output, fired, fuel, heat, fuels: [{ id, name, batches }], batches, startedAt, seconds, serverTime, maxInput, maxFuel, maxOutput, taken, xp }`: maszyna przetwórcza na działce (młyn, tłocznia oleju, beczka do kiszenia, piec piekarski, kuchnia polowa). `output` i `fuel` to `{ id, name, quantity }` albo `null`, `batches` to partie, na które starczy tego, co w środku; maszyna robi partię za partią także bez gracza i staje, gdy ma 100 gotowych produktów |
| `machine.recipe` | `{ machine, recipe }` | `machine`: ustawia, co maszyna robi; składniki i produkty poprzedniego przepisu wracają do ekwipunku, ogień pali się dalej |
| `machine.load` | `{ machine, item, quantity }` | `machine`: wkłada składnik bieżącego przepisu (do 50 każdego) albo opał (węgiel na 4 partie, drewno na 1; tylko piec piekarski i kuchnia polowa) |
| `machine.take` | `{ machine, what }` | `machine`: wyjmuje `output` (XP za każdą sztukę), `input` (składniki) albo `fuel` (opał) |
| `plot.harvest` | `{ x, y, tileX, tileY }` | `plot.harvested` `{ tileX, tileY, items: [{ id, name, quantity }], xp }`; ścina też posadzone drzewo, gdy urosło |
| `plot.mine` | `{ x, y, mine }` | `plot.mined` `{ mine, items: [{ id, name, quantity }], xp, serverTime }`: jedna jednostka wydobycia kilofem z kopalni `mine` (id z listy `mines` w `plot`) |
| `plot.plantTree` | `{ x, y, tileX, tileY }` | `plot.tree` `{ tree: { tileX, tileY, readyAt }, xp, serverTime }`: sadzi sadzonkę z ekwipunku na wolnym polu |
| `plot.till` | `{ x, y, tileX, tileY }` | `plot.field` `{ field: { tileX, tileY, crop, readyAt }, items, xp, serverTime }`: motyka w ręku zamienia wolne pole żyznej działki w zaorane pole |
| `plot.plant` | `{ x, y, tileX, tileY, crop }` | `plot.field`: zasiew na pustym zaoranym polu |
| `plot.reap` | `{ x, y, tileX, tileY }` | `plot.field` z `items`: zbiór dojrzałej rośliny, pole zostaje zaorane |
| `world.survey` | `{ x, y }` | `world.surveyed` `{ x, y, survey: { oil, gas }, balanceCents }`: płatne badanie geologiczne własnej działki (0 brak, 1 małe, 2 średnie, 3 duże złoże) |
| `station.get` | `{ x, y }` | `station` `{ x, y, items, incoming, outgoing, serverTime, rates }`; pociągi to `{ fromX, fromY, toX, toY, item, name, quantity, arrivesAt }` |
| `station.load` / `station.unload` | `{ x, y, item, quantity }` | `station`: z ekwipunku na stację albo ze stacji do ekwipunku |
| `station.send` | `{ x, y, toX, toY, item, quantity }` | `station`: pociąg jedzie na stację innej kupionej działki (swojej albo innego gracza) |
| `contracts.get` | | `contracts` `{ serverTime, npc, nextNpcAt, board, taken, issued, finished, limits }`, zlecenia `[{ id, item, name, quantity, delivered, rewardCents, xp, deadline, npc, issuer, contractor, mine, delivering, state }]`: `npc` to zlecenia firm dla gracza, `nextNpcAt` chwila nadejścia następnego (albo `null`), `board` otwarte zlecenia innych graczy, `taken` przyjęte przez gracza, `issued` wystawione przez niego (otwarte i zamknięte w ciągu doby), `finished` wykonane przez niego w ciągu doby; `state` to `open`, `taken`, `done`, `expired`, `cancelled` albo `abandoned`. Przy okazji serwer rozlicza zlecenia po terminie |
| `contracts.create` | `{ item, quantity, rewardCents, hours }` | `contracts.done` `{ balanceCents, completed, rewardCents, xp }`; wystawia zlecenie na tablicę, nagroda od razu schodzi z portfela i czeka w zleceniu |
| `contracts.accept` | `{ id }` | `contracts.done`; przyjmuje zlecenie innego gracza, odtąd dostarcza je tylko ten gracz |
| `contracts.deliver` | `{ id, quantity }` | `contracts.done`; oddaje sztuki z ekwipunku; ostatnia kończy zlecenie (`completed`), wypłaca nagrodę i XP |
| `contracts.abandon` | `{ id }` | `contracts.done`; rezygnacja: dostarczone sztuki wracają, zlecenie gracza wraca na tablicę |
| `contracts.cancel` | `{ id }` | `contracts.done`; odwołuje własne zlecenie, którego nikt jeszcze nie przyjął; nagroda wraca |
| `achievements.get` | | `achievements` `{ unlocked, total, groups: [{ name, badges: [{ id, name, description, goal, progress, text, unlockedAt }] }] }`: wszystkie odznaki z postępem (`text` np. „37 / 100”), `unlockedAt` to chwila zdobycia w ms uniksowych albo `null` |
| `achievements.watch` | | `achievements.watching`: od teraz po odpowiedzi, która dała odznakę, serwer wysyła na to połączenie wiadomość bez `id`: `achievement.unlocked` `{ id, group, name, description }` |
| `rankings.get` | `{ ranking }` (opcjonalnie) | `rankings` `{ rankings: [{ id, name }], ranking, top: [{ place, name, value, text, mine }], me: { place, value, text } \| null }`: 10 najlepszych graczy rankingu `money` (najbogatsi), `level` (najwyższy poziom), `produced` (największa produkcja) albo `badges` (najwięcej odznak); równe wyniki dzielą miejsce |

Czasy w `garage` to milisekundy uniksowe według zegara serwera; `xp` to `{ xp, level, leveledUp }` albo `null`.
Podłoga garażu to kratownica `room.width` × `room.depth` pól o boku `room.cellSize` metrów. Mebel zajmuje `width` × `depth` pól (po obrocie o 90° lub 270° na odwrót); `x`, `y` to jego lewe przednie pole. Meble nie mogą wystawać poza podłogę ani nachodzić na siebie.
Kwoty są w centach. `buyCents` to cena, za którą gracz kupuje od handlarza, `sellCents` to cena skupu.

Mapa świata to siatka działek 5 × 5 km w odwzorowaniu równopowierzchniowym Behrmanna (każda działka ma 25 km² na całym globie). Kolumna `x` liczy się od 180° W na wschód, wiersz `y` od bieguna północnego; mapa zawija się ze wschodu na zachód. Biomy mają stałe numery (0 ocean, 1 jezioro, 2 las, 3 żyzne gleby, 4 step i łąki, 5 pustynia, 6 góry, 7 tundra, 8 lodowiec, 9 miasto, 10 wybrzeże, 11 pojezierze). Wody nie można kupić. Cena n-tej działki gracza to 1 000 $, 10 000 $, 100 000 $, 1 000 000 $, a piątej i każdej kolejnej 1 000 000 000 $, razy mnożnik biomu (żyzne gleby, wybrzeże i pojezierze ×1,5, miasto ×2). Zakup daje 500 XP.

Za zakup lasu gracz dostaje siekierę, pustyni łopatę, gór kilof, żyznych gleb motykę (do pustej ręki, a jeśli coś już trzyma, do ekwipunku); pozostałe biomy nie dają narzędzia. Wnętrze działki to 250 × 250 pól po 20 m, generowane zawsze tak samo z położenia działki; serwer zapisuje tylko to, co gracze zebrali. Drzewo ścina się siekierą w 5 s (1 drewno i 80% szans na sadzonkę drzewa), skałę rozbija kilofem (2 kamienie i szansa na węgiel, rudę żelaza lub miedzi), wydmę przekopuje łopatą (3 piasku); skała i wydma to 1,5 s pracy, każde pole daje 2 XP. Wzdłuż północnej krawędzi każdej działki biegną tory ze stacją. Pociąg jedzie 5 s na 100 km (najkrócej 10 s), opłata to 1 $ plus 1 cent za sztukę na każde 100 km.

Każda działka w górach ma od 1 do 5 kopalni (liczba i położenie są stałe dla danej działki, pierwsza stoi niedaleko stacji). Gracz z kilofem w ręku wydobywa w kopalni rudy: 5 s pracy, 2 XP i wynik losowany osobno dla każdego surowca: kamień 99%, węgiel 35%, ruda żelaza 20%, ruda miedzi 20%, ruda cyny 10%, ruda srebra 5%, ruda złota 0,1%. Jedna jednostka daje najwyżej dwie rudy; gdy wypadnie ich więcej, gracz dostaje dwie najrzadsze. Klient kopie dalej sam, dopóki postać stoi przy kopalni. Kopalnia ma 50 jednostek, a 10 minut po wydobyciu ostatniej znów jest pełna. Handlarz skupuje rudę cyny po 25 $, srebra po 60 $, złota po 500 $; wszystkie rudy można też sprzedawać i kupować między graczami.

W garażu od początku stoi stół warsztatowy. Przy stole wybiera się przedmiot i klika *Wytwórz*: składniki znikają od razu, a przedmiot powstaje po czasie z przepisu i trafia do ekwipunku, także gdy postać odejdzie od stołu. Zamówienia wykonują się po kolei, w kolejce może czekać do 5. Przepisy: stół warsztatowy (20 drewna i 5 gwoździ, 30 s, 10 XP), piec kamienny (20 kamienia, 45 s, 15 XP) i 5 gwoździ (1 sztabka żelaza, 10 s, 2 XP). Gwoździe sprzedaje też handlarz po 1 $ (skupuje po 0,25 $). Stół i piec można postawić w garażu albo na wolnym polu własnej działki (jedno pole), więc da się wytwarzać i przetapiać z dala od garażu; oba można też sprzedawać i kupować między graczami, a handlarz skupuje stół po 30 $ i piec po 15 $. Stół warsztatowy można też kupić u handlarza, ale drogo: 500 $.

Piec kamienny pali węgiel i przetapia włożoną rudę na sztabki, sztuka po sztuce, również pod nieobecność gracza: ruda żelaza, miedzi i cyny po 10 s, srebra 15 s, złota 20 s. Jeden węgiel starcza na 5 przetopień. W piecu mieści się do 50 rudy jednego rodzaju i 50 węgla, a gotowe sztabki czekają w nim do wyjęcia (1 XP za sztukę). Handlarz skupuje sztabki żelaza po 10 $, miedzi po 18 $, cyny po 35 $, srebra po 80 $ i złota po 600 $.

Sadzonkę drzewa kupuje się na rynku (u handlarza za 2 $ albo od innych graczy) i sadzi na wolnym polu dowolnej działki (1 XP). Rośnie 10 minut, w lesie o 25% krócej (7,5 min), w mieście o 50% dłużej (15 min), a na lodowcu nic nie wyrośnie. Urośnięte drzewo ścina się siekierą jak każde inne. Handlarz skupuje drewno po 2 $, a sadzonki po 1 $.

Na żyznych glebach motyka orze wolne pola (1,5 s pracy, 1 XP). Na zaoranym polu sieje się jedną z roślin: pszenica 5 min, marchew 7 min, kapusta 8 min, kukurydza 10 min, ziemniaki 15 min, słonecznik 20 min; dojrzałą roślinę zbiera się ręką, a pole zostaje zaorane. Pod każdą działką mogą leżeć złoża ropy i gazu (stałe dla danego miejsca, częstsze na tundrze, pustyni i wybrzeżu), ale nie widać ich na mapie: właściciel działki może zlecić badanie geologiczne za 5 000 $, a wynik widzi tylko on.

Na własnej działce można układać linie produkcyjne. Taśmociąg (4 sztuki z 2 sztabek żelaza i drewna, u handlarza 5 $) przesuwa przedmioty dwoma torami w stronę, w którą jest obrócony, 1,25 pola na sekundę, i przekazuje je na taśmę, w którą celuje (nie czołowo). Taśma zasilana od tyłu albo tylko z jednego boku przenosi oba tory tak, jak są, więc taśmy skręcają; taśma dochodząca z boku do linii zasilanej od tyłu kładzie wszystko na bliższy tor. Po taśmach można chodzić. Rozdzielacz (2 taśmociągi, 4 sztabki żelaza i 2 sztabki miedzi, u handlarza 40 $) bierze przedmioty z taśmy za sobą i oddaje je na taśmy po lewej i prawej stronie, na zmianę; z ustawionym filtrem wybrane przedmioty idą na wybraną stronę, a cała reszta na drugą. Podajnik (2 sztabki żelaza, sztabka miedzi i 5 gwoździ, u handlarza 30 $) bierze po jednym przedmiocie z pola za sobą (z taśmy, z wyjścia pieca lub maszyny, z magazynu) i odkłada na pole przed sobą (na taśmę najpierw na dalszy tor); do pieca czy maszyny bierze tylko to, co ta przyjmie (rudę, węgiel, składniki ustawionego przepisu, opał), a z magazynu z mieszanym towarem bierze po kolei z każdego rodzaju. Jeden obrót ramienia trwa 1,6 s. Magazyny: skrzynia drewniana (8 miejsc po 100 sztuk), skrzynia żelazna (24 miejsca), stos drewna (400 drewna), hałda (1000 kamienia, piasku, węgla albo rudy jednego rodzaju) i silos zbożowy (2000 pszenicy, kukurydzy albo słonecznika). Wszystko to robi się przy stole warsztatowym, stawia klawiszem R obróconym w wybraną stronę, a podnosi z powrotem do ekwipunku z zawartością. Serwer liczy taśmy i podajniki w krokach po 0,2 s za cały czas od ostatniego spojrzenia na działkę, także pod nieobecność gracza; gdy nic się nie rusza, przeskakuje do chwili, w której piec albo maszyna skończy kolejną sztukę, a maszyneria zajęta bez końca (np. pętla taśm) pracuje najwyżej 30 minut na jedno spojrzenie. Nowe maszyny innych modułów włączają się w to, implementując `IMachinePorts`.

Zlecenia (okno *Zlecenia*, klawisz J w garażu): każdy gracz ma naraz 3 zlecenia od firm NPC (np. huta, piekarnia, tartak), każde na inny towar, z nagrodą wyraźnie wyższą od ceny skupu, XP (10 plus 1 za każde 20 $ nagrody, najwyżej 300) i terminem od 4 do 24 godzin. Towar oddaje się z ekwipunku, także po trochu; nagroda przychodzi, gdy dotrze ostatnia sztuka. Po wykonaniu albo rezygnacji następne zlecenie firmy przychodzi po 5 minutach, a po minięciu terminu od razu. Gracze wystawiają zlecenia na tablicę dla innych (1–100 000 sztuk dowolnego przedmiotu, nagroda 0,01–10 000 000 $, termin 1–168 godzin): nagroda czeka w zleceniu, przyjmuje je jeden wykonawca i tylko on dostarcza; za wykonanie dostaje nagrodę i 5 XP, a zleceniodawca towar. Gdy termin minie, dostarczone sztuki wracają do wykonawcy, a nagroda do zleceniodawcy; wykonawca może też zrezygnować wcześniej (zlecenie wraca na tablicę), a zleceniodawca odwołać zlecenie, dopóki nikt go nie przyjął. Gracz wystawia najwyżej 10 zleceń i realizuje najwyżej 5 cudzych naraz.

Osiągnięcia: moduł `Achievements` liczy, co gracz robi (zebrane drewno, jednostki z kopalni, sztabki wyjęte z pieca, przedmioty ze stołu i maszyn, plony, postawione obiekty i taśmy, pociągi, kupione działki, sprzedaż handlarzowi, transakcje z graczami, wykonane zlecenia, najwyższy poziom i najwięcej pieniędzy w portfelu), na podstawie obsłużonych wiadomości (`IMessageObserver`), więc pozostałe moduły nic o nim nie wiedzą. 39 odznak w 9 grupach (Las, Górnictwo, Hutnictwo, Rzemiosło, Rolnictwo, Fabryka, Ziemia, Handel, Postać); „Kolekcjoner” za 20 innych. W grze okno *Osiągnięcia* (klawisz O) pokazuje odznaki z postępem i rankingi, a nowa odznaka wyskakuje u góry ekranu. Inne moduły dokładają własne rankingi, rejestrując `IPlayerRanking`.

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
