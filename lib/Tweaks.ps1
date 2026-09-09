# Tweaks.ps1 – ustawienia systemu Windows 11.
# Każdy wpis: Id, Group, Name, Description, Default (zaznaczony domyślnie), Explorer (wymaga restartu Eksploratora), Action (scriptblock).
# Pozycje domyślnie zaznaczone odpowiadają ustawieniom wyłączonym na komputerze wzorcowym.

$ADV = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$CDM = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'

function Set-MouseAcceleration {
    param([bool]$Enabled)
    $v = if ($Enabled) { @('1', '6', '10') } else { @('0', '0', '0') }
    Set-RegValue 'HKCU:\Control Panel\Mouse' 'MouseSpeed'      $v[0] 'String'
    Set-RegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' $v[1] 'String'
    Set-RegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' $v[2] 'String'
    try {
        if (-not ('FreshSetup.Mouse' -as [type])) {
            Add-Type -Namespace FreshSetup -Name Mouse -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);
'@
        }
        $arr = [int[]]@([int]$v[1], [int]$v[2], [int]$v[0])
        [FreshSetup.Mouse]::SystemParametersInfo(0x0004, 0, $arr, 0x0003) | Out-Null   # SPI_SETMOUSE, UPDATEINIFILE|SENDCHANGE
    }
    catch { }
}

function Set-HighPerformancePlan {
    $guid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    $list = (powercfg /list) -join "`n"
    if ($list -notmatch $guid) {
        # Na laptopach z Modern Standby plan jest ukryty – tworzymy kopię.
        $dup = (powercfg /duplicatescheme $guid) -join ' '
        if ($dup -match '([0-9a-fA-F-]{36})') { $guid = $Matches[1] }
    }
    powercfg /setactive $guid | Out-Null
    $active = (powercfg /getactivescheme) -join ' '
    if ($active -notmatch $guid) { throw "powercfg nie przełączył planu: $active" }
}

