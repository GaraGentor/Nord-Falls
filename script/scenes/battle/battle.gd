extends Control

const ENEMY_THINK_TIME := 0.6
const ENEMY_ACTION_TIME := 0.9
## Pause nach Gift/Verbrennung, länger als die KP-Animation: ein K.O. ist dann schon verarbeitet (turn_wheel.remove_mon)
const STATUS_TICK_TIME := BattleMonCard.HP_TWEEN_TIME + 0.3
## so lange steht "Betäubt!" über einem gelähmten Monster, bevor sein Zug endet
const STUNNED_TIME := 0.9
## Auto-Zugende (BattleControls): so lange laufen die Animationen der letzten Karte noch, bevor der Zug endet
const AUTO_END_DELAY := 0.6
## Chancen auf Zufallsbeute pro besiegtem Monster, gefangene Monster würfeln nicht. Jede Beute wird einzeln gewürfelt.
const KEY_LOOT_CHANCE := 0.15
const GEM_LOOT_CHANCE := 0.10
const GOLD_LOOT_CHANCE := 0.15
const COUPON_LOOT_CHANCE := 0.05
## Essenz als Zufallsbeute: Grundbetrag plus Zuschlag pro Biom-Tiefe
const GOLD_LOOT_MIN := 5
const GOLD_LOOT_MAX := 15
const GOLD_LOOT_PER_DEPTH := 5
## Boss Tränen als Beute pro Biom (Index = State.map_level), der letzte Eintrag gilt für den finalen Boss.
## Boss-Felder auf der Karte lassen keine fallen.
const BOSS_SHARDS_BY_BIOME := [1, 1, 2, 2, 4]
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
## pro Extra einer Karte (Schwächung, Aufladung, Heilung ...) zählt sie so viel mehr
const AI_EXTRA_WEIGHT := 0.15

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
## Übungskampf (Tutorial.practice): Stand des Runs vorher, damit danach alles wie zuvor ist
var _practice_snapshot := {}
## zählt jeden Zug mit: ein verzögertes Auto-Zugende greift nur im Zug, in dem es angestoßen wurde
var _turn_serial := 0
## One-Way-Items der eigenen Monster als Postits am linken Rand (ItemPostits)
var _item_postits: ItemPostitsScript
## Items, die in diesem Kampf schon als Beute gefallen sind (höchstens Items.MAX_DROPS_PER_BATTLE)
var _item_drops := 0
## Todes-Totem: gefallene eigene Monster, die am Ende des laufenden Zuges mit wenigen KP zurückkommen
var _pending_revives: Array[Monster] = []
## Wurfnetz: der laufende Fangversuch beendet den Zug nicht
var _catch_keeps_turn := false

const ItemPostitsScript := preload("res://script/scenes/battle/item_postits.gd")

func _enter_tree() -> void:
	if Tutorial.practice:
		_generate_practice()
		return
	# Kampf wiederholen (BattleRetry): Gegner und Zustand sind schon wiederhergestellt, nichts neu würfeln
	var replay = BattleRetry.take_replay()
	if replay != null:
		is_boss_battle = replay
	else:
		_generate_battle()
	BattleRetry.capture(is_boss_battle)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_add_ambient()
	Events.mouse_event.connect(_catch_mouse_event)
	Events.monster_faints.connect(_check_game_over)
	Events.finish_catching.connect(_finish_catching)

	# Schilde, Buffs und Abklingzeiten gelten nur für einen Kampf
	for mon in State.mons + State.enemy_mons:
		mon.reset_battle_state()
	BossRelics.current_round = 0
	BossRelics.banned_until_round = 0
	BossRelics.buddy_free_since = 0
	# Schaden verbraucht zuerst den Schild, der am frühesten abläuft
	Monster.shield_expiry = _shield_expiry
	Events.use_item.connect(_on_use_item)
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
	# Ebene genau über dem Kampffeld, aber über dem Eingabe-Blocker: Geschwindigkeit und Auto-Zugende lassen sich
	# immer umstellen, die Hand immer scrollen (ausspielen nur im eigenen Zug, siehe card_hand.can_play)
	var top_layer := Control.new()
	top_layer.name = "GameWindowTop"
	top_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_layer)
	top_layer.anchor_right = $GameWindow.anchor_right
	top_layer.anchor_bottom = $GameWindow.anchor_bottom
	top_layer.offset_left = $GameWindow.offset_left
	top_layer.offset_top = $GameWindow.offset_top
	top_layer.offset_right = $GameWindow.offset_right
	top_layer.offset_bottom = $GameWindow.offset_bottom
	card_hand.reparent(top_layer, false)
	card_hand.can_play = func() -> bool: return not $UI_Blocker.visible and _is_own_turn() and not _battle_over
	var controls := BattleControls.new()
	top_layer.add_child(controls)
	controls.auto_end_toggled.connect(func(_enabled): _try_auto_end())
	# Kampf-Cheats aus dem Debug-Menü links neben den Knöpfen, nicht im Übungskampf
	if BattleDebugButtons.wanted() and not Tutorial.practice:
		var debug_buttons := BattleDebugButtons.new()
		$GameWindow.add_child(debug_buttons)
		debug_buttons.win_pressed.connect(_debug_win)
	_relic_bar.pressed.connect(func(): _relic_overlay.play_intro(BossRelics.active, false))
	_item_postits = ItemPostitsScript.new($GameWindow)
	_item_postits.can_use = func(mon: Monster) -> bool:
		return not _battle_over and _is_own_turn() and mon == active_mon and mon.is_alive()
	# über dem Eingabe-Blocker: auch im Zug der Gegner lassen sich die Postits ausfahren (Einsetzen nur im eigenen Zug)
	add_child(_item_postits)
	move_child(_item_postits, $UI_Blocker.get_index() + 1)
	# Hand und Knöpfe über dem Blocker, die Postits noch darüber
	move_child(top_layer, _item_postits.get_index())
	_apply_start_items()
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
	if Tutorial.practice:
		_add_tutorial_targets()
		# wer das Tutorial überspringt, hat auch mit dem Übungskampf nichts mehr zu tun
		Tutorial.enabled_changed.connect(_on_tutorial_enabled_changed)
		Tutorial.trigger("battle")

