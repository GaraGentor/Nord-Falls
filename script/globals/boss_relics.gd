extends Node

## Boss-Relikte: gehören zum Boss-Kampf (active), nicht zu einem Monster, getrennt von den Relikten
## des Spielers (Relics). Jeder Boss-Kampf würfelt sie schon beim Betreten des Bioms (Map.generate_encounters), auf der
## Karte kreisen sie um den Biom-Boss (BossRelicOrbit), im Kampf (battle.gd) wirken sie für alle lebenden
## Gegner gleich. Ist der letzte Gegner besiegt oder gefangen, zerbrechen sie (BossRelicOverlay), ein
## gefangener Boss behält nur seine Werte, Fähigkeiten und Trophäen. Angezeigt werden sie in der
## Relikt-Leiste am Rand des Kampffelds (BossRelicBar).
##
## Die Wirkungen laufen über den Kampf (battle.gd) und das Turn Wheel (turn_wheel.gd):
## - on_turn_start: Bongos, Fate-Spiegel (nach dem Ablaufen der alten Schilde)
## - silences_round: Mikrofon lässt Züge ausfallen
## - dodges / on_damage_dealt: Nebelmaschine, Heilmösch, Fate-Spiegel, Magische Dornen
## - on_round_started: Glutboden
## - order_for_round: Flinkes Wiesel
## - buddy_due / make_buddy / buddy_gone: Buddy (battle.gd _spawn_buddy)
##
## Endboss-Relikte ("final": true) kommen nur im Endboss-Kampf (random_final_relics), nie in anderen Boss-Kämpfen.

const GemField = preload("res://script/scenes/gems/gems.gd")

## Heilmösch: Anteil des zugefügten Schadens, um den sich der Träger heilt
const HEAL_MOSS_SHARE := 0.2
## Glutboden: Schaden pro Runde an jedem Gegner, Anteil seiner max. KP
const EMBER_FLOOR_SHARE := 0.05
## Bongos: Schild wie ein Block-Skill mit diesem Wert, also (Sp.) Verteidigung x 25 %
const BONGOS_SHIELD_VALUE := 25.0
## Nebelmaschine: Chance, dass ein Angriff auf den Träger verfehlt
const FOG_MISS_CHANCE := 0.2
## Mikrofon: Heilung in stummen Runden, Anteil der fehlenden KP
const MICROPHONE_HEAL_SHARE := 0.1
## Magische Dornen: Anteil des erlittenen Schadens, der zum Angreifer zurückprallt
const THORNS_SHARE := 0.15

## So viele zufällige Relikte hat jeder Boss-Kampf, egal wie viele Bosse
const RELICS_PER_BATTLE := 1
## So viele Endboss-Relikte hat der Endboss-Kampf (aus dem Endboss-Pool, random_final_relics)
const FINAL_RELICS_PER_BATTLE := 1
## Buddy: alle so viele Runden kommt ein Helfer, solange gerade keiner kämpft
const BUDDY_INTERVAL := 3
## Buddy: Stufe des Helfers (zufällig dazwischen), immer 1 Aktion, nicht fangbar
const BUDDY_LEVEL := Vector2i(10, 15)
## Wie oft eine Seltenheit als Boss auftaucht, relativ zueinander (roll_species). Im Vergleich zu einem normalen Feld
## (Map.RARITY_SPAWN_WEIGHTS, 12:6:3:2:1) sind seltenere Arten als Boss deutlich wahrscheinlicher.
## Noch nicht freigeschaltete Seltenheiten (Map.RARITY_UNLOCKS) und solche ohne Arten fallen weg.
const BOSS_RARITY_WEIGHTS := {
	Enums.MON_RARITY.COMMON: 1.0,
	Enums.MON_RARITY.UNCOMMON: 2.0,
	Enums.MON_RARITY.RARE: 4.0,
	Enums.MON_RARITY.EPIC: 3.0,
	Enums.MON_RARITY.LEGENDARY: 2.0,
}
## Chance pro Boss-Kampf und Biom-Tiefe, dass einer der Bosse mythisch ist (Map.roll_boss_enemies),
## nur wenn mythische Arten schon freigeschaltet sind (Map.RARITY_UNLOCKS)
const MYTHIC_BOSS_CHANCE := [0.03, 0.05, 0.08, 0.1, 0.15]

