# Публикация на GitHub — пошагово

Инструкция доводит папку `dirt-showdown-racenet-local` до публичного репозитория
с аккуратной страницей и готовым релизом. Git знать не обязательно: основной путь
— через сайт GitHub.

---

## 0. Что публикуем, а что нет

В репозиторий идут только исходники, установщик, патчи и документация:

```
dirt-showdown-racenet-local/
├─ README.md / README.ru.md      описание проекта (EN — основное, RU — ссылкой из него)
├─ LICENSE / NOTICE.md           MIT на наш код + статус upstream
├─ CHANGELOG.md                  история версий
├─ CONTRIBUTING.md               правила для issue/PR
├─ .gitignore / .gitattributes   чистота и переводы строк
├─ .github/                      workflow релиза + шаблон issue
├─ installer/                    Install.cmd + Install.ps1
├─ patches/                      два патча к upstream
├─ tools/                        сборка, applier патчей, ручной патчер
├─ docs/                         вся документация
└─ release-notes/                тексты релизов
```

**Не коммитим:**

- `dist/`, `.work/` — артефакты сборки (уже в `.gitignore`);
- собранный `server/` — он весит десятки мегабайт и живёт только в release-ассете;
- `*.zip`, `*.pfx`, `*.key`, `certs/`, `data/`, `logs/`, `*.db`;
- файлы игры (`showdown*.exe`) и скриншоты с личными данными.

Сервер в репозитории не нужен ещё и юридически: репозиторий содержит наши
изменения, а бинарник upstream распространяется отдельным ассетом.

---

## 1. Проверка перед публикацией

Откройте папку репозитория и убедитесь, что в ней нет лишнего:

```powershell
cd dirt-showdown-racenet-local

# не должно быть ничего
Get-ChildItem -Recurse -Force -File |
  Where-Object { $_.Name -match '\.(pfx|p12|key|pem|cer|crt|db|zip|7z)$' }

# не должно быть папок сборки
Test-Path .work; Test-Path dist

# не должно быть личных IP / SteamID
Get-ChildItem -Recurse -File |
  Select-String -Pattern '26\.\d+\.\d+\.\d+|7656119\d{10}'
```

Если что-то нашлось — удалите или замените на документационный адрес
(`203.0.113.10` из RFC 5737).

Проверьте, что `README.md` открывается локально и ссылки `docs/...` существуют.

---

## 2. Создайте репозиторий

На GitHub: **New repository**.

| Поле | Значение |
|---|---|
| Owner | вы или организация |
| Repository name | `dirt-showdown-racenet-local` |
| Description | `Unofficial local RaceNet server for DiRT Showdown (Steam): brings back challenges, friends and online achievements after EgoNet shutdown. One-click Windows installer, no second PC needed. No game files included.` |
| Visibility | **Public** |
| Initialize this repository | **ничего не отмечать** (README, .gitignore и license уже есть) |

После создания откройте **About** (шестерёнка справа) и заполните:

- **Description** — как выше (по-английски, так проект найдут);
- **Website** — оставьте пустым;
- **Topics**:

```
dirt-showdown racenet codemasters egonet game-preservation
server-emulator race-net dirt steam achievements windows
```

Темы дают поиск и аккуратные «таблетки» под описанием.

---

## 3. Загрузите файлы

### Вариант А — сайт GitHub (проще всего, git не нужен)

1. На странице пустого репозитория нажмите **uploading an existing file**.
2. Откройте папку `dirt-showdown-racenet-local` в проводнике.
3. Выделите **всё содержимое папки** (Ctrl+A) и перетащите в браузер.
   Важно: перетаскивать нужно содержимое, а не саму папку, иначе появится
   лишний уровень `dirt-showdown-racenet-local/` внутри репозитория.
4. Дождитесь окончания загрузки (файлов ~20, все маленькие).
5. В поле сообщения коммита введите:
   `RaceNet Local 0.1.0: local RaceNet server and installer for DiRT Showdown`
6. Нажмите **Commit changes**.