## Gruppen, die das interaktive Tutorial hervorhebt (siehe Tutorial.SEQUENCES)
func _add_tutorial_targets() -> void:
	turn_wheel.add_to_group("tut_bat_wheel")
	card_hand.add_to_group("tut_bat_hand")
	catch_button.add_to_group("tut_bat_catch")
	$UI/HBoxContainer/TextureRect3/EndTurn.add_to_group("tut_bat_end_turn")
	for scene in _monster_scenes():
		if State.enemy_mons.has(scene.mon):
			scene.add_to_group("tut_bat_enemies")
			scene.intent_box.add_to_group("tut_bat_intent")

func _on_round_started(round_number: int) -> void:
	BossRelics.current_round = round_number
	_relic_bar.refresh()
	# Schilde zu Kampfbeginn (Schildrune) halten genau die erste Runde
	if round_number == 2:
		for mon: Monster in State.mons + State.enemy_mons:
			mon.expire_start_shields()
	BossRelics.on_round_started()
	# vor dem Aufbau des Rads: der neue Helfer ist in dieser Runde schon dabei
	if BossRelics.buddy_due(round_number):
		_spawn_buddy()

## Endboss-Relikt Buddy: ein Helfer betritt den ersten freien Gegner-Platz (leer, gefallen oder gefangen).
## Sind alle Plätze besetzt, kommt er erst, wenn einer frei wird.
func _spawn_buddy() -> void:
	var enemy_scenes := _monster_scenes().filter(func(scene): return not scene.home_mons)
	var free_scenes := enemy_scenes.filter(func(scene):
		return scene.mon == null or not scene.mon.is_alive() or not State.enemy_mons.has(scene.mon))
	if free_scenes.is_empty():
		return
	var buddy := BossRelics.make_buddy()
	State.enemy_mons.append(buddy)
	free_scenes[0].show_mon(buddy)
	battle_info.add_mon_card(buddy)
	_plan_intent(buddy)
	Events.intents_changed.emit()
	Events.monster_effect_text.emit(buddy, tr(BossRelics.get_relic("buddy").name), BossRelics.RELIC_COLOR)
	_relic_bar.refresh()

## Wie viele Zugwechsel, bis ein Schild von source auf holder abläuft (Monster.shield_expiry)
func _shield_expiry(source: Monster, holder: Monster) -> int:
	if source == null:
		return turn_wheel.turns_until_round_end()
	if not source.is_alive() or not (State.mons.has(source) or State.enemy_mons.has(source)):
		return turn_wheel.turns_until(holder)
	return turn_wheel.turns_until(source)

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
	_turn_serial += 1
	# Pfeil rechts neben dem Monster, das am Zug ist
	for scene in _monster_scenes():
		scene.set_turn_active(scene.mon == mon and mon != null)
	$UI_Blocker.visible = true
	# ein zerbrechendes Boss-Relikt hält den Kampf an
	await _relic_overlay.wait_idle()
	if not is_inside_tree():
		return
	_item_postits.refresh()
	# Gift wirkt vor dem Zug und geht durch alle Schilde
	if ElementEffects.tick_poison(mon):
		await get_tree().create_timer(STATUS_TICK_TIME).timeout
		if not is_inside_tree():
			return
	# wer am Zug ist, dessen Schilde und Spiegelungen laufen ab, egal auf wem sie liegen
	for other: Monster in State.mons + State.enemy_mons:
		other.expire_from(mon)
	mon.start_turn()
	# am Gift gestorben: das Rad hat das Monster schon entfernt, weiter zum nächsten
	if not mon.is_alive():
		turn_wheel.next_mon()
		return
	# Boss-Relikte zu Zugbeginn (Bongos, Fate-Spiegel), nach dem Ablaufen der alten Schilde
	BossRelics.on_turn_start(mon, turn_wheel.round_number)
	# Wasser-Passiv "regen": etwas KP zu Beginn des eigenen Zuges
	Skills.apply_regen(mon)
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

## Ende eines Zuges: das nächste Monster ist dran. Vorher stehen die vom Todes-Totem geretteten Monster wieder auf.
func _end_turn(_mon: Monster) -> void:
	_revive_pending()
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
	_refresh_catch_badge()

## "Neu!" am Hypnose-Knopf: der ausgewählte Gegner (das Ziel der Hypnose) ist eine Art, die man noch nicht besitzt
const CATCH_BADGE_FONT_SIZE := 32
## Lage des Schilds relativ zur oberen Mitte des Knopfs
const CATCH_BADGE_OFFSET := Vector2(42, 0)
var _catch_badge: Label

