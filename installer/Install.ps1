#Requires -Version 5.1
<#
.SYNOPSIS
    RaceNet Local - DiRT Showdown: установщик локального сервера RaceNet.

.DESCRIPTION
    Ставит локальный сервер RaceNet для DiRT Showdown (Steam), патчит доверенный
    корневой сертификат внутри showdown.exe / showdown_avx.exe (данные, не код),
    добавляет запись в hosts и создаёт ярлыки запуска.

    Никакие файлы игры не заменяются: меняются только 1003 байта встроенного
    сертификата Codemasters, рядом создаётся .racenet-original.bak.

.PARAMETER Mode
    Local  - поднять сервер на этом ПК (по умолчанию).
    Friend - подключиться к серверу друга (нужен его IP и запущенный сервер).

.PARAMETER GamePath
    Папка DiRT Showdown. Если не указана - определяется автоматически.

.PARAMETER Server
    IP или имя сервера друга (только для -Mode Friend).

.PARAMETER Uninstall
    Полностью удалить мод: восстановить exe, убрать hosts, сертификат, ярлыки.

.PARAMETER RestoreOnly
    Только восстановить exe и hosts, сервер и данные оставить.

.PARAMETER Gui
    Показать графический установщик.

.PARAMETER Silent
    Без вопросов и без GUI (для скриптов).

.PARAMETER AllowFriends
    Разрешить подключение друзей: сервер слушает все интерфейсы + правило firewall.

.EXAMPLE
    Install.cmd

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Install.ps1 -Mode Local -Silent -AllowFriends

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Install.ps1 -Mode Friend -Server 203.0.113.10
#>
[CmdletBinding()]
param(
    [ValidateSet('Local', 'Friend')]
    [string]$Mode = 'Local',
    [string]$GamePath = '',
    [string]$Server = '',
    [switch]$Uninstall,
    [switch]$RestoreOnly,
    [switch]$Gui,
    [switch]$Silent,
    [switch]$AllowFriends,
    [switch]$KeepData,
    [switch]$NoShortcut,
    [switch]$NoElevate,
    [string]$HostsFile = '',
    [string]$ServerSource = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:ProductName = 'RaceNet Local - DiRT Showdown'
$script:InstallDir = Join-Path $env:LOCALAPPDATA 'RaceNetLocal'
$script:ServerDir = Join-Path $script:InstallDir 'server'
$script:StatePath = Join-Path $script:InstallDir 'install-state.json'
$script:MarkerBegin = '# --- RaceNetLocal begin ---'
$script:MarkerEnd = '# --- RaceNetLocal end ---'
$script:ShortcutName = 'DiRT Showdown - RaceNet'
$script:StartMenuFolder = 'RaceNet Local'
$script:FirewallRule = 'RaceNet Local (TCP 80,443)'
$script:LogFile = Join-Path $env:TEMP 'RaceNetLocal-install.log'
$script:GuiLog = $null
$script:ExpectedCertLength = 1003
$script:HostNames = @(
    'prod.egonet.codemasters.com',
    'egonet.codemasters.com',
    'racenet.codemasters.com',
    'api.racenet.codemasters.com',
    'showdown.racenet.codemasters.com',
    'grid2.racenet.codemasters.com',
    'racenet.com',
    'www.racenet.com',
    'api.racenet.com'
)
$script:ExecutableNames = @('showdown.exe', 'showdown_avx.exe')
$script:ProcessNames = @('showdown', 'showdown_avx')

# ---------------------------------------------------------------- logging ---

function Write-InstallLog {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Ok', 'Warn', 'Error', 'Step')]
        [string]$Level = 'Info'
    )

    $line = '[{0:HH:mm:ss}] {1}' -f (Get-Date), $Message

    try {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }

    $color = 'Gray'
    if ($Level -eq 'Ok') { $color = 'Green' }
    if ($Level -eq 'Warn') { $color = 'Yellow' }
    if ($Level -eq 'Error') { $color = 'Red' }
    if ($Level -eq 'Step') { $color = 'Cyan' }

    Write-Host $line -ForegroundColor $color

    if ($null -ne $script:GuiLog) {
        try {
            $script:GuiLog.AppendText($line + "`r`n")
            $script:GuiLog.SelectionStart = $script:GuiLog.TextLength
            $script:GuiLog.ScrollToCaret()
            [System.Windows.Forms.Application]::DoEvents()
        } catch { }
    }
}

function Fail-Install {
    param([string]$Message)
    Write-InstallLog $Message 'Error'
    throw $Message
}

# ------------------------------------------------------- admin / elevation ---

function Test-IsAdmin {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Restart-Elevated {
    $arguments = New-Object System.Collections.Generic.List[string]
    $arguments.Add('-NoProfile')
    $arguments.Add('-ExecutionPolicy')
    $arguments.Add('Bypass')
    $arguments.Add('-File')
    $arguments.Add('"' + $PSCommandPath + '"')

    foreach ($entry in $PSBoundParameters.GetEnumerator()) {
        if ($entry.Key -eq 'NoElevate') { continue }
        $value = $entry.Value
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { $arguments.Add('-' + $entry.Key) }
        } elseif ($null -ne $value -and "$value" -ne '') {
            $arguments.Add('-' + $entry.Key)
            $arguments.Add('"' + (([string]$value).Replace('"', '\"')) + '"')
        }
    }
    $arguments.Add('-NoElevate')

    $startInfo = @{
        FilePath     = 'powershell.exe'
        ArgumentList = $arguments.ToArray()
        Verb         = 'RunAs'
    }
    if ($Gui) { $startInfo['WindowStyle'] = 'Hidden' }

    Write-InstallLog 'Требуются права администратора - запрашиваю повышение...' 'Step'
    try {
        $process = Start-Process @startInfo -PassThru
        $process.WaitForExit()
        exit $process.ExitCode
    } catch {
        Fail-Install ('Не удалось получить права администратора: ' + $_.Exception.Message)
    }
}

