extends Node

func deal_damage(props):
	# für Kopfgelder: wer zuletzt getroffen hat, hat das Monster besiegt
	props.mon._last_hit_by = props.from
	var full_damage = calc_damage(props.from, props.mon, props.skill)
	# Blutstein: der nächste Treffer auf dieses Monster macht mehr Schaden, danach ist die Markierung weg
	var blood: float = props.mon._item_marks.get("blood", 0.0)
	if blood > 0.0:
		full_damage = ceilf(full_damage * blood)
		props.mon._item_marks.erase("blood")
		Events.monster_effect_text.emit(props.mon, tr("ITEM_BLOOD_STONE") + " x" + String.num(blood, 1), Items.EFFECT_COLOR)
	reveal_stats_by_hit(props.from, props.mon, props.skill)
	# der Schild fängt den Schaden zuerst ab (physisch und magisch), Magma und Schlamm gehen mit etwas Glück durch
	var absorbed: float = full_damage
	if ElementEffects.rolls_pierce(props.skill, props.from):
		ElementEffects.show_pierce(props.mon)
	else:
		absorbed = props.mon.absorb_damage(full_damage)
	# Übungskampf: niemand geht K.O.
	var damage = Tutorial.cap_damage(props.mon, absorbed)
	# für Element-Effekte, die vom verursachten Schaden abhängen (Eis), siehe battle.gd _use_skill
	props.dealt = props.get("dealt", 0.0) + damage
	props.blocked = props.get("blocked", 0.0) + full_damage - absorbed
	var multiplier = skill_element_multiplier(props.skill, props.mon._type)
	print("lose:" + str(props.skill.value) + ":" + str(damage) + " (Element x" + str(multiplier) + ")")
	Events.monster_hit_with_element.emit(props.mon, damage, multiplier, full_damage - damage)
	var kills: bool = props.mon.is_alive() and roundi(props.mon.hp() - props.mon._lost_hp - damage) <= 0
	if State.mons.has(props.mon) and kills:
		State.record_own_faint(props.mon, props.from, props.skill, damage, multiplier)
	props.mon._lost_hp += damage
	# Spiegelscherbe: ein Anteil des Treffers (vor den Schilden) prallt zum Angreifer zurück
	var reflect: float = props.mon.reflect_share()
	if reflect > 0.0 and props.from != props.mon:
		Items.reflect_hit(props.from, props.mon, ceilf(full_damage * reflect))
	# Passiv "Heilung bei K.O.": der Angreifer heilt sich um einen Anteil seiner max. KP
	if kills and props.from.is_alive():
		var kill_heal := own_passive_sum(props.from, "kill_heal")
		if kill_heal > 0.0:
			heal(props.from, props.from.hp() * kill_heal / 100.0)

# ─────────────────────────
# Schadensformel
# Jeder Skill hat einen festen Schaden (value) und bekommt einen Anteil (scaling) des eigenen Angriffs obendrauf:
# physisch vom Angriff, magisch vom Sp. Angriff. Die Verteidigung des Ziels zählt nicht, nur Schilde fangen Schaden ab.
# Danach wirkt der Element-Faktor, aber nur bei magischen Angriffen (skill_element_multiplier): physische Angriffe
# treffen immer neutral, egal welches Element sie haben.

# Treffer decken Werte auf: trifft man den Gegner, wird seine Verteidigung aufgedeckt,
# trifft er einen selbst, sein (Sp.) Angriff.
func reveal_stats_by_hit(from: Monster, to: Monster, skill: Dictionary) -> void:
	var physical = is_physical(skill)
	if State.mons.has(from) and not State.mons.has(to):
		State.reveal_mon_stat(to._name, "def")
	elif State.mons.has(to) and not State.mons.has(from):
		State.reveal_mon_stat(from._name, "atk" if physical else "s_atk")

func is_physical(skill: Dictionary) -> bool:
	return skill.get("damage_type", Enums.SKILL_DAMAGE_TYPE.PHYSICAL) == Enums.SKILL_DAMAGE_TYPE.PHYSICAL

func calc_damage(from: Monster, to: Monster, skill: Dictionary) -> float:
	# schlummernde Skills schwächer und nur mit den Elementen des Angreifers
	skill = effective_skill(from, skill)
	var physical = is_physical(skill)
	var atk: float = from.attack() if physical else from.s_attack()
	# Passive, Aufladungen und Extras (Jäger, Ausnutzen) wirken als Faktor auf den ganzen Schaden,
	# kritische Treffer (Fokusflamme, Überladung) multiplizieren obendrauf. Der Element-Faktor gilt nur für Magie.
	var factor := damage_factor(from, to, skill) * skill_element_multiplier(skill, to._type) * crit_factor(from)
	return stat_damage(atk, skill.value, skill.get("scaling", 0.0), factor)

# ─────────────────────────
# Kritische Treffer: gibt es nur über Sonder-Verstärkungen, kein Zufall. Darum stehen sie auch in Vorschau und Absichten.
#   "crit_next": der nächste Angriff ist kritisch (danach verbraucht, battle.gd _use_skill)
#   "crit":      alle Angriffe sind kritisch, solange die Verstärkung hält
# Der Wert der Verstärkung ist der Zusatzschaden in Prozent (50 = x1,5). Beide zusammen zählen nur einmal (der größere).

## 1.0 ohne kritischen Treffer, sonst 1 + Zusatzschaden
func crit_factor(from: Monster) -> float:
	if from == null:
		return 1.0
	return 1.0 + maxf(from.boon_value("crit_next"), from.boon_value("crit")) / 100.0

func is_crit(from: Monster) -> bool:
	return from != null and (from.has_boon("crit_next") or from.has_boon("crit"))

## Faktor auf den Skill-Wert eines Angriffs (1.0 = unverändert), alle Boni addieren sich:
## Passive des Angreifers (Element-Kraft, Magie-Kraft), seine Aufladung für diese Schadensart
## und die Extras der Karte gegen geschwächte oder angeschlagene Ziele.
func damage_factor(from: Monster, to: Monster, skill: Dictionary) -> float:
	var bonus := 0.0
	if not is_physical(skill):
		bonus += own_passive_sum(from, "magic_power")
	# der Angriff muss alle Elemente des Passivs haben (Magma-Passiv: Magma, Vulkan, Aschesturm, Chaos)
	for passive in own_passives(from, "element_power"):
		var passive_element: int = passive.get("passive_element", 0)
		if passive_element != 0 and skill.nature & passive_element == passive_element:
			bonus += effective_skill(from, passive).value
	bonus = bonus / 100.0 + from.charge(charge_kind(skill))
	for extra in extras(skill):
		match extra.kind:
			"bonus_vs_weakened":
				if to.is_weakened():
					bonus += extra.value / 100.0
			"bonus_low_hp":
				if to.hp_share() < LOW_HP_SHARE:
					bonus += extra.value / 100.0
	return 1.0 + bonus

## Schaden = (fester Schaden + scaling x Angriff) x factor (Element, Boni).
## Getrennt von calc_damage, damit das Debug-Menü Beispiele ohne echte Monster rechnen kann.
## Aufrunden, damit angezeigter und abgezogener Schaden gleich sind (jeder Treffer macht mind. 1).
func stat_damage(atk: float, value: float, scaling: float, factor: float) -> float:
	return maxf(ceilf((value + scaling * atk) * factor), 1.0)

# ─────────────────────────
# Element-Kreis: Wasser > Feuer > Luft > Erde > Wasser
# (Wasser löscht Feuer, Feuer verzehrt Luft, Wind trägt Erde ab, Erde dämmt Wasser ein.)
# Gegenüberliegende Elemente (Wasser/Luft, Feuer/Erde) sind neutral zueinander.
const STRONG_AGAINST = {
	Enums.MON_TYPES.WATER: Enums.MON_TYPES.FIRE,
	Enums.MON_TYPES.FIRE: Enums.MON_TYPES.AIR,
	Enums.MON_TYPES.AIR: Enums.MON_TYPES.EARTH,
	Enums.MON_TYPES.EARTH: Enums.MON_TYPES.WATER,
}
const ELEMENT_BONUS := 0.5

# Jedes Element des Skills wird gegen jedes Element des Ziels verglichen:
# +1 wenn der Skill stark dagegen ist, -1 wenn das Ziel-Element den Skill abwehrt.
# Kombinierte Monster erben damit alle Schwächen und alle Resistenzen ihrer Elemente, die sich gegenseitig aufheben können.
func element_score(skill_nature: int, target_type: int) -> int:
	var score = 0
	for attack_element in STRONG_AGAINST:
		if not skill_nature & attack_element:
			continue
		for defend_element in STRONG_AGAINST:
			if not target_type & defend_element:
				continue
			if STRONG_AGAINST[attack_element] == defend_element:
				score += 1
			elif STRONG_AGAINST[defend_element] == attack_element:
				score -= 1
	return score

# Macht der Skill Schaden? (Schild-, Buff- und passive Skills haben zwar einen Wert, aber keinen Schaden.)
func is_damage_skill(skill: Dictionary) -> bool:
	return skill.has("value") and skill.get("effect", "damage") == "damage"

# Schilde und Buffs zielen auf das eigene Team.
func targets_friends(skill: Dictionary) -> bool:
	return skill.target in [Enums.CARD_TARGETS.SINGLE_FRIEND, Enums.CARD_TARGETS.TEAM_FRIEND, Enums.CARD_TARGETS.SELF]

# Wirkt nur auf den Wirker selbst.
func targets_self(skill: Dictionary) -> bool:
	return skill.target == Enums.CARD_TARGETS.SELF

# Einzelangriff auf einen Gegner (an ihn binden Aggro-Effekte das Ziel, siehe taunters).
func targets_single_enemy(skill: Dictionary) -> bool:
	return skill.target == Enums.CARD_TARGETS.SINGLE_ENEMY

# Flächen-Skills treffen alle Monster der Zielseite.
func targets_team(skill: Dictionary) -> bool:
	return skill.target in [Enums.CARD_TARGETS.TEAM_ENEMY, Enums.CARD_TARGETS.TEAM_FRIEND]

# Passive Skills wirken einfach, solange das Monster sie kennt, und können nicht ausgespielt werden.
func is_passive(skill: Dictionary) -> bool:
	return skill.get("effect", "") == "passive"

# +1 -> x1.5, +2 -> x2.0, ... / -1 -> x0.5, -2 -> x0.25, ...
# Chaos-Skills bekommen gegen Nicht-Chaos-Ziele einen Zuschlag (ElementEffects.chaos_bonus).
func element_multiplier(skill_nature: int, target_type: int) -> float:
	var score = element_score(skill_nature, target_type)
	var bonus = ElementEffects.chaos_bonus(skill_nature, target_type)
	if score >= 0:
		return 1.0 + ELEMENT_BONUS * score + bonus
	return pow(1.0 - ELEMENT_BONUS, -score) + bonus

## Element-Faktor eines Angriffs auf ein Ziel: nur magische Angriffe nutzen den Element-Kreis (auch bei kritischen
## Treffern), physische treffen immer neutral (x1), egal welches Element sie haben.
func skill_element_multiplier(skill: Dictionary, target_type: int) -> float:
	if is_physical(skill):
		return 1.0
	return element_multiplier(skill.get("nature", 0), target_type)

# ─────────────────────────
# Schilde halten, bis der Wirker wieder am Zug ist, oder bis sie aufgebraucht sind (siehe Monster.expire_from, Monster.absorb_damage).
# Es gibt nur eine Art Schild: er blockt physische und magische Angriffe (außer Karten, die ausdrücklich durchgehen, z. B. Magma).

# Schild: fester Wert + scaling x Verteidigung des Wirkers.
func add_shield(props):
	props.mon.add_shield(shield_amount(props.from, props.skill), props.from)

## Schildstärke, die der Wirker mit dieser Karte gibt (auch für Karten, Absichten und KI):
## fester Wert + scaling x seine Verteidigung, Schild-Passive des Wirkers kommen obendrauf.
func shield_amount(from: Monster, skill: Dictionary) -> float:
	var used := effective_skill(from, skill)
	var bonus := own_passive_sum(from, "shield_power") / 100.0
	return ceilf((used.value + used.get("scaling", 0.0) * from.defense()) * (1.0 + bonus))
# Buff: value % mehr auf buff_stat für buff_turns eigene Züge des Ziels.
# +1, weil Buffs zu Beginn jedes eigenen Zuges herunterzählen (wie bei den Element-Effekten).
func add_buff(props):
	props.mon.add_buff(props.skill.buff_stat, props.skill.value / 100, props.skill.buff_turns + 1)

# Sonder-Verstärkung (effect "boon", Feld "boon" = Art, siehe Monster._boons): value für buff_turns eigene Züge des Ziels,
# buff_turns -1 = bis verbraucht (nächster Treffer kritisch). Der Wert kommt aus props.skill, schlummernd also abgeschwächt.
const BOON_KINDS := ["crit_next", "crit", "leech", "extra_moves", "taunt"]

func add_boon(props):
	var turns: int = props.skill.get("buff_turns", -1)
	props.mon.add_boon(props.skill.boon, props.skill.value, -1 if turns < 0 else turns + 1)
	Events.status_vfx.emit(props.mon, "buff")

# ─────────────────────────
# Aggro: Monster, die die Aufmerksamkeit auf sich ziehen (Kampfschrei als Sonder-Verstärkung "taunt", Passiv "taunt"),
# müssen von Einzelangriffen der Gegenseite getroffen werden. Flächenangriffe treffen ohnehin alle.
# Gilt für beide Seiten: battle.gd prüft es beim Ausspielen (_is_valid_target) und beim Planen der Gegner (_candidate_targets).

func is_taunting(mon: Monster) -> bool:
	return mon.has_boon("taunt") or not own_passives(mon, "taunt").is_empty()

## Lebende Monster aus side, die gerade die Aufmerksamkeit auf sich ziehen
func taunters(side: Array) -> Array:
	return side.filter(func(mon: Monster): return mon.is_alive() and is_taunting(mon))

# ─────────────────────────
# Kosten: Aktionen, die ein Skill das Monster kostet. Passiv "shield_cost" (Bollwerkmeister) senkt Schilde,
# die SHIELD_COST_DISCOUNT_FROM oder mehr Aktionen kosten, um seinen Wert (nie unter 1).
const SHIELD_COST_DISCOUNT_FROM := 3

