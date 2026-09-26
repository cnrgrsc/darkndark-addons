# Darkndark — Development Plan

A family of World of Warcraft: Midnight (12.x) addons, published on CurseForge:

- **Darkndark:** A rotation and combo assistant for every class and spec, in the spirit of Hekili but built within Midnight's addon rules.
- **Darkndark Talents:** Top-player talent builds per content type, a player-picked build chooser, bar and keybind layout, and gear checks.
- **Darkndark UI** *(planned, third addon):* A full interface package. Scope is still to be defined with the user.

---

## 1. Research summary: what Midnight allows

Midnight 12.0 introduced **Secret Values**. Addons can display combat data but can no longer make decisions based on it, and this is why Hekili was discontinued. We verified the table below against Blizzard's API documentation (wow-ui-source, `live` branch):

| Data | API | In combat | How we use it |
|---|---|---|---|
| Blizzard's suggestion | `C_AssistedCombat.GetNextCastSpell()` | **Readable** | Base recommendation (every spec) |
| Rotation spell list | `C_AssistedCombat.GetRotationSpells()` | **Readable** | Queue prediction, fallback engine |
| Is a spell on cooldown? | `C_Spell.GetSpellCooldown().isActive / isOnGCD` | **NeverSecret** ✅ | "Is it ready" checks |
| Cooldown numbers | `...startTime / duration` | Secret | Display only (swipe) |
| Cooldown visuals | `C_Spell.GetSpellCooldownDuration()` → `Cooldown:SetCooldownFromDurationObject()` | Displayable | Icon swipe |
| Usable? | `C_Spell.IsSpellUsable()` | **Readable** | Resource and condition checks |
| Range | `C_Spell.IsSpellInRange()` | **Readable** | Red tint |
| Procs | `C_SpellActivationOverlay.IsSpellOverlayed()` + `SPELL_ACTIVATION_OVERLAY_GLOW_*` | **Readable** | Proc priority |
| Charges | `C_Spell.GetSpellCharges().currentCharges` | Secret (`maxCharges` readable) | Profile rules when available |
| Resources | `UnitPower` | Secret when restricted; Blizzard says class resources stay readable | Secret-safe reads |
| Auras | `C_UnitAuras.GetPlayerAuraBySpellID` | Whitelisted auras only | Secret-safe reads |
| Is the target casting? | `UNIT_SPELLCAST_*` events on target | Events fire (payload may be secret) | Interrupt helper |
| Combat log | `COMBAT_LOG_EVENT_UNFILTERED` | **Removed** | Not used |
| Restriction state | `C_RestrictedActions.IsAddOnRestrictionActive()` | Readable | Diagnostics |

**Conclusion:** We can't see how much time is left on a cooldown, but we can answer "can this be pressed right now?" (off cooldown, usable, in range, procced). That is enough to build a real priority engine on top of Blizzard's suggestion.

---

## 2. Darkndark architecture

```
Darkndark/
├─ Darkndark.toc
├─ Locales.lua            English (default) + Turkish
├─ Core.lua               namespace, saved settings and defaults, event bus, slash commands
├─ Util.lua               secret-safe helpers (reads guarded by issecretvalue)
├─ Spells.lua             spell state: ready / usable / range / proc / charges, spec info
├─ Keybinds.lua           spell → key (Blizzard, Bartender4, ElvUI, Dominos, macros)
├─ Engine.lua             recommendation engine (profile → Blizzard → fallback) + queue
├─ Cooldowns.lua          finds major cooldowns and defensives on its own
├─ Interrupt.lua          class interrupt detection + target cast tracking
├─ Profiles/Registry.lua  spec profile API (Darkndark:RegisterProfile)
├─ UI/Icon.lua            icon widget (swipe, glow, keybind, tint)
├─ UI/Skin.lua            optional Masque support
├─ UI/Display.lua         main panel, cooldown bar, defensives bar, interrupt icon
├─ UI/Options.lua         Blizzard Settings panel
└─ Diagnostics.lua        /dnd probe: reports what is secret in game
```

### Recommendation layers
1. **Profile** (per spec, optional): A rule list. The first spell whose condition passes and that can be pressed now wins.
2. **Blizzard:** `GetNextCastSpell()`, which works for every spec.
3. **Fallback:** The first pressable spell from the rotation list, used when Assisted Combat is unavailable (for example at low level).
4. **Queue:** The next 1–4 pressable spells, with procs first. With "Hold cooldowns" on, major cooldowns glow on their own bar instead of taking the main icon.