func _refresh_catch_badge() -> void:
	if catch_button == null:
		return
	if _catch_badge == null:
		_catch_badge = MoveChevrons.make_new_tag(tr("BATTLE_CATCH_NEW"), CATCH_BADGE_FONT_SIZE)
		catch_button.add_child(_catch_badge)
		# wie ein Aufkleber schräg oben rechts an der Spirale (das Symbol sitzt mittig im breiteren Knopf)
		_catch_badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
		_catch_badge.position += CATCH_BADGE_OFFSET
	var target := currently_selected_enemy_mon
	_catch_badge.visible = target != null and target.is_alive() and not target._minion \
		and MoveChevrons.is_new_species(target._name)

## nach einem K.O. oder Fang ein noch kämpfendes Monster markieren
func _reselect_if_gone(gone: Monster) -> void:
	if selected_mon != gone and currently_selected_enemy_mon != gone:
		return
	var alive_enemies = State.enemy_mons.filter(func(mon: Monster): return mon.is_alive() and mon != gone)
	if currently_selected_enemy_mon == gone:
		currently_selected_enemy_mon = alive_enemies[0] if not alive_enemies.is_empty() else null
		_refresh_catch_badge()
	if selected_mon != gone:
		return
	var alive = alive_enemies + State.mons.filter(func(mon: Monster): return mon.is_alive())
	if not alive.is_empty():
		_select_mon(alive[0])

func _exit_tree() -> void:
	if not _practice_snapshot.is_empty():
		_restore_practice_snapshot()
	if Tutorial.enabled_changed.is_connected(_on_tutorial_enabled_changed):
		Tutorial.enabled_changed.disconnect(_on_tutorial_enabled_changed)
	Events.mouse_event.disconnect(_catch_mouse_event)
	Events.monster_faints.disconnect(_check_game_over)
	Events.finish_catching.disconnect(_finish_catching)
	Events.use_item.disconnect(_on_use_item)
	Monster.shield_expiry = Callable()
	# Boss-Relikte gelten nur für diesen Kampf
	BossRelics.active = []
	BossRelics.banned_until_round = 0
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
			_try_auto_end()
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
	if Skills.targets_self(skill):
		return active_mon
	if Skills.targets_friends(skill):
		return selected_mon if _allies_of(active_mon).has(selected_mon) else active_mon
	# Aggro: zieht ein Gegner die Aufmerksamkeit auf sich, geht der Einzelangriff auf ihn
	var taunters := Skills.taunters(_opponents_of(active_mon))
	if Skills.targets_single_enemy(skill) and not taunters.is_empty() and not taunters.has(currently_selected_enemy_mon):
		return taunters[0]
	return currently_selected_enemy_mon

## Schilde und Buffs nur auf eigene Monster (Selbst-Karten nur auf den Wirker), Angriffe nur auf Gegner.
## Ziehen Gegner die Aufmerksamkeit auf sich (Skills.taunters), müssen Einzelangriffe einen von ihnen treffen.
func _is_valid_target(from: Monster, skill: Dictionary, target: Monster) -> bool:
	if target == null:
		return false
	if Skills.targets_self(skill):
		return target == from and from.is_alive()
	var side = _allies_of(from) if Skills.targets_friends(skill) else _opponents_of(from)
	if not side.has(target):
		return false
	if Skills.targets_single_enemy(skill):
		var taunters := Skills.taunters(side)
		return taunters.is_empty() or taunters.has(target)
	return true

## Setzt einen Skill ein: Flächen-Skills treffen die ganze Seite des Ziels, danach startet die Abklingzeit.
## Element-Effekte (ElementEffects): Schwächungen und Status pro getroffenem Gegner, Verstärkungen einmal für den Wirker.
## Vulkan wirkt mit etwas Glück ein zweites Mal mit gleicher Stärke (zweiter Treffer, doppelter Schild).
func _use_skill(from: Monster, card: Dictionary, target: Monster) -> void:
	# Blitz: die Fähigkeit kann fehlschlagen, Aktion und Abklingzeit sind trotzdem verbraucht
	if ElementEffects.rolls_fail(from):
		Skills.start_cooldown(card)
		Events.monster_status_changed.emit(from)
		return
	# schlummernde Skills wirken schwächer und ohne Element-Effekt (Skills.effective_skill), die Abklingzeit läuft auf der Karte
	var skill := Skills.effective_skill(from, card)
	# Weckstein: der nächste schlummernde Skill wirkt mit voller Kraft
	if from._item_marks.get("awake", false) and Skills.is_dormant(from, card):
		skill = card
		from._item_marks.erase("awake")
		Events.monster_effect_text.emit(from, tr("ITEM_WAKE_STONE"), Items.EFFECT_COLOR)
	var targets = [target]
	if Skills.targets_team(skill):
		targets = _allies_of(target)
	var repeats := 1
	if ElementEffects.rolls_eruption(skill, from):
		repeats = 2
		Events.monster_effect_text.emit(from, tr("EFFECT_TEXT_ERUPTION"), ElementEffects.ERUPTION_COLOR)
	var dealt := 0.0
	var hostile := not Skills.targets_friends(skill)
	# kritischer Treffer (Fokusflamme, Überladung): steckt schon in Skills.calc_damage, hier nur die Anzeige
	var crit := Skills.is_damage_skill(skill) and Skills.is_crit(from)
	if crit:
		Events.monster_effect_text.emit(from, tr("EFFECT_TEXT_CRIT"), ElementEffects.ERUPTION_COLOR)
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
			Events.skill_vfx.emit(mon, skill, props.get("blocked", 0.0))
			var hit: float = props.get("dealt", 0.0)
			dealt += hit
			if hostile:
				ElementEffects.on_hit(from, mon, skill)
				Skills.apply_hit_extras(from, mon, skill)
				BossRelics.on_damage_dealt(from, mon, skill, hit, turn_wheel.round_number)
			else:
				Skills.apply_friend_extras(from, mon, skill)
	# die eigene Aufladung ist mit diesem Angriff verbraucht, danach erst laden die Extras die Partner auf
	if Skills.is_damage_skill(skill):
		from.consume_charge(Skills.charge_kind(skill))
		# "nächster Treffer kritisch" gilt für genau einen Angriff (Flächenangriffe: alle Ziele dieses Angriffs)
		from.consume_boon("crit_next")
	ElementEffects.on_cast(from, skill, dealt)
	Skills.apply_cast_extras(from, skill, dealt)
	Skills.start_cooldown(card)
	Events.monster_status_changed.emit(from)
	# Kampfschrei: angekündigte Einzelangriffe der Gegner gehen jetzt auf den Wirker
	if skill.get("boon", "") == "taunt":
		_retarget_intents()
	# Treffer decken Werte auf (Skills.reveal_stats_by_hit)
	if selected_mon == from or targets.has(selected_mon):
		battle_info.refresh()

