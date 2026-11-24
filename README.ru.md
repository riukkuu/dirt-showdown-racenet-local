# RaceNet Local — DiRT Showdown

![Платформа](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6?style=flat-square)
![Игра](https://img.shields.io/badge/game-DiRT%20Showdown%20201700-orange?style=flat-square)
![Лицензия](https://img.shields.io/badge/license-MIT%20for%20our%20code-blue?style=flat-square)
![Ачивки](https://img.shields.io/badge/No%20Turning%20Back-verified-success?style=flat-square)

> **English version:** [README.md](README.md)

Локальный сервер RaceNet для **DiRT Showdown** (Steam, appid 201700): возвращает
челленджи, список друзей и онлайн-достижения, которые отключились после закрытия
серверов Codemasters EgoNet/RaceNet.

Сервер работает **на вашем ПК**: игра ходит на `127.0.0.1`, данные не уходят на серверы
Codemasters (в режиме друга — только между вами и хостом). Второй компьютер и
второй аккаунт не нужны — достаточно, чтобы в Steam был хотя бы один друг
(см. [ачивки](docs/ACHIEVEMENTS.md)).

> Это форк-надстройка над [EgoNet Revival](https://github.com/Berleis/egonet-revival)
> (Berleis). Здесь добавлены локальный режим, установщик «в один клик», синтетические
> челленджи для игры без второго игрока и исправления логина/списка друзей.

---

## Быстрый старт

1. Скачайте последний `RaceNetLocal-DiRT-Showdown-v*.zip` со страницы
   [Releases](../../releases) и распакуйте **целиком** в любую папку.
2. Закройте DiRT Showdown. Запустите `Install.cmd` → «Да» в UAC.
3. Нажмите **Установить**, дождитесь «Готово».
4. Запускайте игру ярлыком **«DiRT Showdown — RaceNet»** на рабочем столе.
5. В игре: RaceNet → **Challenges**. Дальше — по [гайду по достижениям](docs/ACHIEVEMENTS.md).

Установщик сам найдёт папку игры (Steam-библиотеки), создаст резервные копии,
пропатчит сертификат в `showdown.exe` / `showdown_avx.exe`, добавит запись в
`hosts`, поставит корневой сертификат в профиль пользователя и создаст ярлыки.

**Удаление:** тот же `Install.cmd` → **Удалить мод**. Файлы игры восстановятся из
`.racenet-original.bak`, `hosts` и сертификат очистятся.

Подробно (GUI, CLI, ручная установка, что где лежит):
[docs/INSTALL.md](docs/INSTALL.md).

---

## Что внутри архива

```
RaceNetLocal-DiRT-Showdown-v0.1.0/
├─ Install.cmd          запуск установщика (двойной клик)
├─ Install.ps1          установщик: GUI и CLI
├─ server/              self-contained сервер (.NET 10, SQLite)
├─ docs/                установка, ачивки, друзья, проблемы, техника, право
├─ tools/patch-game.ps1 ручной патчер exe (если не хотите установщик)
├─ README.md            английская версия (основная на GitHub)
├─ README.ru.md         этот файл
├─ LICENSE / NOTICE.md  лицензия нашего кода и статус upstream
└─ VERSION.txt
```

---

## Что работает

| Возможность | Статус |
|---|---|
| Вход в RaceNet, без зависания на «SIGNING INTO RACENET» | ✅ |
| Список друзей (до 256), синтетические челленджи для друзей без своих записей | ✅ |
| Просмотр / принятие / отправка челленджей, призраки (ghosts) | ✅ |
| Челленджи без лимита в 20 штук | ✅ |
| Достижение **No Turning Back** (отправить челлендж) | ✅ проверено |
| **Beat it!** (пройти челлендж друга) | ⚠️ ожидается, см. гайд |
| **Running the Show** (доминировать друга) | ⚠️ требует серии побед |
| Fanbase-достижения (10/20/30 онлайн) | ❓ зависит от начисления XP |
| Совместная игра с другом через Radmin VPN / LAN | ✅ [инструкция](docs/FRIENDS.md) |
| Настоящий онлайн-мультиплеер (лобби) | ❌ не входит в мод |

---

## Требования

- Windows 10/11 (x64).
- Steam-версия DiRT Showdown (appid 201700).
- Права администратора — **только на время установки** (правка `hosts`).
- Свободные порты **80** и **443** на время игры.
- Интернет для Steam (сама игра и достижения — через Steam).

Сервер не требует установленного .NET: в релизе self-contained сборка.

---

## Достижения

Коротко: после установки мода становятся доступны достижения, завязанные на
RaceNet-челленджи. Второй игрок не нужен, но **нужен хотя бы один друг в Steam**:
игра берёт список друзей из Steam, а сервер подставляет для них челленджи из
каталога.

- [Гайд по достижениям](docs/ACHIEVEMENTS.md) — что проверено, а что нет.
- Важно: это не анлокер. Достижения выдаёт сама игра через Steam, как и раньше.

---

## Друзья (Radmin VPN / LAN)

Хост включает «Разрешить подключение друзей» в установщике (сервер слушает
все интерфейсы + правило firewall). Друг ставит тот же пакет в режиме
**«Подключиться к серверу друга»** и указывает IP хоста. Сертификат друг
скачивает с сервера хоста автоматически.

Подробно: [docs/FRIENDS.md](docs/FRIENDS.md).

---

## Что именно меняется на ПК

| Что | Где | Обратимо |
|---|---|---|
| 1003 байта встроенного сертификата Codemasters | `showdown.exe`, `showdown_avx.exe` | да, `.racenet-original.bak` |
| Перенаправление имён RaceNet на `127.0.0.1` (или IP друга) | `C:\Windows\System32\drivers\etc\hosts`, блок `# --- RaceNetLocal ---` | да |
| Корневой сертификат | `Cert:\CurrentUser\Root` | да, удаляется установщиком |
| Сервер, данные, логи | `%LOCALAPPDATA%\RaceNetLocal` | да, удаляется вместе с модом |
| Ярлыки | рабочий стол, меню «Пуск» | да |

Код игры не меняется: подменяется только встроенный корневой сертификат, чтобы
игра доверяла локальному серверу. Никакие файлы игры не скачиваются и не
распространяются.

Подробности: [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

---

## Как проверить, что всё работает

1. **Сервер:** откройте <http://127.0.0.1/health> — должен вернуться JSON с
   `"ok":true`. Если браузер не открывает — сервер не запущен или заняты порты.
2. **Hosts:** в `C:\Windows\System32\drivers\etc\hosts` есть блок
   `# --- RaceNetLocal begin ---` со строкой `127.0.0.1 prod.egonet.codemasters.com`.
3. **Exe:** рядом с `showdown.exe` лежит `showdown.exe.racenet-original.bak`.
4. **Игра:** не висит на «SIGNING INTO RACENET», в Challenges есть друзья.

---

## Если что-то не работает

- Игра висит на «SIGNING INTO RACENET» → не запущен сервер или не пропатчен exe.
- Пустые Challenges → нет друзей в Steam или сервер не перезапущен после патча.
- Порты заняты (IIS, VMware, Skype) → освободите 80/443.
- Steam «Проверить целостность» вернул exe → запустите установщик заново.

Все случаи: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).
Не помогло — [создайте issue](../../issues/new?template=bug_report.yml).

---

## Сборка из исходников

```powershell
# .NET SDK 10 + интернет
.\tools\build-release.ps1 -Version 0.1.0
# результат: dist\RaceNetLocal-DiRT-Showdown-v0.1.0.zip
```

Скрипт скачивает upstream по закреплённому коммиту, применяет патчи из `patches/`
(с проверкой SHA256), публикует self-contained сервер и собирает zip.
Git не требуется.

Требования к сборке и структура репозитория — в [docs/INSTALL.md](docs/INSTALL.md).

---

## Структура репозитория

```
dirt-showdown-racenet-local/
├─ installer/        Install.cmd + Install.ps1 (GUI и CLI)
├─ patches/          два unified-diff патча к upstream
├─ tools/            сборка релиза, applier патчей, ручной патчер exe
├─ docs/             документация
├─ release-notes/    тексты релизов
└─ .github/          workflow сборки релиза и шаблон issue
```

Сервер в репозиторий не коммитится — он собирается и попадает в release-ассет.

---

## Участие

Баги и предложения — через issue по шаблону. Как помочь с кодом и что нельзя
прикладывать: [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Лицензия и правовой статус

- Наш код (установщик, скрипты, документация) — **MIT**, см. [LICENSE](LICENSE).
- Патчи применяются к [EgoNet Revival](https://github.com/Berleis/egonet-revival);
  upstream на закреплённом коммите **не содержит файла лицензии**. Мы не заявляем
  права на upstream-код и не перепродаём его. Если вы правообладатель — см.
  [NOTICE.md](NOTICE.md).
- Проект неофициальный, не связан с Codemasters, EA, Steam. DiRT — товарный знак
  Codemasters. Файлы игры не распространяются.
- Не используйте для соревновательных таблиц достижений (Steam Hunters и т.п.).

Подробно: [docs/LEGAL.md](docs/LEGAL.md).

---

## Благодарности

- [Berleis/egonet-revival](https://github.com/Berleis/egonet-revival) — протокол,
  сервер, установщик и огромная работа по реверсу RaceNet.
- Сообществу DiRT Showdown — за захваченные челленджи и тесты.
