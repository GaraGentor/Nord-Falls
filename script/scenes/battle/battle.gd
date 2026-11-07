extends Control

const ENEMY_THINK_TIME := 0.6
const ENEMY_ACTION_TIME := 0.9
## Chancen auf Zufallsbeute pro besiegtem Monster, gefangene Monster würfeln nicht. Jede Beute wird einzeln gewürfelt.
const KEY_LOOT_CHANCE := 0.15
const GEM_LOOT_CHANCE := 0.10
const GOLD_LOOT_CHANCE := 0.15
const COUPON_LOOT_CHANCE := 0.05
## Essenz als Zufallsbeute: Grundbetrag plus Zuschlag pro Biom-Tiefe
const GOLD_LOOT_MIN := 5
const GOLD_LOOT_MAX := 15
const GOLD_LOOT_PER_DEPTH := 5
## Boss Tränen als Beute: Biom-Boss und finaler Boss, Boss-Felder auf der Karte lassen keine fallen
const BIOME_BOSS_SHARDS := 1
const FINAL_BOSS_SHARDS := 3
const NOISE_SHADER := preload("res://script/scenes/world_map/map_noise.gdshader")

@export var catch_anim: Control
@export var catch_button: Button
@export var battle_info: Control
@export var card_hand: ScrollContainer

@onready var turn_wheel: Control = battle_info.turn_wheel

var is_playing: bool = true

## auf dem Feld markiertes Monster (eigenes oder gegnerisches), wird im Infobereich angezeigt
var selected_mon: Monster
## zuletzt markierter Gegner: Ziel für Hypnose und Karten ohne eigenes Ziel
var currently_selected_enemy_mon: Monster

var mouse_action = Enums.MOUSE_ACTION.NONE

## Monster, das laut Turn Wheel gerade am Zug ist
var active_mon: Monster

## Boss-Feld oder Biom-Boss: ein Sieg bringt eine Relic-Auswahl
var is_boss_battle: bool = false

func _enter_tree() -> void:
	_generate_battle()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_add_ambient()
	Events.mouse_event.connect(_catch_mouse_event)
	Events.monster_faints.connect(_check_game_over)
	Events.finish_catching.connect(_finish_catching)

	# Schilde, Buffs und Abklingzeiten gelten nur für einen Kampf
	for mon in State.mons + State.enemy_mons:
		mon.reset_battle_state()
	if Relics.works("all_skills"):
		for emon in State.enemy_mons:
			emon.unlock_skills()
	# Gegner zeigen ihren ersten Zug schon vor Kampfbeginn
	for emon in State.enemy_mons:
		_plan_intent(emon)
	Events.intents_changed.emit()
	_refresh_skill_points()
	Events.mouse_event.emit({"action": Enums.MOUSE_ACTION.SELECT_MONSTER, "mon": State.enemy_mons[0]})

	if State.mons.size() > 1:
		$GameWindow/HBoxContainer2/MonsterScene1.visible = true

	if State.is_final_boss:
		$UI/HBoxContainer/TextureRect/Catch.visible = false

	# unsichtbar, blockiert aber Eingaben während der Gegner am Zug ist
	$UI_Blocker.self_modulate = Color(1, 1, 1, 0)
	turn_wheel.turn_for.connect(_on_turn_for)
	card_hand.show_mon(State.mons[0])
	turn_wheel.start()

## Im schwarzen Infobereich zieht das Wetter des aktuellen Bioms durch, im selben Pixel-Look wie auf der Karte
func _add_ambient() -> void:
	var ui_background: Control = $UI/ColorRect
	var weather := MapWeather.new()
	ui_background.add_sibling(weather)
	weather.apply_look(MapBiomeTheme.get_look(State.current_biome()))
	var noise_material := ShaderMaterial.new()
	noise_material.shader = NOISE_SHADER
	var noise := ColorRect.new()
	noise.material = noise_material
	noise.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weather.add_sibling(noise)
	noise.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _is_own_turn() -> bool:
	return active_mon != null and State.mons.has(active_mon)