func subract_skill_points(selected_skill, mon) -> bool:
	var cost := Skills.skill_cost(mon, selected_skill)
	if mon._computed_moves >= cost:
		mon._computed_moves -= cost
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
	# Boss-Relikte gehören zum Kampf, nicht zu einem Boss: alle Bosse teilen sie. Gewürfelt mit den Gegnern (Map.generate_encounters)
	var relics := Map.take_pending_relics()
	BossRelics.active = relics if is_boss_battle else []
	if is_boss_battle:
		_apply_debug_boss_setup(ms)
	print("encounter depth ", depth, " fight ", State.biome_fight_index, ": ", ms.size(), "x level ", level)
	State.enemy_mons = ms

# ─────────────────────────
# Übungskampf (Tutorial.practice): ein einzelner Gegner aus dem aktuellen Biom auf Startstufe mit einer Aktion.
# Niemand geht K.O. und der Fang klappt sicher (Tutorial.cap_damage, Tutorial.catches_for_sure).
# Er zählt nicht: kein Fortschritt im Biom, keine Beute, kein Fang, und das Team ist danach wie vorher.

func _generate_practice() -> void:
	_practice_snapshot = {
		"lost_hp": State.mons.map(func(mon: Monster): return mon._lost_hp),
		"run_catches": State.run_catches,
		"caught_mon_names": State.caught_mon_names.duplicate(),
		"defeated_mon_names": State.defeated_mon_names.duplicate(),
		"revealed_mon_stats": State.revealed_mon_stats.duplicate(true),
		"skills": State.mons.map(func(mon: Monster): return mon._skills.duplicate()),
		# im Übungskampf eingesetzte Items kommen zurück, der geliehene Köder geht wieder
		"items": State.mons.map(func(mon: Monster): return mon._items.duplicate()),
		"bag": State.bag.duplicate(),
	}
	for mon: Monster in State.mons:
		_add_practice_attacks(mon)
		# das Tutorial zeigt am Köder, wie One-Way-Items funktionieren: jedes Monster bekommt einen geliehen
		mon._items[0] = Items.make("bait")
	var enemy: Monster = Helper.generate_mons({"count": 1, "species": [_practice_species()]})[0]
	enemy._level = State.INITIAL_LEVEL
	enemy._initial_moves = Monster.BASE_MOVES
	var ms: Array[Monster] = [enemy]
	BossRelics.active = []
	State.enemy_mons = ms

## Eine möglichst gewöhnliche Art aus dem Pool des aktuellen Bioms (ohne Pool aus allen Arten)
func _practice_species() -> String:
	var names: Array = Monmap.mons.filter(func(meta): return not meta.has("bounty_target")).map(func(meta): return meta.name)
	if State.map_level < State.biome_pools.size() and not State.biome_pools[State.map_level].is_empty():
		names = State.biome_pools[State.map_level].duplicate()
	var lowest: int = names.map(Monmap.rarity_of).min()
	return names.filter(func(mon_name): return Monmap.rarity_of(mon_name) == lowest).pick_random()

## Grundelement -> Namensteil der Starter-Skills (Skills.starter_skills)
const PRACTICE_ELEMENTS := {
	Enums.MON_TYPES.EARTH: "EARTH",
	Enums.MON_TYPES.FIRE: "FIRE",
	Enums.MON_TYPES.WATER: "WATER",
	Enums.MON_TYPES.AIR: "AIR",
}

## Das Tutorial verlangt Angriffe auf den Gegner, die gewählten Ei-Attacken können aber nur Schilde oder Buffs sein:
## für den Übungskampf vorn eine physische und eine magische Attacke des eigenen Elements (danach wieder weg)
func _add_practice_attacks(mon: Monster) -> void:
	for element: int in PRACTICE_ELEMENTS:
		if not Skills.shares_element(mon._type, element):
			continue
		var attacks := []
		for kind in ["PHYS", "MAG"]:
			var skill := Skills.get_skill("SKILL_%s_%s_LIGHT_THRUST" % [PRACTICE_ELEMENTS[element], kind])
			if not skill.is_empty() and not mon._skills.any(func(own): return own.name == skill.name):
				skill.scouted = true
				attacks.append(skill)
		mon._skills = attacks + mon._skills
		return