### Moving and resizing (every panel)
- `/dnd unlock` shows every panel with a green frame.
- Drag to move. Mouse wheel resizes by ±5%, and the bottom-right grip resizes freely. Right-click opens the settings.
- `/dnd lock` makes the panels click-through again.

---

## 3. Darkndark Talents

### Data pipeline (`tools/update-builds.mjs`)
- **murlok.io:** For every spec and bracket: the top 50 players (hero tree, item level), talent popularity, stat distribution and priority, enchants and gems.
- **raider.io API:** Those players' real talent import strings (`loadout_text`).
- **Selection:** For each hero tree, we pick the **real** player build that best matches murlok's bracket-specific talent popularity, so the result is always a valid build.
- Addons can't reach the internet, so the data ships inside every release as `Data/Builds.lua`. To refresh it, run `node tools/update-builds.mjs` (results are cached, so reruns are fast).
- When the match score is below 60%, the build is flagged "low confidence": those players were probably crawled while using a build for different content.

### Modules (`DarkndarkTalents/`)
- `Loadout.lua`: An exact port of Blizzard's import algorithm. It creates or updates "DND ..." loadouts, switches with `LoadConfig`, and computes how closely your talents match a build.
- `Context.lua`: Detects arena (Shuffle, 2v2, 3v3), battlegrounds (Blitz, RBG), raids and dungeons, and offers the matching build. It stays quiet while a keystone is running.
- `Gear.lua`: Compares your stat rating distribution with top players and flags item level gaps, missing enchants and empty sockets.
- `ActionBars.lua`: Full bar and keybind layout. It scans the visible buttons (Blizzard, ElvUI, Bartender4, Dominos), groups spells (rotation, cooldowns, defensives, interrupt, utility) and binds them to template keys. Macros and items are never touched, and a 5-step undo is kept.
- `UI/Window.lua`: Talents, Top Players and Gear tabs, movable and resizable, plus a "Darkndark" button on the talent window. The Top Players tab lists the top 20 players of your current spec for each content type, ranked by rating or score, and lets you use or share any one player's exact talents.
- `UI/Prompt.lua`: When you enter content, a chooser asks which talents you want: recommended, the other hero tree, your saved build, a top player's build, or keep your current talents. Nothing changes until you choose.
- `Share.lua`: Shares any build as a clickable talent build link in chat (the same link Blizzard's talent window creates).

---

## 4. Roadmap

### Done
- [x] Darkndark core (v0.1): engine, keybinds, panels, settings, probe, profile API
- [x] Darkndark v0.2: defensives bar, hold cooldowns, sounds, Masque
- [x] Darkndark Talents v0.1: builds for 7 content types, one-click apply, content prompts, gear check, bar layout
- [x] Mock test harness (`tests/`, `npm test`): 34 scenarios
- [x] Packaging: `tools/package.ps1` (manual zips) + GitHub Actions workflow (automatic)

### Next
- [ ] **Darkndark UI (third addon):** define scope with the user (unit frames, action bars, nameplates, layout profiles?), then plan and build it
- [ ] Per-dungeon and per-raid-boss builds (raider.io runs by dungeon, Warcraft Logs by boss)
- [ ] In-game testing of both addons (`/console scriptErrors 1`, `/dnd probe` in open world, on a dummy and in a dungeon)
- [ ] Spec profiles for Darkndark, based on probe results (Retribution Paladin first, then all 39 specs)
- [ ] Keybind template editor in the Talents window
- [ ] Druid and Rogue form/stealth bars in the bar layout
- [ ] PvP talent recommendations (the data is on murlok)
- [ ] Raid builds from the Warcraft Logs API (needs a free client key)
- [ ] Weekly automatic data refresh with GitHub Actions
- [ ] Rule editor that needs no code, and profile import/export strings
- [ ] Screenshots, logos and more languages

---

## 5. Rules and risks
- **Blizzard ToS:** The addons never press anything for the player; they only display information and change talents, bars or keys when the player clicks. No unlockers, no automation.
- Comparing or doing arithmetic on a secret value throws a Lua error, so every combat read goes through secret-safe helpers.
- Blizzard's whitelist can change with patches, so rerun `/dnd probe` after each one.
- Interface versions: `120005, 120007, 120100, 120105` (12.0.5 to 12.1.5).

## 6. Development setup
- `install.ps1` links both addon folders into WoW's `AddOns` folder as junctions. Edit the files here and type `/reload` in game.
- `tools/package.ps1 -Version x.y.z` builds CurseForge-ready zips into `.release/`.
