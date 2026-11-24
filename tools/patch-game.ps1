#Requires -Version 5.1
<#
.SYNOPSIS
    Патч/восстановление/проверка встроенного сертификата в DiRT Showdown.

.DESCRIPTION
    Меняет 1003 байта встроенного корневого сертификата Codemasters внутри
    showdown.exe / showdown_avx.exe на локальный CA RaceNet Local.
    Резервные копии: *.racenet-original.bak.

    Это «ручной» инструмент. Обычному пользователю он не нужен - всё делает
    Install.ps1.

.EXAMPLE
    .\tools\patch-game.ps1 -GamePath "D:\Steam\steamapps\common\DiRT Showdown" `
        -Certificate "$env:LOCALAPPDATA\RaceNetLocal\server\certs\codemasters-local-root-ca.cer"

.EXAMPLE
    .\tools\patch-game.ps1 -GamePath "D:\...\DiRT Showdown" -Status

.EXAMPLE
    .\tools\patch-game.ps1 -GamePath "D:\...\DiRT Showdown" -Restore
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GamePath,
    [string]$Certificate = '',
    [switch]$Restore,
    [switch]$Status,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$executables = @('showdown.exe', 'showdown_avx.exe')
$needle = 'Codemasters Online Root CA'
$expectedLength = 1003

function Get-DerLength {
    param([byte[]]$Bytes, [int]$Offset)
    if ($Offset + 2 -gt $Bytes.Length) { return 0 }
    if ($Bytes[$Offset] -ne 0x30) { return 0 }
    $marker = $Bytes[$Offset + 1]
    if (($marker -band 0x80) -eq 0) { return 2 + $marker }
    $n = $marker -band 0x7f
    if ($n -lt 1 -or $n -gt 4) { return 0 }
    if ($Offset + 2 + $n -gt $Bytes.Length) { return 0 }
    [long]$len = 0
    for ($i = 0; $i -lt $n; $i++) { $len = ($len -shl 8) -bor $Bytes[$Offset + 2 + $i] }
    return [int](2 + $n + $len)
}

function Get-EmbeddedRoots {
    param([byte[]]$Bytes)
    $roots = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[int]
    $ascii = [System.Text.Encoding]::ASCII.GetString($Bytes)
    $index = $ascii.IndexOf($needle, [System.StringComparison]::Ordinal)
    while ($index -ge 0) {
        $start = [Math]::Max(0, $index - 800)
        for ($offset = $start; $offset -le $index; $offset++) {
            if ($Bytes[$offset] -ne 0x30) { continue }
            $length = Get-DerLength -Bytes $Bytes -Offset $offset
            if ($length -lt 256 -or $length -gt 8192) { continue }
            if ($offset + $length -gt $Bytes.Length) { continue }
            if ($offset + $length -le $index) { continue }
            $chunk = New-Object byte[] $length
            [Array]::Copy($Bytes, $offset, $chunk, 0, $length)
            try {
                $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($chunk)
            } catch { continue }
            if ($cert.Subject -like '*CN=Codemasters Online Root CA*' -and
                $cert.Subject -like '*OU=Codemasters Online*') {
                if ($seen.Add($offset)) {
                    [void]$roots.Add([pscustomobject]@{ Offset = $offset; Bytes = $chunk })
                }
                $offset = $offset + $length - 1
            }
        }
        $index = $ascii.IndexOf($needle, $index + 1, [System.StringComparison]::Ordinal)
    }
    return $roots
}

function Test-BytesEqual {
    param([byte[]]$Left, [byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($i = 0; $i -lt $Left.Length; $i++) { if ($Left[$i] -ne $Right[$i]) { return $false } }
    return $true
}

if (-not (Test-Path -LiteralPath (Join-Path $GamePath 'showdown.exe'))) {
    throw "showdown.exe не найден в $GamePath"
}

$rootBytes = $null
if (-not $Restore -and -not $Status) {
    if (-not $Certificate) { throw 'Укажите -Certificate path\to\codemasters-local-root-ca.cer' }
    if (-not (Test-Path -LiteralPath $Certificate)) { throw "Сертификат не найден: $Certificate" }
    $rootBytes = [System.IO.File]::ReadAllBytes($Certificate)
    if ($rootBytes.Length -ne $expectedLength) {
        throw "Длина сертификата $($rootBytes.Length), ожидается $expectedLength."
    }
}

foreach ($name in $executables) {
    $path = Join-Path $GamePath $name
    if (-not (Test-Path -LiteralPath $path)) { Write-Host "$name : нет файла"; continue }

    if ($Restore) {
        $backup = $path + '.racenet-original.bak'
        if (Test-Path -LiteralPath $backup) {
            Copy-Item -LiteralPath $backup -Destination $path -Force
            Write-Host "$name : восстановлен из backup"
        } else {
            Write-Host "$name : backup не найден"
        }
        continue
    }

    $bytes = [System.IO.File]::ReadAllBytes($path)
    $roots = @(Get-EmbeddedRoots -Bytes $bytes)
    if ($roots.Count -eq 0) { Write-Host "$name : сертификат Codemasters не найден"; continue }

    if ($Status) {
        foreach ($root in $roots) {
            $subject = ([System.Security.Cryptography.X509Certificates.X509Certificate2]::new($root.Bytes)).Subject
            Write-Host ("{0} : offset 0x{1:x}, {2} байт, {3}" -f $name, $root.Offset, $root.Bytes.Length, $subject)
        }
        continue
    }

    $changed = $false
    foreach ($root in $roots) {
        if (Test-BytesEqual -Left $root.Bytes -Right $rootBytes) {
            Write-Host "$name : уже пропатчен"
            continue
        }
        if ($root.Bytes.Length -ne $rootBytes.Length) { throw "$name : длина не совпадает" }
        $backup = $path + '.racenet-original.bak'
        if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $path -Destination $backup -Force }
        [Array]::Copy($rootBytes, 0, $bytes, $root.Offset, $rootBytes.Length)
        $changed = $true
        Write-Host ("{0} : пропатчен на 0x{1:x}" -f $name, $root.Offset)
    }
    if ($changed) { [System.IO.File]::WriteAllBytes($path, $bytes) }
}
