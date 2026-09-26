# Darkndark Addons

Two World of Warcraft: **Midnight** (12.x) addons for every class and spec.

| Addon | What it does | Command |
|---|---|---|
| **[Darkndark](Darkndark/)** | Rotation helper built within Midnight's addon rules. It shows the next ability to press and the ones after it, with your keybinds. It also has major cooldown and defensive bars and an interrupt helper, and every panel can be moved and resized. | `/dnd` |
| **[Darkndark Talents](DarkndarkTalents/)** | Talent builds that top players use for Mythic+, raid, Solo Shuffle/1v1, 2v2, 3v3, Blitz and RBG. It includes a build chooser for when you enter content, a Top Players browser, chat sharing, bar and keybind layout, and a gear and stat check. | `/dndt` |

Both addons only show information and change things when you click. They never press abilities for you.

- Landing page: [`docs/index.html`](docs/index.html)
- CurseForge descriptions: [`docs/curseforge/`](docs/curseforge/)
- Roadmap and design notes: [`PLAN.md`](PLAN.md)
- Changelogs: [`CHANGELOG.md`](CHANGELOG.md) (Darkndark) and [`CHANGELOG-talents.md`](CHANGELOG-talents.md) (Darkndark Talents)

## Repository layout

```
Darkndark/            rotation helper addon
DarkndarkTalents/     talent builds addon (Data/Builds.lua is generated)
tools/
  update-builds.mjs   regenerates talent data from murlok.io + raider.io
  package.ps1         builds CurseForge-ready zips into .release/
tests/                mock WoW API test harness (fengari)
docs/                 landing page and CurseForge texts
.github/workflows/    CI tests and CurseForge release
install.ps1           links the addons into your WoW AddOns folder
```

## Development

Requirements: Node.js 18 or later. PowerShell is only needed for the Windows helper scripts.

```powershell
# Link both addons into WoW (junctions), then /reload in game after edits
.\install.ps1

# Run the test suites (both addons)
cd tests; npm install; npm test

# Refresh talent build data (cached; the first full run takes about an hour)
node tools/update-builds.mjs                      # all specs
node tools/update-builds.mjs paladin/retribution  # one spec

# Build zips for manual CurseForge upload
.\tools\package.ps1 -Version 0.2.0
```

## Releasing

Push a version tag (for example `git tag v0.2.0 && git push --tags`). The release workflow runs the tests and packages both addons with the BigWigs packager. It uploads them to CurseForge once the project IDs are in the TOC files and a `CF_API_KEY` repository secret exists.

## Data sources

Talent builds, top player rankings and stat priorities come from [murlok.io](https://murlok.io) and the [raider.io API](https://raider.io/api). The addons are not affiliated with Blizzard Entertainment.
