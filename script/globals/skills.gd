extends Node

func deal_damage(props):
	# für Kopfgelder: wer zuletzt getroffen hat, hat das Monster besiegt
	props.mon._last_hit_by = props.from
	var full_damage = calc_damage(props.from, props.mon, props.skill)
	reveal_stats_by_hit(props.from, props.mon, props.skill)
	# Schilde fangen den Schaden zuerst ab, Magma und Schlamm gehen mit etwas Glück durch den passenden Schild
	var absorbed: float = full_damage
	if ElementEffects.rolls_pierce(props.skill, props.from):
		ElementEffects.show_pierce(props.mon, is_physical(props.skill))
	else:
		absorbed = props.mon.absorb_damage(full_damage, is_physical(props.skill))
	# Übungskampf: niemand geht K.O.
	var damage = Tutorial.cap_damage(props.mon, absorbed)
	# für Element-Effekte, die vom verursachten Schaden abhängen (Eis), siehe battle.gd _use_skill
	props.dealt = props.get("dealt", 0.0) + damage
	props.blocked = props.get("blocked", 0.0) + full_damage - absorbed
	var multiplier = element_multiplier(props.skill.nature, props.mon._type)
	print("lose:" + str(props.skill.value) + ":" + str(damage) + " (Element x" + str(multiplier) + ")")
	Events.monster_hit_with_element.emit(props.mon, damage, multiplier, full_damage - damage)
	var kills: bool = props.mon.is_alive() and roundi(props.mon.hp() - props.mon._lost_hp - damage) <= 0
	if State.mons.has(props.mon) and kills:
		State.record_own_faint(props.mon, props.from, props.skill, damage, multiplier)
	props.mon._lost_hp += damage
	# Passiv "Heilung bei K.O.": der Angreifer heilt sich um einen Anteil seiner max. KP
	if kills and props.from.is_alive():
		var kill_heal := own_passive_sum(props.from, "kill_heal")
		if kill_heal > 0.0:
			heal(props.from, props.from.hp() * kill_heal / 100.0)

# ─────────────────────────
# Schadensformel
# Jeder Skill hat einen festen Schaden (value) und bekommt einen Anteil (scaling) des eigenen Angriffs obendrauf:
# physisch vom Angriff, magisch vom Sp. Angriff. Verteidigung und Sp. Verteidigung des Ziels zählen nicht,
# nur Schilde fangen Schaden ab. Danach wirkt der Element-Faktor.

# Treffer decken Werte auf: trifft man den Gegner, wird seine (Sp.) Verteidigung aufgedeckt,
# trifft er einen selbst, sein (Sp.) Angriff.
func reveal_stats_by_hit(from: Monster, to: Monster, skill: Dictionary) -> void:
	var physical = is_physical(skill)
	if State.mons.has(from) and not State.mons.has(to):
		State.reveal_mon_stat(to._name, "def" if physical else "s_def")
	elif State.mons.has(to) and not State.mons.has(from):
		State.reveal_mon_stat(from._name, "atk" if physical else "s_atk")

func is_physical(skill: Dictionary) -> bool:
	return skill.get("damage_type", Enums.SKILL_DAMAGE_TYPE.PHYSICAL) == Enums.SKILL_DAMAGE_TYPE.PHYSICAL

func calc_damage(from: Monster, to: Monster, skill: Dictionary) -> float:
	# schlummernde Skills schwächer und nur mit den Elementen des Angreifers
	skill = effective_skill(from, skill)
	var physical = is_physical(skill)
	var atk: float = from.attack() if physical else from.s_attack()
	# Passive, Aufladungen und Extras (Jäger, Ausnutzen) wirken als Faktor auf den ganzen Schaden
	return stat_damage(atk, skill.value, skill.get("scaling", 0.0), damage_factor(from, to, skill) * element_multiplier(skill.nature, to._type))

## Faktor auf den Skill-Wert eines Angriffs (1.0 = unverändert), alle Boni addieren sich:
## Passive des Angreifers (Element-Kraft, Magie-Kraft), seine Aufladung für diese Schadensart
## und die Extras der Karte gegen geschwächte oder angeschlagene Ziele.
func damage_factor(from: Monster, to: Monster, skill: Dictionary) -> float:
	var bonus := 0.0
	if not is_physical(skill):
		bonus += own_passive_sum(from, "magic_power")
	for passive in own_passives(from, "element_power"):
		if skill.nature & passive.get("passive_element", 0):
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
	return skill.target in [Enums.CARD_TARGETS.SINGLE_FRIEND, Enums.CARD_TARGETS.TEAM_FRIEND]

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

