extends Control

const ENEMY_THINK_TIME := 0.6
const ENEMY_ACTION_TIME := 0.9
## Pause nach Gift/Verbrennung, länger als die KP-Animation: ein K.O. ist dann schon verarbeitet (turn_wheel.remove_mon)
const STATUS_TICK_TIME := BattleMonCard.HP_TWEEN_TIME + 0.3
## so lange steht "Betäubt!" über einem gelähmten Monster, bevor sein Zug endet
const STUNNED_TIME := 0.9
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
const BossRelicOverlayScript := preload("res://script/scenes/battle/boss_relic_overlay.gd")

# ─────────────────────────
# Gegner-KI (siehe ki_plan.txt): jede Kombination aus Skill und Ziel bekommt einen Score, gewürfelt wird mit
# Gewicht score ^ Schärfe. Schärfe 0 = reiner Zufall, je höher, desto öfter der beste Zug.
## Schärfe in Biom 1, Zuschlag pro Biom-Tiefe und für Bosse
const AI_SHARPNESS_BASE := 0.5
const AI_SHARPNESS_PER_DEPTH := 0.5
const AI_SHARPNESS_BOSS := 1.0
## Score x so viel, wenn der Angriff das Ziel (zusammen mit den schon geplanten Angriffen) besiegt
const AI_KILL_BONUS := 2.0
## Anteil des Schadens, der über die Rest-KP hinausgeht oder ein schon verplantes Ziel trifft
const AI_OVERKILL_SHARE := 0.15
## wie stark Ziele mit hohem (Sp.) Angriff bevorzugt werden (0 = gar nicht)
const AI_THREAT_WEIGHT := 0.3
## Schild- und Buff-Skills: Grundwert = Schildmenge bzw. Wertzuwachs x Züge x dieses Gewicht (Ausbau in Schritt 6)
const AI_DEFENSE_WEIGHT := 0.5
## jeder Zug bleibt möglich
const AI_MIN_SCORE := 0.1

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

## Vorstellung und Zerbrechen der Boss-Relikte, liegt über allem
var _relic_overlay: BossRelicOverlayScript
## Boss-Relikte des Kampfs am Rand des Kampffelds
var _relic_bar: BossRelicBar
## Szenenwechsel ist schon unterwegs: spätere K.O.-Meldungen ändern nichts mehr
var _battle_over := false
## Boss-Relikte, die gerade zerbrechen oder darauf warten
var _pending_breaks := 0

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
	battle_info.build_mon_cards()
	Events.mouse_event.emit({"action": Enums.MOUSE_ACTION.SELECT_MONSTER, "mon": State.enemy_mons[0]})

	if State.mons.size() > 1:
		$GameWindow/HBoxContainer2/MonsterScene1.visible = true

	if State.is_final_boss:
		$UI/HBoxContainer/TextureRect/Catch.visible = false

	# unsichtbar, blockiert aber Eingaben während der Gegner am Zug ist
	$UI_Blocker.self_modulate = Color(1, 1, 1, 0)
	card_hand.show_mon(State.mons[0])
	_relic_bar = BossRelicBar.new()
	$GameWindow.add_child(_relic_bar)
	_relic_bar.pressed.connect(func(): _relic_overlay.play_intro(BossRelics.active, false))
	_relic_overlay = BossRelicOverlayScript.new()
	add_child(_relic_overlay)
	# Boss-Relikte stellen sich vor, bevor die erste Runde beginnt
	if not BossRelics.active.is_empty():
		await _relic_overlay.play_intro(BossRelics.active)
		if not is_inside_tree():
			return
	turn_wheel.round_started.connect(_on_round_started)
	turn_wheel.turn_for.connect(_on_turn_for)
	turn_wheel.start()

