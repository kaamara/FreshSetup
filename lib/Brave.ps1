# Brave.ps1 – polityki prywatności Brave (rejestr HKLM) i ustawienie Brave jako domyślnej przeglądarki.
# Polityki: https://github.com/brave/brave-core/tree/master/components/policy/resources/templates/policy_definitions/BraveSoftware
# Uwaga: ustawienia objęte polityką są w Brave oznaczone jako „zarządzane” i zablokowane. Usunięcie klucza rejestru je odblokowuje
# (przycisk „Usuń polityki Brave” w aplikacji).

$Script:BravePolicyPath = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'

$Script:BraveCatalog = @(
    @{ Id = 'brave_default'; Kind = 'default'; Name = 'Ustaw Brave jako domyślną przeglądarkę'; Default = $true
       Description = 'Rejestruje Brave dla http, https, .htm i .html – to samo, co przycisk „Ustaw domyślne” w Ustawieniach. Wymaga zainstalowanego Brave.' }

    @{ Id = 'brave_bookmarks'; Kind = 'bookmarks'; Name = 'Importuj zakładki z pliku'; Default = $true
       Description = 'Wgrywa zakładki do profilu Brave z pliku wybranego w kolumnie „Pliki i zakładki” (eksport HTML z brave://bookmarks → ⋮ → Eksportuj, albo plik „Bookmarks” z profilu). Brave musi być zamknięty.' }

    @{ Id = 'brave_p3a'; Kind = 'policy'; Name = 'Wyłącz analitykę P3A i dzienny ping statystyk'; Default = $true
       Description = 'Ustawienia Brave > Prywatność: „Zezwalaj na analitykę produktu chroniącą prywatność (P3A)” i „Automatycznie wysyłaj dzienny ping” = wył.'
       Values = @{ BraveP3AEnabled = 0; BraveStatsPingEnabled = 0 } }

    @{ Id = 'brave_metrics'; Kind = 'policy'; Name = 'Wyłącz raporty diagnostyczne i metryki (Chromium)'; Default = $true
       Description = 'Wyłącza automatyczne wysyłanie raportów diagnostycznych, statystyk użycia i danych o adresach URL.'
       Values = @{ MetricsReportingEnabled = 0; UrlKeyedAnonymizedDataCollectionEnabled = 0; FeedbackSurveysEnabled = 0 } }

    @{ Id = 'brave_webdiscovery'; Kind = 'policy'; Name = 'Wyłącz Web Discovery Project'; Default = $true
       Description = 'Nie wysyła anonimowych danych o wyszukiwaniach do Brave Search (Web Discovery Project).'
       Values = @{ BraveWebDiscoveryEnabled = 0 } }

    @{ Id = 'brave_rewards'; Kind = 'policy'; Name = 'Wyłącz Brave Rewards'; Default = $true
       Description = 'Ukrywa Brave Rewards (reklamy Brave, BAT).'
       Values = @{ BraveRewardsDisabled = 1 } }

    @{ Id = 'brave_wallet'; Kind = 'policy'; Name = 'Wyłącz Brave Wallet'; Default = $true
       Description = 'Ukrywa portfel krypto Brave Wallet.'
       Values = @{ BraveWalletDisabled = 1 } }

    @{ Id = 'brave_vpn'; Kind = 'policy'; Name = 'Wyłącz Brave VPN'; Default = $true
       Description = 'Ukrywa Brave VPN (płatna usługa) i jego przycisk.'
       Values = @{ BraveVPNDisabled = 1 } }

    @{ Id = 'brave_leo'; Kind = 'policy'; Name = 'Wyłącz Leo (asystent AI)'; Default = $true
       Description = 'Wyłącza asystenta AI Leo i jego przycisk w pasku bocznym.'
       Values = @{ BraveAIChatEnabled = 0 } }

    @{ Id = 'brave_news'; Kind = 'policy'; Name = 'Wyłącz Brave News'; Default = $true
       Description = 'Ukrywa kanał wiadomości Brave News na nowej karcie.'
       Values = @{ BraveNewsDisabled = 1 } }

    @{ Id = 'brave_talk'; Kind = 'policy'; Name = 'Wyłącz Brave Talk'; Default = $true
       Description = 'Ukrywa Brave Talk (wideorozmowy).'
       Values = @{ BraveTalkDisabled = 1 } }

    @{ Id = 'brave_background'; Kind = 'policy'; Name = 'Nie działaj w tle po zamknięciu'; Default = $true
       Description = 'Brave kończy pracę po zamknięciu ostatniego okna (BackgroundModeEnabled = 0).'
       Values = @{ BackgroundModeEnabled = 0 } }

    @{ Id = 'brave_bookmarkbar'; Kind = 'policy'; Name = 'Zawsze pokazuj pasek zakładek'; Default = $false
       Description = 'Pasek zakładek widoczny na każdej stronie (BookmarkBarEnabled = 1).'
       Values = @{ BookmarkBarEnabled = 1 } }

    @{ Id = 'brave_playlist'; Kind = 'policy'; Name = 'Wyłącz Playlist'; Default = $false
       Description = 'Ukrywa funkcję Brave Playlist.'
       Values = @{ BravePlaylistEnabled = 0 } }

    @{ Id = 'brave_tor'; Kind = 'policy'; Name = 'Wyłącz prywatne okna z Tor'; Default = $false
       Description = 'Usuwa opcję „Nowe okno prywatne z Tor”.'
       Values = @{ TorDisabled = 1 } }

    @{ Id = 'brave_searchsuggest'; Kind = 'policy'; Name = 'Wyłącz sugestie wyszukiwania w pasku adresu'; Default = $false
       Description = 'Brave nie wysyła wpisywanego tekstu do wyszukiwarki w celu podpowiedzi.'
       Values = @{ SearchSuggestEnabled = 0 } }

    @{ Id = 'brave_nodefaultprompt'; Kind = 'policy'; Name = 'Wyłącz monit „ustaw Brave jako domyślną”'; Default = $false
       Description = 'Brave nie będzie pytać o ustawienie jako domyślna (przydatne, gdy domyślną ustawia ta aplikacja).'
       Values = @{ DefaultBrowserSettingEnabled = 0 } }
)

