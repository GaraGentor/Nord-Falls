extends Node

## Interaktives Tutorial als eigener Lauf (Plan: tutorial_plan.txt). Solange "tutorial_done" false ist, fragt die
## Ei-Auswahl beim Start, ob man mit Hilfe spielen will (start_run) oder nicht (decline). Später startet es nur
## über den Button in den Einstellungen, und nur in der Ei-Auswahl (can_start), nie mitten in einem Lauf.
## Während des Tutorial-Laufs (run_active) wird nichts gespeichert (SaveManager.suspended), am Ende oder beim
## Überspringen kommt der Spielstand von vorher zurück (end_run): aus dem Tutorial bleibt nichts.
##
## Szenen rufen trigger("<id>") auf, im Tutorial-Lauf spielt dann ein TutorialOverlay die Sequenz ab, jede nur einmal
## (SaveManager "tutorial_seen"). In echten Läufen kommt nichts.
## Die Kämpfe der Tutorial-Karte sind fest beschrieben (FIGHTS), battle.gd baut sie danach auf.
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
##  bubble   "right" / "left": Trainer und Sprechblase bleiben auf dieser Bildschirmseite

const SELECTION_SCENE := "res://script/scenes/selection/selection.tscn"

## Wer spricht: Bild und Pixel-Material des NPCs unten in der Ecke
const SPEAKERS := {
	"trainer": {
		"texture": "res://assets/npcs/trainer_cutout.png",
		"material": "res://script/scenes/trainer/trainer_npc_material.tres",
	},
}

