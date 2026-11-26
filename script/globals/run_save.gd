class_name RunSave

## Speichern und Beenden (Tür im Header der Karte): der laufende Run landet in einer eigenen Datei (PATH), getrennt vom
## Spielstand (SaveManager) und den Einstellungen. Gespeichert wird alles, was zum Weiterspielen nötig ist: State, die
## Gegner und Boss-Relikte der Karte (Map) und die Boss-Relikte (BossRelics), samt Monstern, Items, Relikten, Geld usw.
##
## Never surrender: beim Spielstart liest SaveManager die Datei in den Speicher und löscht sie sofort (take_on_boot).
## Die Ei-Auswahl zeigt dann nur "Weiter" statt "Ei werfen" (ohne Biom-Pfad, ohne Tutorial). Wird das Spiel geschlossen,
## ohne wieder zu speichern, ist der Run weg, genauso nach Sieg oder Niederlage (dann gibt es ja keine Datei mehr).
##
## Monster, Wachstum und Kartenfelder sind Objekte, die sich gegenseitig kennen (Feld -> Gegner, Monster -> Growth,
## Feld -> Nachbarfelder). Sie werden einmal in eine Objekt-Tabelle geschrieben und sonst nur per Nummer verwiesen,
## so bleibt beim Laden jedes Objekt dasselbe. Skills enthalten Callables ("handle"): gespeichert werden nur ihre
## Daten, beim Laden kommt der Skill frisch aus Skills.get_skill und bekommt die gespeicherten Werte zurück.

const PATH := "user://run_save.txt"
const VERSION := 1

## Eigenschaften der Autoloads, die zum Run gehören (Reihenfolge zählt: State.ep zählt beim Setzen run_ep_earned
## hoch, run_ep_earned kommt deshalb danach)
const STATE_SKIP := ["SETTING_LEVEL", "INITIAL_LEVEL", "INITIAL_MONS", "boss_shards"]
const MAP_PROPS := ["row_ref_half", "boss_ref_half", "biome_ref_kills", "pending_ref_half", "boss_enemies",
	"boss_relics", "pending_enemies", "pending_relics", "all_nodes", "starting_nodes"]
const BOSS_RELIC_PROPS := ["active", "current_round", "banned_until_round", "buddy_free_since"]
## Objekt-Eigenschaften, die nicht gespeichert werden (UI-Knoten des Felds, feste Namenstabelle)
const OBJECT_SKIP := ["_ui_item", "_name_map"]
## Ersatz für Gelöschtes (entfernte Art, entfernter Skill): fliegt beim Laden aus Listen raus
const REMOVED := "__run_save_removed__"

## Beim Start gelesener Run, wartet auf "Weiter" in der Ei-Auswahl (leer = keiner)
static var _pending := {}

# ─────────────────────────
# Datei

