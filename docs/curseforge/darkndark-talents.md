# Darkndark Talents

**The talent builds top players actually use, for your current spec, in whatever content you're playing. One click to switch.**

## Features
- **Builds for every content type:** Mythic+, Raid, Solo Shuffle (and 1v1 duels), Arena 2v2 and 3v3, Blitz and Rated BGs.
- **Real data:** built from the top 50 players of each spec per bracket (murlok.io), using the exact talent strings they have equipped (raider.io). When the top players split between hero talent trees, you also get an alternative build for the second tree.
- **One-click apply:** the build is written into a "DND M+" (or "DND 3v3", and so on) loadout and switched on. Applying a newer version of a build replaces the old loadout.
- **Top Players browser:** for your current character's spec, see the top 20 players in each content type ranked by rating or M+ score. Pick anyone and use their exact talents, or share them.
- **You choose:** when you enter a dungeon, raid, arena or battleground, a chooser asks which talents you want (recommended, the other hero tree, your saved build, a top player's build, or no change). Nothing changes until you pick.
- **Share builds:** put a clickable talent build link in chat for your group or guild.
- **Your own builds:** save your current talents as your build for any content type.
- **Match score:** shows how close your current talents are to each recommended build.
- **Bar and keybind layout:** after a build change, the build's spells go on your visible bars with keys bound (rotation on 1-6 R F T, cooldowns on Shift+1-6, defensives on Ctrl+1-5, interrupt on G, utility on Z X C V). Works with Blizzard bars, ElvUI, Bartender4 and Dominos. Macros and items are never touched, and "Undo bars" steps back through your last 5 layouts.
- **Gear & stats check:** compares your secondary stat distribution and item level with top players, and lists missing enchants and empty gem sockets.
- Movable and resizable window (drag it; use Ctrl + mouse wheel or the corner grip). A "Darkndark" button is added to the talent window.

## Commands
| Command | |
|---|---|
| `/dndt` | Open or close the window |
| `/dndt gear` | Open the Gear & Stats tab |
| `/dndt check` | Check the current content now |
| `/dndt reset` | Reset the window position |

## Data updates
Build data is refreshed with `node tools/update-builds.mjs` and shipped with each release.