const SEQUENCES := {
	# Ei-Auswahl: Tipps, Biom-Pfad, erstes Ei und daran das Monster erklärt, dann die anderen Eier und die Wahl
	# mit Empfehlung ({mon}: Tutorial.prepare_starters garantiert einen Starter, der gegen das erste Biom stark ist)
	"selection": {"speaker": "trainer", "steps": [
		{"text": "TUT_SEL_WELCOME"},
		{"text": "TUT_SEL_TIPS", "target": "sel_tips"},
		{"text": "TUT_SEL_PATH", "target": "biome_path"},
		{"text": "TUT_SEL_PATH_CLICK", "target": "biome_path"},
		{"text": "TUT_SEL_DRAW", "target": "draw_egg", "wait": "pressed:draw_egg"},
		{"text": "TUT_SEL_LANDING", "wait": "signal:starter_egg_landed"},
		{"text": "TUT_SEL_SKILLS", "target": "sel_skills"},
		{"text": "TUT_SEL_ELEMENT", "target": "sel_chips"},
		{"text": "TUT_SEL_GROWTH", "target": "sel_radar"},
		{"text": "TUT_SEL_STATS", "target": "sel_stats"},
		{"text": "TUT_SEL_DRAW_REST", "target": "draw_egg", "wait": "pressed:draw_egg", "count": 2},
		{"text": "TUT_SEL_PICK", "target": "eggs", "wait": "signal:select_initial_mon"},
		{"text": "TUT_SEL_GO", "target": ["eggs", "begin_journey"], "wait": "pressed:begin_journey", "dismiss": true},
	]},
	"egg_configurator": {"speaker": "trainer", "steps": [
		{"text": "TUT_CFG_MON", "target": "cfg_mon"},
		{"text": "TUT_CFG_SLOTS", "target": "cfg_slots"},
		{"text": "TUT_CFG_ARC", "target": "cfg_grid"},
		{"text": "TUT_CFG_UNLOCK", "target": "cfg_grid"},
		# Blase rechts: sonst verdeckt der Text Karten, die man antippen muss
		{"text": "TUT_CFG_GRID", "target": ["cfg_grid", "cfg_slots"], "wait": "signal:egg_loadout_complete", "bubble": "right"},
		{"text": "TUT_CFG_GO", "target": ["cfg_go", "cfg_slots", "cfg_grid"], "wait": "pressed:cfg_go", "dismiss": true, "bubble": "right"},
	]},
	# Feld 1 (FIGHTS[0]): alles rund um den Kampf an einem Gegner, gegen den der Starter stark ist. Niemand geht K.O.,
	# der Fang mit Hypnose klappt sicher. Items, gefallene Monster und Bosse kommen in Feld 8 und 12.
	"battle": {"speaker": "trainer", "steps": [
		{"text": "TUT_BAT_INTRO"},
		{"text": "TUT_BAT_WHEEL", "target": "bat_wheel"},
		{"text": "TUT_BAT_INTENT", "target": "bat_intent"},
		{"text": "TUT_BAT_SCOUT", "target": "bat_enemies"},
		{"text": "TUT_BAT_CARD", "target": ["bat_hand", "bat_enemies"], "wait": "signal:call_skill_card"},
		# Faust = physisch, Funkeln (Diamant) = magisch (nur Magie nutzt das Element), ein Schild blockt beides; dazu Buffs und Passive
		{"text": "TUT_BAT_KINDS", "target": "bat_hand"},
		{"text": "TUT_BAT_BUFFS", "target": "bat_hand"},
		{"text": "TUT_BAT_ELEMENTS"},
		{"text": "TUT_BAT_END", "target": ["bat_hand", "bat_end_turn"]},
		# übrige Aktionen in der funkelnden Raute in der Mitte des Zugrads, dann den Zug beenden
		# erst weiter, wenn der Gegner wirklich dran ist: ist danach wieder ein eigenes Monster am Zug,
		# muss auch das den Zug beenden (sonst erledigt oder fängt man den Gegner vorbei am Tutorial)
		{"text": "TUT_BAT_MOVES", "target": ["bat_moves", "bat_end_turn"], "wait": "signal:enemy_turn_started"},
		{"text": "TUT_BAT_CATCH", "target": ["bat_catch", "bat_catch_chance"], "wait": "pressed:bat_catch"},
	]},
	# Feld 2: Element vom Partner leihen, Tempo und Auto. Der Gegner hat nur 1 LP.
	"fight_2": {"speaker": "trainer", "steps": [
		{"text": "TUT_F2_INTRO"},
		{"text": "TUT_F2_CONTROLS", "target": "bat_controls"},
		# die Kugel wird auf das eigene Monster am Zug gezogen: beide eigenen Monster sind hell und nehmen sie an
		{"text": "TUT_F2_LOAN", "target": ["bat_orbs", "bat_own_0", "bat_own_1"], "wait": "signal:element_borrowed"},
		{"text": "TUT_F2_PLAY", "target": ["bat_hand", "bat_enemies"], "wait": "signal:call_skill_card", "dismiss": true},
	]},
	# Feld 8: Items im Kampf, dann fällt ein eigenes Monster (eigene 1 LP, FIGHTS[7] faint_wins)
	"fight_8": {"speaker": "trainer", "steps": [
		{"text": "TUT_F8_INTRO"},
		{"text": "TUT_BAT_ITEMS", "target": "bat_items", "if_present": true},
		{"text": "TUT_F8_ITEM", "target": ["bat_items", "bat_enemies"], "wait": "signal:item_used", "if_present": true},
		# alle eigenen Monster beenden ihren Zug, bis der Gegner dran ist und eines erwischt
		{"text": "TUT_F8_END", "target": "bat_end_turn", "wait": "signal:enemy_turn_started"},
	]},
	# Feld 12, Biom-Boss: Boss-Relikte und was Bosse besonders macht. Er hat 1 LP und nur einen nutzlosen Schild.
	"fight_boss": {"speaker": "trainer", "steps": [
		{"text": "TUT_BAT_BOSS"},
		{"text": "TUT_BOSS_RELICS", "target": "bat_relics"},
		{"text": "TUT_BOSS_GO", "target": ["bat_hand", "bat_enemies"], "wait": "signal:call_skill_card", "dismiss": true},
	]},
	"map": {"speaker": "trainer", "steps": [
		{"text": "TUT_MAP_INTRO"},
		{"text": "TUT_MAP_PATH", "target": "map_start"},
		{"text": "TUT_MAP_TEAM", "target": "map_team"},
		{"text": "TUT_MAP_DETAILS", "target": "map_team"},
		{"text": "TUT_MAP_BAG", "target": "map_bag"},
		{"text": "TUT_MAP_LEGEND", "target": "map_legend"},
		# nur zu Beginn eines Runs, wenn die erste Reihe noch frei wählbar ist
		{"text": "TUT_MAP_START", "target": "map_start", "wait": "pressed:map_start", "if_present": true, "dismiss": true},
	]},
	# Gericht nach Feld 1 (Tutorial.judgement_join_only): nur den Fang ins Team ziehen und bestätigen
	"judgement": {"speaker": "trainer", "steps": [
		{"text": "TUT_JUD_CATCHES", "target": "jud_catches"},
		{"text": "TUT_JUD_JOIN", "target": ["jud_catches", "jud_team"], "wait": "signal:judgement_team_joined"},
		{"text": "TUT_JUD_SKILLS", "target": "jud_skills"},
		# im Tutorial ist die Tasche immer zu sehen (judgement.gd), Ablegen geht hier aber nicht
		{"text": "TUT_JUD_BAG", "target": "jud_bag", "if_present": true},
		{"text": "TUT_JUD_CONFIRM", "target": "jud_confirm", "wait": "pressed:jud_confirm"},
	]},
	"loot": {"speaker": "trainer", "steps": [
		{"text": "TUT_LOOT_XP", "target": "loot_team"},
		{"text": "TUT_LOOT_DRAG", "target": "loot_field", "free": true},
	]},
	# Felder 5-7, 10 und 11: es spricht der Trainer, nicht der NPC der Szene (eigene Texte, die NPC-Sätze bleiben für
	# echte Läufe). Laden: Regale, Monster und Tasche
	"shop": {"speaker": "trainer", "steps": [
		{"text": "TUT_SHOP_WELCOME"},
		{"text": "TUT_SHOP_POTIONS", "target": ["shop_shelf_0", "shop_mon_0", "shop_mon_1"]},
		{"text": "TUT_SHOP_ITEMS", "target": ["shop_shelf_1", "shop_bag"]},
		{"text": "TUT_SHOP_GEMS", "target": ["shop_shelf_2", "shop_mon_0", "shop_mon_1"]},
		{"text": "TUT_SHOP_RELICS", "target": ["shop_shelf_3", "shop_bag"]},
		{"text": "TUT_SHOP_CLICK", "target": ["shop_shelf_0", "shop_shelf_1", "shop_shelf_2", "shop_shelf_3", "shop_mon_0", "shop_mon_1"]},
	]},
	"trainer": {"speaker": "trainer", "steps": [
		{"text": "TUT_TRN_CARDS", "target": "trn_cards"},
		{"text": "TUT_TRN_MONS", "target": ["trn_cards", "trn_mons"]},
		{"text": "TUT_TRN_PAY", "target": "trn_bag"},
	]},
	# Kerker: das Tutorial leiht Boss Tränen (jailer.gd), damit man eine Kette sprengen kann
	"jailer": {"speaker": "trainer", "steps": [
		{"text": "TUT_JAIL_CAGES", "target": "jail_cages"},
		{"text": "TUT_JAIL_TEARS", "target": "jail_bag"},
		{"text": "TUT_JAIL_CHAIN", "target": ["jail_bag", "jail_cages"]},
		{"text": "TUT_JAIL_KEY"},
		{"text": "TUT_JAIL_REROLL", "target": "jail_reroll"},
	]},
	"camp": {"speaker": "trainer", "steps": [
		{"text": "TUT_CAMP_TEAM", "target": ["camp_mon_0", "camp_mon_1"]},
		{"text": "TUT_CAMP_FEED", "target": "camp_feed", "free": true},
	]},
	# Erst-Begegnungen ohne NPC: der Trainer erklärt kurz (Glücksrad und Void erklären sich selbst)
	"hub": {"speaker": "trainer", "steps": [{"text": "TUT_HUB", "target": "hub_stations"}]},
	# Feld 4: nur Öffnen (treasure.gd zeigt im Tutorial kein Weiterziehen), dann frei Beute einsammeln
	"treasure": {"speaker": "trainer", "steps": [
		{"text": "TUT_TREASURE", "target": "treasure_open", "wait": "pressed:treasure_open"},
	]},
	# Trank aus der Schatzkiste (potion_reward.gd): was er tut, wofür, und wo es später welche gibt
	"potion": {"speaker": "trainer", "steps": [
		{"text": "TUT_POTION_WHAT", "target": "potion_card"},
		{"text": "TUT_POTION_WHY", "target": "potion_mons"},
		{"text": "TUT_POTION_LATER"},
		{"text": "TUT_POTION_DRAG", "target": ["potion_card", "potion_mons"], "free": true},
	]},
	# Karte nach dem Glücksrad (Feld 3, erster Schlüssel): die Vorräte oben im Header
	"currencies": {"speaker": "trainer", "steps": [
		{"text": "TUT_CUR_INTRO", "target": "map_currencies"},
		{"text": "TUT_CUR_ESSENCE", "target": "map_cur_essence"},
		{"text": "TUT_CUR_TEARS", "target": "map_cur_tears"},
		{"text": "TUT_CUR_KEYS", "target": "map_cur_keys"},
		{"text": "TUT_CUR_COUPONS", "target": "map_cur_coupons"},
	]},
	"gems": {"speaker": "trainer", "steps": [{"text": "TUT_GEMS"}]},
	"relic_reward": {"speaker": "trainer", "steps": [{"text": "TUT_RELIC_REWARD"}]},
	"skill_reward": {"speaker": "trainer", "steps": [{"text": "TUT_SKILL_REWARD"}]},
	# Feld 3: Glücksrad "Ewiges Pech" (wheel_event.gd), landet sicher auf dem grünen Fleck: ein Schlüssel
	"wheel": {"speaker": "trainer", "steps": [
		{"text": "TUT_WHEEL"},
		{"text": "TUT_WHEEL_SPIN", "target": "wheel_spin", "wait": "pressed:wheel_spin", "dismiss": true},
	]},
	# nach dem Schatz (Feld 4, world_map.gd _tutorial_inventory): Inventar, Köder an ein Monster
	"inventory": {"speaker": "trainer", "steps": [
		{"text": "TUT_INV_INTRO", "target": "inv_bag"},
		{"text": "TUT_INV_EQUIP", "target": ["inv_bag", "inv_team"], "wait": "signal:item_equipped"},
		{"text": "TUT_INV_DONE", "target": "map_bag"},
	]},
	# Letzter Wille nach Feld 8 (last_will_screen.gd): erst der Nachlass, dann die Wiederbelebung mit dem neuen Fang
	"last_will": {"speaker": "trainer", "steps": [
		{"text": "TUT_WILL_INTRO", "target": "will_soul"},
		{"text": "TUT_WILL_PILES", "target": "will_piles", "open": true},
		{"text": "TUT_WILL_REVIVE", "target": ["will_catch", "will_soul"], "wait": "signal:last_will_revived", "open": true},
	]},
	# Beute nach dem Biom-Boss (level_up.gd): Reliktkiste, Couvert und Ei. Kiste und Couvert gehen in jedem Fall auf.
	"boss_loot": {"speaker": "trainer", "steps": [
		{"text": "TUT_BOSS_LOOT", "target": "loot_chest", "if_present": true},
		{"text": "TUT_BOSS_ENVELOPE", "target": "loot_envelope", "if_present": true},
		{"text": "TUT_BOSS_EGG", "target": "loot_egg", "if_present": true},
		{"text": "TUT_BOSS_TAKE", "target": "loot_field", "free": true},
	]},
	# Ende des Tutorial-Laufs (finish): danach geht es zurück zur Ei-Auswahl mit dem echten Spielstand
	"finish": {"speaker": "trainer", "steps": [{"text": "TUT_END"}, {"text": "TUT_END_BACK"}]},
}

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
	_overlay_id = id
	return true

