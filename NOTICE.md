# NOTICE

## Upstream project

This repository is an overlay on top of **EgoNet Revival** by Berleis:

- https://github.com/Berleis/egonet-revival
- Pinned commit: `9d2c7d6bcc716e10e3327e26c1dbe3a1434d37d2`
- License status at that commit: **no license file present** (GitHub reports no license).

We do not claim authorship or ownership of upstream code. This repository stores
only our own changes as unified diffs (`patches/`), plus an installer, build
scripts and documentation. The release archives contain a compiled build of the
patched upstream server; they are assembled from upstream sources by
`tools/build-release.ps1`.

If you are the upstream author or a rights holder and want this distribution
changed or removed, please open an issue in this repository and it will be
handled.

**Recommendation before publishing:** ask the upstream author for permission
(or a license) and consider sending the two patches upstream as a pull request.
That is the cleanest long-term path.

## What is not distributed here

- No DiRT Showdown game files, executables, assets, saves or Steam data.
- No Codemasters/EA code.
- No certificate private keys, no personal IP addresses, no captured payloads
  from other players.

## Trademarks

DiRT, DiRT Showdown, Codemasters and related marks are trademarks of their
respective owners. This project is unofficial and not affiliated with, endorsed
by, or sponsored by Codemasters, EA or Valve/Steam.

## Third-party components

Release builds include the .NET runtime and ASP.NET Core (MIT, © .NET Foundation),
Microsoft.Data.Sqlite / SQLitePCLRaw (Apache-2.0 / MIT) and other NuGet packages
under their respective licenses. See the `*.deps.json` and package metadata in the
release.

## Our license

Original code in this repository (installer, scripts, documentation) is MIT —
see `LICENSE`. Patches are provided as diffs against upstream and inherit
upstream's (unclear) licensing status.
