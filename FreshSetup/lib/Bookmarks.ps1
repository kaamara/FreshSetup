# Bookmarks.ps1 – import zakładek do Brave (profil Default) z pliku HTML (eksport z Brave/Chrome/Edge/Firefox)
# albo z pliku „Bookmarks” (JSON profilu Chromium). Brave musi być zamknięty podczas zapisu.

$Script:BraveUserData       = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'
$Script:ChromiumEpochOffset = 11644473600
$Script:BookmarkRootGuids   = @{
    bar    = '0bc5d13f-2cba-5d74-951f-3f233fe6c908'
    other  = '82b081ec-3dd3-529c-8475-ab6c344590dd'
    synced = '4cf2e351-0e85-532b-bb37-df045d8f8d0f'
}

function ConvertTo-ChromeTime {
    param([long]$UnixSeconds = 0)
    if ($UnixSeconds -le 0) { $UnixSeconds = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
    return [string](($UnixSeconds + $Script:ChromiumEpochOffset) * 1000000)
}

function New-BookmarkNode {
    param([string]$Name, [string]$Url = '', [long]$AddDate = 0)
    $node = [ordered]@{
        date_added     = (ConvertTo-ChromeTime $AddDate)
        date_last_used = '0'
        guid           = [guid]::NewGuid().ToString()
        id             = '0'
        name           = $Name
    }
    if ($Url) {
        $node['type'] = 'url'
        $node['url'] = $Url
    }
    else {
        $node['children'] = New-Object System.Collections.ArrayList
        $node['date_modified'] = '0'
        $node['type'] = 'folder'
    }
    return $node
}

function ConvertFrom-NetscapeBookmarks {
    # Parsuje format Netscape Bookmark (eksport HTML). Zwraca @{ Bar = [lista]; Other = [lista] }.
    param([string]$Html)
    $root = New-BookmarkNode -Name 'root'
    $toolbar = New-Object System.Collections.Generic.HashSet[string]
    $stack = New-Object System.Collections.Stack
    $current = $root
    $pending = $null
    $rootOpened = $false
    $rx = [regex]'(?is)<DT>\s*<H3([^>]*)>(.*?)</H3>|<DT>\s*<A\s([^>]*)>(.*?)</A>|<DL[^>]*>|</DL>'
    foreach ($m in $rx.Matches($Html)) {
        $tok = $m.Value
        if ($tok -match '^<DL') {
            if ($pending) { $stack.Push($current); $current = $pending; $pending = $null }
            elseif (-not $rootOpened) { $rootOpened = $true }
            else { $stack.Push($current) }
        }
        elseif ($tok -match '^</DL') {
            if ($stack.Count -gt 0) { $current = $stack.Pop() }
        }
        elseif ($tok -match '^<DT>\s*<H3') {
            $attrs = $m.Groups[1].Value
            $title = [Net.WebUtility]::HtmlDecode(($m.Groups[2].Value -replace '<[^>]+>', '')).Trim()
            $add = 0
            if ($attrs -match 'ADD_DATE="(\d+)"') { $add = [long]$Matches[1] }
            $f = New-BookmarkNode -Name $title -AddDate $add
            if ($attrs -match 'PERSONAL_TOOLBAR_FOLDER="true"') { [void]$toolbar.Add($f.guid) }
            [void]$current.children.Add($f)
            $pending = $f
        }
        else {
            $attrs = $m.Groups[3].Value
            if ($attrs -notmatch 'HREF="([^"]*)"') { continue }
            $href = [Net.WebUtility]::HtmlDecode($Matches[1])
            if ($href -match '^(place|javascript|data):') { continue }
            $title = [Net.WebUtility]::HtmlDecode(($m.Groups[4].Value -replace '<[^>]+>', '')).Trim()
            if (-not $title) { $title = $href }
            $add = 0
            if ($attrs -match 'ADD_DATE="(\d+)"') { $add = [long]$Matches[1] }
            [void]$current.children.Add((New-BookmarkNode -Name $title -Url $href -AddDate $add))
        }
    }
    $bar = New-Object System.Collections.ArrayList
    $other = New-Object System.Collections.ArrayList
    foreach ($n in $root.children) {
        if ($n.type -eq 'folder' -and $toolbar.Contains($n.guid)) { foreach ($c in $n.children) { [void]$bar.Add($c) } }
        else { [void]$other.Add($n) }
    }
    if ($bar.Count -eq 0 -and $other.Count -gt 0) { $bar = $other; $other = New-Object System.Collections.ArrayList }
    return @{ Bar = $bar; Other = $other }
}

function ConvertTo-BookmarkNode {
    # PSCustomObject (z ConvertFrom-Json) -> uporządkowana tablica skrótów z ArrayList w children
    param($Obj)
    $node = [ordered]@{}
    foreach ($p in $Obj.PSObject.Properties) {
        if ($p.Name -eq 'children') {
            $list = New-Object System.Collections.ArrayList
            foreach ($c in @($p.Value)) { if ($c) { [void]$list.Add((ConvertTo-BookmarkNode $c)) } }
            $node['children'] = $list
        }
        elseif ($p.Name -eq 'meta_info') { continue }
        else { $node[$p.Name] = [string]$p.Value }
    }
    if (-not $node.Contains('guid') -or -not $node['guid']) { $node['guid'] = [guid]::NewGuid().ToString() }
    return $node
}

function Read-ChromiumBookmarksJson {
    param([string]$Json)
    $doc = $Json | ConvertFrom-Json
    $bar = New-Object System.Collections.ArrayList
    $other = New-Object System.Collections.ArrayList
    if ($doc.roots.bookmark_bar.children) { foreach ($c in @($doc.roots.bookmark_bar.children)) { [void]$bar.Add((ConvertTo-BookmarkNode $c)) } }
    if ($doc.roots.other.children)        { foreach ($c in @($doc.roots.other.children))        { [void]$other.Add((ConvertTo-BookmarkNode $c)) } }
    if ($doc.roots.synced.children)       { foreach ($c in @($doc.roots.synced.children))       { [void]$other.Add((ConvertTo-BookmarkNode $c)) } }
    return @{ Bar = $bar; Other = $other }
}

function Measure-BookmarkNodes {
    param($Nodes)
    $n = 0
    foreach ($x in @($Nodes)) {
        if ($x.type -eq 'url') { $n++ }
        elseif ($x.children) { $n += Measure-BookmarkNodes $x.children }
    }
    return $n
}

function Set-BookmarkIds {
    param($Nodes, [ref]$Next)
    foreach ($x in @($Nodes)) {
        $x['id'] = [string]$Next.Value
        $Next.Value++
        if ($x.type -eq 'folder') { Set-BookmarkIds $x.children $Next }
    }
}

function Update-Md5 {
    param($Md5, [byte[]]$Bytes)
    if ($Bytes.Length -gt 0) { [void]$Md5.TransformBlock($Bytes, 0, $Bytes.Length, $null, 0) }
}

function Update-BookmarkChecksum {
    # Odtwarza algorytm sumy kontrolnej Chromium (bookmark_codec.cc): id, tytuł (UTF-16), typ, url.
    param($Md5, $Node)
    Update-Md5 $Md5 ([Text.Encoding]::UTF8.GetBytes([string]$Node.id))
    Update-Md5 $Md5 ([Text.Encoding]::Unicode.GetBytes([string]$Node.name))
    if ($Node.type -eq 'url') {
        Update-Md5 $Md5 ([Text.Encoding]::UTF8.GetBytes('url'))
        Update-Md5 $Md5 ([Text.Encoding]::UTF8.GetBytes([string]$Node.url))
    }
    else {
        Update-Md5 $Md5 ([Text.Encoding]::UTF8.GetBytes('folder'))
        foreach ($c in @($Node.children)) { Update-BookmarkChecksum $Md5 $c }
    }
}

function Get-BookmarksChecksum {
    param($Roots)
    $md5 = [Security.Cryptography.MD5]::Create()
    foreach ($r in @($Roots.bookmark_bar, $Roots.other, $Roots.synced)) { Update-BookmarkChecksum $md5 $r }
    [void]$md5.TransformFinalBlock((New-Object byte[] 0), 0, 0)
    return (($md5.Hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Import-BraveBookmarks {
    param(
        [Parameter(Mandatory = $true)][string]$SourceFile,
        [string]$Profile = 'Default'
    )
    if (-not (Test-Path -LiteralPath $SourceFile)) { throw "Brak pliku zakładek: $SourceFile" }
    if (Get-Process brave -ErrorAction SilentlyContinue) { throw 'Brave jest uruchomiony – zamknij go przed importem.' }

    $raw = Get-Content -LiteralPath $SourceFile -Raw -Encoding UTF8
    if ($raw.TrimStart().StartsWith('{')) { $imp = Read-ChromiumBookmarksJson $raw }
    else { $imp = ConvertFrom-NetscapeBookmarks $raw }
    $count = (Measure-BookmarkNodes $imp.Bar) + (Measure-BookmarkNodes $imp.Other)
    if ($count -eq 0) { throw 'W pliku nie znaleziono żadnych zakładek (obsługiwane: eksport HTML lub plik „Bookmarks” z profilu).' }

    $profileDir = Join-Path $Script:BraveUserData $Profile
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    $target = Join-Path $profileDir 'Bookmarks'
    $existing = $null
    if (Test-Path $target) {
        Copy-Item -LiteralPath $target -Destination ($target + '.freshsetup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak') -Force
        try { $existing = Read-ChromiumBookmarksJson (Get-Content -LiteralPath $target -Raw -Encoding UTF8) } catch { $existing = $null }
    }

    $bar = New-Object System.Collections.ArrayList
    $other = New-Object System.Collections.ArrayList
    if ($existing -and ((Measure-BookmarkNodes $existing.Bar) + (Measure-BookmarkNodes $existing.Other)) -gt 0) {
        foreach ($n in $existing.Bar)   { [void]$bar.Add($n) }
        foreach ($n in $existing.Other) { [void]$other.Add($n) }
        $folder = New-BookmarkNode -Name ('Zaimportowane ' + (Get-Date -Format 'yyyy-MM-dd'))
        foreach ($n in $imp.Bar) { [void]$folder.children.Add($n) }
        if ($imp.Other.Count -gt 0) {
            $sub = New-BookmarkNode -Name 'Pozostałe zakładki'
            foreach ($n in $imp.Other) { [void]$sub.children.Add($n) }
            [void]$folder.children.Add($sub)
        }
        [void]$bar.Add($folder)
        $mode = 'scalono z istniejącymi zakładkami'
    }
    else {
        $bar = $imp.Bar
        $other = $imp.Other
        $mode = 'utworzono nowy plik zakładek'
    }

    $roots = [ordered]@{
        bookmark_bar = [ordered]@{ children = $bar;   date_added = (ConvertTo-ChromeTime); date_last_used = '0'; date_modified = '0'; guid = $Script:BookmarkRootGuids.bar;    id = '1'; name = 'Bookmarks bar';    type = 'folder' }
        other        = [ordered]@{ children = $other; date_added = (ConvertTo-ChromeTime); date_last_used = '0'; date_modified = '0'; guid = $Script:BookmarkRootGuids.other;  id = '2'; name = 'Other bookmarks';  type = 'folder' }
        synced       = [ordered]@{ children = (New-Object System.Collections.ArrayList); date_added = (ConvertTo-ChromeTime); date_last_used = '0'; date_modified = '0'; guid = $Script:BookmarkRootGuids.synced; id = '3'; name = 'Mobile bookmarks'; type = 'folder' }
    }
    $next = 4
    Set-BookmarkIds $bar ([ref]$next)
    Set-BookmarkIds $other ([ref]$next)
    $doc = [ordered]@{ checksum = (Get-BookmarksChecksum $roots); roots = $roots; version = 1 }
    $json = $doc | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($target, $json, (New-Object Text.UTF8Encoding $false))
    return @{ Count = $count; Mode = $mode; Target = $target }
}