func _on_turn_for(mon: Monster) -> void:
	active_mon = mon
	mon.start_turn()
	var own_index = State.mons.find(mon)
	if own_index > -1:
		# Skillpunkte zu Beginn des eigenen Zuges auffüllen
		mon.reset_to_new_round()
		# wer am Zug ist, zeigt das Turn Wheel; die Hand zeigt seine Karten
		card_hand.show_mon(mon)
		catch_button.disabled = false
		$UI_Blocker.visible = false
		return
	$UI_Blocker.visible = true
	await get_tree().create_timer(ENEMY_THINK_TIME).timeout
	if not is_inside_tree():
		return
	# der angekündigte Zug wird Aktion für Aktion ausgeführt, die Anzeige schrumpft mit
	while not mon._intent.is_empty() and mon.is_alive() and not _opponents_of(mon).is_empty():
		_ki_action(mon, mon._intent.pop_front())
		Events.intents_changed.emit()
		# eingesetzte Skills sind jetzt aufgedeckt
		if selected_mon == mon:
			battle_info.refresh()
		await get_tree().create_timer(ENEMY_ACTION_TIME).timeout
		if not is_inside_tree():
			return
	_plan_intent(mon)
	Events.intents_changed.emit()
	turn_wheel.next_mon()

func _monster_scenes() -> Array:
	return [$GameWindow/HBoxContainer2.get_node("MonsterScene" + str(0)),
		$GameWindow/HBoxContainer2.get_node("MonsterScene" + str(1)),
		$GameWindow/HBoxContainer3.get_node("MonsterScene" + str(0)),
		$GameWindow/HBoxContainer3.get_node("MonsterScene" + str(1)),
		$GameWindow/HBoxContainer3.get_node("MonsterScene" + str(2))]

func _scene_for(mon: Monster) -> Control:
	return _monster_scenes().filter(func(e): return e.mon == mon)[0]

## markiert genau ein Monster auf dem ganzen Feld und zeigt es im Infobereich
func _select_mon(mon: Monster) -> void:
	selected_mon = mon
	if State.enemy_mons.has(mon):
		currently_selected_enemy_mon = mon
	for scene in _monster_scenes():
		scene.texture_rect.material = Monmap.living_selected_material if scene.mon == mon and mon != null else Monmap.LIVING_MATERIAL
	battle_info.monster = mon

## nach einem K.O. oder Fang ein noch kämpfendes Monster markieren
func _reselect_if_gone(gone: Monster) -> void:
	if selected_mon != gone and currently_selected_enemy_mon != gone:
		return
	var alive_enemies = State.enemy_mons.filter(func(mon: Monster): return mon.is_alive() and mon != gone)
	if currently_selected_enemy_mon == gone:
		currently_selected_enemy_mon = alive_enemies[0] if not alive_enemies.is_empty() else null
	if selected_mon != gone:
		return
	var alive = alive_enemies + State.mons.filter(func(mon: Monster): return mon.is_alive())
	if not alive.is_empty():
		_select_mon(alive[0])

func _exit_tree() -> void:
	Events.mouse_event.disconnect(_catch_mouse_event)
	Events.monster_faints.disconnect(_check_game_over)
	Events.finish_catching.disconnect(_finish_catching)
	# Buffs sollen nach dem Kampf nicht in den Werten auf der Karte stehen bleiben
	for mon in State.mons:
		mon.reset_battle_state()
	# keine Absichten außerhalb des Kampfes (z. B. als "Eingehend" im Lager)
	for emon in State.enemy_mons:
		emon._intent = []

func _catch_mouse_event(event) -> void:
	if event.action == Enums.MOUSE_ACTION.SELECT_MONSTER and event.mon != null:
		_select_mon(event.mon)
	if event.action == Enums.MOUSE_ACTION.PLAY_CARD:
		# nur das Monster, das am Zug ist, darf Skills spielen
		if not _is_own_turn():
			return
		# per Drag & Drop gespielte Karten bringen ihr Ziel mit
		var target: Monster = event.get("mon", _default_target(event.skill))
		if not Skills.is_playable(active_mon, event.skill) or not _is_valid_target(active_mon, event.skill, target):
			return
		var isOk = subract_skill_points(event.skill, active_mon)
		print("deal damage" + str(isOk))
		if isOk:
			catch_button.disabled = true
			_use_skill(active_mon, event.skill, target)
			Events.call_skill_card.emit(event.skill)
			mouse_action = Enums.MOUSE_ACTION.NONE
	mouse_action = event.action

## lebende Monster auf der Seite von mon (inklusive mon selbst)
func _allies_of(mon: Monster) -> Array:
	return (State.mons if State.mons.has(mon) else State.enemy_mons).filter(func(m: Monster): return m.is_alive())

