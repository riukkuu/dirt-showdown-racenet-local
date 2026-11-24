#Requires -Version 5.1
<#
.SYNOPSIS
    Собирает релизный zip: сервер + установщик + документация.

.DESCRIPTION
    1. Скачивает upstream EgoNet Revival по закреплённому коммиту.
    2. Применяет наши патчи (patches/*.patch) и проверяет хеши.
    3. Публикует self-contained сервер (win-x64, .NET 10).
    4. Собирает dist/RaceNetLocal-DiRT-Showdown-v<версия>.zip + .sha256.

    Требуется .NET SDK 10 и доступ в интернет (NuGet + GitHub).
    Git не требуется.

.PARAMETER Version
    Версия релиза без префикса v, например 0.1.0.

.PARAMETER UpstreamZip
    Локальный zip upstream (для офлайн-сборки/тестов). Если не задан - скачивается.

.PARAMETER NuGetConfig
    Дополнительный NuGet.config (например, с локальным источником пакетов).
#>
[CmdletBinding()]
param(
    [string]$Version = '0.1.0',
    [string]$UpstreamCommit = '9d2c7d6bcc716e10e3327e26c1dbe3a1434d37d2',
    [string]$UpstreamZip = '',
    [string]$NuGetConfig = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoRoot = Split-Path -Parent $PSScriptRoot
$workRoot = Join-Path $repoRoot '.work'
$sourceDir = Join-Path $workRoot 'upstream'
$publishDir = Join-Path $workRoot 'publish'
$distDir = Join-Path $repoRoot 'dist'
$packageName = "RaceNetLocal-DiRT-Showdown-v$Version"
$packageDir = Join-Path $distDir $packageName
$zipPath = Join-Path $distDir ($packageName + '.zip')

function Write-Step([string]$Message) {
    Write-Host ''
    Write-Host ('=== ' + $Message + ' ===') -ForegroundColor Cyan
}

function Assert-LastExitCode([string]$What) {
    if ($LASTEXITCODE -ne 0) {
        throw ($What + ' завершилось с кодом ' + $LASTEXITCODE)
    }
}

Write-Step 'Проверка инструментов'
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $dotnet) { throw '.NET SDK не найден. Установите .NET SDK 10: https://dotnet.microsoft.com/download' }
dotnet --version
Assert-LastExitCode 'dotnet --version'

if (Test-Path -LiteralPath $workRoot) { Remove-Item -LiteralPath $workRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

Write-Step 'Исходники upstream'
if ($UpstreamZip) {
    if (-not (Test-Path -LiteralPath $UpstreamZip)) { throw "Не найден архив: $UpstreamZip" }
    $zip = (Resolve-Path -LiteralPath $UpstreamZip).Path
    Write-Host "Использую локальный архив: $zip"
} else {
    $zip = Join-Path $workRoot 'egonet-revival.zip'
    $url = "https://codeload.github.com/Berleis/egonet-revival/zip/$UpstreamCommit"
    Write-Host "Скачиваю $url"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
}

Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $workRoot 'expand') -Force
$expanded = Get-ChildItem -LiteralPath (Join-Path $workRoot 'expand') -Directory | Select-Object -First 1
if (-not $expanded) { throw 'Не удалось распаковать архив upstream.' }
Move-Item -LiteralPath $expanded.FullName -Destination $sourceDir
Write-Host ('Исходники: ' + $sourceDir)

Write-Step 'Применение патчей'
& (Join-Path $PSScriptRoot 'apply-patches.ps1') -SourceRoot $sourceDir
Assert-LastExitCode 'apply-patches.ps1'

Write-Step 'Конфигурация релиза'
$serverProjectDir = Join-Path $sourceDir 'src\RaceNetShowdown.Server'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'appsettings.release.json') `
    -Destination (Join-Path $serverProjectDir 'appsettings.json') -Force

foreach ($file in @('appsettings.Development.json', 'appsettings.Grid2Discovery.json', 'appsettings.Hosting.example.json')) {
    $path = Join-Path $serverProjectDir $file
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}

Write-Step 'Обновление уязвимой транзитивной зависимости'
# EF Core 10.0.12 тянет System.Security.Cryptography.Pkcs 9.0.11, на которую есть
# CVE-2026-70162 (средняя) и CVE-2026-84008 (высокая). Сервер не разбирает
# недоверенный CMS/PKCS#7, но фиксируем исправленную версию, чтобы релиз
# собирался без предупреждений NU1902/NU1903.
$pkcsVersion = '10.0.15'
& dotnet add (Join-Path $serverProjectDir 'RaceNetShowdown.Server.csproj') package System.Security.Cryptography.Pkcs --version $pkcsVersion --no-restore
Assert-LastExitCode 'dotnet add package System.Security.Cryptography.Pkcs'

Write-Step 'Публикация сервера (self-contained win-x64)'
$publishArgs = @(
    'publish',
    (Join-Path $serverProjectDir 'RaceNetShowdown.Server.csproj'),
    '-c', 'Release',
    '-r', 'win-x64',
    '--self-contained', 'true',
    '-p:PublishReadyToRun=false',
    '-p:DebugType=none',
    '-o', $publishDir,
    '--nologo',
    '-v', 'minimal'
)
if ($NuGetConfig) { $publishArgs += @('--configfile', $NuGetConfig) }

& dotnet @publishArgs
Assert-LastExitCode 'dotnet publish'

Write-Step 'Чистка лишнего из публикации'
foreach ($item in @('appsettings.Development.json', 'appsettings.Grid2Discovery.json',
        'appsettings.Hosting.example.json', 'logs', 'data', 'certs')) {
    $path = Join-Path $publishDir $item
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
}
Get-ChildItem -LiteralPath $publishDir -Filter '*.pdb' | Remove-Item -Force

Write-Step 'Сборка пакета'
if (Test-Path -LiteralPath $packageDir) { Remove-Item -LiteralPath $packageDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $packageDir | Out-Null

Copy-Item -LiteralPath (Join-Path $repoRoot 'installer\Install.cmd') -Destination $packageDir
Copy-Item -LiteralPath (Join-Path $repoRoot 'installer\Install.ps1') -Destination $packageDir
Copy-Item -LiteralPath (Join-Path $repoRoot 'README.md') -Destination $packageDir
Copy-Item -LiteralPath (Join-Path $repoRoot 'README.en.md') -Destination $packageDir
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination $packageDir
Copy-Item -LiteralPath (Join-Path $repoRoot 'NOTICE.md') -Destination $packageDir
Copy-Item -LiteralPath (Join-Path $repoRoot 'CHANGELOG.md') -Destination $packageDir

$docsTarget = Join-Path $packageDir 'docs'
New-Item -ItemType Directory -Force -Path $docsTarget | Out-Null
Copy-Item -Path (Join-Path $repoRoot 'docs\*.md') -Destination $docsTarget -Exclude 'PUBLISHING.md'

$toolsTarget = Join-Path $packageDir 'tools'
New-Item -ItemType Directory -Force -Path $toolsTarget | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\patch-game.ps1') -Destination $toolsTarget

$notes = Join-Path $repoRoot ('release-notes\v' + $Version + '.md')
if (Test-Path -LiteralPath $notes) {
    Copy-Item -LiteralPath $notes -Destination (Join-Path $packageDir 'RELEASE_NOTES.md')
}

Copy-Item -LiteralPath $publishDir -Destination (Join-Path $packageDir 'server') -Recurse
[System.IO.File]::WriteAllText((Join-Path $packageDir 'VERSION.txt'), $Version + "`r`n", [System.Text.Encoding]::ASCII)

if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
# Собираем zip вручную: Compress-Archive в Windows PowerShell 5.1 пишет в именах
# записей обратные слэши (нарушение ZIP-спеки), из-за чего архив странно
# выглядит в не-Windows инструментах. Здесь имена всегда через "/".
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $packageRoot = (Resolve-Path -LiteralPath $packageDir).Path.TrimEnd('\')
    foreach ($file in Get-ChildItem -LiteralPath $packageDir -Recurse -File) {
        $relative = $file.FullName.Substring($packageRoot.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $file.FullName, ($packageName + '/' + $relative),
            [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $archive.Dispose()
}

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$hashFile = $zipPath + '.sha256'
[System.IO.File]::WriteAllText($hashFile, ($hash + '  ' + (Split-Path -Leaf $zipPath) + "`n"), [System.Text.Encoding]::ASCII)

$sizeMb = [Math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 1)
Write-Step 'Готово'
Write-Host ("Пакет:  " + $zipPath)
Write-Host ("Размер: " + $sizeMb + ' MB')
Write-Host ("SHA256: " + $hash)