const RELIC_COLOR := Color(1.0, 0.75, 0.3)
## Eigenes "Lebende Pixel"-Material für die Relikt-Bilder, unabhängig von Monmap.LIVING_MATERIAL einstellbar
const RELIC_MATERIAL := preload("res://script/ui/shader/relic_living_material.tres")
const HEAL_COLOR := Color(0.55, 1.0, 0.55)

# var statt const: wie bei Relics bleiben die Einträge erweiterbar (z. B. später um Lambdas)
var RELICS := {
	"heal_moss": {
		"name": "BOSS_RELIC_HEAL_MOSS",
		"description": "BOSS_RELIC_HEAL_MOSS_DESC",
		"icon": "res://assets/boss_relics/heal_moss.png",
		"value": roundi(HEAL_MOSS_SHARE * 100),
	},
	"ember_floor": {
		"name": "BOSS_RELIC_EMBER_FLOOR",
		"description": "BOSS_RELIC_EMBER_FLOOR_DESC",
		"icon": "res://assets/boss_relics/ember_floor.png",
		"value": roundi(EMBER_FLOOR_SHARE * 100),
	},
	"fate_mirror": {
		"name": "BOSS_RELIC_FATE_MIRROR",
		"description": "BOSS_RELIC_FATE_MIRROR_DESC",
		"icon": "res://assets/boss_relics/fate_mirror.png",
		"value": 100,
	},
	"bongos": {
		"name": "BOSS_RELIC_BONGOS",
		"description": "BOSS_RELIC_BONGOS_DESC",
		"icon": "res://assets/boss_relics/bongos.png",
		"value": roundi(BONGOS_SHIELD_VALUE),
	},
	"fog_machine": {
		"name": "BOSS_RELIC_FOG_MACHINE",
		"description": "BOSS_RELIC_FOG_MACHINE_DESC",
		"icon": "res://assets/boss_relics/fog_machine.png",
		"value": roundi(FOG_MISS_CHANCE * 100),
	},
	"swift_weasel": {
		"name": "BOSS_RELIC_SWIFT_WEASEL",
		"description": "BOSS_RELIC_SWIFT_WEASEL_DESC",
		"icon": "res://assets/boss_relics/swift_weasel.png",
		"value": 0,
		"final": true,
	},
	# Platzhalter-Bild, bis es ein eigenes für den Buddy gibt
	"buddy": {
		"name": "BOSS_RELIC_BUDDY",
		"description": "BOSS_RELIC_BUDDY_DESC",
		"icon": "res://assets/boss_relics/bongos.png",
		"value": BUDDY_INTERVAL,
		"final": true,
	},
	"microphone": {
		"name": "BOSS_RELIC_MICROPHONE",
		"description": "BOSS_RELIC_MICROPHONE_DESC",
		"icon": "res://assets/boss_relics/microphone.png",
		"value": roundi(MICROPHONE_HEAL_SHARE * 100),
	},
	"magic_thorns": {
		"name": "BOSS_RELIC_MAGIC_THORNS",
		"description": "BOSS_RELIC_MAGIC_THORNS_DESC",
		"icon": "res://assets/boss_relics/magic_thorns.png",
		"value": roundi(THORNS_SHARE * 100),
	},
}

func get_relic(id: String) -> Dictionary:
	return RELICS.get(id, {})

func description(id: String) -> String:
	var relic := get_relic(id)
	return tr(relic.description).format({"value": relic.value, "min": BUDDY_LEVEL.x, "max": BUDDY_LEVEL.y})

## Endboss-Relikt? Die kommen nur im Endboss-Kampf vor.
func is_final(id: String) -> bool:
	return get_relic(id).get("final", false)