## lebende Monster auf der Gegenseite von mon
func _opponents_of(mon: Monster) -> Array:
	return (State.enemy_mons if State.mons.has(mon) else State.mons).filter(func(m: Monster): return m.is_alive())

## Ziel für Karten, die ohne Drag & Drop gespielt werden: Schilde und Buffs auf das markierte eigene Monster
## (sonst auf sich selbst), Angriffe auf den zuletzt markierten Gegner.
func _default_target(skill: Dictionary) -> Monster:
	if Skills.targets_friends(skill):
		return selected_mon if _allies_of(active_mon).has(selected_mon) else active_mon
	return currently_selected_enemy_mon

## Schilde und Buffs nur auf eigene Monster, Angriffe nur auf Gegner
func _is_valid_target(from: Monster, skill: Dictionary, target: Monster) -> bool:
	if target == null:
		return false
	var side = _allies_of(from) if Skills.targets_friends(skill) else _opponents_of(from)
	return side.has(target)

## Setzt einen Skill ein: Flächen-Skills treffen die ganze Seite des Ziels, danach startet die Abklingzeit.
func _use_skill(from: Monster, skill: Dictionary, target: Monster) -> void:
	var targets = [target]
	if Skills.targets_team(skill):
		targets = _allies_of(target)
	for mon in targets:
		# Angriffsanimation nur gegen Gegner
		if not Skills.targets_friends(skill):
			Events.monster_hit_monster.emit(_scene_for(from), _scene_for(mon))
		skill.handle.call({"from": from, "skill": skill, "mon": mon})
	Skills.start_cooldown(skill)
	Events.monster_status_changed.emit(from)
	# Treffer decken Werte auf (Skills.reveal_stats_by_hit)
	if selected_mon == from or targets.has(selected_mon):
		battle_info.refresh()

func subract_skill_points(selected_skill, mon) -> bool:
	if mon._computed_moves >= selected_skill.cost:
		mon._computed_moves -= selected_skill.cost
		return true
	return false

func _refresh_skill_points() -> void:
	for mon in State.mons:
		if mon.is_alive():
			mon.reset_to_new_round()

## Monster und Anzahl stehen seit dem Betreten des Bioms fest (Map.generate_encounters).
## Erst hier kommt dazu, was vom Fortschritt im Biom abhängt: Stufe und Aktionen.
func _generate_battle():
	var depth = Map.encounter_depth()
	var encounter: Dictionary = Map.ENCOUNTERS[depth]
	var fight_index: int = State.biome_fight_index
	var level: int
	var min_moves: int = 1
	is_boss_battle = State.is_boss_fight or State.is_map_boss
	var t = Map.fight_progress(fight_index)
	if State.is_boss_fight:
		var boss: Dictionary = Map.BOSS_ENCOUNTERS[depth]
		level = encounter.level[1] + boss.level_bonus
		min_moves = boss.min_moves
		t = 1.0
	elif State.is_map_boss:
		# Boss-Feld auf der Karte: Boss-Anzahl, aber auf der aktuellen Stufe des Bioms
		var boss: Dictionary = Map.BOSS_ENCOUNTERS[depth]
		level = roundi(lerpf(encounter.level[0], encounter.level[1], t)) + boss.level_bonus
		min_moves = boss.min_moves
		State.is_map_boss = false
	else:
		level = roundi(lerpf(encounter.level[0], encounter.level[1], t))
		State.biome_fight_index += 1
	var ms := _take_enemies(fight_index)
	# nie unter der Startstufe des eigenen Teams
	for mon in ms:
		mon._is_boss = is_boss_battle
		mon._level = maxi(State.INITIAL_LEVEL, level + randi_range(encounter.offset[0], encounter.offset[1]))
		if mon._bounty != "":
			mon._level += Skills.get_bounty(mon._bounty).level_bonus
		mon._initial_moves = maxi(Map.roll_weighted(encounter.moves, t), min_moves)
		State.record_sighting(mon, depth)
	print("encounter depth ", depth, " fight ", State.biome_fight_index, ": ", ms.size(), "x level ", level)
	State.enemy_mons = ms

