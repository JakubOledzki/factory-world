---
name: balans
description: Liczy balans ekonomii Factory World z prawdziwych danych w kodzie serwera: zarobek na minutę i godzinę przepisów i maszyn, opłacalność łańcuchów produkcji, czas do celów (pierwsza działka, kolejne działki, poziomy), źródła i ujścia waluty. Użyj przy "sprawdź balans", "czy to się opłaca", "ile zarobi gracz", "za tanie/za drogie", przy zmianie cen, przepisów, czasów, krzywej XP albo cen działek.
---

# Balans

Liczby bierz zawsze z kodu, nie z pamięci ani z dokumentu projektowego: gra zmienia się szybko, a dokument bywa starszy niż kod.

## 1. Skąd brać dane

| Co | Gdzie |
| --- | --- |
| Przepisy stołu i kowadła (wynik, ilość, czas, składniki, XP, stacja) | `server/src/Modules/FactoryWorld.Modules.Crafting/Crafting.cs`, `Recipes` |
| Maszyny przetwórcze, piece, stołówki | `Processing.cs`, `Furnace.cs`, `Canteen.cs` w tym samym module |
| Skup i sprzedaż handlarza (w centach) | `server/src/Modules/FactoryWorld.Modules.Market/MarketModule.cs`, `NpcPrices.Buys`, `OwnSells`, `Markup` |
| Wydarzenia rynkowe i dzienne wahania cen | `MarketEvents.cs` |
| Badania (koszt, czas, XP, co odblokowują) | `server/src/Modules/FactoryWorld.Modules.Research/Research.cs` |
| Krzywa XP i poziomy | moduł `Characters` (`Handlers.cs`, szukaj `levelXp` / `nextLevelXp`) |
| Ceny działek (`PlotPrices.TierCents`), biomy (`PriceFactor`) | moduł `World`: `WorldMap.cs`, a mnożnik miast w `Cities.cs` (`PlotPriceFactorAsync`) |
| Opłaty kolejowe, eksport, banki | moduł `World`: `Railway.cs`, `Export.cs`, `Banking.cs` |
| Ulepszenia garażu, segregacja | moduł `Recycling` (`GarageUpgrades.cs`) |
| Zlecenia NPC | `server/src/Modules/FactoryWorld.Modules.Contracts/NpcContracts.cs` |
| Premie (ubrania, posiłki, stołówka, prąd) | `Items.cs` (`Garment`, `Meal`), `Canteen.cs`, moduł `Power` |

Gdy dane są rozrzucone w kodzie, napisz krótki skrypt w Pythonie w katalogu tymczasowym (poza repozytorium), który je wyciąga i liczy, zamiast przepisywać liczby ręcznie. Pokaż, z których plików i linii je wziął.

## 2. Co policzyć

Dla każdego przepisu lub maszyny, której dotyczy pytanie:

- **wartość wejścia** = suma (ilość składnika × cena skupu handlarza), bo tyle gracz traci, nie sprzedając składników;
- **wartość wyjścia** = ilość × cena skupu produktu;
- **marża na partię** i **marża na minutę** = (wyjście − wejście) / czas partii, z szybkością maszyny (prąd, poziom) i premiami, jeśli pytanie ich dotyczy;
- **XP na minutę**;
- porównanie z innymi przepisami tej samej gałęzi i poziomu (tabela, posortowana po marży na minutę).

Dla łańcucha (np. ruda → sztabka → gwoździe → skrzynia): marża każdego kroku i całości, liczba maszyn każdego rodzaju potrzebna do równej przepustowości, wąskie gardło.

Dla celów gracza: czas do pierwszej działki i kolejnych progów cen działek, do poziomów z krzywej XP, przy (a) ręcznej pracy w garażu, (b) typowej wczesnej automatyzacji, (c) pełnej fabryce.

## 3. Czerwone flagi

Zgłoś każdą z nich osobno:

- **Pętla zysku u handlarza**: kup u handlarza → przetwórz → sprzedaj handlarzowi z zyskiem. Handlarz musi zawsze płacić mniej, niż bierze, także w najlepszym wydarzeniu rynkowym i z najwyższymi premiami.
- **Przepis wyższego poziomu zarabia mniej na minutę** niż niższy z tej samej gałęzi (nie ma po co go badać).
- **Przepis z ujemną marżą**, który nie jest pośrednim krokiem do czegoś droższego.
- **Źródło waluty bez limitu** (skup, zlecenia, eksport), które przy pełnej automatyzacji daje rząd wielkości więcej niż reszta gry.
- **Skok wymagań**: cel (działka, poziom, badanie), na który przy danym etapie trzeba czekać wielokrotnie dłużej niż na poprzedni.
- **Ominięty łańcuch**: tańsza droga do tego samego produktu.

## 4. Wynik

Po polsku, liczby w dolarach (centy / 100) z separatorem tysięcy:

1. Jedno-dwa zdania odpowiedzi na pytanie.
2. Tabela lub tabele z wyliczeniami.
3. Czerwone flagi z proponowaną zmianą (konkretna liczba w konkretnym pliku) i jej skutkiem przeliczonym tak samo.
4. Założenia (np. "bez premii z ubrań", "ceny bez wydarzenia rynkowego").

Przy więcej niż kilku liczbach do porównania zrób wykres (skill `dataviz`). Nie zmieniaj liczb w kodzie bez zgody gracza; po zgodzie zmiana idzie jak każda inna (testy, changelog), a ceny i przepisy zgodnie ze skillem `nowa-zawartosc`.