func skill_cost(mon: Monster, skill: Dictionary) -> int:
	var cost: int = skill.get("cost", 1)
	if mon != null and skill.get("effect", "") == "shield" and cost >= SHIELD_COST_DISCOUNT_FROM:
		cost -= roundi(own_passive_sum(mon, "shield_cost"))
	return maxi(cost, 1) if skill.get("cost", 1) > 0 else 0
# ─────────────────────────
# Absichten: Gegner planen ihren nächsten Zug im Voraus (Monster._intent, battle.gd _plan_intent),
# der Spieler sieht vorher, wen sie mit wie viel Schaden treffen werden.

# Trifft eine geplante Aktion dieses Monster? Flächen-Skills treffen alle auf der Seite des Ziels.
func action_hits(action: Dictionary, mon: Monster) -> bool:
	if action.target == mon:
		return true
	return targets_team(action.skill) and action.target != null and State.mons.has(action.target) == State.mons.has(mon)

# Geplante Angriffe der attackers auf target, einer pro Eintrag:
# {"physical": bool, "full": ohne Schild, "after": nach Schild}. Der Schild blockt physische und magische Treffer,
# und jeder Treffer verbraucht ihn, wie Monster.absorb_damage es im Kampf tut.
func incoming_hits(target: Monster, attackers: Array) -> Array:
	var shield = target.shield()
	var hits = []
	for attacker: Monster in attackers:
		if not attacker.is_alive():
			continue
		for action in attacker._intent:
			if not is_damage_skill(action.skill) or not action_hits(action, target):
				continue
			var physical = is_physical(action.skill)
			var full = calc_damage(attacker, target, action.skill)
			# Aufladungen gelten nur für den ersten passenden Angriff, die Vorschau rechnet sie bei jedem mit (kleine Ungenauigkeit)
			# gleiche Rechnung wie Monster.absorb_damage. Dass Magma oder Schlamm durch den Schild gehen, ist Zufall
			# und steht nicht in der Vorschau. Ebenso, dass ein Schild mittendrin abläuft, weil sein Wirker zwischen
			# zwei angekündigten Angriffen am Zug ist (kleine Ungenauigkeit).
			var blocked = minf(shield, full)
			shield -= blocked
			hits.append({"physical": physical, "full": full, "after": full - blocked})
	return hits

# ─────────────────────────
# Passive Skills (effect "passive", Feld "passive" = Art). Es gilt die Element-Regel: nur Monster, die den Skill einsetzen
# könnten, bekommen bzw. geben den Bonus, schlummernd abgeschwächt (effective_skill). Alle Werte in Prozent.
#   "stat":           +value % auf passive_stat. passive_scope: "self" = nur das Monster, "partner" = das nächste Monster
#                     im Team (beim letzten das erste), "team" = jedes Monster im Team (auch es selbst)
#   "element_power":  eigene Angriffe mit passive_element machen +value % Schaden
#   "magic_power":    eigene magische Angriffe machen +value % Schaden
#   "shield_power":   eigene Schilde +value %
#   "effect_chance":  eigene Element-Effekte lösen value % öfter aus (Karten mit Auslösechance, Vulkan)
#   "leech":          heilt sich um value % des verursachten Schadens
#   "kill_heal":      heilt sich um value % seiner max. KP, wenn es einen Gegner besiegt
#   "regen":          heilt sich zu Beginn jedes eigenen Zuges um value % seiner max. KP (apply_regen)
#   "shield_cost":    eigene Schilde ab SHIELD_COST_DISCOUNT_FROM Aktionen kosten value Aktionen weniger (skill_cost)
#   "taunt":          zieht dauerhaft die Einzelangriffe der Gegner auf sich (taunters)

const PASSIVE_SCOPES := ["self", "partner", "team"]

## Lebende und besiegte Monster auf der Seite von mon (für Passive zählt die Aufstellung, nicht wer noch steht)
func team_of(mon: Monster) -> Array:
	if State.mons.has(mon):
		return State.mons
	if State.enemy_mons.has(mon):
		return State.enemy_mons
	return [mon]

## Partner eines Monsters: das nächste im Team, beim letzten das erste (null, wenn es allein ist)
func partner_of(mon: Monster) -> Monster:
	var team := team_of(mon)
	if team.size() < 2:
		return null
	return team[(team.find(mon) + 1) % team.size()]

## Passive dieser Art, die das Monster gerade nutzen kann
func own_passives(mon: Monster, kind: String) -> Array:
	return mon._skills.filter(func(skill): return is_passive(skill) and skill.get("passive", "") == kind and can_use(mon, skill))

## Summe der Werte (schlummernd abgeschwächt) aller eigenen Passive dieser Art
func own_passive_sum(mon: Monster, kind: String) -> float:
	var total := 0.0
	for skill in own_passives(mon, kind):
		total += effective_skill(mon, skill).value
	return total

## Faktor aller Werte-Passive im Team auf einen Wert von mon (1.0 = kein Bonus)
func passive_stat_factor(mon: Monster, stat: String) -> float:
	var bonus := 0.0
	for member in team_of(mon):
		for skill in own_passives(member, "stat"):
			if skill.get("passive_stat", "") != stat:
				continue
			var scope: String = skill.get("passive_scope", "team")
			if scope == "team" or (scope == "self" and member == mon) or (scope == "partner" and partner_of(member) == mon):
				bonus += effective_skill(member, skill).value
	return 1.0 + bonus / 100.0

# ─────────────────────────
# Extras: Zusatzwirkungen einer Karte, Feld "extras" = [{"kind": ..., "value": ..., ...}] (Baustein _extra).
#   "debuff":            Ziel (jeder getroffene Gegner) -value % auf stat für turns eigene Züge, mit chance (0..1)
#   "self_buff":         Wirker +value % auf stat für turns eigene Züge
#   "team_buff":         jedes eigene Monster (auch der Wirker) +value % auf stat für turns Züge
#   "charge":            die anderen eigenen Monster machen mit ihrem nächsten Angriff der Art stat
#                        ("physical"/"magic") +value % Schaden (Aufladung, Monster._charges)
#   "leech":             Wirker heilt sich um value % des verursachten Schadens
#   "heal":              Ziel (eigenes Monster) heilt value % seiner max. KP
#   "bonus_vs_weakened": +value % Schaden gegen Ziele mit Schwächung oder Statuseffekt
#   "bonus_low_hp":      +value % Schaden gegen Ziele unter LOW_HP_SHARE ihrer KP

const LOW_HP_SHARE := 0.5

func extras(skill: Dictionary) -> Array:
	return skill.get("extras", [])

## Aufladungs-Art eines Angriffs: "physical" oder "magic"
func charge_kind(skill: Dictionary) -> String:
	return "physical" if is_physical(skill) else "magic"

## Pro getroffenem Gegner (battle.gd _use_skill): Schwächungen der Karte
func apply_hit_extras(from: Monster, target: Monster, skill: Dictionary) -> void:
	if not target.is_alive():
		return
	for extra in extras(skill):
		if extra.kind == "debuff" and randf() < extra.get("chance", 1.0):
			target.add_debuff("skill_" + extra.stat, extra.stat, extra.value / 100.0, extra.turns + 1)
			Events.monster_effect_text.emit(target, "-%d%% %s" % [roundi(extra.value), stat_label(extra.stat)], ElementEffects.DEBUFF_COLOR)
			Events.status_vfx.emit(target, "debuff")

## Pro eigenem Ziel (Schild, Buff): Heilung der Karte
func apply_friend_extras(_from: Monster, target: Monster, skill: Dictionary) -> void:
	if not target.is_alive():
		return
	for extra in extras(skill):
		if extra.kind == "heal":
			heal(target, target.hp() * extra.value / 100.0)

## Einmal pro Einsatz, nach allen Treffern: Verstärkungen, Aufladungen und Lebensraub (Karte und Passiv)
func apply_cast_extras(from: Monster, skill: Dictionary, dealt: float) -> void:
	if not from.is_alive():
		return
	var allies := team_of(from).filter(func(m: Monster): return m.is_alive())
	# Lebensraub aus Passiv und Sonder-Verstärkung (Blutgezeiten)
	var leech: float = own_passive_sum(from, "leech") + from.boon_value("leech") if is_damage_skill(skill) else 0.0
	for extra in extras(skill):
		match extra.kind:
			"self_buff":
				from.add_buff(extra.stat, extra.value / 100.0, extra.turns + 1)
				Events.status_vfx.emit(from, "buff")
			"team_buff":
				for ally in allies:
					ally.add_buff(extra.stat, extra.value / 100.0, extra.turns + 1)
					Events.status_vfx.emit(ally, "buff")
			"charge":
				for ally in allies:
					if ally != from:
						ally.add_charge(extra.stat, extra.value / 100.0)
						Events.status_vfx.emit(ally, "buff")
			"leech":
				leech += extra.value
	if leech > 0.0 and dealt > 0.0:
		heal(from, dealt * leech / 100.0)

## Passiv "regen" (Wasser): zu Beginn jedes eigenen Zuges value % der max. KP zurück (battle.gd, nach den Boss-Relikten)
func apply_regen(mon: Monster) -> void:
	var regen := own_passive_sum(mon, "regen")
	if regen > 0.0 and mon.is_alive():
		heal(mon, mon.hp() * regen / 100.0)

## Heilt bis zu den vollen KP und zeigt "+N" (gleiche Anzeige wie die Heil-Relikte)
func heal(mon: Monster, amount: float) -> void:
	if not mon.is_alive() or mon._lost_hp <= 0.0:
		return
	BossRelics.heal(mon, amount)
	Events.status_vfx.emit(mon, "heal")

## Kurzname eines Werts ("ANG", "VER", ...) für Texte
const STAT_LABELS := {"hp": "STAT_HP", "atk": "STAT_ATK", "def": "STAT_DEF", "s_atk": "STAT_SPA", "fail": "STAT_FAIL",
	"speed": "STAT_SPE"}

func stat_label(stat: String) -> String:
	return tr(STAT_LABELS.get(stat, stat)).trim_suffix(":")

