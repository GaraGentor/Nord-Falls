extends Node

## Element-Effekte: Kombi-Elemente geben ihren Skills einen Zusatzeffekt.
## Ausschlaggebend ist das Element des Skills (skill.nature), nicht das des Monsters. Grundelemente haben keinen Effekt.
##
## Zweier-Kombis, lösen nur mit einer Chance aus (TRIGGER_CHANCES), Schwächungen halten EFFECT_TURNS Züge:
##   Dampf:   Ziel -20 % Verteidigung (10 %)
##   Staub:   Ziel -20 % Angriff und Sp. Angriff (10 %)
##   Blitz:   Fähigkeiten des Ziels schlagen zu 25 % fehl (10 %)
##   Eis:     jedes Monster im Team des Wirkers bekommt 60 % des verursachten Schadens als Schild (25 %)
##   Magma:   Treffer geht durch den Schild, ohne Schild 30 % der Verteidigung des Ziels als Zusatzschaden (20 %)
##   Schlamm: Ziel verliert 1 Aktion im nächsten Zug, nur wenn es noch mindestens 2 hätte (15 %)
## Dreier-Kombis: Sumpf = Gift bis Kampfende (10 % pro Treffer auf einen Stapel), Aschesturm = wahrer Zusatzschaden
## (10 %), Gewitter = Paralyse bis Kampfende, Vulkan = Chance auf doppelte Wirkung.
## Chaos: höherer Element-Faktor gegen alle Nicht-Chaos-Ziele. Hat nur der Endboss (Monster.MAX_ELEMENTS = 3).
##
## Schlummernde Skills (Skills.effective_skill, "_dormant") haben keinen Effekt, erst wenn sie erwacht sind.
## Passive "effect_chance" des Wirkers (z. B. Permafrost) erhöhen die Auslösechance (effect_chance mit from).
##
## Element-Leihgabe (ElementLoan): geliehene Elemente geben dem Skill ein anderes Effekt-Element ("effect_nature"),
## das dann sicher auslöst ("_loaned"). Schaden und Element-Faktor rechnen weiter mit "nature".
##
## Alle Werte stehen hier, damit das Balancing an einer Stelle passiert.
##
## Einzelne Karten können die Werte ihres Elements anpassen (optionale Felder im Skill, ohne sie gilt 1.0):
##   "effect_chance": Faktor auf die Auslösechance (pro getroffenem Ziel bzw. einmal für den Wirker).
##   "effect_power":  Faktor auf die Stärke: Prozente, Gift-/Aschesturm-Schaden, Fehlschlag-, Lähmungs- und Vulkan-Chance.
## Chaos ist ein reiner Element-Zuschlag und nimmt keine Kartenwerte an.
## Bei Vulkan wirken beide: Chance = effect_chance * VOLCANO_CHANCE * effect_power.

const EARTH := Enums.MON_TYPES.EARTH
const FIRE := Enums.MON_TYPES.FIRE
const WATER := Enums.MON_TYPES.WATER
const AIR := Enums.MON_TYPES.AIR

const LIGHTNING := FIRE | AIR
const STEAM := FIRE | WATER
const MUD := EARTH | WATER
const DUST := EARTH | AIR
const MAGMA := EARTH | FIRE
const ICE := AIR | WATER
const SWAMP := EARTH | AIR | WATER
const ASH_STORM := EARTH | AIR | FIRE
const THUNDERSTORM := AIR | WATER | FIRE
const VOLCANO := EARTH | FIRE | WATER
const CHAOS := EARTH | FIRE | WATER | AIR

