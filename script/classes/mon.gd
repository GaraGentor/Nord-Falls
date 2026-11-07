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
# Nur Gegner: geplanter nächster Zug als [{"skill": Dictionary, "target": Monster}], im Kampf als Absicht sichtbar (battle.gd _plan_intent)
var _intent: Array = []

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
	_intent = []
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
	Events.monster_status_changed.emit(self)

func add_shield(amount: float, physical: bool) -> void:
	if physical:
		_shield += amount
	else:
		_s_shield += amount
	Events.monster_status_changed.emit(self)

# Zieht den Schaden vom passenden Schild ab und liefert, was durchkommt.
func absorb_damage(damage: float, physical: bool) -> float:
	var shield = _shield if physical else _s_shield
	var blocked = minf(shield, damage)
	if blocked <= 0:
		return damage
	if physical:
		_shield -= blocked
	else:
		_s_shield -= blocked
	Events.monster_status_changed.emit(self)
	return damage - blocked

# Erneutes Buffen desselben Werts stapelt nicht, sondern frischt Stärke und Dauer auf.
func add_buff(stat: String, factor: float, turns: int) -> void:
	_buffs[stat] = {"factor": maxf(factor, _buffs.get(stat, {}).get("factor", 0.0)), "turns": turns}
	Events.monster_status_changed.emit(self)

func buff_factor(stat: String) -> float:
	return 1.0 + _buffs.get(stat, {}).get("factor", 0.0)

func is_buffed() -> bool:
	return not _buffs.is_empty()

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
	return _base_stat("hp") + gem_bonus("hp") + Skills.passive_bonus(self, "hp")

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
	return share * _level * Helper.points_per_level(_best_points) * STAT_SCALE

func gem_bonus(stat: String) -> int:
	# der Relikt-Bonus zählt pro Trophäe und wird nicht gespeichert, gilt also auch rückwirkend
	return _gems.get(stat, 0) + gem_count(stat) * Relics.modify("trophy_bonus", 0)

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
