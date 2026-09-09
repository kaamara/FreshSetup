#requires -Version 5.1
<#
    FreshSetup – szybka konfiguracja świeżo zainstalowanego Windows 11
    ------------------------------------------------------------------
    Uruchamiaj przez FreshSetup.bat (poprosi o uprawnienia administratora).
    Kolumny: Aplikacje (winget) | Ustawienia Windows | Brave | Pliki i zakładki.
    Jedno kliknięcie „Start” wykonuje wszystko, co zaznaczone.

    Zmienne do testów: FRESHSETUP_NOELEVATE=1 pomija podnoszenie uprawnień; -AutoCloseSeconds N zamyka okno po N sekundach.
#>
param([int]$AutoCloseSeconds = 0)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------------------------------------------------------------- uprawnienia administratora
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$Script:IsAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $Script:IsAdmin -and $env:FRESHSETUP_NOELEVATE -ne '1') {
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$($MyInvocation.MyCommand.Path)`"")
    try { Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs -Verb RunAs | Out-Null } catch { }
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
try {
    Add-Type -Namespace FreshSetup -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
    [FreshSetup.Dpi]::SetProcessDPIAware() | Out-Null
} catch { }
try {
    Add-Type -Namespace FreshSetup -Name Native -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);'
} catch { }

function Set-ScrollTop {
    # Przewija RichTextBox na samą górę (ScrollToCaret bywa ignorowane, gdy kontrolka nie ma fokusu): WM_VSCROLL + SB_TOP.
    param([Windows.Forms.RichTextBox]$Box)
    try { [void][FreshSetup.Native]::SendMessage($Box.Handle, 0x115, [IntPtr]6, [IntPtr]::Zero) } catch { }
}

foreach ($lib in 'SFTA', 'Common', 'Winget', 'Catalog', 'Tweaks', 'Brave', 'Bookmarks', 'Payload', 'Hardware') {
    . (Join-Path $Script:AppRoot "lib\$lib.ps1")
}
Initialize-Log | Out-Null

# ---------------------------------------------------------------- motyw i pomocnicze kontrolki
$Script:Theme = @{
    Bg     = [Drawing.Color]::FromArgb(28, 28, 32)
    Panel  = [Drawing.Color]::FromArgb(40, 40, 46)
    Fg     = [Drawing.Color]::FromArgb(236, 236, 240)
    Muted  = [Drawing.Color]::FromArgb(150, 150, 160)
    Accent = [Drawing.Color]::FromArgb(251, 84, 43)
    Ok     = [Drawing.Color]::FromArgb(110, 205, 120)
    Warn   = [Drawing.Color]::FromArgb(240, 190, 80)
    Err    = [Drawing.Color]::FromArgb(240, 95, 95)
    Border = [Drawing.Color]::FromArgb(70, 70, 80)
}
$Script:Ui = @{}
$Script:Busy = $false
$Script:SuppressItemCheck = $false

function New-Label {
    param([string]$Text, [Drawing.Font]$Font = $null, [Drawing.Color]$Color = $Script:Theme.Fg, [switch]$Wrap)
    $l = New-Object Windows.Forms.Label
    $l.Text = $Text
    $l.ForeColor = $Color
    $l.AutoSize = -not $Wrap
    if ($Font) { $l.Font = $Font }
    $l.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 2)
    return $l
}

function New-Button {
    param([string]$Text, [int]$Width = 120, [switch]$Primary)
    $b = New-Object Windows.Forms.Button
    $b.Text = $Text
    $b.Size = [Drawing.Size]::new($Width, 34)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderColor = $Script:Theme.Border
    $b.FlatAppearance.BorderSize = 1
    $b.BackColor = if ($Primary) { $Script:Theme.Accent } else { $Script:Theme.Panel }
    $b.ForeColor = $Script:Theme.Fg
    $b.Cursor = 'Hand'
    $b.Margin = [Windows.Forms.Padding]::new(0, 0, 8, 0)
    if ($Primary) { $b.Font = [Drawing.Font]::new('Segoe UI Semibold', 10.5) }
    return $b
}

function New-CheckList {
    $list = New-Object Windows.Forms.CheckedListBox
    $list.Dock = 'Fill'
    $list.CheckOnClick = $true
    $list.BorderStyle = 'FixedSingle'
    $list.BackColor = $Script:Theme.Panel
    $list.ForeColor = $Script:Theme.Fg
    $list.IntegralHeight = $false
    $list.HorizontalScrollbar = $true
    $list.Margin = [Windows.Forms.Padding]::new(0)
    $list.Tag = @()
    return $list
}

function New-RowStyle { param([string]$Type, [float]$Value = 0)
    if ($Type -eq 'Percent') { return [Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, $Value) }
    return [Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize)
}
function New-ColStyle { param([string]$Type, [float]$Value = 0)
    if ($Type -eq 'Percent') { return [Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, $Value) }
    return [Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::AutoSize)
}

function Show-Description {
    param($Item)
    if (-not $Item) { return }
    $text = ''
    if ($Item.Description) { $text = "$($Item.Name) — $($Item.Description)" }
    elseif ($Item.type) {
        $srcInfo = if ($Item.type -eq 'url') { $Item.source } else { "payload\$($Item.source)" }
        $text = "$(Format-PayloadItem $Item)`nŹródło: $srcInfo   |   Miejsce docelowe: $($Item.destination)"
    }
    $Script:Ui.Desc.Text = $text
}

function Get-CheckedItems {
    param([Windows.Forms.CheckedListBox]$List)
    $result = @()
    foreach ($i in $List.CheckedIndices) { $result += , $List.Tag[$i] }
    return $result
}