## IDs der normalen Boss-Relikte (Boss-Felder, Biom-Bosse)
func normal_ids() -> Array:
	return RELICS.keys().filter(func(id): return not is_final(id))

## IDs der Endboss-Relikte
func final_ids() -> Array:
	return RELICS.keys().filter(is_final)

# ─────────────────────────
# Relikte des laufenden Kampfs

## IDs aus RELICS, die im laufenden Boss-Kampf wirken. Leer außerhalb von Boss-Kämpfen und nach dem Zerbrechen.
var active: Array = []
## Runde des laufenden Kampfs (battle.gd setzt sie zu Beginn jeder Runde)
var current_round := 0
## Bannsiegel (One-Way-Item): bis einschließlich dieser Runde wirken die Relikte nicht
var banned_until_round := 0
## Buddy: Runde, seit der kein Helfer mehr kämpft (Kampfbeginn = 0, sonst die Runde, in der er fiel)
var buddy_free_since := 0

## Wirkt das Relikt gerade? Aktiv und nicht gebannt.
func works(id: String) -> bool:
	return active.has(id) and not is_banned()

func is_banned() -> bool:
	return current_round <= banned_until_round

## Bannsiegel: die Relikte wirken in dieser und den nächsten rounds - 1 Runden nicht
func ban(rounds: int) -> void:
	banned_until_round = current_round + rounds - 1

## Wirkt das Relikt für dieses Monster? Nur für lebende Gegner (gefangene stehen nicht mehr in State.enemy_mons).
func has(mon: Monster, id: String) -> bool:
	return works(id) and mon != null and mon.is_alive() and State.enemy_mons.has(mon)

## Nimmt die Relikte aus dem Kampf und gibt sie zurück (zum Zerbrechen)
func take_active() -> Array:
	var taken := active
	active = []
	return taken

# ─────────────────────────
# Bosse ausstatten (Map.roll_boss_enemies, battle.gd)

## Art eines Bosses: Seltenheit gewichtet nach BOSS_RARITY_WEIGHTS (mythic: mythisch),
## bevorzugt mit einem Element des aktuellen Bioms
func roll_species(depth: int, mythic := false) -> String:
	# der Endboss (Monmap final_boss) kommt nur über Map.roll_boss_enemies in den letzten Boss-Kampf
	var all = Monmap.mons.filter(func(meta): return not meta.has("bounty_target") and not meta.get("final_boss", false))
	var rarity: int = Enums.MON_RARITY.MYTHIC if mythic else _roll_boss_rarity(depth, all)
	var candidates = all.filter(func(meta): return meta.get("rarity", Enums.MON_RARITY.COMMON) == rarity)
	if candidates.is_empty():
		candidates = all
	var biome: int = State.current_biome()
	var matching = candidates.filter(func(meta): return meta.initial_type & biome)
	return (matching if not matching.is_empty() else candidates).pick_random().name

## Seltenheit eines nicht-mythischen Bosses: nur freigeschaltete Seltenheiten, von denen es Arten gibt
func _roll_boss_rarity(depth: int, species: Array) -> int:
	var rarities = BOSS_RARITY_WEIGHTS.keys().filter(func(rarity):
		return Map.is_rarity_unlocked(rarity, depth, true) \
			and species.any(func(meta): return meta.get("rarity", Enums.MON_RARITY.COMMON) == rarity))
	if rarities.is_empty():
		return Enums.MON_RARITY.RARE
	var weights = rarities.map(func(rarity): return BOSS_RARITY_WEIGHTS[rarity])
	return rarities[Map.pick_weighted_index(range(rarities.size()), weights)]

## Ist in diesem Boss-Kampf einer der Bosse mythisch? (MYTHIC_BOSS_CHANCE, erst nach Freischaltung)
func roll_mythic(depth: int) -> bool:
	return Map.is_rarity_unlocked(Enums.MON_RARITY.MYTHIC, depth) \
		and randf() < MYTHIC_BOSS_CHANCE[clampi(depth, 0, MYTHIC_BOSS_CHANCE.size() - 1)]