# ------------------------------------------------------------ game folder ---

function Get-SteamLibraries {
    $libraries = New-Object System.Collections.Generic.List[string]

    $candidates = @()
    try { $candidates += (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch { }
    try { $candidates += (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath } catch { }
    try { $candidates += (Get-ItemProperty 'HKLM:\SOFTWARE\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath } catch { }

    foreach ($steamPath in $candidates) {
        if (-not $steamPath) { continue }
        $steamPath = $steamPath -replace '/', '\'
        if (-not (Test-Path -LiteralPath $steamPath)) { continue }
        [void]$libraries.Add($steamPath)

        $vdf = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            try {
                $text = Get-Content -LiteralPath $vdf -Raw
                foreach ($match in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
                    $path = $match.Groups[1].Value -replace '\\\\', '\'
                    if (Test-Path -LiteralPath $path) { [void]$libraries.Add($path) }
                }
            } catch { }
        }
    }

    return $libraries | Select-Object -Unique
}

function Find-GameFolder {
    param([string]$Explicit)

    if ($Explicit) {
        if (Test-Path -LiteralPath $Explicit) { return (Resolve-Path -LiteralPath $Explicit).Path }
        return $null
    }

    foreach ($library in Get-SteamLibraries) {
        $candidate = Join-Path $library 'steamapps\common\DiRT Showdown'
        if (Test-Path -LiteralPath (Join-Path $candidate 'showdown.exe')) { return $candidate }
    }

    foreach ($drive in 'C', 'D', 'E', 'F', 'G', 'H') {
        foreach ($pattern in @(
                "$drive`:\SteamLibrary\steamapps\common\DiRT Showdown",
                "$drive`:\Steam\steamapps\common\DiRT Showdown",
                "$drive`:\Program Files (x86)\Steam\steamapps\common\DiRT Showdown",
                "$drive`:\Program Files\Steam\steamapps\common\DiRT Showdown",
                "$drive`:\Games\DiRT Showdown"
            )) {
            if (Test-Path -LiteralPath (Join-Path $pattern 'showdown.exe')) { return $pattern }
        }
    }

    return $null
}

function Assert-GameFolder {
    param([string]$Path)

    if (-not $Path) {
        Fail-Install 'Не найдена папка DiRT Showdown. Укажите её вручную в установщике.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Path 'showdown.exe'))) {
        Fail-Install ('В папке нет showdown.exe: ' + $Path + '. Укажите папку игры, а не библиотеку Steam.')
    }
}

function Stop-GameProcesses {
    $running = Get-Process -Name $script:ProcessNames -ErrorAction SilentlyContinue
    if (-not $running) { return }
    Write-InstallLog 'Закрываю DiRT Showdown перед изменением файлов...' 'Step'
    foreach ($process in $running) {
        try {
            $process.Kill()
            $process.WaitForExit(5000) | Out-Null
        } catch {
            Write-InstallLog ('Не удалось закрыть процесс: ' + $_.Exception.Message) 'Warn'
        }
    }
    Start-Sleep -Milliseconds 700
}

# ----------------------------------------------------------------- hosts ---

function Get-HostsPath {
    if ($HostsFile) { return $HostsFile }
    return Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
}

function Backup-HostsFile {
    param([string]$Path)

    $backupDir = Join-Path $env:ProgramData 'RaceNetLocal'
    try { New-Item -ItemType Directory -Force -Path $backupDir | Out-Null } catch { return }
    $backup = Join-Path $backupDir 'hosts.before-racenetlocal.bak'
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $Path -Destination $backup -Force
        Write-InstallLog ('Резервная копия hosts: ' + $backup)
    }
}

function Set-HostsEntry {
    param([string]$Path, [string]$Address)

    Backup-HostsFile -Path $Path

    $encoding = [System.Text.Encoding]::Default
    $text = [System.IO.File]::ReadAllText($Path, $encoding)
    $text = [regex]::Replace(
        $text,
        '(?s)\r?\n?' + [regex]::Escape($script:MarkerBegin) + '.*?' + [regex]::Escape($script:MarkerEnd) + '\r?\n?',
        "`r`n")

    $lines = $text -split "`r?`n"
    $kept = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { [void]$kept.Add($line); continue }
        $parts = $trimmed -split '\s+'
        if ($parts.Count -ge 2) {
            $name = $parts[1].ToLowerInvariant()
            if ($script:HostNames -contains $name) { continue }
        }
        [void]$kept.Add($line)
    }

    $body = ($kept -join "`r`n").TrimEnd()
    $block = New-Object System.Text.StringBuilder
    [void]$block.AppendLine()
    [void]$block.AppendLine($script:MarkerBegin)
    foreach ($name in $script:HostNames) {
        [void]$block.AppendLine($Address + ' ' + $name)
    }
    [void]$block.AppendLine($script:MarkerEnd)

    $newText = $body + "`r`n" + $block.ToString()
    [System.IO.File]::WriteAllText($Path, $newText, $encoding)

    Write-InstallLog ('hosts: ' + $Address + ' -> ' + $script:HostNames[0] + ' (+' + ($script:HostNames.Count - 1) + ' имён)') 'Ok'
}

function Remove-HostsEntry {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }

    $encoding = [System.Text.Encoding]::Default
    $text = [System.IO.File]::ReadAllText($Path, $encoding)
    $text = [regex]::Replace(
        $text,
        '(?s)\r?\n?' + [regex]::Escape($script:MarkerBegin) + '.*?' + [regex]::Escape($script:MarkerEnd) + '\r?\n?',
        "`r`n")

    $lines = $text -split "`r?`n"
    $kept = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { [void]$kept.Add($line); continue }
        $parts = $trimmed -split '\s+'
        if ($parts.Count -ge 2 -and ($script:HostNames -contains $parts[1].ToLowerInvariant())) { continue }
        [void]$kept.Add($line)
    }

    $newText = ($kept -join "`r`n").TrimEnd() + "`r`n"
    [System.IO.File]::WriteAllText($Path, $newText, $encoding)
    Write-InstallLog 'Запись из hosts удалена.' 'Ok'
}