# ---------------------------------------------------------------- kolumna z listą wyboru
function New-CheckColumn {
    param([string]$Title, [array]$Items, [scriptblock]$Display)
    $panel = New-Object Windows.Forms.TableLayoutPanel
    $panel.Dock = 'Fill'; $panel.ColumnCount = 1; $panel.RowCount = 3
    $panel.Margin = [Windows.Forms.Padding]::new(4, 0, 4, 0)
    [void]$panel.RowStyles.Add((New-RowStyle Auto))
    [void]$panel.RowStyles.Add((New-RowStyle Percent 100))
    [void]$panel.RowStyles.Add((New-RowStyle Auto))

    $lblTitle = New-Label -Text $Title -Font ([Drawing.Font]::new('Segoe UI Semibold', 11))
    $lblTitle.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 4)

    $list = New-CheckList
    $list.Tag = @($Items)
    foreach ($it in $Items) {
        $text = if ($Display) { & $Display $it } else { $it.Name }
        [void]$list.Items.Add($text, [bool]$it.Default)
    }
    $list.Add_SelectedIndexChanged({ param($s, $e)
        $i = $s.SelectedIndex
        if ($i -ge 0 -and $i -lt $s.Tag.Count) { Show-Description $s.Tag[$i] }
    })

    $links = New-Object Windows.Forms.FlowLayoutPanel
    $links.AutoSize = $true; $links.WrapContents = $false
    $links.Margin = [Windows.Forms.Padding]::new(0, 4, 0, 0)
    foreach ($def in @(@('wszystko', 'all'), @('nic', 'none'), @('domyślne', 'default'))) {
        $ll = New-Object Windows.Forms.LinkLabel
        $ll.Text = $def[0]; $ll.AutoSize = $true; $ll.Tag = $def[1]
        $ll.LinkColor = $Script:Theme.Accent; $ll.ActiveLinkColor = $Script:Theme.Fg; $ll.VisitedLinkColor = $Script:Theme.Accent
        $ll.Margin = [Windows.Forms.Padding]::new(0, 0, 14, 0)
        $ll.Add_LinkClicked({ param($s, $e)
            $mode = $s.Tag
            for ($i = 0; $i -lt $list.Items.Count; $i++) {
                $val = switch ($mode) { 'all' { $true } 'none' { $false } default { [bool]$list.Tag[$i].Default } }
                $list.SetItemChecked($i, $val)
            }
        }.GetNewClosure())
        $links.Controls.Add($ll)
    }

    $panel.Controls.Add($lblTitle, 0, 0)
    $panel.Controls.Add($list, 0, 1)
    $panel.Controls.Add($links, 0, 2)
    return @{ Panel = $panel; List = $list }
}

# ---------------------------------------------------------------- kolumna „Pliki i zakładki”
function Show-DestinationDialog {
    # Zwraca @{ Destination = '...'; Url = '...' } albo $null po anulowaniu.
    param([switch]$AskUrl)
    $f = New-Object Windows.Forms.Form
    $f.Text = if ($AskUrl) { 'Dodaj link do pobrania' } else { 'Miejsce docelowe' }
    $f.Size = [Drawing.Size]::new(560, $(if ($AskUrl) { 300 } else { 240 }))
    $f.StartPosition = 'CenterParent'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.BackColor = $Script:Theme.Bg; $f.ForeColor = $Script:Theme.Fg; $f.Font = $Script:Ui.Form.Font

    $y = 16
    $txtUrl = $null
    if ($AskUrl) {
        $lu = New-Label -Text 'Adres URL pliku do pobrania na nowym komputerze:'
        $lu.Location = [Drawing.Point]::new(16, $y); $f.Controls.Add($lu)
        $txtUrl = New-Object Windows.Forms.TextBox
        $txtUrl.Location = [Drawing.Point]::new(16, $y + 24); $txtUrl.Width = 510
        $txtUrl.BackColor = $Script:Theme.Panel; $txtUrl.ForeColor = $Script:Theme.Fg; $txtUrl.BorderStyle = 'FixedSingle'
        $f.Controls.Add($txtUrl)
        $y += 62
    }
    $lbl = New-Label -Text 'Gdzie skopiować na nowym komputerze?'
    $lbl.Location = [Drawing.Point]::new(16, $y); $f.Controls.Add($lbl)

    $combo = New-Object Windows.Forms.ComboBox
    $combo.DropDownStyle = 'DropDownList'; $combo.Location = [Drawing.Point]::new(16, $y + 24); $combo.Width = 510
    $combo.BackColor = $Script:Theme.Panel; $combo.ForeColor = $Script:Theme.Fg; $combo.FlatStyle = 'Flat'
    foreach ($p in $Script:DestinationPresets) { [void]$combo.Items.Add("$($p.Name)   ($($p.Path))") }
    [void]$combo.Items.Add('Inna ścieżka…')
    $combo.SelectedIndex = 0
    $f.Controls.Add($combo)

    $txt = New-Object Windows.Forms.TextBox
    $txt.Location = [Drawing.Point]::new(16, $y + 56); $txt.Width = 510; $txt.ReadOnly = $true
    $txt.Text = $Script:DestinationPresets[0].Path
    $txt.BackColor = $Script:Theme.Panel; $txt.ForeColor = $Script:Theme.Fg; $txt.BorderStyle = 'FixedSingle'
    $f.Controls.Add($txt)
    $combo.Add_SelectedIndexChanged({
        $i = $combo.SelectedIndex
        if ($i -lt $Script:DestinationPresets.Count) { $txt.ReadOnly = $true; $txt.Text = $Script:DestinationPresets[$i].Path }
        else { $txt.ReadOnly = $false; $txt.Text = ''; $txt.Focus() }
    }.GetNewClosure())

    $hint = New-Label -Text 'Można używać zmiennych środowiskowych, np. %USERPROFILE%\Desktop lub D:\Gry' -Color $Script:Theme.Muted
    $hint.Location = [Drawing.Point]::new(16, $y + 84); $f.Controls.Add($hint)

    $ok = New-Button -Text 'OK' -Width 100 -Primary
    $ok.Location = [Drawing.Point]::new(318, $y + 118); $ok.DialogResult = 'OK'; $f.Controls.Add($ok)
    $cancel = New-Button -Text 'Anuluj' -Width 100
    $cancel.Location = [Drawing.Point]::new(426, $y + 118); $cancel.DialogResult = 'Cancel'; $f.Controls.Add($cancel)
    $f.AcceptButton = $ok; $f.CancelButton = $cancel

    if ($f.ShowDialog($Script:Ui.Form) -ne 'OK') { return $null }
    $dest = $txt.Text.Trim()
    if (-not $dest) { return $null }
    $url = if ($txtUrl) { $txtUrl.Text.Trim() } else { $null }
    if ($AskUrl -and ($url -notmatch '^https?://')) {
        [Windows.Forms.MessageBox]::Show('Podaj poprawny adres zaczynający się od http:// lub https://', 'FreshSetup', 'OK', 'Warning') | Out-Null
        return $null
    }
    return @{ Destination = $dest; Url = $url }
}

