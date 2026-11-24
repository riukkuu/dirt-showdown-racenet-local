#Requires -Version 5.1
<#
.SYNOPSIS
    Применяет наши unified-diff патчи к дереву исходников EgoNet Revival.

.DESCRIPTION
    Патчи в patches/ описывают только наши изменения (2 файла). Скрипт не требует
    git: используется встроенный минимальный applier для unified diff.

    После применения проверяются SHA256 итоговых файлов. Если upstream изменился,
    скрипт остановится с понятной ошибкой - это защита от тихой поломки сборки.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,
    [string]$PatchDirectory = ''
)

$ErrorActionPreference = 'Stop'

if (-not $PatchDirectory) {
    $PatchDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'patches'
}

$expectedHashes = @{
    'src/RaceNetShowdown.Server/RaceNet/EgoNetChallengePayloads.cs' = 'CA99465F108BA2F266EB0D1095FD9256F14DF22DE70B87EEC2764043484EC94B'
    'src/RaceNetShowdown.Server/RaceNet/RaceNetResponder.cs'       = 'DE733FD1595264A56644AA5ECC776842A065CF8E4202BAB899B53DCE635248AF'
}

function Apply-UnifiedPatch {
    param([string]$File, [string]$PatchFile)

    $sourceLines = [System.Collections.Generic.List[string]]::new()
    $text = [System.IO.File]::ReadAllText($File)
    foreach ($line in ($text -split "`n")) { [void]$sourceLines.Add($line) }

    $patchLines = [System.IO.File]::ReadAllLines($PatchFile)
    $result = [System.Collections.Generic.List[string]]::new()
    $sourceIndex = 0
    $patchIndex = 0

    while ($patchIndex -lt $patchLines.Count -and -not $patchLines[$patchIndex].StartsWith('@@')) {
        $patchIndex++
    }

    while ($patchIndex -lt $patchLines.Count) {
        $header = $patchLines[$patchIndex]
        $match = [regex]::Match($header, '^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')
        if (-not $match.Success) {
            throw "Некорректный заголовок hunk в $PatchFile : $header"
        }

        $oldStart = [int]$match.Groups[1].Value
        if ($match.Groups[2].Success) { $oldCount = [int]$match.Groups[2].Value } else { $oldCount = 1 }

        $targetIndex = $oldStart - 1
        while ($sourceIndex -lt $targetIndex -and $sourceIndex -lt $sourceLines.Count) {
            [void]$result.Add($sourceLines[$sourceIndex])
            $sourceIndex++
        }

        $patchIndex++
        while ($patchIndex -lt $patchLines.Count -and -not $patchLines[$patchIndex].StartsWith('@@')) {
            $line = $patchLines[$patchIndex]
            if ($line.StartsWith('+')) {
                [void]$result.Add($line.Substring(1))
            } elseif ($line.StartsWith('-')) {
                if ($sourceIndex -ge $sourceLines.Count) {
                    throw "Патч выходит за конец файла $File (строка $patchIndex)"
                }
                $sourceIndex++
            } elseif ($line.StartsWith(' ')) {
                [void]$result.Add($line.Substring(1))
                $sourceIndex++
            } elseif ($line.StartsWith('\')) {
                # "\ No newline at end of file"
            } elseif ($line -eq '') {
                # разделитель между hunk'ами
            } else {
                throw "Неизвестная строка патча в $PatchFile : $line"
            }
            $patchIndex++
        }

        while ($patchIndex -lt $patchLines.Count -and $patchLines[$patchIndex] -eq '') {
            $patchIndex++
        }
    }

    while ($sourceIndex -lt $sourceLines.Count) {
        [void]$result.Add($sourceLines[$sourceIndex])
        $sourceIndex++
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($File, ($result -join "`n"), $utf8)
}

foreach ($patchFile in (Get-ChildItem -LiteralPath $PatchDirectory -Filter '*.patch' | Sort-Object Name)) {
    $relative = $null
    foreach ($line in [System.IO.File]::ReadAllLines($patchFile.FullName)) {
        if ($line.StartsWith('+++ b/')) {
            $relative = $line.Substring(6).Trim()
            break
        }
    }
    if (-not $relative) { throw "В патче нет заголовка +++ b/: $($patchFile.Name)" }

    $target = Join-Path $SourceRoot ($relative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $target)) { throw "Файл для патча не найден: $target" }

    Write-Host ("Применяю {0} -> {1}" -f $patchFile.Name, $relative)
    Apply-UnifiedPatch -File $target -PatchFile $patchFile.FullName
}

foreach ($relative in $expectedHashes.Keys) {
    $target = Join-Path $SourceRoot ($relative -replace '/', '\')
    $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($hash -ne $expectedHashes[$relative]) {
        throw ("SHA256 не совпал после патча: {0}`n  ожидался {1}`n  получен  {2}`n" -f $relative, $expectedHashes[$relative], $hash) +
            'Upstream, вероятно, изменился. Обновите патчи (git diff) и хеши в tools/apply-patches.ps1.'
    }
    Write-Host ("  OK {0}" -f $relative)
}

Write-Host 'Все патчи применены, хеши совпадают.'