function Set-BravePolicy {
    param([Parameter(Mandatory = $true)][hashtable]$Item)
    foreach ($k in $Item.Values.Keys) {
        Set-RegValue $Script:BravePolicyPath $k ([int]$Item.Values[$k])
    }
    $desc = ($Item.Values.Keys | ForEach-Object { "$_=$($Item.Values[$_])" }) -join ', '
    Write-Log "  ✓ $($Item.Name)  [$desc]" Ok
}

function Remove-BravePolicies {
    if (Test-Path $Script:BravePolicyPath) {
        Remove-Item -Path $Script:BravePolicyPath -Recurse -Force
        Write-Log 'Usunięto polityki Brave (HKLM\SOFTWARE\Policies\BraveSoftware\Brave). Uruchom Brave ponownie.' Ok
        return $true
    }
    Write-Log 'Brak polityk Brave do usunięcia.' Info
    return $false
}

function Get-BravePath {
    $candidates = @(
        (Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\brave.exe' '(default)'),
        (Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\brave.exe' '(default)'),
        "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
        "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

function Get-BraveProgId {
    # Odczytuje ProgId zarejestrowany przez Brave (system lub użytkownik), np. BraveHTML.
    foreach ($hive in 'HKCU:', 'HKLM:') {
        $ra = Get-ItemProperty "$hive\Software\RegisteredApplications" -ErrorAction SilentlyContinue
        if (-not $ra) { continue }
        foreach ($p in $ra.PSObject.Properties) {
            if ($p.Name -like 'Brave*' -and $p.Value -is [string]) {
                $cap = Get-ItemProperty "$hive\$($p.Value)\URLAssociations" -ErrorAction SilentlyContinue
                if ($cap -and $cap.https) { return [string]$cap.https }
            }
        }
    }
    foreach ($k in 'HKCU:\Software\Classes\BraveHTML', 'HKLM:\Software\Classes\BraveHTML') {
        if (Test-Path $k) { return 'BraveHTML' }
    }
    return $null
}

function Set-BraveDefaultBrowser {
    $progId = Get-BraveProgId
    if (-not $progId) {
        Write-Log '  Brave nie jest zarejestrowany w systemie (nie zainstalowany?) – pomijam.' Warn
        return $false
    }
    Write-Log "  ProgId Brave: $progId" Dim
    foreach ($proto in 'http', 'https') { Set-PTA -ProgId $progId -Protocol $proto }
    foreach ($ext in '.htm', '.html') { Set-FTA -ProgId $progId -Extension $ext }

    $ok = $true
    foreach ($proto in 'http', 'https') {
        $cur = Get-RegValue "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$proto\UserChoice" 'ProgId'
        if ($cur -ne $progId) { $ok = $false }
    }
    if ($ok) {
        Write-Log '  ✓ Brave jest domyślną przeglądarką (http, https, .htm, .html).' Ok
        return $true
    }
    Write-Log '  Automatyczne ustawienie nie zadziałało – otwieram Ustawienia > Aplikacje domyślne > Brave. Kliknij „Ustaw domyślne”.' Warn
    try { Start-Process 'ms-settings:defaultapps?registeredAppUser=Brave' } catch { Start-Process 'ms-settings:defaultapps' }
    return $false
}