## SaveManager._ready: Datei in den Speicher holen und gleich löschen
static func take_on_boot() -> void:
	_pending = {}
	if not FileAccess.file_exists(PATH):
		return
	var text := FileAccess.get_file_as_string(PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var parsed = str_to_var(text)
	if parsed is Dictionary and int(parsed.get("version", 0)) == VERSION:
		_pending = parsed
	else:
		push_warning("RunSave: Spielstand in %s ist unlesbar und wurde verworfen" % PATH)

## Liegt ein gespeicherter Run bereit? Dann gibt es in der Ei-Auswahl nur "Weiter".
static func has_pending() -> bool:
	return not _pending.is_empty()

## Auf der Karte speichern (nicht im Tutorial-Lauf, der schreibt nichts auf die Platte)
static func can_save() -> bool:
	return not Tutorial.run_active and not State.mons.is_empty()

static func save() -> bool:
	if not can_save():
		return false
	var ctx := {"ids": {}, "objects": []}
	var data := {
		"version": VERSION,
		"state": _encode_props(State, _state_props(), ctx),
		"map": _encode_props(Map, MAP_PROPS, ctx),
		"boss_relics": _encode_props(BossRelics, BOSS_RELIC_PROPS, ctx),
	}
	data["objects"] = ctx.objects
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_error("RunSave: %s lässt sich nicht schreiben (%s)" % [PATH, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(var_to_str(data))
	file.close()
	return true

## "Weiter": den gespeicherten Run wiederherstellen, danach geht es auf die Karte
static func restore() -> bool:
	if _pending.is_empty():
		return false
	var data := _pending
	_pending = {}
	State.reset()
	var objects := _create_objects(data.objects)
	_fill_objects(data.objects, objects)
	_restore_props(State, data.state, objects)
	_restore_props(Map, data.map, objects)
	_restore_props(BossRelics, data.boss_relics, objects)
	Relics.relics_changed.emit()
	Items.items_changed.emit()
	return true

static func _state_props() -> Array:
	var props := []
	for prop in State.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not STATE_SKIP.has(prop.name):
			props.append(prop.name)
	return props

# ─────────────────────────
# Speichern: Werte in reine Daten (ohne Objekte und Callables) umwandeln

static func _encode_props(target: Object, props: Array, ctx: Dictionary) -> Dictionary:
	var result := {}
	for prop in props:
		var value = target.get(prop)
		if value is Callable:
			continue
		result[prop] = _encode(value, ctx)
	return result

static func _encode(value, ctx: Dictionary):
	match typeof(value):
		TYPE_ARRAY:
			var items := []
			for item in value:
				items.append(_encode(item, ctx))
			return items
		TYPE_DICTIONARY:
			# Skills: nur die Daten, die Callables kommen beim Laden aus Skills.get_skill
			if value.get("handle") is Callable and value.has("name"):
				return {"__skill": value.name, "data": _encode_plain_dict(value, ctx)}
			return _encode_plain_dict(value, ctx)
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return null
		TYPE_OBJECT:
			return _encode_object(value, ctx)
		_:
			return value

static func _encode_plain_dict(value: Dictionary, ctx: Dictionary) -> Dictionary:
	var result := {}
	for key in value:
		var item = value[key]
		if item is Callable:
			continue
		result[_encode(key, ctx)] = _encode(item, ctx)
	return result

static func _encode_object(obj: Object, ctx: Dictionary):
	if obj == null or not is_instance_valid(obj):
		return null
	if obj is Resource:
		return {"__res": obj.resource_path} if obj.resource_path != "" else null
	var kind := _kind_of(obj)
	if kind == "":
		# Knoten (UI) und alles andere gehören nicht zum Run
		return null
	var key := obj.get_instance_id()
	if ctx.ids.has(key):
		return {"__obj": ctx.ids[key]}
	var id: int = ctx.objects.size()
	ctx.ids[key] = id
	var record := {"kind": kind, "props": {}}
	ctx.objects.append(record)
	if obj is Monster:
		record["name"] = obj._name
		record["level"] = obj._level
	for prop in obj.get_property_list():
		if not prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE or OBJECT_SKIP.has(prop.name):
			continue
		var item = obj.get(prop.name)
		if item is Callable:
			continue
		record.props[prop.name] = _encode(item, ctx)
	return {"__obj": id}

static func _kind_of(obj: Object) -> String:
	if obj is Monster:
		return "monster"
	if obj is Growth:
		return "growth"
	if obj.get_script() == Map.path:
		return "path"
	return ""

# ─────────────────────────
# Laden: erst alle Objekte anlegen, dann füllen (sie verweisen aufeinander)

static func _create_objects(records: Array) -> Array:
	var objects := []
	for record in records:
		var obj: Object = null
		match record.kind:
			"monster":
				var meta: Dictionary = Monmap.mon_metainfos_by_name(str(record.name)) if _species_exists(str(record.name)) else {}
				if not meta.is_empty():
					obj = Monster.new(int(record.level), meta)
			"growth":
				var preferred := {}
				for attr in Growth.ATTRS:
					preferred[attr] = 1.0
				obj = Growth.new(preferred)
			"path":
				obj = Map.path.new(Vector3.ZERO)
		objects.append(obj)
	return objects

static func _species_exists(mon_name: String) -> bool:
	return Monmap.mons.any(func(meta): return str(meta.name) == mon_name)

static func _fill_objects(records: Array, objects: Array) -> void:
	for i in records.size():
		var obj: Object = objects[i]
		if obj == null:
			continue
		for prop in records[i].props:
			var value = _decode(records[i].props[prop], objects)
			# _lost_hp hat einen Setter mit Kampf-Signalen: nur setzen, wenn das Monster wirklich Schaden hat
			if prop == "_lost_hp" and is_zero_approx(float(value)):
				continue
			_assign(obj, prop, value)

static func _restore_props(target: Object, saved: Dictionary, objects: Array) -> void:
	for prop in saved:
		_assign(target, prop, _decode(saved[prop], objects))

static func _decode(value, objects: Array):
	match typeof(value):
		TYPE_ARRAY:
			var items := []
			for item in value:
				var decoded = _decode(item, objects)
				if not (decoded is String and decoded == REMOVED):
					items.append(decoded)
			return items
		TYPE_DICTIONARY:
			if value.has("__obj"):
				var obj = objects[int(value.__obj)] if int(value.__obj) < objects.size() else null
				return obj if obj != null else REMOVED
			if value.has("__res"):
				return load(value.__res) if ResourceLoader.exists(value.__res) else null
			if value.has("__skill"):
				var skill := Skills.get_skill(str(value.__skill))
				if skill.is_empty():
					return REMOVED
				_merge(skill, _decode(value.data, objects))
				return skill
			var result := {}
			for key in value:
				var decoded_key = _decode(key, objects)
				var decoded = _decode(value[key], objects)
				if (decoded_key is String and decoded_key == REMOVED) or (decoded is String and decoded == REMOVED):
					continue
				result[decoded_key] = decoded
			return result
		_:
			return value

## Gespeicherte Skill-Werte in den frischen Skill übernehmen. Verschachtelte Dictionaries werden zusammengeführt,
## damit Callables darin (die nicht gespeichert wurden) erhalten bleiben.
static func _merge(base: Dictionary, saved: Dictionary) -> void:
	for key in saved:
		if base.get(key) is Dictionary and saved[key] is Dictionary:
			_merge(base[key], saved[key])
		else:
			base[key] = saved[key]

## Typisierte Arrays und Dictionaries (Array[Monster] usw.) lassen sich nicht direkt mit untypisierten belegen:
## dann eine leere Kopie mit demselben Typ befüllen
static func _assign(target: Object, prop: String, value) -> void:
	var current = target.get(prop)
	if current is Array and value is Array and current.is_typed():
		var typed: Array = current.duplicate()
		typed.clear()
		var element_script = current.get_typed_script()
		for item in value:
			if element_script == null or (item is Object and is_instance_of(item, element_script)):
				typed.append(item)
		target.set(prop, typed)
		return
	if current is Dictionary and value is Dictionary and current.is_typed():
		var typed_dict: Dictionary = current.duplicate()
		typed_dict.clear()
		typed_dict.assign(value)
		target.set(prop, typed_dict)
		return
	target.set(prop, value)
