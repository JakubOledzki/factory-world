# Test obciążenia serwera

Boty grają przez prawdziwy protokół gry (WebSocket, te same wiadomości co klient): łączą się, logują,
ładują postać, garaż, ekwipunek, portfel i ceny, a potem co `--think` ms (średnio, ±50%) wykonują jedną akcję:

| Akcja | Udział |
| --- | --- |
| `ping` | 15% |
| `inventory.get`, `inventory.move` | 12%, 6% |
| `garage.get`, `recycling.sort` | 10%, 6% |
| `wallet.get` | 8% |
| `market.prices`, `market.overview`, `market.item`, `market.mine`, `market.sell` | 4%, 5%, 8%, 3%, 4% |
| `world.area`, `world.plot` | 8%, 6% |
| `crafting.get` | 5% |

Chodzenie postacią liczy tylko klient, więc nie obciąża serwera i nie ma go w teście.
Odmowy wynikające z zasad gry (np. pełna kolejka segregacji) to zwykłe odpowiedzi; błędem jest
przekroczenie czasu, zerwane połączenie albo `internal`.

## Uruchomienie

Wymagany .NET 10 SDK i Python 3 (do raportu).

```bash
# 10, 100, 1000 i 10000 graczy na lokalnym serwerze, potem raport results/report.html
tools/loadtest/run.sh

# inny serwer, inne poziomy, CPU i RAM serwera (gdy działa na tej samej maszynie co boty)
URL=wss://gra.example.com/ws LEVELS="100 1000 5000" tools/loadtest/run.sh
SERVER_PID=$(pgrep -f FactoryWorld.Server.dll) tools/loadtest/run.sh

# fala logowań hasłem zamiast tokenu z urządzenia
LOGIN=password LEVELS="100 1000" tools/loadtest/run.sh
```

Jeden poziom ręcznie:

```bash
cd tools/loadtest
dotnet run -c Release -- --url ws://127.0.0.1:5080/ws --players 1000 --ramp 10 --duration 60 --think 2000
```

| Opcja | Domyślnie | Znaczenie |
| --- | --- | --- |
| `--url` | `ws://127.0.0.1:5080/ws` | adres WebSocket serwera |
| `--players` | 10 | liczba graczy jednocześnie |
| `--ramp` | 10 | w ciągu ilu sekund dołączają |
| `--duration` | 60 | ile sekund grają po dołączeniu (tylko ta faza liczy się do czasów odpowiedzi) |
| `--think` | 2000 | średni odstęp między akcjami jednego gracza (ms) |
| `--login` | `token` | `token` (`auth.resume`, jak klient z zapisanym logowaniem) albo `password` (`auth.login`) |
| `--timeout` | 15 | po ilu sekundach brak odpowiedzi liczy się jako błąd |
| `--accounts` | `loadtest-accounts.tsv` | plik z kontami botów; brakujące konta są zakładane przy pierwszym uruchomieniu |
| `--register-concurrency` | 8 | ile kont zakładać naraz |
| `--server-pid` | | PID serwera: zapisuje jego CPU, RAM i liczbę wątków, a także CPU PostgreSQL (tylko Linux, ta sama maszyna) |
| `--out` | `results/<gracze>.json` | plik z wynikami |
| `--prepare-only` | | tylko załóż konta |

Konta botów (`loadbot<N>@loadtest.local`, postać `lb<N>`) zostają w bazie. Nie uruchamiaj testu na bazie
z prawdziwymi graczami bez zgody: boty zajmują nazwy postaci i dodają wiersze do tabel.

## Wyniki

Każdy przebieg zapisuje JSON: podsumowanie (p50/p95/p99 czasu odpowiedzi, przepustowość obsłużona i zadana,
błędy, ping, czas wejścia do gry, CPU i RAM), czasy każdej akcji osobno i przebieg sekunda po sekundzie.
`report.py` składa je w jedną stronę z wykresami:

```bash
python3 report.py results/*.json > results/report.html
python3 report.py --before stare/*.json -- results/*.json > porownanie.html
```

Żeby wynik mówił o serwerze, a nie o maszynie z botami, uruchamiaj boty na innym komputerze niż serwer
(10 000 botów zajmuje około pół rdzenia). Gdy maszyna jest zajęta w ponad 85%, raport oznacza wynik gwiazdką.