## Wie viele eigene Züge des betroffenen Monsters Zweier-Effekte halten
const EFFECT_TURNS := 2
## Dampf / Staub: Chance und Schwächung (Dampf: Vert., Staub: Ang. und Sp. Ang.)
const DEBUFF_CHANCE := 0.1
const DEBUFF_FACTOR := 0.2
## Blitz: Chance, dass das Ziel geschwächt wird, und Fehlschlag-Chance seiner Fähigkeiten
const FAIL_TRIGGER_CHANCE := 0.1
const FAIL_CHANCE := 0.25
## Eis: Chance und Anteil des verursachten Schadens, der als Schild zurückkommt (für jedes Monster im Team des Wirkers)
const ICE_CHANCE := 0.25
const ICE_SHIELD_SHARE := 0.6
## Magma: Chance, dass der Treffer durch den Schild geht. Ohne Schild beim Ziel: Zusatzschaden aus dessen Verteidigung
const PIERCE_CHANCE := 0.2
const MELT_SHARE := 0.3
## Schlamm: Chance, dass das Ziel im nächsten Zug 1 Aktion verliert (Monster._mud_debt).
## Nur wenn ihm danach noch mindestens 1 Aktion bleibt (also ab 2 Aktionen pro Zug), stapelt nicht.
const MUD_CHANCE := 0.15
const MUD_MIN_MOVES := 2
## Sumpf: Chance pro Treffer auf einen Stapel Gift, Gift-Schaden pro Stapel (Anteil der max. KP) vor jedem Zug des Ziels
const POISON_CHANCE := 0.1
const POISON_SHARE := 0.03
const POISON_MAX_STACKS := 5
## Aschesturm: Chance pro Treffer auf zusätzlichen wahren Schaden (Anteil der max. KP des Ziels, ignoriert alle Schilde)
const ASH_CHANCE := 0.1
const ASH_SHARE := 0.03
## Gewitter: Chance zu Zugbeginn, betäubt zu sein (der Zug endet sofort)
const PARALYSIS_CHANCE := 0.1
## Vulkan: Chance, dass der Skill ein zweites Mal wirkt
const VOLCANO_CHANCE := 0.15
## Chaos: Zuschlag auf den Element-Faktor gegen alle Nicht-Chaos-Ziele
const CHAOS_BONUS := 0.25

## Auslösechance pro Element (ohne Eintrag: löst immer aus)
const TRIGGER_CHANCES := {
	STEAM: DEBUFF_CHANCE, DUST: DEBUFF_CHANCE, LIGHTNING: FAIL_TRIGGER_CHANCE, ICE: ICE_CHANCE,
	MAGMA: PIERCE_CHANCE, MUD: MUD_CHANCE, SWAMP: POISON_CHANCE, ASH_STORM: ASH_CHANCE,
}

## Schlüssel pro Element: Übersetzung EFFECT_<KEY>_DESC
const EFFECT_KEYS := {
	LIGHTNING: "LIGHTNING", STEAM: "STEAM", MUD: "MUD", DUST: "DUST", MAGMA: "MAGMA", ICE: "ICE",
	SWAMP: "SWAMP", ASH_STORM: "ASH_STORM", THUNDERSTORM: "THUNDERSTORM", VOLCANO: "VOLCANO", CHAOS: "CHAOS",
}

## Statuseffekte bis Kampfende (Monster._statuses)
const POISON := "poison"
const PARALYSIS := "paralysis"
const STATUS_LABELS := {POISON: "STATUS_POISON", PARALYSIS: "STATUS_PARALYSIS"}
const STATUS_COLORS := {POISON: Color(0.6, 0.9, 0.3), PARALYSIS: Color(1.0, 0.9, 0.3)}
const DEBUFF_COLOR := Color(1.0, 0.45, 0.4)
const ERUPTION_COLOR := Color(1.0, 0.35, 0.15)
const ASH_COLOR := Color(1.0, 0.5, 0.2)
const PIERCE_COLOR := Color(1.0, 0.65, 0.3)
const MUD_COLOR := Color(0.75, 0.6, 0.45)
const FAIL_COLOR := Color(1.0, 0.9, 0.3)
## Schwächungs-Quelle und Pseudo-Wert für Blitz (Monster._debuffs), zählt nicht auf echte Werte
const FAIL_DEBUFF := "lightning"
const FAIL_STAT := "fail"

# ─────────────────────────
# Auslösen beim Ausspielen (battle.gd _use_skill)

## Pro getroffenem Gegner, nach dem Schaden: Schwächungen, Statuseffekte und Zusatzschaden aufs Ziel.
func on_hit(from: Monster, target: Monster, skill: Dictionary) -> void:
	var nature := effect_nature(skill)
	if not Skills.is_damage_skill(skill) or not target.is_alive() or not nature in [STEAM, DUST, LIGHTNING, MUD, SWAMP, ASH_STORM, THUNDERSTORM]:
		return
	if not _triggers(skill, from):
		return
	var power := effect_power(skill)
	match nature:
		STEAM:
			target.add_debuff("steam_def", "def", DEBUFF_FACTOR * power, EFFECT_TURNS + 1)
			Events.status_vfx.emit(target, "debuff")
		DUST:
			target.add_debuff("dust_atk", "atk", DEBUFF_FACTOR * power, EFFECT_TURNS + 1)
			target.add_debuff("dust_s_atk", "s_atk", DEBUFF_FACTOR * power, EFFECT_TURNS + 1)
			Events.status_vfx.emit(target, "debuff")
		LIGHTNING:
			target.add_debuff(FAIL_DEBUFF, FAIL_STAT, FAIL_CHANCE * power, EFFECT_TURNS + 1)
			Events.status_vfx.emit(target, "debuff")
		MUD:
			_apply_mud(target)
		SWAMP:
			_apply_status(target, POISON, from, power, POISON_MAX_STACKS)
		ASH_STORM:
			_effect_damage(target, from, target.hp() * ASH_SHARE * power, tr("EFFECT_TEXT_ASH"), ASH_COLOR, "EFFECT_TEXT_ASH")
		THUNDERSTORM:
			_apply_status(target, PARALYSIS, from, power)

