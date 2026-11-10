extends Node

## Interaktives Tutorial: Szenen rufen trigger("<id>") auf, beim ersten Mal spielt ein TutorialOverlay die Sequenz ab.
## Jede Sequenz läuft nur einmal (SaveManager "tutorial_seen"). Sind alle gesehen oder hat der Spieler
## übersprungen, ist das Tutorial abgeschlossen ("tutorial_done") und erscheint nicht mehr.
## Neue Spielstände starten ohne Tutorial; eingeschaltet wird es im Einstellungen-Dialog (set_enabled).
##
## Echte Kämpfe bleiben frei vom Tutorial: der Kampf wird in einem eigenen Übungskampf erklärt (start_practice),
## der vor der Karte läuft und nichts am Run oder Spielstand ändert.
##
## Schritt einer Sequenz:
##  text   Übersetzungsschlüssel, den der NPC sagt
##  target Gruppe(n) ohne "tut_"-Präfix, die hervorgehoben werden (String oder Array, optional);
##         jede Gruppe bekommt ein Loch um alle ihre Mitglieder
##  wait   "next" (Weiter-Knopf, Standard), "pressed:<Gruppe>" (einen Knopf der Gruppe drücken, mit count mehrmals)
##         oder "signal:<Signal aus Events>"
##  free   bei "next": das Ziel bleibt trotzdem bedienbar (z. B. Beute einsammeln)
##  open   alles bleibt bedienbar und nur leicht abgedunkelt, das Ziel zeigt nur den nächsten Schritt
##  if_present  der Schritt entfällt, wenn sein (erstes) Ziel gerade nicht zu sehen ist

## Ein- oder ausgeschaltet (Einstellungen), true = eingeschaltet
signal enabled_changed(on: bool)

const BATTLE_SCENE := "res://script/scenes/battle/battle.tscn"
const MAP_SCENE := "res://script/scenes/world_map/world_map.tscn"

## Wer spricht: Bild und Pixel-Material des NPCs unten in der Ecke
const SPEAKERS := {
	"trainer": {
		"texture": "res://assets/npcs/trainer_cutout.png",
		"material": "res://script/scenes/trainer/trainer_npc_material.tres",
	},
}

