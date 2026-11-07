extends Node

enum MOUSE_ACTION {
	NONE,
	PLAY_CARD,
	SELECT_MONSTER,
	CATCH_MONSTER,
	CURRENTLY_SELECTED,
}

enum MON_TYPES {
	EARTH = 1 << 0,
	FIRE = 1 << 1,
	WATER  = 1 << 2,
	AIR = 1 << 3,
	#MAGMA,
	#SAND,
	#MUD,
	#STEAM,
	#PLASMA,
	#ICE,
}
var MON_TYPE_MAP = {
	"0" = "EARTH",
	"1" = "FIRE",
	"2" = "WATER",
	"3" = "AIR",
	#"4" = "MAGMA",
	#"5" = "SAND",
	#"6" = "MUD",
	#"7" = "STEAM",
	#"8" = "Plasma",
	#"9" = "ICE",
}

enum CARD_TARGETS {
	SINGLE_ENEMY,
	TEAM_ENEMY,
	SINGLE_FRIEND,
	TEAM_FRIEND,
}

enum SKILL_DAMAGE_TYPE {
	PHYSICAL,
	ABILITY,
}

enum MON_RARITY {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
}
