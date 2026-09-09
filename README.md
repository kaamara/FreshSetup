# FreshSetup

Aplikacja z prostym GUI do szybkiej konfiguracji świeżo zainstalowanego Windows 11:

- **Aplikacje (winget)** – Brave, Steam, Discord, PyCharm, Git, Visual Studio Code, Docker Desktop, IntelliJ IDEA, Claude, Spotify, FACEIT Anti-Cheat, Python 3.14 (+ opcjonalnie Claude Code, klient FACEIT, Python Install Manager).
- **Ustawienia Windows** – prywatność, menu Start, pasek zadań, motyw ciemny, akceleracja myszy, klawisze trwałe, plan zasilania. Pozycje zaznaczone domyślnie odpowiadają ustawieniom wyłączonym na komputerze wzorcowym.
- **Brave** – ustawienie jako domyślna przeglądarka, polityki prywatności (P3A, ping statystyk, metryki, Web Discovery, Rewards, Wallet, VPN, Leo, News, Talk…), import zakładek z pliku.
- **Pliki i zakładki** – dowolne pliki, foldery i linki, które mają trafić na nowy komputer w wybrane miejsce (Pulpit, Dokumenty, `%APPDATA%`, `D:\Gry`…), oraz plik zakładek do Brave.
- **Podzespoły** (panel po prawej) – spis sprzętu zbierany przez CIM/WMI w PowerShellu: procesor (rdzenie, taktowanie, cache), RAM (moduły, typ DDR, MHz faktyczne i nominalne, sloty), karty graficzne (VRAM, sterownik, tryb), płyta główna i BIOS, dyski fizyczne i woluminy, zasilanie (bateria, plan; zasilacza ATX nie da się odczytać programowo), monitory, karty sieciowe, urządzenia audio. Przyciski **Odśwież / Kopiuj / Zapisz…**.

Wszystko wykonuje się jednym kliknięciem **Start**. Bez zewnętrznych zależności – czysty PowerShell 5.1 + WinForms, działa na świeżym Windows 11.

## Jak używać

### 1. Przygotowanie (na obecnym komputerze)

1. Uruchom `FreshSetup.bat` (poprosi o uprawnienia administratora).
2. W kolumnie **Pliki i zakładki**:
   - `+ Plik` / `+ Folder` – wybierz, co ma zostać skopiowane, i wskaż miejsce docelowe. Kopia trafia do `payload\files\`.
   - `+ Link` – adres URL pliku, który ma zostać pobrany na nowym komputerze.
   - `Wybierz…` przy zakładkach – wskaż eksport zakładek z Brave (`brave://bookmarks` → ⋮ → **Eksportuj zakładki**, plik `.html`) albo plik `Bookmarks` z profilu (`%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\Default\Bookmarks`).