## Zufällige Relikte für einen Boss-Kampf, damit kein Boss-Kampf ohne Relikt bleibt. Bevorzugt kommen Relikte, die im
## Biom noch nicht zerbrochen (State.used_boss_relics) und nicht in exclude (schon an andere Kämpfe des Bioms vergeben)
## sind. Reichen die nicht, dürfen sich Relikte im Biom wiederholen (z. B. auf verschiedenen Pfaden).
## Mit einem neuen Biom ist wieder jedes Relikt frei (Map.generate_encounters).
## Endboss-Relikte kommen hier nie vor (random_final_relics).
func random_relics(count := RELICS_PER_BATTLE, exclude: Array = []) -> Array:
	var pool := normal_ids()
	var fresh = pool.filter(func(id): return not State.used_boss_relics.has(id) and not exclude.has(id))
	var repeats = pool.filter(func(id): return not fresh.has(id))
	fresh.shuffle()
	repeats.shuffle()
	return (fresh + repeats).slice(0, count)

## Zufällige Relikte aus dem Endboss-Pool für den Endboss-Kampf (Map.generate_encounters im letzten Biom)
func random_final_relics(count := FINAL_RELICS_PER_BATTLE) -> Array:
	var pool := final_ids()
	pool.shuffle()
	return pool.slice(0, count)

## Die Relikte haben ihren Kampf hinter sich (zerbrochen oder liegen gelassen) und kommen in diesem Biom nur noch,
## wenn keine anderen mehr frei sind
func mark_used(ids: Array) -> void:
	for id in ids:
		if not State.used_boss_relics.has(id):
			State.used_boss_relics.append(id)

## Vorläufig: in Tiefe 1 jede Trophäen-Art 1x, in Tiefe 5 jede 5x
func default_trophies(depth: int) -> Dictionary:
	var trophies := {}
	for stat in GemField.STATS:
		trophies[stat] = depth + 1
	return trophies

## Trophäen auf der niedrigsten Stufe (Stat-Key -> Anzahl), hängen wie beim Spieler direkt am Monster
func add_trophies(mon: Monster, trophies: Dictionary) -> void:
	for stat in trophies:
		var count: int = trophies[stat]
		if count > 0:
			mon.add_gem(stat, DebugSettings.trophy_bonus(0) * count, count)

# ─────────────────────────
# Wirkungen im Kampf

## Zu Beginn jeder Runde: Glutboden trifft einmal alle eigenen Monster.
## Als Verursacher (Kopfgelder, Todesursache) zählt der erste lebende Gegner.
func on_round_started() -> void:
	if not works("ember_floor"):
		return
	var source: Monster = null
	for mon in State.enemy_mons:
		if mon.is_alive():
			source = mon
			break
	if source == null:
		return
	for target in State.mons.filter(func(m: Monster): return m.is_alive()):
		_relic_damage(target, source, ceilf(target.hp() * EMBER_FLOOR_SHARE), "ember_floor")

## Zu Beginn eines eigenen Zuges, nachdem die alten Schilde abgelaufen sind
func on_turn_start(mon: Monster, _round_number: int) -> void:
	if has(mon, "bongos"):
		mon.add_shield(ceilf(mon.defense() * BONGOS_SHIELD_VALUE / 100.0))
		_say(mon, "bongos")
	if has(mon, "fate_mirror"):
		var amount: float = mon._relic_state.get(MIRROR_KEY, 0.0)
		if amount > 0:
			mon.add_shield(amount)
		if mon._relic_state.has(MIRROR_KEY):
			_say(mon, "fate_mirror")
		mon._relic_state.erase(MIRROR_KEY)

## Mikrofon: in ungeraden Runden fallen alle Züge aus
func silences_round(round_number: int) -> bool:
	return round_number % 2 == 1 and works("microphone")

## Statt des ausgefallenen Zuges heilt sich das Monster um einen Teil seiner fehlenden KP
func microphone_turn(mon: Monster) -> void:
	Events.monster_effect_text.emit(mon, tr("BOSS_RELIC_SILENCED"), RELIC_COLOR)
	heal(mon, mon._lost_hp * MICROPHONE_HEAL_SHARE)

