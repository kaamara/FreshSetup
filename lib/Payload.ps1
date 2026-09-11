# Payload.ps1 – pliki/foldery/linki kopiowane na nowy komputer oraz plik zakładek Brave.
# Wszystko leży w folderze payload\ obok aplikacji, wystarczy skopiować cały folder FreshSetup
#   payload\manifest.json – lista pozycji i ich miejsc docelowych
#   payload\files\<id>\…  – kopie dodanych plików/folderów
#   payload\bookmarks\…   – plik zakładek

$Script:PayloadDir       = Join-Path $Script:AppRoot 'payload'
$Script:PayloadFiles     = Join-Path $Script:PayloadDir 'files'
$Script:PayloadBookmarks = Join-Path $Script:PayloadDir 'bookmarks'
$Script:ManifestPath     = Join-Path $Script:PayloadDir 'manifest.json'

$Script:DestinationPresets = @(
    @{ Name = 'Pulpit';             Path = '%USERPROFILE%\Desktop' }
    @{ Name = 'Dokumenty';          Path = '%USERPROFILE%\Documents' }
    @{ Name = 'Pobrane';            Path = '%USERPROFILE%\Downloads' }
    @{ Name = 'Obrazy';             Path = '%USERPROFILE%\Pictures' }
    @{ Name = 'Muzyka';             Path = '%USERPROFILE%\Music' }
    @{ Name = 'Wideo';              Path = '%USERPROFILE%\Videos' }
    @{ Name = 'Folder użytkownika'; Path = '%USERPROFILE%' }
    @{ Name = 'AppData\Roaming';    Path = '%APPDATA%' }
    @{ Name = 'AppData\Local';      Path = '%LOCALAPPDATA%' }
    @{ Name = 'Dysk C:\';           Path = 'C:\' }
)

function ConvertTo-PayloadItem {
    param($Obj)
    return @{
        id          = [string]$Obj.id
        type        = [string]$Obj.type
        name        = [string]$Obj.name
        source      = [string]$Obj.source
        destination = [string]$Obj.destination
        enabled     = [bool]$Obj.enabled
    }
}

function Get-Manifest {
    $m = @{ items = @(); bookmarks = $null }
    if (Test-Path $Script:ManifestPath) {
        try {
            $json = Get-Content -LiteralPath $Script:ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($json.items) { $m.items = @($json.items | ForEach-Object { ConvertTo-PayloadItem $_ }) }
            if ($json.bookmarks) { $m.bookmarks = [string]$json.bookmarks }
        }
        catch { Write-Log "Nie można odczytać payload\manifest.json: $($_.Exception.Message)" Warn }
    }
    return $m
}

function Save-Manifest {
    param([hashtable]$Manifest)
    New-Item -ItemType Directory -Force -Path $Script:PayloadDir | Out-Null
    $items = New-Object System.Collections.ArrayList
    foreach ($it in @($Manifest.items)) {
        [void]$items.Add([ordered]@{ id = $it.id; type = $it.type; name = $it.name; source = $it.source; destination = $it.destination; enabled = [bool]$it.enabled })
    }
    $obj = [ordered]@{ items = $items; bookmarks = $Manifest.bookmarks }
    $json = $obj | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($Script:ManifestPath, $json, (New-Object Text.UTF8Encoding $false))
}

function Get-DestinationLabel {
    param([string]$Path)
    $p = $Script:DestinationPresets | Where-Object { $_.Path -eq $Path } | Select-Object -First 1
    if ($p) { return $p.Name }
    return $Path
}

function Format-PayloadItem {
    param([hashtable]$Item)
    $kind = switch ($Item.type) { 'file' { 'Plik' } 'folder' { 'Folder' } 'url' { 'Link' } default { $Item.type } }
    return "[$kind] $($Item.name)  →  $(Get-DestinationLabel $Item.destination)"
}

function Add-PayloadItem {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('file', 'folder', 'url')][string]$Type,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    $m = Get-Manifest
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    if ($Type -eq 'url') {
        $name = ''
        try { $name = [IO.Path]::GetFileName(([uri]$Source).LocalPath) } catch { }
        if (-not $name -or $name -eq '/' ) { $name = "pobrane-$id" }
        $src = $Source
    }
    else {
        $name = Split-Path -Path $Source -Leaf
        $dir = Join-Path $Script:PayloadFiles $id
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        if ($Type -eq 'folder') {
            $dst = Join-Path $dir $name
            New-Item -ItemType Directory -Force -Path $dst | Out-Null
            Copy-Item -Path (Join-Path $Source '*') -Destination $dst -Recurse -Force
        }
        else {
            Copy-Item -LiteralPath $Source -Destination (Join-Path $dir $name) -Force
        }
        $src = "files\$id\$name"
    }
    $item = @{ id = $id; type = $Type; name = $name; source = $src; destination = $Destination; enabled = $true }
    $list = New-Object System.Collections.ArrayList
    foreach ($it in @($m.items)) { [void]$list.Add($it) }
    [void]$list.Add($item)
    $m.items = $list.ToArray()
    Save-Manifest $m
    return $item
}