function Update-FilesList {
    $list = $Script:Ui.Files
    $m = Get-Manifest
    $Script:SuppressItemCheck = $true
    try {
        $list.Items.Clear()
        $list.Tag = @($m.items)
        foreach ($it in @($m.items)) { [void]$list.Items.Add((Format-PayloadItem $it), [bool]$it.enabled) }
    }
    finally { $Script:SuppressItemCheck = $false }
    if ($m.bookmarks) {
        $Script:Ui.BookmarkLabel.Text = '  ' + (Split-Path $m.bookmarks -Leaf)
        $Script:Ui.BookmarkLabel.ForeColor = $Script:Theme.Ok
    }
    else {
        $Script:Ui.BookmarkLabel.Text = '  brak pliku – kliknij „Wybierz…”'
        $Script:Ui.BookmarkLabel.ForeColor = $Script:Theme.Muted
    }
}

function New-FilesColumn {
    $panel = New-Object Windows.Forms.TableLayoutPanel
    $panel.Dock = 'Fill'; $panel.ColumnCount = 1; $panel.RowCount = 5
    $panel.Margin = [Windows.Forms.Padding]::new(4, 0, 4, 0)
    [void]$panel.RowStyles.Add((New-RowStyle Auto))
    [void]$panel.RowStyles.Add((New-RowStyle Percent 100))
    [void]$panel.RowStyles.Add((New-RowStyle Auto))
    [void]$panel.RowStyles.Add((New-RowStyle Auto))
    [void]$panel.RowStyles.Add((New-RowStyle Auto))

    $lblTitle = New-Label -Text 'Pliki i zakładki' -Font ([Drawing.Font]::new('Segoe UI Semibold', 11))
    $lblTitle.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 4)

    $list = New-CheckList
    $list.Add_SelectedIndexChanged({ param($s, $e)
        $i = $s.SelectedIndex
        if ($i -ge 0 -and $i -lt $s.Tag.Count) { Show-Description $s.Tag[$i] }
    })
    $list.Add_ItemCheck({ param($s, $e)
        if ($Script:SuppressItemCheck) { return }
        if ($e.Index -ge 0 -and $e.Index -lt $s.Tag.Count) {
            Set-PayloadItemEnabled -Id $s.Tag[$e.Index].id -Enabled ($e.NewValue -eq 'Checked')
        }
    })

    $btns = New-Object Windows.Forms.FlowLayoutPanel
    $btns.AutoSize = $true; $btns.WrapContents = $true
    $btns.Margin = [Windows.Forms.Padding]::new(0, 6, 0, 0)
    $bFile = New-Button -Text '+ Plik' -Width 74
    $bDir  = New-Button -Text '+ Folder' -Width 84
    $bUrl  = New-Button -Text '+ Link' -Width 72
    $bDel  = New-Button -Text 'Usuń' -Width 68
    foreach ($b in $bFile, $bDir, $bUrl, $bDel) { $b.Margin = [Windows.Forms.Padding]::new(0, 0, 6, 0); $btns.Controls.Add($b) }

    $bFile.Add_Click({
        $dlg = New-Object Windows.Forms.OpenFileDialog
        $dlg.Multiselect = $true; $dlg.Title = 'Wybierz pliki do skopiowania na nowy komputer'
        if ($dlg.ShowDialog($Script:Ui.Form) -ne 'OK') { return }
        $r = Show-DestinationDialog
        if (-not $r) { return }
        foreach ($f in $dlg.FileNames) {
            try { Add-PayloadItem -Type file -Source $f -Destination $r.Destination | Out-Null; Write-Log "Dodano plik: $f  →  $($r.Destination)" Ok }
            catch { Write-Log "Nie udało się dodać $f : $($_.Exception.Message)" Error }
        }
        Update-FilesList
    })
    $bDir.Add_Click({
        $dlg = New-Object Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Wybierz folder do skopiowania na nowy komputer'
        if ($dlg.ShowDialog($Script:Ui.Form) -ne 'OK') { return }
        $r = Show-DestinationDialog
        if (-not $r) { return }
        try { Add-PayloadItem -Type folder -Source $dlg.SelectedPath -Destination $r.Destination | Out-Null; Write-Log "Dodano folder: $($dlg.SelectedPath)  →  $($r.Destination)" Ok }
        catch { Write-Log "Nie udało się dodać folderu: $($_.Exception.Message)" Error }
        Update-FilesList
    })
    $bUrl.Add_Click({
        $r = Show-DestinationDialog -AskUrl
        if (-not $r) { return }
        try { Add-PayloadItem -Type url -Source $r.Url -Destination $r.Destination | Out-Null; Write-Log "Dodano link: $($r.Url)  →  $($r.Destination)" Ok }
        catch { Write-Log "Nie udało się dodać linku: $($_.Exception.Message)" Error }
        Update-FilesList
    })
    $bDel.Add_Click({
        $i = $Script:Ui.Files.SelectedIndex
        if ($i -lt 0) { return }
        $it = $Script:Ui.Files.Tag[$i]
        $ans = [Windows.Forms.MessageBox]::Show("Usunąć z listy: $($it.name)?", 'FreshSetup', 'YesNo', 'Question')
        if ($ans -ne 'Yes') { return }
        Remove-PayloadItem -Id $it.id
        Write-Log "Usunięto z listy: $($it.name)" Info
        Update-FilesList
    })

    $bmTitle = New-Label -Text 'Zakładki Brave (plik HTML z eksportu lub plik „Bookmarks”):' -Color $Script:Theme.Muted -Wrap
    $bmTitle.Dock = 'Top'; $bmTitle.Height = 20; $bmTitle.AutoEllipsis = $true
    $bmTitle.Margin = [Windows.Forms.Padding]::new(0, 10, 0, 2)

    $bmRow = New-Object Windows.Forms.TableLayoutPanel
    $bmRow.AutoSize = $false; $bmRow.Height = 36; $bmRow.ColumnCount = 3; $bmRow.RowCount = 1; $bmRow.Dock = 'Top'
    $bmRow.Margin = [Windows.Forms.Padding]::new(0)
    [void]$bmRow.ColumnStyles.Add((New-ColStyle Percent 100))
    [void]$bmRow.ColumnStyles.Add((New-ColStyle Auto))
    [void]$bmRow.ColumnStyles.Add((New-ColStyle Auto))
    $bmLabel = New-Object Windows.Forms.Label
    $bmLabel.AutoSize = $false; $bmLabel.Dock = 'Fill'; $bmLabel.AutoEllipsis = $true
    $bmLabel.TextAlign = 'MiddleLeft'; $bmLabel.BackColor = $Script:Theme.Panel; $bmLabel.ForeColor = $Script:Theme.Muted
    $bmLabel.Margin = [Windows.Forms.Padding]::new(0, 1, 6, 1)
    $bPick = New-Button -Text 'Wybierz…' -Width 90
    $bClr  = New-Button -Text 'Usuń' -Width 60
    $bPick.Margin = [Windows.Forms.Padding]::new(0, 1, 6, 1); $bClr.Margin = [Windows.Forms.Padding]::new(0, 1, 0, 1)
    $bmRow.Controls.Add($bmLabel, 0, 0); $bmRow.Controls.Add($bPick, 1, 0); $bmRow.Controls.Add($bClr, 2, 0)

    $bPick.Add_Click({
        $dlg = New-Object Windows.Forms.OpenFileDialog
        $dlg.Title = 'Wybierz plik zakładek (eksport HTML z Brave/Chrome/Firefox lub plik „Bookmarks”)'
        $dlg.Filter = 'Zakładki (*.html;*.htm;Bookmarks;*.json)|*.html;*.htm;Bookmarks;*.json|Wszystkie pliki (*.*)|*.*'
        if ($dlg.ShowDialog($Script:Ui.Form) -ne 'OK') { return }
        try { $rel = Set-PayloadBookmarks -Source $dlg.FileName; Write-Log "Plik zakładek zapisany w payload\$rel" Ok }
        catch { Write-Log "Nie udało się skopiować pliku zakładek: $($_.Exception.Message)" Error }
        Update-FilesList
    })
    $bClr.Add_Click({ Clear-PayloadBookmarks; Write-Log 'Usunięto plik zakładek z payload.' Info; Update-FilesList })

    $panel.Controls.Add($lblTitle, 0, 0)
    $panel.Controls.Add($list, 0, 1)
    $panel.Controls.Add($btns, 0, 2)
    $panel.Controls.Add($bmTitle, 0, 3)
    $panel.Controls.Add($bmRow, 0, 4)
    return @{ Panel = $panel; List = $list; BookmarkLabel = $bmLabel }
}

