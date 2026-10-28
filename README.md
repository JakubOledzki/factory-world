# Factory World 3D (Roblox)

Wersja gry Factory World dla Robloxa, w 3D. To osobna gra napisana od zera w Luau: zasady, ceny, przepisy i czasy
są przeniesione z serwera gry 2D (branch `main`, katalog `server/`), a modele 3D są zbudowane w kodzie z części Robloxa.
Branch `roblox-3d` ma własną historię i zawiera tylko wersję Roblox: nie dzieli plików z grą 2D i nie jest scalany z `main`.

![Plac i działki](docs/screenshots/1-plac-i-dzialki.png)
![Kopanie na działce](docs/screenshots/2-kopanie-na-dzialce.png)
![Budowanie na siatce](docs/screenshots/6-budowanie.png)
![Maszyny i badania](docs/screenshots/7-przetworstwo.png)
![Modele](docs/screenshots/5-modele.png)

Zrzuty pochodzą z podglądu w przeglądarce (`tools/preview/`), który rysuje dokładnie te modele, które buduje serwer
(`src/shared/Models.luau`); w Robloxie oświetlenie, materiały i postacie wyglądają nieco inaczej.

## Etapy

| Etap | Zawartość | Stan |
| --- | --- | --- |
| 1. Rdzeń | Plac z handlarzem i stołem warsztatowym, działka 3D dla każdego gracza (8 na serwer), jedna kopalnia na działkę z poziomem (na razie 1, pod przyszłe ulepszenia; kilof, 5 s, do 2 rud, 50 urobków, 10 min na odnowienie), 8 dzikich sosen (siekiera, 5 s, 1 drewno), piec kamienny (węgiel, 5 wytopów z jednej bryłki, liczy się sam, gdy gracza nie ma), stół warsztatowy (piec z 20 kamieni, gwoździe), ekwipunek, portfel w centach z księgą operacji, zapis postępu w DataStore | gotowe |
| 2. Logistyka | Działka 232 × 232 study z siatką budowania na całości (56 × 56 pól po 4 study; wszystko na działce stoi na jej polach), tryb budowania (stawianie, obracanie, rozbiórka, linie siatki widoczne tylko przy budowaniu), taśmociągi (2 pasy, zakręty, dołączanie z boku, przeciąganie skręca taśmę), podajniki, drewniane skrzynie (8 miejsc po 100 szt.), piec na siatce karmiony podajnikami, drzewa jak w 2D (ścięte znika, 30% na sadzonkę, sadzonka rośnie 10 min), nowe przepisy na stole (taśmociąg ×4, podajnik, skrzynia), gęsty las między działkami i wokół placu (tylko ozdoba, nie da się go ściąć ani w nim budować; ścieżki do bram wolne) | gotowe |
| 3. Przetwórstwo | Maszyny na siatce (2 × 2 pola, odlewnia 3 × 3) z przepisami i czasami z gry 2D: tartak (deski, belki, pellet), warsztat kamieniarski (bloki), kruszarka (piasek, kruszywo rud: 3 z 2 rud, w piecu topi się szybciej), odlewnia na węgiel, drewno albo pellet (brąz, stal, cegły); maszyna robi wsad za wsadem także pod nieobecność gracza, podajniki ją karmią i opróżniają. Badania (jedno naraz, koszt od razu, czas jak w 2D): Gospodarka leśna, Kamieniarstwo, Kruszenie, Metalurgia odblokowują maszyny na stole i u handlarza. Kruszarka działa bez prądu do etapu 5 | gotowe |
| 4. Handel | Rynek między graczami (wszystkie serwery), wydarzenia rynkowe | następny |
| 5. Świat | Prąd, pociągi, spółki, mapa świata, lepsze modele z Blendera | |

## Uruchomienie w Roblox Studio