Что проверить после загрузки:

- [ ] в корне видны `README.md`, `README.ru.md`, `LICENSE`, `installer/`, `docs/`;
- [ ] виден файл `.gitignore`;
- [ ] видна папка `.github/workflows/build-release.yml`
      (если `.github` не загрузилась — создайте файл вручную:
      **Add file → Create new file**, имя
      `.github/workflows/build-release.yml`, вставьте содержимое из локальной
      копии);
- [ ] папки `dist`, `.work`, `server` и архивов нет.

### Вариант Б — GitHub Desktop

1. Установите [GitHub Desktop](https://desktop.github.com/).
2. **File → Add local repository** → выберите папку `dirt-showdown-racenet-local`.
3. Он предложит создать репозиторий — согласитесь, ветка `main`.
4. Проверьте список файлов: ничего из `dist`, `.work` быть не должно.
5. **Commit to main** с тем же сообщением → **Publish repository**,
   снимите галочку «Keep this code private».

### Вариант В — git в терминале

```bash
cd dirt-showdown-racenet-local
git init
git add .
git commit -m "RaceNet Local 0.1.0: local RaceNet server and installer for DiRT Showdown"
git branch -M main
git remote add origin https://github.com/<user>/dirt-showdown-racenet-local.git
git push -u origin main
```

---

## 4. Настройте репозиторий

**Settings → General:**

- **Features:** Issues — включить; Discussions, Projects, Wiki — выключить
  (пока нет модерации, они только создают пустые разделы).
- **Social preview:** загрузите картинку 1280×640 (название проекта, игра,
  подпись «unofficial»). Это то, что видно при репосте ссылки в Discord/Steam.

**Settings → Actions → General:**

- **Actions permissions:** Allow all actions.
- **Workflow permissions:** Read and write permissions
  (workflow публикует релиз по тегу).

**Settings → Branches:** защита не нужна, пока вы единственный мейнтейнер.

---

## 5. Соберите релиз

Есть два пути. Если локальный zip уже проверен — проще загрузить его вручную.

### Путь 1 — вручную (рекомендуется для первого релиза)

1. **Releases → Draft a new release.**
2. **Tag:** `v0.1.0`, **Target:** `main`.
3. **Release title:** `RaceNet Local v0.1.0 — DiRT Showdown`.
4. **Describe this release:** вставьте текст из `release-notes/v0.1.0.md`.
5. Прикрепите в **Attach binaries** два файла:
   - `RaceNetLocal-DiRT-Showdown-v0.1.0.zip`
   - `RaceNetLocal-DiRT-Showdown-v0.1.0.zip.sha256`
6. **Publish release.**

Проверьте: ассеты скачиваются, SHA256 в описании совпадает с файлом
(`Get-FileHash ... -Algorithm SHA256`).

### Путь 2 — через GitHub Actions (по тегу)

Workflow `.github/workflows/build-release.yml` собирает пакет на
`windows-latest`, проверяет SHA256 и сам создаёт релиз.

```bash
git tag v0.1.0
git push origin v0.1.0
```

Без git: **Actions → build-release → Run workflow**, версия `0.1.0`.
Через 5–10 минут появится релиз с ассетами. Этот путь удобен для следующих
версий, но первый релиз лучше проверить глазами.

> CI собирает из upstream по закреплённому коммиту. Если GitHub или NuGet
> недоступны, используйте локальную сборку: `.\tools\build-release.ps1 -Version 0.1.0`.

---

## 6. Оформление страницы

- **Закрепите репозиторий:** профиль → Customize your pins → выберите проект.
- **Скриншоты.** Один скриншот меню Challenges и один — окна установщика сильно
  повышают доверие. Добавьте их в `docs/img/` и вставьте в README:
  `![Challenges](docs/img/challenges.png)`. Личные данные (ник, IP, SteamID)
  замажьте.
- **Первый экран README** уже содержит: название, бейджи, одно предложение о
  проекте, быстрый старт и честную таблицу статусов — этого достаточно, чтобы
  человек понял, что скачивать.
- **Не добавляйте** логотипы Codemasters/EA/Steam — только текстовые упоминания.

---

## 7. Проверка после публикации

Пройдите по странице как обычный игрок:

- [ ] README отображается по-английски, ссылка на русскую версию работает;
- [ ] бейджи и картинки грузятся, ссылки `docs/...` рабочие;
- [ ] ссылка `Releases` в README ведёт на релизы;
- [ ] в релизе ровно два ассета, размер zip ~54 МБ;
- [ ] SHA256 из описания совпадает с `.sha256`;
- [ ] скачанный zip распаковывается, внутри есть `Install.cmd` и `server/`;
- [ ] `Install.cmd` запускается (UAC), установщик находит игру;
- [ ] Issue-шаблон открывается: **Issues → New issue → Bug report**;
- [ ] в репозитории нет сертификатов, баз, логов и личных данных.

---

## 8. Обновление версии

1. Внесите изменения, обновите `CHANGELOG.md`.
2. Создайте `release-notes/v0.2.0.md`.
3. Обновите версию по умолчанию в `tools/build-release.ps1` и поле `version`
   в `installer/Install.ps1` (`install-state.json`).
4. Соберите: `.\tools\build-release.ps1 -Version 0.2.0`.
5. Закоммитьте, создайте тег `v0.2.0`, прикрепите новые ассеты.

---

## 9. Права и правовой статус

- Наш код — MIT. У upstream [EgoNet Revival](https://github.com/Berleis/egonet-revival)
  на закреплённом коммите **нет файла лицензии** — по умолчанию «все права
  защищены».
- Перед публикацией бинарников желательно написать автору upstream и попросить
  разрешение. Шаблон письма:

  > Hi! I maintain a small fork/overlay of egonet-revival that adds a local mode,
  > a one-click installer and two patches (synthetic challenges, login fix).
  > I would like to publish prebuilt releases. Could you clarify the license, or
  > would you prefer that I only distribute patches and have users build locally?
  > Happy to send the patches as a PR.

- До ответа можно опубликовать репозиторий **без** бинарников: патчи,
  установщик и документация. Это заметно снижает риск.
- Если придёт жалоба — уберите бинарники из релизов, оставьте патчи и
  документацию, ответьте вежливо.

---

## 10. Частые проблемы GitHub

| Симптом | Причина / решение |
|---|---|
| Загрузилась вложенная папка `dirt-showdown-racenet-local/` | Перетащили папку вместо содержимого. Перенесите файлы через **Add file → Upload files**, открыв папку внутри. |
| Не видно `.github` или `.gitignore` | Создайте файл вручную через **Add file → Create new file** с нужным путём. |
| Actions не запускается по тегу | Settings → Actions → Allow all actions; проверьте, что тег начинается с `v`. |
| Workflow не может создать релиз | Settings → Actions → Workflow permissions → Read and write. |
| README-ссылки ведут не туда | Ссылки на релизы из корня — `../../releases`; из `docs/` — `../../../releases`. |
| Файл больше 25 МБ не грузится через веб | В репозиторий такие файлы и не нужны. Zip — только в release-ассет (до 2 ГБ). |
| Хочется заменить zip в релизе | Releases → Edit release → удалить ассет → прикрепить новый → Update release. |

---

## 11. Финальный чек-лист

- [ ] README по умолчанию английский, русская версия доступна по ссылке.
- [ ] README честно описывает статус ачивок (что проверено, что нет).
- [ ] Указано «unofficial», нет логотипов правообладателей.
- [ ] В репозитории нет `dist/`, `.work/`, `server/`, архивов, сертификатов.
- [ ] В релизе нет файлов игры и приватных ключей.
- [ ] Есть инструкция по удалению (README + docs/INSTALL.md).
- [ ] Есть SHA256 ассета.
- [ ] Есть контакт для жалоб (issue) и шаблон бага.
- [ ] Установщик проверен на чистой машине или после «Проверить целостность».