function Clear-DnsCache {
    try {
        & ipconfig.exe /flushdns | Out-Null
        Write-InstallLog 'DNS-кеш сброшен.'
    } catch { }
}

# ------------------------------------------------------------- certificates ---

function Install-TrustedRoot {
    param([string]$CerPath)

    $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CerPath)
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'CurrentUser')
    $store.Open('ReadWrite')
    try {
        $existing = $store.Certificates | Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }
        if (-not $existing) {
            $store.Add($certificate)
            Write-InstallLog ('Корневой сертификат установлен: ' + $certificate.Thumbprint) 'Ok'
        } else {
            Write-InstallLog 'Корневой сертификат уже установлен.'
        }
    } finally {
        $store.Close()
    }

    return $certificate.Thumbprint
}

function Remove-TrustedRoot {
    param([string]$Thumbprint)

    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'CurrentUser')
    $store.Open('ReadWrite')
    try {
        $found = @($store.Certificates | Where-Object {
                ($Thumbprint -and $_.Thumbprint -eq $Thumbprint) -or
                (-not $Thumbprint -and $_.Subject -like '*Codemasters Online Root CA*')
            })
        foreach ($certificate in $found) {
            $store.Remove($certificate)
            Write-InstallLog ('Сертификат удалён: ' + $certificate.Thumbprint) 'Ok'
        }
    } finally {
        $store.Close()
    }
}

# ------------------------------------------------------------ exe patching ---

function Get-DerTotalLength {
    param([byte[]]$Bytes, [int]$Offset)

    if ($Offset + 2 -gt $Bytes.Length) { return 0 }
    if ($Bytes[$Offset] -ne 0x30) { return 0 }

    $marker = $Bytes[$Offset + 1]
    if (($marker -band 0x80) -eq 0) { return 2 + $marker }

    $lengthBytes = $marker -band 0x7f
    if ($lengthBytes -lt 1 -or $lengthBytes -gt 4) { return 0 }
    if ($Offset + 2 + $lengthBytes -gt $Bytes.Length) { return 0 }

    [long]$length = 0
    for ($i = 0; $i -lt $lengthBytes; $i++) {
        $length = ($length -shl 8) -bor $Bytes[$Offset + 2 + $i]
    }

    return [int](2 + $lengthBytes + $length)
}

function Get-EmbeddedCertificates {
    param([byte[]]$Bytes)

    $result = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[int]
    $ascii = [System.Text.Encoding]::ASCII.GetString($Bytes)
    $needle = 'Codemasters Online Root CA'
    $index = $ascii.IndexOf($needle, [System.StringComparison]::Ordinal)

    while ($index -ge 0) {
        $start = [Math]::Max(0, $index - 800)
        for ($offset = $start; $offset -le $index; $offset++) {
            if ($Bytes[$offset] -ne 0x30) { continue }
            $length = Get-DerTotalLength -Bytes $Bytes -Offset $offset
            if ($length -lt 256 -or $length -gt 8192) { continue }
            if ($offset + $length -gt $Bytes.Length) { continue }
            if ($offset + $length -le $index) { continue }

            $chunk = New-Object byte[] $length
            [Array]::Copy($Bytes, $offset, $chunk, 0, $length)

            try {
                $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($chunk)
            } catch {
                continue
            }

            if ($certificate.Subject -like '*CN=Codemasters Online Root CA*' -and
                $certificate.Subject -like '*OU=Codemasters Online*') {
                if ($seen.Add($offset)) {
                    [void]$result.Add([pscustomobject]@{ Offset = $offset; Bytes = $chunk })
                }
                $offset = $offset + $length - 1
            }
        }
        $index = $ascii.IndexOf($needle, $index + 1, [System.StringComparison]::Ordinal)
    }

    return $result
}