## Id der laufenden Sequenz (für stop)
var _overlay_id := ""

## Beendet die Sequenz id, falls sie läuft, als gesehen: für Dialoge auf der Karte, die schließen, bevor man Weiter
## drückt (z. B. Trank vergeben). Sonst bliebe die Blase stehen und blockierte die nächste Sequenz.
func stop(id: String) -> void:
	if is_running() and _overlay_id == id:
		_mark_seen(id)
		_overlay.queue_free()

func should_show(id: String) -> bool:
	return SEQUENCES.has(id) and run_active and not SaveManager.save_data["tutorial_seen"].has(id)

func is_running() -> bool:
	return is_instance_valid(_overlay) and not _overlay.is_queued_for_deletion()

## Darf der Spieler gerade mit dem Ziel "tut_<group>" handeln? Ohne laufende Sequenz immer, sonst nur, wenn der
## aktuelle Schritt es als Ziel hat und eine Aktion erwartet (z. B. Karten im Kampf erst beim Ausspiel-Schritt)
func allows(group: String) -> bool:
	return not is_running() or _overlay.step_allows(group)

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
	# keine echten Boss Tränen im Tutorial, für den Kerkermeister gibt es eine geliehene
	SaveManager.save_data["boss_shards"] = 0
	State.reset()
	State.boss_shards = 0
	SceneLoader.change_scene(SELECTION_SCENE)

