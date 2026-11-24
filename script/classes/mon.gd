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
# Helfer des Endboss-Relikts Buddy: nur für einen Kampf, nicht fangbar, keine Beute
var _minion: bool = false
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
# Schilde fangen Schaden ab (physisch und magisch), bis sie aufgebraucht sind oder der Wirker wieder am Zug ist.
# Einträge {"amount": float, "source": Monster}; source == null = Schild zu Kampfbeginn (Schildrune), hält die erste Runde.
# Schilde desselben Wirkers laufen gleichzeitig ab und liegen daher in einem Eintrag (add_shield).
# Stirbt der Wirker, kommt sein Zug nie wieder: dann fällt der Schild zu Beginn des nächsten eigenen Zuges weg (start_turn).
var _shields: Array = []
## Wie viele Züge bis ein Schild dieses Wirkers abläuft (source, holder) -> int, gesetzt von battle.gd (Turn Wheel).
## Damit verbraucht Schaden zuerst den Schild, der am frühesten abläuft. Ohne Kampf zählt die Reihenfolge des Hinzufügens.
static var shield_expiry: Callable
# Spiegelscherbe: Treffer werfen einen Anteil des Schadens zurück, Einträge {"share": float, "source": Monster},
# laufen ab wie Schilde (bis der Wirker wieder am Zug ist)
var _reflects: Array = []
# Markierungen durch One-Way-Items im Kampf: "bait" = +Fangchance (0..1), "blood" = Schadensfaktor des nächsten Treffers
var _item_marks: Dictionary = {}
# Ausgerüstete One-Way-Items (Items), zwei Plätze, null = leer. Gehören zum Run, nicht zum Kampf.
var _items: Array = [null, null]
# Buffs: Stat-Key (wie bei _gems) -> {"factor": 0.3 = +30 %, "turns": übrige eigene Züge}
var _buffs: Dictionary = {}
# Schwächungen (ElementEffects): Quelle -> {"stat": Stat-Key, "factor": 0.2 = -20 %, "turns": übrige eigene Züge, -1 = bis Kampfende}.
# Nach Quelle getrennt, damit z. B. Staub (kurz) und Verbrennung (dauerhaft) auf Angriff sich nicht gegenseitig überschreiben.
var _debuffs: Dictionary = {}
# Statuseffekte bis Kampfende (ElementEffects): "poison"/"burn"/"paralysis" -> {"stacks": Anzahl, "from": Verursacher,
# "power": Stärke-Faktor der stärksten Karte, die ihn ausgelöst hat (effect_power)}
var _statuses: Dictionary = {}
# Aufladungen (Extra "charge"): "physical"/"magic" -> +Anteil Schaden für den nächsten Angriff dieser Art, danach weg
var _charges: Dictionary = {}
# Sonder-Verstärkungen (Skills "boon", siehe Skills.add_boon): Art -> {"value": float, "turns": übrige eigene Züge
# (+1 wie bei Buffs), -1 = bis verbraucht oder Kampfende}. Arten: "crit_next" (nächster Treffer kritisch, +value % Schaden),
# "crit" (alle Treffer kritisch), "leech" (Lebensraub value %), "extra_moves" (+value Aktionen pro Zug),
# "taunt" (zieht die Einzelangriffe der Gegner auf sich)
var _boons: Dictionary = {}
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
	_shields = []
	_reflects = []
	_item_marks = {}
	_buffs = {}
	_debuffs = {}
	_statuses = {}
	_charges = {}
	_boons = {}
	_intent = []
	_relic_state = {}
	for skill in _skills:
		skill.erase("_cooldown_left")
	Events.monster_status_changed.emit(self)

# Beginn eines eigenen Zuges (eigene Monster und Gegner): Abklingzeiten und Buffs zählen herunter.
# Die eigenen Schilde und die anderer Monster dieses Wirkers sind schon abgelaufen (battle.gd ruft vorher
# expire_from für alle Monster auf). Hier fallen nur noch Schilde weg, deren Wirker nicht mehr kämpft.
func start_turn() -> void:
	_shields = _shields.filter(func(entry): return entry.source == null or _still_fighting(entry.source))
	_reflects = _reflects.filter(func(entry): return _still_fighting(entry.source))
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
	for key in _boons.keys():
		if _boons[key].turns < 0:
			continue
		_boons[key].turns -= 1
		if _boons[key].turns <= 0:
			_boons.erase(key)
	Events.monster_status_changed.emit(self)

