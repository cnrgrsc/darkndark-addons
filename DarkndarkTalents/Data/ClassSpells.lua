local _, ns = ...

-- Hand-maintained spell groups used by the bar layout. Unknown or unlearned
-- IDs are skipped at runtime, so outdated entries are harmless.
ns.ClassSpells = {
	interrupts = {
		WARRIOR = { 6552 }, ROGUE = { 1766 }, MAGE = { 2139 }, HUNTER = { 147362, 187707 },
		DEATHKNIGHT = { 47528 }, DEMONHUNTER = { 183752 }, DRUID = { 106839, 78675 },
		MONK = { 116705 }, PALADIN = { 96231 }, PRIEST = { 15487 }, SHAMAN = { 57994 },
		WARLOCK = { 119910, 19647, 132409, 89766 }, EVOKER = { 351338 },
	},
	defensives = {
		WARRIOR     = { 871, 118038, 184364, 97462, 23920, 12975 },
		ROGUE       = { 5277, 31224, 185311, 1966 },
		MAGE        = { 45438, 55342, 342245, 414658, 11426, 235313, 235450 },
		HUNTER      = { 186265, 109304, 264735 },
		DEATHKNIGHT = { 48792, 48707, 49039, 55233, 51052 },
		DEMONHUNTER = { 198589, 196718, 187827, 204021, 203720 },
		DRUID       = { 22812, 61336, 108238, 102342 },
		MONK        = { 115203, 122470, 122278, 122783, 115176 },
		PALADIN     = { 642, 498, 184662, 31850, 86659, 403876, 1022 },
		PRIEST      = { 19236, 47585, 586, 33206, 47788 },
		SHAMAN      = { 108271, 108281, 198103 },
		WARLOCK     = { 104773, 108416 },
		EVOKER      = { 363916, 374348, 374227 },
	},
}
