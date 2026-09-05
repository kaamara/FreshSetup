# Winget.ps1 – wykrywanie/instalacja winget oraz instalowanie aplikacji

function Get-WingetPath {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @("$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe")
    $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue |
        Sort-Object -Property Version -Descending | Select-Object -First 1
    if ($pkg -and $pkg.InstallLocation) { $candidates += (Join-Path $pkg.InstallLocation 'winget.exe') }
    $sys = Get-ChildItem "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($sys) { $candidates += $sys.FullName }
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

function Initialize-Winget {
    # Zwraca ścieżkę do winget.exe; na świeżym systemie próbuje go zarejestrować / doinstalować.
    $wg = Get-WingetPath
    if ($wg) { Write-Log "winget: $wg" Ok; return $wg }

    Write-Log 'winget nie znaleziony – próba rejestracji pakietu App Installer...' Warn
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
        Start-Sleep -Seconds 2
        $wg = Get-WingetPath
        if ($wg) { Write-Log "winget zarejestrowany: $wg" Ok; return $wg }
    }
    catch { Write-Log "  nie udało się: $($_.Exception.Message)" Dim }

    Write-Log 'Próba naprawy przez moduł Microsoft.WinGet.Client (PowerShell Gallery)...' Info
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Force -Scope CurrentUser -Repository PSGallery -AllowClobber -ErrorAction Stop
        Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        Repair-WinGetPackageManager -Latest -Force -ErrorAction Stop | Out-Null
        Start-Sleep -Seconds 2
        $wg = Get-WingetPath
        if ($wg) { Write-Log "winget zainstalowany: $wg" Ok; return $wg }
    }
    catch { Write-Log "  nie udało się: $($_.Exception.Message)" Dim }

    Write-Log 'Pobieranie winget (App Installer + zależności) z serwerów Microsoft...' Info
    $tmp = Join-Path $env:TEMP 'FreshSetup-winget'
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $files = @(
        @{ Url = 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx';      File = 'Microsoft.VCLibs.x64.14.00.Desktop.appx' },
        @{ Url = 'https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6'; File = 'Microsoft.UI.Xaml.2.8.6.zip' },
        @{ Url = 'https://aka.ms/getwinget';                                     File = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' }
    )
    foreach ($f in $files) {
        Write-Log "  pobieranie $($f.File)" Dim
        Invoke-UiPump
        Invoke-WebRequest -Uri $f.Url -OutFile (Join-Path $tmp $f.File) -UseBasicParsing
    }
    Expand-Archive -Path (Join-Path $tmp 'Microsoft.UI.Xaml.2.8.6.zip') -DestinationPath (Join-Path $tmp 'xaml') -Force
    $xamlAppx = Get-ChildItem (Join-Path $tmp 'xaml\tools\AppX\x64\Release') -Filter '*.appx' -ErrorAction SilentlyContinue | Select-Object -First 1
    try { Add-AppxPackage -Path (Join-Path $tmp 'Microsoft.VCLibs.x64.14.00.Desktop.appx') -ErrorAction Stop } catch { Write-Log "  VCLibs: $($_.Exception.Message)" Dim }
    if ($xamlAppx) { try { Add-AppxPackage -Path $xamlAppx.FullName -ErrorAction Stop } catch { Write-Log "  UI.Xaml: $($_.Exception.Message)" Dim } }
    Add-AppxPackage -Path (Join-Path $tmp 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle') -ErrorAction Stop
    Start-Sleep -Seconds 3
    $wg = Get-WingetPath
    if ($wg) { Write-Log "winget zainstalowany: $wg" Ok; return $wg }
    throw 'Nie udało się zainstalować winget. Zainstaluj „Instalator aplikacji” ze sklepu Microsoft Store i uruchom ponownie.'
}

function Test-WingetInstalled {
    param([string]$Winget, [string]$Id)
    $r = Invoke-External -FilePath $Winget -ArgumentList @('list', '--id', $Id, '--exact', '--accept-source-agreements', '--disable-interactivity') -TimeoutSec 180
    return ($r.ExitCode -eq 0 -and $r.Output -match [regex]::Escape($Id))
}

function Install-WingetApp {
    param(
        [Parameter(Mandatory = $true)][string]$Winget,
        [Parameter(Mandatory = $true)][hashtable]$App,
        [switch]$SkipInstalled
    )
    $ids = @($App.WingetId)
    if ($App.Fallback) { $ids += $App.Fallback }

    if ($SkipInstalled) {
        foreach ($id in $ids) {
            if (Test-WingetInstalled -Winget $Winget -Id $id) {
                Write-Log "  $($App.Name) jest już zainstalowany ($id) – pomijam." Ok
                return @{ Success = $true; Status = 'skipped' }
            }
        }
    }

    foreach ($id in $ids) {
        $wgArgs = @('install', '--id', $id, '--exact', '--source', 'winget', '--silent',
                    '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
        if ($App.Scope -eq 'user') {
            Write-Log '  instalator wymaga uruchomienia bez uprawnień administratora – uruchamiam jako zwykły użytkownik' Dim
            $r = Invoke-ExternalAsUser -FilePath $Winget -ArgumentList $wgArgs
        }
        else {
            $r = Invoke-External -FilePath $Winget -ArgumentList $wgArgs -Stream
        }
        $code = $r.ExitCode
        $hex = '0x{0:X8}' -f [int]$code   # ujemne kody HRESULT formatowane jako uzupełnienie do dwóch, np. 0x8A150014

        if ($r.TimedOut) {
            Write-Log "  $($App.Name): przekroczono limit czasu instalacji" Error
            return @{ Success = $false; Status = 'timeout' }
        }

        switch ($code) {
            0            { Write-Log "  $($App.Name): zainstalowano." Ok; return @{ Success = $true; Status = 'installed' } }
            3010         { Write-Log "  $($App.Name): zainstalowano – wymagany restart." Ok; $Script:RebootRecommended = $true; return @{ Success = $true; Status = 'installed' } }
            1641         { Write-Log "  $($App.Name): zainstalowano – wymagany restart." Ok; $Script:RebootRecommended = $true; return @{ Success = $true; Status = 'installed' } }
            -1978335189  { Write-Log "  $($App.Name): już zainstalowany w aktualnej wersji." Ok; return @{ Success = $true; Status = 'skipped' } }
            -1978335135  { Write-Log "  $($App.Name): już zainstalowany." Ok; return @{ Success = $true; Status = 'skipped' } }
            -1978335212  {
                Write-Log "  pakiet $id nie znaleziony w winget ($hex)" Warn
                continue   # spróbuj kolejnego ID (fallback)
            }
            default {
                if ($r.Output -match 'already installed|jest ju[zż] zainstalowan') {
                    Write-Log "  $($App.Name): już zainstalowany." Ok
                    return @{ Success = $true; Status = 'skipped' }
                }
                Write-Log "  $($App.Name): błąd instalacji, kod $code ($hex)" Error
                $tail = ($r.Output -split "[\r\n]+" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' | '
                if ($tail) { Write-Log "      $tail" Dim }
                return @{ Success = $false; Status = 'error'; Code = $code }
            }
        }
    }
    Write-Log "  $($App.Name): nie znaleziono pakietu w winget." Error
    return @{ Success = $false; Status = 'notfound' }
}
