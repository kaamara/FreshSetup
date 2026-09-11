FreshSetup

Aplikacja z prostym GUI do konfiguracji świeżo zainstalowanego Windows 11. Czysty PowerShell 5.1 + WinForms, bez zewnętrznych zależności.

Co robi
Aplikacje – instalacja przez winget (Brave, Steam, Discord, VS Code, PyCharm, IntelliJ, Git, Docker Desktop, Claude, Spotify, Python i inne).
Ustawienia Windows – prywatność, Start, pasek zadań, ciemny motyw, akceleracja myszy, klawisze trwałe, plan zasilania.
Brave – ustawienie jako domyślna przeglądarka, polityki prywatności, import zakładek.
Pliki i zakładki – kopiowanie własnych plików, folderów i linków w wybrane miejsca na nowym komputerze.
Podzespoły – spis sprzętu (CPU, RAM, GPU, płyta, dyski, monitory, sieć, audio) z opcją kopiowania i zapisu.

Wszystko uruchamia jedno kliknięcie Start.

Użycie
1. Na obecnym komputerze
Uruchom FreshSetup.bat (poprosi o uprawnienia administratora).
W kolumnie Pliki i zakładki dodaj pliki, foldery i linki oraz wskaż plik zakładek Brave (brave://bookmarks → ⋮ → Eksportuj zakładki).
Zamknij aplikację i skopiuj cały folder FreshSetup (razem z payload\) na pendrive lub do chmury.
2. Na nowym komputerze
Skopiuj folder na dysk i uruchom FreshSetup.bat.
Zaznacz interesujące pozycje.
Kliknij Start.

Kolejność: winget → aplikacje → polityki Brave → domyślna przeglądarka → zakładki → pliki → ustawienia Windows → restart Eksploratora. Log trafia do okna i do logs\FreshSetup-<data>.log.

Struktura
FreshSetup.bat        uruchamia FreshSetup.ps1 jako administrator
FreshSetup.ps1        GUI i orkiestracja
lib\Catalog.ps1       lista aplikacji winget
lib\Tweaks.ps1        ustawienia Windows (rejestr, powercfg)
lib\Brave.ps1         polityki Brave + domyślna przeglądarka
lib\Bookmarks.ps1     import zakładek (HTML / JSON)
lib\Payload.ps1       pliki, foldery i linki (payload\manifest.json)
lib\Hardware.ps1      spis podzespołów (CIM/WMI)
lib\Winget.ps1        wykrywanie, bootstrap i instalacja pakietów
lib\Common.ps1        log, rejestr, uruchamianie procesów
lib\SFTA.ps1          PS-SFTA (MIT, DanysysTeam) – domyślne aplikacje
payload\              Twoje pliki i zakładki
logs\                 logi z uruchomień
Dodawanie aplikacji

W lib\Catalog.ps1 dopisz wiersz:

powershell
@{ Id = 'obs'; Name = 'OBS Studio'; WingetId = 'OBSProject.OBSStudio'; Default = $true; Description = 'Nagrywanie ekranu.' }

ID pakietu: winget search <nazwa>. Opcjonalnie Scope = 'user' (instalacja bez uprawnień administratora) i Override = '...' (własne przełączniki instalatora).

Uwagi
Uruchamiaj z konta, które ma być skonfigurowane – ustawienia HKCU, domyślna przeglądarka i profil Brave dotyczą tego konta.
Polityki Brave lądują w HKLM\SOFTWARE\Policies\BraveSoftware\Brave i są w przeglądarce oznaczone jako „zarządzane przez organizację”. Przycisk Usuń polityki Brave je kasuje.
Domyślna przeglądarka jest ustawiana przez PS-SFTA (hash UserChoice). Jeśli metoda przestanie działać, aplikacja otworzy Ustawienia → Aplikacje domyślne.
Import zakładek wymaga zamkniętego Brave. Istniejący plik dostaje kopię .bak, nowe zakładki trafiają do folderu „Zaimportowane”.
Spotify instaluje się z obniżonymi uprawnieniami, Docker Desktop wymaga WSL2 i restartu.
Pliki .ps1 muszą zachować BOM UTF-8 i nie mogą być normalizowane – pilnuje tego .gitattributes.
Instalacja
bash
git clone https://github.com/kaamara/FreshSetup.git
Tryb testowy

FRESHSETUP_NOELEVATE=1 – GUI bez podnoszenia uprawnień. -AutoCloseSeconds 5 – zamknięcie okna po 5 s.

## Tryb testowy

`FRESHSETUP_NOELEVATE=1` uruchamia GUI bez podnoszenia uprawnień (do podglądu interfejsu); `-AutoCloseSeconds 5` zamyka okno po 5 s.
