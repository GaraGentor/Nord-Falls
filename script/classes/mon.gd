class_name Monster

var _name: String
var _type: int
var _sub_type: int

var _best_points: int = 500
# Multipliziert alle Werte, damit Schaden (ceilf) und KP (roundi) auch auf niedriger Stufe fein genug abgestuft sind
const STAT_SCALE := 8.0

var _growth: Growth

var _level: int
var _level_progress: int = 0
var _ep: int = 5
var _upgrades: int = 0
# Key aus Skills.BOUNTIES, wenn dieses wilde Monster ein Kopfgeld-Monster ist, sonst ""
var _bounty: String = ""
# Gegner aus einem Boss-Kampf (Biom-Boss oder Boss-Feld)
var _is_boss: bool = false
# Monster, das zuletzt Schaden verursacht hat (entscheidet, wer ein Kopfgeld bekommt)
var _last_hit_by: Monster
var _lost_hp: float = 0:
	set(value):
		_lost_hp = value
		#if _lost_hp < 0:
		#	_lost_hp = -0.1
		#if _lost_hp > hp():
		#	_lost_hp = hp()
		Events.deal_damage_to_monster.emit(self)
		await Events.damage_animation_done
		if not is_alive():
			Events.monster_faints.emit(self)

var _skills: Array
# Aktionen pro Zug ohne Kerkermeister-Verbesserung (jede gesprengte Kette gibt +1, siehe jailer.gd)
const BASE_MOVES := 1
# Gegner würfeln mehr (Map.ENCOUNTERS moves), das verfällt beim Fangen
var _initial_moves: int = BASE_MOVES
var _computed_moves: int = BASE_MOVES:
	set(value):
		_computed_moves = value
		Events.refresh_ui_for_monster.emit()

# Edelstein-Boni für diesen Run: Stat-Key aus STATS in gems.gd -> feste Punkte obendrauf (vor Buffs)
var _gems: Dictionary = {}
# Wie viele Steine dahinterstecken: gleicher Stat-Key -> Anzahl (ein Stein gibt je nach Tiefe unterschiedlich viele Punkte)
var _gem_counts: Dictionary = {}
# Elemente, die der Spieler im Run vergeben hat (Trank, Erbe), als Maske. Nur die lassen sich vererben, Art- und Biom-Elemente nicht.
var _gained_elements: int = 0
# Jedes Monster kann pro Run nur einmal wiederbelebt werden (judgement.gd)
var _revived: bool = false

# Kampf-Zustand, wird zu Beginn jedes Kampfes zurückgesetzt (reset_battle_state)
# Schilde fangen Schaden ab, bis sie aufgebraucht sind oder der nächste eigene Zug beginnt (start_turn): physisch gegen physischen, magisch gegen magischen Schaden
var _shield: float = 0
var _s_shield: float = 0
# Buffs: Stat-Key (wie bei _gems) -> {"factor": 0.3 = +30 %, "turns": übrige eigene Züge}
var _buffs: Dictionary = {}
# Schwächungen (ElementEffects): Quelle -> {"stat": Stat-Key, "factor": 0.2 = -20 %, "turns": übrige eigene Züge, -1 = bis Kampfende}.
# Nach Quelle getrennt, damit z. B. Staub (kurz) und Verbrennung (dauerhaft) auf Angriff sich nicht gegenseitig überschreiben.
var _debuffs: Dictionary = {}
# Statuseffekte bis Kampfende (ElementEffects): "poison"/"burn"/"paralysis" -> {"stacks": Anzahl, "from": Verursacher,
# "power": Stärke-Faktor der stärksten Karte, die ihn ausgelöst hat (effect_power)}
var _statuses: Dictionary = {}
# Buffs und Schwächungen zusammen drücken einen Wert nie unter diesen Faktor
const MIN_STAT_FACTOR := 0.25
# Nur Gegner: geplanter nächster Zug als [{"skill": Dictionary, "target": Monster}], im Kampf als Absicht sichtbar (battle.gd _plan_intent)
var _intent: Array = []
# Zwischenstände der Boss-Relikte dieses Monsters im laufenden Kampf (z. B. Schaden für den Fate-Spiegel), siehe BossRelics
var _relic_state: Dictionary = {}

func _init(level: int, meta_data: Dictionary) -> void:
	## get saved data and apply.
	Events.mon_upgraded.connect(mon_upgraded)

	_name = meta_data.name
	_type = meta_data.initial_type
	var rolled_stats = State.get_mon_stats(_name)
	_best_points = rolled_stats.best_points
	_growth = rolled_stats.growth
	# nie unter der Startstufe (gilt für eigene und wilde Monster)
	_level = maxi(level, State.INITIAL_LEVEL)
	if SaveManager.save_data.monsters.has(_name):
		var filtered = SaveManager.save_data.monsters[_name]
		_upgrades = filtered.upgrade