## Schlamm: das Ziel verliert 1 Aktion in seinem nächsten Zug, wenn ihm danach noch eine bleibt (stapelt nicht).
## Gegner kürzen ihren schon angekündigten Zug (battle.gd _use_skill ruft danach _trim_intent).
func _apply_mud(target: Monster) -> void:
	if target._mud_debt > 0 or ElementLoan.moves_per_turn(target) - target._loan_debt < MUD_MIN_MOVES:
		return
	target._mud_debt = 1
	Events.monster_effect_text.emit(target, tr("EFFECT_TEXT_MUD"), MUD_COLOR)
	Events.monster_status_changed.emit(target)

## Einmal pro Einsatz, nach allen Treffern: Eis gibt jedem lebenden Monster im Team des Wirkers einen Schild aus dem
## Schaden (auch dem Partner, der das Element geliehen hat). Der Schild hält, bis der Wirker wieder am Zug ist.
func on_cast(from: Monster, skill: Dictionary, dealt: float) -> void:
	if not from.is_alive() or effect_nature(skill) != ICE or dealt <= 0 or not _triggers(skill, from):
		return
	var amount := ceilf(dealt * ICE_SHIELD_SHARE * effect_power(skill))
	var team: Array = State.mons if State.mons.has(from) else State.enemy_mons
	for mon: Monster in team:
		if mon.is_alive():
			mon.add_shield(amount, from)

## Magma: löst der Effekt bei diesem Treffer aus? Mit Schild geht der Treffer durch, ohne gibt es melt_damage dazu.
func rolls_pierce(skill: Dictionary, from: Monster = null) -> bool:
	return effect_nature(skill) == MAGMA and _triggers(skill, from)

## Magma ohne Schild beim Ziel: Zusatzschaden aus der Verteidigung des Ziels (zeigt "Schmelze +X")
func melt_damage(target: Monster, skill: Dictionary) -> float:
	var extra := ceilf(target.defense() * MELT_SHARE * effect_power(skill))
	if extra > 0:
		Events.monster_effect_text.emit(target, tr("EFFECT_TEXT_MELT") + " +%d" % roundi(extra), PIERCE_COLOR)
	return extra

## Zeigt "Durchschlag!" über dem Ziel, wenn es einen Schild hatte
func show_pierce(target: Monster) -> void:
	if target.shield() > 0:
		Events.monster_effect_text.emit(target, tr("EFFECT_TEXT_PIERCE"), PIERCE_COLOR)

## Blitz: schlägt die Fähigkeit dieses Monsters diesmal fehl?
func rolls_fail(mon: Monster) -> bool:
	var chance := 0.0
	for debuff in mon._debuffs.values():
		if debuff.stat == FAIL_STAT:
			chance += debuff.factor
	if chance <= 0.0 or randf() >= chance:
		return false
	Events.monster_effect_text.emit(mon, tr("EFFECT_TEXT_FAILED"), FAIL_COLOR)
	return true

## Vulkan: wirkt der Skill diesmal doppelt?
## from: Wirker, seine Passive "effect_chance" machen den Ausbruch wahrscheinlicher
func rolls_eruption(skill: Dictionary, from: Monster = null) -> bool:
	if effect_nature(skill) != VOLCANO or not is_active(skill):
		return false
	# geliehen (ElementLoan): wirkt sicher doppelt
	return is_loaned(skill) or randf() < effect_chance(skill, from) * eruption_base(skill, from) * effect_power(skill)

