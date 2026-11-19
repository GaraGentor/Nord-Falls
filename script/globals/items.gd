extends Node

## One-Way-Items (auch "Loot"): Gegenstände für einen einzigen Einsatz im Kampf.
##
## Woher: Beute nach Kämpfen (battle.gd _roll_kill_loot, höchstens MAX_DROPS_PER_BATTLE pro Kampf, gleiche Chance wie ein
## Schlüssel), in Schätzen (treasure.gd, direkt in die Tasche) und gewöhnliche auch im Shop. Sie liegen erst auf dem Schlachtfeld (State.pending_items) und kommen erst in
## die Tasche, wenn man sie im Level-Up-Bildschirm hineinzieht.
## Wo: in der Tasche (State.bag, Raster mit BAG_COLUMNS Spalten, wächst bei Bedarf um eine Reihe) oder ausgerüstet an
## einem Monster (Monster._items, SLOTS_PER_MON Plätze). Nur ausgerüstete Items lassen sich im Kampf einsetzen.
## Ein Item ist ein Dictionary {"id": String}, die Werte stehen in ITEMS.
##
## Einsatz (battle.gd _use_item): nur im Zug des Monsters, das es trägt, kostet keine Aktion und beendet den Zug nicht.
## Arten (Feld "use"): "enemy" auf einen Gegner ziehen, "ally" auf ein eigenes Monster ziehen, "field" aufs Kampffeld
## ziehen (wirkt ohne Ziel), "auto" wirkt von selbst (nicht einsetzbar).
## Stirbt ein Monster, fallen seine Items aufs Schlachtfeld (drop_items), verlässt es das Team, gehen sie in die Tasche.

enum Rarity { COMMON, RARE, EPIC }

const RARITY_LABELS := {
	Rarity.COMMON: "RARITY_COMMON",
	Rarity.RARE: "RARITY_RARE",
	Rarity.EPIC: "RARITY_EPIC",
}
const RARITY_COLORS := {
	Rarity.COMMON: Color(0.75, 0.75, 0.75),
	Rarity.RARE: Color(0.3, 0.6, 1.0),
	Rarity.EPIC: Color(0.75, 0.35, 1.0),
}
## Seltenheit der Beute: normale Kämpfe und Boss-Kämpfe (Boss-Felder und Biom-Bosse)
const RARITY_WEIGHTS := {Rarity.COMMON: 75.0, Rarity.RARE: 20.0, Rarity.EPIC: 5.0}
const BOSS_RARITY_WEIGHTS := {Rarity.COMMON: 40.0, Rarity.RARE: 40.0, Rarity.EPIC: 20.0}
## Schätze (treasure.gd): jede Seltenheit gleich oft
const TREASURE_RARITY_WEIGHTS := {Rarity.COMMON: 1.0, Rarity.RARE: 1.0, Rarity.EPIC: 1.0}

## Beute: höchstens so viele Items pro Kampf, jedes besiegte Monster würfelt mit der Schlüssel-Chance (battle.gd)
const MAX_DROPS_PER_BATTLE := 2

const SLOTS_PER_MON := 2
## Tasche: so viele Spalten, mindestens so viele Plätze; ist sie voll, kommt eine weitere Reihe dazu
const BAG_COLUMNS := 4
const BAG_MIN_SLOTS := 12

## Shop: so viele gewöhnliche Items im Sortiment, Preis zufällig dazwischen
const SHOP_ASSORTMENT := 5
const SHOP_PRICE := [10, 20]

## Werte der Items
const BAIT_BONUS := 0.05
const RUNE_SHIELD := 10.0
const PORTABLE_SHIELD := 10.0
const BLOOD_FACTOR := 1.5
const MIRROR_SHARE := 0.5
const BAN_ROUNDS := 2
const TOTEM_HP := 1.0

## Farbe der schwebenden Texte, wenn ein Item wirkt
const EFFECT_COLOR := Color(1.0, 0.8, 0.45)

const USE_ENEMY := "enemy"
const USE_ALLY := "ally"
const USE_FIELD := "field"
const USE_AUTO := "auto"

