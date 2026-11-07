extends Node

## Relics: passive Run-Boni, gesammelt in State.relics (Liste von Relic-IDs).
##
## Wirkung über benannte Hooks: An den Stellen im Spielcode, wo ein Wert entsteht, wird
## Relics.modify("<hook>", wert, kontext) aufgerufen. Jedes Relic kann pro Hook eine
## Funktion (wert, kontext) -> neuer_wert mitbringen. So steht die Logik eines Relics an
## einem Ort, der Spielcode kennt nur die Hooks, nicht die einzelnen Relics.
##
## Bekannte Hooks:
## - "moves": Skillpunkte (Züge) eines Monsters zu Beginn seines Zuges, kontext = Monster
## - "catch_chance": Fangchance 0..1 vor dem Begrenzen, kontext = gegnerisches Monster
## - "battle_ep": EP für einen gewonnenen Kampf, kontext = null
## - "key_chance": Chance 0..1 auf einen Schlüssel als Beute, kontext = null
## - "first_round_order": Zugreihenfolge der ersten Kampfrunde (Array von Monstern), kontext = null
## - "level_up_levels": Stufen, die ein Level-Up bringt, kontext = Monster
## - "trophy_bonus": Extra-Punkte pro Trophäe, auch für schon gesammelte, kontext = null
##
## Einmalige Effekte beim Einsammeln stehen unter "on_add" (siehe add_relic).
##
## Für reaktive Effekte ("wenn X passiert, tu Y") kann ein Relic später zusätzlich
## "on_<event>" Einträge bekommen, die in _ready() an die Signale aus Events gehängt werden.

signal relics_changed

## Relics gibt es als Boss-Belohnung und im Shop
enum Rarity { COMMON, RARE }

const KEY_FINDER_FACTOR := 1.5
const LEVEL_UP_LEVELS := 2
const TROPHY_EXTRA_BONUS := 2
const KEY_RING_KEYS := 2

# var statt const: Lambdas sind keine konstanten Ausdrücke
var RELICS := {
	"extra_move": {
		"name": "RELIC_EXTRA_MOVE",
		"description": "RELIC_EXTRA_MOVE_DESC",
		"icon": "res://assets/ui/icons/sword.svg",
		"rarity": Rarity.RARE,
		"hooks": {
			# nur eigene Monster profitieren
			"moves": func(value: int, mon: Monster) -> int: return value + 1 if State.mons.has(mon) else value,
		},
	},
	"lucky_charm": {
		"name": "RELIC_LUCKY_CHARM",
		"description": "RELIC_LUCKY_CHARM_DESC",
		"icon": "res://assets/ui/icons/sparkle.svg",
		"rarity": Rarity.COMMON,
		"hooks": {
			"catch_chance": func(value: float, _mon: Monster) -> float: return value * 1.25,
		},
	},
	"golden_idol": {
		"name": "RELIC_GOLDEN_IDOL",
		"description": "RELIC_GOLDEN_IDOL_DESC",
		"icon": "res://assets/ui/icons/firework (1).svg",
		"rarity": Rarity.COMMON,
		"hooks": {
			"battle_ep": func(value: int, _ctx) -> int: return roundi(value * 1.3),
		},
	},
	# Spyglass und Super Catcher haben keine Hooks, die Karte fragt sie über works() ab (world_map.gd)
	"spyglass": {
		"name": "RELIC_SPYGLASS",
		"description": "RELIC_SPYGLASS_DESC",
		"icon": "res://assets/ui/icons/info.svg",
		"rarity": Rarity.RARE,
	},
	"super_catcher": {
		"name": "RELIC_SUPER_CATCHER",
		"description": "RELIC_SUPER_CATCHER_DESC",
		"icon": "res://assets/ui/icons/bag.svg",
		"rarity": Rarity.COMMON,
	},
	"key_finder": {
		"name": "RELIC_KEY_FINDER",
		"description": "RELIC_KEY_FINDER_DESC",
		"icon": "res://assets/ui/icons/key.svg",
		"rarity": Rarity.COMMON,
		"hooks": {
			"key_chance": func(value: float, _ctx) -> float: return value * KEY_FINDER_FACTOR,
		},
	},
	"slow_start": {
		"name": "RELIC_SLOW_START",
		"description": "RELIC_SLOW_START_DESC",
		"icon": "res://assets/ui/icons/chevron-double-right.svg",
		"rarity": Rarity.RARE,
		"hooks": {
			"first_round_order": func(order: Array, _ctx) -> Array: return _slowest_own_first(order),
		},
	},
	# Wie Spyglass ohne Hook: die Kampf-Anzeige fragt es über works() ab (battle_info_panel.gd)
	"all_stats": {
		"name": "RELIC_ALL_STATS",
		"description": "RELIC_ALL_STATS_DESC",
		"icon": "res://assets/ui/icons/info.svg",
		"rarity": Rarity.RARE,
	},
	# Ohne Hook: der Kampf deckt damit zu Beginn alle gegnerischen Attacken auf (battle.gd)
	"all_skills": {
		"name": "RELIC_ALL_SKILLS",
		"description": "RELIC_ALL_SKILLS_DESC",
		"icon": "res://assets/ui/icons/info.svg",
		"rarity": Rarity.RARE,
	},
	"double_level": {
		"name": "RELIC_DOUBLE_LEVEL",
		"description": "RELIC_DOUBLE_LEVEL_DESC",
		"icon": "res://assets/ui/icons/arrow_go.svg",
		"rarity": Rarity.RARE,
		"hooks": {
			"level_up_levels": func(_value: int, _mon: Monster) -> int: return LEVEL_UP_LEVELS,
		},
	},
	"trophy_bonus": {
		"name": "RELIC_TROPHY_BONUS",
		"description": "RELIC_TROPHY_BONUS_DESC",
		"icon": "res://assets/ui/icons/fist.svg",
		"rarity": Rarity.COMMON,
		"hooks": {
			"trophy_bonus": func(value: int, _ctx) -> int: return value + TROPHY_EXTRA_BONUS,
		},
	},
	"key_ring": {
		"name": "RELIC_KEY_RING",
		"description": "RELIC_KEY_RING_DESC",
		"icon": "res://assets/ui/icons/key.svg",
		"rarity": Rarity.COMMON,
		"on_add": func() -> void: State.keys += KEY_RING_KEYS,
	},
	# Ersetzt im Lager Tasche und Essenz (heal_camp.gd)
	"endless_fire": {
		"name": "RELIC_ENDLESS_FIRE",
		"description": "RELIC_ENDLESS_FIRE_DESC",
		"icon": "res://assets/ui/icons/heart.svg",
		"rarity": Rarity.COMMON,
	},
	# Erlaubt auf der Karte jede Lane der nächsten Reihe (world_map.gd)
	"flying_carpet": {
		"name": "RELIC_FLYING_CARPET",
		"description": "RELIC_FLYING_CARPET_DESC",
		"icon": "res://assets/ui/icons/parchment.svg",
		"rarity": Rarity.RARE,
	},
}