## Die Gegner des betretenen Felds. Kämpfe aus dem Debug-Menü kommen ohne Feld oder mit fester Anzahl und würfeln hier.
func _take_enemies(fight_index: int) -> Array[Monster]:
	var planned: Array[Monster] = Map.pending_enemies
	Map.pending_enemies = []
	var forced_count: int = DebugSettings.take_enemy_count(0)
	if not planned.is_empty() and forced_count == 0:
		return planned
	return Map.roll_boss_enemies(forced_count) if is_boss_battle else Map.roll_fight_enemies(fight_index, forced_count)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func round_won():
	upgrade_mons()

func upgrade_mons():
	pass

func _check_game_over(last_fainted:Monster) -> void:
	turn_wheel.remove_mon(last_fainted)
	_reselect_if_gone(last_fainted)
	_retarget_intents()
	var is_enemy = true if State.enemy_mons.find(last_fainted) > -1 else false
	print("check gameover", State.mons.all(
			func(mon: Monster):
			return not mon.is_alive()
			))
	print("who ded?", str(is_enemy), State.enemy_mons.size(), ":", last_fainted._name)
	if is_enemy:
		State.killed_monsters += 1
		State.run_kills += 1
		State.mark_mon_defeated(last_fainted._name)
		_roll_kill_loot()
		var bounty_skill = Skills.claim_bounty(last_fainted)
		if bounty_skill != "":
			Helper.show_unlock_message(tr("BOUNTY_UNLOCKED").format({"skill": tr(bounty_skill), "mon": Helper.mon_display_name(last_fainted._last_hit_by._name)}))
		print("State.mons.all(func(mon: Monster): return mon._hp <= 0 and not mon._new)",
		State.mons.all(
			func(mon: Monster):
			return not mon.is_alive()
			)
	)
	if State.mons.all(
			func(mon: Monster):
			return not mon.is_alive()
			):
		State.end_run(false)
		_clear_fainted_mons()
		get_tree().change_scene_to_file("res://script/scenes/run_end/run_end.tscn")
		return
	if State.enemy_mons.all(func(mon: Monster): return not mon.is_alive()) or State.enemy_mons.size() == 0:
		print("will close battle")
		State.stage_clear()
		_add_boss_loot()
		# besiegte Gegner bleiben in enemy_mons, gefangene nicht: nur Kills bringen Essenz
		State.pending_ep += Relics.modify("battle_ep", State.enemy_mons.map(func(mon): return mon._ep).reduce(func(a, b): return a + b, 0))
		print("state pending ep", State.pending_ep)
		# clear dead monsters.
		# open stats.
		var fallen = _clear_fainted_mons()
		# nach dem finalen Boss kommt kein Kampf mehr, Wiederbelebung und Letzter Wille brächten nichts
		if not State.is_final_boss:
			State.fainted_own_mons.append_array(fallen)
		if State.catched_mons.size() > 0 or not State.fainted_own_mons.is_empty():
			get_tree().change_scene_to_file("res://script/scenes/judgment/judgement.tscn")
			return
		get_tree().change_scene_to_file("res://script/scenes/world_map/world_map.tscn")

## Zufallsbeute für ein besiegtes Monster. Der finale Boss beendet den Run, danach bringt Beute nichts mehr.
func _roll_kill_loot() -> void:
	if State.is_final_boss:
		return
	if randf() < Relics.modify("key_chance", KEY_LOOT_CHANCE):
		State.pending_keys += 1
	if randf() < GEM_LOOT_CHANCE:
		State.pending_gems += 1
	if randf() < COUPON_LOOT_CHANCE:
		State.pending_coupons += 1
	if randf() < GOLD_LOOT_CHANCE:
		State.pending_ep += randi_range(GOLD_LOOT_MIN, GOLD_LOOT_MAX) + State.map_level * GOLD_LOOT_PER_DEPTH

## Mini-Boss und Biom-Boss lassen bei jedem Sieg Kiste und Couvert fallen, auch wenn sie gefangen wurden.
## Biom-Bosse lassen zusätzlich Boss Tränen fallen, der finale Boss nur diese. Das Ei lost der Level-Up-Bildschirm.
func _add_boss_loot() -> void:
	if State.is_boss_fight:
		State.pending_boss_shards = FINAL_BOSS_SHARDS if State.is_final_boss else BIOME_BOSS_SHARDS
	if not is_boss_battle or State.is_final_boss:
		return
	State.pending_relic_chest = not Relics.get_unowned().is_empty()
	State.pending_skill_envelope = not Skills.reward_offers().is_empty()