# ---------------------------------------------------------------- główne okno
$form = New-Object Windows.Forms.Form
$form.Text = 'FreshSetup – konfiguracja nowego komputera'
$wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Size = [Drawing.Size]::new([Math]::Min(1720, $wa.Width - 40), [Math]::Min(900, $wa.Height - 40))
$form.MinimumSize = [Drawing.Size]::new(1150, 660)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $Script:Theme.Bg
$form.ForeColor = $Script:Theme.Fg
$form.Font = [Drawing.Font]::new('Segoe UI', 9.5)
$Script:Ui.Form = $form

$root = New-Object Windows.Forms.TableLayoutPanel
$root.Dock = 'Fill'; $root.ColumnCount = 1; $root.RowCount = 7
$root.Padding = [Windows.Forms.Padding]::new(14, 10, 8, 10)
$root.Margin = [Windows.Forms.Padding]::new(0)
[void]$root.RowStyles.Add((New-RowStyle Auto))        # nagłówek
[void]$root.RowStyles.Add((New-RowStyle Percent 60))  # listy
[void]$root.RowStyles.Add((New-RowStyle Auto))        # opis
[void]$root.RowStyles.Add((New-RowStyle Auto))        # opcje
[void]$root.RowStyles.Add((New-RowStyle Auto))        # postęp
[void]$root.RowStyles.Add((New-RowStyle Percent 40))  # log
[void]$root.RowStyles.Add((New-RowStyle Auto))        # przyciski

# nagłówek
$header = New-Object Windows.Forms.TableLayoutPanel
$header.AutoSize = $true; $header.ColumnCount = 2; $header.RowCount = 1; $header.Dock = 'Top'
$header.Margin = [Windows.Forms.Padding]::new(0)
[void]$header.ColumnStyles.Add((New-ColStyle Percent 100))
[void]$header.ColumnStyles.Add((New-ColStyle Auto))
$hLeft = New-Object Windows.Forms.FlowLayoutPanel
$hLeft.FlowDirection = 'TopDown'; $hLeft.AutoSize = $true; $hLeft.WrapContents = $false; $hLeft.Margin = [Windows.Forms.Padding]::new(0)
$hLeft.Controls.Add((New-Label -Text 'FreshSetup' -Font ([Drawing.Font]::new('Segoe UI Semibold', 18))))
$hLeft.Controls.Add((New-Label -Text 'Aplikacje przez winget, prywatność Windows i Brave, kopiowanie plików i zakładek – wszystko jednym kliknięciem.' -Color $Script:Theme.Muted))
$adminText = if ($Script:IsAdmin) { 'administrator' } else { 'BEZ uprawnień administratora (tryb testowy)' }
$hRight = New-Label -Text ("Użytkownik: $env:USERNAME  •  $adminText`nLog: $Script:LogFile") -Color $Script:Theme.Muted
$hRight.TextAlign = 'TopRight'
$header.Controls.Add($hLeft, 0, 0)
$header.Controls.Add($hRight, 1, 0)

# kolumny
$cols = New-Object Windows.Forms.TableLayoutPanel
$cols.Dock = 'Fill'; $cols.ColumnCount = 4; $cols.RowCount = 1
$cols.Margin = [Windows.Forms.Padding]::new(0, 10, 0, 4)
foreach ($w in 19, 31, 25, 25) { [void]$cols.ColumnStyles.Add((New-ColStyle Percent $w)) }
$appsCol  = New-CheckColumn -Title 'Aplikacje (winget)' -Items $Script:AppCatalog
$winCol   = New-CheckColumn -Title 'Ustawienia Windows' -Items $Script:TweakCatalog -Display { param($it) "[$($it.Group)] $($it.Name)" }
$braveCol = New-CheckColumn -Title 'Brave' -Items $Script:BraveCatalog
$filesCol = New-FilesColumn
$cols.Controls.Add($appsCol.Panel, 0, 0)
$cols.Controls.Add($winCol.Panel, 1, 0)
$cols.Controls.Add($braveCol.Panel, 2, 0)
$cols.Controls.Add($filesCol.Panel, 3, 0)
$Script:Ui.Apps = $appsCol.List
$Script:Ui.Tweaks = $winCol.List
$Script:Ui.Brave = $braveCol.List
$Script:Ui.Files = $filesCol.List
$Script:Ui.BookmarkLabel = $filesCol.BookmarkLabel