# ─────────────────────────
# Schilde halten bis zum nächsten eigenen Zug des geschützten Monsters oder bis sie aufgebraucht sind (siehe Monster.start_turn, Monster.absorb_damage).
# Physische Schilde fangen nur physischen Schaden ab, magische nur magischen.

# Rüstung: fester Wert + scaling x Verteidigung des Wirkers, Magie-Schild: fester Wert + scaling x seine Sp. Verteidigung.
func add_shield(props):
	props.mon.add_shield(shield_amount(props.from, props.skill), is_physical(props.skill))

## Schildstärke, die der Wirker mit dieser Karte gibt (auch für Karten, Absichten und KI):
## fester Wert + scaling x seine (Sp.) Verteidigung, Schild-Passive des Wirkers kommen obendrauf.
func shield_amount(from: Monster, skill: Dictionary) -> float:
	var used := effective_skill(from, skill)
	var physical := is_physical(used)
	var def: float = from.defense() if physical else from.s_defense()
	var bonus := own_passive_sum(from, "shield_power" if physical else "s_shield_power") / 100.0
	return ceilf((used.value + used.get("scaling", 0.0) * def) * (1.0 + bonus))

# Buff: value % mehr auf buff_stat für buff_turns eigene Züge des Ziels.
# +1, weil Buffs zu Beginn jedes eigenen Zuges herunterzählen (wie bei den Element-Effekten).
func add_buff(props):
	props.mon.add_buff(props.skill.buff_stat, props.skill.value / 100, props.skill.buff_turns + 1)

# ─────────────────────────
# Absichten: Gegner planen ihren nächsten Zug im Voraus (Monster._intent, battle.gd _plan_intent),
# der Spieler sieht vorher, wen sie mit wie viel Schaden treffen werden.

# Trifft eine geplante Aktion dieses Monster? Flächen-Skills treffen alle auf der Seite des Ziels.
func action_hits(action: Dictionary, mon: Monster) -> bool:
	if action.target == mon:
		return true
	return targets_team(action.skill) and action.target != null and State.mons.has(action.target) == State.mons.has(mon)

# Geplante Angriffe der attackers auf target, einer pro Eintrag:
# {"physical": bool, "full": ohne Schild, "after": nach Schild}. Physisch und magisch zählen getrennt gegen ihren Schild,
# und jeder Treffer verbraucht den Schild, wie Monster.absorb_damage es im Kampf tut.
func incoming_hits(target: Monster, attackers: Array) -> Array:
	var shield = target._shield
	var s_shield = target._s_shield
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
			# und steht nicht in der Vorschau.
			var blocked = minf(shield if physical else s_shield, full)
			if physical:
				shield -= blocked
			else:
				s_shield -= blocked
			hits.append({"physical": physical, "full": full, "after": full - blocked})
	return hits

# ─────────────────────────
# Passive Skills (effect "passive", Feld "passive" = Art). Es gilt die Element-Regel: nur Monster, die den Skill einsetzen
# könnten, bekommen bzw. geben den Bonus, schlummernd abgeschwächt (effective_skill). Alle Werte in Prozent.
#   "stat":           +value % auf passive_stat. passive_scope: "self" = nur das Monster, "partner" = das nächste Monster
#                     im Team (beim letzten das erste), "team" = jedes Monster im Team (auch es selbst)
#   "element_power":  eigene Angriffe mit passive_element machen +value % Schaden
#   "magic_power":    eigene magische Angriffe machen +value % Schaden
#   "shield_power":   eigene physische Schilde +value %,  "s_shield_power": eigene magische Schilde +value %
#   "effect_chance":  eigene Element-Effekte lösen value % öfter aus (Karten mit Auslösechance, Vulkan)
#   "leech":          heilt sich um value % des verursachten Schadens
#   "kill_heal":      heilt sich um value % seiner max. KP, wenn es einen Gegner besiegt

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
	var leech := own_passive_sum(from, "leech") if is_damage_skill(skill) else 0.0
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

