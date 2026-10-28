# Factory World 3D (Roblox)

Wersja 3D gry Factory World dla Robloxa, w Luau, jako projekt Rojo. Ten branch (`roblox-3d`) ma własną historię i zawiera
tylko wersję Roblox; gra 2D (Godot + serwer C#) jest na `main`. Nie scalaj tych branchy i nie kopiuj tu plików gry 2D.
Opis etapów, budowy i uruchomienia jest w `README.md`.

## Polecenia

- Testy zasad i sprawdzenie składni wszystkich plików `.luau`: `npm install`, potem `npm test`
- Podgląd 3D i zrzuty do `docs/screenshots`: `npm run preview` (Playwright z Chromium)
- Gra: `rokit install`, `rojo serve`, w Roblox Studio wtyczka Rojo → Connect, F5

## Zasady

- **Serwer decyduje o wszystkim.** Klient wysyła tylko intencje przez `ReplicatedStorage.Remotes` (`Net.Handle`). Serwer sprawdza zakres liczb
  (`Net.Int`, `Net.Item`), własność, odległość, czas przytrzymania i narzędzie, a dropy losuje sam.
- **Wszystko albo nic.** Sprawdzenie i zmiana pieniędzy i przedmiotów bez żadnego `yield` pomiędzy.
- **Pieniądze tylko przez `Wallet`**, w centach, z `reason` w księdze.
- **Id przedmiotów są zapisane w DataStore:** nie zmieniaj istniejących id w `src/shared/Items.luau`; trzymaj je zgodne z `Contracts/Items.cs` na `main`.
- **Symulacja na żądanie** od zapisanego czasu (`Clock.Now()`), bez pętli.
- **Handlarz zawsze płaci mniej, niż sam bierze** (test w `tests/rules_spec.lua`).
- Wygląd obiektów tylko w `src/shared/Models.luau` (lista części); `Services/Build.luau` je buduje, a podgląd rysuje te same dane.
- Kod w części Luau zgodnej ze zwykłą Lua (bez adnotacji typów, `continue`, `+=`, interpolacji), żeby testy działały poza Robloxem.

## Styl

- Kod, komentarze, nazwy i commity po angielsku; kody błędów w `snake_case`, polski tekst błędu w `src/client/Game.luau`.
- Teksty dla gracza i README po polsku.