function Remove-PayloadItem {
    param([Parameter(Mandatory = $true)][string]$Id)
    $m = Get-Manifest
    $it = @($m.items) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if ($it -and $it.type -ne 'url') {
        Remove-Item -LiteralPath (Join-Path $Script:PayloadFiles $Id) -Recurse -Force -ErrorAction SilentlyContinue
    }
    $m.items = @(@($m.items) | Where-Object { $_.id -ne $Id })
    Save-Manifest $m
}

function Set-PayloadItemEnabled {
    param([string]$Id, [bool]$Enabled)
    $m = Get-Manifest
    foreach ($it in @($m.items)) { if ($it.id -eq $Id) { $it.enabled = $Enabled } }
    Save-Manifest $m
}

function Set-PayloadBookmarks {
    param([Parameter(Mandatory = $true)][string]$Source)
    New-Item -ItemType Directory -Force -Path $Script:PayloadBookmarks | Out-Null
    Get-ChildItem -LiteralPath $Script:PayloadBookmarks -File -ErrorAction SilentlyContinue | Remove-Item -Force
    $name = Split-Path -Path $Source -Leaf
    Copy-Item -LiteralPath $Source -Destination (Join-Path $Script:PayloadBookmarks $name) -Force
    $m = Get-Manifest
    $m.bookmarks = "bookmarks\$name"
    Save-Manifest $m
    return $m.bookmarks
}

function Clear-PayloadBookmarks {
    Get-ChildItem -LiteralPath $Script:PayloadBookmarks -File -ErrorAction SilentlyContinue | Remove-Item -Force
    $m = Get-Manifest
    $m.bookmarks = $null
    Save-Manifest $m
}

function Copy-PayloadItem {
    # Kopiuje/pobiera jedną pozycję do jej miejsca docelowego. Zwraca ścieżkę docelową.
    param([Parameter(Mandatory = $true)][hashtable]$Item)
    $dest = [Environment]::ExpandEnvironmentVariables($Item.destination)
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $target = Join-Path $dest $Item.name
    switch ($Item.type) {
        'url' {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $wc = New-Object Net.WebClient
            $wc.Headers.Add('User-Agent', 'FreshSetup/1.0')
            $task = $wc.DownloadFileTaskAsync($Item.source, $target)
            while (-not $task.IsCompleted) { Invoke-UiPump; Start-Sleep -Milliseconds 200 }
            if ($task.IsFaulted) {
                $ex = $task.Exception
                if ($ex.InnerException) { $ex = $ex.InnerException }
                throw "pobieranie nie powiodło się: $($ex.Message)"
            }
        }
        'folder' {
            $src = Join-Path $Script:PayloadDir $Item.source
            if (-not (Test-Path -LiteralPath $src)) { throw "brak źródła w payload: $src" }
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            Copy-Item -Path (Join-Path $src '*') -Destination $target -Recurse -Force
        }
        default {
            $src = Join-Path $Script:PayloadDir $Item.source
            if (-not (Test-Path -LiteralPath $src)) { throw "brak źródła w payload: $src" }
            Copy-Item -LiteralPath $src -Destination $target -Force
        }
    }
    return $target
}