func _on_round_started(_round_number: int) -> void:
	BossRelics.on_round_started()

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
	$UI_Blocker.visible = true
	# ein zerbrechendes Boss-Relikt hält den Kampf an
	await _relic_overlay.wait_idle()
	if not is_inside_tree():
		return
	# Gift wirkt vor dem Zug, solange die Rüstung aus dem letzten Zug noch steht (start_turn lässt Schilde ablaufen)
	if ElementEffects.tick_poison(mon):
		await get_tree().create_timer(STATUS_TICK_TIME).timeout
		if not is_inside_tree():
			return
	mon.start_turn()
	# am Gift gestorben: das Rad hat das Monster schon entfernt, weiter zum nächsten
	if not mon.is_alive():
		turn_wheel.next_mon()
		return
	# Boss-Relikte zu Zugbeginn (Bongos, Fate-Spiegel), nach dem Ablaufen der alten Schilde
	BossRelics.on_turn_start(mon, turn_wheel.round_number)
	# Mikrofon: in ungeraden Runden fällt jeder Zug aus, dafür heilt sich das Monster etwas.
	# Gegner behalten ihren angekündigten Zug für die nächste Runde.
	if BossRelics.silences_round(turn_wheel.round_number):
		BossRelics.microphone_turn(mon)
		await get_tree().create_timer(STUNNED_TIME).timeout
		if not is_inside_tree():
			return
		_end_turn(mon)
		return
	# Paralyse: betäubt, der Zug endet sofort
	if ElementEffects.rolls_paralysis(mon):
		await get_tree().create_timer(STUNNED_TIME).timeout
		if not is_inside_tree():
			return
		if State.enemy_mons.has(mon):
			_plan_intent(mon)
			Events.intents_changed.emit()
		_end_turn(mon)
		return
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
		await _relic_overlay.wait_idle()
		if not is_inside_tree():
			return
	_plan_intent(mon)
	Events.intents_changed.emit()
	_end_turn(mon)

## Ende eines Zuges: Verbrennung wirkt, danach ist das nächste Monster dran.
func _end_turn(mon: Monster) -> void:
	if ElementEffects.tick_burn(mon):
		await get_tree().create_timer(STATUS_TICK_TIME).timeout
		if not is_inside_tree():
			return
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
		scene.texture_rect.material = Monmap.monster_battle_selected_material if scene.mon == mon and mon != null else Monmap.MONSTER_MATERIAL
	turn_wheel.set_selected_mon(mon)
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
	# Boss-Relikte gelten nur für diesen Kampf
	BossRelics.active = []
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
## Element-Effekte (ElementEffects): Schwächungen und Status pro getroffenem Gegner, Verstärkungen einmal für den Wirker.
## Vulkan wirkt mit etwas Glück ein zweites Mal mit gleicher Stärke (zweiter Treffer, doppelter Schild).
func _use_skill(from: Monster, skill: Dictionary, target: Monster) -> void:
	var targets = [target]
	if Skills.targets_team(skill):
		targets = _allies_of(target)
	var repeats := 1
	if ElementEffects.rolls_eruption(skill):
		repeats = 2
		Events.monster_effect_text.emit(from, tr("EFFECT_TEXT_ERUPTION"), ElementEffects.ERUPTION_COLOR)
	var dealt := 0.0
	var hostile := not Skills.targets_friends(skill)
	for _i in repeats:
		for mon in targets:
			if not mon.is_alive():
				continue
			# Angriffsanimation nur gegen Gegner
			if hostile:
				Events.monster_hit_monster.emit(_scene_for(from), _scene_for(mon))
				# Boss-Relikt Nebelmaschine: der Angriff kann ins Leere gehen
				if Skills.is_damage_skill(skill) and BossRelics.dodges(mon):
					continue
			var props := {"from": from, "skill": skill, "mon": mon}
			skill.handle.call(props)
			var hit: float = props.get("dealt", 0.0)
			dealt += hit
			if hostile:
				ElementEffects.on_hit(from, mon, skill)
				BossRelics.on_damage_dealt(from, mon, skill, hit, turn_wheel.round_number)
	ElementEffects.on_cast(from, skill, dealt)
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
	# Boss-Relikte gehören zum Kampf, nicht zu einem Boss: alle Bosse teilen sie
	BossRelics.active = BossRelics.random_relics() if is_boss_battle else []
	if is_boss_battle:
		_apply_debug_boss_setup(ms)
	print("encounter depth ", depth, " fight ", State.biome_fight_index, ": ", ms.size(), "x level ", level)
	State.enemy_mons = ms