## Zusatzzeilen für die Beschreibung: Passiv-Bonus steht schon im Haupttext, hier nur die Extras
func extras_text(skill: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for extra in extras(skill):
		var values := {"value": Helper.format_number(extra.get("value", 0.0)), "turns": extra.get("turns", 0),
			"stat": stat_label(extra.get("stat", "")), "share": roundi(LOW_HP_SHARE * 100)}
		var key: String = "SKILL_EXTRA_" + String(extra.kind).to_upper()
		if extra.kind == "charge":
			key += "_" + String(extra.stat).to_upper()
		var text := tr(key).format(values)
		var chance: float = extra.get("chance", 1.0)
		if chance < 1.0:
			text = tr("EFFECT_CHANCE_PREFIX").format({"chance": roundi(chance * 100)}) + text
		lines.append(text)
	return lines

# ─────────────────────────
# Abklingzeit: Nach dem Einsatz ist ein Skill für cooldown eigene Züge gesperrt.
# Heruntergezählt wird zu Beginn jedes Zuges des Monsters (Monster.start_turn), daher +1 für den laufenden Zug.
# _cooldown_left ist damit genau die Anzahl Züge, bis der Skill wieder bereit ist.

func start_cooldown(skill: Dictionary) -> void:
	if skill.get("cooldown", 0) > 0:
		skill._cooldown_left = skill.cooldown + 1

func cooldown_left(skill: Dictionary) -> int:
	return skill.get("_cooldown_left", 0)

func is_ready(skill: Dictionary) -> bool:
	return cooldown_left(skill) <= 0

func tick_cooldown(skill: Dictionary) -> void:
	if cooldown_left(skill) > 0:
		skill._cooldown_left -= 1

# Kann das Monster den Skill gerade ausspielen? (Element passt, nicht passiv, Abklingzeit vorbei)
func is_playable(mon: Monster, skill: Dictionary) -> bool:
	return can_use(mon, skill) and not is_passive(skill) and is_ready(skill)

# Stufe eines Skills (1 = schwach, 4 = sehr stark) -> Gewicht beim zufälligen Generieren.
# Je stärker der Skill, desto seltener taucht er auf.
const TIER_WEIGHTS = {1: 50, 2: 25, 3: 10, 4: 3}

# Liefert eine frische Kopie des Skills mit diesem Namen (aus allen Skill-Listen) oder {}.
func get_skill(skill_name: String) -> Dictionary:
	for list in [starter_skills, standard_skills, egg_skills, defensive_skills, buff_skills, passive_skills, area_skills, milestone_skills, bounty_skills, reward_skills, ascension_skills, draft_skills]:
		for skill in list:
			if skill.name == skill_name:
				var copy = skill.duplicate(true)
				copy.id = Helper.generate_fake_uuid()
				return copy
	return {}

func has_skill(skill_name: String) -> bool:
	return not get_skill(skill_name).is_empty()

## Gemeinsamer Pool aller Ei-Attacken und Effekt-Skills (Schilde, Buffs, Passive, Flächenschaden).
## Aus ihm würfeln wilde Monster (Biom-Pool) und der Trainer, die Arten verweisen in Monmap darauf.
## Standard-, Meilenstein-, Kopfgeld-, Couvert- und Aufstiegs-Skills gehören nicht dazu.
func pool_skills() -> Array:
	return egg_skills + defensive_skills + buff_skills + passive_skills + area_skills

## Effekt-Skills des Pools (alles außer Schaden auf ein Ziel)
func effect_skills() -> Array:
	return defensive_skills + buff_skills + passive_skills + area_skills

## Tauchen bei wilden Monstern im Biom-Pool auf (Feld "wild": false = nie wild; Meilenstein-Skills liegen ohnehin nicht im Pool)
func is_wild_skill(skill: Dictionary) -> bool:
	return skill.get("wild", true)

## Kann der Trainer lehren (Feld "trainer": false = nicht beim Trainer)
func is_trainer_skill(skill: Dictionary) -> bool:
	return skill.get("trainer", true)

## Standard-Skill eines Grundelements für eine Kategorie ("physical", "magic", "shield"), {} wenn keiner
func standard_skill(element: int, category: String) -> Dictionary:
	for skill in standard_skills:
		if skill.nature == element and stat_category(skill) == category:
			return get_skill(skill.name)
	return {}

## Kategorie nach dem Wert, mit dem ein Skill rechnet: Angriff -> "physical", Sp. Angriff -> "magic",
## Verteidigung -> "shield" (Buffs und Passive: "")
func stat_category(skill: Dictionary) -> String:
	if is_damage_skill(skill):
		return "physical" if is_physical(skill) else "magic"
	if skill.get("effect", "") == "shield":
		return "shield"
	return ""

## Die drei Kampfwerte eines Monsters nach Größe sortiert, als Kategorien (siehe stat_category)
const CATEGORY_STATS := {"physical": "atk", "magic": "s_atk", "shield": "def"}

func categories_by_stat(mon: Monster) -> Array:
	var values := {"physical": mon.attack(), "magic": mon.s_attack(), "shield": mon.defense()}
	var keys := values.keys()
	keys.sort_custom(func(a, b): return values[a] > values[b])
	return keys

func get_tier(skill_name: String) -> int:
	return get_skill(skill_name).get("tier", 1)

# Pro Biom-Tiefe werden höhere Stufen wahrscheinlicher (Faktor pro Stufe über 1).
const DEPTH_TIER_BONUS := 0.4

# Maximale Anzahl Skills, die ein Monster gleichzeitig beherrscht.
const MAX_SKILLS := 6

func get_weight(skill_name: String, depth: int = 0) -> float:
	var tier = get_tier(skill_name)
	return TIER_WEIGHTS[tier] * pow(1.0 + DEPTH_TIER_BONUS * depth, tier - 1)

# Zieht einen Skill-Namen gewichtet nach Stufe (und Biom-Tiefe).
func pick_weighted(skill_names: Array, depth: int = 0) -> String:
	if skill_names.is_empty():
		return ""
	var total = 0.0
	for skill_name in skill_names:
		total += get_weight(skill_name, depth)
	var roll = randf() * total
	for skill_name in skill_names:
		roll -= get_weight(skill_name, depth)
		if roll <= 0:
			return skill_name
	return skill_names.back()

# Zieht bis zu count verschiedene Skill-Namen gewichtet nach Stufe (und Biom-Tiefe).
func pick_weighted_unique(skill_names: Array, count: int, depth: int = 0) -> Array:
	var pool = skill_names.duplicate()
	var picked = []
	for i in min(count, pool.size()):
		var skill_name = pick_weighted(pool, depth)
		picked.append(skill_name)
		pool.erase(skill_name)
	return picked

# Skills des gemeinsamen Pools, deren Element zum Biom passt (biome_mask 0 = alle).
func get_biome_skills(biome_mask: int) -> Array:
	return pool_skills().filter(func(skill): return is_wild_skill(skill) and (biome_mask == 0 or skill.nature & biome_mask != 0)).map(
		func(skill): return skill.name)

## Skills, die der Trainer lehren kann: gemeinsamer Pool ab min_tier, ohne die mit "trainer": false
func trainer_skills(min_tier: int) -> Array:
	return pool_skills().filter(func(skill): return is_trainer_skill(skill) and skill.tier >= min_tier)

# ─────────────────────────
# Lernen von Skills gefangener Monster

func knows_skill(mon: Monster, skill_name: String) -> bool:
	return mon._skills.any(func(skill): return skill.name == skill_name)

# ─────────────────────────
# Element-Regel: Ein Monster kann einen Skill einsetzen, sobald es mindestens ein Element des Skills hat
# (ein Luft-Monster kann keine Magma-Attacke spielen, ein Erde-Monster schon).
# Hat es alle Elemente, ist der Skill wach: volle Stärke und Element-Effekt
# (Vulkan = Erde+Feuer+Wasser spielt z. B. Erde, Feuer, Wasser, Magma, Schlamm, Dampf und Vulkan wach).
# Fehlen ihm welche, schlummert der Skill (effective_skill): weniger Wert, kein Element-Effekt, und er trifft nur mit
# den Elementen, die das Monster hat. Jeder Trank mit einem fehlenden Element macht ihn stärker, mit dem letzten erwacht er.

## Stärke eines schlummernden Skills: DORMANT_BASE_POWER + Rest anteilig nach vorhandenen Elementen
## (Magma-Attacke mit Erde: 1 von 2 -> 70 %, Vulkan-Attacke mit Erde: 1 von 3 -> 60 %, mit Magma: 2 von 3 -> 80 %)
const DORMANT_BASE_POWER := 0.4

func covers(type_mask: int, nature: int) -> bool:
	return nature & ~type_mask == 0

func shares_element(type_mask: int, nature: int) -> bool:
	return nature == 0 or nature & type_mask != 0

func can_use(mon: Monster, skill: Dictionary) -> bool:
	return shares_element(mon._type, skill.nature)

## Unbekannte Skill-Namen (z. B. gelöschte Skills) gelten als nicht einsetzbar statt abzustürzen.
func can_use_name(mon: Monster, skill_name: String) -> bool:
	var skill = get_skill(skill_name)
	return not skill.is_empty() and shares_element(mon._type, skill.nature)

## Hat das Monster alle Elemente des Skills? (Gegner und wilde Monster bekommen nur solche Skills)
func is_awake(mon: Monster, skill: Dictionary) -> bool:
	return covers(mon._type, skill.nature)

func is_awake_name(mon: Monster, skill_name: String) -> bool:
	var skill = get_skill(skill_name)
	return not skill.is_empty() and covers(mon._type, skill.nature)

## Einsetzbar, aber noch nicht alle Elemente da
func is_dormant(mon: Monster, skill: Dictionary) -> bool:
	return mon != null and can_use(mon, skill) and not is_awake(mon, skill)

## 1.0 für wache Skills, sonst siehe DORMANT_BASE_POWER
func dormant_power(mon: Monster, skill: Dictionary) -> float:
	if not is_dormant(mon, skill):
		return 1.0
	var share := float(Map.count_elements(skill.nature & mon._type)) / Map.count_elements(skill.nature)
	return DORMANT_BASE_POWER + (1.0 - DORMANT_BASE_POWER) * share

## Der Skill so, wie das Monster ihn gerade einsetzt. Wach: der Skill selbst. Schlummernd: eine Kopie mit
## abgeschwächtem Wert, nur den eigenen Elementen (für den Element-Faktor) und "_dormant" (ElementEffects wirkt nicht).
## Mehrfach anwenden schadet nicht.
func effective_skill(mon: Monster, skill: Dictionary) -> Dictionary:
	if skill.get("_effective", false) or skill.get("_dormant", false):
		return skill
	if not is_dormant(mon, skill):
		return skill
	var copy := skill.duplicate()
	copy._effective = true
	copy._dormant = true
	copy.nature = skill.nature & mon._type
	var power := dormant_power(mon, skill)
	var value = skill.get("value")
	if value is float or value is int:
		copy.value = maxf(roundf(value * power), 1.0)
	if skill.has("scaling"):
		copy.scaling = snappedf(skill.scaling * power, 0.01)
	return copy

# Einzelne Elemente, die dem Monster für diesen Skill noch fehlen (zum Einsetzen bzw. zum Erwachen).
func missing_elements(mon: Monster, skill: Dictionary) -> Array:
	return Enums.MON_TYPES.values().filter(func(element): return skill.nature & element and not mon._type & element)

func _element_list(elements: Array) -> String:
	var labels = elements.map(func(element): return tr(ColorMap.get_combo(element).label))
	return ", ".join(PackedStringArray(labels))

# Warum das Monster den Skill nicht einsetzen kann: "Benötigt: Feuer" bzw. "Benötigt eins von: Erde, Feuer"
# ("" wenn einsetzbar, auch schlummernd).
func missing_elements_text(mon: Monster, skill: Dictionary) -> String:
	if can_use(mon, skill):
		return ""
	var missing = missing_elements(mon, skill)
	var key := "SKILL_NEEDS_ELEMENTS" if missing.size() == 1 else "SKILL_NEEDS_ONE_ELEMENT"
	return tr(key).format({"elements": _element_list(missing)})

# Schlummernder Skill: "Schlummert: 70 % Stärke, trifft als Erde" und darunter "Erwacht mit: Feuer" ("" sonst).
# Mit [hl]-Markierungen wie die Skill-Beschreibungen (Helper.highlight).
func dormant_text(mon: Monster, skill: Dictionary) -> String:
	if not is_dormant(mon, skill):
		return ""
	var dormant := tr("SKILL_DORMANT").format({
		"power": roundi(dormant_power(mon, skill) * 100),
		"element": tr(ColorMap.get_combo(skill.nature & mon._type).label)})
	return dormant + "\n" + tr("SKILL_AWAKENS_WITH").format({"elements": _element_list(missing_elements(mon, skill))})

## Nach einem neuen Element (Trank): kurz oben einblenden, welche Skills des Monsters dadurch erwacht sind
func announce_awakened(mon: Monster, old_type: int) -> void:
	var awakened = mon._skills.filter(func(skill): return covers(mon._type, skill.nature) and not covers(old_type, skill.nature))
	if awakened.is_empty():
		return
	var names = awakened.map(func(skill): return tr(skill.name))
	Helper.show_unlock_message(tr("SKILL_AWAKENED").format({
		"mon": Helper.mon_battle_name(mon), "skills": ", ".join(PackedStringArray(names))}))

# Lern-Buttons: gesperrt, wenn das Monster den Skill schon kennt; fehlende Elemente werden als Hinweis angehängt
# (gelernt werden darf trotzdem, spielbar wird der Skill erst mit den passenden Elementen).
func setup_learn_button(button: Button, mon: Monster, skill: Dictionary, label_key: String) -> void:
	button.disabled = knows_skill(mon, skill.name)
	if button.disabled:
		button.text = tr("JUDGEMENT_LEARN_KNOWN")
	elif not can_use(mon, skill):
		button.text = tr(label_key) + " (" + missing_elements_text(mon, skill) + ")"
	else:
		button.text = tr(label_key)

# Kopie des Skills, wie das Monster ihn lernt.
func learnable_copy(skill: Dictionary) -> Dictionary:
	var copy = skill.duplicate()
	copy.id = Helper.generate_fake_uuid()
	copy.erase("egg_skill")
	# gelernte Attacken sind dem eigenen Monster bekannt, auch wenn der Gegner sie nie eingesetzt hat
	copy.scouted = true
	return copy

# ─────────────────────────
# Ei-Attacken pro Monster-Art (siehe Monmap: default_egg_skills / unlockable_egg_skills)

# Alle Ei-Attacken, die die Art zu Beginn eines Runs mitnehmen kann (Standard + freigeschaltet).
func get_available_egg_skills(mon_name: String) -> Array:
	var meta = Monmap.mon_metainfos_by_name(mon_name)
	var available = meta.get("default_egg_skills", []).duplicate()
	for skill_name in meta.get("unlockable_egg_skills", []):
		if SaveManager.is_egg_skill_unlocked(mon_name, skill_name):
			available.append(skill_name)
	for skill_name in meta.get("milestone_egg_skills", {}).values() + meta.get("bounty_egg_skills", {}).values():
		if SaveManager.is_egg_skill_unlocked(mon_name, skill_name):
			available.append(skill_name)
	return available

# Ei-Attacken der Art, die noch freigeschaltet werden können.
func get_locked_egg_skills(mon_name: String) -> Array:
	var meta = Monmap.mon_metainfos_by_name(mon_name)
	return meta.get("unlockable_egg_skills", []).filter(
		func(skill_name): return not SaveManager.is_egg_skill_unlocked(mon_name, skill_name))

# Ei-Attacken lassen sich nur für Arten freischalten, die in der Ei-Auswahl stehen
# (Start-Arten und gefangene, deren Ei schon eingesammelt wurde: Helper.get_all_owned_monster_names).
func can_unlock_egg_skills(mon_name: String) -> bool:
	return Helper.get_all_owned_monster_names().has(mon_name)

# Ist dieser Skill eines Monsters eine Ei-Attacke, die durch Opfern freigeschaltet werden kann?
func is_unlockable_egg_skill(mon: Monster, skill: Dictionary) -> bool:
	return skill.get("egg_skill", false) and can_unlock_egg_skills(mon._name) and get_locked_egg_skills(mon._name).has(skill.name)

# Alle Ei-Attacken der Art: {"available": freigeschaltete, "locked": noch gesperrte (fangen & opfern, Meilensteine, Kopfgelder),
# "hints": gesperrter Skill -> [Sperr-Label, Freischalt-Hinweis] wie im Konfigurator}.
func get_all_egg_skills(mon_name: String) -> Dictionary:
	var locked = []
	var hints = {}
	for skill_name in get_locked_egg_skills(mon_name):
		locked.append(skill_name)
		hints[skill_name] = ["CONFIGURATOR_LOCKED", "EGG_SKILL_HINT"]
	for entry in get_locked_milestones(mon_name):
		locked.append(entry.skill)
		hints[entry.skill] = ["CONFIGURATOR_LOCKED_MILESTONE", entry.hint]
	for entry in get_locked_bounties(mon_name):
		locked.append(entry.skill)
		hints[entry.skill] = ["CONFIGURATOR_LOCKED_BOUNTY", entry.hint]
	return {"available": get_available_egg_skills(mon_name), "locked": locked, "hints": hints}

# Wie die Art diese verfügbare Ei-Attacke bekommen hat: [Label, Beschreibung], Gegenstück zu den Sperr-Hinweisen.
# Noch gesperrt oder keine Ei-Attacke der Art: [].
func get_egg_skill_source(mon_name: String, skill_name: String) -> Array:
	var meta = Monmap.mon_metainfos_by_name(mon_name)
	if meta.get("default_egg_skills", []).has(skill_name):
		return ["EGG_SOURCE_DEFAULT", "EGG_SOURCE_DEFAULT_HINT"]
	if not SaveManager.is_egg_skill_unlocked(mon_name, skill_name):
		return []
	if meta.get("unlockable_egg_skills", []).has(skill_name):
		return ["EGG_SOURCE_SACRIFICE", "EGG_SOURCE_SACRIFICE_HINT"]
	for milestone in MILESTONES:
		if meta.get("milestone_egg_skills", {}).get(milestone.key, "") == skill_name:
			return ["EGG_SOURCE_MILESTONE", milestone.source_hint]
	for bounty in BOUNTIES:
		if meta.get("bounty_egg_skills", {}).get(bounty.key, "") == skill_name:
			return ["EGG_SOURCE_BOUNTY", bounty_text(bounty, bounty.source_hint)]
	return []

# Kategorien der Ei-Attacken für die Übersicht in der Start-Auswahl, in Anzeigereihenfolge.
# Neue Kategorie: hier eintragen und in egg_skill_category zuordnen.
const EGG_SKILL_CATEGORIES = [
	{"key": "physical", "label": "EGG_CATEGORY_PHYSICAL", "icon": "res://assets/ui/icons/fist.svg"},
	{"key": "magic", "label": "EGG_CATEGORY_MAGIC", "icon": "res://assets/ui/icons/sparkle.svg"},
	{"key": "shield", "label": "EGG_CATEGORY_SHIELD", "icon": "res://assets/ui/icons/stat_shield.svg"},
	{"key": "buff", "label": "EGG_CATEGORY_BUFF", "icon": "res://assets/ui/icons/battle/buff.svg"},
	{"key": "passive", "label": "EGG_CATEGORY_PASSIVE", "icon": "res://assets/ui/icons/passive.svg"},
]

const PHYSICAL_ICON := preload("res://assets/ui/icons/fist.svg")
const MAGIC_ICON := preload("res://assets/ui/icons/sparkle.svg")
const PASSIVE_ICON := preload("res://assets/ui/icons/passive.svg")
const BUFF_ICON := preload("res://assets/ui/icons/battle/buff.svg")
const DEBUFF_ICON := preload("res://assets/ui/icons/battle/debuff.svg")

## Icon unten links auf Karten und in Tabellen. Passive, Buffs (auch Sonder-Verstärkungen) und Debuffs zeigen ihr
## eigenes Symbol. Sonst der Wert, mit dem die Fähigkeit rechnet, mit denselben Symbolen wie die Werte-Tabellen
## (StatsGrid.ICONS): Schaden = Angriffswert (Faust bzw. Funken), Schild = Verteidigung (Schild).
func kind_icon(skill: Dictionary) -> Texture2D:
	if is_passive(skill):
		return PASSIVE_ICON
	if is_buff_skill(skill):
		return BUFF_ICON
	if is_debuff_skill(skill):
		return DEBUFF_ICON
	var stat := affected_stat(skill)
	if stat != "":
		return StatsGrid.ICONS[stat]
	return PHYSICAL_ICON if is_physical(skill) else MAGIC_ICON

func is_buff_skill(skill: Dictionary) -> bool:
	return skill.get("effect", "") in ["buff", "boon"]

func is_debuff_skill(skill: Dictionary) -> bool:
	return skill.get("effect", "") == "debuff"

## Fähigkeiten, die auf Karten unten links nur ihr Symbol zeigen, ohne Stärke: Passive, Buffs und Debuffs
func shows_only_icon(skill: Dictionary) -> bool:
	return is_passive(skill) or is_buff_skill(skill) or is_debuff_skill(skill)

## Stat-Key, den die Fähigkeit verändert bzw. mit dem sie rechnet ("" = keiner)
func affected_stat(skill: Dictionary) -> String:
	var stat: String = ""
	if is_passive(skill):
		stat = skill.get("passive_stat", "")
	elif skill.get("effect", "") == "buff":
		stat = skill.get("buff_stat", "")
	elif skill.get("effect", "") == "boon":
		# Sonder-Verstärkungen geben das Symbol vor (Krit -> Angriff, Lebensraub -> KP, Aktionen -> Initiative)
		stat = skill.get("icon_stat", "")
	elif is_damage_skill(skill):
		stat = "atk" if is_physical(skill) else "s_atk"
	else:
		stat = "def"
	return stat if StatsGrid.ICONS.has(stat) else ""

## Wert, der auf Karten und in Tabellen unter "Stärke" steht: bei Angriffen der Schaden mit neutralem Element,
## bei Schilden die Schildstärke, beides aus den aktuellen Werten des Monsters.
## Buffs und Passive zeigen ihren Grundwert. Ohne Monster oder solange der Wert eines Gegners noch nicht aufgedeckt
## ist, steht die Formel da ("5+0.2x"), damit die Karte nichts verrät.
func power_text(skill: Dictionary, mon: Monster) -> String:
	var used := effective_skill(mon, skill)
	var value = used.get("value", skill.get("damage", ""))
	if not (value is float or value is int):
		return Helper.format_number(value)
	var physical := is_physical(skill)
	var stat := ""
	if is_damage_skill(skill):
		stat = "atk" if physical else "s_atk"
	elif skill.get("effect", "") == "shield":
		stat = "def"
	if stat == "" or not used.has("scaling"):
		return Helper.format_number(value)
	if mon == null or not _stat_visible(mon, stat):
		return "%s+%sx" % [Helper.format_number(value), Helper.format_number(used.scaling)]
	if skill.get("effect", "") == "shield":
		return str(int(shield_amount(mon, skill)))
	var base: float = mon.attack() if physical else mon.s_attack()
	return str(int(stat_damage(base, used.value, used.scaling, 1.0)))

## Gegner im Kampf verraten ihre Werte erst, wenn sie aufgedeckt sind (siehe BattleInfoPanel._hidden_stats).
func _stat_visible(mon: Monster, stat: String) -> bool:
	if not State.enemy_mons.has(mon):
		return true
	return State.is_mon_known(mon._name) or Relics.works("all_stats") or State.is_mon_stat_revealed(mon._name, stat)

func egg_skill_category(skill: Dictionary) -> String:
	if is_passive(skill):
		return "passive"
	if skill.get("effect", "") in ["buff", "boon"]:
		return "buff"
	if not is_damage_skill(skill):
		return "shield"
	return "physical" if is_physical(skill) else "magic"

# ─────────────────────────
# Meilenstein-Ei-Attacken: feste Freischaltungen pro Art, gezählt wird nur mit der Art als Start-Monster
# und nur, solange das Start-Monster selbst noch im Team ist (ausgetauscht oder K.O. = kein Fortschritt).
# Alle Bedingungen gelten innerhalb EINES Runs, Fortschritt nimmt man nicht in den nächsten Run mit.
# Welche Meilensteine eine Art hat und welcher Skill dazugehört, steht in Monmap (milestone_egg_skills, Schlüssel = key),
# gewürfelt von tools/skill_verteilung.js. Sie tauchen nie bei wilden Monstern oder im Biom-Pool auf.
# stat: Zähler des laufenden Runs (milestone_progress), count: nötiger Wert, hint: Freischalt-Hinweis im Konfigurator,
# source_hint: Beschreibung, wie die Attacke freigeschaltet wurde.
# Neuer Meilenstein: hier eintragen, Texte in translations.csv, Zähler in milestone_progress, Würfel-Tabellen im Werkzeug.
const MILESTONES = [
	# den n-ten Biom-Boss besiegen (Boss 5 ist der Endboss und kein Meilenstein)
	{"key": "boss_1", "stat": "run_bosses", "count": 1, "hint": "MILESTONE_HINT_BOSS_1", "source_hint": "MILESTONE_SOURCE_BOSS_1"},
	{"key": "boss_2", "stat": "run_bosses", "count": 2, "hint": "MILESTONE_HINT_BOSS_2", "source_hint": "MILESTONE_SOURCE_BOSS_2"},
	{"key": "boss_3", "stat": "run_bosses", "count": 3, "hint": "MILESTONE_HINT_BOSS_3", "source_hint": "MILESTONE_SOURCE_BOSS_3"},
	{"key": "boss_4", "stat": "run_bosses", "count": 4, "hint": "MILESTONE_HINT_BOSS_4", "source_hint": "MILESTONE_SOURCE_BOSS_4"},
	# den n-ten Biom-Boss besiegen, ohne dass in diesem Run ein eigenes Monster K.O. ging
	{"key": "flawless_1", "stat": "flawless_bosses", "count": 1, "hint": "MILESTONE_HINT_FLAWLESS_1", "source_hint": "MILESTONE_SOURCE_FLAWLESS_1"},
	{"key": "flawless_2", "stat": "flawless_bosses", "count": 2, "hint": "MILESTONE_HINT_FLAWLESS_2", "source_hint": "MILESTONE_SOURCE_FLAWLESS_2"},
	{"key": "flawless_3", "stat": "flawless_bosses", "count": 3, "hint": "MILESTONE_HINT_FLAWLESS_3", "source_hint": "MILESTONE_SOURCE_FLAWLESS_3"},
	# das Start-Monster landet den letzten Treffer eines Biom-Boss-Kampfs
	{"key": "finisher_1", "stat": "boss_finishers", "count": 1, "hint": "MILESTONE_HINT_FINISHER_1", "source_hint": "MILESTONE_SOURCE_FINISHER_1"},
	{"key": "finisher_2", "stat": "boss_finishers", "count": 2, "hint": "MILESTONE_HINT_FINISHER_2", "source_hint": "MILESTONE_SOURCE_FINISHER_2"},
	{"key": "finisher_3", "stat": "boss_finishers", "count": 3, "hint": "MILESTONE_HINT_FINISHER_3", "source_hint": "MILESTONE_SOURCE_FINISHER_3"},
	# K.O.s durch das Start-Monster (letzter Treffer)
	{"key": "kills_5", "stat": "starter_kills", "count": 5, "hint": "MILESTONE_HINT_KILLS_5", "source_hint": "MILESTONE_SOURCE_KILLS_5"},
	{"key": "kills_8", "stat": "starter_kills", "count": 8, "hint": "MILESTONE_HINT_KILLS_8", "source_hint": "MILESTONE_SOURCE_KILLS_8"},
	{"key": "kills_10", "stat": "starter_kills", "count": 10, "hint": "MILESTONE_HINT_KILLS_10", "source_hint": "MILESTONE_SOURCE_KILLS_10"},
	{"key": "kills_15", "stat": "starter_kills", "count": 15, "hint": "MILESTONE_HINT_KILLS_15", "source_hint": "MILESTONE_SOURCE_KILLS_15"},
	# Bounty Hunter: das Start-Monster erlegt ein Kopfgeld-Monster (letzter Treffer); solange offen, tauchen Kopfgelder auf
	{"key": "bounty", "stat": "starter_bounties", "count": 1, "hint": "MILESTONE_HINT_BOUNTY", "source_hint": "MILESTONE_SOURCE_BOUNTY"},
	# Elemente des Start-Monsters (Tränke, Letzter Wille)
	{"key": "new_element", "stat": "new_elements", "count": 1, "hint": "MILESTONE_HINT_NEW_ELEMENT", "source_hint": "MILESTONE_SOURCE_NEW_ELEMENT"},
	{"key": "chaos", "stat": "elements", "count": 4, "hint": "MILESTONE_HINT_CHAOS", "source_hint": "MILESTONE_SOURCE_CHAOS"},
]

func get_milestone(key: String) -> Dictionary:
	for milestone in MILESTONES:
		if milestone.key == key:
			return milestone
	return {}

# Noch gesperrte Meilensteine der Art als [{skill, hint, ...}], in der Reihenfolge aus Monmap.
func get_locked_milestones(mon_name: String) -> Array:
	var skills_by_key = Monmap.mon_metainfos_by_name(mon_name).get("milestone_egg_skills", {})
	var locked = []
	for key in skills_by_key:
		var milestone := get_milestone(key)
		var skill_name = skills_by_key[key]
		if milestone.is_empty():
			push_warning("Monmap: unbekannter Meilenstein '%s' bei '%s'" % [key, mon_name])
		elif not SaveManager.is_egg_skill_unlocked(mon_name, skill_name):
			var entry = milestone.duplicate()
			entry.skill = skill_name
			locked.append(entry)
	return locked

# Stand eines Meilenstein-Zählers im laufenden Run (siehe MILESTONES stat).
func milestone_progress(stat: String) -> int:
	var starter: Monster = State.starter
	match stat:
		"run_bosses":
			return State.map_level
		"flawless_bosses":
			return State.run_flawless_bosses
		"boss_finishers":
			return State.run_boss_finishers
		"starter_kills":
			return State.run_starter_kills
		"starter_bounties":
			return State.run_starter_bounties
		"new_elements":
			if starter == null:
				return 0
			return _count_elements(starter._type & ~int(Monmap.mon_metainfos_by_name(starter._name).initial_type))
		"elements":
			return 0 if starter == null else _count_elements(starter._type)
	return 0

func _count_elements(mask: int) -> int:
	var count := 0
	for element in [EARTH, FIRE, WATER, AIR]:
		if mask & element:
			count += 1
	return count

# Hat das Start-Monster noch einen offenen Meilenstein dieses Zählers? (z. B. damit Kopfgelder auftauchen)
func starter_wants(stat: String) -> bool:
	return State.is_starter_in_team() and get_locked_milestones(State.starter_name).any(func(m): return m.stat == stat)

# Prüft nach jedem Fortschritt alle offenen Meilensteine des Start-Monsters, schaltet erreichte frei und meldet sie.
# Liefert die Namen der neu freigeschalteten Skills (stehen auch in State.run_milestone_unlocks fürs Run-Ende).
func check_milestones() -> Array:
	if State.starter_name == "" or not State.is_starter_in_team():
		return []
	var unlocked = []
	for milestone in get_locked_milestones(State.starter_name):
		if milestone_progress(milestone.stat) >= milestone.count:
			SaveManager.unlock_egg_skill(State.starter_name, milestone.skill)
			unlocked.append(milestone.skill)
	if not unlocked.is_empty():
		State.run_milestone_unlocks.append_array(unlocked)
		Helper.show_unlock_message(tr("MILESTONE_UNLOCKED").format({
			"mon": Helper.mon_display_name(State.starter_name),
			"skills": ", ".join(PackedStringArray(unlocked.map(func(skill_name): return tr(skill_name)))),
		}))
	return unlocked

# ─────────────────────────
# Bounty Hunter: besondere Kopfgeld-Monster tauchen selten in normalen Kämpfen auf.
# Nur wenn ein Monster einer Art den letzten Treffer selbst landet, bekommt diese Art die Ei-Attacke aus
# Monmap (bounty_egg_skills). K.O. durch ein anderes Team-Mitglied oder Fangen zählt nicht.
# mon: Art des Kopfgeld-Monsters, level_bonus: Stufen über dem Kampf, min_depth: ab welcher Biom-Tiefe es auftaucht,
# label: Anzeigename (Platzhalter {mon} = Name der Art), hint: Freischalt-Hinweis im Konfigurator,
# source_hint: Beschreibung, wie die Attacke freigeschaltet wurde (beide mit {mon} und {biome}, siehe bounty_text).
# Die Liste würfelt tools/skill_verteilung.js: ein Kopfgeld pro Art, je seltener die belohnte Art, desto tieferes Biom.
# Bekommt ein Kopfgeld eine eigene Art, trägt diese in Monmap "bounty_target": "<key>" und kommt in den normalen
# Spawn-Pool: dann zählt jedes Auftauchen als Kopfgeld-Monster.
const BOUNTIES = [
	# automatisch erzeugt (tools/skill_verteilung.js): key = alpha_<Art, die die Ei-Attacke bekommt>, mon = Ziel
	{"key": "alpha_1", "mon": "22", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_2", "mon": "4", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_3", "mon": "80", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_4", "mon": "18", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_5", "mon": "21", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_6", "mon": "13", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_7", "mon": "43", "level_bonus": 3, "min_depth": 3, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_8", "mon": "2", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_9", "mon": "5", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_10", "mon": "3", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_11", "mon": "81", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_12", "mon": "75", "level_bonus": 3, "min_depth": 3, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_13", "mon": "41", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_14", "mon": "17", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_15", "mon": "15", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_16", "mon": "4", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_17", "mon": "59", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_18", "mon": "81", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_19", "mon": "46", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_20", "mon": "16", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_21", "mon": "64", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_22", "mon": "18", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_23", "mon": "82", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_24", "mon": "17", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_25", "mon": "7", "level_bonus": 3, "min_depth": 3, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_26", "mon": "76", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_27", "mon": "10", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_28", "mon": "24", "level_bonus": 3, "min_depth": 3, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_29", "mon": "22", "level_bonus": 4, "min_depth": 4, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_30", "mon": "68", "level_bonus": 4, "min_depth": 4, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_31", "mon": "81", "level_bonus": 4, "min_depth": 4, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_33", "mon": "46", "level_bonus": 4, "min_depth": 4, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_36", "mon": "15", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_37", "mon": "46", "level_bonus": 3, "min_depth": 3, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_38", "mon": "11", "level_bonus": 4, "min_depth": 4, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_39", "mon": "19", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_40", "mon": "5", "level_bonus": 3, "min_depth": 3, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_41", "mon": "41", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_42", "mon": "64", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_43", "mon": "11", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_45", "mon": "16", "level_bonus": 4, "min_depth": 4, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_46", "mon": "46", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_47", "mon": "17", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_48", "mon": "46", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_49", "mon": "22", "level_bonus": 3, "min_depth": 3, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_50", "mon": "64", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_51", "mon": "16", "level_bonus": 4, "min_depth": 4, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_52", "mon": "76", "level_bonus": 3, "min_depth": 3, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_53", "mon": "40", "level_bonus": 3, "min_depth": 3, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_54", "mon": "15", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_55", "mon": "14", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_56", "mon": "67", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_57", "mon": "36", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_59", "mon": "15", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_60", "mon": "6", "level_bonus": 3, "min_depth": 3, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_61", "mon": "21", "level_bonus": 3, "min_depth": 3, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_62", "mon": "3", "level_bonus": 4, "min_depth": 4, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_63", "mon": "18", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_64", "mon": "81", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_66", "mon": "1", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_67", "mon": "11", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_68", "mon": "9", "level_bonus": 3, "min_depth": 3, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_69", "mon": "20", "level_bonus": 4, "min_depth": 4, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_70", "mon": "74", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_71", "mon": "57", "level_bonus": 4, "min_depth": 4, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_72", "mon": "63", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_73", "mon": "15", "level_bonus": 4, "min_depth": 4, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_74", "mon": "4", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_75", "mon": "21", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_76", "mon": "56", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_77", "mon": "3", "level_bonus": 3, "min_depth": 3, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_78", "mon": "24", "level_bonus": 3, "min_depth": 2, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_79", "mon": "64", "level_bonus": 4, "min_depth": 4, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_80", "mon": "76", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_81", "mon": "11", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
	{"key": "alpha_82", "mon": "11", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT", "source_hint": "BOUNTY_SOURCE"},
]

# Chance pro normalem Kampf, dass ein Kopfgeld-Monster eingestreut wird (zusätzlich zu denen, die von selbst kommen).
# Ein ganzer Run hat rund 26 normale Kämpfe: 1 - 0.985^26 ≈ 33 %, also etwa jeder dritte Run.
const BOUNTY_CHANCE := 0.015

func get_bounty(key: String) -> Dictionary:
	for bounty in BOUNTIES:
		if bounty.key == key:
			return bounty
	return {}

# Noch gesperrte Kopfgelder der Art als [{skill, hint, ...}].
func get_locked_bounties(mon_name: String) -> Array:
	var skills_by_key = Monmap.mon_metainfos_by_name(mon_name).get("bounty_egg_skills", {})
	var locked = []
	for bounty in BOUNTIES:
		var skill_name = skills_by_key.get(bounty.key, "")
		if skill_name != "" and not SaveManager.is_egg_skill_unlocked(mon_name, skill_name):
			var entry = bounty.duplicate()
			entry.skill = skill_name
			entry.hint = bounty_text(bounty, bounty.hint)
			locked.append(entry)
	return locked

# Hinweis- bzw. Quellen-Text eines Kopfgelds mit Zielname und Biom (tr() lässt fertige Texte unverändert).
func bounty_text(bounty: Dictionary, key: String) -> String:
	return tr(key).format({
		"mon": tr(bounty.label).format({"mon": Helper.mon_display_name(bounty.mon)}),
		"biome": bounty.min_depth + 1,
	})

# Kopfgelder, die für mindestens ein Team-Monster noch etwas freischalten und in dieser Biom-Tiefe auftauchen.
# Hat das Start-Monster den Meilenstein "bounty" offen, zählt jedes Kopfgeld dieser Tiefe.
func get_open_bounties(team: Array, depth: int) -> Array:
	var keys = []
	if starter_wants("starter_bounties"):
		for bounty in BOUNTIES:
			if bounty.min_depth <= depth:
				keys.append(bounty.key)
	for mon in team:
		# Arten, die nicht in der Ei-Auswahl stehen, schalten nichts frei (can_unlock_egg_skills)
		if not can_unlock_egg_skills(mon._name):
			continue
		for bounty in get_locked_bounties(mon._name):
			if bounty.min_depth <= depth and not keys.has(bounty.key):
				keys.append(bounty.key)
	return keys.map(func(key): return get_bounty(key))

# Das Kopfgeld-Monster wurde besiegt: freigeschaltet wird nur für die Art, die den letzten Treffer gelandet hat.
# Liefert den Namen der neu freigeschalteten Ei-Attacke oder "".
func claim_bounty(defeated: Monster) -> String:
	var killer = defeated._last_hit_by
	if defeated._bounty == "" or killer == null or not State.mons.has(killer) or not can_unlock_egg_skills(killer._name):
		return ""
	var skill_name = Monmap.mon_metainfos_by_name(killer._name).get("bounty_egg_skills", {}).get(defeated._bounty, "")
	if skill_name == "" or SaveManager.is_egg_skill_unlocked(killer._name, skill_name):
		return ""
	SaveManager.unlock_egg_skill(killer._name, skill_name)
	return skill_name

# ═════════════════════════
# SKILL-DATEN
# Feste Werte: value = fester Schaden bzw. Schild, scaling = Anteil des eigenen Werts obendrauf
# (Angriff: Ang. bzw. Sp. Ang., Schild: Vert.). Die Verteidigung des Ziels zählt beim Schaden nicht.
# Beispiel Leichter Windstoß: 5 Schaden + 0,2 x Sp. Ang.

const EARTH := Enums.MON_TYPES.EARTH
const FIRE := Enums.MON_TYPES.FIRE
const WATER := Enums.MON_TYPES.WATER
const AIR := Enums.MON_TYPES.AIR
const STEAM := FIRE | WATER
const LIGHTNING := FIRE | AIR
const MAGMA := EARTH | FIRE
const ICE := AIR | WATER
const DUST := EARTH | AIR
const MUD := EARTH | WATER
const THUNDERSTORM := AIR | WATER | FIRE
const VOLCANO := EARTH | FIRE | WATER
const ASH_STORM := EARTH | AIR | FIRE
const SWAMP := EARTH | AIR | WATER
const CHAOS := EARTH | FIRE | WATER | AIR
const PHYS := Enums.SKILL_DAMAGE_TYPE.PHYSICAL
const MAG := Enums.SKILL_DAMAGE_TYPE.ABILITY
const SELF := Enums.CARD_TARGETS.SELF
const ALLY := Enums.CARD_TARGETS.SINGLE_FRIEND

# ─────────────────────────
# Start-Skills (Ei-Attacken der Arten, siehe Monmap default_egg_skills), pro Grundelement:
#   Leichter Stoß 5 + 0,2 (keine Abklingzeit), Leichter Schlag 8 + 0,3 (Abklingzeit 1), Nutzloser Stoß 2 + 0,2,
#   je physisch (Ang.) und magisch (Sp. Ang.), dazu Leichter Schild 5 + 0,3 und Nutzloser Schild 2 + 0,2 (Vert.).
#   Alle Stufe 1, 1 Aktion.
# Welche Art welche drei bekommt, hängt von ihrem höchsten Kampfwert ab (Monmap).
var starter_skills = [
	# Earth
	_flat_attack_skill("SKILL_EARTH_PHYS_LIGHT_THRUST", EARTH, 5.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_EARTH_PHYS_LIGHT_STRIKE", EARTH, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_EARTH_PHYS_WEAK_THRUST", EARTH, 2.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_EARTH_MAG_LIGHT_THRUST", EARTH, 5.0, 0.2, MAG, 0),
	_flat_attack_skill("SKILL_EARTH_MAG_LIGHT_STRIKE", EARTH, 8.0, 0.3, MAG, 1),
	_flat_attack_skill("SKILL_EARTH_MAG_WEAK_THRUST", EARTH, 2.0, 0.2, MAG, 0),
	_flat_shield_skill("SKILL_EARTH_ARMOR_LIGHT", EARTH, 5.0, 0.3, 0),
	_flat_shield_skill("SKILL_EARTH_ARMOR_WEAK", EARTH, 2.0, 0.2, 0),
	# Fire
	_flat_attack_skill("SKILL_FIRE_PHYS_LIGHT_THRUST", FIRE, 5.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_FIRE_PHYS_LIGHT_STRIKE", FIRE, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_FIRE_PHYS_WEAK_THRUST", FIRE, 2.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_FIRE_MAG_LIGHT_THRUST", FIRE, 5.0, 0.2, MAG, 0),
	_flat_attack_skill("SKILL_FIRE_MAG_LIGHT_STRIKE", FIRE, 8.0, 0.3, MAG, 1),
	_flat_attack_skill("SKILL_FIRE_MAG_WEAK_THRUST", FIRE, 2.0, 0.2, MAG, 0),
	_flat_shield_skill("SKILL_FIRE_ARMOR_LIGHT", FIRE, 5.0, 0.3, 0),
	_flat_shield_skill("SKILL_FIRE_ARMOR_WEAK", FIRE, 2.0, 0.2, 0),
	# Water
	_flat_attack_skill("SKILL_WATER_PHYS_LIGHT_THRUST", WATER, 5.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_WATER_PHYS_LIGHT_STRIKE", WATER, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_WATER_PHYS_WEAK_THRUST", WATER, 2.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_WATER_MAG_LIGHT_THRUST", WATER, 5.0, 0.2, MAG, 0),
	_flat_attack_skill("SKILL_WATER_MAG_LIGHT_STRIKE", WATER, 8.0, 0.3, MAG, 1),
	_flat_attack_skill("SKILL_WATER_MAG_WEAK_THRUST", WATER, 2.0, 0.2, MAG, 0),
	_flat_shield_skill("SKILL_WATER_ARMOR_LIGHT", WATER, 5.0, 0.3, 0),
	_flat_shield_skill("SKILL_WATER_ARMOR_WEAK", WATER, 2.0, 0.2, 0),
	# Air
	_flat_attack_skill("SKILL_AIR_PHYS_LIGHT_THRUST", AIR, 5.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_AIR_PHYS_LIGHT_STRIKE", AIR, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_AIR_PHYS_WEAK_THRUST", AIR, 2.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_AIR_MAG_LIGHT_THRUST", AIR, 5.0, 0.2, MAG, 0),
	_flat_attack_skill("SKILL_AIR_MAG_LIGHT_STRIKE", AIR, 8.0, 0.3, MAG, 1),
	_flat_attack_skill("SKILL_AIR_MAG_WEAK_THRUST", AIR, 2.0, 0.2, MAG, 0),
	_flat_shield_skill("SKILL_AIR_ARMOR_LIGHT", AIR, 5.0, 0.3, 0),
	_flat_shield_skill("SKILL_AIR_ARMOR_WEAK", AIR, 2.0, 0.2, 0),
	# Zusätzliche Ei-Attacken der Startmonster (State.INITIAL_MONS), durch Fangen & Opfern freizuschalten
	# (Monmap unlockable_egg_skills), physisch bzw. magisch nach dem höheren Angriffswert:
	#   Angreifer: Kleiner Punch / Kleine [Element]kanone 5 + 0,3 (keine Abklingzeit),
	#              Punch / [Element]kanone 12 + 0,4 (Abklingzeit 1)
	#   Tanks:     Leichte Rückhand / Leichte [Element]kanone 8 + 0,3 (Abklingzeit 1),
	#              Leichter Schild (Vert.) 5 + 0,3
	# Earth
	_flat_attack_skill("SKILL_EARTH_PHYS_SMALL_PUNCH", EARTH, 5.0, 0.3, PHYS, 0),
	_flat_attack_skill("SKILL_EARTH_MAG_SMALL_CANNON", EARTH, 5.0, 0.3, MAG, 0),
	_flat_attack_skill("SKILL_EARTH_PHYS_PUNCH", EARTH, 12.0, 0.4, PHYS, 1),
	_flat_attack_skill("SKILL_EARTH_MAG_CANNON", EARTH, 12.0, 0.4, MAG, 1),
	_flat_attack_skill("SKILL_EARTH_PHYS_BACKHAND", EARTH, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_EARTH_MAG_LIGHT_CANNON", EARTH, 8.0, 0.3, MAG, 1),
	_flat_shield_skill("SKILL_EARTH_ARMOR_PLAIN", EARTH, 5.0, 0.3, 0),
	# Fire
	_flat_attack_skill("SKILL_FIRE_PHYS_SMALL_PUNCH", FIRE, 5.0, 0.3, PHYS, 0),
	_flat_attack_skill("SKILL_FIRE_MAG_SMALL_CANNON", FIRE, 5.0, 0.3, MAG, 0),
	_flat_attack_skill("SKILL_FIRE_PHYS_PUNCH", FIRE, 12.0, 0.4, PHYS, 1),
	_flat_attack_skill("SKILL_FIRE_MAG_CANNON", FIRE, 12.0, 0.4, MAG, 1),
	_flat_attack_skill("SKILL_FIRE_PHYS_BACKHAND", FIRE, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_FIRE_MAG_LIGHT_CANNON", FIRE, 8.0, 0.3, MAG, 1),
	_flat_shield_skill("SKILL_FIRE_ARMOR_PLAIN", FIRE, 5.0, 0.3, 0),
	# Water
	_flat_attack_skill("SKILL_WATER_PHYS_SMALL_PUNCH", WATER, 5.0, 0.3, PHYS, 0),
	_flat_attack_skill("SKILL_WATER_MAG_SMALL_CANNON", WATER, 5.0, 0.3, MAG, 0),
	_flat_attack_skill("SKILL_WATER_PHYS_PUNCH", WATER, 12.0, 0.4, PHYS, 1),
	_flat_attack_skill("SKILL_WATER_MAG_CANNON", WATER, 12.0, 0.4, MAG, 1),
	_flat_attack_skill("SKILL_WATER_PHYS_BACKHAND", WATER, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_WATER_MAG_LIGHT_CANNON", WATER, 8.0, 0.3, MAG, 1),
	_flat_shield_skill("SKILL_WATER_ARMOR_PLAIN", WATER, 5.0, 0.3, 0),
	# Air
	_flat_attack_skill("SKILL_AIR_PHYS_SMALL_PUNCH", AIR, 5.0, 0.3, PHYS, 0),
	_flat_attack_skill("SKILL_AIR_MAG_SMALL_CANNON", AIR, 5.0, 0.3, MAG, 0),
	_flat_attack_skill("SKILL_AIR_PHYS_PUNCH", AIR, 12.0, 0.4, PHYS, 1),
	_flat_attack_skill("SKILL_AIR_MAG_CANNON", AIR, 12.0, 0.4, MAG, 1),
	_flat_attack_skill("SKILL_AIR_PHYS_BACKHAND", AIR, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_AIR_MAG_LIGHT_CANNON", AIR, 8.0, 0.3, MAG, 1),
	_flat_shield_skill("SKILL_AIR_ARMOR_PLAIN", AIR, 5.0, 0.3, 0),
]

# Standard-Skills: ein Trank mit neuem Grundelement bietet sie zum Lernen an (ElementGainOverlay). Vorerst leer.
var standard_skills = []

# ─────────────────────────
# Skill-Listen. Den INHALT von egg_skills, defensive_skills, buff_skills, passive_skills, area_skills, milestone_skills,
# reward_skills und draft_skills sortiert tools/skill_verteilung.js bei jedem Lauf neu (Regeln in skill_regeln.txt):
#   Ei-Attacke oder Start-Skill einer Art -> gemeinsamer Pool (nach Art des Skills: Angriff, Schild, Buff, Passiv, Fläche)
#   nur Meilenstein einer Art            -> milestone_skills (nie wild, nie beim Trainer, nie im Couvert)
#   von keiner Art benutzt, ab Stufe 2   -> reward_skills (nur im Couvert)
#   von keiner Art benutzt, Stufe 1      -> draft_skills
# Neue Skills einfach in eine dieser Listen schreiben (am besten draft_skills), das Werkzeug ordnet sie ein.
# Kommentare INNERHALB dieser Listen schreibt das Werkzeug selbst (Element-Überschriften), eigene gehen verloren.
# "trainer": false = nicht beim Trainer (Stufe 4, Kombi-Top), bleibt am Skill stehen.
#
# Werte (fester Wert + Anteil x Wert, siehe Schadensformel). Element-Charakter: Feuer physische Angriffe, Luft magische
# Angriffe, Erde Schild etwas stärker ("+"): gilt pro enthaltenem Element auch in den Kombis.
#   Grundelement   Stufe 2 (CD 1, 1 Aktion)    Angriff 12 + 0,30 (+ 13 + 0,33)   Schild 12 + 0,30 (+ 14 + 0,33)
#                  Stufe 3 (CD 2, 1 Aktion)    Angriff 15 + 0,37 (+ 17 + 0,40)   Schild 16 + 0,37 (+ 18 + 0,40)
#                  Stufe 3 schnell (CD 0, 1)   Angriff 12 + 0,30 (+ 13 + 0,33)   Schild 12 + 0,30 (+ 14 + 0,33)
#   Zweier-Kombi   Stufe 3 Angriff (CD 2, 2)   30 + 0,50 (+ 33 + 0,55)
#                  Stufe 3 Schild  (CD 2, 1)   25 + 0,45 (+ 28 + 0,50)
#                  Stufe 4 Top     (CD 3, 2)   45 + 0,65 (+ 48 + 0,70)
#   Dreier-Kombi   Stufe 3 Angriff/Schild (CD 3, 3 Aktionen)   55 + 0,75 (+ 60 + 0,80)
#                  Stufe 4 Top     (CD 4, 3)   75 + 0,95 (+ 80 + 1,00)
#   Leichte Kombi-Skills (je 3 pro Kombi: physisch, magisch, Schild), billig und oft spielbar:
#   Zweier-Kombi   Stufe 2 (CD 1, 1 Aktion)    18 + 0,35 (+ 20 + 0,40)
#   Dreier-Kombi   Stufe 3 (CD 1, 1 Aktion)    20 + 0,50 (+ 22 + 0,55)
# Dreier-Schilde kosten 3 Aktionen: genau die verbilligt der Bollwerkmeister.
# Buffs: Stufe 2 ein Monster +25 % für 2 Züge (CD 2), Stufe 3 ganzes Team +12 % für 2 Züge (CD 3),
#   Stufe 4 Kombi-Buffs Team +15-18 % oder Einzel +35 % für 3 Züge (CD 3, 2 Aktionen).
# Passive: Stufe 3 Element-Passive des Grundelements (+10 %), Stufe 4 Kombi-Kraft (Angriffe mit allen Elementen der Kombi +15 %).

# Gemeinsamer Pool (wilde Monster im Biom-Pool, Trainer, Couvert ab Stufe 2): Angriffe
var egg_skills = [
	# Feuer
	_attack_skill("SKILL_FIRE_PHYS_FLAME_FIST", FIRE, 13.0, 0.33, PHYS, 2, 1, 1),
	_attack_skill("SKILL_FIRE_MAG_SPARK_SHOT", FIRE, 12.0, 0.3, MAG, 2, 1, 1),
	_attack_skill("SKILL_FIRE_PHYS_BLAZE_RUSH_SWIFT", FIRE, 13.0, 0.33, PHYS, 3, 0, 1),
	_attack_skill("SKILL_FIRE_MAG_FIREBALL_SWIFT", FIRE, 12.0, 0.3, MAG, 3, 0, 1),
	_attack_skill("SKILL_FIRE_PHYS_BLAZE_RUSH", FIRE, 17.0, 0.4, PHYS, 3, 2, 1),
	_attack_skill("SKILL_FIRE_MAG_FIREBALL", FIRE, 15.0, 0.37, MAG, 3, 2, 1),
	# Wasser
	_attack_skill("SKILL_WATER_PHYS_TIDE_SLAP", WATER, 12.0, 0.3, PHYS, 2, 1, 1),
	_attack_skill("SKILL_WATER_MAG_BUBBLE_BEAM", WATER, 12.0, 0.3, MAG, 2, 1, 1),
	_attack_skill("SKILL_WATER_MAG_HYDRO_LANCE_SWIFT", WATER, 12.0, 0.3, MAG, 3, 0, 1),
	_attack_skill("SKILL_WATER_PHYS_BREAKER", WATER, 15.0, 0.37, PHYS, 3, 2, 1),
	_attack_skill("SKILL_WATER_MAG_HYDRO_LANCE", WATER, 15.0, 0.37, MAG, 3, 2, 1),
	# Erde
	_attack_skill("SKILL_EARTH_PHYS_BOULDER_BASH", EARTH, 12.0, 0.3, PHYS, 2, 1, 1),
	_attack_skill("SKILL_EARTH_MAG_PEBBLE_STORM", EARTH, 12.0, 0.3, MAG, 2, 1, 1),
	_attack_skill("SKILL_EARTH_PHYS_QUAKE_STOMP_SWIFT", EARTH, 12.0, 0.3, PHYS, 3, 0, 1),
	_attack_skill("SKILL_EARTH_MAG_GEO_PULSE_SWIFT", EARTH, 12.0, 0.3, MAG, 3, 0, 1),
	_attack_skill("SKILL_EARTH_PHYS_QUAKE_STOMP", EARTH, 15.0, 0.37, PHYS, 3, 2, 1),
	_attack_skill("SKILL_EARTH_MAG_GEO_PULSE", EARTH, 15.0, 0.37, MAG, 3, 2, 1),
	# Luft
	_attack_skill("SKILL_AIR_PHYS_GUST_KICK", AIR, 12.0, 0.3, PHYS, 2, 1, 1),
	_attack_skill("SKILL_AIR_MAG_WIND_BLADE", AIR, 13.0, 0.33, MAG, 2, 1, 1),
	_attack_skill("SKILL_AIR_PHYS_CYCLONE_CLAW_SWIFT", AIR, 12.0, 0.3, PHYS, 3, 0, 1),
	_attack_skill("SKILL_AIR_MAG_TEMPEST_RAY_SWIFT", AIR, 13.0, 0.33, MAG, 3, 0, 1),
	_attack_skill("SKILL_AIR_PHYS_CYCLONE_CLAW", AIR, 15.0, 0.37, PHYS, 3, 2, 1),
	_attack_skill("SKILL_AIR_MAG_TEMPEST_RAY", AIR, 17.0, 0.4, MAG, 3, 2, 1),
	# Dampf
	_attack_skill("SKILL_STEAM_PHYS_SCALD_STRIKE", STEAM, 33.0, 0.55, PHYS, 3, 2, 2),
	_attack_skill("SKILL_STEAM_MAG_STEAM_JET", STEAM, 30.0, 0.5, MAG, 3, 2, 2),
	_attack_skill("SKILL_STEAM_PHYS_STEAM_HAMMER", STEAM, 48.0, 0.7, PHYS, 4, 3, 2),
	# Blitz
	_attack_skill("SKILL_LIGHTNING_PHYS_VOLT_PUNCH", LIGHTNING, 33.0, 0.55, PHYS, 3, 2, 2),
	_attack_skill("SKILL_LIGHTNING_MAG_ARC_BOLT", LIGHTNING, 33.0, 0.55, MAG, 3, 2, 2),
	_with(_attack_skill("SKILL_LIGHTNING_MAG_THUNDERCLAP", LIGHTNING, 48.0, 0.7, MAG, 4, 3, 2), {"trainer": false}),
	# Magma
	_attack_skill("SKILL_MAGMA_PHYS_LAVA_FIST", MAGMA, 33.0, 0.55, PHYS, 3, 2, 2),
	_with(_attack_skill("SKILL_MAGMA_PHYS_ERUPTION_SLAM", MAGMA, 48.0, 0.7, PHYS, 4, 3, 2), {"trainer": false}),
	# Eis
	_attack_skill("SKILL_ICE_PHYS_ICICLE_JAB", ICE, 30.0, 0.5, PHYS, 3, 2, 2),
	_attack_skill("SKILL_ICE_MAG_FROST_RAY", ICE, 33.0, 0.55, MAG, 3, 2, 2),
	_with(_attack_skill("SKILL_ICE_MAG_BLIZZARD", ICE, 48.0, 0.7, MAG, 4, 3, 2), {"trainer": false}),
	# Staub
	_attack_skill("SKILL_DUST_PHYS_SAND_CLAW", DUST, 30.0, 0.5, PHYS, 3, 2, 2),
	_attack_skill("SKILL_DUST_MAG_DUST_DEVIL", DUST, 33.0, 0.55, MAG, 3, 2, 2),
	_with(_attack_skill("SKILL_DUST_MAG_SANDSTORM", DUST, 48.0, 0.7, MAG, 4, 3, 2), {"trainer": false}),
	# Schlamm
	_attack_skill("SKILL_MUD_PHYS_MUD_SLAM", MUD, 30.0, 0.5, PHYS, 3, 2, 2),
	_attack_skill("SKILL_MUD_MAG_BOG_PULSE", MUD, 30.0, 0.5, MAG, 3, 2, 2),
	# Gewitter
	_with(_attack_skill("SKILL_THUNDERSTORM_MAG_SKYFALL", THUNDERSTORM, 80.0, 1.0, MAG, 4, 4, 3), {"trainer": false}),
	# Aschesturm
	_with(_attack_skill("SKILL_ASH_STORM_PHYS_ASHEN_ROLLER", ASH_STORM, 80.0, 1.0, PHYS, 4, 4, 3), {"trainer": false}),
	# Sumpf
	_with(_attack_skill("SKILL_SWAMP_MAG_BOG_MAW", SWAMP, 80.0, 1.0, MAG, 4, 4, 3), {"trainer": false}),
]
# Gemeinsamer Pool: Schilde
var defensive_skills = [
	# Feuer
	_shield_skill("SKILL_FIRE_ARMOR_CINDER_PLATE", FIRE, 12.0, 0.3, 2, 1, 1),
	_shield_skill("SKILL_FIRE_ARMOR_FLAME_WALL", FIRE, 16.0, 0.37, 3, 2, 1),
	# Wasser
	_shield_skill("SKILL_WATER_ARMOR_SHELL", WATER, 12.0, 0.3, 2, 1, 1),
	_shield_skill("SKILL_WATER_ARMOR_CORAL_WALL", WATER, 16.0, 0.37, 3, 2, 1),
	# Erde
	_shield_skill("SKILL_EARTH_ARMOR_GRANITE_BASTION_SWIFT", EARTH, 14.0, 0.33, 3, 0, 1),
	_shield_skill("SKILL_EARTH_ARMOR_STONE_SKIN", EARTH, 14.0, 0.33, 2, 1, 1),
	_shield_skill("SKILL_EARTH_ARMOR_GRANITE_BASTION", EARTH, 18.0, 0.4, 3, 2, 1),
	# Luft
	_shield_skill("SKILL_AIR_ARMOR_DRAFT_GUARD", AIR, 12.0, 0.3, 2, 1, 1),
	_shield_skill("SKILL_AIR_ARMOR_GALE_WALL", AIR, 16.0, 0.37, 3, 2, 1),
	# Blitz
	_shield_skill("SKILL_LIGHTNING_ARMOR_STATIC_PLATE", LIGHTNING, 25.0, 0.45, 3, 2, 1),
	# Magma
	_shield_skill("SKILL_MAGMA_ARMOR_OBSIDIAN_PLATE", MAGMA, 28.0, 0.5, 3, 2, 1),
	# Eis
	_shield_skill("SKILL_ICE_ARMOR_ICE_PLATE", ICE, 25.0, 0.45, 3, 2, 1),
	# Staub
	_shield_skill("SKILL_DUST_ARMOR_DUNE_WALL", DUST, 28.0, 0.5, 3, 2, 1),
	# Schlamm
	_with(_shield_skill("SKILL_MUD_ARMOR_LANDSLIDE_WALL", MUD, 48.0, 0.7, 4, 3, 2), {"trainer": false}),
]
# Gemeinsamer Pool: Buffs und Sonder-Verstärkungen
var buff_skills = [
	# Feuer
	_buff_skill("SKILL_FIRE_BUFF_ATK", FIRE, "atk", 25.0, 2, 2, 2, 1),
	_buff_skill("SKILL_FIRE_BUFF_S_ATK", FIRE, "s_atk", 25.0, 2, 2, 2, 1),
	_team_buff_skill("SKILL_FIRE_BUFF_TEAM_S_ATK", FIRE, "s_atk", 12.0, 2, 3, 3, 1),
	# Wasser
	_buff_skill("SKILL_WATER_BUFF_ATK", WATER, "atk", 25.0, 2, 2, 2, 1),
	_buff_skill("SKILL_WATER_BUFF_DEF", WATER, "def", 25.0, 2, 2, 2, 1),
	_buff_skill("SKILL_WATER_BUFF_S_ATK", WATER, "s_atk", 25.0, 2, 2, 2, 1),
	_boon_skill("SKILL_WATER_BOON_BLOOD_TIDE", WATER, "leech", 20.0, 1, ALLY, "hp", 3, 2, 2, "SKILL_BOON_LEECH_DESC"),
	# Erde
	_buff_skill("SKILL_EARTH_BUFF_ATK", EARTH, "atk", 25.0, 2, 2, 2, 1),
	_buff_skill("SKILL_EARTH_BUFF_DEF", EARTH, "def", 25.0, 2, 2, 2, 1),
	_buff_skill("SKILL_EARTH_BUFF_S_ATK", EARTH, "s_atk", 25.0, 2, 2, 2, 1),
	_team_buff_skill("SKILL_EARTH_BUFF_TEAM_ATK", EARTH, "atk", 12.0, 2, 3, 3, 1),
	_team_buff_skill("SKILL_EARTH_BUFF_TEAM_DEF", EARTH, "def", 12.0, 2, 3, 3, 1),
	_team_buff_skill("SKILL_EARTH_BUFF_TEAM_S_ATK", EARTH, "s_atk", 12.0, 2, 3, 3, 1),
	# Luft
	_buff_skill("SKILL_AIR_BUFF_ATK", AIR, "atk", 25.0, 2, 2, 2, 1),
	_buff_skill("SKILL_AIR_BUFF_DEF", AIR, "def", 25.0, 2, 2, 2, 1),
	_buff_skill("SKILL_AIR_BUFF_S_ATK", AIR, "s_atk", 25.0, 2, 2, 2, 1),
	_boon_skill("SKILL_AIR_BOON_TAILWIND", AIR, "extra_moves", 1.0, 3, ALLY, "speed", 3, 2, 2, "SKILL_BOON_EXTRA_MOVES_DESC"),
	# Dampf
	_with(_team_buff_skill("SKILL_STEAM_BUFF_T4", STEAM, "def", 15.0, 2, 4, 3, 2), {"trainer": false, "extras": [_extra("heal", 8.0, "", 0, 1.0)]}),
	# Blitz
	_with(_boon_skill("SKILL_LIGHTNING_BOON_OVERCHARGE", LIGHTNING, "crit", 50.0, 1, SELF, "atk", 4, 3, 2, "SKILL_BOON_CRIT_DESC"), {"trainer": false}),
	# Magma
	_with(_team_buff_skill("SKILL_MAGMA_BUFF_T4", MAGMA, "atk", 18.0, 2, 4, 3, 2), {"trainer": false}),
	# Eis
	_with(_buff_skill("SKILL_ICE_BUFF_T4", ICE, "s_atk", 35.0, 3, 4, 3, 2), {"trainer": false}),
	# Staub
	_with(_team_buff_skill("SKILL_DUST_BUFF_T4", DUST, "s_atk", 15.0, 2, 4, 3, 2), {"trainer": false}),
	# Schlamm
	_with(_team_buff_skill("SKILL_MUD_BUFF_T4", MUD, "def", 18.0, 2, 4, 3, 2), {"trainer": false}),
]
# Gemeinsamer Pool: Passive
var passive_skills = [
	# Wasser
	_passive_skill("SKILL_PASSIVE_WATER_POWER", WATER, 4.0, 3, "regen", "SKILL_PASSIVE_REGEN_DESC"),
	# Erde
	_passive_skill("SKILL_PASSIVE_EARTH_POWER", EARTH, 10.0, 3, "shield_power", "SKILL_PASSIVE_SHIELD_POWER_DESC"),
]
# Gemeinsamer Pool: Flächenschaden
var area_skills = []
# Nur über Meilensteine (Skills.MILESTONES): nicht im Pool, nicht beim Trainer, nicht im Couvert
var milestone_skills = [
	# Feuer
	_with(_passive_skill("SKILL_PASSIVE_FIRE_POWER", FIRE, 10.0, 3, "element_power", "SKILL_PASSIVE_ELEMENT_POWER_DESC"), {"passive_element": FIRE}),
	# Luft
	_passive_skill("SKILL_PASSIVE_AIR_POWER", AIR, 10.0, 3, "magic_power", "SKILL_PASSIVE_MAGIC_POWER_DESC"),
	# Dampf
	_shield_skill("SKILL_STEAM_ARMOR_STEAM_COAT", STEAM, 18.0, 0.35, 2, 1, 1),
	_attack_skill("SKILL_STEAM_PHYS_HOT_JAB", STEAM, 20.0, 0.4, PHYS, 2, 1, 1),
	_attack_skill("SKILL_STEAM_MAG_VAPOR_PUFF", STEAM, 18.0, 0.35, MAG, 2, 1, 1),
	_with(_passive_skill("SKILL_PASSIVE_STEAM_T4", STEAM, 15.0, 4, "element_power", "SKILL_PASSIVE_ELEMENT_POWER_DESC"), {"passive_element": STEAM, "trainer": false}),
	# Blitz
	_shield_skill("SKILL_LIGHTNING_ARMOR_CHARGE_PLATE", LIGHTNING, 18.0, 0.35, 2, 1, 1),
	_attack_skill("SKILL_LIGHTNING_PHYS_SHOCK_TAP", LIGHTNING, 20.0, 0.4, PHYS, 2, 1, 1),
	_attack_skill("SKILL_LIGHTNING_MAG_SPARK_BOLT", LIGHTNING, 20.0, 0.4, MAG, 2, 1, 1),
	_with(_passive_skill("SKILL_PASSIVE_BATTLE_FERVOR", LIGHTNING, 20.0, 3, "stat", "SKILL_PASSIVE_STAT_SELF_DESC"), {"passive_stat": "atk", "passive_scope": "self"}),
	_with(_passive_skill("SKILL_PASSIVE_STORM_SPIRIT", LIGHTNING, 20.0, 3, "stat", "SKILL_PASSIVE_STAT_SELF_DESC"), {"passive_stat": "s_atk", "passive_scope": "self"}),
	_with(_passive_skill("SKILL_PASSIVE_LIGHTNING_T4", LIGHTNING, 15.0, 4, "element_power", "SKILL_PASSIVE_ELEMENT_POWER_DESC"),
		{"passive_element": LIGHTNING, "trainer": false}),
	# Magma
	_shield_skill("SKILL_MAGMA_ARMOR_PUMICE_SKIN", MAGMA, 20.0, 0.4, 2, 1, 1),
	_attack_skill("SKILL_MAGMA_PHYS_EMBER_KNUCKLE", MAGMA, 20.0, 0.4, PHYS, 2, 1, 1),
	_attack_skill("SKILL_MAGMA_MAG_LAVA_SPIT", MAGMA, 18.0, 0.35, MAG, 2, 1, 1),
	_with(_passive_skill("SKILL_PASSIVE_MAGMA_T4", MAGMA, 15.0, 4, "element_power", "SKILL_PASSIVE_ELEMENT_POWER_DESC"),
		{"passive_element": MAGMA, "trainer": false}),
	# Eis
	_shield_skill("SKILL_ICE_ARMOR_RIME_COAT", ICE, 18.0, 0.35, 2, 1, 1),
	_attack_skill("SKILL_ICE_PHYS_FROST_BITE", ICE, 18.0, 0.35, PHYS, 2, 1, 1),
	_attack_skill("SKILL_ICE_MAG_SNOW_FLURRY", ICE, 20.0, 0.4, MAG, 2, 1, 1),
	_with(_passive_skill("SKILL_PASSIVE_ICE_T4", ICE, 15.0, 4, "element_power", "SKILL_PASSIVE_ELEMENT_POWER_DESC"),
		{"passive_element": ICE, "trainer": false}),
	# Staub
	_shield_skill("SKILL_DUST_ARMOR_SANDSTONE_SKIN", DUST, 20.0, 0.4, 2, 1, 1),
	_attack_skill("SKILL_DUST_PHYS_GRIT_PUNCH", DUST, 18.0, 0.35, PHYS, 2, 1, 1),
	_with(_passive_skill("SKILL_PASSIVE_DUST_T4", DUST, 15.0, 4, "element_power", "SKILL_PASSIVE_ELEMENT_POWER_DESC"),
		{"passive_element": DUST, "trainer": false}),
	# Schlamm
	_shield_skill("SKILL_MUD_ARMOR_MUD_COAT", MUD, 20.0, 0.4, 2, 1, 1),
	_attack_skill("SKILL_MUD_PHYS_MUD_PUNCH", MUD, 18.0, 0.35, PHYS, 2, 1, 1),
	_attack_skill("SKILL_MUD_MAG_SLUDGE_SHOT", MUD, 18.0, 0.35, MAG, 2, 1, 1),
	_passive_skill("SKILL_PASSIVE_BULWARK_MASTER", MUD, 1.0, 3, "shield_cost", "SKILL_PASSIVE_SHIELD_COST_DESC"),
	_with(_passive_skill("SKILL_PASSIVE_MUD_T4", MUD, 15.0, 4, "element_power", "SKILL_PASSIVE_ELEMENT_POWER_DESC"),
		{"passive_element": MUD, "trainer": false}),
	# Gewitter
	_attack_skill("SKILL_THUNDERSTORM_PHYS_STORM_FIST", THUNDERSTORM, 60.0, 0.8, PHYS, 3, 3, 3),
	_attack_skill("SKILL_THUNDERSTORM_MAG_CHAIN_LIGHTNING", THUNDERSTORM, 60.0, 0.8, MAG, 3, 3, 3),
	_attack_skill("SKILL_THUNDERSTORM_MAG_STATIC_RAIN", THUNDERSTORM, 22.0, 0.55, MAG, 3, 1, 1),
	# Vulkan
	_shield_skill("SKILL_VOLCANO_ARMOR_LAVA_CRUST", VOLCANO, 22.0, 0.55, 3, 1, 1),
	_attack_skill("SKILL_VOLCANO_PHYS_CALDERA_CRUSH", VOLCANO, 60.0, 0.8, PHYS, 3, 3, 3),
	_attack_skill("SKILL_VOLCANO_PHYS_VOLCANIC_FIST", VOLCANO, 22.0, 0.55, PHYS, 3, 1, 1),
	_shield_skill("SKILL_VOLCANO_ARMOR_BASALT_FORT", VOLCANO, 60.0, 0.8, 3, 3, 3),
	# Aschesturm
	_attack_skill("SKILL_ASH_STORM_PHYS_CINDER_CLAW", ASH_STORM, 60.0, 0.8, PHYS, 3, 3, 3),
	_attack_skill("SKILL_ASH_STORM_MAG_ASH_CYCLONE", ASH_STORM, 60.0, 0.8, MAG, 3, 3, 3),
	_attack_skill("SKILL_ASH_STORM_PHYS_SOOT_STRIKE", ASH_STORM, 22.0, 0.55, PHYS, 3, 1, 1),
	_attack_skill("SKILL_ASH_STORM_MAG_EMBER_GUST", ASH_STORM, 22.0, 0.55, MAG, 3, 1, 1),
	# Sumpf
	_attack_skill("SKILL_SWAMP_PHYS_ROOT_LASH", SWAMP, 55.0, 0.75, PHYS, 3, 3, 3),
	_attack_skill("SKILL_SWAMP_MAG_MIASMA_CLOUD", SWAMP, 60.0, 0.8, MAG, 3, 3, 3),
	_attack_skill("SKILL_SWAMP_MAG_SPORE_PUFF", SWAMP, 22.0, 0.55, MAG, 3, 1, 1),
]
# Kopfgeld-Ei-Attacken (Skills.BOUNTIES)
var bounty_skills = [
	# Staub
	_attack_skill("SKILL_DUST_MAG_DUST_SHOT", DUST, 20.0, 0.4, MAG, 2, 1, 1),
	# Gewitter
	_shield_skill("SKILL_THUNDERSTORM_ARMOR_RAIN_GUARD", THUNDERSTORM, 20.0, 0.5, 3, 1, 1),
	_shield_skill("SKILL_THUNDERSTORM_ARMOR_STORM_PLATE", THUNDERSTORM, 55.0, 0.75, 3, 3, 3),
	_attack_skill("SKILL_THUNDERSTORM_PHYS_SQUALL_STRIKE", THUNDERSTORM, 22.0, 0.55, PHYS, 3, 1, 1),
	# Aschesturm
	_shield_skill("SKILL_ASH_STORM_ARMOR_CINDER_SHELL", ASH_STORM, 22.0, 0.55, 3, 1, 1),
	# Sumpf
	_attack_skill("SKILL_SWAMP_PHYS_REED_WHIP", SWAMP, 20.0, 0.5, PHYS, 3, 1, 1),
]
# Nur im Couvert der Bosse: Skills ab Stufe 2, die keine Art benutzt
var reward_skills = [
	# Feuer
	_boon_skill("SKILL_FIRE_BOON_FOCUS_FLAME", FIRE, "crit_next", 50.0, -1, SELF, "atk", 3, 2, 1, "SKILL_BOON_CRIT_NEXT_DESC"),
	# Dampf
	_shield_skill("SKILL_STEAM_ARMOR_VAPOR_PLATE", STEAM, 25.0, 0.45, 3, 2, 1),
	# Magma
	_attack_skill("SKILL_MAGMA_MAG_MAGMA_BURST", MAGMA, 30.0, 0.5, MAG, 3, 2, 2),
	# Schlamm
	_shield_skill("SKILL_MUD_ARMOR_CLAY_SHELL", MUD, 28.0, 0.5, 3, 2, 1),
	_with(_passive_skill("SKILL_PASSIVE_DEEP_VITALITY", MUD, 20.0, 3, "stat", "SKILL_PASSIVE_STAT_SELF_DESC"), {"passive_stat": "hp", "passive_scope": "self"}),
	# Vulkan
	_attack_skill("SKILL_VOLCANO_MAG_PYROCLAST", VOLCANO, 55.0, 0.75, MAG, 3, 3, 3),
	_attack_skill("SKILL_VOLCANO_MAG_FUME_BURST", VOLCANO, 20.0, 0.5, MAG, 3, 1, 1),
	_attack_skill("SKILL_VOLCANO_PHYS_MAGMA_TITAN", VOLCANO, 80.0, 1.0, PHYS, 4, 4, 3),
	# Aschesturm
	_shield_skill("SKILL_ASH_STORM_ARMOR_SLAG_ARMOR", ASH_STORM, 60.0, 0.8, 3, 3, 3),
	# Sumpf
	_shield_skill("SKILL_SWAMP_ARMOR_MANGROVE_WALL", SWAMP, 60.0, 0.8, 3, 3, 3),
	# Chaos
	_boon_skill("SKILL_CHAOS_BOON_BATTLE_CRY", CHAOS, "taunt", 1.0, 0, SELF, "def", 2, 2, 1, "SKILL_BOON_TAUNT_DESC"),
	_passive_skill("SKILL_PASSIVE_PROVOKER", CHAOS, 1.0, 4, "taunt", "SKILL_PASSIVE_TAUNT_DESC"),
]

# ─────────────────────────
# Couvert der Bosse (Fähigkeiten-Belohnung): REWARD_SKILL_OFFERS Skills der Stufen 2-4 zur Auswahl, ohne Preis.
# Gezogen wird aus reward_skills und dem gemeinsamen Pool (ohne Meilenstein-Skills), was in diesem Run noch niemand
# aus einem Couvert gelernt hat. Die Stufe hängt von der Seltenheit des Teams ab (reward_tier_weights):
# je seltener das Team, desto eher Stufe 4. Ein Team nur aus gewöhnlichen Monstern bekommt höchstens Stufe 3.
const REWARD_SKILL_OFFERS := 3
const REWARD_MIN_TIER := 2

## Durchschnittliche Seltenheit des Teams: 0 = nur gewöhnliche ... 5 = nur mythische (Enums.MON_RARITY)
func team_rarity() -> float:
	if State.mons.is_empty():
		return 0.0
	var total := 0.0
	for mon in State.mons:
		total += Monmap.rarity_of(mon._name)
	return total / State.mons.size()

## Gewicht pro Stufe im Couvert. Stufe 4 gibt es erst, wenn mindestens ein Monster seltener als gewöhnlich ist.
##   Team im Schnitt    Stufe 2  Stufe 3  Stufe 4
##   gewöhnlich (0)       50       35        0
##   ungewöhnlich (1)     44       37       13
##   selten (2)           38       39       21
##   episch (3)           32       41       29
##   legendär (4)         26       43       37
func reward_tier_weights(rarity: float) -> Dictionary:
	return {
		2: maxf(50.0 - 6.0 * rarity, 10.0),
		3: 35.0 + 2.0 * rarity,
		4: 0.0 if rarity <= 0.0 else 5.0 + 8.0 * rarity,
	}

## Alles, was ein Couvert gerade anbieten kann (ab REWARD_MIN_TIER, in diesem Run noch nicht aus einem Couvert gelernt)
func reward_pool() -> Array:
	var seen := {}
	var pool := []
	for skill in reward_skills + pool_skills():
		if skill.get("tier", 1) < REWARD_MIN_TIER or seen.has(skill.name) or State.taught_reward_skills.has(skill.name):
			continue
		seen[skill.name] = true
		pool.append(skill)
	return pool

# Auswahl fürs Couvert: Stufe nach der Seltenheit des Teams, mindestens ein Skill für das Team sofort einsetzbar,
# sofern es so einen noch gibt.
func reward_offers() -> Array:
	var weights := reward_tier_weights(team_rarity())
	var pool: Array = reward_pool().filter(func(skill): return weights.get(skill.tier, 0.0) > 0.0)
	var offers := []
	for i in REWARD_SKILL_OFFERS:
		var skill = _pick_reward(pool, weights)
		if skill == null:
			break
		offers.append(skill)
		pool.erase(skill)
	var usable := func(skill): return State.mons.any(func(mon): return can_use(mon, skill))
	if not offers.is_empty() and not offers.any(usable):
		var fitting := pool.filter(usable)
		if not fitting.is_empty():
			offers[0] = _pick_reward(fitting, weights)
	return offers.map(func(skill): return get_skill(skill.name))

## Zieht zuerst eine Stufe nach Gewicht (nur Stufen, die es im Pool gibt), dann zufällig einen Skill dieser Stufe
func _pick_reward(pool: Array, weights: Dictionary):
	if pool.is_empty():
		return null
	var by_tier := {}
	for skill in pool:
		by_tier.get_or_add(skill.tier, []).append(skill)
	var total := 0.0
	for tier in by_tier:
		total += weights.get(tier, 0.0)
	var roll := randf() * total
	for tier in by_tier:
		roll -= weights.get(tier, 0.0)
		if roll <= 0.0:
			return by_tier[tier].pick_random()
	return pool.pick_random()

# Aufstiegs-Skills: Trinkt ein Monster einen Element-Trank und steigt dadurch zu einem Kombi-Element auf,
# kann es den Skill genau dieses Elements lernen (Treasure.add_potion_card, ElementGainOverlay). Vorerst leer.
var ascension_skills = []

# ─────────────────────────
# Entwürfe: Skills der Stufe 1, die keine Art benutzt, und neue Skills, bis tools/skill_verteilung.js sie einsortiert.
# get_skill findet sie, das Wiki listet sie unter "Unbenutzt". Werte-Tabelle: siehe oben bei den Skill-Listen.
var draft_skills = [
	# Sumpf
	_shield_skill("SKILL_SWAMP_ARMOR_MOSS_HIDE", SWAMP, 22.0, 0.55, 3, 1, 1),
]

## Aufstiegs-Skill für genau dieses Kombi-Element (frische Kopie), {} für Grundelemente und Chaos
func ascension_skill(nature: int) -> Dictionary:
	for skill in ascension_skills:
		if skill.nature == nature:
			return get_skill(skill.name)
	return {}

# ─────────────────────────
# Bausteine. Jeder gibt nur ein Dictionary zurück (das Wiki liest sie aus, siehe tools/wiki/build_wiki.js).

## Angriff auf ein Ziel: value fester Schaden + scaling x (Sp.) Angriff, Stufe 1, 1 Aktion
func _flat_attack_skill(skill_name: String, nature: int, value: float, scaling: float, damage_type: int, cooldown: int) -> Dictionary:
	return {
		"cost": 1,
		"name": skill_name,
		"nature": nature,
		"value": value,
		"scaling": scaling,
		"cooldown": cooldown,
		"damage_type": damage_type,
		"effect": "damage",
		"description": "SKILL_DAMAGE_PHYSICAL_DESC" if damage_type == Enums.SKILL_DAMAGE_TYPE.PHYSICAL else "SKILL_DAMAGE_ABILITY_DESC",
		"target": Enums.CARD_TARGETS.SINGLE_ENEMY,
		"scouted": false,
		"tier": 1,
		"shop_cost": {"min": 5, "max": 15},
		"handle": func(props): deal_damage(props)
	}

## Schild auf ein eigenes Monster: value fester Schild + scaling x Verteidigung, Stufe 1, 1 Aktion. Blockt physisch und magisch.
func _flat_shield_skill(skill_name: String, nature: int, value: float, scaling: float, cooldown: int) -> Dictionary:
	return {
		"cost": 1,
		"name": skill_name,
		"nature": nature,
		"value": value,
		"scaling": scaling,
		"cooldown": cooldown,
		"effect": "shield",
		"description": "SKILL_SHIELD_DESC",
		"target": Enums.CARD_TARGETS.SINGLE_FRIEND,
		"scouted": false,
		"tier": 1,
		"shop_cost": {"min": 5, "max": 15},
		"handle": func(props): add_shield(props)
	}

## Angriff auf ein Ziel mit Stufe, Abklingzeit und Kosten (Entwürfe, siehe draft_skills)
func _attack_skill(skill_name: String, nature: int, value: float, scaling: float, damage_type: int, tier: int, cooldown: int, cost: int) -> Dictionary:
	return {
		"cost": cost,
		"name": skill_name,
		"nature": nature,
		"value": value,
		"scaling": scaling,
		"cooldown": cooldown,
		"damage_type": damage_type,
		"effect": "damage",
		"description": "SKILL_DAMAGE_PHYSICAL_DESC" if damage_type == Enums.SKILL_DAMAGE_TYPE.PHYSICAL else "SKILL_DAMAGE_ABILITY_DESC",
		"target": Enums.CARD_TARGETS.SINGLE_ENEMY,
		"scouted": false,
		"tier": tier,
		"shop_cost": {"min": 5 * tier, "max": 15 * tier},
		"handle": func(props): deal_damage(props)
	}

## Schild auf ein eigenes Monster mit Stufe, Abklingzeit und Kosten (Entwürfe, siehe draft_skills)
func _shield_skill(skill_name: String, nature: int, value: float, scaling: float, tier: int, cooldown: int, cost: int) -> Dictionary:
	return {
		"cost": cost,
		"name": skill_name,
		"nature": nature,
		"value": value,
		"scaling": scaling,
		"cooldown": cooldown,
		"effect": "shield",
		"description": "SKILL_SHIELD_DESC",
		"target": Enums.CARD_TARGETS.SINGLE_FRIEND,
		"scouted": false,
		"tier": tier,
		"shop_cost": {"min": 5 * tier, "max": 15 * tier},
		"handle": func(props): add_shield(props)
	}

## Buff auf ein eigenes Monster (add_buff): value % mehr auf stat für turns eigene Züge des Ziels
func _buff_skill(skill_name: String, nature: int, stat: String, value: float, turns: int, tier: int, cooldown: int, cost: int) -> Dictionary:
	return {
		"cost": cost,
		"name": skill_name,
		"nature": nature,
		"value": value,
		"cooldown": cooldown,
		"damage_type": Enums.SKILL_DAMAGE_TYPE.ABILITY,
		"effect": "buff",
		"buff_stat": stat,
		"buff_turns": turns,
		"description": "SKILL_BUFF_SINGLE_DESC",
		"target": Enums.CARD_TARGETS.SINGLE_FRIEND,
		"scouted": false,
		"tier": tier,
		"shop_cost": {"min": 5 * tier, "max": 15 * tier},
		"handle": func(props): add_buff(props)
	}

## Buff auf jedes eigene Monster (add_buff pro Monster)
func _team_buff_skill(skill_name: String, nature: int, stat: String, value: float, turns: int, tier: int, cooldown: int, cost: int) -> Dictionary:
	return {
		"cost": cost,
		"name": skill_name,
		"nature": nature,
		"value": value,
		"cooldown": cooldown,
		"damage_type": Enums.SKILL_DAMAGE_TYPE.ABILITY,
		"effect": "buff",
		"buff_stat": stat,
		"buff_turns": turns,
		"description": "SKILL_BUFF_TEAM_DESC",
		"target": Enums.CARD_TARGETS.TEAM_FRIEND,
		"scouted": false,
		"tier": tier,
		"shop_cost": {"min": 5 * tier, "max": 15 * tier},
		"handle": func(props): add_buff(props)
	}

## Sonder-Verstärkung (add_boon): boon = Art (BOON_KINDS), value = Stärke, turns = eigene Züge des Ziels (-1 = bis verbraucht),
## target SELF oder SINGLE_FRIEND, icon_stat = Symbol auf der Karte (affected_stat)
func _boon_skill(skill_name: String, nature: int, boon: String, value: float, turns: int, target: int, icon_stat: String, tier: int, cooldown: int, cost: int, description: String) -> Dictionary:
	return {
		"cost": cost,
		"name": skill_name,
		"nature": nature,
		"value": value,
		"cooldown": cooldown,
		"damage_type": Enums.SKILL_DAMAGE_TYPE.ABILITY,
		"effect": "boon",
		"boon": boon,
		"buff_turns": turns,
		"icon_stat": icon_stat,
		"description": description,
		"target": target,
		"scouted": false,
		"tier": tier,
		"shop_cost": {"min": 5 * tier, "max": 15 * tier},
		"handle": func(props): add_boon(props)
	}

## Passiver Skill (effect "passive", passive = Art, siehe Passive weiter oben), kann nicht ausgespielt werden
func _passive_skill(skill_name: String, nature: int, value: float, tier: int, passive: String, description: String) -> Dictionary:
	return {
		"cost": 0,
		"name": skill_name,
		"nature": nature,
		"value": value,
		"cooldown": 0,
		"damage_type": Enums.SKILL_DAMAGE_TYPE.ABILITY,
		"effect": "passive",
		"passive": passive,
		"description": description,
		"target": Enums.CARD_TARGETS.TEAM_FRIEND,
		"scouted": false,
		"tier": tier,
		"shop_cost": {"min": 5 * tier, "max": 15 * tier},
		"handle": func(_props): pass
	}

## Extra einer Karte (siehe "Extras" weiter oben). stat "" und turns 0, wo sie nicht gebraucht werden.
func _extra(kind: String, value: float, stat: String, turns: int, chance: float) -> Dictionary:
	return {"kind": kind, "value": value, "stat": stat, "turns": turns, "chance": chance}

func _with(skill: Dictionary, extra: Dictionary) -> Dictionary:
	skill.merge(extra, true)
	return skill