func _clear_fainted_mons() -> Array:
	var v = State.mons.filter(func(mon:Monster): return not mon.is_alive())
	for item: Monster in v:
		State.mons.erase(item)
	return v

## Plant den nächsten Zug eines Gegners (Monster._intent): zufällige Skills, bis seine Aktionen aufgebraucht sind,
## jeweils auf ein zufälliges lebendes Ziel (Angriffe auf eigene Monster, Schilde und Buffs auf sich selbst oder einen Verbündeten).
## Gegner halten sich an dieselben Regeln wie der Spieler (Element, Kosten, Abklingzeit, Passive nicht ausspielbar).
## Nur Angriffe ohne Abklingzeit dürfen mehrfach im selben Zug vorkommen.
## Geplant wird vor dem Zug: Abklingzeiten zählen zu dessen Beginn noch einmal herunter, daher reicht <= 1.
## Kerkermeister-Verbesserungen und Relics gelten nur für eigene Monster, Gegner haben _initial_moves (gewürfelt in _generate_battle).
func _plan_intent(emon: Monster) -> void:
	emon._intent = []
	if not emon.is_alive() or _opponents_of(emon).is_empty():
		return
	var moves: int = emon._initial_moves
	var once_used = []
	while true:
		var options = emon._skills.filter(func(skill): return _can_plan(emon, skill, moves) and not once_used.has(skill))
		if options.is_empty():
			return
		var picked: Dictionary = options.pick_random()
		moves -= maxi(picked.cost, 1)
		if picked.get("cooldown", 0) > 0 or not Skills.is_damage_skill(picked):
			once_used.append(picked)
		emon._intent.append({"skill": picked, "target": _pick_target(emon, picked)})

func _can_plan(emon: Monster, skill: Dictionary, moves_left: int) -> bool:
	return Skills.can_use(emon, skill) and not Skills.is_passive(skill) \
		and Skills.cooldown_left(skill) <= 1 and maxi(skill.cost, 1) <= moves_left

func _pick_target(emon: Monster, skill: Dictionary) -> Monster:
	var side = _allies_of(emon) if Skills.targets_friends(skill) else _opponents_of(emon)
	return side.pick_random() if not side.is_empty() else null

## Ziele, die inzwischen K.O. oder gefangen sind, werden durch ein anderes lebendes Ziel ersetzt.
func _retarget_intents() -> void:
	for emon in State.enemy_mons:
		for action in emon._intent:
			if not _is_valid_target(emon, action.skill, action.target):
				action.target = _pick_target(emon, action.skill)
	Events.intents_changed.emit()

## Eine geplante Aktion eines Gegners ausführen (fällt weg, wenn es kein gültiges Ziel mehr gibt).
func _ki_action(emon: Monster, action: Dictionary) -> void:
	var skill: Dictionary = action.skill
	if not Skills.is_playable(emon, skill):
		return
	var target: Monster = action.target
	if not _is_valid_target(emon, skill, target):
		target = _pick_target(emon, skill)
		if target == null:
			return
	_use_skill(emon, skill, target)
	skill.scouted = true

func _on_end_turn_pressed() -> void:
	if not _is_own_turn():
		return
	$UI_Blocker.visible = true
	Events.mouse_event.emit({"action": Enums.MOUSE_ACTION.NONE})
	turn_wheel.next_mon()

func _finish_catching(catched: bool, mon: Monster) -> void:
	if catched:
		State.mark_mon_defeated(mon._name)
		var index = State.enemy_mons.find(mon)
		if index > -1:
			State.enemy_mons.remove_at(index)
		# catch_anim hat das Monster bereits aus enemy_mons entfernt, daher immer prüfen
		_check_game_over(mon)
		if not is_inside_tree():
			return
	_on_end_turn_pressed()

func _on_catch_pressed() -> void:
	# Events.mouse_event.emit({"action": Enums.MOUSE_ACTION.CATCH_MONSTER})
	print(currently_selected_enemy_mon)
	print(State.enemy_mons)
	var already_catched = State.catched_mons.find(currently_selected_enemy_mon)
	if currently_selected_enemy_mon and currently_selected_enemy_mon.is_alive() and already_catched == -1:
		catch_anim._catch_animation(currently_selected_enemy_mon)