## Nebelmaschine: verfehlt dieser Angriff den Träger?
func dodges(target: Monster) -> bool:
	if not has(target, "fog_machine") or randf() >= FOG_MISS_CHANCE:
		return false
	Events.monster_effect_text.emit(target, tr("BOSS_RELIC_MISS"), RELIC_COLOR)
	return true

## Nach jedem Treffer eines Angriffs, hit = Schaden, der durch die Schilde kam
func on_damage_dealt(from: Monster, target: Monster, skill: Dictionary, hit: float, round_number: int) -> void:
	if hit <= 0:
		return
	var physical := Skills.is_physical(skill)
	if has(from, "heal_moss"):
		heal(from, hit * HEAL_MOSS_SHARE)
	if has(from, "fate_mirror"):
		from._relic_state[MIRROR_KEY] = from._relic_state.get(MIRROR_KEY, 0.0) + hit
	# ungerade Runden prallt physischer, gerade magischer Schaden ab
	if has(target, "magic_thorns") and physical == (round_number % 2 == 1):
		_relic_damage(from, target, ceilf(hit * THORNS_SHARE), "magic_thorns")

## Flinkes Wiesel: in ungeraden Runden als Erster, in geraden als Letzter am Zug
func order_for_round(order: Array, round_number: int) -> Array:
	for mon in order.filter(func(m: Monster): return has(m, "swift_weasel")):
		order.erase(mon)
		if round_number % 2 == 1:
			order.push_front(mon)
		else:
			order.push_back(mon)
	return order

## Buddy: kommt in dieser Runde ein neuer Helfer? Alle BUDDY_INTERVAL Runden, solange gerade keiner kämpft.
func buddy_due(round_number: int) -> bool:
	if not works("buddy"):
		return false
	if State.enemy_mons.any(func(m: Monster): return m._minion and m.is_alive()):
		return false
	return round_number - buddy_free_since >= BUDDY_INTERVAL

## Der Helfer fiel: ab dieser Runde läuft die Wartezeit bis zum nächsten
func buddy_gone(round_number: int) -> void:
	buddy_free_since = round_number

## Ein Helfer: wildes Monster des Bioms auf niedriger Stufe (BUDDY_LEVEL), immer 1 Aktion, nicht fangbar
func make_buddy() -> Monster:
	var buddy: Monster = Helper.generate_mons({"count": 1})[0]
	buddy._level = randi_range(BUDDY_LEVEL.x, BUDDY_LEVEL.y)
	buddy._initial_moves = 1
	buddy._minion = true
	buddy._bounty = ""
	buddy.reset_battle_state()
	return buddy

func heal(mon: Monster, amount: float) -> void:
	var healed := minf(roundf(amount), mon._lost_hp)
	if healed < 1.0:
		return
	Events.monster_effect_text.emit(mon, "+%d" % roundi(healed), HEAL_COLOR)
	mon._lost_hp -= healed

## Schicksalsspiegel: gesammelter Schaden, der im nächsten Zug zum Schild wird
const MIRROR_KEY := "mirror"

func _say(mon: Monster, id: String) -> void:
	Events.monster_effect_text.emit(mon, tr(get_relic(id).name), RELIC_COLOR)

## Schaden durch ein Relikt, ohne Schilde. Zählt wie ein Treffer von from (Kopfgelder, Todesursache).
func _relic_damage(target: Monster, from: Monster, damage: float, id: String) -> void:
	if damage <= 0 or not target.is_alive():
		return
	target._last_hit_by = from
	if State.mons.has(target) and roundi(target.hp() - target._lost_hp - damage) <= 0:
		State.record_own_faint(target, from, {"name": get_relic(id).name}, damage, 1.0)
	Events.monster_effect_text.emit(target, tr(get_relic(id).name) + " -%d" % roundi(damage), RELIC_COLOR)
	target._lost_hp += damage
