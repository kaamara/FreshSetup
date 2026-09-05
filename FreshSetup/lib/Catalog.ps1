# Catalog.ps1 – lista aplikacji do instalacji przez winget.
# Dodaj własną aplikację kopiując jeden wpis. ID znajdziesz poleceniem:  winget search <nazwa>
#   Id          – dowolny unikalny identyfikator wewnętrzny
#   Name        – nazwa widoczna w GUI
#   WingetId    – dokładne ID pakietu winget
#   Default     – czy domyślnie zaznaczone
#   Fallback    – (opcjonalnie) zapasowe ID, gdyby główne nie istniało
#   Scope       – (opcjonalnie) 'user' = instalator musi działać BEZ uprawnień administratora (np. Spotify)
#   Description – opis pokazywany pod listami

$Script:AppCatalog = @(
    @{ Id = 'brave';      Name = 'Brave (przeglądarka)';   WingetId = 'Brave.Brave';                Default = $true
       Description = 'Przeglądarka Brave. Po instalacji zastosowane zostaną polityki prywatności z kolumny „Brave”, ustawienie jako domyślna i import zakładek.' }
    @{ Id = 'steam';      Name = 'Steam';                  WingetId = 'Valve.Steam';                Default = $true
       Description = 'Klient gier Steam.' }
    @{ Id = 'discord';    Name = 'Discord';                WingetId = 'Discord.Discord';            Default = $true
       Description = 'Komunikator Discord.' }
    @{ Id = 'pycharm';    Name = 'PyCharm';                WingetId = 'JetBrains.PyCharm';          Default = $true;  Fallback = 'JetBrains.PyCharm.Community'
       Description = 'JetBrains PyCharm (zunifikowana edycja 2025.3+; zapasowo Community).' }
    @{ Id = 'git';        Name = 'Git';                    WingetId = 'Git.Git';                    Default = $true
       Description = 'Git for Windows (git, Git Bash).' }
    @{ Id = 'vscode';     Name = 'Visual Studio Code';     WingetId = 'Microsoft.VisualStudioCode'; Default = $true
       Description = 'Edytor Visual Studio Code.' }
    @{ Id = 'docker';     Name = 'Docker Desktop';         WingetId = 'Docker.DockerDesktop';       Default = $true
       Description = 'Docker Desktop. Wymaga WSL2 i zwykle restartu komputera po instalacji.' }
    @{ Id = 'intellij';   Name = 'IntelliJ IDEA';          WingetId = 'JetBrains.IntelliJIDEA';     Default = $true;  Fallback = 'JetBrains.IntelliJIDEA.Community'
       Description = 'JetBrains IntelliJ IDEA (zunifikowana edycja; zapasowo Community).' }
    @{ Id = 'claude';     Name = 'Claude (aplikacja)';     WingetId = 'Anthropic.Claude';           Default = $true
       Description = 'Aplikacja desktopowa Claude (Anthropic).' }
    @{ Id = 'claudecode'; Name = 'Claude Code (CLI)';      WingetId = 'Anthropic.ClaudeCode';       Default = $false
       Description = 'Narzędzie Claude Code do terminala.' }
    @{ Id = 'spotify';    Name = 'Spotify';                WingetId = 'Spotify.Spotify';            Default = $true;  Scope = 'user'
       Description = 'Spotify. Instalator odmawia pracy jako administrator, więc uruchamiany jest jako zwykły użytkownik.' }
)
