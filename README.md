# Darkndark

**A rotation and combo assistant for every class and spec, built for Midnight's addon rules.**

Midnight's *Secret Values* ended the old rotation helpers. Darkndark works inside the new rules. It starts from Blizzard's Assisted Combat suggestion and adds its own layer on top, using only the combat information addons can still read: whether an ability is off cooldown, usable, in range, or procced.

## Features
- **Main recommendation.** A large icon for the next ability plus up to 4 predicted abilities after it. Procs are moved to the front.
- **Works for every class and spec** out of the box. Spec profiles can add extra priority rules.
- **Keybinds on icons.** Detects keys from Blizzard bars, Bartender4, ElvUI, Dominos and macros.
- **Cooldown bar.** Finds each spec's major cooldowns on its own.
- **Hold cooldowns mode.** Major cooldowns stay off the main icon and glow on their bar when it is time, so you choose when to press them.
- **Defensives bar.** Shows your personal defensives and whether each one is ready.
- **Interrupt helper.** Appears when your target casts and glows when your interrupt is ready, with an optional sound.
- **Fully movable and resizable.** Type `/dnd unlock`. Drag a panel to move it; use the mouse wheel or the corner grip to resize it.
- **Masque support** and a settings panel (Esc > Options > AddOns > Darkndark).
- English and Turkish.

## Commands
| Command | |
|---|---|
| `/dnd unlock` / `/dnd lock` | Move and resize panels |
| `/dnd config` | Open settings |
| `/dnd reset` | Reset positions and sizes |
| `/dnd scale 1.2` | Scale the main panel |
| `/dnd toggle` | Turn the addon on or off |
| `/dnd probe` | Show a report of what combat data is readable right now (for bug reports) |
| `/dnd debug` | Show where each recommendation came from |

## Fair play
Darkndark never presses anything for you. It only shows information.

## Writing a spec profile
See `Profiles/Registry.lua`. Profiles are plain priority lists:
```lua
Darkndark:RegisterProfile(260, {
    name = "Outlaw",
    priority = {
        { spell = 185763, when = function(s) return s.proc(185763) end },
        { spell = 2098,   when = function(s) return s.powerAtLeast(Enum.PowerType.ComboPoints, 5) end },
    },
})
```