3. Zamknij aplikację. Cały folder `FreshSetup` (z `payload\`) skopiuj na pendrive / do chmury.

### 2. Na nowym komputerze

1. Skopiuj folder `FreshSetup` na dysk i uruchom `FreshSetup.bat`.
2. Zaznacz/odznacz pozycje (linki „wszystko / nic / domyślne” pod każdą listą; klik na pozycji pokazuje jej opis).
3. Kliknij **Start**. Kolejność: winget → aplikacje → polityki Brave → domyślna przeglądarka → zakładki → pliki → ustawienia Windows → restart Eksploratora.
4. Log jest w oknie i w `logs\FreshSetup-<data>.log`.

## Struktura

```
FreshSetup.bat        uruchamia FreshSetup.ps1 z uprawnieniami administratora
FreshSetup.ps1        GUI i orkiestracja
lib\Catalog.ps1       lista aplikacji winget – tu dodajesz nowe programy
lib\Tweaks.ps1        ustawienia Windows (rejestr, powercfg)
lib\Brave.ps1         polityki Brave + domyślna przeglądarka
lib\Bookmarks.ps1     import zakładek (HTML Netscape / JSON Chromium) do profilu Brave
lib\Payload.ps1       pliki/foldery/linki do skopiowania (payload\manifest.json)
lib\Hardware.ps1      spis podzespołów (CIM/WMI) – sekcje panelu „Podzespoły”
lib\Winget.ps1        wykrywanie i bootstrap winget, instalacja pakietów
lib\Common.ps1        log, rejestr, uruchamianie procesów bez blokowania GUI
lib\SFTA.ps1          biblioteka PS-SFTA (MIT, DanysysTeam) – ustawianie domyślnych aplikacji w Windows 10/11
payload\              Twoje pliki, foldery i plik zakładek
logs\                 logi z uruchomień
```

## Dodawanie aplikacji

W `lib\Catalog.ps1` dopisz wiersz, np.:

```powershell
@{ Id = 'obs'; Name = 'OBS Studio'; WingetId = 'OBSProject.OBSStudio'; Default = $true; Description = 'Nagrywanie ekranu.' }
```

ID pakietu sprawdzisz poleceniem `winget search <nazwa>`. Pole `Scope = 'user'` wymusza instalację bez uprawnień administratora (potrzebne np. dla Spotify). Pole `Override = '...'` przekazuje własne przełączniki instalatora (`winget --override`), np. dla Pythona `/quiet InstallAllUsers=1 PrependPath=1`, żeby `python` był od razu w PATH.

## Uwagi

- **Uprawnienia** – aplikacja podnosi uprawnienia sama. Uruchamiaj ją z konta, które ma być skonfigurowane (ustawienia HKCU, domyślna przeglądarka i profil Brave dotyczą konta, na którym działa proces).
- **Polityki Brave** zapisywane są w `HKLM\SOFTWARE\Policies\BraveSoftware\Brave`. Objęte nimi opcje są w Brave oznaczone jako „zarządzane przez organizację” i zablokowane. Przycisk **Usuń polityki Brave** usuwa cały klucz i odblokowuje ustawienia.
- **Domyślna przeglądarka** – Windows 11 chroni to ustawienie podpisem (hash UserChoice). Używana jest biblioteka PS-SFTA, która go wylicza. Jeśli po aktualizacji Windows metoda przestanie działać, aplikacja otworzy Ustawienia → Aplikacje domyślne → Brave, gdzie wystarczy kliknąć „Ustaw domyślne”.
- **Zakładki** – jeśli Brave ma już zakładki, importowane trafiają do folderu „Zaimportowane <data>” na pasku zakładek; w przeciwnym razie plik jest tworzony od zera. Poprzedni plik dostaje kopię `.bak`. Brave musi być zamknięty (aplikacja zapyta, czy go zamknąć).
- **Spotify** – instalator odmawia pracy jako administrator, dlatego uruchamiany jest z obniżonymi uprawnieniami (`runas /trustlevel:0x20000`).
- **Docker Desktop** – wymaga WSL2 i restartu; aplikacja zaproponuje restart na końcu.
- **winget** – jeśli na świeżym systemie go brakuje, aplikacja próbuje kolejno: rejestracji pakietu App Installer, naprawy modułem `Microsoft.WinGet.Client`, pobrania instalatora z `aka.ms/getwinget`.
- **Dane diagnostyczne** – na Windows 11 Home minimalny poziom to „wymagane” (1); aplikacja ustawia właśnie ten poziom.

## Repozytorium

Kod mieszka w <https://github.com/kaamara/FreshSetup> (prywatne). Na nowym komputerze wystarczy:

```powershell
git clone https://github.com/kaamara/FreshSetup.git
```

Uwaga: `payload\` i `logs\` są w `.gitignore`, więc **Twoje pliki i zakładki nie trafiają do repozytorium**. To celowe – repo trzyma tylko kod, a prywatne dane przenosisz sam (pendrive, chmura) albo dodajesz od nowa w aplikacji. Jeśli kiedyś zechcesz mimo wszystko wersjonować konkretną rzecz, wymuś to jawnie: `git add -f payload/bookmarks/bookmarks.html`.

Pliki `.ps1` muszą zachować BOM UTF-8 i nie mogą być normalizowane – pilnuje tego `.gitattributes` (`* -text`).

## Tryb testowy

`FRESHSETUP_NOELEVATE=1` uruchamia GUI bez podnoszenia uprawnień (do podglądu interfejsu); `-AutoCloseSeconds 5` zamyka okno po 5 s.
