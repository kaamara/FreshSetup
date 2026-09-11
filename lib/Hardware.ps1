# Hardware.ps1 – spis podzespołów komputera zbierany przez CIM/WMI (czysty PowerShell, bez zewnętrznych narzędzi).
# Każda sekcja to hashtable @{ Title; Get = { zwraca tablicę wierszy @(klucz, wartość) } }.
# Uwaga: zasilacz ATX nie raportuje żadnych parametrów do systemu – tej informacji nie da się odczytać programowo.

function Format-GiB {
    param([double]$Bytes)
    if ($Bytes -le 0) { return 'brak danych' }
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) {
        $v = $Bytes / 1GB
        if ([math]::Abs($v - [math]::Round($v)) -lt 0.05) { return ('{0:N0} GB' -f $v) }
        return ('{0:N1} GB' -f $v)
    }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} B' -f $Bytes)
}

function Get-CimSafe {
    param([string]$Class, [string]$Namespace = 'root\cimv2', [string]$Filter)
    try {
        if ($Filter) { return @(Get-CimInstance -Namespace $Namespace -ClassName $Class -Filter $Filter -ErrorAction Stop) }
        return @(Get-CimInstance -Namespace $Namespace -ClassName $Class -ErrorAction Stop)
    }
    catch { return @() }
}

function Get-HwSystem {
    $rows = @()
    $cs = Get-CimSafe Win32_ComputerSystem | Select-Object -First 1
    $os = Get-CimSafe Win32_OperatingSystem | Select-Object -First 1
    if ($cs) {
        $model = "$($cs.Manufacturer) $($cs.Model)".Trim()
        if ($model) { $rows += , @('Komputer', $model) }
        $rows += , @('Typ', $(if ($cs.PCSystemType -eq 2) { 'laptop / urządzenie mobilne' } else { 'komputer stacjonarny' }))
    }
    $rows += , @('Nazwa', $env:COMPUTERNAME)
    if ($os) {
        $ver = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'DisplayVersion'
        $rows += , @('System', "$($os.Caption -replace '^Microsoft ', '') $ver (build $($os.BuildNumber))")
        if ($os.InstallDate) { $rows += , @('Zainstalowano', $os.InstallDate.ToString('yyyy-MM-dd')) }
    }
    $fw = if ($env:firmware_type) { $env:firmware_type } else { 'nieznany' }
    $rows += , @('Firmware', $fw)
    try {
        $sb = Confirm-SecureBootUEFI -ErrorAction Stop
        $rows += , @('Secure Boot', $(if ($sb) { 'włączony' } else { 'wyłączony' }))
    }
    catch { }
    $tpm = Get-CimSafe -Class Win32_Tpm -Namespace 'root\cimv2\Security\MicrosoftTpm' | Select-Object -First 1
    if ($tpm) {
        $spec = ([string]$tpm.SpecVersion -split ',')[0].Trim()
        $rows += , @('TPM', "$spec, $(if ($tpm.IsEnabled_InitialValue) { 'aktywny' } else { 'nieaktywny' })")
    }
    return $rows
}

function Get-HwCpu {
    $rows = @()
    $cpus = Get-CimSafe Win32_Processor
    $i = 0
    foreach ($cpu in $cpus) {
        $i++
        $prefix = if ($cpus.Count -gt 1) { "CPU $i " } else { '' }
        $rows += , @("${prefix}Model", ($cpu.Name -replace '\s+', ' ').Trim())
        $rows += , @("${prefix}Rdzenie / wątki", "$($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors)")
        $rows += , @("${prefix}Taktowanie", "$($cpu.MaxClockSpeed) MHz (bazowe wg producenta)")
        $l2 = if ($cpu.L2CacheSize) { '{0:N1} MB' -f ($cpu.L2CacheSize / 1024) } else { '?' }
        $l3 = if ($cpu.L3CacheSize) { '{0:N1} MB' -f ($cpu.L3CacheSize / 1024) } else { '?' }
        $rows += , @("${prefix}Cache L2 / L3", "$l2 / $l3")
        if ($cpu.SocketDesignation) { $rows += , @("${prefix}Gniazdo", $cpu.SocketDesignation) }
    }
    return $rows
}

