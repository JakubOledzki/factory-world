---
name: audyt-ekonomii
description: Sprawdza zmianę w serwerze Factory World pod kątem dublowania lub gubienia pieniędzy i przedmiotów, oszukiwania przez klienta i dziur w ekonomii. Użyj przed commitem lub PR-em, gdy zmiana dotyka portfela, ekwipunku, rynku, handlarza, zleceń, spółek, banków, pociągów, eksportu, maszyn wydających produkty albo nagród (XP, dropy). Także na prośbę "audyt ekonomii", "czy to da się oszukać", "sprawdź transakcje".
---

# Audyt ekonomii

Najgroźniejsze błędy w tej grze to pieniądze lub przedmioty, które powstają z niczego albo znikają. Ten audyt przechodzi każdą ścieżkę w zmianie, która je przenosi, i sprawdza ją według zasad poniżej.

## 1. Zbierz zakres

- `git diff main...HEAD -- server/` (albo niezatwierdzone zmiany: `git diff -- server/`).
- Wypisz każdą metodę w diffie, która woła `IWallet.CreditAsync` / `DebitAsync`, `IInventory.AddAsync` / `ReceiveAsync` / `RemoveAsync`, zapisuje zawartość maszyn, magazynów, stacji, skrzyń, ofert rynku, kont banków lub kasy spółek, albo przyznaje XP.
- Dla każdej takiej metody znajdź handler (`IMessageHandler`), z którego gracz ją wywołuje, i payload, który kontroluje.

## 2. Sprawdź każdą ścieżkę

Zapisz przy każdej ścieżce, które punkty przechodzi, a które nie.

1. **Wszystko albo nic.** Pobranie i wydanie (pieniądze za towar, składniki za produkt, towar ze skrzyni do pociągu) dzieje się w jednym `GameDb.InTransactionAsync`. Wzór: `MarketService.BuyAsync` i `SellAsync` w `FactoryWorld.Modules.Market/MarketModule.cs`. Wyjątek po pobraniu i przed wydaniem musi wycofać całość.
2. **Najpierw zabierz, potem daj.** Zabranie (`DebitAsync`, `RemoveAsync`) sprawdza stan w tym samym zapytaniu, które go zmienia (`... WHERE balance_cents >= @cents RETURNING`), a nie osobnym odczytem wcześniej. Odczyt, a potem zapis bez blokady (`FOR UPDATE`, warunek w `UPDATE`, `ON CONFLICT`) to wyścig: dwa szybkie żądania wydadzą to samo dwa razy.
3. **Powtórzone żądanie.** Co się stanie, gdy klient wyśle tę samą wiadomość dwa razy pod rząd albo z dwóch połączeń? Szczególnie: odbiór nagrody, wyjęcie z maszyny (`take`), wypełnienie zlecenia, odbiór pociągu, zakończenie badania. Stan "już odebrane" musi być zapisany w tej samej transakcji co wydanie.
4. **Liczby od klienta.** Każda ilość i cena z payloadu ma sprawdzony zakres (> 0, górna granica jak w `market.list`: 1–10 000 sztuk, 0,01–1 000 000 $). Szukaj: ujemnych ilości, zera, `long` przekraczającego zakres przy mnożeniu `cena × ilość`, ułamków zaokrąglanych na korzyść gracza (prowizje i premie procentowe liczone `* (100 + x) / 100` zaokrąglają w dół; sprawdź, kto na tym zyskuje).
5. **Czyje to jest.** Każde `id`, `x, y` i `owner` z payloadu jest sprawdzane względem `client.RequireAccount()`: własna działka albo prawa spółki (`ICompanyPlots.RightsAsync`), własna oferta, własna maszyna. Działka publiczna daje tylko `visit`.
6. **Księga.** Pieniądze zmieniają się tylko przez `IWallet` (każda zmiana to wpis w `wallet.ledger` z czytelnym `reason`). Żadnego bezpośredniego `UPDATE wallet.wallets` z innego modułu. Kasa spółki i konta banków: to samo, przez ich własne serwisy.
7. **Granice modułów.** Moduł nie czyta ani nie pisze cudzych tabel (cudzego schematu w SQL). Potrzebuje czegoś z innego modułu, to woła jego interfejs z `FactoryWorld.Modules.Abstractions/Contracts/Services.cs`.
8. **Losowanie i czas na serwerze.** Dropy losuje serwer (`Random.Shared.Next(...)` przekazany do czystej funkcji, jak w `Mining.cs`, `PlotInterior.cs`). Czas pochodzi z `TimeProvider`, nigdy z payloadu. Klient nie może wybrać wyniku ani przyspieszyć produkcji.
9. **Doganianie czasu.** Symulacja liczona od `simulatedAt` / `startedAt` nie może wydać produktu dwa razy: po wydaniu znacznik czasu przesuwa się w tej samej transakcji. Sprawdź też limit doganiania (taśmy: 30 minut naraz) i co się dzieje, gdy zegar serwera stoi w testach.
10. **Źródła i ujścia waluty.** Czy zmiana dodaje nowe źródło pieniędzy (skup, nagroda, zlecenie NPC, odsetki)? Policz, ile da na godzinę przy pełnej automatyzacji i czy jest ograniczone (malejący zwrot, limit, cena wejścia). Nowe źródło bez ujścia to inflacja. Do dokładniejszego liczenia użyj skilla `balans`.
11. **Handlarz.** Handlarz zawsze płaci mniej, niż sam bierze za ten sam towar, także po wydarzeniach rynkowych (`MarketEvents`, ±10% zmian dziennych) i po premiach z ubrań i certyfikatu lasu. Kup u handlarza → przetwórz → sprzedaj handlarzowi nie może dawać zysku bez pracy lub czasu.

## 3. Sprawdź testy

- Dla każdej ścieżki z punktów 1–5 powinien być test w `server/tests/FactoryWorld.Server.Tests/` (styl: `PlayerMarketTests.cs`, `CraftingTests.cs`; nazwy testów to zdania po angielsku z podkreślnikami). Brakuje testu na "za mało pieniędzy", "cudza działka" albo "dwa razy to samo żądanie"? Zaproponuj go, z nazwą i treścią.
- Testy wymagają PostgreSQL: `docker compose up db`, potem `cd server && dotnet test`. Uruchom je, jeśli baza działa; jeśli nie, napisz, że nie zostały uruchomione.

## 4. Raport

Po polsku, od najgroźniejszego:

- **Błąd** (da się zdublować lub zgubić pieniądze/przedmioty, albo oszukać): plik:linia, scenariusz krok po kroku (jakie wiadomości wysłać), poprawka.
- **Ryzyko** (zależy od wyścigu, kolejności lub balansu): to samo, z oceną, jak łatwo to wywołać.
- **Brakujące testy**.
- Ścieżki, które przeszły wszystko, jednym zdaniem każda.

Nie poprawiaj kodu bez prośby. Na koniec zapytaj, czy naprawić znalezione błędy.