## Im Debug-Menü gewählte Relikte (für den Kampf) und Trophäen (für jeden Boss) ersetzen die gewürfelten
func _apply_debug_boss_setup(bosses: Array[Monster]) -> void:
	var relics = DebugSettings.take_boss_relics()
	var trophies = DebugSettings.take_boss_trophies()
	if relics != null:
		BossRelics.active = relics.duplicate()
	for boss in bosses:
		if trophies != null:
			boss._gems = {}
			boss._gem_counts = {}
			BossRelics.add_trophies(boss, trophies)

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
	if _battle_over:
		return
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
		# mit dem letzten Gegner zerbrechen die Relikte des Kampfs, erst danach geht es weiter
		if not BossRelics.active.is_empty() and State.enemy_mons.all(func(mon: Monster): return not mon.is_alive()):
			_pending_breaks += 1
			await _break_relics(false)
			_pending_breaks -= 1
			if not is_inside_tree() or _battle_over:
				return
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
		_battle_over = true
		State.end_run(false)
		_clear_fainted_mons()
		get_tree().change_scene_to_file("res://script/scenes/run_end/run_end.tscn")
		return
	if State.enemy_mons.all(func(mon: Monster): return not mon.is_alive()) or State.enemy_mons.size() == 0:
		# zerbrechen die Relikte gerade noch, beendet erst deren Aufruf den Kampf
		if _pending_breaks > 0:
			return
		_battle_over = true
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

## Der letzte Gegner ist weg: die Relikte des Kampfs zerbrechen, forgotten = Fang mit vollen KP (sie bleiben liegen)
func _break_relics(forgotten: bool) -> void:
	var relics := BossRelics.take_active()
	_relic_bar.refresh()
	await _relic_overlay.play_break(relics, forgotten)

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

## Plant den nächsten Zug eines Gegners (Monster._intent): Skills, bis seine Aktionen aufgebraucht sind.
## Jede Kombination aus Skill und Ziel wird bewertet (_score_action) und gewichtet gewürfelt (_weighted_pick),
## dabei zählen die schon geplanten Angriffe aller Gegner mit (Fokus, kein Overkill). Zum Schluss wird sortiert (_order_intent).
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
			break
		var candidates = []
		for skill in options:
			for target in _candidate_targets(emon, skill):
				candidates.append({"skill": skill, "target": target, "score": _score_action(emon, skill, target)})
		var picked: Dictionary = _weighted_pick(candidates)
		moves -= maxi(picked.skill.cost, 1)
		if picked.skill.get("cooldown", 0) > 0 or not Skills.is_damage_skill(picked.skill):
			once_used.append(picked.skill)
		# sofort eintragen: die folgenden Aktionen sehen diesen Angriff schon bei den Rest-KP
		emon._intent.append({"skill": picked.skill, "target": picked.target})
	_order_intent(emon)

func _can_plan(emon: Monster, skill: Dictionary, moves_left: int) -> bool:
	return Skills.can_use(emon, skill) and not Skills.is_passive(skill) \
		and Skills.cooldown_left(skill) <= 1 and maxi(skill.cost, 1) <= moves_left

## Bestes Ziel für einen Skill (gewichtet gewürfelt), auch beim Neuwählen nach einem K.O.
func _pick_target(emon: Monster, skill: Dictionary) -> Monster:
	var candidates = []
	for target in _candidate_targets(emon, skill):
		candidates.append({"target": target, "score": _score_action(emon, skill, target)})
	return _weighted_pick(candidates).target if not candidates.is_empty() else null

## Mögliche Ziele: Flächen-Skills treffen ohnehin die ganze Seite, dort reicht ein Ziel.
func _candidate_targets(emon: Monster, skill: Dictionary) -> Array:
	var side = _allies_of(emon) if Skills.targets_friends(skill) else _opponents_of(emon)
	if Skills.targets_team(skill) and not side.is_empty():
		return [side[0]]
	return side

## Gewichteter Zufall über {"score": float, ...}: Gewicht = score ^ Schärfe
func _weighted_pick(candidates: Array) -> Dictionary:
	var sharpness := _ai_sharpness()
	var weights = candidates.map(func(c): return pow(maxf(c.score, AI_MIN_SCORE), sharpness))
	var total: float = 0.0
	for w in weights:
		total += w
	var roll := randf() * total
	for i in candidates.size():
		roll -= weights[i]
		if roll <= 0.0:
			return candidates[i]
	return candidates.back()

## Je tiefer im Run, desto taktischer, Bosse noch etwas mehr
func _ai_sharpness() -> float:
	var sharpness := AI_SHARPNESS_BASE + AI_SHARPNESS_PER_DEPTH * Map.encounter_depth()
	if is_boss_battle or State.is_final_boss:
		sharpness += AI_SHARPNESS_BOSS
	return sharpness