## Grund-Chance des Vulkan-Ausbruchs: VOLCANO_CHANCE, eigene Karten-Chance ("eruption_chance", Vulkan Ausbruch)
## und für magische Angriffe mindestens das Passiv "magic_eruption" des Wirkers (True Magi)
func eruption_base(skill: Dictionary, from: Monster = null) -> float:
	var base: float = skill.get("eruption_chance", VOLCANO_CHANCE)
	if from != null and Skills.is_damage_skill(skill) and not Skills.is_physical(skill):
		base = maxf(base, Skills.own_passive_sum(from, "magic_eruption") / 100.0)
	return base

## Chaos: Zuschlag auf den Element-Faktor (Skills.element_multiplier). Kennt nur das Element, nicht die Karte,
## daher gilt hier immer der Standardwert.
func chaos_bonus(skill_nature: int, target_type: int) -> float:
	return CHAOS_BONUS if skill_nature == CHAOS and target_type != CHAOS else 0.0

## Kartenwerte (siehe oben), ohne Feld 1.0.
## from: Wirker, seine Passive "effect_chance" (Skills) erhöhen die Chance um ihren Wert in Prozent
func effect_chance(skill: Dictionary, from: Monster = null) -> float:
	var chance: float = skill.get("effect_chance", 1.0)
	if from != null:
		chance *= 1.0 + Skills.own_passive_sum(from, "effect_chance") / 100.0
	return chance

func effect_power(skill: Dictionary) -> float:
	return skill.get("effect_power", 1.0)

## Schlummernde Skills wirken ohne Element-Effekt
func is_active(skill: Dictionary) -> bool:
	return not skill.get("_dormant", false)

## Element, dessen Effekt der Skill auslöst: sein eigenes oder mit geliehenen Elementen (ElementLoan, "effect_nature")
func effect_nature(skill: Dictionary) -> int:
	return skill.get("effect_nature", skill.get("nature", 0))

## Mit geliehenem Element (ElementLoan): der Effekt löst sicher aus
func is_loaned(skill: Dictionary) -> bool:
	return skill.get("_loaned", false)

## Auslösechance des Elements x Kartenwert x Passive des Wirkers, höchstens 100 %. Geliehen: immer.
func trigger_chance(skill: Dictionary, from: Monster = null) -> float:
	if is_loaned(skill):
		return 1.0
	return minf(TRIGGER_CHANCES.get(effect_nature(skill), 1.0) * effect_chance(skill, from), 1.0)

func _triggers(skill: Dictionary, from: Monster = null) -> bool:
	return is_active(skill) and randf() < trigger_chance(skill, from)

## Statuseffekt aus einer Karte ohne Schaden (Skills.apply_debuff "status"): stacks Stapel auf einmal, normale Stärke
func inflict(target: Monster, status: String, from: Monster, stacks := 1) -> void:
	_apply_status(target, status, from, 1.0, POISON_MAX_STACKS if status == POISON else 1, stacks)

func _apply_status(target: Monster, status: String, from: Monster, power: float, max_stacks := 1, stacks := 1) -> void:
	var is_new := not target.has_status(status)
	for _i in stacks:
		target.add_status(status, from, max_stacks, power)
	if is_new or max_stacks > 1:
		var text := tr(STATUS_LABELS[status])
		if max_stacks > 1:
			text += " x%d" % target.status_stacks(status)
		Events.monster_effect_text.emit(target, text, STATUS_COLORS[status])

# ─────────────────────────
# Statuseffekte im Zugablauf (battle.gd _on_turn_for)

## Gift, vor dem Zug: geht durch alle Schilde. Liefert true, wenn Gift gewirkt hat.
func tick_poison(mon: Monster) -> bool:
	if not mon.is_alive() or not mon.has_status(POISON):
		return false
	var from: Monster = mon._statuses[POISON].get("from")
	_effect_damage(mon, from, mon.hp() * POISON_SHARE * mon.status_power(POISON) * mon.status_stacks(POISON) * poison_factor(from),
		tr(STATUS_LABELS[POISON]), STATUS_COLORS[POISON], STATUS_LABELS[POISON])
	return true

## Sumpffeld (Passiv "poison_power" des Verursachers): Gift wirkt stärker, 1.0 ohne
func poison_factor(from: Monster) -> float:
	return 1.0 if from == null else 1.0 + Skills.own_passive_sum(from, "poison_power") / 100.0

## Chance pro Zug, betäubt zu sein: PARALYSIS_CHANCE, mit Dichte Wolken (Passiv "paralysis_chance" des Verursachers) mehr
func paralysis_chance(mon: Monster) -> float:
	var base := PARALYSIS_CHANCE
	var from: Monster = mon._statuses.get(PARALYSIS, {}).get("from")
	if from != null:
		base = maxf(base, Skills.own_passive_sum(from, "paralysis_chance") / 100.0)
	return base * mon.status_power(PARALYSIS)