func _restore_practice_snapshot() -> void:
	for i in mini(State.mons.size(), _practice_snapshot.lost_hp.size()):
		State.mons[i]._lost_hp = _practice_snapshot.lost_hp[i]
		State.mons[i]._skills = _practice_snapshot.skills[i]
		State.mons[i]._items = _practice_snapshot.items[i]
	State.bag = _practice_snapshot.bag
	State.run_catches = _practice_snapshot.run_catches
	State.caught_mon_names = _practice_snapshot.caught_mon_names
	State.defeated_mon_names = _practice_snapshot.defeated_mon_names
	State.revealed_mon_stats = _practice_snapshot.revealed_mon_stats
	State.catched_mons = []
	State.enemy_mons = []
	_practice_snapshot = {}

## Gefangen oder Tutorial ausgeschaltet: zurück zur Karte, der Kampf hinterlässt nichts
func _end_practice() -> void:
	if _battle_over:
		return
	_battle_over = true
	# noch im Kampf zurücksetzen, die Lebensbalken hören dabei noch zu
	_restore_practice_snapshot()
	Tutorial.end_practice()

func _on_tutorial_enabled_changed(on: bool) -> void:
	if not on:
		_end_practice()

## Im Debug-Menü gewählte Relikte (für den Kampf) und Trophäen (für jeden Boss) ersetzen die gewürfelten
func _apply_debug_boss_setup(bosses: Array[Monster]) -> void:
	var relics = DebugSettings.take_boss_relics()
	var trophies = DebugSettings.take_boss_trophies()
	if relics != null:
		BossRelics.active = relics.duplicate()
	for boss in bosses:
		# Bosse ohne Trophäen (Schalter im Debug-Menü): auch die schon beim Betreten des Bioms gewürfelten fallen weg
		if trophies != null or not DebugSettings.boss_trophies_enabled():
			boss._gems = {}
			boss._gem_counts = {}
		if trophies != null:
			BossRelics.add_trophies(boss, trophies)

## Die Gegner des betretenen Felds. Kämpfe aus dem Debug-Menü kommen ohne Feld oder mit fester Anzahl und würfeln hier.
func _take_enemies(fight_index: int) -> Array[Monster]:
	var planned: Array[Monster] = Map.pending_enemies
	Map.pending_enemies = []
	var forced_count: int = DebugSettings.take_enemy_count(0)
	if not planned.is_empty() and forced_count == 0:
		return planned
	return Map.roll_boss_enemies(forced_count, State.is_final_boss) if is_boss_battle else Map.roll_fight_enemies(fight_index, forced_count)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func round_won():
	upgrade_mons()

func upgrade_mons():
	pass

## Meilenstein-Zähler, wenn das Start-Monster den letzten Treffer gelandet hat (nicht im Übungskampf):
## K.O.s, Kopfgelder und der letzte Treffer eines Biom-Boss-Kampfs (Boss-Felder auf der Karte zählen nicht).
func _count_starter_kill(defeated: Monster) -> void:
	if not _practice_snapshot.is_empty() or State.starter == null or defeated._last_hit_by != State.starter:
		return
	State.run_starter_kills += 1
	if defeated._bounty != "":
		State.run_starter_bounties += 1
	if State.is_boss_fight and State.enemy_mons.all(func(mon: Monster): return not mon.is_alive()):
		State.run_boss_finishers += 1
	Skills.check_milestones()

func _check_game_over(last_fainted:Monster) -> void:
	if _battle_over:
		return
	turn_wheel.remove_mon(last_fainted)
	_reselect_if_gone(last_fainted)
	_retarget_intents()
	var is_enemy = true if State.enemy_mons.find(last_fainted) > -1 else false
	if not is_enemy and State.mons.has(last_fainted):
		_try_death_totem(last_fainted)
	print("check gameover", State.mons.all(
			func(mon: Monster):
			return not mon.is_alive()
			))
	print("who ded?", str(is_enemy), State.enemy_mons.size(), ":", last_fainted._name)
	if is_enemy and last_fainted._minion:
		BossRelics.buddy_gone(turn_wheel.round_number)
	if is_enemy:
		State.killed_monsters += 1
		State.run_kills += 1
		State.mark_mon_defeated(last_fainted._name)
		_roll_kill_loot()
		var bounty_skill = Skills.claim_bounty(last_fainted)
		if bounty_skill != "":
			Helper.show_unlock_message(tr("BOUNTY_UNLOCKED").format({"skill": tr(bounty_skill), "mon": Helper.mon_display_name(last_fainted._last_hit_by._name)}))
		_count_starter_kill(last_fainted)
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
	# vom Todes-Totem gerettete Monster zählen schon als lebendig
	if State.mons.all(
			func(mon: Monster):
			return not mon.is_alive() and not _pending_revives.has(mon)
			):
		_battle_over = true
		State.end_run(false)
		_clear_fainted_mons()
		# statt eines grauen Bildes beim Laden: Lade-Bildschirm mit den Wellen
		SceneLoader.change_scene("res://script/scenes/run_end/run_end.tscn")
		return
	if State.enemy_mons.all(func(mon: Monster): return not mon.is_alive()) or State.enemy_mons.size() == 0:
		# zerbrechen die Relikte gerade noch, beendet erst deren Aufruf den Kampf
		if _pending_breaks > 0:
			return
		_battle_over = true
		print("will close battle")
		_revive_pending()
		State.stage_clear()
		_add_boss_loot()
		# besiegte Gegner bleiben in enemy_mons, gefangene nicht: nur Kills bringen Essenz
		State.pending_ep += Relics.modify("battle_ep", State.enemy_mons.map(func(mon): return mon._ep).reduce(func(a, b): return a + b, 0))
		print("state pending ep", State.pending_ep)
		# clear dead monsters.
		# open stats.
		var fallen = _clear_fainted_mons()
		# Items gefallener Monster liegen auf dem Schlachtfeld und müssen neu eingesammelt werden
		for mon: Monster in fallen:
			Items.drop_items(mon)
		# nach dem finalen Boss kommt kein Kampf mehr, Wiederbelebung und Letzter Wille brächten nichts
		if not State.is_final_boss:
			State.fainted_own_mons.append_array(fallen)
		if State.catched_mons.size() > 0 or not State.fainted_own_mons.is_empty():
			get_tree().change_scene_to_file("res://script/scenes/judgment/judgement.tscn")
			return
		get_tree().change_scene_to_file("res://script/scenes/world_map/world_map.tscn")

