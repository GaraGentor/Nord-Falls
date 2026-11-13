extends Node

## Element-Effekte: Kombi-Elemente geben ihren Skills einen Zusatzeffekt (siehe balancing_plan.txt).
## Ausschlaggebend ist das Element des Skills (skill.nature), nicht das des Monsters. Grundelemente haben keinen Effekt.
##
## Zweier-Kombis, drei Spiegelpaare (Gegner schwächen <-> sich selbst stärken), wirken EFFECT_TURNS Züge:
##   Tempo:   Dampf (Ziel langsamer)        <-> Blitz (Wirker schneller)
##   Schilde: Magma (zieht Schilde doppelt ab) <-> Eis (Wirker bekommt Frostpanzer aus dem Schaden)
##   Angriff: Staub (Ziel schwächer)        <-> Schlamm (Wirker stärker)
## Dreier-Kombis, bis Kampfende: Sumpf = Gift, Aschesturm = Verbrennung, Gewitter = Paralyse,
## Vulkan = Chance auf doppelte Wirkung. Chaos: höherer Element-Faktor gegen alle Nicht-Chaos-Ziele.
##
## Schlummernde Skills (Skills.effective_skill, "_dormant") haben keinen Effekt, erst wenn sie erwacht sind.
## Passive "effect_chance" des Wirkers (z. B. Permafrost) erhöhen die Auslösechance (effect_chance mit from).
##
## Alle Werte stehen hier, damit das Balancing an einer Stelle passiert.
##
## Einzelne Karten können die Werte ihres Elements anpassen (optionale Felder im Skill, ohne sie gilt 1.0):
##   "effect_chance": Chance, dass der Effekt beim Ausspielen auslöst (pro getroffenem Ziel bzw. einmal für den Wirker).
##   "effect_power":  Faktor auf die Stärke: Prozente, Gift-/Verbrennungsschaden, Lähmungs- und Vulkan-Chance,
##                    Magma-Mehrabzug.
## Beispiel: _with(_egg_skill(...), {"effect_chance": 0.5, "effect_power": 1.5}) = schwächere Karte, Effekt seltener,
## dafür 1,5x so stark. Magma löst immer aus (sonst stimmt die Schadensvorschau nicht), dort zählt nur effect_power.
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
## Blitz / Dampf: Initiative +/-
const SPEED_FACTOR := 0.2
## Schlamm / Staub: Angriff und Sp. Angriff +/-
const ATTACK_FACTOR := 0.2
## Magma: so viel Schild kostet jeder abgefangene Schadenspunkt
const MAGMA_SHIELD_COST := 2.0
## Eis: Anteil des verursachten Schadens, der als Schild zurückkommt
const ICE_SHIELD_SHARE := 0.25
## Sumpf: Gift-Schaden pro Stapel (Anteil der max. KP) vor jedem Zug des Ziels
const POISON_SHARE := 0.03
const POISON_MAX_STACKS := 5
## Aschesturm: Verbrennung nach jedem Zug des Ziels (Anteil der max. KP) und dauerhaft weniger Angriff
const BURN_SHARE := 0.06
const BURN_ATTACK_FACTOR := 0.15
## Gewitter: Chance zu Zugbeginn, betäubt zu sein (der Zug endet sofort)
const PARALYSIS_CHANCE := 0.2
## Vulkan: Chance, dass der Skill ein zweites Mal wirkt
const VOLCANO_CHANCE := 0.15
## Chaos: Zuschlag auf den Element-Faktor gegen alle Nicht-Chaos-Ziele
const CHAOS_BONUS := 0.25

## Schlüssel pro Element: Übersetzung EFFECT_<KEY>_DESC
const EFFECT_KEYS := {
	LIGHTNING: "LIGHTNING", STEAM: "STEAM", MUD: "MUD", DUST: "DUST", MAGMA: "MAGMA", ICE: "ICE",
	SWAMP: "SWAMP", ASH_STORM: "ASH_STORM", THUNDERSTORM: "THUNDERSTORM", VOLCANO: "VOLCANO", CHAOS: "CHAOS",
}

## Statuseffekte bis Kampfende (Monster._statuses)
const POISON := "poison"
const BURN := "burn"
const PARALYSIS := "paralysis"
const STATUS_LABELS := {POISON: "STATUS_POISON", BURN: "STATUS_BURN", PARALYSIS: "STATUS_PARALYSIS"}
const STATUS_COLORS := {POISON: Color(0.6, 0.9, 0.3), BURN: Color(1.0, 0.5, 0.2), PARALYSIS: Color(1.0, 0.9, 0.3)}
const DEBUFF_COLOR := Color(1.0, 0.45, 0.4)
const ERUPTION_COLOR := Color(1.0, 0.35, 0.15)

