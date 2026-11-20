class_name BattleRetry
extends RefCounted

## Einstellung "Kampf wiederholen" (GameSettings.retry_battle): zu Beginn jedes Kampfs (nach dem Würfeln der Gegner)
## merkt sich das Spiel den ganzen Run-Zustand. Nach einer Niederlage bietet der End-Screen dann WIEDERHOLEN an:
## State, alle beteiligten Monster, die Boss-Relikte des Kampfs und der Spielstand (SaveManager) gehen auf den Stand
## vor dem Kampf zurück, und derselbe Kampf startet mit denselben Gegnern neu (battle.gd überspringt das Würfeln).
## Monster werden an Ort und Stelle zurückgesetzt, damit alle Verweise (State.starter, _last_hit_by ...) stimmen.

const BATTLE_PATH := "res://script/scenes/battle/battle.tscn"

## Stand vor dem Kampf, leer = nichts zu wiederholen
static var _snapshot := {}
## Der nächste Kampf ist eine Wiederholung: die Gegner stehen schon in State.enemy_mons
static var _replay := false

## Zustand zu Kampfbeginn merken, is_boss_battle wird bei der Wiederholung wiederhergestellt
static func capture(is_boss_battle: bool) -> void:
	if not GameSettings.retry_battle:
		_snapshot = {}
		return
	var mons := {}
	for mon in _all_mons():
		mons[mon] = _object_props(mon)
	_snapshot = {
		"state": _object_props(State),
		"mons": mons,
		"save_data": SaveManager.save_data.duplicate(true),
		"boss_relics": BossRelics.active.duplicate(true),
		"is_boss_battle": is_boss_battle,
	}

## Nach dem Run (neuer Run, Sieg) gibt es nichts mehr zu wiederholen
static func clear() -> void:
	_snapshot = {}
	_replay = false

static func available() -> bool:
	return GameSettings.retry_battle and not _snapshot.is_empty()

## Alles auf den Stand vor dem Kampf und den Kampf neu starten
static func retry() -> void:
	if not available():
		return
	SaveManager.save_data = _snapshot.save_data.duplicate(true)
	SaveManager.save_game()
	_restore_props(State, _snapshot.state)
	for mon: Monster in _snapshot.mons:
		_restore_props(mon, _snapshot.mons[mon])
	BossRelics.active = _snapshot.boss_relics.duplicate(true)
	_replay = true
	SceneLoader.change_scene(BATTLE_PATH)

## Wird dieser Kampf wiederholt? Liefert dann is_boss_battle, sonst null. Gilt nur einmal.
static func take_replay():
	if not _replay or _snapshot.is_empty():
		_replay = false
		return null
	_replay = false
	return _snapshot.is_boss_battle

## Alle Monster, die der Kampf verändern kann
static func _all_mons() -> Array[Monster]:
	var found: Array[Monster] = []
	var lists: Array = [State.mons, State.enemy_mons, State.catched_mons, State.fainted_own_mons, State.fainted_enemy_mons]
	for list: Array in lists:
		for mon: Monster in list:
			if mon != null and not found.has(mon):
				found.append(mon)
	if State.starter != null and not found.has(State.starter):
		found.append(State.starter)
	return found

## Skript-Variablen eines Objekts, Arrays und Dictionaries tief kopiert (Monster darin bleiben Verweise)
static func _object_props(object: Object) -> Dictionary:
	var props := {}
	for prop in object.get_property_list():
		if not prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		props[prop.name] = _copy(object.get(prop.name))
	return props

static func _restore_props(object: Object, props: Dictionary) -> void:
	for key: String in props:
		var value = props[key]
		var current = object.get(key)
		# Setter wie Monster._lost_hp lösen Ereignisse aus: nur setzen, was sich geändert hat
		if typeof(current) == typeof(value) and current == value:
			continue
		object.set(key, _copy(value))
	# der Setter von State.ep zählt jeden Zuwachs in run_ep_earned mit, daher zum Schluss noch einmal
	if props.has("run_ep_earned"):
		object.set("run_ep_earned", props.run_ep_earned)

static func _copy(value):
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value