## Sofortsieg (Debug-Menü): alle Gegner fallen, danach geht es weiter wie nach einem normalen Sieg (_check_game_over).
## Ohne letzten Treffer eines eigenen Monsters gibt es dabei keine Kopfgelder und keine Meilensteine.
func _debug_win() -> void:
	if _battle_over:
		return
	for mon: Monster in State.enemy_mons.duplicate():
		if mon.is_alive():
			mon._last_hit_by = null
			mon._lost_hp = mon.hp()

## Der letzte Gegner ist weg: die Relikte des Kampfs zerbrechen, forgotten = Fang mit vollen KP (sie bleiben liegen)
func _break_relics(forgotten: bool) -> void:
	var relics := BossRelics.take_active()
	# einmal zerbrochen, kommen sie in diesem Biom nur noch, wenn keine anderen frei sind
	BossRelics.mark_used(relics)
	_relic_bar.refresh()
	await _relic_overlay.play_break(relics, forgotten)

## Zufallsbeute für ein besiegtes Monster. Der finale Boss beendet den Run, danach bringt Beute nichts mehr.
func _roll_kill_loot() -> void:
	if State.is_final_boss:
		return
	if randf() < Relics.modify("key_chance", KEY_LOOT_CHANCE):
		State.pending_keys += 1
	# One-Way-Items: gleiche Chance wie ein Schlüssel (ohne Relikt-Bonus), höchstens zwei pro Kampf
	if _item_drops < Items.MAX_DROPS_PER_BATTLE and randf() < KEY_LOOT_CHANCE:
		_item_drops += 1
		State.pending_items.append(Items.roll_item(is_boss_battle))
	if randf() < GEM_LOOT_CHANCE:
		State.pending_gems += 1
	if randf() < COUPON_LOOT_CHANCE:
		State.pending_coupons += 1
	if randf() < GOLD_LOOT_CHANCE:
		State.pending_ep += randi_range(GOLD_LOOT_MIN, GOLD_LOOT_MAX) + State.map_level * GOLD_LOOT_PER_DEPTH

## Mini-Boss und Biom-Boss lassen bei jedem Sieg Kiste und Couvert fallen, auch wenn sie gefangen wurden.
## Biom-Bosse lassen zusätzlich Boss Tränen fallen, der finale Boss nur diese. Das Ei lost der Level-Up-Bildschirm.
## In der Kiste: beim Biom-Boss seltene Relikte, beim Boss-Feld gewöhnliche (Relics.chest_rarity).
func _add_boss_loot() -> void:
	if State.is_boss_fight:
		var biome := BOSS_SHARDS_BY_BIOME.size() - 1 if State.is_final_boss else mini(State.map_level, BOSS_SHARDS_BY_BIOME.size() - 1)
		State.pending_boss_shards = BOSS_SHARDS_BY_BIOME[biome]
	if not is_boss_battle or State.is_final_boss:
		return
	State.relic_chest_rarity = Relics.chest_rarity(State.is_boss_fight)
	State.pending_relic_chest = not Relics.chest_offers(State.relic_chest_rarity).is_empty()
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
## Kerkermeister-Verbesserungen gelten nur für eigene Monster, Gegner haben _initial_moves (gewürfelt in _generate_battle).
## Der Relic-Hook "moves" (Schicksals-Symbol) gilt auch für Gegner.
func _plan_intent(emon: Monster) -> void:
	emon._intent = []
	if not emon.is_alive() or _opponents_of(emon).is_empty():
		return
	var moves: int = Relics.modify("moves", emon._initial_moves, emon) + roundi(emon.boon_value("extra_moves"))
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
		moves -= maxi(Skills.skill_cost(emon, picked.skill), 1)
		if picked.skill.get("cooldown", 0) > 0 or not Skills.is_damage_skill(picked.skill):
			once_used.append(picked.skill)
		# sofort eintragen: die folgenden Aktionen sehen diesen Angriff schon bei den Rest-KP
		emon._intent.append({"skill": picked.skill, "target": picked.target})
	_order_intent(emon)

