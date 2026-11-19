extends Node

## Element-Effekte: Kombi-Elemente geben ihren Skills einen Zusatzeffekt.
## Ausschlaggebend ist das Element des Skills (skill.nature), nicht das des Monsters. Grundelemente haben keinen Effekt.
##
## Zweier-Kombis, lösen nur mit einer Chance aus (TRIGGER_CHANCES), Schwächungen halten EFFECT_TURNS Züge:
##   Dampf:   Ziel -20 % Verteidigung (10 %)
##   Staub:   Ziel -20 % Angriff und Sp. Angriff (10 %)
##   Blitz:   Fähigkeiten des Ziels schlagen zu 10 % fehl (10 %)
##   Eis:     Wirker bekommt 25 % des verursachten Schadens als Schild (25 %)
##   Magma:   Treffer geht durch den Schild (20 %)
##   Schlamm: wie Magma (Platzhalter, bis es einen eigenen Effekt gibt)
## Dreier-Kombis: Sumpf = Gift bis Kampfende (10 % pro Treffer auf einen Stapel), Aschesturm = wahrer Zusatzschaden
## (10 %), Gewitter = Paralyse bis Kampfende, Vulkan = Chance auf doppelte Wirkung.
## Chaos: höherer Element-Faktor gegen alle Nicht-Chaos-Ziele.
##
## Schlummernde Skills (Skills.effective_skill, "_dormant") haben keinen Effekt, erst wenn sie erwacht sind.
## Passive "effect_chance" des Wirkers (z. B. Permafrost) erhöhen die Auslösechance (effect_chance mit from).
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
const FAIL_CHANCE := 0.1
## Eis: Chance und Anteil des verursachten Schadens, der als Schild zurückkommt
const ICE_CHANCE := 0.25
const ICE_SHIELD_SHARE := 0.25
## Magma / Schlamm: Chance, dass der Treffer durch den Schild geht
const PIERCE_CHANCE := 0.2
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
	MAGMA: PIERCE_CHANCE, MUD: PIERCE_CHANCE, SWAMP: POISON_CHANCE, ASH_STORM: ASH_CHANCE,
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
const FAIL_COLOR := Color(1.0, 0.9, 0.3)
## Schwächungs-Quelle und Pseudo-Wert für Blitz (Monster._debuffs), zählt nicht auf echte Werte
const FAIL_DEBUFF := "lightning"
const FAIL_STAT := "fail"

# ─────────────────────────
# Auslösen beim Ausspielen (battle.gd _use_skill)

## Pro getroffenem Gegner, nach dem Schaden: Schwächungen, Statuseffekte und Zusatzschaden aufs Ziel.
func on_hit(from: Monster, target: Monster, skill: Dictionary) -> void:
	if not Skills.is_damage_skill(skill) or not target.is_alive() or not skill.nature in [STEAM, DUST, LIGHTNING, SWAMP, ASH_STORM, THUNDERSTORM]:
		return
	if not _triggers(skill, from):
		return
	var power := effect_power(skill)
	match skill.nature:
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
		SWAMP:
			_apply_status(target, POISON, from, power, POISON_MAX_STACKS)
		ASH_STORM:
			_effect_damage(target, from, target.hp() * ASH_SHARE * power, tr("EFFECT_TEXT_ASH"), ASH_COLOR, "EFFECT_TEXT_ASH")
		THUNDERSTORM:
			_apply_status(target, PARALYSIS, from, power)

## Einmal pro Einsatz, nach allen Treffern: Eis gibt dem Wirker einen Schild aus dem Schaden.
func on_cast(from: Monster, skill: Dictionary, dealt: float) -> void:
	if not from.is_alive() or skill.nature != ICE or dealt <= 0 or not _triggers(skill, from):
		return
	from.add_shield(ceilf(dealt * ICE_SHIELD_SHARE * effect_power(skill)))

## Magma / Schlamm: geht dieser Treffer durch den Schild?
func rolls_pierce(skill: Dictionary, from: Monster = null) -> bool:
	return skill.get("nature", 0) in [MAGMA, MUD] and _triggers(skill, from)

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
	return skill.nature == VOLCANO and is_active(skill) and randf() < effect_chance(skill, from) * VOLCANO_CHANCE * effect_power(skill)

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

## Auslösechance des Elements x Kartenwert x Passive des Wirkers, höchstens 100 %
func trigger_chance(skill: Dictionary, from: Monster = null) -> float:
	return minf(TRIGGER_CHANCES.get(skill.get("nature", 0), 1.0) * effect_chance(skill, from), 1.0)

func _triggers(skill: Dictionary, from: Monster = null) -> bool:
	return is_active(skill) and randf() < trigger_chance(skill, from)

func _apply_status(target: Monster, status: String, from: Monster, power: float, max_stacks := 1) -> void:
	var is_new := not target.has_status(status)
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
	_effect_damage(mon, from, mon.hp() * POISON_SHARE * mon.status_power(POISON) * mon.status_stacks(POISON),
		tr(STATUS_LABELS[POISON]), STATUS_COLORS[POISON], STATUS_LABELS[POISON])
	return true

## Paralyse, zu Zugbeginn: ist das Monster diesmal betäubt?
func rolls_paralysis(mon: Monster) -> bool:
	if not mon.is_alive() or not mon.has_status(PARALYSIS) or randf() >= PARALYSIS_CHANCE * mon.status_power(PARALYSIS):
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
	var mask: int = skill.get("nature", 0)
	if not EFFECT_KEYS.has(mask) or mask == CHAOS:
		return element_effect_text(mask)
	var power := effect_power(skill)
	var chance := effect_chance(skill)
	if mask == VOLCANO:
		# bei Vulkan ist die Chance selbst der Effekt
		power *= chance
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