## Hinweis, wie das Item eingesetzt wird (steht unter der Beschreibung)
const USE_HINTS := {
	USE_ENEMY: "ITEM_USE_ENEMY",
	USE_ALLY: "ITEM_USE_ALLY",
	USE_FIELD: "ITEM_USE_FIELD",
	USE_AUTO: "ITEM_USE_AUTO",
}

# Platzhalter-Bilder wie bei den Relikten, die Farbe der Seltenheit kommt über das Material dazu (icon)
const ITEMS := {
	# ── gewöhnlich (auch im Shop) ──
	"net": {"name": "ITEM_NET", "description": "ITEM_NET_DESC", "icon": "res://assets/ui/icons/battle/catch.svg",
		"rarity": Rarity.COMMON, "use": USE_ENEMY},
	"bait": {"name": "ITEM_BAIT", "description": "ITEM_BAIT_DESC", "icon": "res://assets/ui/icons/collection_eggs.svg",
		"rarity": Rarity.COMMON, "use": USE_ENEMY, "value": BAIT_BONUS * 100},
	"whetstone": {"name": "ITEM_WHETSTONE", "description": "ITEM_WHETSTONE_DESC", "icon": "res://assets/ui/icons/sword.svg",
		"rarity": Rarity.COMMON, "use": USE_ALLY, "value": 1},
	"shield_rune": {"name": "ITEM_SHIELD_RUNE", "description": "ITEM_SHIELD_RUNE_DESC", "icon": "res://assets/ui/icons/stat_s_shield.svg",
		"rarity": Rarity.COMMON, "use": USE_AUTO, "value": RUNE_SHIELD},
	"portable_shield": {"name": "ITEM_PORTABLE_SHIELD", "description": "ITEM_PORTABLE_SHIELD_DESC", "icon": "res://assets/ui/icons/battle/shield.svg",
		"rarity": Rarity.COMMON, "use": USE_FIELD, "value": PORTABLE_SHIELD},
	"scarecrow": {"name": "ITEM_SCARECROW", "description": "ITEM_SCARECROW_DESC", "icon": "res://assets/ui/icons/battle/debuff.svg",
		"rarity": Rarity.COMMON, "use": USE_ENEMY},
	# ── selten ──
	"hourglass": {"name": "ITEM_HOURGLASS", "description": "ITEM_HOURGLASS_DESC", "icon": "res://assets/ui/icons/clock.svg",
		"rarity": Rarity.RARE, "use": USE_ALLY},
	"wake_stone": {"name": "ITEM_WAKE_STONE", "description": "ITEM_WAKE_STONE_DESC", "icon": "res://assets/ui/icons/sparkle.svg",
		"rarity": Rarity.RARE, "use": USE_ALLY},
	"stench": {"name": "ITEM_STENCH", "description": "ITEM_STENCH_DESC", "icon": "res://assets/ui/icons/firework (1).svg",
		"rarity": Rarity.RARE, "use": USE_FIELD},
	"blood_stone": {"name": "ITEM_BLOOD_STONE", "description": "ITEM_BLOOD_STONE_DESC", "icon": "res://assets/ui/icons/stat_heart.svg",
		"rarity": Rarity.RARE, "use": USE_ENEMY, "value": BLOOD_FACTOR},
	"cuckoo_clock": {"name": "ITEM_CUCKOO_CLOCK", "description": "ITEM_CUCKOO_CLOCK_DESC", "icon": "res://assets/ui/icons/chevron-double-right.svg",
		"rarity": Rarity.RARE, "use": USE_ALLY, "value": 1},
	# ── episch ──
	"death_totem": {"name": "ITEM_DEATH_TOTEM", "description": "ITEM_DEATH_TOTEM_DESC", "icon": "res://assets/ui/icons/stat_pentagram.svg",
		"rarity": Rarity.EPIC, "use": USE_AUTO, "once_per_run": true},
	"clear_water": {"name": "ITEM_CLEAR_WATER", "description": "ITEM_CLEAR_WATER_DESC", "icon": "res://assets/ui/icons/battle/buff.svg",
		"rarity": Rarity.EPIC, "use": USE_ALLY},
	"ban_seal": {"name": "ITEM_BAN_SEAL", "description": "ITEM_BAN_SEAL_DESC", "icon": "res://assets/ui/icons/parchment.svg",
		"rarity": Rarity.EPIC, "use": USE_FIELD, "value": BAN_ROUNDS},
	"mirror_shard": {"name": "ITEM_MIRROR_SHARD", "description": "ITEM_MIRROR_SHARD_DESC", "icon": "res://assets/ui/icons/battle/s_shield.svg",
		"rarity": Rarity.EPIC, "use": USE_ALLY, "value": MIRROR_SHARE * 100},
}