## Heilt bis zu den vollen KP und zeigt "+N" (gleiche Anzeige wie die Heil-Relikte)
func heal(mon: Monster, amount: float) -> void:
	if not mon.is_alive() or mon._lost_hp <= 0.0:
		return
	BossRelics.heal(mon, amount)
	Events.status_vfx.emit(mon, "heal")

## Kurzname eines Werts ("ANG", "SVE", ...) für Texte
const STAT_LABELS := {"hp": "STAT_HP", "atk": "STAT_ATK", "def": "STAT_DEF", "s_atk": "STAT_SPA", "fail": "STAT_FAIL",
	"s_def": "STAT_SPD", "speed": "STAT_SPE"}

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
	for list in [starter_skills, standard_skills, egg_skills, defensive_skills, buff_skills, passive_skills, area_skills, bounty_skills, reward_skills, ascension_skills]:
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
## Standard-Skills, Kopfgeld-, Couvert- und Aufstiegs-Skills gehören nicht dazu.
func pool_skills() -> Array:
	return egg_skills + defensive_skills + buff_skills + passive_skills + area_skills

## Effekt-Skills des Pools (alles außer Schaden auf ein Ziel)
func effect_skills() -> Array:
	return defensive_skills + buff_skills + passive_skills + area_skills

## Tauchen bei wilden Monstern im Biom-Pool auf (Feld "wild": false = nur über Ei-Attacken der Arten)
func is_wild_skill(skill: Dictionary) -> bool:
	return skill.get("wild", true)

## Kann der Trainer lehren (Feld "trainer": false = nicht beim Trainer)
func is_trainer_skill(skill: Dictionary) -> bool:
	return skill.get("trainer", true)

## Standard-Skill eines Grundelements für eine Kategorie ("physical", "magic", "shield", "s_shield"), {} wenn keiner
func standard_skill(element: int, category: String) -> Dictionary:
	for skill in standard_skills:
		if skill.nature == element and stat_category(skill) == category:
			return get_skill(skill.name)
	return {}

## Kategorie nach dem Wert, mit dem ein Skill rechnet: Angriff -> "physical", Sp. Angriff -> "magic",
## Verteidigung -> "shield", Sp. Verteidigung -> "s_shield" (Buffs und Passive: "")
func stat_category(skill: Dictionary) -> String:
	if is_damage_skill(skill):
		return "physical" if is_physical(skill) else "magic"
	if skill.get("effect", "") == "shield":
		return "shield" if is_physical(skill) else "s_shield"
	return ""

## Die vier Kampfwerte eines Monsters nach Größe sortiert, als Kategorien (siehe stat_category)
const CATEGORY_STATS := {"physical": "atk", "magic": "s_atk", "shield": "def", "s_shield": "s_def"}

func categories_by_stat(mon: Monster) -> Array:
	var values := {"physical": mon.attack(), "magic": mon.s_attack(), "shield": mon.defense(), "s_shield": mon.s_defense()}
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

# Ist dieser Skill eines Monsters eine Ei-Attacke, die durch Opfern freigeschaltet werden kann?
func is_unlockable_egg_skill(mon: Monster, skill: Dictionary) -> bool:
	return skill.get("egg_skill", false) and get_locked_egg_skills(mon._name).has(skill.name)

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
			return ["EGG_SOURCE_BOUNTY", bounty.source_hint]
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

## Icon oben rechts auf Karten und in Tabellen: der Wert, den die Fähigkeit verändert, mit denselben Symbolen wie die
## Werte-Tabellen (StatsGrid.ICONS). Schaden = Angriffswert (Faust bzw. Funken), Schild = Verteidigung (Schild bzw.
## Magie-Schild), Buff und Passiv = der verstärkte Wert (z. B. Herz bei KP). Unbekanntes Passiv: Passiv-Symbol.
func kind_icon(skill: Dictionary) -> Texture2D:
	var stat := affected_stat(skill)
	if stat != "":
		return StatsGrid.ICONS[stat]
	if is_passive(skill):
		return PASSIVE_ICON
	return PHYSICAL_ICON if is_physical(skill) else MAGIC_ICON

