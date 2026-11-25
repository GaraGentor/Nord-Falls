extends Node

## Interaktives Tutorial als eigener Lauf (Plan: tutorial_plan.txt). Solange "tutorial_done" false ist, fragt die
## Ei-Auswahl beim Start, ob man mit Hilfe spielen will (start_run) oder nicht (decline). Später startet es nur
## über den Button in den Einstellungen, und nur in der Ei-Auswahl (can_start), nie mitten in einem Lauf.
## Während des Tutorial-Laufs (run_active) wird nichts gespeichert (SaveManager.suspended), am Ende oder beim
## Überspringen kommt der Spielstand von vorher zurück (end_run): aus dem Tutorial bleibt nichts.
##
## Szenen rufen trigger("<id>") auf, im Tutorial-Lauf spielt dann ein TutorialOverlay die Sequenz ab, jede nur einmal
## (SaveManager "tutorial_seen"). In echten Läufen kommt nichts.
## Der Kampf wird in einem eigenen Übungskampf erklärt (start_practice), der vor der Karte läuft.
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
##  dismiss  der Schritt wartet auf eine Aktion, zeigt aber auch Weiter: das beendet die Sequenz (Trainer verschwindet)

const BATTLE_SCENE := "res://script/scenes/battle/battle.tscn"
const SELECTION_SCENE := "res://script/scenes/selection/selection.tscn"
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
		{"text": "TUT_SEL_GO", "target": ["eggs", "begin_journey"], "wait": "pressed:begin_journey", "dismiss": true},
	]},
	"egg_configurator": {"speaker": "trainer", "steps": [
		{"text": "TUT_CFG_MON", "target": "cfg_mon"},
		{"text": "TUT_CFG_SLOTS", "target": "cfg_slots"},
		{"text": "TUT_CFG_ARC", "target": "cfg_grid"},
		{"text": "TUT_CFG_GRID", "target": ["cfg_grid", "cfg_slots"], "wait": "signal:egg_loadout_complete"},
		{"text": "TUT_CFG_GO", "target": ["cfg_go", "cfg_slots", "cfg_grid"], "wait": "pressed:cfg_go", "dismiss": true},
	]},
	# Übungskampf (start_practice): alles rund um den Kampf an einem Gegner, der nicht K.O. gehen kann
	"battle": {"speaker": "trainer", "steps": [
		{"text": "TUT_BAT_INTRO"},
		{"text": "TUT_BAT_WHEEL", "target": "bat_wheel"},
		{"text": "TUT_BAT_INTENT", "target": "bat_intent"},
		{"text": "TUT_BAT_CARD", "target": ["bat_hand", "bat_enemies"], "wait": "signal:call_skill_card"},
		# Faust = physisch, Funkeln (Diamant) = magisch (nur Magie nutzt das Element), ein Schild blockt beides; dazu Buffs und Passive
		{"text": "TUT_BAT_KINDS", "target": "bat_hand"},
		{"text": "TUT_BAT_BUFFS", "target": "bat_hand"},
		{"text": "TUT_BAT_ELEMENTS"},
		{"text": "TUT_BAT_END", "target": "bat_end_turn", "wait": "pressed:bat_end_turn"},
		{"text": "TUT_BAT_FAINTED"},
		{"text": "TUT_BAT_BOSS"},
		# One-Way-Items: links am Rand stecken die Postits, im Übungskampf hat jedes Monster einen Köder geliehen
		{"text": "TUT_BAT_ITEMS", "target": "bat_items"},
		{"text": "TUT_BAT_BAIT", "target": ["bat_items", "bat_enemies"], "wait": "signal:item_used"},
		{"text": "TUT_BAT_CATCH", "target": "bat_catch", "wait": "pressed:bat_catch"},
	]},
	"map": {"speaker": "trainer", "steps": [
		{"text": "TUT_MAP_INTRO"},
		{"text": "TUT_MAP_TEAM", "target": "map_team"},
		{"text": "TUT_MAP_BAG", "target": "map_bag"},
		{"text": "TUT_MAP_LEGEND", "target": "map_legend"},
		# nur zu Beginn eines Runs, wenn die erste Reihe noch frei wählbar ist
		{"text": "TUT_MAP_START", "target": "map_start", "wait": "pressed:map_start", "if_present": true, "dismiss": true},
	]},
	"judgement": {"speaker": "trainer", "steps": [
		{"text": "TUT_JUD_CATCHES", "target": "jud_catches"},
		{"text": "TUT_JUD_TEAM", "target": "jud_team"},
		{"text": "TUT_JUD_SKILLS", "target": "jud_skills"},
		{"text": "TUT_JUD_BAG", "target": "jud_bag", "if_present": true},
		{"text": "TUT_JUD_CONFIRM", "target": "jud_confirm", "wait": "pressed:jud_confirm", "open": true, "dismiss": true},
	]},
	"loot": {"speaker": "trainer", "steps": [
		{"text": "TUT_LOOT_XP", "target": "loot_team"},
		{"text": "TUT_LOOT_DRAG", "target": "loot_field", "free": true},
	]},
	# Erst-Begegnungen mit NPC: der NPC der Szene spricht selbst (Gruppe "tut_npc")
	# Die Kasse (rechts) spricht ihre eigenen Sätze (shop.gd HOWTO_LINES), jetzt mit Blick auf Regale, Monster und Tasche
	"shop": {"speaker": "npc", "steps": [
		{"text": "SHOP_SAY_WELCOME"},
		{"text": "SHOP_SAY_POTIONS", "target": ["shop_shelf_0", "shop_mon_0", "shop_mon_1"]},
		{"text": "SHOP_SAY_ITEMS", "target": ["shop_shelf_1", "shop_bag"]},
		{"text": "SHOP_SAY_GEMS", "target": ["shop_shelf_2", "shop_mon_0", "shop_mon_1"]},
		{"text": "SHOP_SAY_RELICS", "target": ["shop_shelf_3", "shop_bag"]},
		{"text": "SHOP_SAY_CLICK", "target": ["shop_shelf_0", "shop_shelf_1", "shop_shelf_2", "shop_shelf_3", "shop_mon_0", "shop_mon_1"]},
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
	_overlay.skipped.connect(ask_skip)
	_overlay.tree_exited.connect(func():
		if on_end.is_valid():
			on_end.call())
	_overlay.start(SEQUENCES[id], get_tree().current_scene)
	return true

func should_show(id: String) -> bool:
	return SEQUENCES.has(id) and run_active and not SaveManager.save_data["tutorial_seen"].has(id)

func is_running() -> bool:
	return is_instance_valid(_overlay) and not _overlay.is_queued_for_deletion()

## Für Szenen, die Mausklicks selbst in _input auswerten: true, solange das Tutorial den Klick an dieser Stelle abfängt
func blocks_input(point: Vector2) -> bool:
	return is_running() and not _overlay.lets_through(point)

# ─────────────────────────
# Tutorial-Lauf

## true vom Start des Tutorials bis zu seinem Ende (oder Überspringen)
var run_active := false
## Spielstand von vor dem Tutorial, kommt mit end_run zurück
var _save_backup := {}

## Ei-Auswahl beim Start: fragen, ob man mit Hilfe spielen will (neuer Spielstand oder Tutorial nie beendet)
func needs_start_question() -> bool:
	return not run_active and not SaveManager.save_data["tutorial_done"]

## Einstellungen: starten nur in der Ei-Auswahl, nie mitten in einem Lauf
func can_start() -> bool:
	var scene := get_tree().current_scene
	return not run_active and scene != null and scene.scene_file_path == SELECTION_SCENE

## Startabfrage abgelehnt: kein Tutorial, die Frage kommt nicht wieder
func decline() -> void:
	SaveManager.save_data["tutorial_done"] = true
	SaveManager.save_game()

## Merkt sich den Spielstand, schaltet das Speichern ab und startet die Ei-Auswahl neu im Tutorial-Modus,
## mit eigenen Eiern und eigenem Biom-Pfad (die echten kommen mit end_run zurück)
func start_run() -> void:
	if run_active:
		return
	# auf der Platte bleibt tutorial_done, wie es war: bricht das Spiel mittendrin ab, kommt die Startabfrage wieder
	_save_backup = SaveManager.save_data.duplicate(true)
	_save_backup["tutorial_done"] = true
	SaveManager.suspended = true
	run_active = true
	SaveManager.save_data["tutorial_seen"] = []
	SaveManager.save_data["starter_eggs"] = []
	SaveManager.save_data["biome_path"] = []
	SaveManager.save_data["biome_pools"] = []
	State.reset()
	SceneLoader.change_scene(SELECTION_SCENE)

## Ende oder Überspringen: Spielstand von vorher zurück, Speichern wieder an, zurück zur Ei-Auswahl
func end_run() -> void:
	if not run_active:
		return
	run_active = false
	practice = false
	_back_from_practice = false
	if is_running():
		_overlay.queue_free()
	SaveManager.save_data = _save_backup
	_save_backup = {}
	SaveManager.suspended = false
	SaveManager.save_game()
	State.reset()
	State.boss_shards = SaveManager.save_data["boss_shards"]
	SceneLoader.change_scene(SELECTION_SCENE)

## "Tutorial überspringen" in der Sprechblase: mit Rückfrage, die Sequenz bleibt solange stehen
func ask_skip() -> void:
	if not run_active or not is_running():
		return
	var dialog := ChoiceDialog.ask(_overlay.dialog_host(), tr("TUTORIAL_SKIP_TITLE"), tr("TUTORIAL_SKIP_TEXT"),
		tr("TUTORIAL_SKIP_YES"), tr("TUTORIAL_SKIP_NO"))
	if await dialog.chosen:
		end_run()

# ─────────────────────────
# Übungskampf: läuft vor der Karte, solange die Kampf-Sequenz noch aussteht

func wants_practice() -> bool:
	return should_show("battle")

func start_practice() -> void:
	practice = true
	SceneLoader.change_scene(BATTLE_SCENE)

## battle.gd: der Übungskampf ist vorbei (gefangen oder Tutorial ausgeschaltet), weiter zur Karte
func end_practice() -> void:
	practice = false
	_back_from_practice = true
	SceneLoader.change_scene(MAP_SCENE)

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