# opis
$desc = New-Object Windows.Forms.Label
$desc.AutoSize = $false; $desc.Dock = 'Top'; $desc.Height = 46
$desc.ForeColor = $Script:Theme.Muted
$desc.Text = 'Kliknij pozycję na liście, aby zobaczyć jej opis. Zaznaczone pozycje zostaną wykonane po naciśnięciu „Start”.'
$desc.Margin = [Windows.Forms.Padding]::new(4, 4, 4, 0)
$Script:Ui.Desc = $desc

# opcje
$opts = New-Object Windows.Forms.FlowLayoutPanel
$opts.AutoSize = $true; $opts.WrapContents = $true; $opts.Margin = [Windows.Forms.Padding]::new(4, 2, 4, 2)
$cbSkip = New-Object Windows.Forms.CheckBox
$cbSkip.Text = 'Pomiń aplikacje już zainstalowane'; $cbSkip.Checked = $true; $cbSkip.AutoSize = $true
$cbSkip.Margin = [Windows.Forms.Padding]::new(0, 0, 24, 0)
$cbExplorer = New-Object Windows.Forms.CheckBox
$cbExplorer.Text = 'Zrestartuj Eksploratora po zmianach ustawień'; $cbExplorer.Checked = $true; $cbExplorer.AutoSize = $true
$opts.Controls.Add($cbSkip); $opts.Controls.Add($cbExplorer)
$Script:Ui.SkipInstalled = $cbSkip
$Script:Ui.RestartExplorer = $cbExplorer

# postęp
$prog = New-Object Windows.Forms.TableLayoutPanel
$prog.AutoSize = $true; $prog.ColumnCount = 1; $prog.RowCount = 2; $prog.Dock = 'Top'
$prog.Margin = [Windows.Forms.Padding]::new(4, 4, 4, 4)
[void]$prog.RowStyles.Add((New-RowStyle Auto))
[void]$prog.RowStyles.Add((New-RowStyle Auto))
$status = New-Label -Text 'Gotowy.' -Color $Script:Theme.Fg
$bar = New-Object Windows.Forms.ProgressBar
$bar.Dock = 'Top'; $bar.Height = 12; $bar.Style = 'Continuous'; $bar.Margin = [Windows.Forms.Padding]::new(0, 4, 0, 0)
$prog.Controls.Add($status, 0, 0); $prog.Controls.Add($bar, 0, 1)
$Script:Ui.Status = $status
$Script:Ui.Progress = $bar

# log
$rtb = New-Object Windows.Forms.RichTextBox
$rtb.Dock = 'Fill'; $rtb.ReadOnly = $true; $rtb.BorderStyle = 'None'
$rtb.BackColor = $Script:Theme.Panel; $rtb.ForeColor = $Script:Theme.Fg
$rtb.Font = [Drawing.Font]::new('Consolas', 9.25)
$rtb.WordWrap = $false; $rtb.ScrollBars = 'Both'; $rtb.DetectUrls = $false
$rtb.Margin = [Windows.Forms.Padding]::new(4, 2, 4, 6)
$Script:Ui.Log = $rtb
$Script:LogSink = {
    param($line, $level)
    $color = switch ($level) {
        'Ok'    { $Script:Theme.Ok }
        'Warn'  { $Script:Theme.Warn }
        'Error' { $Script:Theme.Err }
        'Dim'   { $Script:Theme.Muted }
        'Step'  { $Script:Theme.Accent }
        default { $Script:Theme.Fg }
    }
    $r = $Script:Ui.Log
    $r.SelectionStart = $r.TextLength; $r.SelectionLength = 0
    $r.SelectionColor = $color
    $r.AppendText($line + "`r`n")
    $r.SelectionStart = $r.TextLength
    $r.ScrollToCaret()
    Invoke-UiPump
}

# przyciski
$btnRow = New-Object Windows.Forms.FlowLayoutPanel
$btnRow.AutoSize = $true; $btnRow.FlowDirection = 'RightToLeft'; $btnRow.Dock = 'Top'; $btnRow.WrapContents = $false
$btnRow.Margin = [Windows.Forms.Padding]::new(0, 4, 0, 0)
$btnStart   = New-Button -Text '▶  Start' -Width 180 -Primary
$btnLog     = New-Button -Text 'Otwórz log' -Width 110
$btnPayload = New-Button -Text 'Folder payload' -Width 130
$btnUnlock  = New-Button -Text 'Usuń polityki Brave' -Width 160
$btnClose   = New-Button -Text 'Zamknij' -Width 100
$btnStart.Margin = [Windows.Forms.Padding]::new(0)
foreach ($b in $btnStart, $btnLog, $btnPayload, $btnUnlock, $btnClose) { $b.Margin = [Windows.Forms.Padding]::new(8, 0, 0, 0); $btnRow.Controls.Add($b) }
$Script:Ui.Start = $btnStart
$Script:Ui.Buttons = @($btnLog, $btnPayload, $btnUnlock)

$root.Controls.Add($header, 0, 0)
$root.Controls.Add($cols, 0, 1)
$root.Controls.Add($desc, 0, 2)
$root.Controls.Add($opts, 0, 3)
$root.Controls.Add($prog, 0, 4)
$root.Controls.Add($rtb, 0, 5)
$root.Controls.Add($btnRow, 0, 6)