## Stat-Key, den die Fähigkeit verändert bzw. mit dem sie rechnet ("" = keiner)
func affected_stat(skill: Dictionary) -> String:
	var stat: String = ""
	if is_passive(skill):
		stat = skill.get("passive_stat", "")
	elif skill.get("effect", "") == "buff":
		stat = skill.get("buff_stat", "")
	elif is_damage_skill(skill):
		stat = "atk" if is_physical(skill) else "s_atk"
	elif skill.get("effect", "") == "shield" or not is_damage_skill(skill):
		stat = "def" if is_physical(skill) else "s_def"
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
	elif egg_skill_category(skill) == "shield":
		stat = "def" if physical else "s_def"
	if stat == "" or not used.has("scaling"):
		return Helper.format_number(value)
	if mon == null or not _stat_visible(mon, stat):
		return "%s+%sx" % [Helper.format_number(value), Helper.format_number(used.scaling)]
	if stat == "def" or stat == "s_def":
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
	if skill.get("effect", "") == "buff":
		return "buff"
	if not is_damage_skill(skill):
		return "shield"
	return "physical" if is_physical(skill) else "magic"

# ─────────────────────────
# Meilenstein-Ei-Attacken: feste Freischaltungen pro Art, gezählt wird nur mit der Art als Start-Monster
# und nur, solange das Start-Monster selbst noch im Team ist (ausgetauscht oder K.O. = kein Fortschritt).
# Welcher Skill zu welchem Meilenstein gehört, steht in Monmap (milestone_egg_skills).
# Sie tauchen nie bei wilden Monstern oder im Biom-Pool auf, man bekommt sie nur über den Meilenstein.
# stat ist der Zähler in SaveManager (pro Art), hint der Freischalt-Hinweis im Konfigurator,
# source_hint die Beschreibung, wie die Attacke freigeschaltet wurde.
const MILESTONES = [
	{"key": "boss_1", "stat": "biome_boss_kills", "count": 1, "hint": "MILESTONE_HINT_BOSS_1", "source_hint": "MILESTONE_SOURCE_BOSS_1"},
	{"key": "boss_5", "stat": "biome_boss_kills", "count": 5, "hint": "MILESTONE_HINT_BOSS_5", "source_hint": "MILESTONE_SOURCE_BOSS_5"},
	{"key": "game_win", "stat": "game_wins", "count": 1, "hint": "MILESTONE_HINT_GAME_WIN", "source_hint": "MILESTONE_SOURCE_GAME_WIN"},
]

# Noch gesperrte Meilensteine der Art als [{skill, hint, ...}].
func get_locked_milestones(mon_name: String) -> Array:
	var skills_by_key = Monmap.mon_metainfos_by_name(mon_name).get("milestone_egg_skills", {})
	var locked = []
	for milestone in MILESTONES:
		var skill_name = skills_by_key.get(milestone.key, "")
		if skill_name != "" and not SaveManager.is_egg_skill_unlocked(mon_name, skill_name):
			var entry = milestone.duplicate()
			entry.skill = skill_name
			locked.append(entry)
	return locked

# Zählt einen Meilenstein-Zähler der Art hoch und liefert die Namen der dadurch neu freigeschalteten Skills.
func add_milestone_progress(mon_name: String, stat: String) -> Array:
	if mon_name == "" or not State.is_starter_in_team():
		return []
	SaveManager.add_milestone_progress(mon_name, stat)
	var unlocked = []
	for milestone in get_locked_milestones(mon_name):
		if SaveManager.get_milestone_progress(mon_name, milestone.stat) >= milestone.count:
			SaveManager.unlock_egg_skill(mon_name, milestone.skill)
			unlocked.append(milestone.skill)
	return unlocked

