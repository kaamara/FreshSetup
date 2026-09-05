# Common.ps1 – logowanie, rejestr, uruchamianie procesów zewnętrznych bez blokowania GUI

$Script:RebootRecommended     = $false
$Script:ExplorerRestartNeeded = $false
$Script:LogSink               = $null

function Initialize-Log {
    $dir = Join-Path $Script:AppRoot 'logs'
    try { New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null }
    catch {
        $dir = Join-Path $env:TEMP 'FreshSetup-logs'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Script:LogFile = Join-Path $dir ('FreshSetup-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
    return $Script:LogFile
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Ok', 'Warn', 'Error', 'Dim', 'Step')][string]$Level = 'Info'
    )
    $line = '[{0:HH:mm:ss}] {1}' -f (Get-Date), $Message
    if ($Script:LogFile) { try { Add-Content -Path $Script:LogFile -Value $line -Encoding UTF8 } catch { } }
    if ($Script:LogSink) { try { & $Script:LogSink $line $Level } catch { } }
}

function Invoke-UiPump { [System.Windows.Forms.Application]::DoEvents() }

function Set-RegValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value,
        [string]$Type = 'DWord'
    )
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

function Read-FileTail {
    # Czyta nowe bajty z pliku, który inny proces wciąż zapisuje.
    param([string]$Path, [ref]$Offset)
    try {
        $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            if ($fs.Length -le $Offset.Value) { return $null }
            $fs.Seek($Offset.Value, [IO.SeekOrigin]::Begin) | Out-Null
            $buf = New-Object byte[] ($fs.Length - $Offset.Value)
            $n = $fs.Read($buf, 0, $buf.Length)
            $Offset.Value += $n
            # winget pisze UTF-8; klasyczne narzędzia konsolowe (cmd, whoami) piszą w stronie kodowej OEM (np. CP852).
            try { return (New-Object Text.UTF8Encoding($false, $true)).GetString($buf, 0, $n) }
            catch {
                $oem = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
                return $oem.GetString($buf, 0, $n)
            }
        }
        finally { $fs.Dispose() }
    }
    catch { return $null }
}

function Format-ConsoleChunk {
    # Zamienia surowe wyjście konsolowe (znaki \r, paski postępu) na czyste linie.
    param([string]$Chunk)
    $result = New-Object System.Collections.Generic.List[string]
    if (-not $Chunk) { return $result }
    $lines = $Chunk -split "[\r\n]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($l in $lines) {
        if ($l -match '^[\s\-\\|/█▓▒░■▪●•]+$') { continue }
        if ($l -match '^\d+(\.\d+)?\s*(B|KB|MB|GB)\s*/\s*\d') { continue }
        if ($result.Count -gt 0 -and $result[$result.Count - 1] -eq $l) { continue }
        $result.Add($l)
    }
    return $result
}

function Write-ChunkToLog {
    param([string]$Path, [ref]$Offset)
    $chunk = Read-FileTail -Path $Path -Offset $Offset
    foreach ($l in (Format-ConsoleChunk $chunk)) { Write-Log "      $l" Dim }
}

function Invoke-External {
    # Uruchamia proces, czeka na jego koniec nie blokując GUI, zwraca kod wyjścia i wyjście.
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$Stream,
        [int]$TimeoutSec = 3600
    )
    $out = [IO.Path]::GetTempFileName()
    $err = [IO.Path]::GetTempFileName()
    $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -NoNewWindow
    $null = $proc.Handle
    $offset = 0
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    while (-not $proc.HasExited) {
        Invoke-UiPump
        Start-Sleep -Milliseconds 200
        if ($Stream) { Write-ChunkToLog -Path $out -Offset ([ref]$offset) }
        if ($sw.Elapsed.TotalSeconds -gt $TimeoutSec) {
            $timedOut = $true
            try { $proc.Kill() } catch { }
            break
        }
    }
    $proc.WaitForExit()
    if ($Stream) { Write-ChunkToLog -Path $out -Offset ([ref]$offset) }
    $stdout = ''; $stderr = ''
    try { $stdout = [IO.File]::ReadAllText($out) } catch { }
    try { $stderr = [IO.File]::ReadAllText($err) } catch { }
    Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
    $code = if ($timedOut) { -1 } else { $proc.ExitCode }
    return @{ ExitCode = $code; Output = ($stdout + "`n" + $stderr); TimedOut = $timedOut }
}

function Get-ShortPath {
    param([string]$Path)
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        if (Test-Path -LiteralPath $Path -PathType Container) { return $fso.GetFolder($Path).ShortPath }
        return $fso.GetFile($Path).ShortPath
    }
    catch { return $Path }
}

function Invoke-ExternalAsUser {
    # Uruchamia polecenie BEZ uprawnień administratora (poziom "Basic User" przez runas /trustlevel).
    # Potrzebne np. dla instalatora Spotify, który odmawia działania z poziomu administratora.
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSec = 1800
    )
    $work = Join-Path $env:TEMP ('FreshSetup-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $out = Join-Path $work 'out.txt'
    $done = Join-Path $work 'done.txt'
    $cmdFile = Join-Path $work 'run.cmd'
    $quoted = $ArgumentList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
    $script = "@echo off`r`n`"$FilePath`" $($quoted -join ' ') > `"$out`" 2>&1`r`necho %errorlevel%> `"$done`"`r`n"
    [IO.File]::WriteAllText($cmdFile, $script, [Text.Encoding]::Default)

    $shortCmd = Get-ShortPath $cmdFile
    if ($shortCmd -match '\s') {
        # Brak nazw 8.3 na dysku – awaryjnie przez explorer.exe (uruchamia pliki bez podniesienia uprawnień).
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$cmdFile`""
    }
    else {
        Start-Process -FilePath 'runas.exe' -ArgumentList "/trustlevel:0x20000 `"cmd.exe /c $shortCmd`"" -WindowStyle Hidden
    }

    $offset = 0
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path $done)) {
        Invoke-UiPump
        Start-Sleep -Milliseconds 300
        Write-ChunkToLog -Path $out -Offset ([ref]$offset)
        if ($sw.Elapsed.TotalSeconds -gt $TimeoutSec) {
            return @{ ExitCode = -1; Output = ''; TimedOut = $true }
        }
    }
    Start-Sleep -Milliseconds 300
    Write-ChunkToLog -Path $out -Offset ([ref]$offset)
    $code = 0
    try { $code = [int]((Get-Content $done -Raw).Trim()) } catch { }
    $output = ''
    try { $output = [IO.File]::ReadAllText($out) } catch { }
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    return @{ ExitCode = $code; Output = $output; TimedOut = $false }
}

function Restart-Explorer {
    Write-Log 'Restart Eksploratora Windows (zastosowanie zmian paska zadań / motywu)...' Info
    try {
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
        Write-Log '  Eksplorator uruchomiony ponownie.' Ok
    }
    catch { Write-Log "  Nie udało się zrestartować Eksploratora: $($_.Exception.Message)" Warn }
}