# ---------------------------------------------------------------- panel „Podzespoły” (prawa strona)
$Script:HwFont     = [Drawing.Font]::new('Segoe UI', 9)
$Script:HwFontBold = [Drawing.Font]::new('Segoe UI Semibold', 10)
$Script:HardwareText = ''
$hwPanel = New-Object Windows.Forms.TableLayoutPanel
$hwPanel.Dock = 'Fill'; $hwPanel.ColumnCount = 1; $hwPanel.RowCount = 3
$hwPanel.Margin = [Windows.Forms.Padding]::new(0, 10, 0, 10)
[void]$hwPanel.RowStyles.Add((New-RowStyle Auto))
[void]$hwPanel.RowStyles.Add((New-RowStyle Percent 100))
[void]$hwPanel.RowStyles.Add((New-RowStyle Auto))
$hwTitle = New-Label -Text 'Podzespoły' -Font ([Drawing.Font]::new('Segoe UI Semibold', 11))
$hwTitle.Margin = [Windows.Forms.Padding]::new(0, 0, 0, 4)
$hwBox = New-Object Windows.Forms.RichTextBox
$hwBox.Dock = 'Fill'; $hwBox.ReadOnly = $true; $hwBox.BorderStyle = 'None'
$hwBox.BackColor = $Script:Theme.Panel; $hwBox.ForeColor = $Script:Theme.Fg; $hwBox.Font = $Script:HwFont
$hwBox.WordWrap = $true; $hwBox.ScrollBars = 'Vertical'; $hwBox.DetectUrls = $false
$hwBox.Margin = [Windows.Forms.Padding]::new(0)
$hwBtns = New-Object Windows.Forms.FlowLayoutPanel
$hwBtns.AutoSize = $true; $hwBtns.WrapContents = $true; $hwBtns.Margin = [Windows.Forms.Padding]::new(0, 6, 0, 0)
$bHwRefresh = New-Button -Text 'Odśwież' -Width 90
$bHwCopy    = New-Button -Text 'Kopiuj' -Width 80
$bHwSave    = New-Button -Text 'Zapisz…' -Width 90
foreach ($b in $bHwRefresh, $bHwCopy, $bHwSave) { $b.Margin = [Windows.Forms.Padding]::new(0, 0, 6, 0); $hwBtns.Controls.Add($b) }
$hwPanel.Controls.Add($hwTitle, 0, 0); $hwPanel.Controls.Add($hwBox, 0, 1); $hwPanel.Controls.Add($hwBtns, 0, 2)
$Script:Ui.Hw = $hwBox
$Script:Ui.HwButtons = @($bHwRefresh, $bHwCopy, $bHwSave)

$outer = New-Object Windows.Forms.TableLayoutPanel
$outer.Dock = 'Fill'; $outer.ColumnCount = 2; $outer.RowCount = 1
$outer.Padding = [Windows.Forms.Padding]::new(0, 0, 14, 0)
[void]$outer.ColumnStyles.Add((New-ColStyle Percent 100))
[void]$outer.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute, 380))
$outer.Controls.Add($root, 0, 0)
$outer.Controls.Add($hwPanel, 1, 0)
$form.Controls.Add($outer)

function Add-HwText {
    param([string]$Text, [Drawing.Color]$Color, [switch]$Bold)
    $r = $Script:Ui.Hw
    $r.SelectionStart = $r.TextLength; $r.SelectionLength = 0
    $r.SelectionColor = $Color
    $r.SelectionFont = $(if ($Bold) { $Script:HwFontBold } else { $Script:HwFont })
    $r.AppendText($Text)
}