# ─────────────────────────
# Bounty Hunter: besondere Kopfgeld-Monster tauchen selten in normalen Kämpfen auf.
# Nur wenn ein Monster einer Art den letzten Treffer selbst landet, bekommt diese Art die Ei-Attacke aus
# Monmap (bounty_egg_skills). K.O. durch ein anderes Team-Mitglied oder Fangen zählt nicht.
# mon: Art des Kopfgeld-Monsters, level_bonus: Stufen über dem Kampf, min_depth: ab welcher Biom-Tiefe es auftaucht,
# label: Anzeigename (Platzhalter {mon} = Name der Art), hint: Freischalt-Hinweis im Konfigurator,
# source_hint: Beschreibung, wie die Attacke freigeschaltet wurde.
# Beispiele, bis es eigene Monster für die Kopfgelder gibt. Bekommt ein Kopfgeld eine eigene Art, trägt diese in
# Monmap "bounty_target": "<key>" und kommt in den normalen Spawn-Pool: dann zählt jedes Auftauchen als Kopfgeld-Monster.
const BOUNTIES = [
	{"key": "alpha_1", "mon": "1", "level_bonus": 2, "min_depth": 0, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT_ALPHA_1", "source_hint": "BOUNTY_SOURCE_ALPHA_1"},
	{"key": "alpha_2", "mon": "2", "level_bonus": 2, "min_depth": 1, "label": "BOUNTY_ALPHA", "hint": "BOUNTY_HINT_ALPHA_2", "source_hint": "BOUNTY_SOURCE_ALPHA_2"},
	{"key": "northern_warden", "mon": "1", "level_bonus": 4, "min_depth": 3, "label": "BOUNTY_NORTHERN_WARDEN", "hint": "BOUNTY_HINT_NORTHERN_WARDEN", "source_hint": "BOUNTY_SOURCE_NORTHERN_WARDEN"},
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
			locked.append(entry)
	return locked

# Kopfgelder, die für mindestens ein Team-Monster noch etwas freischalten und in dieser Biom-Tiefe auftauchen.
func get_open_bounties(team: Array, depth: int) -> Array:
	var keys = []
	for mon in team:
		for bounty in get_locked_bounties(mon._name):
			if bounty.min_depth <= depth and not keys.has(bounty.key):
				keys.append(bounty.key)
	return keys.map(func(key): return get_bounty(key))

# Das Kopfgeld-Monster wurde besiegt: freigeschaltet wird nur für die Art, die den letzten Treffer gelandet hat.
# Liefert den Namen der neu freigeschalteten Ei-Attacke oder "".
func claim_bounty(defeated: Monster) -> String:
	var killer = defeated._last_hit_by
	if defeated._bounty == "" or killer == null or not State.mons.has(killer):
		return ""
	var skill_name = Monmap.mon_metainfos_by_name(killer._name).get("bounty_egg_skills", {}).get(defeated._bounty, "")
	if skill_name == "" or SaveManager.is_egg_skill_unlocked(killer._name, skill_name):
		return ""
	SaveManager.unlock_egg_skill(killer._name, skill_name)
	return skill_name

# ═════════════════════════
# SKILL-DATEN
# Feste Werte: value = fester Schaden bzw. Schild, scaling = Anteil des eigenen Werts obendrauf
# (Angriff: Ang. bzw. Sp. Ang., Schild: Vert. bzw. Sp. Vert.). Die Verteidigung des Ziels zählt beim Schaden nicht.
# Beispiel Leichter Windstoß: 5 Schaden + 0,2 x Sp. Ang.

const EARTH := Enums.MON_TYPES.EARTH
const FIRE := Enums.MON_TYPES.FIRE
const WATER := Enums.MON_TYPES.WATER
const AIR := Enums.MON_TYPES.AIR
const PHYS := Enums.SKILL_DAMAGE_TYPE.PHYSICAL
const MAG := Enums.SKILL_DAMAGE_TYPE.ABILITY

# ─────────────────────────
# Start-Skills (Ei-Attacken der Arten, siehe Monmap default_egg_skills), pro Grundelement:
#   Leichter Stoß 5 + 0,2 (keine Abklingzeit), Leichter Schlag 8 + 0,3 (Abklingzeit 1), Nutzloser Stoß 2 + 0,2,
#   je physisch (Ang.) und magisch (Sp. Ang.), dazu Leichter Schild 5 + 0,3 und Nutzloser Schild 2 + 0,2,
#   je als Rüstung (Vert.) und Magie-Schild (Sp. Vert.). Alle Stufe 1, 1 Aktion.
# Welche Art welche drei bekommt, hängt von ihrem höchsten Kampfwert ab (Monmap).
var starter_skills = [
	# Earth
	_flat_attack_skill("SKILL_EARTH_PHYS_LIGHT_THRUST", EARTH, 5.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_EARTH_PHYS_LIGHT_STRIKE", EARTH, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_EARTH_PHYS_WEAK_THRUST", EARTH, 2.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_EARTH_MAG_LIGHT_THRUST", EARTH, 5.0, 0.2, MAG, 0),
	_flat_attack_skill("SKILL_EARTH_MAG_LIGHT_STRIKE", EARTH, 8.0, 0.3, MAG, 1),
	_flat_attack_skill("SKILL_EARTH_MAG_WEAK_THRUST", EARTH, 2.0, 0.2, MAG, 0),
	_flat_shield_skill("SKILL_EARTH_ARMOR_LIGHT", EARTH, 5.0, 0.3, PHYS, 0),
	_flat_shield_skill("SKILL_EARTH_ARMOR_WEAK", EARTH, 2.0, 0.2, PHYS, 0),
	_flat_shield_skill("SKILL_EARTH_WARD_LIGHT", EARTH, 5.0, 0.3, MAG, 0),
	_flat_shield_skill("SKILL_EARTH_WARD_WEAK", EARTH, 2.0, 0.2, MAG, 0),
	# Fire
	_flat_attack_skill("SKILL_FIRE_PHYS_LIGHT_THRUST", FIRE, 5.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_FIRE_PHYS_LIGHT_STRIKE", FIRE, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_FIRE_PHYS_WEAK_THRUST", FIRE, 2.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_FIRE_MAG_LIGHT_THRUST", FIRE, 5.0, 0.2, MAG, 0),
	_flat_attack_skill("SKILL_FIRE_MAG_LIGHT_STRIKE", FIRE, 8.0, 0.3, MAG, 1),
	_flat_attack_skill("SKILL_FIRE_MAG_WEAK_THRUST", FIRE, 2.0, 0.2, MAG, 0),
	_flat_shield_skill("SKILL_FIRE_ARMOR_LIGHT", FIRE, 5.0, 0.3, PHYS, 0),
	_flat_shield_skill("SKILL_FIRE_ARMOR_WEAK", FIRE, 2.0, 0.2, PHYS, 0),
	_flat_shield_skill("SKILL_FIRE_WARD_LIGHT", FIRE, 5.0, 0.3, MAG, 0),
	_flat_shield_skill("SKILL_FIRE_WARD_WEAK", FIRE, 2.0, 0.2, MAG, 0),
	# Water
	_flat_attack_skill("SKILL_WATER_PHYS_LIGHT_THRUST", WATER, 5.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_WATER_PHYS_LIGHT_STRIKE", WATER, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_WATER_PHYS_WEAK_THRUST", WATER, 2.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_WATER_MAG_LIGHT_THRUST", WATER, 5.0, 0.2, MAG, 0),
	_flat_attack_skill("SKILL_WATER_MAG_LIGHT_STRIKE", WATER, 8.0, 0.3, MAG, 1),
	_flat_attack_skill("SKILL_WATER_MAG_WEAK_THRUST", WATER, 2.0, 0.2, MAG, 0),
	_flat_shield_skill("SKILL_WATER_ARMOR_LIGHT", WATER, 5.0, 0.3, PHYS, 0),
	_flat_shield_skill("SKILL_WATER_ARMOR_WEAK", WATER, 2.0, 0.2, PHYS, 0),
	_flat_shield_skill("SKILL_WATER_WARD_LIGHT", WATER, 5.0, 0.3, MAG, 0),
	_flat_shield_skill("SKILL_WATER_WARD_WEAK", WATER, 2.0, 0.2, MAG, 0),
	# Air
	_flat_attack_skill("SKILL_AIR_PHYS_LIGHT_THRUST", AIR, 5.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_AIR_PHYS_LIGHT_STRIKE", AIR, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_AIR_PHYS_WEAK_THRUST", AIR, 2.0, 0.2, PHYS, 0),
	_flat_attack_skill("SKILL_AIR_MAG_LIGHT_THRUST", AIR, 5.0, 0.2, MAG, 0),
	_flat_attack_skill("SKILL_AIR_MAG_LIGHT_STRIKE", AIR, 8.0, 0.3, MAG, 1),
	_flat_attack_skill("SKILL_AIR_MAG_WEAK_THRUST", AIR, 2.0, 0.2, MAG, 0),
	_flat_shield_skill("SKILL_AIR_ARMOR_LIGHT", AIR, 5.0, 0.3, PHYS, 0),
	_flat_shield_skill("SKILL_AIR_ARMOR_WEAK", AIR, 2.0, 0.2, PHYS, 0),
	_flat_shield_skill("SKILL_AIR_WARD_LIGHT", AIR, 5.0, 0.3, MAG, 0),
	_flat_shield_skill("SKILL_AIR_WARD_WEAK", AIR, 2.0, 0.2, MAG, 0),
	# Zusätzliche Ei-Attacken der Startmonster (State.INITIAL_MONS), physisch bzw. magisch nach dem höheren Angriffswert:
	#   Angreifer: Kleiner Punch / Kleine [Element]kanone 5 + 0,3 (keine Abklingzeit),
	#              Punch / [Element]kanone 12 + 0,4 (Abklingzeit 1)
	#   Tanks:     Leichte Rückhand / Leichte [Element]kanone 8 + 0,3 (Abklingzeit 1),
	#              Leichter Schild (Rüstung, Vert.) / Leichter [Element]schild (Magie-Schild, Sp. Vert.) 5 + 0,3
	# Earth
	_flat_attack_skill("SKILL_EARTH_PHYS_SMALL_PUNCH", EARTH, 5.0, 0.3, PHYS, 0),
	_flat_attack_skill("SKILL_EARTH_MAG_SMALL_CANNON", EARTH, 5.0, 0.3, MAG, 0),
	_flat_attack_skill("SKILL_EARTH_PHYS_PUNCH", EARTH, 12.0, 0.4, PHYS, 1),
	_flat_attack_skill("SKILL_EARTH_MAG_CANNON", EARTH, 12.0, 0.4, MAG, 1),
	_flat_attack_skill("SKILL_EARTH_PHYS_BACKHAND", EARTH, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_EARTH_MAG_LIGHT_CANNON", EARTH, 8.0, 0.3, MAG, 1),
	_flat_shield_skill("SKILL_EARTH_ARMOR_PLAIN", EARTH, 5.0, 0.3, PHYS, 0),
	_flat_shield_skill("SKILL_EARTH_WARD_PLAIN", EARTH, 5.0, 0.3, MAG, 0),
	# Fire
	_flat_attack_skill("SKILL_FIRE_PHYS_SMALL_PUNCH", FIRE, 5.0, 0.3, PHYS, 0),
	_flat_attack_skill("SKILL_FIRE_MAG_SMALL_CANNON", FIRE, 5.0, 0.3, MAG, 0),
	_flat_attack_skill("SKILL_FIRE_PHYS_PUNCH", FIRE, 12.0, 0.4, PHYS, 1),
	_flat_attack_skill("SKILL_FIRE_MAG_CANNON", FIRE, 12.0, 0.4, MAG, 1),
	_flat_attack_skill("SKILL_FIRE_PHYS_BACKHAND", FIRE, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_FIRE_MAG_LIGHT_CANNON", FIRE, 8.0, 0.3, MAG, 1),
	_flat_shield_skill("SKILL_FIRE_ARMOR_PLAIN", FIRE, 5.0, 0.3, PHYS, 0),
	_flat_shield_skill("SKILL_FIRE_WARD_PLAIN", FIRE, 5.0, 0.3, MAG, 0),
	# Water
	_flat_attack_skill("SKILL_WATER_PHYS_SMALL_PUNCH", WATER, 5.0, 0.3, PHYS, 0),
	_flat_attack_skill("SKILL_WATER_MAG_SMALL_CANNON", WATER, 5.0, 0.3, MAG, 0),
	_flat_attack_skill("SKILL_WATER_PHYS_PUNCH", WATER, 12.0, 0.4, PHYS, 1),
	_flat_attack_skill("SKILL_WATER_MAG_CANNON", WATER, 12.0, 0.4, MAG, 1),
	_flat_attack_skill("SKILL_WATER_PHYS_BACKHAND", WATER, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_WATER_MAG_LIGHT_CANNON", WATER, 8.0, 0.3, MAG, 1),
	_flat_shield_skill("SKILL_WATER_ARMOR_PLAIN", WATER, 5.0, 0.3, PHYS, 0),
	_flat_shield_skill("SKILL_WATER_WARD_PLAIN", WATER, 5.0, 0.3, MAG, 0),
	# Air
	_flat_attack_skill("SKILL_AIR_PHYS_SMALL_PUNCH", AIR, 5.0, 0.3, PHYS, 0),
	_flat_attack_skill("SKILL_AIR_MAG_SMALL_CANNON", AIR, 5.0, 0.3, MAG, 0),
	_flat_attack_skill("SKILL_AIR_PHYS_PUNCH", AIR, 12.0, 0.4, PHYS, 1),
	_flat_attack_skill("SKILL_AIR_MAG_CANNON", AIR, 12.0, 0.4, MAG, 1),
	_flat_attack_skill("SKILL_AIR_PHYS_BACKHAND", AIR, 8.0, 0.3, PHYS, 1),
	_flat_attack_skill("SKILL_AIR_MAG_LIGHT_CANNON", AIR, 8.0, 0.3, MAG, 1),
	_flat_shield_skill("SKILL_AIR_ARMOR_PLAIN", AIR, 5.0, 0.3, PHYS, 0),
	_flat_shield_skill("SKILL_AIR_WARD_PLAIN", AIR, 5.0, 0.3, MAG, 0),
]

# Die übrigen Listen sind vorerst leer, die Skills werden Stück für Stück neu verteilt.
# Standard-Skills: ein Trank mit neuem Grundelement bietet sie zum Lernen an (ElementGainOverlay)
var standard_skills = []
# Gemeinsamer Pool: wilde Monster (Biom-Pool) und Trainer
var egg_skills = []
var defensive_skills = []
var buff_skills = []
var passive_skills = []
var area_skills = []
# Kopfgeld-Ei-Attacken (Skills.BOUNTIES)
var bounty_skills = []
# Einzigartige Skills aus dem Couvert der Bosse
var reward_skills = []

# So viele Skills bietet ein Couvert zur Auswahl.
const REWARD_SKILL_OFFERS := 3

# Auswahl fürs Couvert: noch von niemandem gelernte einzigartige Skills, mindestens einer davon für das Team sofort einsetzbar,
# sofern es so einen noch gibt.
func reward_offers() -> Array:
	var pool: Array = reward_skills.filter(func(skill): return not State.taught_reward_skills.has(skill.name))
	pool.shuffle()
	var offers := pool.slice(0, REWARD_SKILL_OFFERS)
	var usable := func(skill): return State.mons.any(func(mon): return can_use(mon, skill))
	if not offers.is_empty() and not offers.any(usable):
		var fitting := pool.filter(usable)
		if not fitting.is_empty():
			offers[0] = fitting[0]
	return offers.map(func(skill): return get_skill(skill.name))

# Aufstiegs-Skills: Trinkt ein Monster einen Element-Trank und steigt dadurch zu einem Kombi-Element auf,
# kann es den Skill genau dieses Elements lernen (Treasure.add_potion_card, ElementGainOverlay). Vorerst leer.
var ascension_skills = []

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

## Schild auf ein eigenes Monster: value fester Schild + scaling x (Sp.) Verteidigung, Stufe 1, 1 Aktion
func _flat_shield_skill(skill_name: String, nature: int, value: float, scaling: float, damage_type: int, cooldown: int) -> Dictionary:
	return {
		"cost": 1,
		"name": skill_name,
		"nature": nature,
		"value": value,
		"scaling": scaling,
		"cooldown": cooldown,
		"damage_type": damage_type,
		"effect": "shield",
		"description": "SKILL_SHIELD_PHYSICAL_DESC" if damage_type == Enums.SKILL_DAMAGE_TYPE.PHYSICAL else "SKILL_SHIELD_ABILITY_DESC",
		"target": Enums.CARD_TARGETS.SINGLE_FRIEND,
		"scouted": false,
		"tier": 1,
		"shop_cost": {"min": 5, "max": 15},
		"handle": func(props): add_shield(props)
	}

## Extra einer Karte (siehe "Extras" weiter oben). stat "" und turns 0, wo sie nicht gebraucht werden.
func _extra(kind: String, value: float, stat: String, turns: int, chance: float) -> Dictionary:
	return {"kind": kind, "value": value, "stat": stat, "turns": turns, "chance": chance}

func _with(skill: Dictionary, extra: Dictionary) -> Dictionary:
	skill.merge(extra, true)
	return skill