const PROPS_MATERIAL = preload("res://script/scenes/jailer/jailer_props_material.tres")

# ─────────────────────────
# Daten

func make(id: String) -> Dictionary:
	return {"id": id}

func get_info(item: Dictionary) -> Dictionary:
	return ITEMS.get(item.get("id", ""), {})

func use_of(item: Dictionary) -> String:
	return get_info(item).get("use", USE_AUTO)

func rarity_of(item: Dictionary) -> int:
	return get_info(item).get("rarity", Rarity.COMMON)

func rarity_color(item: Dictionary) -> Color:
	return RARITY_COLORS[rarity_of(item)]

func title(item: Dictionary) -> String:
	return tr(get_info(item).get("name", ""))

## Beschreibung mit eingesetztem Wert, ohne Einsatz-Hinweis
func description(item: Dictionary) -> String:
	var info := get_info(item)
	var value = info.get("value", 0)
	var shown := str(roundi(value)) if (value is float and is_equal_approx(value, roundf(value))) or value is int else str(value)
	return tr(info.get("description", "")).format({"value": shown})

## Wie das Item eingesetzt wird ("Auf einen Gegner ziehen" ...)
func use_hint(item: Dictionary) -> String:
	return tr(USE_HINTS[use_of(item)])

## Platzhalter-Bild im Pixel-Look, eingefärbt in der Farbe der Seltenheit
func icon(item: Dictionary) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = load(get_info(item).get("icon", "res://assets/ui/icons/bag.svg"))
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat: ShaderMaterial = PROPS_MATERIAL.duplicate()
	var tint := rarity_color(item)
	tint.a = 0.85
	mat.set_shader_parameter("tint_color", tint)
	rect.material = mat
	return rect

# ─────────────────────────
# Beute und Shop

## Zufälliges Item einer gewürfelten Seltenheit. Items, die es pro Run nur einmal gibt (Todes-Totem), fallen weg,
## sobald sie einmal gefunden wurden. weights ersetzt die Gewichte der Seltenheiten (z. B. TREASURE_RARITY_WEIGHTS).
func roll_item(boss := false, weights: Dictionary = {}) -> Dictionary:
	if weights.is_empty():
		weights = BOSS_RARITY_WEIGHTS if boss else RARITY_WEIGHTS
	var rarities := weights.keys()
	var rarity: int = rarities[Map.pick_weighted_index(range(rarities.size()), rarities.map(func(r): return weights[r]))]
	var ids := _available_ids(rarity)
	if ids.is_empty():
		ids = _available_ids(Rarity.COMMON)
	var id: String = ids.pick_random()
	if ITEMS[id].get("once_per_run", false):
		State.found_unique_items.append(id)
	return make(id)

func _available_ids(rarity: int) -> Array:
	return ITEMS.keys().filter(func(id): return ITEMS[id].rarity == rarity \
		and not (ITEMS[id].get("once_per_run", false) and State.found_unique_items.has(id)))

## Sortiment des Shops für einen Besuch: verschiedene gewöhnliche Items mit zufälligem Preis
func shop_assortment() -> Array:
	var ids := ITEMS.keys().filter(func(id): return ITEMS[id].rarity == Rarity.COMMON)
	ids.shuffle()
	return ids.slice(0, SHOP_ASSORTMENT).map(func(id): return {"item": make(id), "price": randi_range(SHOP_PRICE[0], SHOP_PRICE[1])})

# ─────────────────────────
# Tasche und Ausrüstung
# Ein Platz wird über ein Dictionary angesprochen: {"mon": Monster, "index": int} für einen Platz am Monster,
# {"mon": null, "index": int} für einen Platz in der Tasche.

signal items_changed