function Update-HardwarePanel {
    # Zbiera sekcje po kolei i dopisuje je do panelu na bieżąco (CIM/WMI potrafi zająć kilka sekund).
    $r = $Script:Ui.Hw
    foreach ($b in $Script:Ui.HwButtons) { $b.Enabled = $false }
    $startWasEnabled = $Script:Ui.Start.Enabled
    $Script:Ui.Start.Enabled = $false
    $r.Clear()
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("Podzespoły – $env:COMPUTERNAME – $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    $first = $true
    foreach ($s in $Script:HardwareSections) {
        if ($first) { $first = $false } else { Add-HwText -Text "`n" -Color $Script:Theme.Fg }
        Add-HwText -Text "$($s.Title)`n" -Color $Script:Theme.Accent -Bold
        [void]$sb.AppendLine(); [void]$sb.AppendLine("== $($s.Title) ==")
        Invoke-UiPump
        try {
            $rows = @(& $s.Get)
            if (-not $rows.Count) { Add-HwText -Text "  brak danych`n" -Color $Script:Theme.Muted; [void]$sb.AppendLine('  brak danych') }
            foreach ($row in $rows) {
                Add-HwText -Text "$($row[0]): " -Color $Script:Theme.Muted
                Add-HwText -Text "$($row[1])`n" -Color $Script:Theme.Fg
                [void]$sb.AppendLine("  $($row[0]): $($row[1])")
            }
        }
        catch {
            Add-HwText -Text "  błąd: $($_.Exception.Message)`n" -Color $Script:Theme.Err
            [void]$sb.AppendLine("  błąd: $($_.Exception.Message)")
        }
        Invoke-UiPump
    }
    $r.SelectionStart = 0; $r.SelectionLength = 0
    Set-ScrollTop -Box $r
    $Script:HardwareText = $sb.ToString()
    foreach ($b in $Script:Ui.HwButtons) { $b.Enabled = $true }
    if (-not $Script:Busy) { $Script:Ui.Start.Enabled = $startWasEnabled }
}

$bHwRefresh.Add_Click({ Update-HardwarePanel; Write-Log 'Spis podzespołów odświeżony.' Dim })
$bHwCopy.Add_Click({
    if ($Script:HardwareText) {
        [Windows.Forms.Clipboard]::SetText($Script:HardwareText)
        Write-Log 'Spis podzespołów skopiowany do schowka.' Ok
    }
})
$bHwSave.Add_Click({
    if (-not $Script:HardwareText) { return }
    $dlg = New-Object Windows.Forms.SaveFileDialog
    $dlg.Title = 'Zapisz spis podzespołów'
    $dlg.Filter = 'Plik tekstowy (*.txt)|*.txt|Wszystkie pliki (*.*)|*.*'
    $dlg.FileName = "podzespoly-$env:COMPUTERNAME-$(Get-Date -Format 'yyyy-MM-dd').txt"
    $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if ($dlg.ShowDialog($Script:Ui.Form) -ne 'OK') { return }
    try {
        [IO.File]::WriteAllText($dlg.FileName, $Script:HardwareText, (New-Object Text.UTF8Encoding $true))
        Write-Log "Spis podzespołów zapisany: $($dlg.FileName)" Ok
    }
    catch { Write-Log "Nie udało się zapisać spisu: $($_.Exception.Message)" Error }
})

# ---------------------------------------------------------------- logika uruchomienia
function Set-Status { param([string]$Text) $Script:Ui.Status.Text = $Text; Invoke-UiPump }

function Set-UiBusy {
    param([bool]$Busy)
    $Script:Busy = $Busy
    foreach ($c in $Script:Ui.Apps, $Script:Ui.Tweaks, $Script:Ui.Brave, $Script:Ui.Files, $Script:Ui.SkipInstalled, $Script:Ui.RestartExplorer) { $c.Enabled = -not $Busy }
    foreach ($b in $Script:Ui.Buttons) { $b.Enabled = -not $Busy }
    $Script:Ui.Start.Enabled = -not $Busy
    $Script:Ui.Start.Text = if ($Busy) { 'Pracuję…' } else { '▶  Start' }
    Invoke-UiPump
}

function Start-Setup {
    $ui = $Script:Ui
    $apps   = @(Get-CheckedItems $ui.Apps)
    $tweaks = @(Get-CheckedItems $ui.Tweaks)
    $brave  = @(Get-CheckedItems $ui.Brave)
    $files  = @(Get-CheckedItems $ui.Files)
    if ($apps.Count + $tweaks.Count + $brave.Count + $files.Count -eq 0) {
        [Windows.Forms.MessageBox]::Show('Nic nie zaznaczono.', 'FreshSetup', 'OK', 'Information') | Out-Null
        return
    }
    if (-not $Script:IsAdmin) {
        [Windows.Forms.MessageBox]::Show('Aplikacja działa bez uprawnień administratora – instalacje i część ustawień nie zadziała. Uruchom przez FreshSetup.bat.', 'FreshSetup', 'OK', 'Warning') | Out-Null
    }

    Set-UiBusy $true
    $Script:RebootRecommended = $false
    $Script:ExplorerRestartNeeded = $false
    $total = $apps.Count + $tweaks.Count + $brave.Count + $files.Count + [int]($apps.Count -gt 0)
    $ui.Progress.Maximum = [Math]::Max(1, $total); $ui.Progress.Value = 0
    $failed = New-Object System.Collections.Generic.List[string]
    $stepDone = { $Script:__done++; $Script:Ui.Progress.Value = [Math]::Min($Script:Ui.Progress.Maximum, $Script:__done); Invoke-UiPump }
    $Script:__done = 0

    Write-Log ('═' * 70) Dim
    Write-Log "Start: $($apps.Count) aplikacji, $($tweaks.Count) ustawień Windows, $($brave.Count) opcji Brave, $($files.Count) plików" Step

    # ---- 1. winget + aplikacje
    $winget = $null
    if ($apps.Count -gt 0) {
        Set-Status 'Sprawdzanie winget…'
        Write-Log 'Sprawdzanie winget' Step
        try { $winget = Initialize-Winget } catch { Write-Log "winget: $($_.Exception.Message)" Error }
        if (-not $winget) {
            Write-Log 'Brak winget – instalacja aplikacji pominięta.' Error
            foreach ($a in $apps) { $failed.Add($a.Name) }
        }
        & $stepDone
    }
    if ($winget) {
        $i = 0
        foreach ($app in $apps) {
            $i++
            Set-Status "Instalacja: $($app.Name) ($i/$($apps.Count))"
            Write-Log "Instalacja: $($app.Name) [$($app.WingetId)]" Step
            try {
                $r = Install-WingetApp -Winget $winget -App $app -SkipInstalled:([bool]$ui.SkipInstalled.Checked)
                if (-not $r.Success) { $failed.Add($app.Name) }
            }
            catch { Write-Log "  Błąd: $($_.Exception.Message)" Error; $failed.Add($app.Name) }
            & $stepDone
        }
    }

    # ---- 2. Brave: polityki, domyślna przeglądarka, zakładki
    if ($brave.Count -gt 0) {
        $policies = @($brave | Where-Object { $_.Kind -eq 'policy' })
        if ($policies.Count -gt 0) {
            Set-Status 'Polityki prywatności Brave…'
            Write-Log 'Brave: polityki prywatności (HKLM\SOFTWARE\Policies\BraveSoftware\Brave)' Step
            foreach ($p in $policies) {
                try { Set-BravePolicy -Item $p } catch { Write-Log "  ✗ $($p.Name): $($_.Exception.Message)" Error; $failed.Add($p.Name) }
                & $stepDone
            }
        }
        $def = $brave | Where-Object { $_.Kind -eq 'default' } | Select-Object -First 1
        if ($def) {
            Set-Status 'Ustawianie Brave jako domyślnej przeglądarki…'
            Write-Log 'Brave: domyślna przeglądarka' Step
            try { if (-not (Set-BraveDefaultBrowser)) { $failed.Add($def.Name) } }
            catch { Write-Log "  ✗ $($_.Exception.Message)" Error; $failed.Add($def.Name) }
            & $stepDone
        }
        $bm = $brave | Where-Object { $_.Kind -eq 'bookmarks' } | Select-Object -First 1
        if ($bm) {
            $manifest = Get-Manifest
            if (-not $manifest.bookmarks) {
                Write-Log 'Brave: zakładki – nie wybrano pliku (kolumna „Pliki i zakładki”), pomijam.' Warn
            }
            else {
                Set-Status 'Import zakładek do Brave…'
                Write-Log "Brave: import zakładek z payload\$($manifest.bookmarks)" Step
                try {
                    if (Get-Process brave -ErrorAction SilentlyContinue) {
                        $ans = [Windows.Forms.MessageBox]::Show("Brave jest uruchomiony. Aby zaimportować zakładki, trzeba go zamknąć.`n`nZamknąć Brave teraz?", 'FreshSetup', 'YesNo', 'Question')
                        if ($ans -eq 'Yes') {
                            Get-Process brave -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 2
                        }
                    }
                    $res = Import-BraveBookmarks -SourceFile (Join-Path $Script:PayloadDir $manifest.bookmarks)
                    Write-Log "  ✓ Zaimportowano $($res.Count) zakładek ($($res.Mode)) → $($res.Target)" Ok
                }
                catch { Write-Log "  ✗ Zakładki: $($_.Exception.Message)" Error; $failed.Add($bm.Name) }
            }
            & $stepDone
        }
    }

    # ---- 3. pliki / foldery / linki
    if ($files.Count -gt 0) {
        Write-Log 'Kopiowanie plików na komputer' Step
        foreach ($it in $files) {
            Set-Status "Kopiowanie: $($it.name)"
            try { $t = Copy-PayloadItem -Item $it; Write-Log "  ✓ $($it.name)  →  $t" Ok }
            catch { Write-Log "  ✗ $($it.name): $($_.Exception.Message)" Error; $failed.Add($it.name) }
            & $stepDone
        }
    }

    # ---- 4. ustawienia Windows
    if ($tweaks.Count -gt 0) {
        Write-Log 'Ustawienia Windows' Step
        foreach ($t in $tweaks) {
            Set-Status "Ustawienie: $($t.Name)"
            try {
                & $t.Action
                Write-Log "  ✓ [$($t.Group)] $($t.Name)" Ok
                if ($t.Explorer) { $Script:ExplorerRestartNeeded = $true }
            }
            catch { Write-Log "  ✗ [$($t.Group)] $($t.Name): $($_.Exception.Message)" Error; $failed.Add($t.Name) }
            & $stepDone
        }
        if ($Script:ExplorerRestartNeeded -and $ui.RestartExplorer.Checked) {
            Set-Status 'Restart Eksploratora…'
            Restart-Explorer
        }
    }

    # ---- podsumowanie
    Write-Log ('─' * 70) Dim
    if ($failed.Count -eq 0) { Write-Log 'Gotowe – wszystko wykonane pomyślnie.' Ok }
    else { Write-Log "Gotowe – problemy z: $($failed -join ', ')" Warn }
    if ($Script:RebootRecommended) { Write-Log 'Zalecany restart komputera (np. Docker Desktop / WSL).' Warn }
    Write-Log "Pełny log: $Script:LogFile" Dim
    Set-Status 'Zakończono.'
    $ui.Progress.Value = $ui.Progress.Maximum
    Set-UiBusy $false

    $summary = if ($failed.Count -eq 0) { 'Wszystko wykonane pomyślnie.' } else { "Zakończono z problemami ($($failed.Count)): `n• " + ($failed -join "`n• ") }
    if ($Script:RebootRecommended) {
        $ans = [Windows.Forms.MessageBox]::Show("$summary`n`nZalecany jest restart komputera. Uruchomić ponownie teraz?", 'FreshSetup', 'YesNo', 'Question')
        if ($ans -eq 'Yes') { Start-Process shutdown.exe -ArgumentList '/r', '/t', '5', '/c', '"FreshSetup: restart po instalacji"' }
    }
    else {
        [Windows.Forms.MessageBox]::Show($summary, 'FreshSetup', 'OK', $(if ($failed.Count -eq 0) { 'Information' } else { 'Warning' })) | Out-Null
    }
}

$btnStart.Add_Click({
    try { Start-Setup }
    catch {
        Write-Log "Błąd krytyczny: $($_.Exception.Message)" Error
        Set-UiBusy $false
        [Windows.Forms.MessageBox]::Show("Wystąpił błąd: $($_.Exception.Message)", 'FreshSetup', 'OK', 'Error') | Out-Null
    }
})
$btnLog.Add_Click({ if (Test-Path $Script:LogFile) { Start-Process notepad.exe -ArgumentList "`"$Script:LogFile`"" } })
$btnPayload.Add_Click({
    New-Item -ItemType Directory -Force -Path $Script:PayloadDir | Out-Null
    Start-Process explorer.exe -ArgumentList "`"$Script:PayloadDir`""
})
$btnUnlock.Add_Click({
    $ans = [Windows.Forms.MessageBox]::Show('Usunąć wszystkie polityki Brave zapisane przez FreshSetup? Ustawienia w Brave zostaną odblokowane.', 'FreshSetup', 'YesNo', 'Question')
    if ($ans -eq 'Yes') { try { Remove-BravePolicies | Out-Null } catch { Write-Log "Błąd: $($_.Exception.Message)" Error } }
})
$btnClose.Add_Click({ $form.Close() })
$form.Add_FormClosing({ param($s, $e)
    if ($Script:Busy) {
        $ans = [Windows.Forms.MessageBox]::Show('Trwa wykonywanie zadań. Przerwać i zamknąć?', 'FreshSetup', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { $e.Cancel = $true }
    }
})
$form.Add_Shown({
    $osName = [string](Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'ProductName')
    $osVer  = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'DisplayVersion'
    $build  = [int](Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'CurrentBuild')
    if ($build -ge 22000) { $osName = $osName -replace 'Windows 10', 'Windows 11' }   # rejestr zgłasza „Windows 10” także na 11
    Write-Log "FreshSetup uruchomiony – $osName $osVer, użytkownik $env:USERNAME, $adminText." Info
    Write-Log "Folder aplikacji: $Script:AppRoot" Dim
    Update-FilesList
    $m = Get-Manifest
    Write-Log "Payload: $(@($m.items).Count) pozycji, zakładki: $(if ($m.bookmarks) { $m.bookmarks } else { 'brak' })" Dim
    Write-Log 'Zaznacz, co ma zostać wykonane, i kliknij „Start”.' Info
    Set-Status 'Zbieranie spisu podzespołów…'
    $hwSw = [Diagnostics.Stopwatch]::StartNew()
    Update-HardwarePanel
    Write-Log ("Spis podzespołów zebrany w {0:N1} s (panel po prawej; Kopiuj / Zapisz…)." -f $hwSw.Elapsed.TotalSeconds) Dim
    Set-Status 'Gotowy.'
})

if ($AutoCloseSeconds -gt 0) {
    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = $AutoCloseSeconds * 1000
    $timer.Add_Tick({ $timer.Stop(); $form.Close() })
    $timer.Start()
}

try { [void]$form.ShowDialog() }
catch {
    try { Write-Log "Błąd krytyczny GUI: $($_.Exception.Message)" Error } catch { }
    [Windows.Forms.MessageBox]::Show("Błąd krytyczny: $($_.Exception.Message)`n`n$($_.ScriptStackTrace)", 'FreshSetup', 'OK', 'Error') | Out-Null
}