## Wie gut ist dieser Skill gegen dieses Ziel? Schaden in KP, Schilde/Buffs als Grundwert (Ausbau in Schritt 6).
func _score_action(emon: Monster, skill: Dictionary, target: Monster) -> float:
	if Skills.targets_friends(skill):
		if skill.has("buff_stat"):
			var stat_value: float = _stat_value(target, skill.buff_stat)
			return stat_value * skill.value / 100 * skill.get("buff_turns", 1) * AI_DEFENSE_WEIGHT
		var physical := Skills.is_physical(skill)
		var def: float = emon.defense() if physical else emon.s_defense()
		return def * skill.value / 100 * AI_DEFENSE_WEIGHT
	if not Skills.is_damage_skill(skill):
		return AI_MIN_SCORE
	var targets = _allies_of(target) if Skills.targets_team(skill) else [target]
	var score := 0.0
	for mon: Monster in targets:
		score += _damage_value(emon, skill, mon)
	return score

## aktueller Wert zu einem Buff-Schlüssel (buff_stat)
func _stat_value(mon: Monster, stat: String) -> float:
	match stat:
		"atk": return mon.attack()
		"s_atk": return mon.s_attack()
		"s_def": return mon.s_defense()
		"speed": return mon.speed()
	return mon.defense()

## Schaden gegen ein Ziel, gemessen an seinen Rest-KP nach allen schon geplanten Angriffen:
## Kill = Bonus, Schaden darüber hinaus zählt kaum, Ziele mit hohem Angriff werden leicht bevorzugt.
## Schilde der Ziele zählen nicht: sie laufen meist ab, bevor der Gegner zuschlägt.
func _damage_value(emon: Monster, skill: Dictionary, target: Monster) -> float:
	var damage := Skills.calc_damage(emon, target, skill)
	var remaining := _remaining_hp(target)
	var value: float
	if remaining <= 0.0:
		value = damage * AI_OVERKILL_SHARE
	else:
		value = minf(damage, remaining) + maxf(damage - remaining, 0.0) * AI_OVERKILL_SHARE
		if damage >= remaining:
			value *= AI_KILL_BONUS
	return value * _threat_factor(target)

## KP nach allen Angriffen, die die Gegner (inklusive des gerade planenden) schon eingeplant haben
func _remaining_hp(target: Monster) -> float:
	var remaining: float = target.hp() - target._lost_hp
	for hit in Skills.incoming_hits(target, State.enemy_mons):
		remaining -= hit.full
	return remaining

## 1.0 für durchschnittlich starke Ziele, mehr für Ziele mit überdurchschnittlichem (Sp.) Angriff
func _threat_factor(target: Monster) -> float:
	var side = _allies_of(target)
	if side.size() < 2 or AI_THREAT_WEIGHT <= 0.0:
		return 1.0
	var total := 0.0
	for mon: Monster in side:
		total += maxf(mon.attack(), mon.s_attack())
	var average := total / side.size()
	if average <= 0.0:
		return 1.0
	var threat := maxf(target.attack(), target.s_attack()) / average
	return maxf(1.0 + AI_THREAT_WEIGHT * (threat - 1.0), 0.5)

## Reihenfolge im Zug: Buffs (Verteidigung rauf -> größerer Schild), Schilde, Schlamm-Angriffe
## (Angriff rauf für die folgenden Treffer), übrige Angriffe. Innerhalb einer Gruppe bleibt die Reihenfolge.
func _order_intent(emon: Monster) -> void:
	var entries = []
	for i in emon._intent.size():
		entries.append({"priority": _action_priority(emon._intent[i].skill), "index": i, "action": emon._intent[i]})
	entries.sort_custom(func(a, b): return a.priority < b.priority or (a.priority == b.priority and a.index < b.index))
	emon._intent = entries.map(func(e): return e.action)

func _action_priority(skill: Dictionary) -> int:
	if skill.has("buff_stat"):
		return 0
	if not Skills.is_damage_skill(skill):
		return 1
	if skill.nature == ElementEffects.MUD:
		return 2
	return 3

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
	_end_turn(active_mon)

func _finish_catching(catched: bool, mon: Monster) -> void:
	if catched:
		# war es der letzte Gegner, gehen die Relikte verloren: zerbrochen, oder bei vollen KP einfach liegen gelassen
		var last_enemy: bool = State.enemy_mons.all(func(m: Monster): return m == mon or not m.is_alive())
		if last_enemy and not BossRelics.active.is_empty():
			await _break_relics(mon._lost_hp <= 0)
			if not is_inside_tree():
				return
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