func mon_upgraded(mon_name):
	if mon_name == _name and SaveManager.save_data.monsters.has(mon_name):
		var filtered = SaveManager.save_data.monsters[mon_name]
		_upgrades = filtered.upgrade

func upgrade_by_level(level: int = 0):
	_level += level
	upgrade_all_skills_by_level(level)
	pass
# TODO: skill klasse erstellen?
func upgrade_all_skills_by_level(level):
	pass
	#for skill in _skills:
	#	skill.value += skill.growth

func upgrade_skill(skill, level):
	pass

func reset_battle_state() -> void:
	_shield = 0
	_s_shield = 0
	_buffs = {}
	_debuffs = {}
	_statuses = {}
	_intent = []
	_relic_state = {}
	for skill in _skills:
		skill.erase("_cooldown_left")
	Events.monster_status_changed.emit(self)

# Beginn eines eigenen Zuges (eigene Monster und Gegner): Abklingzeiten und Buffs zählen herunter,
# Schilde laufen ab (sie halten also genau bis zum nächsten eigenen Zug).
func start_turn() -> void:
	_shield = 0
	_s_shield = 0
	for skill in _skills:
		Skills.tick_cooldown(skill)
	for stat in _buffs.keys():
		_buffs[stat].turns -= 1
		if _buffs[stat].turns <= 0:
			_buffs.erase(stat)
	for key in _debuffs.keys():
		if _debuffs[key].turns < 0:
			continue
		_debuffs[key].turns -= 1
		if _debuffs[key].turns <= 0:
			_debuffs.erase(key)
	Events.monster_status_changed.emit(self)

func add_shield(amount: float, physical: bool) -> void:
	if physical:
		_shield += amount
	else:
		_s_shield += amount
	Events.monster_status_changed.emit(self)

# Zieht den Schaden vom passenden Schild ab und liefert, was durchkommt.
# shield_cost: so viel Schild kostet jeder abgefangene Schadenspunkt (Magma: 2, siehe ElementEffects.shield_cost).
func absorb_damage(damage: float, physical: bool, shield_cost := 1.0) -> float:
	var shield = _shield if physical else _s_shield
	var blocked = minf(shield / shield_cost, damage)
	if blocked <= 0:
		return damage
	if physical:
		_shield = maxf(_shield - blocked * shield_cost, 0.0)
	else:
		_s_shield = maxf(_s_shield - blocked * shield_cost, 0.0)
	Events.monster_status_changed.emit(self)
	return damage - blocked

# Erneutes Buffen desselben Werts stapelt nicht, sondern frischt Stärke und Dauer auf.
func add_buff(stat: String, factor: float, turns: int) -> void:
	_buffs[stat] = {"factor": maxf(factor, _buffs.get(stat, {}).get("factor", 0.0)), "turns": turns}
	Events.monster_status_changed.emit(self)

func buff_factor(stat: String) -> float:
	var factor: float = 1.0 + _buffs.get(stat, {}).get("factor", 0.0)
	for debuff in _debuffs.values():
		if debuff.stat == stat:
			factor -= debuff.factor
	return maxf(factor, MIN_STAT_FACTOR)

func is_buffed() -> bool:
	return not _buffs.is_empty()

# Erneutes Schwächen aus derselben Quelle stapelt nicht, sondern frischt Stärke und Dauer auf (turns -1 = bis Kampfende).
func add_debuff(key: String, stat: String, factor: float, turns: int) -> void:
	var old: Dictionary = _debuffs.get(key, {})
	var old_turns: int = old.get("turns", 0)
	var new_turns := -1 if turns < 0 or old_turns < 0 else maxi(turns, old_turns)
	_debuffs[key] = {"stat": stat, "factor": maxf(factor, old.get("factor", 0.0)), "turns": new_turns}
	Events.monster_status_changed.emit(self)

func is_debuffed() -> bool:
	return not _debuffs.is_empty()

# Statuseffekt bis Kampfende, erneutes Anwenden erhöht die Stapel bis max_stacks.
# Die Stärke bleibt die der stärksten Karte, eine schwächere Karte senkt sie nicht.
func add_status(status: String, from: Monster, max_stacks := 1, power := 1.0) -> void:
	var entry: Dictionary = _statuses.get(status, {"stacks": 0, "power": 0.0})
	entry.stacks = mini(entry.stacks + 1, max_stacks)
	entry.power = maxf(entry.power, power)
	entry.from = from
	_statuses[status] = entry
	Events.monster_status_changed.emit(self)