function Get-HwMemory {
    $types = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
    $forms = @{ 8 = 'DIMM'; 12 = 'SO-DIMM' }
    $rows = @()
    $mods = Get-CimSafe Win32_PhysicalMemory
    $arr = Get-CimSafe Win32_PhysicalMemoryArray | Select-Object -First 1
    $total = ($mods | Measure-Object -Property Capacity -Sum).Sum
    if (-not $total) {
        $cs = Get-CimSafe Win32_ComputerSystem | Select-Object -First 1
        if ($cs) { $total = $cs.TotalPhysicalMemory }
    }
    $summary = Format-GiB $total
    if ($mods.Count) { $summary += " w $($mods.Count) modułach" }
    if ($arr -and $arr.MemoryDevices) { $summary += " (gniazd: $($arr.MemoryDevices))" }
    $rows += , @('Łącznie', $summary)
    $i = 0
    foreach ($m in $mods) {
        $i++
        $t = $types[[int]$m.SMBIOSMemoryType]
        if (-not $t) { $t = $types[[int]$m.MemoryType] }
        if (-not $t) { $t = 'typ ' + $m.SMBIOSMemoryType }
        $ff = $forms[[int]$m.FormFactor]
        $speed = if ($m.ConfiguredClockSpeed -and $m.Speed -and $m.ConfiguredClockSpeed -ne $m.Speed) { "$($m.ConfiguredClockSpeed) MHz (nominalnie $($m.Speed) MHz)" }
                 elseif ($m.ConfiguredClockSpeed) { "$($m.ConfiguredClockSpeed) MHz" }
                 elseif ($m.Speed) { "$($m.Speed) MHz" } else { '? MHz' }
        $man = if ($m.Manufacturer -and $m.Manufacturer -notmatch '^(Unknown|Undefined|Manufacturer\d*|0{2,})$') { $m.Manufacturer } else { '' }
        $mk = ("$man $($m.PartNumber)" -replace '\s+', ' ').Trim()
        $slot = ("$($m.BankLabel) $($m.DeviceLocator)" -replace '\s+', ' ').Trim()
        $desc = ("$(Format-GiB $m.Capacity) $t $ff $speed" -replace '\s+', ' ').Trim()
        if ($mk) { $desc += ", $mk" }
        if ($slot) { $desc += " – slot $slot" }
        $rows += , @("Moduł $i", $desc)
    }
    return $rows
}

function Get-HwGpu {
    $rows = @()
    # Rzeczywista ilość VRAM z klucza klasy kart graficznych.
    $vram = @{}
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    foreach ($k in (Get-ChildItem $classKey -ErrorAction SilentlyContinue)) {
        $p = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
        if (-not $p -or -not $p.DriverDesc) { continue }
        $q = $p.'HardwareInformation.qwMemorySize'
        if ($null -eq $q) { continue }
        try {
            if ($q -is [byte[]]) { $q = [BitConverter]::ToUInt64($q, 0) }
            $vram[[string]$p.DriverDesc] = [uint64]$q
        }
        catch { }
    }
    $gpus = Get-CimSafe Win32_VideoController
    $i = 0
    foreach ($g in $gpus) {
        $i++
        $prefix = if ($gpus.Count -gt 1) { "GPU $i " } else { '' }
        $mem = $vram[[string]$g.Name]
        if (-not $mem -and $g.AdapterRAM) { $mem = [uint64]$g.AdapterRAM }
        $rows += , @("${prefix}Karta", $g.Name)
        $rows += , @("${prefix}VRAM", (Format-GiB $mem))
        $drv = $g.DriverVersion
        if ($g.DriverDate) { $drv += " ($(([datetime]$g.DriverDate).ToString('yyyy-MM-dd')))" }
        $rows += , @("${prefix}Sterownik", $drv)
        if ($g.CurrentHorizontalResolution) {
            $rows += , @("${prefix}Tryb", "$($g.CurrentHorizontalResolution)×$($g.CurrentVerticalResolution) @ $($g.CurrentRefreshRate) Hz")
        }
    }
    return $rows
}

function Get-HwBoard {
    $rows = @()
    $bb = Get-CimSafe Win32_BaseBoard | Select-Object -First 1
    $bios = Get-CimSafe Win32_BIOS | Select-Object -First 1
    if ($bb) {
        $rows += , @('Płyta główna', ("$($bb.Manufacturer) $($bb.Product)" -replace '\s+', ' ').Trim())
        if ($bb.Version -and $bb.Version -notmatch 'default|to be filled') { $rows += , @('Wersja płyty', $bb.Version) }
    }
    if ($bios) {
        $b = "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)".Trim()
        if ($bios.ReleaseDate) { $b += " ($(([datetime]$bios.ReleaseDate).ToString('yyyy-MM-dd')))" }
        $rows += , @('BIOS / UEFI', $b)
    }
    return $rows
}

function Get-HwDisks {
    $rows = @()
    $pds = @()
    try { $pds = @(Get-PhysicalDisk -ErrorAction Stop | Sort-Object { [int]$_.DeviceId }) } catch { }
    if ($pds.Count) {
        foreach ($d in $pds) {
            $desc = "$($d.FriendlyName) – $(Format-GiB $d.Size)"
            $kind = @($d.MediaType, $d.BusType) | Where-Object { $_ -and $_ -ne 'Unspecified' -and $_ -ne 'Unknown' }
            if ($kind) { $desc += ', ' + ($kind -join ' ') }
            if ($d.HealthStatus) { $desc += ", stan: $($d.HealthStatus)" }
            $rows += , @("Dysk $($d.DeviceId)", $desc)
        }
    }
    else {
        foreach ($d in (Get-CimSafe Win32_DiskDrive | Sort-Object Index)) {
            $rows += , @("Dysk $($d.Index)", "$($d.Model) – $(Format-GiB $d.Size), $($d.InterfaceType)")
        }
    }
    foreach ($v in (Get-CimSafe Win32_LogicalDisk -Filter 'DriveType=3' | Sort-Object DeviceID)) {
        if (-not $v.Size) { continue }
        $pct = [math]::Round(100 * $v.FreeSpace / $v.Size)
        $label = if ($v.VolumeName) { ', „' + $v.VolumeName + '”' } else { '' }
        $rows += , @("Wolumin $($v.DeviceID.TrimEnd(':'))", "$(Format-GiB $v.Size), wolne $(Format-GiB $v.FreeSpace) ($pct%), $($v.FileSystem)$label")
    }
    return $rows
}