## Das langsamste eigene Monster rückt ganz nach vorn. order ist schon nach Initiative sortiert.
func _slowest_own_first(order: Array) -> Array:
	var own := order.filter(func(mon: Monster): return State.mons.has(mon))
	if not own.is_empty():
		order.erase(own.back())
		order.push_front(own.back())
	return order

func get_relic(id: String) -> Dictionary:
	return RELICS.get(id, {})

func has_relic(id: String) -> bool:
	return State.relics.has(id)

## Im Debug-Menü ausgeschaltete Relics wirken nicht und werden nirgends angeboten
func is_active(id: String) -> bool:
	return not DebugSettings.is_relic_disabled(id)

## Gesammelt und nicht im Debug-Menü ausgeschaltet
func works(id: String) -> bool:
	return has_relic(id) and is_active(id)

func set_active(id: String, active: bool) -> void:
	DebugSettings.set_relic_disabled(id, not active)
	relics_changed.emit()

## Aktive Relics, die in diesem Run noch nicht gesammelt wurden, optional nur einer Seltenheit
func get_unowned(rarity: int = -1) -> Array:
	return RELICS.keys().filter(func(id): return is_active(id) and not has_relic(id) and (rarity < 0 or RELICS[id].rarity == rarity))

## Wogegen sich ein gesammeltes Relic im Void tauschen lässt: gleiche Seltenheit, noch nicht gesammelt
func swap_offers(id: String) -> Array:
	return get_unowned(RELICS[id].rarity)

func can_swap() -> bool:
	return State.relics.any(func(id): return not swap_offers(id).is_empty())

func add_relic(id: String) -> void:
	if not RELICS.has(id) or has_relic(id):
		return
	State.relics.append(id)
	var on_add = get_relic(id).get("on_add")
	if on_add:
		on_add.call()
	relics_changed.emit()

func remove_relic(id: String) -> void:
	if not has_relic(id):
		return
	State.relics.erase(id)
	relics_changed.emit()

## Wendet die Hooks aller gesammelten, aktiven Relics nacheinander auf value an.
func modify(hook: String, value, context = null):
	for id in State.relics:
		if not is_active(id):
			continue
		var fn = get_relic(id).get("hooks", {}).get(hook)
		if fn:
			value = fn.call(value, context)
	return value