## Ende oder Überspringen: Spielstand von vorher zurück, Speichern wieder an, zurück zur Ei-Auswahl
func end_run() -> void:
	if not run_active:
		return
	run_active = false
	fight = {}
	if is_running():
		_overlay.queue_free()
	SaveManager.save_data = _save_backup
	_save_backup = {}
	SaveManager.suspended = false
	SaveManager.save_game()
	State.reset()
	State.boss_shards = SaveManager.save_data["boss_shards"]
	SceneLoader.change_scene(SELECTION_SCENE)

## Letztes Feld geschafft (Biom-Boss, world_map.gd _finish_biome): Abschiedsworte, dann end_run
func finish() -> void:
	if not trigger("finish", end_run):
		end_run()

## "Tutorial überspringen" in der Sprechblase: mit Rückfrage, die Sequenz bleibt solange stehen
func ask_skip() -> void:
	if not run_active or not is_running():
		return
	var dialog := ChoiceDialog.ask(_overlay.dialog_host(), tr("TUTORIAL_SKIP_TITLE"), tr("TUTORIAL_SKIP_TEXT"),
		tr("TUTORIAL_SKIP_YES"), tr("TUTORIAL_SKIP_NO"))
	if await dialog.chosen:
		end_run()

# ─────────────────────────
# Ei-Auswahl im Tutorial