const SEQUENCES := {
	"selection": {"speaker": "trainer", "steps": [
		{"text": "TUT_SEL_WELCOME"},
		{"text": "TUT_SEL_PATH", "target": "biome_path"},
		{"text": "TUT_SEL_DRAW", "target": "draw_egg", "wait": "pressed:draw_egg", "count": 3},
		{"text": "TUT_SEL_PICK", "target": "eggs", "wait": "signal:select_initial_mon"},
		{"text": "TUT_SEL_INFO", "target": "starter_info"},
		{"text": "TUT_SEL_GO", "target": ["eggs", "begin_journey"], "wait": "pressed:begin_journey"},
	]},
	"egg_configurator": {"speaker": "trainer", "steps": [
		{"text": "TUT_CFG_MON", "target": "cfg_mon"},
		{"text": "TUT_CFG_SLOTS", "target": "cfg_slots"},
		{"text": "TUT_CFG_GRID", "target": "cfg_grid"},
		{"text": "TUT_CFG_GO", "target": ["cfg_go", "cfg_slots", "cfg_grid"], "wait": "pressed:cfg_go"},
	]},
	# Übungskampf (start_practice): alles rund um den Kampf an einem Gegner, der nicht K.O. gehen kann
	"battle": {"speaker": "trainer", "steps": [
		{"text": "TUT_BAT_INTRO"},
		{"text": "TUT_BAT_WHEEL", "target": "bat_wheel"},
		{"text": "TUT_BAT_INTENT", "target": "bat_intent"},
		{"text": "TUT_BAT_CARD", "target": ["bat_hand", "bat_enemies"], "wait": "signal:call_skill_card"},
		{"text": "TUT_BAT_ELEMENTS"},
		{"text": "TUT_BAT_END", "target": "bat_end_turn", "wait": "pressed:bat_end_turn"},
		{"text": "TUT_BAT_FAINTED"},
		{"text": "TUT_BAT_BOSS"},
		{"text": "TUT_BAT_CATCH", "target": "bat_catch", "wait": "pressed:bat_catch"},
	]},
	"map": {"speaker": "trainer", "steps": [
		{"text": "TUT_MAP_INTRO"},
		{"text": "TUT_MAP_TEAM", "target": "map_team"},
		{"text": "TUT_MAP_LEGEND", "target": "map_legend"},
		# nur zu Beginn eines Runs, wenn die erste Reihe noch frei wählbar ist
		{"text": "TUT_MAP_START", "target": "map_start", "wait": "pressed:map_start", "if_present": true},
	]},
	"judgement": {"speaker": "trainer", "steps": [
		{"text": "TUT_JUD_CATCHES", "target": "jud_catches"},
		{"text": "TUT_JUD_TEAM", "target": "jud_team"},
		{"text": "TUT_JUD_ZONES", "target": "jud_zones"},
		{"text": "TUT_JUD_CONFIRM", "target": "jud_confirm", "wait": "pressed:jud_confirm", "open": true},
	]},
	"loot": {"speaker": "trainer", "steps": [
		{"text": "TUT_LOOT_XP", "target": "loot_team"},
		{"text": "TUT_LOOT_DRAG", "target": "loot_field", "free": true},
	]},
	# Erst-Begegnungen mit NPC: der NPC der Szene spricht selbst (Gruppe "tut_npc")
	# Die Kasse spricht ihre eigenen Sätze (shop.gd HOWTO_LINES), jetzt mit Blick auf die Regale
	"shop": {"speaker": "npc", "steps": [
		{"text": "SHOP_SAY_WELCOME"},
		{"text": "SHOP_SAY_POTIONS", "target": ["shop_shelf_0", "shop_shelf_1", "shop_mon_0", "shop_mon_1"]},
		{"text": "SHOP_SAY_GEMS", "target": ["shop_shelf_2", "shop_mon_0", "shop_mon_1"]},
		{"text": "SHOP_SAY_RELICS", "target": ["shop_shelf_3", "shop_bag"]},
		{"text": "SHOP_SAY_CLICK", "target": ["shop_shelf_0", "shop_shelf_1", "shop_shelf_2", "shop_shelf_3"]},
	]},
	"trainer": {"speaker": "npc", "steps": [
		{"text": "TUT_TRN_CARDS", "target": "trn_cards"},
		{"text": "TUT_TRN_MONS", "target": ["trn_cards", "trn_mons"]},
		{"text": "TUT_TRN_PAY", "target": "trn_bag"},
	]},
	"jailer": {"speaker": "npc", "steps": [
		{"text": "TUT_JAIL_CAGES", "target": "jail_cages"},
		{"text": "TUT_JAIL_TEARS", "target": "jail_bag"},
		{"text": "TUT_JAIL_CHAIN", "target": ["jail_bag", "jail_cages"]},
		{"text": "TUT_JAIL_REROLL", "target": "jail_reroll"},
	]},
	"camp": {"speaker": "npc", "steps": [
		{"text": "TUT_CAMP_TEAM", "target": ["camp_mon_0", "camp_mon_1"]},
		{"text": "TUT_CAMP_FEED", "target": "camp_feed", "free": true},
	]},
	# Erst-Begegnungen ohne NPC: der Trainer erklärt kurz (Glücksrad und Void erklären sich selbst)
	"hub": {"speaker": "trainer", "steps": [{"text": "TUT_HUB", "target": "hub_stations"}]},
	"treasure": {"speaker": "trainer", "steps": [{"text": "TUT_TREASURE", "target": "treasure_buttons"}]},
	"gems": {"speaker": "trainer", "steps": [{"text": "TUT_GEMS"}]},
	"relic_reward": {"speaker": "trainer", "steps": [{"text": "TUT_RELIC_REWARD"}]},
	"skill_reward": {"speaker": "trainer", "steps": [{"text": "TUT_SKILL_REWARD"}]},
}