function Get-HwPower {
    $rows = @()
    $rows += , @('Zasilacz', 'brak odczytu – zasilacze ATX nie raportują mocy ani modelu do systemu (sprawdź naklejkę na obudowie zasilacza)')
    $bats = Get-CimSafe Win32_Battery
    foreach ($b in $bats) {
        $status = switch ([int]$b.BatteryStatus) { 1 { 'rozładowywanie' } 2 { 'zasilanie sieciowe' } 3 { 'naładowana' } 6 { 'ładowanie' } default { "status $($b.BatteryStatus)" } }
        $rows += , @('Bateria', "$($b.Name), $($b.EstimatedChargeRemaining)%, $status")
    }
    try {
        $plan = (powercfg /getactivescheme) -join ' '
        if ($plan -match '\((.+)\)\s*$') { $rows += , @('Plan zasilania', $Matches[1]) }
    }
    catch { }
    return $rows
}

function Get-HwMonitors {
    $vendors = @{ AUS = 'ASUS'; SAM = 'Samsung'; DEL = 'Dell'; GSM = 'LG'; LGD = 'LG'; BNQ = 'BenQ'; ACR = 'Acer'; AOC = 'AOC'; MSI = 'MSI'
                  PHL = 'Philips'; HWP = 'HP'; HPN = 'HP'; IVM = 'iiyama'; GBT = 'Gigabyte'; LEN = 'Lenovo'; VSC = 'ViewSonic'; SNY = 'Sony'
                  NEC = 'NEC'; EIZ = 'EIZO'; APP = 'Apple'; XMI = 'Xiaomi'; HSD = 'HannStar'; CMN = 'Chi Mei'; AUO = 'AU Optronics'; BOE = 'BOE' }
    $rows = @()
    $mons = Get-CimSafe -Class WmiMonitorID -Namespace 'root\wmi'
    $i = 0
    foreach ($m in $mons) {
        $i++
        $name = -join ($m.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
        $man  = -join ($m.ManufacturerName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
        if ($vendors[$man]) { $man = $vendors[$man] }
        $year = if ($m.YearOfManufacture) { " ($($m.YearOfManufacture))" } else { '' }
        if (-not $name) { $name = 'model nieznany' }
        $rows += , @("Monitor $i", "$man $name$year".Trim())
    }
    return $rows
}

function Get-HwNetwork {
    $rows = @()
    try {
        foreach ($a in (Get-NetAdapter -Physical -ErrorAction Stop | Sort-Object -Property Status, Name)) {
            $st = switch ($a.Status) { 'Up' { 'aktywna' } 'Disconnected' { 'odłączona' } 'Disabled' { 'wyłączona' } default { $a.Status } }
            $rows += , @($a.Name, "$($a.InterfaceDescription), $($a.LinkSpeed), $st")
        }
    }
    catch {
        foreach ($a in (Get-CimSafe Win32_NetworkAdapter -Filter 'PhysicalAdapter=True')) { $rows += , @($a.NetConnectionID, $a.Name) }
    }
    return $rows
}

function Get-HwAudio {
    $rows = @()
    foreach ($s in (Get-CimSafe Win32_SoundDevice)) { $rows += , @('Urządzenie', $s.Name) }
    return $rows
}

$Script:HardwareSections = @(
    @{ Title = 'Komputer i system';   Get = { Get-HwSystem } }
    @{ Title = 'Procesor';            Get = { Get-HwCpu } }
    @{ Title = 'Pamięć RAM';          Get = { Get-HwMemory } }
    @{ Title = 'Karta graficzna';     Get = { Get-HwGpu } }
    @{ Title = 'Płyta główna i BIOS'; Get = { Get-HwBoard } }
    @{ Title = 'Dyski';               Get = { Get-HwDisks } }
    @{ Title = 'Zasilanie';           Get = { Get-HwPower } }
    @{ Title = 'Monitory';            Get = { Get-HwMonitors } }
    @{ Title = 'Sieć';                Get = { Get-HwNetwork } }
    @{ Title = 'Dźwięk';              Get = { Get-HwAudio } }
)

function Get-HardwareReportText {
    # Pełny raport jako tekst
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("Podzespoły – $env:COMPUTERNAME – $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    foreach ($s in $Script:HardwareSections) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("== $($s.Title) ==")
        try {
            $rows = @(& $s.Get)
            if (-not $rows.Count) { [void]$sb.AppendLine('  brak danych') }
            foreach ($r in $rows) { [void]$sb.AppendLine("  $($r[0]): $($r[1])") }
        }
        catch { [void]$sb.AppendLine("  błąd: $($_.Exception.Message)") }
    }
    return $sb.ToString()
}