## Summe aller Schilde
func shield() -> float:
	var total := 0.0
	for entry in _shields:
		total += entry.amount
	return total

## Schild von source (null = dieses Monster selbst): hält, bis source wieder am Zug ist
func add_shield(amount: float, source: Monster = null) -> void:
	if amount <= 0:
		return
	_add_shield_entry(amount, self if source == null else source)

## Schild zu Kampfbeginn (Schildrune): hält die ganze erste Runde, egal wer wann am Zug ist (expire_start_shields)
func add_start_shield(amount: float) -> void:
	if amount > 0:
		_add_shield_entry(amount, null)

func _add_shield_entry(amount: float, source: Monster) -> void:
	for entry in _shields:
		if entry.source == source:
			entry.amount += amount
			Events.monster_status_changed.emit(self)
			return
	_shields.append({"amount": amount, "source": source})
	Events.monster_status_changed.emit(self)

## caster ist wieder am Zug: seine Schilde und Spiegelungen auf diesem Monster laufen ab
func expire_from(caster: Monster) -> void:
	var before := _shields.size() + _reflects.size()
	_shields = _shields.filter(func(entry): return entry.source != caster)
	_reflects = _reflects.filter(func(entry): return entry.source != caster)
	if _shields.size() + _reflects.size() != before:
		Events.monster_status_changed.emit(self)

## Die erste Runde ist vorbei: Schilde zu Kampfbeginn laufen ab
func expire_start_shields() -> void:
	expire_from(null)

## Steht source noch lebend im Kampf? (gefangene Gegner stehen nicht mehr in enemy_mons)
func _still_fighting(source: Monster) -> bool:
	return source != null and source.is_alive() and (State.mons.has(source) or State.enemy_mons.has(source))

# Zieht den Schaden von den Schilden ab (sie blocken physische und magische Angriffe) und liefert, was durchkommt.
# Zuerst wird der Schild verbraucht, der am frühesten abläuft (shield_expiry).
func absorb_damage(damage: float) -> float:
	if _shields.is_empty() or damage <= 0:
		return damage
	var order := _shields.duplicate()
	if shield_expiry.is_valid():
		var holder := self
		order.sort_custom(func(a, b): return shield_expiry.call(a.source, holder) < shield_expiry.call(b.source, holder))
	var left := damage
	for entry in order:
		var blocked := minf(entry.amount, left)
		entry.amount -= blocked
		left -= blocked
		if left <= 0:
			break
	_shields = _shields.filter(func(entry): return entry.amount > 0)
	Events.monster_status_changed.emit(self)
	return left

## Spiegelscherbe: Treffer werfen share des Schadens zurück, bis source wieder am Zug ist
func add_reflect(share: float, source: Monster) -> void:
	_reflects = _reflects.filter(func(entry): return entry.source != source)
	_reflects.append({"share": share, "source": source})
	Events.monster_status_changed.emit(self)

## Anteil des Schadens, der zum Angreifer zurückprallt (mehrere Spiegelungen zählen nicht doppelt, die stärkste gilt)
func reflect_share() -> float:
	var share := 0.0
	for entry in _reflects:
		share = maxf(share, entry.share)
	return share

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
	return not _buffs.is_empty() or not _charges.is_empty() or not _boons.is_empty()

# Erneutes Verleihen derselben Sonder-Verstärkung stapelt nicht, sondern nimmt den größeren Wert und die längere Dauer.
func add_boon(kind: String, value: float, turns: int) -> void:
	var old: Dictionary = _boons.get(kind, {})
	var old_turns: int = old.get("turns", 0)
	var new_turns := -1 if turns < 0 or old_turns < 0 else maxi(turns, old_turns)
	_boons[kind] = {"value": maxf(value, old.get("value", 0.0)), "turns": new_turns}
	Events.monster_status_changed.emit(self)

func has_boon(kind: String) -> bool:
	return _boons.has(kind)

func boon_value(kind: String) -> float:
	return _boons.get(kind, {}).get("value", 0.0)

func consume_boon(kind: String) -> void:
	if _boons.erase(kind):
		Events.monster_status_changed.emit(self)

# Aufladung für den nächsten Angriff dieser Art ("physical"/"magic"), erneutes Aufladen nimmt den größeren Wert
func add_charge(kind: String, factor: float) -> void:
	_charges[kind] = maxf(factor, _charges.get(kind, 0.0))
	Events.monster_status_changed.emit(self)

