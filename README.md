# RaceNet Local — DiRT Showdown

![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6?style=flat-square)
![Game](https://img.shields.io/badge/game-DiRT%20Showdown%20201700-orange?style=flat-square)
![License](https://img.shields.io/badge/license-MIT%20for%20our%20code-blue?style=flat-square)
![Achievements](https://img.shields.io/badge/No%20Turning%20Back-verified-success?style=flat-square)

> **Русская версия:** [README.ru.md](README.ru.md)

Local RaceNet server for **DiRT Showdown** (Steam, appid 201700). It brings back
challenges, friends and the online achievements that disappeared when Codemasters
shut down EgoNet/RaceNet.

The server runs **on your PC**: the game talks to `127.0.0.1`, nothing is sent to
Codemasters servers (in friend mode, data stays between you and the host). No second
PC or second account is needed — only at least one friend on your Steam friend list
(see [achievements](docs/ACHIEVEMENTS.md)).

> A fork/overlay on top of [EgoNet Revival](https://github.com/Berleis/egonet-revival)
> (Berleis). This project adds a local mode, a one-click installer, synthetic
> challenges for playing without a second player, and login/friend-list fixes.

---

## Quick start

1. Download the latest `RaceNetLocal-DiRT-Showdown-v*.zip` from
   [Releases](../../releases) and extract it **completely**.
2. Close DiRT Showdown. Run `Install.cmd`, accept the UAC prompt.
3. Click **Install** and wait for “Done”.
4. Launch the game with the new **“DiRT Showdown — RaceNet”** desktop shortcut.
5. In game: RaceNet → **Challenges**. Then follow the [achievement guide](docs/ACHIEVEMENTS.md).

The installer detects the game folder, backs up both executables, replaces the
embedded Codemasters root certificate (1003 bytes, data only), adds `hosts`
entries, installs the root certificate for the current user and creates shortcuts.

**Uninstall:** run `Install.cmd` → **Remove mod**. Executables are restored from
`.racenet-original.bak`, `hosts` and the certificate are cleaned up.

Details (GUI, CLI, manual setup, file locations): [docs/INSTALL.md](docs/INSTALL.md).

---

## What's in the archive

```
RaceNetLocal-DiRT-Showdown-v0.1.0/
├─ Install.cmd          double-click to start the installer
├─ Install.ps1          installer: GUI + CLI
├─ server/              self-contained server (.NET 10, SQLite)
├─ docs/                install, achievements, friends, troubleshooting, internals
├─ tools/patch-game.ps1 manual executable patcher
├─ README.md            this file (English)
├─ README.ru.md         Russian version
├─ LICENSE / NOTICE.md  our GNU GPL 3.0 license and upstream status
└─ VERSION.txt
```

---

## Status

| Feature | Status |
|---|---|
| RaceNet login without hanging on “SIGNING INTO RACENET” | ✅ |
| Friend list (up to 256), synthetic challenges for friends without recorded ones | ✅ |
| View / accept / send challenges, ghost upload/download | ✅ |
| No 20-challenge cap | ✅ |
| **No Turning Back** achievement | ✅ verified |
| **Beat it!**, **Running the Show** | ⚠️ expected, see guide |
| Fanbase achievements (10/20/30 online) | ❓ unverified |
| Friend-to-friend play over Radmin VPN / LAN | ✅ [guide](docs/FRIENDS.md) |
| Real online multiplayer lobbies | ❌ not part of this mod |

---

## Requirements

- Windows 10/11 x64.
- Steam version of DiRT Showdown (appid 201700).
- Administrator rights **for installation only** (`hosts` edit).
- Ports **80** and **443** free while playing.
- Steam online.

The server is self-contained: no .NET runtime installation required.

---

## Achievements

After installation, achievements tied to RaceNet challenges become available again.
A second player is not required, but **at least one Steam friend is**: the game takes
the friend list from Steam, and the server supplies challenges for those friends.

- [Achievement guide](docs/ACHIEVEMENTS.md) — what is verified and what is not.
- Important: this is not an unlocker. Achievements are granted by the game through
  Steam, just like before.

---

## Friends (Radmin VPN / LAN)

The host enables “Allow friend connections” in the installer (the server listens on
all interfaces and adds a firewall rule). A friend installs the same package in
“Connect to a friend's server” mode and enters the host IP. The certificate is
downloaded from the host automatically.

Details: [docs/FRIENDS.md](docs/FRIENDS.md) (Russian).

---

## What changes on your PC

| Item | Location | Reversible |
|---|---|---|
| 1003-byte embedded certificate | `showdown.exe`, `showdown_avx.exe` | yes, `.racenet-original.bak` |
| RaceNet hostnames → `127.0.0.1` | `%SystemRoot%\System32\drivers\etc\hosts` | yes |
| Root certificate | `Cert:\CurrentUser\Root` | yes |
| Server, database, logs | `%LOCALAPPDATA%\RaceNetLocal` | yes |
| Shortcuts | Desktop / Start Menu | yes |

No game code is modified and no game files are distributed.

Details: [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) (Russian).

---

## Verify it works

1. **Server:** open <http://127.0.0.1/health> — JSON with `"ok":true`.
2. **Hosts:** the block `# --- RaceNetLocal begin ---` with
   `127.0.0.1 prod.egonet.codemasters.com` exists.
3. **Executables:** `showdown.exe.racenet-original.bak` is present next to the game.
4. **Game:** no endless “SIGNING INTO RACENET”, Challenges list is not empty.

---

## Troubleshooting

- Stuck on “SIGNING INTO RACENET” → server not running or executable not patched.
- Empty Challenges → no Steam friends, or the server was not restarted after patching.
- Ports 80/443 busy (IIS, VMware, Skype) → free them.
- Steam “Verify integrity” restored the exe → run the installer again.

Full list: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) (Russian).
Still stuck — [open an issue](../../issues/new?template=bug_report.yml).

---

## Build from source

```powershell
# .NET SDK 10 + internet
.\tools\build-release.ps1 -Version 0.1.0
# output: dist\RaceNetLocal-DiRT-Showdown-v0.1.0.zip
```

The script downloads upstream at a pinned commit, applies `patches/*.patch`
(SHA256 checked), publishes a self-contained server and packs the zip.
Git is not required.

Build requirements and repository layout: [docs/INSTALL.md](docs/INSTALL.md).

---

## Repository layout

```
dirt-showdown-racenet-local/
├─ installer/        Install.cmd + Install.ps1 (GUI and CLI)
├─ patches/          two unified diffs against upstream
├─ tools/            release build, patch applier, manual executable patcher
├─ docs/             documentation
├─ release-notes/    release texts
└─ .github/          release workflow and issue template
```

The server is not committed to the repository — it is built and attached to a release.

---

## Contributing

Bugs and suggestions: open an issue using the template. Rules, build notes and
what not to attach: [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License and legal

- Our code (installer, scripts, docs) is **GNU GPL 3.0** — see [LICENSE](LICENSE).
- Patches target [EgoNet Revival](https://github.com/Berleis/egonet-revival),
  which has **no license file** at the pinned commit. We claim no rights over
  upstream code. See [NOTICE.md](NOTICE.md).
- Unofficial project, not affiliated with Codemasters, EA or Steam. DiRT is a
  Codemasters trademark. No game files are distributed.
- Do not use this for competitive achievement leaderboards.

Details: [docs/LEGAL.md](docs/LEGAL.md) (Russian).

---

## Credits

- [Berleis/egonet-revival](https://github.com/Berleis/egonet-revival) — protocol,
  server, installer and the huge reverse-engineering work behind RaceNet.
- The DiRT Showdown community — captured challenges and testing.