## Art, die der Trainer als Starter empfiehlt (stark gegen das erste Biom), Platzhalter {mon} in den Texten
var recommended_starter := ""

## Mindestens ein Starter muss gegen das erste Biom stark sein (Element-Vorteil, Skills.element_score).
## may_replace: fehlt einer, ersetzt ein passendes Start-Monster (State.INITIAL_MONS) das letzte Ei.
## Merkt sich den stärksten als Empfehlung.
func prepare_starters(mons: Array, may_replace: bool) -> Array:
	var biome: int = Map.load_biome_path()[0]
	var score := func(mon_name: String) -> int:
		return Skills.element_score(Monmap.mon_metainfos_by_name(mon_name).initial_type, biome)
	var names: Array = mons.map(func(mon: Monster): return mon._name)
	if may_replace and not names.any(func(mon_name): return score.call(mon_name) > 0):
		# nur Start-Monster, keine gefangenen oder fremden Arten
		var candidates: Array = State.INITIAL_MONS.filter(
			func(mon_name): return score.call(mon_name) > 0 and not names.has(mon_name))
		if not candidates.is_empty():
			mons[mons.size() - 1] = Helper.initial_mon(candidates.pick_random())
			names = mons.map(func(mon: Monster): return mon._name)
	recommended_starter = ""
	var best := 0
	for mon_name in names:
		if score.call(mon_name) > best:
			best = score.call(mon_name)
			recommended_starter = mon_name
	return mons

## Platzhalter der Tutorial-Texte: {mon} empfohlener Starter, {biome} erstes Biom
func text_values() -> Dictionary:
	var values := {"mon": "", "biome": ""}
	if recommended_starter != "":
		values.mon = Helper.mon_display_name(recommended_starter)
	if not State.biome_path.is_empty():
		values.biome = tr(ColorMap.get_combo(State.biome_path[0]).label)
	return values