function Test-BytesEqual {
    param([byte[]]$Left, [byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($i = 0; $i -lt $Left.Length; $i++) {
        if ($Left[$i] -ne $Right[$i]) { return $false }
    }
    return $true
}

function Set-ExecutablePatch {
    param([string]$ExePath, [byte[]]$RootCertificate)

    $name = Split-Path -Leaf $ExePath
    if (-not (Test-Path -LiteralPath $ExePath)) {
        Write-InstallLog ('  ' + $name + ': файл не найден, пропуск') 'Warn'
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($ExePath)
    $candidates = Get-EmbeddedCertificates -Bytes $bytes

    if ($candidates.Count -eq 0) {
        Write-InstallLog ('  ' + $name + ': встроенный сертификат Codemasters не найден') 'Warn'
        return
    }

    $changed = $false
    foreach ($candidate in $candidates) {
        if (Test-BytesEqual -Left $candidate.Bytes -Right $RootCertificate) {
            Write-InstallLog ('  ' + $name + ': уже пропатчен (0x' + $candidate.Offset.ToString('x') + ')')
            continue
        }

        if ($candidate.Bytes.Length -ne $RootCertificate.Length) {
            Fail-Install ($name + ': длина встроенного сертификата ' + $candidate.Bytes.Length +
                ' не совпадает с локальным корнем ' + $RootCertificate.Length + ' байт.')
        }

        $backup = $ExePath + '.racenet-original.bak'
        if (-not (Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $ExePath -Destination $backup -Force
            Write-InstallLog ('  ' + $name + ': резервная копия .racenet-original.bak')
        }

        [Array]::Copy($RootCertificate, 0, $bytes, $candidate.Offset, $RootCertificate.Length)
        $changed = $true
        Write-InstallLog ('  ' + $name + ': сертификат заменён (0x' + $candidate.Offset.ToString('x') + ')') 'Ok'
    }

    if ($changed) {
        [System.IO.File]::WriteAllBytes($ExePath, $bytes)
    }
}

function Set-GamePatch {
    param([string]$TargetGamePath, [byte[]]$RootCertificate)

    Write-InstallLog 'Патчу исполняемые файлы игры (подмена сертификата)...' 'Step'
    foreach ($exeName in $script:ExecutableNames) {
        Set-ExecutablePatch -ExePath (Join-Path $TargetGamePath $exeName) -RootCertificate $RootCertificate
    }
}

function Restore-GameFiles {
    param([string]$TargetGamePath)

    Write-InstallLog 'Восстанавливаю оригинальные исполняемые файлы...' 'Step'
    $restored = 0
    foreach ($exeName in $script:ExecutableNames) {
        $exePath = Join-Path $TargetGamePath $exeName
        $backup = $exePath + '.racenet-original.bak'
        if (Test-Path -LiteralPath $backup) {
            Copy-Item -LiteralPath $backup -Destination $exePath -Force
            Write-InstallLog ('  ' + $exeName + ': восстановлен из резервной копии') 'Ok'
            $restored++
        } else {
            Write-InstallLog ('  ' + $exeName + ': резервной копии нет (проверьте целостность в Steam)') 'Warn'
        }
    }
    return $restored
}

# --------------------------------------------------------------- shortcuts ---

function New-ShortcutFile {
    param([string]$Path, [string]$Target, [string]$WorkingDirectory, [string]$Icon, [string]$Description)

    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $Target
    $shortcut.WorkingDirectory = $WorkingDirectory
    if ($Icon) { $shortcut.IconLocation = $Icon }
    if ($Description) { $shortcut.Description = $Description }
    $shortcut.Save()
}

function Set-Launchers {
    param([string]$TargetGamePath)

    $launchCmd = Join-Path $script:InstallDir 'Launch-DiRT-Showdown.cmd'
    $stopCmd = Join-Path $script:InstallDir 'Stop-RaceNet-Server.cmd'
    $launchText = @"
@echo off
setlocal
cd /d "%~dp0"
tasklist /FI "IMAGENAME eq RaceNetShowdown.Server.exe" 2>NUL | find /I "RaceNetShowdown.Server.exe" >NUL
if errorlevel 1 (
  start "RaceNet Server" /min "%~dp0server\RaceNetShowdown.Server.exe"
  timeout /t 5 /nobreak >NUL
)
where curl.exe >NUL 2>&1
if errorlevel 1 goto launch
curl.exe -s -m 3 http://127.0.0.1/health >NUL 2>&1
if not errorlevel 1 goto launch
echo.
echo [!] RaceNet server is not responding on http://127.0.0.1/health
echo     Check that TCP ports 80 and 443 are free.
echo     Details: docs\TROUBLESHOOTING.md
echo.
pause
:launch
start "" "steam://rungameid/201700"
exit /b 0
"@
    $stopText = @"
@echo off
taskkill /IM RaceNetShowdown.Server.exe /F >NUL 2>&1
echo RaceNet server stopped.
timeout /t 2 /nobreak >NUL
"@
    [System.IO.File]::WriteAllText($launchCmd, $launchText, [System.Text.Encoding]::ASCII)
    [System.IO.File]::WriteAllText($stopCmd, $stopText, [System.Text.Encoding]::ASCII)

    if ($NoShortcut) { return }

    $icon = Join-Path $TargetGamePath 'showdown.exe'
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startMenu = [Environment]::GetFolderPath('Programs')

    New-ShortcutFile -Path (Join-Path $desktop ($script:ShortcutName + '.lnk')) `
        -Target $launchCmd -WorkingDirectory $script:InstallDir -Icon ($icon + ',0') `
        -Description 'Запустить RaceNet-сервер и DiRT Showdown'
    New-ShortcutFile -Path (Join-Path (Join-Path $startMenu $script:StartMenuFolder) ($script:ShortcutName + '.lnk')) `
        -Target $launchCmd -WorkingDirectory $script:InstallDir -Icon ($icon + ',0') `
        -Description 'Запустить RaceNet-сервер и DiRT Showdown'
    New-ShortcutFile -Path (Join-Path (Join-Path $startMenu $script:StartMenuFolder) 'Остановить RaceNet-сервер.lnk') `
        -Target $stopCmd -WorkingDirectory $script:InstallDir -Icon 'shell32.dll,27' `
        -Description 'Остановить локальный сервер RaceNet'

    Write-InstallLog 'Ярлыки созданы (рабочий стол и меню Пуск).' 'Ok'
}

function Remove-Launchers {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startMenu = [Environment]::GetFolderPath('Programs')
    $paths = @(
        (Join-Path $desktop ($script:ShortcutName + '.lnk')),
        (Join-Path (Join-Path $startMenu $script:StartMenuFolder) ($script:ShortcutName + '.lnk')),
        (Join-Path (Join-Path $startMenu $script:StartMenuFolder) 'Остановить RaceNet-сервер.lnk')
    )
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
    $folder = Join-Path $startMenu $script:StartMenuFolder
    if ((Test-Path -LiteralPath $folder) -and -not (Get-ChildItem -LiteralPath $folder -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $folder -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------------ server ---

function Get-ServerPayloadSource {
    if ($ServerSource -and (Test-Path -LiteralPath $ServerSource)) { return (Resolve-Path -LiteralPath $ServerSource).Path }
    foreach ($candidate in @((Join-Path $PSScriptRoot 'server'), (Join-Path (Split-Path -Parent $PSScriptRoot) 'server'))) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'RaceNetShowdown.Server.exe')) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Install-ServerPayload {
    $source = Get-ServerPayloadSource
    if (-not $source) {
        Fail-Install 'Не найдена папка server рядом с установщиком. Распакуйте архив целиком.'
    }

    if ($source.TrimEnd('\') -eq $script:ServerDir.TrimEnd('\')) {
        Write-InstallLog 'Сервер уже установлен в ' + $script:ServerDir
        return
    }

    New-Item -ItemType Directory -Force -Path $script:ServerDir | Out-Null
    Write-InstallLog ('Копирую сервер в ' + $script:ServerDir + ' ...') 'Step'
    Copy-Item -Path (Join-Path $source '*') -Destination $script:ServerDir -Recurse -Force
    Write-InstallLog 'Сервер скопирован.' 'Ok'
}

function Set-ReleaseConfiguration {
    $configPath = Join-Path $script:ServerDir 'appsettings.json'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $config.RaceNet.ListenAnyIp = $false
    $config.RaceNet.CaptureRequests = $false
    $config.RaceNet.RecordCalls = $false
    $config.RaceNet.StoreProvider = 'Sqlite'
    $config.ConnectionStrings.RaceNet = 'Data Source=data/egonet-revival.db'
    $json = $config | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($configPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Ensure-ServerCertificates {
    $serverExe = Join-Path $script:ServerDir 'RaceNetShowdown.Server.exe'
    if (-not (Test-Path -LiteralPath $serverExe)) {
        Fail-Install ('Не найден сервер: ' + $serverExe)
    }

    Write-InstallLog 'Генерирую локальный корневой сертификат...' 'Step'
    Push-Location $script:ServerDir
    try {
        $output = & $serverExe '--regenerate-certs' 2>&1
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    foreach ($line in @($output)) {
        if ($line) { Write-InstallLog ('  ' + $line) }
    }

    if ($code -ne 0) {
        Fail-Install 'Сервер не смог создать сертификаты (код ' + $code + '). См. ' + $script:LogFile
    }

    $cerPath = Join-Path $script:ServerDir 'certs\codemasters-local-root-ca.cer'
    if (-not (Test-Path -LiteralPath $cerPath)) {
        Fail-Install 'Сертификат не создан: ' + $cerPath
    }

    $bytes = [System.IO.File]::ReadAllBytes($cerPath)
    if ($bytes.Length -ne $script:ExpectedCertLength) {
        Fail-Install ('Сертификат имеет длину ' + $bytes.Length + ', ожидается ' + $script:ExpectedCertLength + '.')
    }

    Write-InstallLog ('Сертификат: ' + $cerPath + ' (' + $bytes.Length + ' байт)') 'Ok'
    return $bytes
}

function Test-ServerHealth {
    param([int]$TimeoutSeconds = 30)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri 'http://127.0.0.1/health' -UseBasicParsing -TimeoutSec 2
            if ($response.StatusCode -eq 200) { return $true }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Start-TestServer {
    if (Test-ServerHealth -TimeoutSeconds 1) {
        Write-InstallLog 'Сервер RaceNet уже запущен.' 'Ok'
        return $true
    }

    Write-InstallLog 'Проверяю запуск сервера...' 'Step'
    $serverExe = Join-Path $script:ServerDir 'RaceNetShowdown.Server.exe'
    $process = Start-Process -FilePath $serverExe -WorkingDirectory $script:ServerDir -WindowStyle Hidden -PassThru
    $healthy = Test-ServerHealth -TimeoutSeconds 30

    if (-not $healthy) {
        try { $process.Kill() } catch { }
        Fail-Install ('Сервер не отвечает на http://127.0.0.1/health. Возможно, порты 80/443 заняты. Лог: ' + $script:LogFile)
    }

    Write-InstallLog 'Сервер отвечает: health = 200.' 'Ok'
    try {
        $process.Kill()
        $process.WaitForExit(5000) | Out-Null
    } catch { }
    return $true
}

function Enable-FriendAccess {
    $configPath = Join-Path $script:ServerDir 'appsettings.json'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $config.RaceNet.ListenAnyIp = $true
    $json = $config | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($configPath, $json, (New-Object System.Text.UTF8Encoding($false)))

    try {
        $existing = Get-NetFirewallRule -DisplayName $script:FirewallRule -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetFirewallRule -DisplayName $script:FirewallRule -Direction Inbound -Action Allow `
                -Protocol TCP -LocalPort 80, 443 -Profile Private, Domain | Out-Null
        }
        Write-InstallLog 'Друзья могут подключаться (firewall: TCP 80/443).' 'Ok'
    } catch {
        Write-InstallLog ('Не удалось добавить правило firewall: ' + $_.Exception.Message) 'Warn'
        Write-InstallLog 'Разрешите порты 80 и 443 вручную, иначе друг не подключится.' 'Warn'
    }
}

# ------------------------------------------------------------------- state ---

function Save-InstallState {
    param([string]$InstallMode, [string]$TargetGamePath, [string]$Thumbprint, [string]$HostsAddress, [bool]$Friends)

    $state = [pscustomobject]@{
        product    = 'RaceNet Local'
        version    = '0.1.0'
        mode       = $InstallMode
        gamePath   = $TargetGamePath
        installDir = $script:InstallDir
        thumbprint = $Thumbprint
        hostsIp    = $HostsAddress
        friends    = $Friends
        installed  = (Get-Date).ToString('s')
    }
    New-Item -ItemType Directory -Force -Path $script:InstallDir | Out-Null
    $json = $state | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($script:StatePath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Read-InstallState {
    if (-not (Test-Path -LiteralPath $script:StatePath)) { return $null }
    try { return Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json } catch { return $null }
}

# --------------------------------------------------------------- operations ---

function Install-LocalServer {
    param([string]$TargetGamePath, [switch]$FriendsAllowed)

    Write-InstallLog '=== Установка RaceNet Local (локальный сервер) ===' 'Step'
    Assert-GameFolder $TargetGamePath
    Write-InstallLog ('Папка игры: ' + $TargetGamePath)

    Stop-GameProcesses
    Install-ServerPayload
    Set-ReleaseConfiguration

    $rootCertificate = Ensure-ServerCertificates
    $thumbprint = Install-TrustedRoot -CerPath (Join-Path $script:ServerDir 'certs\codemasters-local-root-ca.cer')

    Set-GamePatch -TargetGamePath $TargetGamePath -RootCertificate $rootCertificate

    Set-HostsEntry -Path (Get-HostsPath) -Address '127.0.0.1'
    Clear-DnsCache

    if ($FriendsAllowed) { Enable-FriendAccess }
    else {
        $configPath = Join-Path $script:ServerDir 'appsettings.json'
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $config.RaceNet.ListenAnyIp = $false
        [System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
    }

    Set-Launchers -TargetGamePath $TargetGamePath
    Start-TestServer | Out-Null
    Save-InstallState -InstallMode 'Local' -TargetGamePath $TargetGamePath -Thumbprint $thumbprint `
        -HostsAddress '127.0.0.1' -Friends ([bool]$FriendsAllowed)

    Write-InstallLog '=== Готово ===' 'Ok'
    Write-InstallLog 'Запускайте игру ярлыком "DiRT Showdown - RaceNet" на рабочем столе.'
    Write-InstallLog 'Сначала откройте Challenges (челленджи), затем нужное достижение.'
}

function Install-FriendMode {
    param([string]$TargetGamePath, [string]$ServerAddress)

    Write-InstallLog '=== Подключение к серверу друга ===' 'Step'
    Assert-GameFolder $TargetGamePath

    $ServerAddress = $ServerAddress.Trim()
    $ServerAddress = $ServerAddress -replace '^https?://', ''
    $ServerAddress = $ServerAddress.TrimEnd('/')
    if (-not $ServerAddress) { Fail-Install 'Укажите IP-адрес сервера друга.' }

    Write-InstallLog ('Сервер друга: ' + $ServerAddress)
    Stop-GameProcesses

    Write-InstallLog 'Скачиваю корневой сертификат сервера друга...' 'Step'
    $certUrl = 'http://' + $ServerAddress + '/racenet-root-ca.cer'
    $certPath = Join-Path $env:TEMP 'racenetlocal-friend-root.cer'
    try {
        Invoke-WebRequest -Uri $certUrl -OutFile $certPath -UseBasicParsing -TimeoutSec 20
    } catch {
        Fail-Install ('Не удалось скачать ' + $certUrl + '. Сервер друга запущен? Порт 80 открыт?')
    }

    $bytes = [System.IO.File]::ReadAllBytes($certPath)
    if ($bytes.Length -ne $script:ExpectedCertLength) {
        Fail-Install ('Сертификат друга неверной длины: ' + $bytes.Length)
    }

    $thumbprint = Install-TrustedRoot -CerPath $certPath
    Set-GamePatch -TargetGamePath $TargetGamePath -RootCertificate $bytes
    Set-HostsEntry -Path (Get-HostsPath) -Address $ServerAddress
    Clear-DnsCache

    $launchCmd = Join-Path $script:InstallDir 'Launch-DiRT-Showdown.cmd'
    $text = @"
@echo off
start "" "steam://rungameid/201700"
exit /b 0
"@
    New-Item -ItemType Directory -Force -Path $script:InstallDir | Out-Null
    [System.IO.File]::WriteAllText($launchCmd, $text, [System.Text.Encoding]::ASCII)

    if (-not $NoShortcut) {
        $icon = Join-Path $TargetGamePath 'showdown.exe'
        $desktop = [Environment]::GetFolderPath('Desktop')
        New-ShortcutFile -Path (Join-Path $desktop ($script:ShortcutName + '.lnk')) `
            -Target $launchCmd -WorkingDirectory $script:InstallDir -Icon ($icon + ',0') `
            -Description 'Запустить DiRT Showdown (RaceNet-сервер друга)'
    }

    Save-InstallState -InstallMode 'Friend' -TargetGamePath $TargetGamePath -Thumbprint $thumbprint `
        -HostsAddress $ServerAddress -Friends $true

    Write-InstallLog '=== Готово ===' 'Ok'
    Write-InstallLog ('Игра будет ходить на сервер ' + $ServerAddress + '.')
}

function Uninstall-RaceNetLocal {
    param([switch]$KeepServerData)

    Write-InstallLog '=== Удаление RaceNet Local ===' 'Step'
    $state = Read-InstallState

    if (Get-Process -Name 'RaceNetShowdown.Server' -ErrorAction SilentlyContinue) {
        Write-InstallLog 'Останавливаю сервер...' 'Step'
        Get-Process -Name 'RaceNetShowdown.Server' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }

    $targetGamePath = $null
    if ($state -and $state.gamePath) { $targetGamePath = $state.gamePath }
    if (-not $targetGamePath) { $targetGamePath = Find-GameFolder -Explicit $GamePath }

    if ($targetGamePath -and (Test-Path -LiteralPath (Join-Path $targetGamePath 'showdown.exe'))) {
        Restore-GameFiles -TargetGamePath $targetGamePath | Out-Null
    } else {
        Write-InstallLog 'Папка игры не найдена - пропускаю восстановление exe.' 'Warn'
    }

    Remove-HostsEntry -Path (Get-HostsPath)
    Clear-DnsCache

    $thumbprint = $null
    if ($state -and $state.thumbprint) { $thumbprint = $state.thumbprint }
    Remove-TrustedRoot -Thumbprint $thumbprint

    try {
        $rule = Get-NetFirewallRule -DisplayName $script:FirewallRule -ErrorAction SilentlyContinue
        if ($rule) { Remove-NetFirewallRule -DisplayName $script:FirewallRule -ErrorAction SilentlyContinue }
    } catch { }

    Remove-Launchers

    if (-not $KeepServerData) {
        if (Test-Path -LiteralPath $script:InstallDir) {
            try {
                Remove-Item -LiteralPath $script:InstallDir -Recurse -Force
                Write-InstallLog ('Удалена папка ' + $script:InstallDir) 'Ok'
            } catch {
                Write-InstallLog ('Не удалось удалить ' + $script:InstallDir + ': ' + $_.Exception.Message) 'Warn'
            }
        }
    }

    Write-InstallLog '=== Удаление завершено ===' 'Ok'
    Write-InstallLog 'Если Steam перезапишет exe - запустите "Проверить целостность файлов" в свойствах игры.'
}

# --------------------------------------------------------------------- GUI ---

function Show-InstallerGui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'RaceNet Local - DiRT Showdown'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(820, 640)
    $form.MinimumSize = New-Object System.Drawing.Size(760, 560)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'RaceNet Local: DiRT Showdown'
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(16, 14)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = 'Локальный сервер RaceNet: челленджи, друзья и онлайн-достижения без серверов Codemasters.'
    $subtitle.AutoSize = $true
    $subtitle.ForeColor = [System.Drawing.Color]::DimGray
    $subtitle.Location = New-Object System.Drawing.Point(18, 48)

    $modeGroup = New-Object System.Windows.Forms.GroupBox
    $modeGroup.Text = 'Режим'
    $modeGroup.Location = New-Object System.Drawing.Point(18, 78)
    $modeGroup.Size = New-Object System.Drawing.Size(760, 64)

    $radioLocal = New-Object System.Windows.Forms.RadioButton
    $radioLocal.Text = 'Локальный сервер (я играю один)'
    $radioLocal.Location = New-Object System.Drawing.Point(14, 24)
    $radioLocal.AutoSize = $true
    $radioLocal.Checked = ($Mode -ne 'Friend')

    $radioFriend = New-Object System.Windows.Forms.RadioButton
    $radioFriend.Text = 'Подключиться к серверу друга'
    $radioFriend.Location = New-Object System.Drawing.Point(330, 24)
    $radioFriend.AutoSize = $true
    $radioFriend.Checked = ($Mode -eq 'Friend')

    $modeGroup.Controls.Add($radioLocal)
    $modeGroup.Controls.Add($radioFriend)

    $gameLabel = New-Object System.Windows.Forms.Label
    $gameLabel.Text = 'Папка игры:'
    $gameLabel.AutoSize = $true
    $gameLabel.Location = New-Object System.Drawing.Point(18, 160)

    $gameBox = New-Object System.Windows.Forms.TextBox
    $gameBox.Location = New-Object System.Drawing.Point(120, 156)
    $gameBox.Size = New-Object System.Drawing.Size(560, 26)

    $browseButton = New-Object System.Windows.Forms.Button
    $browseButton.Text = 'Обзор...'
    $browseButton.Location = New-Object System.Drawing.Point(690, 154)
    $browseButton.Size = New-Object System.Drawing.Size(88, 28)

    $friendLabel = New-Object System.Windows.Forms.Label
    $friendLabel.Text = 'IP сервера друга:'
    $friendLabel.AutoSize = $true
    $friendLabel.Location = New-Object System.Drawing.Point(18, 202)

    $friendBox = New-Object System.Windows.Forms.TextBox
    $friendBox.Location = New-Object System.Drawing.Point(160, 198)
    $friendBox.Size = New-Object System.Drawing.Size(180, 26)
    $friendBox.Text = $Server
    $friendBox.Enabled = $false

    $friendsCheck = New-Object System.Windows.Forms.CheckBox
    $friendsCheck.Text = 'Разрешить подключение друзей (Radmin VPN / LAN)'
    $friendsCheck.Location = New-Object System.Drawing.Point(370, 198)
    $friendsCheck.AutoSize = $true
    $friendsCheck.Checked = [bool]$AllowFriends

    $logLabel = New-Object System.Windows.Forms.Label
    $logLabel.Text = 'Журнал:'
    $logLabel.AutoSize = $true
    $logLabel.Location = New-Object System.Drawing.Point(18, 238)

    $logBox = New-Object System.Windows.Forms.RichTextBox
    $logBox.Location = New-Object System.Drawing.Point(18, 262)
    $logBox.Size = New-Object System.Drawing.Size(760, 280)
    $logBox.ReadOnly = $true
    $logBox.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 24)
    $logBox.ForeColor = [System.Drawing.Color]::Gainsboro
    $logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
    $logBox.Anchor = 'Top,Left,Right,Bottom'

    $installButton = New-Object System.Windows.Forms.Button
    $installButton.Text = 'Установить'
    $installButton.Location = New-Object System.Drawing.Point(520, 556)
    $installButton.Size = New-Object System.Drawing.Size(120, 32)
    $installButton.Anchor = 'Bottom,Right'

    $uninstallButton = New-Object System.Windows.Forms.Button
    $uninstallButton.Text = 'Удалить мод'
    $uninstallButton.Location = New-Object System.Drawing.Point(650, 556)
    $uninstallButton.Size = New-Object System.Drawing.Size(128, 32)
    $uninstallButton.Anchor = 'Bottom,Right'

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = 'Закрыть'
    $closeButton.Location = New-Object System.Drawing.Point(18, 556)
    $closeButton.Size = New-Object System.Drawing.Size(100, 32)
    $closeButton.Anchor = 'Bottom,Left'

    $form.Controls.AddRange(@($title, $subtitle, $modeGroup, $gameLabel, $gameBox, $browseButton,
            $friendLabel, $friendBox, $friendsCheck, $logLabel, $logBox, $installButton, $uninstallButton, $closeButton))

    $script:GuiLog = $logBox

    $radioLocal.Add_CheckedChanged({
            $friendBox.Enabled = $false
            $friendsCheck.Enabled = $true
        })
    $radioFriend.Add_CheckedChanged({
            $friendBox.Enabled = $true
            $friendsCheck.Enabled = $false
        })

    $browseButton.Add_Click({
            $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $dialog.Description = 'Выберите папку DiRT Showdown (где лежит showdown.exe)'
            if (Test-Path -LiteralPath $gameBox.Text) { $dialog.SelectedPath = $gameBox.Text }
            if ($dialog.ShowDialog() -eq 'OK') { $gameBox.Text = $dialog.SelectedPath }
        })

    $installButton.Add_Click({
            $installButton.Enabled = $false
            $uninstallButton.Enabled = $false
            $logBox.Clear()
            try {
                $target = $gameBox.Text.Trim()
                if (-not $target) {
                    $target = Find-GameFolder -Explicit ''
                    if ($target) { $gameBox.Text = $target }
                }
                if ($radioFriend.Checked) {
                    Install-FriendMode -TargetGamePath $target -ServerAddress $friendBox.Text
                } else {
                    Install-LocalServer -TargetGamePath $target -FriendsAllowed:$friendsCheck.Checked
                }
                [System.Windows.Forms.MessageBox]::Show(
                    "Готово.`r`n`r`nЗапустите игру ярлыком `"DiRT Showdown - RaceNet`" и откройте Challenges.",
                    'RaceNet Local', 'OK', 'Information') | Out-Null
            } catch {
                [System.Windows.Forms.MessageBox]::Show(
                    $_.Exception.Message, 'Ошибка установки', 'OK', 'Error') | Out-Null
            } finally {
                $installButton.Enabled = $true
                $uninstallButton.Enabled = $true
            }
        })

    $uninstallButton.Add_Click({
            $confirm = [System.Windows.Forms.MessageBox]::Show(
                'Восстановить файлы игры и удалить мод?', 'Удаление',
                'YesNo', 'Question')
            if ($confirm -ne 'Yes') { return }
            $installButton.Enabled = $false
            $uninstallButton.Enabled = $false
            $logBox.Clear()
            try {
                Uninstall-RaceNetLocal
                [System.Windows.Forms.MessageBox]::Show('Мод удалён.', 'RaceNet Local', 'OK', 'Information') | Out-Null
            } catch {
                [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Ошибка', 'OK', 'Error') | Out-Null
            } finally {
                $installButton.Enabled = $true
                $uninstallButton.Enabled = $true
            }
        })

    $closeButton.Add_Click({ $form.Close() })

    $form.Add_Shown({
            if (-not $gameBox.Text) {
                $found = Find-GameFolder -Explicit ''
                if ($found) { $gameBox.Text = $found }
            }
            if (-not $gameBox.Text) {
                Write-InstallLog 'Папка игры не найдена автоматически - выберите её вручную.' 'Warn'
            }
            Write-InstallLog 'Готово к установке. Игра должна быть закрыта.'
            $form.Activate()
        })

    [void]$form.ShowDialog()
}

# -------------------------------------------------------------------- main ---

if (-not $NoElevate -and -not (Test-IsAdmin)) {
    Restart-Elevated
    return
}

if ($Gui -and -not $Silent) {
    Show-InstallerGui
    return
}

if ($Uninstall) {
    Uninstall-RaceNetLocal -KeepServerData:$KeepData
    return
}

if ($RestoreOnly) {
    $target = Find-GameFolder -Explicit $GamePath
    if (-not $target) { Fail-Install 'Папка игры не найдена.' }
    Restore-GameFiles -TargetGamePath $target | Out-Null
    Remove-HostsEntry -Path (Get-HostsPath)
    return
}

if ($Mode -eq 'Friend') {
    Install-FriendMode -TargetGamePath (Find-GameFolder -Explicit $GamePath) -ServerAddress $Server
    return
}

Install-LocalServer -TargetGamePath (Find-GameFolder -Explicit $GamePath) -FriendsAllowed:$AllowFriends
