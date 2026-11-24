# Установка и удаление

## Обычная установка (GUI)

1. Скачайте `RaceNetLocal-DiRT-Showdown-v<версия>.zip` из Releases.
2. Распакуйте **целиком** (не запускайте из архива: установщику нужна папка
   `server` рядом).
3. Закройте DiRT Showdown.
4. Запустите `Install.cmd`, подтвердите UAC.
5. Проверьте папку игры (определяется автоматически), при необходимости нажмите
   «Обзор...».
6. Нажмите **Установить**.

Установщик выполняет:

1. Поиск игры: реестр Steam → `libraryfolders.vdf` → типовые пути на дисках.
2. Копирование сервера в `%LOCALAPPDATA%\RaceNetLocal\server`.
3. Генерацию локального корневого сертификата (`--regenerate-certs`).
4. Патч `showdown.exe` и `showdown_avx.exe`: замена 1003 байт встроенного
   сертификата Codemasters (создаются `.racenet-original.bak`).
5. Установку сертификата в `Cert:\CurrentUser\Root`.
6. Блок в `hosts`:
   ```
   # --- RaceNetLocal begin ---
   127.0.0.1 prod.egonet.codemasters.com
   ... ещё 8 имён ...
   # --- RaceNetLocal end ---
   ```
7. Ярлыки «DiRT Showdown — RaceNet» и «Остановить RaceNet-сервер».
8. Проверку `http://127.0.0.1/health` (ожидается 200).

## Тихая установка (CLI)

```powershell
# локальный сервер, игра определяется автоматически
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Silent

# свой путь к игре
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Silent -GamePath "D:\Steam\steamapps\common\DiRT Showdown"

# разрешить друзей (Radmin VPN / LAN): сервер слушает все интерфейсы + firewall
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Silent -AllowFriends

# подключиться к серверу друга
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Mode Friend -Server 203.0.113.10

# удалить мод (восстановить exe, hosts, сертификат, ярлыки)
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Uninstall

# удалить мод, но оставить базу/логи сервера
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Uninstall -KeepData

# только восстановить exe и hosts, сервер оставить
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -RestoreOnly
```

Параметры: `-Mode Local|Friend`, `-GamePath`, `-Server`, `-AllowFriends`,
`-KeepData`, `-NoShortcut`, `-HostsFile` (для тестов), `-ServerSource` (папка
`server` вручную), `-NoElevate` (не запрашивать UAC; запускать из-под админа).

## Ручная установка (если установщик не подходит)

1. Скопируйте `server` в `%LOCALAPPDATA%\RaceNetLocal\server`.
2. В этой папке выполните `RaceNetShowdown.Server.exe --regenerate-certs`.
3. Пропатчите exe сертификатом `certs\codemasters-local-root-ca.cer`
   (инструмент: `tools\patch-game.ps1` — см. ниже, либо установщик).
4. Добавьте блок в `hosts` (см. выше).
5. Запускайте `server\RaceNetShowdown.Server.exe` из этой папки.

Для ручного патча есть отдельный скрипт:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\patch-game.ps1 `
  -GamePath "D:\Steam\steamapps\common\DiRT Showdown" `
  -Certificate "C:\...\RaceNetLocal\server\certs\codemasters-local-root-ca.cer"
```

Он делает только подмену сертификата (без hosts, без сертификата в хранилище).

## Где что лежит

| Путь | Что |
|---|---|
| `%LOCALAPPDATA%\RaceNetLocal\server` | сервер, `certs`, `data`, `logs` |
| `%LOCALAPPDATA%\RaceNetLocal\install-state.json` | режим, путь к игре, отпечаток сертификата |
| `%LOCALAPPDATA%\RaceNetLocal\Launch-DiRT-Showdown.cmd` | запуск сервера + игры |
| `%TEMP%\RaceNetLocal-install.log` | журнал установки |
| `%ProgramData%\RaceNetLocal\hosts.before-racenetlocal.bak` | копия hosts до первого изменения |

## Проверка после установки

1. **Сервер.** Откройте <http://127.0.0.1/health> — должен вернуться JSON с
   `"ok":true`. Это же проверяет установщик в конце.
2. **Hosts.** В `C:\Windows\System32\drivers\etc\hosts` появился блок
   `# --- RaceNetLocal begin ---` со строкой `127.0.0.1 prod.egonet.codemasters.com`.
3. **Exe.** Рядом с `showdown.exe` и `showdown_avx.exe` лежат
   `*.racenet-original.bak` — значит патч применился.
4. **Первый запуск.** Ярлык **«DiRT Showdown — RaceNet»** поднимает сервер
   (окно свёрнуто), ждёт ответа `health` и запускает игру через Steam. Окно
   сервера закрывать нельзя — пока он работает, игра видит RaceNet.
5. **Остановка.** Ярлык **«Остановить RaceNet-сервер»** (меню «Пуск» →
   RaceNet Local) или `taskkill /IM RaceNetShowdown.Server.exe /F`.

Если ярлык пишет, что сервер не отвечает, — почти всегда заняты порты 80/443,
см. [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Удаление

GUI: `Install.cmd` → **Удалить мод**.

Вручную (порядок важен):

1. Закрыть игру и сервер (`taskkill /IM RaceNetShowdown.Server.exe /F`).
2. Восстановить `showdown.exe` и `showdown_avx.exe` из `.racenet-original.bak`.
3. Удалить блок `# --- RaceNetLocal ---` из `hosts` и выполнить
   `ipconfig /flushdns`.
4. Удалить сертификат `Codemasters Online Root CA` из
   `Cert:\CurrentUser\Root` (или запустить `Install.ps1 -Uninstall`).
5. Удалить `%LOCALAPPDATA%\RaceNetLocal` и ярлыки.

Альтернатива для exe: Steam → свойства игры → **Проверить целостность файлов**.

## Требования к сборке из исходников

- Windows 10/11 x64.
- [.NET SDK 10](https://dotnet.microsoft.com/download) (`dotnet --version` → 10.x).
- Интернет для NuGet и загрузки upstream.
- Git **не нужен**: патчи применяет `tools/apply-patches.ps1`.

```powershell
.\tools\build-release.ps1 -Version 0.1.0
```

Скрипт:

1. Скачивает upstream по коммиту `9d2c7d6bcc716e10e3327e26c1dbe3a1434d37d2`.
2. Применяет `patches/RaceNetResponder.cs.patch` и
   `patches/EgoNetChallengePayloads.cs.patch`, проверяет SHA256 (защита от
   изменения upstream).
3. Кладёт релизный `appsettings.json` (SQLite, localhost).
4. `dotnet publish -c Release -r win-x64 --self-contained true`.
5. Собирает `dist/RaceNetLocal-DiRT-Showdown-v<версия>.zip` и `.sha256`.

Офлайн-сборка: `-UpstreamZip path\to\egonet-revival.zip`.
Свой NuGet-источник: `-NuGetConfig path\to\NuGet.config`.

## Если upstream обновился

Патчи привязаны к коммиту. При обновлении:

1. Возьмите новый коммит, примените патчи вручную (`git apply` или скопируйте
   изменённые файлы).
2. Сгенерируйте новые diff'ы и обновите SHA256 в `tools/apply-patches.ps1`.
3. Обновите `-UpstreamCommit` по умолчанию в `tools/build-release.ps1`.