# ─────────────────────────
# Tutorial-Kämpfe: Feld der Tutorial-Karte (Zeile, Map.TUTORIAL_ROWS) bzw. "boss" -> Aufbau des Kampfs.
# battle.gd baut den Kampf wie sonst und passt ihn danach an (_setup_tutorial_fight).
#  sequence      Sequenz, die zu Kampfbeginn startet
#  enemy_weak    ein Gegner mit dem Grundelement, gegen das der Starter stark ist
#  enemy_hp      Gegner haben nur so viele LP
#  own_hp        eigene Monster haben nur so viele LP
#  enemy_moves   Aktionen der Gegner pro Zug
#  enemy_attack  Gegner können nur einen leichten Angriff ihres Elements
#  enemy_useless Gegner können nur einen nutzlosen Schild ihres Elements
#  attacks       eigene Monster haben in diesem Kampf nur Angriffe: vorn je einen physischen und magischen ihres
#                Elements, dazu ihre eigenen Angriffe (keine Schilde oder Buffs, die eigenen Skills kommen danach zurück)
#  no_ko         niemand geht K.O., jeder behält mindestens 1 LP
#  catch_sure    der Fang klappt sicher
#  faint_wins    fällt ein eigenes Monster, endet der Kampf mit Sieg und alle Gegner sind gefangen
#  no_catch      keine Hypnose (sonst ginge der Gegner vor dem lehrreichen K.O. ins Netz)
# Alle Tutorial-Kämpfe haben genau einen Gegner, und die eigenen Monster sind in der ersten Runde zuerst dran (TurnWheel).
const FIGHTS := {
	0: {"sequence": "battle", "enemy_weak": true, "enemy_moves": 1, "attacks": true, "no_ko": true, "catch_sure": true},
	1: {"sequence": "fight_2", "enemy_hp": 1, "enemy_moves": 1, "attacks": true},
	7: {"sequence": "fight_8", "own_hp": 1, "enemy_moves": 1, "enemy_attack": true, "faint_wins": true, "no_catch": true},
	"boss": {"sequence": "fight_boss", "enemy_hp": 1, "enemy_moves": 1, "enemy_useless": true, "attacks": true},
}
## Grundelement -> Namensteil der Starter-Skills (Skills.starter_skills: *_LIGHT_THRUST, *_ARMOR_WEAK)
const ELEMENT_KEYS := {
	Enums.MON_TYPES.EARTH: "EARTH",
	Enums.MON_TYPES.FIRE: "FIRE",
	Enums.MON_TYPES.WATER: "WATER",
	Enums.MON_TYPES.AIR: "AIR",
}

## Aufbau des laufenden Tutorial-Kampfs, leer außerhalb (battle.gd setzt ihn beim Betreten, löscht ihn beim Verlassen)
var fight := {}

## battle.gd _enter_tree: welcher Tutorial-Kampf jetzt dran ist (leer = normaler Kampf)
func fight_for_battle() -> Dictionary:
	fight = {}
	if not run_active:
		return fight
	var key = "boss" if State.is_boss_fight else int(State.current_map_position.y)
	fight = FIGHTS.get(key, {})
	return fight

func is_fight() -> bool:
	return not fight.is_empty()

## Tutorial-Kampf mit "no_ko": niemand geht K.O., jeder behält mindestens 1 LP
func cap_damage(mon: Monster, damage: float) -> float:
	if not fight.get("no_ko", false):
		return damage
	return minf(damage, maxf(mon.hp() - mon._lost_hp - 1.0, 0.0))

## Tutorial-Kampf mit "catch_sure": der Fang klappt sicher
func catches_for_sure(mon: Monster) -> bool:
	return fight.get("catch_sure", false) and State.enemy_mons.has(mon)

## Art für "enemy_weak": Grundelement, gegen das der Starter stark ist, möglichst gewöhnlich, zuerst aus dem Biom-Pool
func weak_enemy_species() -> String:
	var target := 0
	for element in Skills.STRONG_AGAINST:
		if State.starter and State.starter._type & element:
			target = Skills.STRONG_AGAINST[element]
			break
	var pool: Array = Monmap.mons.filter(func(meta): return not meta.has("bounty_target")).map(func(meta): return meta.name)
	var matching := pool.filter(func(mon_name): return Monmap.mon_metainfos_by_name(mon_name).initial_type == target)
	if State.map_level < State.biome_pools.size():
		var in_biome := matching.filter(func(mon_name): return State.biome_pools[State.map_level].has(mon_name))
		if not in_biome.is_empty():
			matching = in_biome
	if matching.is_empty():
		matching = pool
	var lowest: int = matching.map(Monmap.rarity_of).min()
	return matching.filter(func(mon_name): return Monmap.rarity_of(mon_name) == lowest).pick_random()

## Gericht nach dem ersten Tutorial-Kampf (Feld 1): nur den Fang auf den freien Platz ziehen und bestätigen
func judgement_join_only() -> bool:
	return run_active and int(State.current_map_position.y) == 0

## Skill eines Grundelements des Monsters nach Vorlage ("SKILL_%s_PHYS_LIGHT_THRUST"), leer wenn es keinen gibt
func element_skill(mon: Monster, pattern: String) -> Dictionary:
	for element: int in ELEMENT_KEYS:
		if mon._type & element:
			var skill := Skills.get_skill(pattern % ELEMENT_KEYS[element])
			if not skill.is_empty():
				skill.scouted = true
				return skill
	return {}

func _mark_seen(id: String) -> void:
	var seen: Array = SaveManager.save_data["tutorial_seen"]
	if not seen.has(id):
		seen.append(id)