Potrzebne: konto Roblox, [Roblox Studio](https://create.roblox.com/) i [Rokit](https://github.com/rojo-rbx/rokit) (instaluje Rojo).

1. W głównym katalogu repozytorium (na branchu `roblox-3d`): `rokit install`, potem `rojo serve`.
2. W Studio zainstaluj wtyczkę Rojo (*Plugins → Manage Plugins* albo `rojo plugin install`), utwórz nowe miejsce (*Baseplate*),
   usuń z niego `Baseplate` i w panelu Rojo kliknij *Connect*. Kod pojawi się w `ReplicatedStorage`, `ServerScriptService` i `StarterPlayer`.
3. *Play* (F5). Bez publikacji gra działa, ale postęp nie zapisuje się (w oknie Output pojawi się ostrzeżenie `[Data]`).
4. Zapis postępu: opublikuj miejsce (*File → Publish to Roblox*) i włącz *Game Settings → Security → Enable Studio Access to API Services*.
5. W *Game Settings → Places* ustaw maksymalnie 8 graczy na serwer (tyle jest działek).
6. Test wielu graczy: *Test → Clients and Servers → 2 Players → Start*.

Zbudowanie pliku miejsca bez Studio: `rojo build -o FactoryWorld3D.rbxl`.

## Sterowanie

Chodzenie jak w każdej grze Roblox. **E** (przytrzymaj) przy kopalni kopie, przy drzewie ścina, przy handlarzu, stole i piecu otwiera okno.
**I** otwiera ekwipunek: kratka 20 pól jak w grze 2D (przeciągnij, aby przenieść). W oknach skrzyni, pieca i maszyny kliknięcie pola w kratce ekwipunku wkłada cały stos (Shift: połowę), a kliknięcie pola skrzyni go wyjmuje. Nowy gracz dostaje kilof, siekierę i 50 $. Ceny skupu i sprzedaży są takie jak w grze 2D.

**B** (albo przycisk *Budowanie*) włącza tryb budowania na siatce działki: **1–9** wybiera taśmociąg, podajnik,
skrzynię, piec, sadzonkę albo maszynę (maszyny widać na pasku, gdy ma się którąś w ekwipunku), **R** obraca, kliknięcie stawia (przeciągnięcie układa taśmę, która skręca razem z ruchem),
**X** to rozbiórka (kliknięta rzecz wraca do ekwipunku razem z zawartością). Drzewa ścina się siekierą (przytrzymaj **E**). Podajnik bierze z pola za sobą (taśma, skrzynia, sztabki z pieca) i kładzie na
pole przed sobą. Skrzynię, piec i maszynę otwiera **E**; w oknie maszyny wybiera się, co ma robić, i wkłada składniki.
**T** (albo przycisk *Badania*) otwiera badania. W Studio badania trwają najwyżej 10 s, żeby szybciej testować.

## Jak to jest zbudowane

| Miejsce | Zawartość |
| --- | --- |
| `src/shared/` (`ReplicatedStorage.Shared`) | Czyste zasady gry bez API Robloxa: `Items` (id jak w `Contracts/Items.cs`, nazwy, kolory), `Prices`, `Mining`, `Forestry`, `Smelting`, `Processing` (maszyny przetwórcze, jak `Processing.cs`), `Research` (drzewko badań, jak `Research.cs`), `Workshop`, `Logistics` (siatka, taśmy, podajniki, skrzynie, porty maszyn, jak `Simulation.cs`), `PlotLayout`, `Money`, `Remotes`, `Assemble` (składa model z części, dla serwera i ducha budowania u klienta), a także `Models`: każdy obiekt (kopalnia, sosna, piec, maszyny, stół, stragan, handlarz, fontanna, płot, ozdoby działki) jako lista części z kształtem (kula, walec, klin, prostopadłościan), materiałem, kolorem i efektami (ogień, dym, światło) |
| `src/server/` (`ServerScriptService.Server`) | `Main` uruchamia usługi z `Services/`: `Data` (DataStore z blokadą sesji i autozapisem), `Wallet`, `Inventory`, `Net` (zdalne wywołania, limit 20 na sekundę, sprawdzanie danych), `World` (plac i las), `Plots` (działki, kopanie), `Furnaces`, `Factory` (liczy siatkę do teraz), `Grid` (budowanie, ścinanie i sadzenie drzew, skrzynie, stan taśm i ramion dla klienta), `Machines` (okno maszyny), `Lab` (badania), `Merchant`, `Workshop`, `Build` (zamienia `Models` w części Robloxa) |
| `src/client/` (`StarterPlayerScripts.Client`) | `Main`, `Game` (stan gracza, wywołania serwera, polskie teksty błędów), `GridView` (płynny ruch taśm i ramion podajników, kręcące się piły i walce maszyn), `Ui/` (HUD, `ItemGrid` (kratka przedmiotów z obrazkami z kształtów), ekwipunek, handlarz, piec, stół, skrzynia, maszyna, badania, pasek budowania) |
| `tests/` | Testy zasad z `src/shared` i sprawdzenie składni wszystkich plików: `npm install`, potem `npm test` (Lua 5.3 w Node, bez Robloxa) |
| `tools/preview/` | Podgląd 3D w przeglądarce (three.js): `scene.js` uruchamia `Models.luau` i `PlotLayout.luau` w Node i składa z nich plac i działki tak jak serwer, a potem robi zrzuty do `docs/screenshots` (`npm run preview`, wymaga Chromium z Playwright) |

Zasady z gry 2D obowiązują też tutaj:

- **Serwer decyduje o wszystkim.** Klient wysyła tylko intencje (`ReplicatedStorage.Remotes`). Serwer sprawdza zakres liczb, własność pieca i działki,
  odległość gracza, czas przytrzymania przycisku i posiadane narzędzie, a dropy losuje sam (`Random` serwera podany do czystej funkcji).
- **Wszystko albo nic.** Zmiana pieniędzy i przedmiotów w jednej operacji dzieje się bez żadnego `yield` między sprawdzeniem a zmianą, więc żadne inne żądanie nie wejdzie pomiędzy.
- **Pieniądze tylko przez `Wallet`**, w centach, każda zmiana z `reason` w księdze gracza (200 ostatnich wpisów).
- **Id przedmiotów trafiają do DataStore:** nie zmieniaj istniejących id w `src/shared/Items.luau`.
- **Symulacja na żądanie:** piec, kopalnie, drzewa, stół i siatka liczą stan od zapisanego czasu (`Clock.Now()`, czas Unix), gdy ktoś na nie spojrzy.
  Siatka idzie krokami po 0,2 s, najwyżej 30 minut pracy bez przerwy na jedno nadrabianie (jak w grze 2D); póki właściciel jest na serwerze, jest odświeżana co krok tylko po to, żeby było widać ruch.
- **Handlarz zawsze płaci mniej, niż sam bierze** (sprawdza to test).

Kod pisany jest w części Luau zgodnej ze zwykłą Lua (bez adnotacji typów, `continue` i `+=`), żeby testy i sprawdzenie składni działały poza Robloxem.

## Do decyzji

- Pieniądze na start (`Prices.StartingCents`, teraz 50 $) i narzędzia startowe (teraz kilof i siekiera).
- Czy na Robloxie ma być jeden wspólny świat działek (mapa Ziemi z gry 2D), czy działki tylko na czas pobytu na serwerze, jak teraz.
