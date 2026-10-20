# Wdrożenie na serwer Linux

Gra działa na serwerze jako trzy kontenery Docker:

| Kontener | Rola |
| --- | --- |
| `web` | Caddy: serwuje grę w przeglądarce, sam załatwia certyfikat HTTPS, przekazuje `/ws` do serwera gry |
| `server` | Serwer gry .NET |
| `db` | PostgreSQL |

Obrazy `web` i `server` buduje GitHub Actions (`.github/workflows/release.yml`) przy każdym pushu na `main`
i publikuje w GitHub Container Registry (`ghcr.io/jakuboledzki/...`). Na serwerze nic się nie kompiluje.

## Czego potrzebujesz

- Serwer VPS z Ubuntu 24.04: 2 vCPU, 4 GB RAM (minimum 2 GB), 40 GB SSD, publiczny IPv4, np. Hetzner, OVH, DigitalOcean.
- Domenę lub subdomenę, np. `gra.twojadomena.pl`, z rekordem **A** wskazującym na adres IP serwera.
- Dostęp SSH do serwera.

## 1. Przygotuj serwer (jednorazowo)

Zaloguj się przez SSH i zainstaluj Dockera:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER   # potem wyloguj się i zaloguj ponownie
```

Otwórz w zaporze tylko SSH, HTTP i HTTPS:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80
sudo ufw allow 443
sudo ufw enable
```

## 2. Dostęp do obrazów

Obrazy w GHCR są domyślnie prywatne. Wybierz jedno:

- **Prościej:** na GitHubie wejdź w *Twój profil → Packages → factory-world-server → Package settings → Change visibility → Public*, to samo dla `factory-world-web`.
- **Prywatnie:** utwórz token na GitHubie (*Settings → Developer settings → Personal access tokens → Tokens (classic)*, uprawnienie `read:packages`) i na serwerze:

  ```bash
  echo TWOJ_TOKEN | docker login ghcr.io -u JakubOledzki --password-stdin
  ```

Pakiety pojawią się po pierwszym udanym przebiegu workflow *Release images* (zakładka *Actions* w repozytorium).

## 3. Konfiguracja

Na serwerze utwórz katalog i skopiuj do niego dwa pliki z repozytorium:

```bash
mkdir -p ~/factory-world && cd ~/factory-world
curl -fsSLO https://raw.githubusercontent.com/JakubOledzki/factory-world/main/deploy/docker-compose.yml
curl -fsSL -o .env https://raw.githubusercontent.com/JakubOledzki/factory-world/main/deploy/.env.example
```

Jeśli repozytorium jest prywatne, skopiuj te pliki przez `scp` z własnego komputera.

Uzupełnij `.env`:

```bash
nano .env
```

- `DOMAIN`: Twoja domena, np. `gra.twojadomena.pl`
- `POSTGRES_PASSWORD`: długie losowe hasło, np. wynik `openssl rand -hex 24`

## 4. Uruchomienie

```bash
docker compose pull
docker compose up -d
```

Po minucie gra jest pod `https://gra.twojadomena.pl`. Sprawdzenie:

```bash
curl https://gra.twojadomena.pl/health   # powinno zwrócić: Healthy
docker compose logs -f server           # logi serwera gry
```

## Aktualizacja do nowej wersji

Po każdym merge'u do `main` GitHub buduje nowe obrazy (ok. 5 minut). Na serwerze:

```bash
cd ~/factory-world
docker compose pull && docker compose up -d
```

Konkretną wersję uruchomisz, ustawiając w `.env` `TAG=<sha commita>`, co pozwala też wrócić do poprzedniej wersji.

## Kopie zapasowe bazy

Codzienny zrzut bazy o 3:00 (`crontab -e`):

```cron
0 3 * * * cd ~/factory-world && docker compose exec -T db pg_dump -U factory factory_world | gzip > ~/backup-$(date +\%F).sql.gz && find ~ -name 'backup-*.sql.gz' -mtime +14 -delete
```

Zrzuty warto też kopiować poza serwer (np. do magazynu obiektowego dostawcy VPS).

## Częste problemy

- **Brak certyfikatu HTTPS:** rekord A domeny musi już wskazywać na serwer, a porty 80 i 443 muszą być otwarte. Logi: `docker compose logs web`.
- **`/health` zwraca `Unhealthy`:** serwer nie łączy się z bazą; sprawdź `POSTGRES_PASSWORD` i `docker compose logs db`. Hasło bazy ustala się przy pierwszym starcie; zmiana w `.env` później wymaga zmiany hasła także w samej bazie.
- **`docker compose pull` odmawia dostępu:** obrazy są prywatne, zobacz krok 2.