$Script:TweakCatalog = @(
    # ------------------------------------------------------------ Prywatność
    @{ Id = 'adid'; Group = 'Prywatność'; Name = 'Wyłącz identyfikator reklamowy'; Default = $true; Explorer = $false
       Description = 'Ustawienia > Prywatność > Ogólne: „Zezwalaj aplikacjom na wyświetlanie spersonalizowanych reklam przy użyciu identyfikatora reklamowego” = wył.'
       Action = { Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 } }

    @{ Id = 'tailored'; Group = 'Prywatność'; Name = 'Wyłącz dopasowane doświadczenia'; Default = $true; Explorer = $false
       Description = 'Diagnostyka i opinie: „Dopasowane doświadczenia” (porady/reklamy na podstawie danych diagnostycznych) = wył.'
       Action = { Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 } }

    @{ Id = 'langlist'; Group = 'Prywatność'; Name = 'Nie udostępniaj listy języków stronom WWW'; Default = $true; Explorer = $false
       Description = 'Prywatność > Ogólne: „Zezwalaj witrynom na dostęp do listy języków” = wył.'
       Action = { Set-RegValue 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1 } }

    @{ Id = 'telemetry'; Group = 'Prywatność'; Name = 'Dane diagnostyczne tylko wymagane, bez prośb o opinie'; Default = $true; Explorer = $false
       Description = 'Diagnostyka i opinie: wyłącza opcjonalne dane diagnostyczne (poziom „wymagane”) i ustawia częstość próśb o opinie na „nigdy”.'
       Action = {
           Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 1
           Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'MaxTelemetryAllowed' 1
           Set-RegValue 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
           Set-RegValue 'HKCU:\Software\Microsoft\Siuf\Rules' 'PeriodInNanoSeconds' 0
       } }

    @{ Id = 'inking'; Group = 'Prywatność'; Name = 'Wyłącz personalizację pisma ręcznego i wpisywania'; Default = $true; Explorer = $false
       Description = 'Prywatność > Personalizacja pisma ręcznego i wpisywania = wył. (słownik osobisty, zbieranie kontaktów).'
       Action = {
           Set-RegValue 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
           Set-RegValue 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
           Set-RegValue 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
           Set-RegValue 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
       } }

    @{ Id = 'typingdiag'; Group = 'Prywatność'; Name = 'Nie wysyłaj danych o pisaniu do Microsoft'; Default = $true; Explorer = $false
       Description = 'Diagnostyka i opinie: „Ulepszaj pismo ręczne i wpisywanie” = wył.'
       Action = { Set-RegValue 'HKCU:\Software\Microsoft\Input\TIPC' 'Enabled' 0 } }

    @{ Id = 'bloat'; Group = 'Prywatność'; Name = 'Nie instaluj automatycznie promowanych aplikacji'; Default = $true; Explorer = $false
       Description = 'Blokuje automatyczne doinstalowywanie aplikacji promowanych (Candy Crush, TikTok itp.) oraz sugestie aplikacji w menu Start.'
       Action = {
           foreach ($n in 'SilentInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'PreInstalledAppsEverEnabled', 'OemPreInstalledAppsEnabled',
                          'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled', 'SubscribedContent-338388Enabled') {
               Set-RegValue $CDM $n 0
           }
       } }

    @{ Id = 'activity'; Group = 'Prywatność'; Name = 'Wyłącz historię aktywności'; Default = $false; Explorer = $false
       Description = 'Prywatność > Historia aktywności: nie zapisuj i nie wysyłaj historii aktywności.'
       Action = {
           Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
           Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0
           Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0
       } }

    @{ Id = 'location'; Group = 'Prywatność'; Name = 'Wyłącz usługi lokalizacji'; Default = $false; Explorer = $false
       Description = 'Prywatność > Lokalizacja = wył. dla systemu i aplikacji.'
       Action = {
           Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String'
           Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String'
       } }

    @{ Id = 'tips'; Group = 'Prywatność'; Name = 'Wyłącz porady, Windows Spotlight i „dokończ konfigurację”'; Default = $false; Explorer = $false
       Description = 'Wyłącza porady/sugestie Windows, treści Spotlight na ekranie blokady i monity „Dokończ konfigurację urządzenia”.'
       Action = {
           foreach ($n in 'SubscribedContent-338389Enabled', 'SubscribedContent-338387Enabled', 'RotatingLockScreenEnabled', 'RotatingLockScreenOverlayEnabled') { Set-RegValue $CDM $n 0 }
           Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
       } }

    @{ Id = 'copilot'; Group = 'Prywatność'; Name = 'Wyłącz Copilot'; Default = $false; Explorer = $true
       Description = 'Wyłącza Windows Copilot (polityka użytkownika) i ukrywa jego przycisk na pasku zadań.'
       Action = {
           Set-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
           Set-RegValue $ADV 'ShowCopilotButton' 0
       } }

    @{ Id = 'recall'; Group = 'Prywatność'; Name = 'Wyłącz Recall (migawki ekranu AI)'; Default = $false; Explorer = $false
       Description = 'Blokuje zapisywanie migawek ekranu przez funkcję Recall (polityka DisableAIDataAnalysis).'
       Action = {
           Set-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
           Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
       } }

    @{ Id = 'bing'; Group = 'Prywatność'; Name = 'Wyłącz wyniki z Internetu (Bing) w wyszukiwaniu Start'; Default = $false; Explorer = $true
       Description = 'Wyszukiwanie w menu Start pokazuje tylko lokalne wyniki, bez Bing.'
       Action = { Set-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1 } }

    # ------------------------------------------------------------ Start i pasek zadań
    @{ Id = 'starttrack'; Group = 'Start'; Name = 'Nie pokazuj ostatnio dodanych/otwieranych elementów'; Default = $true; Explorer = $true
       Description = 'Personalizacja > Start: „Pokaż ostatnio dodane aplikacje” i „Pokaż ostatnio otwierane elementy” = wył.'
       Action = {
           Set-RegValue $ADV 'Start_TrackProgs' 0
           Set-RegValue $ADV 'Start_TrackDocs' 0
       } }

    @{ Id = 'startrec'; Group = 'Start'; Name = 'Wyłącz rekomendacje i porady w menu Start'; Default = $true; Explorer = $true
       Description = 'Personalizacja > Start: „Pokaż rekomendacje dotyczące porad, skrótów, nowych aplikacji” = wył.'
       Action = { Set-RegValue $ADV 'Start_IrisRecommendations' 0 } }

    @{ Id = 'settingsads'; Group = 'Start'; Name = 'Wyłącz sugerowane treści w aplikacji Ustawienia'; Default = $true; Explorer = $false
       Description = 'Prywatność > Ogólne: „Pokaż sugerowane treści w aplikacji Ustawienia” = wył.'
       Action = { foreach ($n in 'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled') { Set-RegValue $CDM $n 0 } } }

    @{ Id = 'taskview'; Group = 'Pasek zadań'; Name = 'Ukryj przycisk Widok zadań'; Default = $true; Explorer = $true
       Description = 'Personalizacja > Pasek zadań: „Widok zadań” = wył.'
       Action = { Set-RegValue $ADV 'ShowTaskViewButton' 0 } }

    @{ Id = 'searchbox'; Group = 'Pasek zadań'; Name = 'Ukryj pole wyszukiwania'; Default = $true; Explorer = $true
       Description = 'Personalizacja > Pasek zadań > Wyszukiwanie = „Ukryj” (wyszukiwanie dalej działa po naciśnięciu Win).'
       Action = { Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0 } }

    @{ Id = 'widgets'; Group = 'Pasek zadań'; Name = 'Ukryj widżety'; Default = $false; Explorer = $true
       Description = 'Personalizacja > Pasek zadań: „Widżety” = wył.'
       Action = { Set-RegValue $ADV 'TaskbarDa' 0 } }

    @{ Id = 'taskbarleft'; Group = 'Pasek zadań'; Name = 'Wyrównaj pasek zadań do lewej'; Default = $false; Explorer = $true
       Description = 'Personalizacja > Pasek zadań > Zachowania paska zadań: wyrównanie = do lewej.'
       Action = { Set-RegValue $ADV 'TaskbarAl' 0 } }

    @{ Id = 'endtask'; Group = 'Pasek zadań'; Name = 'Dodaj „Zakończ zadanie” do menu paska zadań'; Default = $false; Explorer = $true
       Description = 'System > Dla deweloperów: „Zakończ zadanie” po kliknięciu prawym przyciskiem na aplikację w pasku zadań.'
       Action = { Set-RegValue "$ADV\TaskbarDeveloperSettings" 'TaskbarEndTask' 1 } }

    # ------------------------------------------------------------ Wygląd i Eksplorator
    @{ Id = 'darkmode'; Group = 'Wygląd'; Name = 'Tryb ciemny (system i aplikacje)'; Default = $true; Explorer = $true
       Description = 'Personalizacja > Kolory: tryb = Ciemny.'
       Action = {
           Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' 0
           Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' 0
       } }

    @{ Id = 'fileext'; Group = 'Eksplorator'; Name = 'Pokaż rozszerzenia plików'; Default = $false; Explorer = $true
       Description = 'Eksplorator > Widok > Pokaż > Rozszerzenia nazw plików.'
       Action = { Set-RegValue $ADV 'HideFileExt' 0 } }

    @{ Id = 'hidden'; Group = 'Eksplorator'; Name = 'Pokaż ukryte pliki i foldery'; Default = $false; Explorer = $true
       Description = 'Eksplorator > Widok > Pokaż > Ukryte elementy.'
       Action = { Set-RegValue $ADV 'Hidden' 1 } }

    @{ Id = 'launchto'; Group = 'Eksplorator'; Name = 'Otwieraj „Ten komputer” zamiast Strony głównej'; Default = $false; Explorer = $true
       Description = 'Opcje Eksploratora: „Otwórz Eksploratora plików dla: Ten komputer”.'
       Action = { Set-RegValue $ADV 'LaunchTo' 1 } }

    # ------------------------------------------------------------ Sterowanie i wydajność
    @{ Id = 'mouseaccel'; Group = 'Mysz'; Name = 'Wyłącz akcelerację myszy (zwiększ precyzję wskaźnika)'; Default = $true; Explorer = $false
       Description = 'Mysz > Dodatkowe ustawienia > Opcje wskaźnika: „Zwiększ precyzję wskaźnika” = wył. Ważne dla gier.'
       Action = { Set-MouseAcceleration -Enabled $false } }

    @{ Id = 'stickykeys'; Group = 'Klawiatura'; Name = 'Wyłącz skrót klawiszy trwałych (5× Shift) i dźwięki skrótów ułatwień'; Default = $true; Explorer = $false
       Description = 'Ułatwienia dostępu: wyłącza skrót klawiszy trwałych oraz potwierdzenia/dźwięki dla klawiszy przełączających i filtrowania.'
       Action = {
           Set-RegValue 'HKCU:\Control Panel\Accessibility\StickyKeys'        'Flags' '482' 'String'
           Set-RegValue 'HKCU:\Control Panel\Accessibility\ToggleKeys'        'Flags' '38'  'String'
           Set-RegValue 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '102' 'String'
       } }

    @{ Id = 'highperf'; Group = 'Zasilanie'; Name = 'Plan zasilania: Wysoka wydajność'; Default = $true; Explorer = $false
       Description = 'Aktywuje plan „Wysoka wydajność” (tworzy go, jeśli jest ukryty).'
       Action = { Set-HighPerformancePlan } }
)