## true, solange der Übungskampf läuft (battle.gd fragt das ab)
var practice := false
## Übungskampf gerade vorbei: die Karte erklärt sich danach auch mitten im Run (take_back_from_practice)
var _back_from_practice := false

var _overlay: TutorialOverlay

## Startet die Sequenz, wenn sie noch nicht gesehen wurde und keine andere läuft.
## true = sie läuft jetzt; on_end läuft, sobald sie vorbei ist (fertig, übersprungen oder abgebrochen),
## so holen Szenen nach, was sie bis dahin zurückhalten. Ist die Szene dann schon weg, entfällt on_end.
func trigger(id: String, on_end := Callable()) -> bool:
	# eine Sequenz der vorigen Szene, die sich noch nicht selbst beendet hat, macht Platz
	if is_running() and _overlay.is_stale():
		_overlay.queue_free()
	if not should_show(id) or is_running():
		return false
	_overlay = TutorialOverlay.new()
	add_child(_overlay)
	_overlay.finished.connect(_mark_seen.bind(id))
	_overlay.skipped.connect(set_enabled.bind(false))
	_overlay.tree_exited.connect(func():
		if on_end.is_valid():
			on_end.call())
	_overlay.start(SEQUENCES[id], get_tree().current_scene)
	return true

func should_show(id: String) -> bool:
	return SEQUENCES.has(id) and is_enabled() and not SaveManager.save_data["tutorial_seen"].has(id)

func is_running() -> bool:
	return is_instance_valid(_overlay) and not _overlay.is_queued_for_deletion()

func is_enabled() -> bool:
	return not SaveManager.save_data["tutorial_done"]

## Für Szenen, die Mausklicks selbst in _input auswerten: true, solange das Tutorial den Klick an dieser Stelle abfängt
func blocks_input(point: Vector2) -> bool:
	return is_running() and not _overlay.lets_through(point)

## Einstellungen und "Tutorial überspringen": eingeschaltet beginnt alles von vorn,
## ausgeschaltet verschwindet auch eine laufende Sequenz
func set_enabled(on: bool) -> void:
	if on == is_enabled():
		return
	if not on and is_running():
		_overlay.queue_free()
	SaveManager.save_data["tutorial_seen"] = []
	SaveManager.save_data["tutorial_done"] = not on
	SaveManager.save_game()
	enabled_changed.emit(on)

# ─────────────────────────
# Übungskampf: läuft vor der Karte, solange die Kampf-Sequenz noch aussteht

func wants_practice() -> bool:
	return should_show("battle")

func start_practice() -> void:
	practice = true
	get_tree().change_scene_to_file(BATTLE_SCENE)

## battle.gd: der Übungskampf ist vorbei (gefangen oder Tutorial ausgeschaltet), weiter zur Karte
func end_practice() -> void:
	practice = false
	_back_from_practice = true
	get_tree().change_scene_to_file(MAP_SCENE)

## Karte: kommt der Spieler gerade aus dem Übungskampf? Fragt nur einmal.
func take_back_from_practice() -> bool:
	var back := _back_from_practice
	_back_from_practice = false
	return back

## Im Übungskampf geht niemand K.O.: jeder behält mindestens 1 KP
func cap_damage(mon: Monster, damage: float) -> float:
	if not practice:
		return damage
	return minf(damage, maxf(mon.hp() - mon._lost_hp - 1.0, 0.0))

## Im Übungskampf klappt der Fang sicher
func catches_for_sure(mon: Monster) -> bool:
	return practice and State.enemy_mons.has(mon)

func _mark_seen(id: String) -> void:
	var seen: Array = SaveManager.save_data["tutorial_seen"]
	if not seen.has(id):
		seen.append(id)
	if SEQUENCES.keys().all(seen.has):
		SaveManager.save_data["tutorial_done"] = true
	SaveManager.save_game()
