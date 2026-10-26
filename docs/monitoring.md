# Monitoring w Grafana Cloud

Kontener `alloy` (Grafana Alloy) wysyła do darmowego Grafana Cloud logi wszystkich kontenerów i metryki: maszyny,
każdego kontenera, PostgreSQL i samego serwera gry. Konfiguracja: [`deploy/alloy/config.alloy`](../deploy/alloy/config.alloy).
Kontener startuje tylko, gdy w `.env` jest `COMPOSE_PROFILES=monitoring`, więc bez Grafany wdrożenie działa jak dotąd.

## Konfiguracja (jednorazowo)

1. Załóż konto na [grafana.com](https://grafana.com) (plan *Free*) i stack, np. `factoryworld` (region EU).
2. Na stronie stacku (*My Account → stack → Details*):
   - *Prometheus → Details*: skopiuj **Remote Write Endpoint** (kończy się na `/api/prom/push`) i **Username / Instance ID**.
   - *Loki → Details*: skopiuj **URL** i **User**. Do adresu dopisz `/loki/api/v1/push`.
3. *Security → Access Policies → Create access policy*, zakres `metrics:write` i `logs:write`, potem *Add token*.
   Token (`glc_...`) jest widoczny tylko raz.
4. Na serwerze dopisz do `~/factory-world/.env` (wzór w [`deploy/.env.example`](../deploy/.env.example)):

   ```bash
   COMPOSE_PROFILES=monitoring
   GRAFANA_CLOUD_PROMETHEUS_URL=https://prometheus-prod-XX-prod-eu-west-2.grafana.net/api/prom/push
   GRAFANA_CLOUD_PROMETHEUS_USER=1234567
   GRAFANA_CLOUD_LOKI_URL=https://logs-prod-XXX.grafana.net/loki/api/v1/push
   GRAFANA_CLOUD_LOKI_USER=1234567
   GRAFANA_CLOUD_TOKEN=glc_...
   ```

5. Plik `alloy/config.alloy` kopiuje na serwer job `deploy` (przy ręcznym wdrożeniu skopiuj `deploy/alloy/` obok
   `docker-compose.yml`). Uruchom: `docker compose pull && docker compose up -d`, sprawdź: `docker compose logs alloy`.

Hasło bazy trafia do adresu połączenia eksportera PostgreSQL, więc nie może zawierać znaków `@ : / ? #`
(hasło z `openssl rand -hex 24` jest w porządku).

## Co trafia do Grafany

| Źródło | Gdzie szukać |
| --- | --- |
| Logi kontenerów | Loki, etykiety `service` (`server`, `db`, `web`, `alloy`), `container`; logi serwera mają też `level` (`info`, `warn`, `fail`, `crit`) |
| Serwer gry (`/metrics`, co 30 s) | `factoryworld_message_duration_seconds` (histogram czasu odpowiedzi według `type`, boty jako `bot ...`), `factoryworld_players_online`, `factoryworld_bots_online`, `process_cpu_seconds_total`, `process_resident_memory_bytes`, `dotnet_gc_heap_bytes`, `dotnet_threadpool_queue_length` |
| Maszyna | `node_*`: CPU, pamięć, dysk, sieć, obciążenie |
| Kontenery | `container_*` według etykiety `container`: CPU, pamięć, sieć, dysk |
| PostgreSQL | `pg_*`: połączenia, transakcje, rozmiar bazy, blokady |

`/metrics` nie jest dostępne z internetu: Caddy przekazuje na zewnątrz tylko `/ws` i `/health`.

Przykładowe zapytania:

```logql
{service="server"} |= "Load in the last minute"
{service="server"} |~ "Slow |Slow logistics"
{service="server", level=~"fail|crit"}
```

```promql
# 95. percentyl czasu odpowiedzi według rodzaju wiadomości
histogram_quantile(0.95, sum by (le, type) (rate(factoryworld_message_duration_seconds_bucket[5m])))
# średni czas odpowiedzi
sum(rate(factoryworld_message_duration_seconds_sum[5m])) / sum(rate(factoryworld_message_duration_seconds_count[5m]))
# CPU kontenerów w rdzeniach
sum by (container) (rate(container_cpu_usage_seconds_total[5m]))
```

## Claude i Grafana

W claude.ai: *Ustawienia → Łączniki (Connectors)*, znajdź **Grafana Cloud**, *Połącz* i zaloguj się kontem Grafana,
na którym jest stack `factoryworld`. Potem Claude w czacie i w projektach może sam czytać logi i metryki z tego stacku.