func _can_plan(emon: Monster, skill: Dictionary, moves_left: int) -> bool:
	return Skills.can_use(emon, skill) and not Skills.is_passive(skill) \
		and Skills.cooldown_left(skill) <= 1 and maxi(Skills.skill_cost(emon, skill), 1) <= moves_left

## Bestes Ziel für einen Skill (gewichtet gewürfelt), auch beim Neuwählen nach einem K.O.
func _pick_target(emon: Monster, skill: Dictionary) -> Monster:
	var candidates = []
	for target in _candidate_targets(emon, skill):
		candidates.append({"target": target, "score": _score_action(emon, skill, target)})
	return _weighted_pick(candidates).target if not candidates.is_empty() else null

## Mögliche Ziele: Flächen-Skills treffen ohnehin die ganze Seite, dort reicht ein Ziel.
## Selbst-Karten nur auf sich, Einzelangriffe nur auf Monster, die die Aufmerksamkeit auf sich ziehen (falls es welche gibt).
func _candidate_targets(emon: Monster, skill: Dictionary) -> Array:
	if Skills.targets_self(skill):
		return [emon]
	var side = _allies_of(emon) if Skills.targets_friends(skill) else _opponents_of(emon)
	if Skills.targets_team(skill) and not side.is_empty():
		return [side[0]]
	if Skills.targets_single_enemy(skill):
		var taunters := Skills.taunters(side)
		if not taunters.is_empty():
			return taunters
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
	# Team-Karten wirken auf alle eigenen Monster, Extras (Schwächung, Aufladung, Heilung ...) machen eine Karte etwas wertvoller
	var extra_factor := 1.0 + AI_EXTRA_WEIGHT * Skills.extras(skill).size()
	if Skills.targets_friends(skill):
		var receivers := _allies_of(emon).size() if Skills.targets_team(skill) else 1
		# Sonder-Verstärkungen grob nach dem stärkeren Angriffswert des Ziels (gibt es bei Gegnern bisher nicht)
		if skill.get("effect", "") == "boon":
			return maxf(target.attack(), target.s_attack()) * AI_DEFENSE_WEIGHT * extra_factor
		if skill.has("buff_stat"):
			var stat_value: float = _stat_value(target, skill.buff_stat)
			return stat_value * skill.value / 100 * skill.get("buff_turns", 1) * AI_DEFENSE_WEIGHT * receivers * extra_factor
		return Skills.shield_amount(emon, skill) * AI_DEFENSE_WEIGHT * receivers * extra_factor
	if not Skills.is_damage_skill(skill):
		return AI_MIN_SCORE
	var targets = _allies_of(target) if Skills.targets_team(skill) else [target]
	var score := 0.0
	for mon: Monster in targets:
		score += _damage_value(emon, skill, mon)
	return score * extra_factor

## aktueller Wert zu einem Buff-Schlüssel (buff_stat)
func _stat_value(mon: Monster, stat: String) -> float:
	match stat:
		"atk": return mon.attack()
		"s_atk": return mon.s_attack()
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

## Reihenfolge im Zug: Buffs (Verteidigung rauf -> größerer Schild), Schilde, Angriffe.
## Innerhalb einer Gruppe bleibt die Reihenfolge.
func _order_intent(emon: Monster) -> void:
	var entries = []
	for i in emon._intent.size():
		entries.append({"priority": _action_priority(emon._intent[i].skill), "index": i, "action": emon._intent[i]})
	entries.sort_custom(func(a, b): return a.priority < b.priority or (a.priority == b.priority and a.index < b.index))
	emon._intent = entries.map(func(e): return e.action)

func _action_priority(skill: Dictionary) -> int:
	if skill.has("buff_stat") or skill.get("effect", "") == "boon":
		return 0
	if not Skills.is_damage_skill(skill):
		return 1
	return 2

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

## Auto-Zugende (BattleControls.auto_end): ist keine Karte mehr spielbar, endet der eigene Zug von selbst.
## Solange noch gefangen werden darf (noch keine Karte gespielt), bleibt die Entscheidung beim Spieler.
func _try_auto_end() -> void:
	if not _auto_end_ready():
		return
	var serial := _turn_serial
	await get_tree().create_timer(AUTO_END_DELAY).timeout
	if not is_inside_tree() or serial != _turn_serial:
		return
	await _relic_overlay.wait_idle()
	if not is_inside_tree() or serial != _turn_serial or not _auto_end_ready():
		return
	_on_end_turn_pressed()

func _auto_end_ready() -> bool:
	if not BattleControls.auto_end or _battle_over or not _is_own_turn() or not active_mon.is_alive():
		return false
	if _opponents_of(active_mon).is_empty():
		return false
	if catch_button.is_visible_in_tree() and not catch_button.disabled:
		return false
	return not active_mon._skills.any(func(skill): return Skills.is_playable(active_mon, skill) \
		and Skills.skill_cost(active_mon, skill) <= active_mon._computed_moves)

func _finish_catching(catched: bool, mon: Monster) -> void:
	# Wurfnetz: der Fangversuch kostet nichts und beendet den Zug nicht
	var keeps_turn := _catch_keeps_turn
	_catch_keeps_turn = false
	if Tutorial.practice and catched:
		_end_practice()
		return
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
	if keeps_turn and not _battle_over:
		$UI_Blocker.visible = false
		_item_postits.refresh()
		_try_auto_end()
		return
	_on_end_turn_pressed()

# ─────────────────────────
# One-Way-Items (Items): ausgerüstete Items der eigenen Monster, eingesetzt über die Postits am linken Rand.
# Nur im Zug des Monsters, das das Item trägt; kostet keine Aktion und beendet den Zug nicht.