func has_status(status: String) -> bool:
	return _statuses.has(status)

func status_stacks(status: String) -> int:
	return _statuses.get(status, {}).get("stacks", 0)

func status_power(status: String) -> float:
	return _statuses.get(status, {}).get("power", 1.0)

func reset_to_new_round():
	Events.refresh_ui_for_monster.emit()
	print("_upgrades", _upgrades, "_initial_moves", _initial_moves)
	_computed_moves = Relics.modify("moves", _initial_moves + _upgrades, self)

func unlock_skills():
	for skill in _skills:
		skill.scouted = true

# Ei-Attacke, die durch Opfern dieses Monsters freigeschaltet werden kann, sonst {}
func get_unlockable_egg_skill() -> Dictionary:
	for skill in _skills:
		if Skills.is_unlockable_egg_skill(self, skill):
			return skill
	return {}

func hp():
	# passive Skills im Team (z. B. +15 KP) kommen obendrauf
	# KP-Multiplikator aus dem Debug-Menü (Schadensformel) steuert die Kampflänge, Standard 1
	return _base_stat("hp") * DebugSettings.hp_scale() + gem_bonus("hp") + Skills.passive_bonus(self, "hp")

func attack():
	return (_base_stat("atk") + gem_bonus("atk")) * buff_factor("atk")

func defense():
	return (_base_stat("def") + gem_bonus("def")) * buff_factor("def")

func s_attack():
	return (_base_stat("s_atk") + gem_bonus("s_atk")) * buff_factor("s_atk")

func s_defense():
	return (_base_stat("s_def") + gem_bonus("s_def")) * buff_factor("s_def")

func speed():
	return (_base_stat("speed") + gem_bonus("speed")) * buff_factor("speed")

func best():
	return _best_points

## tot, sobald die HP-Anzeige (gerundet) 0 zeigt
func is_alive() -> bool:
	return roundi(hp() - _lost_hp) > 0

# Wert aus Stufe und Basiswerten, ohne Edelsteine und Buffs.
# Die Reserve wird erst hier verrechnet: gespeicherte Eier bleiben gültig und Änderungen im Debug-Menü wirken sofort.
func _base_stat(stat: String) -> float:
	var share := DebugSettings.effective_share(stat, _growth[stat])
	var level_1 := share * Helper.points_per_level(_best_points) * STAT_SCALE
	# jede weitere Stufe bringt so viel wie Stufe 1, skaliert mit dem Growth aus dem Debug-Menü (Standard = Faktor 1)
	# und dem Stufen-Sockel der Schadensformel (Standard 0 = linear)
	return level_1 * DebugSettings.level_scale(_level)

## Durchschnittlicher Wert auf der Stufe dieses Monsters (gleicher Anteil für alle Werte).
## Grundschaden der symmetrischen Schadensformel, damit der Angriff dort nur im Verhältnis zur Verteidigung zählt.
## Mit "feste BST" im Debug-Menü aus einer Referenz-BST statt der eigenen, damit die BST nicht doppelt zählt.
func typical_stat() -> float:
	var bst := DebugSettings.damage_base_bst(_best_points)
	return Helper.points_per_level(bst) * STAT_SCALE * DebugSettings.level_scale(_level) / DebugSettings.STATS.size()

func gem_bonus(stat: String) -> int:
	# der Relikt-Bonus zählt pro Trophäe und wird nicht gespeichert, gilt also auch rückwirkend.
	# Er gehört dem Spieler: Trophäen von Bossen bekommen ihn erst, wenn der Boss gefangen ist.
	var relic_bonus: int = 0 if State.enemy_mons.has(self) else Relics.modify("trophy_bonus", 0)
	return _gems.get(stat, 0) + gem_count(stat) * relic_bonus

func gem_count(stat: String) -> int:
	return _gem_counts.get(stat, 0)

## count > 1: mehrere Steine auf einmal (Erbe eines gefallenen Monsters)
func add_gem(stat: String, bonus: int, count := 1) -> void:
	_gems[stat] = _gems.get(stat, 0) + bonus
	_gem_counts[stat] = gem_count(stat) + count

func gain_element(element: int) -> void:
	_type = ColorMap.add_element(_type, element)
	_gained_elements |= element

# Außerhalb des Kampfes aufrufen, das Monster muss schon wieder im Team stehen (passive KP-Boni zählen mit).
func revive(hp_share: float) -> void:
	_revived = true
	_lost_hp = hp() * (1.0 - hp_share)
	# Der Setter wartet auf dieses Signal, ohne Kampf käme es erst beim ersten Treffer des nächsten Kampfes (wie camp_monster.gd)
	Events.damage_animation_done.emit.call_deferred(self)
