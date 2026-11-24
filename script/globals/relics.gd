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
## - "battle_progress": halbe Stufen extra pro gewonnenem Kampf (normal 0, ein K.O. = 1 halbe Stufe), kontext = Monster
## - "trophy_bonus": Extra-Punkte pro Trophäe, auch für schon gesammelte, kontext = null
## - "element_multiplier": Element-Faktor eines magischen Treffers, kontext = Element-Wertung (Skills.element_score)
##
## Einmalige Effekte beim Einsammeln stehen unter "on_add" (siehe add_relic).
##
## Für reaktive Effekte ("wenn X passiert, tu Y") kann ein Relic später zusätzlich
## "on_<event>" Einträge bekommen, die in _ready() an die Signale aus Events gehängt werden.

signal relics_changed

## Relics gibt es als Boss-Belohnung und im Shop. Relikt-Kisten: Boss-Felder (Mini-Bosse) bieten nur gewöhnliche,
## Biom-Bosse nur seltene an (chest_offers). Im Void wird nur gegen gleiche Seltenheit getauscht.
enum Rarity { COMMON, RARE }

const KEY_FINDER_FACTOR := 1.5
## Doppeltes Wachstum: eine halbe Stufe extra pro Kampf
const BATTLE_PROGRESS_BONUS := 1
const TROPHY_EXTRA_BONUS := 2
const KEY_RING_KEYS := 2
## Schatzjäger: Chance auf Couvert bzw. Trophäe in einer Schatzkiste, wie die auf einen Schlüssel (battle.gd KEY_LOOT_CHANCE)
const TREASURE_HUNTER_CHANCE := 0.15
## Finder: so viele zufällige One-Way-Items beim Einsammeln
const FINDER_ITEMS := 3
## Brutaler Schlag: so viel mehr Element-Faktor bei starken, so viel weniger bei schwachen magischen Treffern
const BRUTAL_STRIKE_SHIFT := 0.5