## Zu Kampfbeginn: Items, die sich selbst aktivieren (Schildrune)
func _apply_start_items() -> void:
	for mon: Monster in State.mons:
		for i in mon._items.size():
			var item = mon._items[i]
			if item != null and item.id == "shield_rune":
				Items.consume({"mon": mon, "index": i})
				mon.add_start_shield(Items.RUNE_SHIELD)
				Events.monster_effect_text.emit(mon, Items.title(item), Items.EFFECT_COLOR)
	_item_postits.refresh()

func _on_use_item(carrier: Monster, index: int, target: Monster) -> void:
	if _battle_over or not _is_own_turn() or carrier != active_mon or not carrier.is_alive():
		return
	var slot := {"mon": carrier, "index": index}
	var item = Items.get_at(slot)
	if item == null or not Items.battle_target_ok(item, target):
		return
	Items.consume(slot)
	Events.monster_effect_text.emit(target if target != null else carrier, Items.title(item), Items.EFFECT_COLOR)
	_apply_item(carrier, item, target)
	_item_postits.refresh()
	Events.item_used.emit(item)
	if selected_mon != null:
		battle_info.refresh()

func _apply_item(carrier: Monster, item: Dictionary, target: Monster) -> void:
	match item.id:
		"net":
			_catch_keeps_turn = true
			_select_mon(target)
			catch_anim._catch_animation(target)
		"bait":
			target._item_marks["bait"] = target._item_marks.get("bait", 0.0) + Items.BAIT_BONUS
			Events.monster_status_changed.emit(target)
		"whetstone":
			# wer gerade am Zug ist, darf sofort mehr; andere bekommen die Aktion in ihrem nächsten Zug
			if target == active_mon:
				target._computed_moves += 1
			else:
				target.add_boon("extra_moves", 1, 2)
			Events.status_vfx.emit(target, "buff")
		"portable_shield":
			for mon: Monster in _allies_of(carrier):
				mon.add_shield(Items.PORTABLE_SHIELD, carrier)
		"scarecrow":
			# eine geplante Aktion weniger, bei nur einer Aktion fällt der ganze Zug aus
			if not target._intent.is_empty():
				target._intent.pop_back()
			Events.status_vfx.emit(target, "debuff")
			Events.intents_changed.emit()
		"hourglass":
			turn_wheel.pull_forward(target)
		"wake_stone":
			target._item_marks["awake"] = true
			Events.status_vfx.emit(target, "buff")
		"stench":
			for emon: Monster in _opponents_of(carrier):
				_plan_intent(emon)
			Events.intents_changed.emit()
		"blood_stone":
			target._item_marks["blood"] = Items.BLOOD_FACTOR
			Events.status_vfx.emit(target, "debuff")
		"cuckoo_clock":
			for skill in target._skills:
				if Skills.cooldown_left(skill) > 0:
					skill._cooldown_left -= 1
			Events.monster_status_changed.emit(target)
			if target == active_mon:
				card_hand.show_mon(target)
		"clear_water":
			target._statuses = {}
			target._debuffs = {}
			Events.status_vfx.emit(target, "heal")
			Events.monster_status_changed.emit(target)
		"ban_seal":
			BossRelics.ban(Items.BAN_ROUNDS)
			_relic_bar.refresh()
		"mirror_shard":
			target.add_reflect(Items.MIRROR_SHARE, carrier)

## Todes-Totem: fällt ein eigenes Monster und trägt irgendein Team-Monster das Totem, steht es am Ende
## des laufenden Zuges (also nach den Aktionen des Gegners) mit wenigen KP wieder auf
func _try_death_totem(mon: Monster) -> void:
	if _pending_revives.has(mon) or Tutorial.practice:
		return
	var slot := Items.find_equipped("death_totem", State.mons)
	if slot.is_empty():
		return
	Items.consume(slot)
	_pending_revives.append(mon)
	_item_postits.refresh()

func _revive_pending() -> void:
	if _pending_revives.is_empty():
		return
	for mon in _pending_revives:
		mon._lost_hp = mon.hp() - Items.TOTEM_HP
		# der K.O. zählt nicht für den Endbildschirm und die Meilensteine ohne K.O.
		for i in range(State.run_deaths.size() - 1, -1, -1):
			if State.run_deaths[i].victim == mon._name:
				State.run_deaths.remove_at(i)
				break
		Events.monster_revived.emit(mon)
		Events.monster_effect_text.emit(mon, tr("ITEM_DEATH_TOTEM"), Items.EFFECT_COLOR)
	_pending_revives.clear()
	# Gegner, die mangels Ziel nichts geplant haben, planen neu
	for emon: Monster in State.enemy_mons:
		if emon.is_alive() and emon._intent.is_empty():
			_plan_intent(emon)
	_retarget_intents()
	_item_postits.refresh()

func _on_catch_pressed() -> void:
	# Events.mouse_event.emit({"action": Enums.MOUSE_ACTION.CATCH_MONSTER})
	print(currently_selected_enemy_mon)
	print(State.enemy_mons)
	var already_catched = State.catched_mons.find(currently_selected_enemy_mon)
	if currently_selected_enemy_mon and currently_selected_enemy_mon.is_alive() and already_catched == -1 \
			and not currently_selected_enemy_mon._minion:
		catch_anim._catch_animation(currently_selected_enemy_mon)