## Paralyse, zu Zugbeginn: ist das Monster diesmal betäubt?
func rolls_paralysis(mon: Monster) -> bool:
	if not mon.is_alive() or not mon.has_status(PARALYSIS) or randf() >= paralysis_chance(mon):
		return false
	Events.monster_effect_text.emit(mon, tr("EFFECT_TEXT_STUNNED"), STATUS_COLORS[PARALYSIS])
	return true

## Wahrer Schaden (Gift, Aschesturm): ignoriert alle Schilde.
## Zählt wie ein Treffer des Verursachers (Kopfgelder, Todesursache in der Run-Auswertung, cause = Name dafür).
func _effect_damage(mon: Monster, from: Monster, amount: float, text: String, color: Color, cause: String) -> void:
	var damage := Tutorial.cap_damage(mon, ceilf(amount))
	Events.monster_effect_text.emit(mon, text + " -%d" % roundi(damage), color)
	if damage <= 0:
		return
	if from != null:
		mon._last_hit_by = from
		if State.mons.has(mon) and roundi(mon.hp() - mon._lost_hp - damage) <= 0:
			State.record_own_faint(mon, from, {"name": cause}, damage, 1.0)
	mon._lost_hp += damage

# ─────────────────────────
# Texte

## Effekt-Zeile für Skill-Beschreibungen mit den Werten dieser Karte (effect_chance, effect_power), "" ohne Effekt
func skill_effect_text(skill: Dictionary) -> String:
	# universelle Skills (Element Chaos), Schwächungen ohne Schaden und Passive haben keinen Element-Effekt
	if Skills.is_universal(skill) or Skills.is_debuff_skill(skill) or Skills.is_passive(skill):
		return ""
	var mask := effect_nature(skill)
	if not EFFECT_KEYS.has(mask) or mask == CHAOS:
		return element_effect_text(mask)
	var power := effect_power(skill)
	# geliehen (ElementLoan): löst sicher aus, die Chance im Text deckelt element_effect_text auf 100 %
	var chance := INF if is_loaned(skill) else effect_chance(skill)
	if mask == VOLCANO and is_loaned(skill):
		# die doppelte Wirkung ist sicher: 100 % statt der Vulkan-Chance
		return element_effect_text(mask, 1.0 / VOLCANO_CHANCE)
	if mask == VOLCANO:
		# bei Vulkan ist die Chance selbst der Effekt (eigene Karten-Chance: Vulkan Ausbruch)
		power *= chance * eruption_base(skill) / VOLCANO_CHANCE
		chance = 1.0
	return element_effect_text(mask, power, chance)

## Erklärung des Effekts eines Elements, "" für Grundelemente. power: Stärke-Faktor einer Karte (effect_power),
## card_chance: Faktor einer Karte auf die Auslösechance (effect_chance). Mit Auslösechance davor, wenn sie unter 100 % liegt.
func element_effect_text(mask: int, power := 1.0, card_chance := 1.0) -> String:
	if not EFFECT_KEYS.has(mask):
		return ""
	var text := tr("EFFECT_%s_DESC" % EFFECT_KEYS[mask]).format({
		"turns": EFFECT_TURNS,
		"debuff": _percent(DEBUFF_FACTOR * power),
		"fail": _percent(FAIL_CHANCE * power),
		"ice": _percent(ICE_SHIELD_SHARE * power),
		"melt": _percent(MELT_SHARE * power),
		"poison": _percent(POISON_SHARE * power),
		"stacks": POISON_MAX_STACKS,
		"ash": _percent(ASH_SHARE * power),
		"paralysis": _percent(PARALYSIS_CHANCE * power),
		"volcano": _percent(VOLCANO_CHANCE * power),
		"chaos": String.num(CHAOS_BONUS, 2),
	})
	var chance := minf(TRIGGER_CHANCES.get(mask, 1.0) * card_chance, 1.0)
	if chance < 1.0:
		text = tr("EFFECT_CHANCE_PREFIX").format({"chance": _percent(chance)}) + text
	return text

## Prozent für Texte, bei krummen Werten mit einer Nachkommastelle (3 % x 1,5 = 4.5)
func _percent(share: float) -> String:
	return Helper.format_number(snappedf(share * 100, 0.1))