func charge(kind: String) -> float:
	return _charges.get(kind, 0.0)

func consume_charge(kind: String) -> void:
	if _charges.erase(kind):
		Events.monster_status_changed.emit(self)

## Geschwächt: Schwächung oder Statuseffekt (für Extras wie "bonus_vs_weakened")
func is_weakened() -> bool:
	return is_debuffed() or not _statuses.is_empty()

## Anteil der verbleibenden KP (1.0 = voll)
func hp_share() -> float:
	var max_hp: float = hp()
	return (max_hp - _lost_hp) / max_hp if max_hp > 0 else 0.0

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
	# Rückenwind & Co.: zusätzliche Aktionen für ein paar eigene Züge (Sonder-Verstärkung "extra_moves")
	_computed_moves = Relics.modify("moves", _initial_moves + _upgrades, self) + roundi(boon_value("extra_moves"))

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
	# Werte-Passive im Team (z. B. +6 % KP für jedes Monster im Team) kommen obendrauf
	# KP-Multiplikator aus dem Debug-Menü (Schadensformel) steuert die Kampflänge, Standard 1
	return (_base_stat("hp") * DebugSettings.hp_scale() + gem_bonus("hp")) * Skills.passive_stat_factor(self, "hp")

# Werte: (Grundwert + Edelsteine) x Buffs/Schwächungen x Werte-Passive im Team
func attack():
	return _stat_with_bonuses("atk")

func defense():
	return _stat_with_bonuses("def")

func s_attack():
	return _stat_with_bonuses("s_atk")

func speed():
	return _stat_with_bonuses("speed")

func _stat_with_bonuses(stat: String) -> float:
	return (_base_stat(stat) + gem_bonus(stat)) * buff_factor(stat) * Skills.passive_stat_factor(self, stat)

func best():
	return _best_points

## tot, sobald die HP-Anzeige (gerundet) 0 zeigt
func is_alive() -> bool:
	return roundi(hp() - _lost_hp) > 0

# Wert aus Stufe und Basiswerten, ohne Edelsteine und Buffs.
# Die Reserve wird erst hier verrechnet: gespeicherte Eier bleiben gültig und Änderungen im Debug-Menü wirken sofort.
func _base_stat(stat: String) -> float:
	# jede weitere Stufe bringt so viel wie Stufe 1, skaliert mit dem Growth aus dem Debug-Menü (Standard = Faktor 1)
	# und dem Stufen-Sockel der Schadensformel (Standard 0 = linear)
	return growth_per_level(stat) * DebugSettings.level_scale(_level)

## Zuwachs eines Werts pro Stufe (Wert auf Stufe 1): Growth-Anteil mal Punkte pro Stufe, zwischen Arten vergleichbar
func growth_per_level(stat: String) -> float:
	var share := DebugSettings.effective_share(stat, _growth[stat])
	return share * Helper.points_per_level(_best_points) * STAT_SCALE

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

## Höchstens so viele Elemente kann ein Monster haben (Dreier-Kombi). Chaos (alle vier) bleibt dem Endboss vorbehalten,
## der es schon als Art-Element mitbringt. Spieler müssen sich so für einen Dreier-Pfad entscheiden.
const MAX_ELEMENTS := 3

## Kann das Monster dieses Element noch annehmen? (noch nicht da und danach höchstens MAX_ELEMENTS)
func can_gain_element(element: int) -> bool:
	return not ColorMap.has_element(_type, element) and Map.count_elements(_type | element) <= MAX_ELEMENTS

func gain_element(element: int) -> void:
	if not can_gain_element(element):
		return
	_type = ColorMap.add_element(_type, element)
	_gained_elements |= element
	# Meilensteine "neues Element" / "Chaos" des Start-Monsters
	if self == State.starter:
		Skills.check_milestones()

# Außerhalb des Kampfes aufrufen, das Monster muss schon wieder im Team stehen (passive KP-Boni zählen mit).
func revive(share: float) -> void:
	_revived = true
	_lost_hp = hp() * (1.0 - share)
	# Der Setter wartet auf dieses Signal, ohne Kampf käme es erst beim ersten Treffer des nächsten Kampfes (wie camp_monster.gd)
	Events.damage_animation_done.emit.call_deferred(self)