# var statt const: Lambdas sind keine konstanten Ausdrücke
var RELICS := {
	"extra_move": {
		"name": "RELIC_EXTRA_MOVE",
		"description": "RELIC_EXTRA_MOVE_DESC",
		"icon": "res://assets/global_relics/extra_move.png",
		"rarity": Rarity.RARE,
		"hooks": {
			# eigene UND gegnerische Monster bekommen eine Aktion mehr (battle.gd _plan_intent fragt den Hook für Gegner ab)
			"moves": func(value: int, _mon: Monster) -> int: return value + 1,
		},
	},
	"lucky_charm": {
		"name": "RELIC_LUCKY_CHARM",
		"description": "RELIC_LUCKY_CHARM_DESC",
		"icon": "res://assets/global_relics/lucky_charm.png",
		"rarity": Rarity.COMMON,
		"hooks": {
			"catch_chance": func(value: float, _mon: Monster) -> float: return value * 1.25,
		},
	},
	"golden_idol": {
		"name": "RELIC_GOLDEN_IDOL",
		"description": "RELIC_GOLDEN_IDOL_DESC",
		"icon": "res://assets/global_relics/golden_idol.png",
		"rarity": Rarity.COMMON,
		"hooks": {
			"battle_ep": func(value: int, _ctx) -> int: return roundi(value * 1.3),
		},
	},
	# Spyglass und Super Catcher haben keine Hooks, die Karte fragt sie über works() ab (world_map.gd)
	"spyglass": {
		"name": "RELIC_SPYGLASS",
		"description": "RELIC_SPYGLASS_DESC",
		"icon": "res://assets/global_relics/spyglass.png",
		"rarity": Rarity.RARE,
	},
	"super_catcher": {
		"name": "RELIC_SUPER_CATCHER",
		"description": "RELIC_SUPER_CATCHER_DESC",
		"icon": "res://assets/global_relics/super_catcher.png",
		"rarity": Rarity.COMMON,
	},
	"key_finder": {
		"name": "RELIC_KEY_FINDER",
		"description": "RELIC_KEY_FINDER_DESC",
		"icon": "res://assets/global_relics/key_finder.png",
		"rarity": Rarity.COMMON,
		"hooks": {
			"key_chance": func(value: float, _ctx) -> float: return value * KEY_FINDER_FACTOR,
		},
	},
	"slow_start": {
		"name": "RELIC_SLOW_START",
		"description": "RELIC_SLOW_START_DESC",
		"icon": "res://assets/global_relics/slow_start.png",
		"rarity": Rarity.RARE,
		"hooks": {
			"first_round_order": func(order: Array, _ctx) -> Array: return _slowest_own_first(order),
		},
	},
	# Wie Spyglass ohne Hook: die Kampf-Anzeige fragt es über works() ab (battle_info_panel.gd)
	"all_stats": {
		"name": "RELIC_ALL_STATS",
		"description": "RELIC_ALL_STATS_DESC",
		"icon": "res://assets/global_relics/all_stats.png",
		"rarity": Rarity.RARE,
	},
	# Ohne Hook: die HP-Balken im Kampf zeigen damit auch bei Gegnern die genauen HP (battle_mon_card.gd, battle_info_panel.gd)
	"enemy_hp": {
		"name": "RELIC_ENEMY_HP",
		"description": "RELIC_ENEMY_HP_DESC",
		"icon": "res://assets/global_relics/enemy_hp.png",
		"rarity": Rarity.COMMON,
	},
	# Ohne Hook: der Kampf deckt damit zu Beginn alle gegnerischen Attacken auf (battle.gd)
	"all_skills": {
		"name": "RELIC_ALL_SKILLS",
		"description": "RELIC_ALL_SKILLS_DESC",
		"icon": "res://assets/global_relics/all_skills.png",
		"rarity": Rarity.RARE,
	},
	"double_level": {
		"name": "RELIC_DOUBLE_LEVEL",
		"description": "RELIC_DOUBLE_LEVEL_DESC",
		"icon": "res://assets/global_relics/double_level.png",
		"rarity": Rarity.COMMON,
		"hooks": {
			"battle_progress": func(value: int, _mon: Monster) -> int: return value + BATTLE_PROGRESS_BONUS,
		},
	},
	"trophy_bonus": {
		"name": "RELIC_TROPHY_BONUS",
		"description": "RELIC_TROPHY_BONUS_DESC",
		"icon": "res://assets/global_relics/trophy_bonus.png",
		"rarity": Rarity.COMMON,
		"hooks": {
			"trophy_bonus": func(value: int, _ctx) -> int: return value + TROPHY_EXTRA_BONUS,
		},
	},
	"key_ring": {
		"name": "RELIC_KEY_RING",
		"description": "RELIC_KEY_RING_DESC",
		"icon": "res://assets/global_relics/key_ring.png",
		"rarity": Rarity.COMMON,
		"on_add": func() -> void: State.keys += KEY_RING_KEYS,
	},
	# Ersetzt im Lager Tasche und Essenz (heal_camp.gd)
	"endless_fire": {
		"name": "RELIC_ENDLESS_FIRE",
		"description": "RELIC_ENDLESS_FIRE_DESC",
		"icon": "res://assets/global_relics/endless_fire.png",
		"rarity": Rarity.RARE,
	},
	# Erlaubt auf der Karte jede Lane der nächsten Reihe (world_map.gd). Nur über die Einstellungen (GameSettings.flying_carpet)
	"flying_carpet": {
		"name": "RELIC_FLYING_CARPET",
		"description": "RELIC_FLYING_CARPET_DESC",
		"icon": "res://assets/global_relics/flying_carpet.png",
		"rarity": Rarity.RARE,
	},
	# Schatzkisten können zusätzlich ein Fähigkeiten-Couvert und eine Trophäe enthalten (treasure.gd)
	"treasure_hunter": {
		"name": "RELIC_TREASURE_HUNTER",
		"description": "RELIC_TREASURE_HUNTER_DESC",
		"icon": "res://assets/global_relics/treasure_hunter.png",
		"rarity": Rarity.COMMON,
	},
	"finder": {
		"name": "RELIC_FINDER",
		"description": "RELIC_FINDER_DESC",
		"icon": "res://assets/global_relics/finder.png",
		"rarity": Rarity.COMMON,
		"on_add": func() -> void:
			for i in FINDER_ITEMS:
				Items.add_to_bag(Items.roll_item()),
	},
	# gilt für alle Monster, eigene und gegnerische (Skills.skill_element_multiplier)
	"brutal_strike": {
		"name": "RELIC_BRUTAL_STRIKE",
		"description": "RELIC_BRUTAL_STRIKE_DESC",
		"icon": "res://assets/global_relics/brutal_strike.png",
		"rarity": Rarity.RARE,
		"hooks": {
			"element_multiplier": func(value: float, score: int) -> float: return _brutal_strike(value, score),
		},
	},
}

## Brutaler Schlag: starke magische Treffer +0.5, schwache -0.5 (bei x0.5 also gar kein Schaden mehr)
func _brutal_strike(value: float, score: int) -> float:
	if score > 0:
		return value + BRUTAL_STRIKE_SHIFT
	if score < 0:
		return maxf(value - BRUTAL_STRIKE_SHIFT, 0.0)
	return value

## Das langsamste eigene Monster rückt ganz nach vorn. order ist schon nach Initiative sortiert.
func _slowest_own_first(order: Array) -> Array:
	var own := order.filter(func(mon: Monster): return State.mons.has(mon))
	if not own.is_empty():
		order.erase(own.back())
		order.push_front(own.back())
	return order

func get_relic(id: String) -> Dictionary:
	return RELICS.get(id, {})

## Gesammelt oder durch den Easy Mode geschenkt. Geschenkte Relikte werden so auch nicht mehr angeboten (get_unowned).
func has_relic(id: String) -> bool:
	return State.relics.has(id) or is_easy_mode_relic(id)