# ─────────────────────────
# Auslösen beim Ausspielen (battle.gd _use_skill)

## Pro getroffenem Gegner, nach dem Schaden: Schwächungen und Statuseffekte aufs Ziel.
func on_hit(from: Monster, target: Monster, skill: Dictionary) -> void:
	if not Skills.is_damage_skill(skill) or not target.is_alive() or not _triggers(skill, from):
		return
	var power := effect_power(skill)
	match skill.nature:
		STEAM:
			target.add_debuff("steam", "speed", SPEED_FACTOR * power, EFFECT_TURNS + 1)
			Events.status_vfx.emit(target, "debuff")
		DUST:
			target.add_debuff("dust_atk", "atk", ATTACK_FACTOR * power, EFFECT_TURNS + 1)
			target.add_debuff("dust_s_atk", "s_atk", ATTACK_FACTOR * power, EFFECT_TURNS + 1)
			Events.status_vfx.emit(target, "debuff")
		SWAMP:
			_apply_status(target, POISON, from, power, POISON_MAX_STACKS)
		ASH_STORM:
			_apply_status(target, BURN, from, power)
			target.add_debuff("burn", "atk", BURN_ATTACK_FACTOR * power, -1)
		THUNDERSTORM:
			_apply_status(target, PARALYSIS, from, power)

## Einmal pro Einsatz, nach allen Treffern: Verstärkungen für den Wirker.
## Buffs zählen zu Beginn jedes eigenen Zuges herunter, +1 für den laufenden Zug.
func on_cast(from: Monster, skill: Dictionary, dealt: float) -> void:
	if not from.is_alive() or not skill.nature in [LIGHTNING, MUD, ICE] or not _triggers(skill, from):
		return
	var power := effect_power(skill)
	match skill.nature:
		LIGHTNING:
			from.add_buff("speed", SPEED_FACTOR * power, EFFECT_TURNS + 1)
			Events.status_vfx.emit(from, "buff")
		MUD:
			from.add_buff("atk", ATTACK_FACTOR * power, EFFECT_TURNS + 1)
			from.add_buff("s_atk", ATTACK_FACTOR * power, EFFECT_TURNS + 1)
			Events.status_vfx.emit(from, "buff")
		ICE:
			if dealt > 0:
				from.add_shield(ceilf(dealt * ICE_SHIELD_SHARE * power), Skills.is_physical(skill))

## Vulkan: wirkt der Skill diesmal doppelt?
## from: Wirker, seine Passive "effect_chance" machen den Ausbruch wahrscheinlicher
func rolls_eruption(skill: Dictionary, from: Monster = null) -> bool:
	return skill.nature == VOLCANO and is_active(skill) and randf() < effect_chance(skill, from) * VOLCANO_CHANCE * effect_power(skill)

## Magma: so viel Schild kostet jeder abgefangene Schadenspunkt (auch in der Absichten-Vorschau)
func shield_cost(skill: Dictionary) -> float:
	if skill.get("nature", 0) != MAGMA or not is_active(skill):
		return 1.0
	return 1.0 + (MAGMA_SHIELD_COST - 1.0) * effect_power(skill)

## Chaos: Zuschlag auf den Element-Faktor (Skills.element_multiplier). Kennt nur das Element, nicht die Karte,
## daher gilt hier immer der Standardwert.
func chaos_bonus(skill_nature: int, target_type: int) -> float:
	return CHAOS_BONUS if skill_nature == CHAOS and target_type != CHAOS else 0.0

## Kartenwerte (siehe oben), ohne Feld 1.0.
## from: Wirker, seine Passive "effect_chance" (Skills) erhöhen die Chance um ihren Wert in Prozent (höchstens 100 %)
func effect_chance(skill: Dictionary, from: Monster = null) -> float:
	var chance: float = skill.get("effect_chance", 1.0)
	if from != null:
		chance *= 1.0 + Skills.own_passive_sum(from, "effect_chance") / 100.0
	return minf(chance, 1.0) if skill.get("nature", 0) != VOLCANO else chance

func effect_power(skill: Dictionary) -> float:
	return skill.get("effect_power", 1.0)

## Schlummernde Skills wirken ohne Element-Effekt
func is_active(skill: Dictionary) -> bool:
	return not skill.get("_dormant", false)

func _triggers(skill: Dictionary, from: Monster = null) -> bool:
	return is_active(skill) and randf() < effect_chance(skill, from)

