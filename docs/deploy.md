# Wdrożenie na serwer Linux

Gra działa na serwerze jako trzy kontenery Docker:

| Kontener | Rola |
| --- | --- |
| `web` | Caddy: serwuje grę w przeglądarce, sam załatwia certyfikat HTTPS, przekazuje `/ws` do serwera gry |
| `server` | Serwer gry .NET |
| `db` | PostgreSQL |

Obrazy `web` i `server` buduje GitHub Actions (`.github/workflows/release.yml`) przy każdym pushu na `main`
i publikuje w GitHub Container Registry (`ghcr.io/jakuboledzki/...`). Na serwerze nic się nie kompiluje.
Po skonfigurowaniu sekretów ten sam workflow sam wdraża nową wersję na serwer (zobacz *Automatyczne wdrażanie po merge'u*).

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

## Automatyczne wdrażanie po merge'u

Po każdym merge'u do `main` workflow *Release images* buduje obrazy, a potem job `deploy` łączy się z serwerem
przez SSH, kopiuje aktualny `deploy/docker-compose.yml`, robi `docker compose pull && docker compose up -d`
i czeka, aż serwer gry odpowie `Healthy`. Dopóki sekrety poniżej nie są ustawione, job `deploy` jest pomijany.

### Jednorazowa konfiguracja

1. **Klucz SSH tylko do wdrożeń.** Na własnym komputerze (nie na serwerze):

   ```bash
   ssh-keygen -t ed25519 -N "" -C "github-deploy" -f factory-world-deploy
   ```

   Powstaną dwa pliki: `factory-world-deploy` (prywatny) i `factory-world-deploy.pub` (publiczny).

2. **Klucz publiczny na serwer.** Dopisz zawartość `factory-world-deploy.pub` do `~/.ssh/authorized_keys`
   użytkownika, który uruchamia Dockera (ten z kroku 1, należący do grupy `docker`):

   ```bash
   ssh-copy-id -i factory-world-deploy.pub uzytkownik@adres-serwera
   ```

3. **Odcisk serwera** (zabezpiecza przed podszyciem się pod serwer). Na własnym komputerze:

   ```bash
   ssh-keyscan adres-serwera
   ```

4. **Sekrety w GitHubie.** W repozytorium: *Settings → Secrets and variables → Actions → New repository secret*:

   | Sekret | Wartość | Wymagany |
   | --- | --- | --- |
   | `DEPLOY_HOST` | adres IP lub domena serwera | tak |
   | `DEPLOY_USER` | użytkownik SSH na serwerze | tak |
   | `DEPLOY_SSH_KEY` | cała zawartość pliku `factory-world-deploy` (klucz prywatny) | tak |
   | `DEPLOY_KNOWN_HOSTS` | wynik `ssh-keyscan` z kroku 3 | zalecany |
   | `DEPLOY_PORT` | port SSH, domyślnie `22` | nie |
   | `DEPLOY_PATH` | katalog z `docker-compose.yml` i `.env`, domyślnie `factory-world` (w katalogu domowym) | nie |

   Bez `DEPLOY_KNOWN_HOSTS` workflow pobiera odcisk serwera przy każdym wdrożeniu, co działa, ale nie chroni
   przed podszyciem się pod serwer.

5. **Dostęp do obrazów.** Serwer musi móc pobrać obrazy z GHCR (krok 2 wyżej: obrazy publiczne albo
   `docker login ghcr.io` na serwerze).

6. Po ustawieniu sekretów uruchom wdrożenie ręcznie: *Actions → Release images → Run workflow*. Plik
   prywatny `factory-world-deploy` możesz potem usunąć z komputera.

Plik `.env` zostaje na serwerze i workflow go nie zmienia.

### Ręczna aktualizacja i powrót do starszej wersji

Ręcznie wdrożysz najnowszą wersję tak:

```bash
cd ~/factory-world
docker compose pull && docker compose up -d
```

Konkretną wersję uruchomisz, ustawiając w `.env` `TAG=<sha commita>`, co pozwala też wrócić do poprzedniej wersji.
Dopóki `TAG` wskazuje konkretny commit, automatyczne wdrożenia nie zmieniają wersji gry; przywróć `TAG=latest`,
żeby znów szły same.

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
- **Job `deploy` kończy się `Permission denied (publickey)`:** klucz publiczny nie trafił do `authorized_keys`
  użytkownika `DEPLOY_USER` albo `DEPLOY_SSH_KEY` nie zawiera całego klucza prywatnego (z liniami `BEGIN` i `END`).
- **Job `deploy` kończy się `permission denied ... docker.sock`:** `DEPLOY_USER` nie należy do grupy `docker`.
