# Как это работает (технически)

## Почему игра «умерла»

DiRT Showdown (2012) ходит в RaceNet/EgoNet по HTTPS на
`prod.egonet.codemasters.com`. После закрытия сервиса (ноябрь 2025) DNS ещё
резолвится, но соединение не устанавливается — игра зависает на
«SIGNING INTO RACENET», а раздел Challenges пустой.

Дополнительно клиент **пиннит** корневой сертификат: копия
`CN=Codemasters Online Root CA` (DER, ровно **1003 байта**) вшита прямо в
`showdown.exe` и `showdown_avx.exe`. Подменить DNS недостаточно — TLS-соединение
не пройдёт проверку.

## Два шага

### 1. DNS

Блок в `hosts` направляет имена RaceNet на `127.0.0.1` (или на IP хоста):

```
127.0.0.1 prod.egonet.codemasters.com
```

Остальные имена (`racenet.com`, `api.racenet.com`, …) добавлены на случай
резервных запросов клиента.

### 2. Подмена пиннинга

Установщик генерирует локальный корневой CA и заменяет **только байты
сертификата** внутри exe:

- старый DER-сертификат Codemasters (1003 байта) заменяется на локальный CA;
- длина и структура DER подобраны так, чтобы файл остался валидным (1003 байта);
- Subject намеренно повторяет `CN=Codemasters Online Root CA, OU=Codemasters
  Online, O=Codemasters Software Ltd, S=Warwickshire, C=UK`;
- код игры не меняется, PE-заголовки и подпись не затрагиваются;
- рядом создаётся `showdown.exe.racenet-original.bak`.

Сервер отдаёт TLS-сертификат `CN=prod.egonet.codemasters.com`, подписанный этим
CA. Клиент проверяет его по вшитому корню — проверка проходит.

Сертификат также ставится в `Cert:\CurrentUser\Root`, чтобы системные
инструменты (curl, браузер) могли проверить health-эндпоинт. Игре это не нужно.

## Сервер

`RaceNetShowdown.Server` — ASP.NET Core (Kestrel), слушает:

- `http://127.0.0.1:80` — health, выдача CA (`/racenet-root-ca.cer`), CRL;
- `https://127.0.0.1:443` — основной RaceNet-трафик.

Протокол EgoNet — бинарный «словарь» в теле POST с заголовком
`X-EgoNet-Function`. Сервер разбирает запрос, определяет игру и функцию и
возвращает совместимый бинарный ответ. Ключевые функции:

```
AsynchronousChallengeService.GetFriendsOverview
AsynchronousChallengeService.GetFriendChallenges
AsynchronousChallengeService.IssueChallenge
AsynchronousChallengeService.AcceptChallenge
AsynchronousChallengeService.SubmitChallengeResult
AsynchronousChallengeService.UploadGhost
AsynchronousChallengeService.DownloadGhost
AsynchronousChallengeService.SubmitPersonalRecord
```

Данные (профили, друзья, челленджи, результаты, призраки) лежат в SQLite:
`server\data\egonet-revival.db`.

## Наши изменения относительно upstream

### `EgoNetChallengePayloads.cs`

- `MaxFriendsReturnedToShowdown` 64 → **256**: у активных игроков список друзей
  длиннее 64, и друзья с индексом > 64 пропадали из UI.
- Убран фиксированный лимит **20** активных челленджей: он скрывал челленджи
  друзей, стоящих ниже по алфавиту.
- `CreateSyntheticFriend`: если у друга нет записанного челленджа, сервер
  подставляет челлендж из каталога захваченных событий (id 238000+, призрак
  154000+). Так можно смотреть/принимать/отправлять челленджи без второго
  игрока.

### `RaceNetResponder.cs`

- `BuildLoginResponse` возвращает `PrincipalId si64` в теле `vdic` — без него
  клиент вечно висит на «SIGNING INTO RACENET».
- Все ответы Challenge: `Content-Type: text/html` и
  `Cache-Control: private, s-maxage=0` — байт-в-байт как у настоящего IIS.
- `IssueChallenge` возвращает `GhostSlotID si64`.
- Fallback-игра по умолчанию — `dirt-showdown`.

## Каталог челленджей

В `EgoNetChallengePayloads` зашит массив из 13 захваченных событий (id 1005…1415)
с результатами, машинами и сложностью. Из них строятся «синтетические» челленджи
для друзей. Цель (ResultToBeat) можно побить — тогда засчитывается победа.

## Безопасность

- Приватный ключ CA и серверный PFX лежат только на вашем ПК
  (`server\certs`), в репозиторий не попадают.
- Корневой сертификат доверенный **только в вашем профиле** (`CurrentUser`), а
  не для всех пользователей.
- Сервер по умолчанию слушает только localhost; наружу открывается лишь в режиме
  «Разрешить друзей» + правило firewall.
- Никакой телеметрии: сервер не отправляет данные в интернет.
- Риск: локальный CA доверенный, поэтому его приватный ключ не должен утечь.
  Если не пользуетесь модом — удалите его (`Install.ps1 -Uninstall`).

## Что мод не делает

- Не патчит память игры, не трогает сохранения и статистику Steam.
- Не обходит проверки достижений: они выдаются игрой за игровые действия.
- Не восстанавливает игровые лобби и матчмейкинг.
- Не подменяет файлы игры целиком — только 1003 байта сертификата.