func _apply_status(target: Monster, status: String, from: Monster, power: float, max_stacks := 1) -> void:
	var is_new := not target.has_status(status)
	target.add_status(status, from, max_stacks, power)
	if is_new or max_stacks > 1:
		var text := tr(STATUS_LABELS[status])
		if max_stacks > 1:
			text += " x%d" % target.status_stacks(status)
		Events.monster_effect_text.emit(target, text, STATUS_COLORS[status])

# ─────────────────────────
# Statuseffekte im Zugablauf (battle.gd _on_turn_for / _end_turn)

## Gift, vor dem Zug und vor dem Ablaufen der Schilde: Magie-Schilde helfen nicht, Rüstung fängt es ab.
## Liefert true, wenn Gift gewirkt hat.
func tick_poison(mon: Monster) -> bool:
	if not mon.is_alive() or not mon.has_status(POISON):
		return false
	_status_damage(mon, POISON, POISON_SHARE * mon.status_power(POISON) * mon.status_stacks(POISON), true)
	return true

## Verbrennung, nach dem Zug: Rüstung hilft nicht, Magie-Schilde fangen sie ab.
## Liefert true, wenn die Verbrennung gewirkt hat.
func tick_burn(mon: Monster) -> bool:
	if not mon.is_alive() or not mon.has_status(BURN):
		return false
	_status_damage(mon, BURN, BURN_SHARE * mon.status_power(BURN), false)
	return true

## Paralyse, zu Zugbeginn: ist das Monster diesmal betäubt?
func rolls_paralysis(mon: Monster) -> bool:
	if not mon.is_alive() or not mon.has_status(PARALYSIS) or randf() >= PARALYSIS_CHANCE * mon.status_power(PARALYSIS):
		return false
	Events.monster_effect_text.emit(mon, tr("EFFECT_TEXT_STUNNED"), STATUS_COLORS[PARALYSIS])
	return true

## Statusschaden als Anteil der max. KP, physical = welcher Schild ihn abfängt.
## Zählt wie ein Treffer des Verursachers (Kopfgelder, Todesursache in der Run-Auswertung).
func _status_damage(mon: Monster, status: String, share: float, physical: bool) -> void:
	var full := ceilf(mon.hp() * share)
	var damage := Tutorial.cap_damage(mon, mon.absorb_damage(full, physical))
	var from: Monster = mon._statuses[status].get("from")
	var text := tr(STATUS_LABELS[status]) + " -%d" % roundi(damage)
	Events.monster_effect_text.emit(mon, text, STATUS_COLORS[status])
	if damage <= 0:
		return
	if from != null:
		mon._last_hit_by = from
		if State.mons.has(mon) and roundi(mon.hp() - mon._lost_hp - damage) <= 0:
			State.record_own_faint(mon, from, {"name": STATUS_LABELS[status]}, damage, 1.0)
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
	if mask == MAGMA:
		# Magma löst immer aus
		chance = 1.0
	var text := element_effect_text(mask, power)
	if chance < 1.0:
		text = tr("EFFECT_CHANCE_PREFIX").format({"chance": _percent(chance)}) + text
	return text

## Erklärung des Effekts eines Elements, "" für Grundelemente. power: Stärke-Faktor einer Karte (effect_power)
func element_effect_text(mask: int, power := 1.0) -> String:
	if not EFFECT_KEYS.has(mask):
		return ""
	return tr("EFFECT_%s_DESC" % EFFECT_KEYS[mask]).format({
		"turns": EFFECT_TURNS,
		"speed": _percent(SPEED_FACTOR * power),
		"attack": _percent(ATTACK_FACTOR * power),
		"magma": Helper.format_number(snappedf(1.0 + (MAGMA_SHIELD_COST - 1.0) * power, 0.1)),
		"ice": _percent(ICE_SHIELD_SHARE * power),
		"poison": _percent(POISON_SHARE * power),
		"stacks": POISON_MAX_STACKS,
		"burn": _percent(BURN_SHARE * power),
		"burn_attack": _percent(BURN_ATTACK_FACTOR * power),
		"paralysis": _percent(PARALYSIS_CHANCE * power),
		"volcano": _percent(VOLCANO_CHANCE * power),
		"chaos": String.num(CHAOS_BONUS, 2),
	})

## Prozent für Texte, bei krummen Werten mit einer Nachkommastelle (3 % x 1,5 = 4.5)
func _percent(share: float) -> String:
	return Helper.format_number(snappedf(share * 100, 0.1))