## Sorgt dafür, dass die Tasche mindestens BAG_MIN_SLOTS volle Reihen hat
func normalize_bag() -> void:
	var size := maxi(BAG_MIN_SLOTS, ceili(State.bag.size() / float(BAG_COLUMNS)) * BAG_COLUMNS)
	while State.bag.size() < size:
		State.bag.append(null)

## Legt das Item auf den ersten freien Platz, eine volle Tasche bekommt vorher eine weitere Reihe
func add_to_bag(item: Dictionary) -> void:
	normalize_bag()
	var index := State.bag.find(null)
	if index == -1:
		index = State.bag.size()
		for i in BAG_COLUMNS:
			State.bag.append(null)
	State.bag[index] = item
	items_changed.emit()

func bag_count() -> int:
	return State.bag.filter(func(item): return item != null).size()

func get_at(slot: Dictionary):
	var list: Array = State.bag if slot.mon == null else slot.mon._items
	return list[slot.index] if slot.index < list.size() else null

func set_at(slot: Dictionary, item) -> void:
	var list: Array = State.bag if slot.mon == null else slot.mon._items
	while list.size() <= slot.index:
		list.append(null)
	list[slot.index] = item

## Tauscht den Inhalt zweier Plätze (leer gegen voll verschiebt einfach)
func swap(a: Dictionary, b: Dictionary) -> void:
	var first = get_at(a)
	set_at(a, get_at(b))
	set_at(b, first)
	# eine volle Tasche wächst, damit immer ein Platz frei bleibt, auf den man etwas ablegen kann
	if State.bag.find(null) == -1:
		for i in BAG_COLUMNS:
			State.bag.append(null)
	items_changed.emit()

## Monster verlässt das Team: seine Items gehen zurück in die Tasche
func return_items(mon: Monster) -> void:
	for i in mon._items.size():
		if mon._items[i] != null:
			add_to_bag(mon._items[i])
			mon._items[i] = null

## Monster ist gefallen: seine Items liegen auf dem Schlachtfeld und müssen erneut eingesammelt werden
func drop_items(mon: Monster) -> void:
	for i in mon._items.size():
		if mon._items[i] != null:
			State.pending_items.append(mon._items[i])
			mon._items[i] = null

func has_items(mon: Monster) -> bool:
	return mon._items.any(func(item): return item != null)

## Erster Platz eines Team-Monsters mit diesem Item ({} wenn keiner)
func find_equipped(id: String, mons: Array) -> Dictionary:
	for mon: Monster in mons:
		for i in mon._items.size():
			if mon._items[i] != null and mon._items[i].id == id:
				return {"mon": mon, "index": i}
	return {}

## Darf das Item im Kampf auf target (null = aufs Kampffeld) gezogen werden?
func battle_target_ok(item: Dictionary, target: Monster) -> bool:
	match use_of(item):
		USE_ENEMY:
			# den finalen Boss kann man nicht fangen, also auch kein Netz werfen
			return target != null and target.is_alive() and State.enemy_mons.has(target) \
				and (item.id != "net" or not State.is_final_boss)
		USE_ALLY:
			return target != null and target.is_alive() and State.mons.has(target)
		USE_FIELD:
			# Bannsiegel nur, wenn es Boss-Relikte gibt
			return item.id != "ban_seal" or not BossRelics.active.is_empty()
	return false

## Item verbraucht
func consume(slot: Dictionary) -> void:
	set_at(slot, null)
	items_changed.emit()

# ─────────────────────────
# Wirkungen, die nicht am Kampf hängen (der Rest steht in battle.gd _use_item)

## Spiegelscherbe: der Angreifer bekommt Schaden zurück, ohne Schilde (wie Magische Dornen)
func reflect_hit(attacker: Monster, target: Monster, damage: float) -> void:
	if damage <= 0 or not attacker.is_alive():
		return
	damage = Tutorial.cap_damage(attacker, damage)
	attacker._last_hit_by = target
	if State.mons.has(attacker) and roundi(attacker.hp() - attacker._lost_hp - damage) <= 0:
		State.record_own_faint(attacker, target, {"name": "ITEM_MIRROR_SHARD"}, damage, 1.0)
	Events.monster_effect_text.emit(attacker, tr("ITEM_MIRROR_SHARD") + " -%d" % roundi(damage), EFFECT_COLOR)
	attacker._lost_hp += damage