## Kommt aus den Einstellungen (Easy Mode oder Gegner-HP), nicht aus dem Run (lässt sich z. B. im Void nicht tauschen)
func is_easy_mode_relic(id: String) -> bool:
	return settings_relics().has(id)

## Relikte, die die Einstellungen gerade schenken
func settings_relics() -> Array[String]:
	var ids: Array[String] = []
	if GameSettings.easy_mode:
		ids.append_array(EASY_MODE_RELICS)
	if GameSettings.show_enemy_hp:
		ids.append(ENEMY_HP_RELIC)
	if GameSettings.flying_carpet:
		ids.append(CARPET_RELIC)
	return ids

## Alle Relikte, die gerade gelten: die gesammelten und die aus den Einstellungen
func owned() -> Array[String]:
	var ids: Array[String] = State.relics.duplicate()
	for id in settings_relics():
		if not ids.has(id):
			ids.append(id)
	return ids

## Im Debug-Menü ausgeschaltete Relics wirken nicht und werden nirgends angeboten
func is_active(id: String) -> bool:
	return not DebugSettings.is_relic_disabled(id)

## Diese Relikte gibt es nur im Shop, alle anderen nur aus Relikt-Kisten (Boss-Belohnung)
const SHOP_RELICS := ["spyglass", "super_catcher", "all_stats", "all_skills", "enemy_hp"]

## Im Easy Mode (GameSettings.easy_mode) gelten diese Relikte in jedem Run als gesammelt
const EASY_MODE_RELICS := ["all_stats", "all_skills"]
## Mit GameSettings.show_enemy_hp gilt dieses Relikt in jedem Run als gesammelt
const ENEMY_HP_RELIC := "enemy_hp"
## Mit GameSettings.flying_carpet gilt dieses Relikt in jedem Run als gesammelt
const CARPET_RELIC := "flying_carpet"
## Diese Relikte gibt es nur über die Einstellungen, sie werden nirgends angeboten (zu stark für normale Runs)
const SETTINGS_ONLY_RELICS := [CARPET_RELIC]

## Was der Shop anbieten kann: nur SHOP_RELICS, aktiv und noch nicht gesammelt
func shop_offers() -> Array:
	return get_unowned().filter(func(id): return SHOP_RELICS.has(id))

## Was eine Relikt-Kiste anbieten kann: alles außer SHOP_RELICS, optional nur einer Seltenheit.
## Ist von der Seltenheit nichts mehr übrig, kommt die andere dran, damit die Kiste nicht leer bleibt.
func chest_offers(rarity: int = -1) -> Array:
	var all := get_unowned().filter(func(id): return not SHOP_RELICS.has(id))
	if rarity < 0:
		return all
	var matching := all.filter(func(id): return RELICS[id].rarity == rarity)
	return matching if not matching.is_empty() else all

## Seltenheit der Relikt-Kiste nach einem Boss-Sieg: Biom-Bosse seltene, Boss-Felder gewöhnliche
func chest_rarity(biome_boss: bool) -> int:
	return Rarity.RARE if biome_boss else Rarity.COMMON

## Gesammelt und nicht im Debug-Menü ausgeschaltet
func works(id: String) -> bool:
	return has_relic(id) and is_active(id)

func set_active(id: String, active: bool) -> void:
	DebugSettings.set_relic_disabled(id, not active)
	relics_changed.emit()

## Aktive Relics, die in diesem Run noch nicht gesammelt wurden, optional nur einer Seltenheit.
## Relikte aus SETTINGS_ONLY_RELICS fehlen immer, es gibt sie nur über die Einstellungen.
func get_unowned(rarity: int = -1) -> Array:
	return RELICS.keys().filter(func(id): return is_active(id) and not has_relic(id) and not SETTINGS_ONLY_RELICS.has(id) and (rarity < 0 or RELICS[id].rarity == rarity))

## Wogegen sich ein gesammeltes Relic im Void tauschen lässt: gleiche Seltenheit, noch nicht gesammelt
func swap_offers(id: String) -> Array:
	return get_unowned(RELICS[id].rarity)

func can_swap() -> bool:
	return State.relics.any(func(id): return not swap_offers(id).is_empty())

func add_relic(id: String) -> void:
	if not RELICS.has(id) or State.relics.has(id):
		return
	State.relics.append(id)
	var on_add = get_relic(id).get("on_add")
	if on_add:
		on_add.call()
	relics_changed.emit()

func remove_relic(id: String) -> void:
	if not State.relics.has(id):
		return
	State.relics.erase(id)
	relics_changed.emit()

## Wendet die Hooks aller gesammelten, aktiven Relics nacheinander auf value an.
func modify(hook: String, value, context = null):
	for id in owned():
		if not is_active(id):
			continue
		var fn = get_relic(id).get("hooks", {}).get(hook)
		if fn:
			value = fn.call(value, context)
	return value
