extends Node

func deal_damage(props):
	# für Kopfgelder: wer zuletzt getroffen hat, hat das Monster besiegt
	props.mon._last_hit_by = props.from
	var full_damage = calc_damage(props.from, props.mon, props.skill)
	reveal_stats_by_hit(props.from, props.mon, props.skill)
	# Schilde fangen den Schaden zuerst ab
	var damage = props.mon.absorb_damage(full_damage, is_physical(props.skill))
	var multiplier = element_multiplier(props.skill.nature, props.mon._type)
	print("lose:" + str(props.skill.value) + ":" + str(damage) + " (Element x" + str(multiplier) + ")")
	Events.monster_hit_with_element.emit(props.mon, damage, multiplier, full_damage - damage)
	if State.mons.has(props.mon) and props.mon.is_alive() and roundi(props.mon.hp() - props.mon._lost_hp - damage) <= 0:
		State.record_own_faint(props.mon, props.from, props.skill, damage, multiplier)
	props.mon._lost_hp += damage

# ─────────────────────────
# Schadensformel
# Physisch: Angriff gegen Verteidigung, Magisch: Sp. Angriff gegen Sp. Verteidigung.
# Bei gleichen Werten bleibt der Schaden wie vorher (Faktor 1), mehr Angriff -> bis zu x2, mehr Verteidigung -> gegen 0.

# Aus dem Schaden lässt sich der beteiligte Wert des Gegners zurückrechnen:
# trifft man ihn, wird seine (Sp.) Verteidigung aufgedeckt, trifft er einen selbst, sein (Sp.) Angriff.
func reveal_stats_by_hit(from: Monster, to: Monster, skill: Dictionary) -> void:
	var physical = is_physical(skill)
	if State.mons.has(from) and not State.mons.has(to):
		State.reveal_mon_stat(to._name, "def" if physical else "s_def")
	elif State.mons.has(to) and not State.mons.has(from):
		State.reveal_mon_stat(from._name, "atk" if physical else "s_atk")

func is_physical(skill: Dictionary) -> bool:
	return skill.get("damage_type", Enums.SKILL_DAMAGE_TYPE.PHYSICAL) == Enums.SKILL_DAMAGE_TYPE.PHYSICAL

func calc_damage(from: Monster, to: Monster, skill: Dictionary) -> float:
	var physical = is_physical(skill)
	var atk = from.attack() if physical else from.s_attack()
	var def = to.defense() if physical else to.s_defense()
	var stat_factor = 2.0 * atk / max(atk + def, 0.001)
	# aufrunden, damit angezeigter und abgezogener Schaden gleich sind (jeder Treffer macht mind. 1)
	return ceilf(atk * (skill.value / 100) * stat_factor * element_multiplier(skill.nature, to._type))

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
	return skill.has("value") and skill.get("effect", "damage") == "damage" \
		and not defensive_skills.any(func(block): return block.name == skill.name)

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
func element_multiplier(skill_nature: int, target_type: int) -> float:
	var score = element_score(skill_nature, target_type)
	if score >= 0:
		return 1.0 + ELEMENT_BONUS * score
	return pow(1.0 - ELEMENT_BONUS, -score)

# ─────────────────────────
# Schilde halten bis zum nächsten eigenen Zug des geschützten Monsters oder bis sie aufgebraucht sind (siehe Monster.start_turn, Monster.absorb_damage).
# Physische Schilde fangen nur physischen Schaden ab, magische nur magischen.

# Physischer Block (auch die Basis-Blocks): value % der Verteidigung des Wirkers, magischer Block: value % seiner Sp. Verteidigung.
func add_shield(props):
	var physical = is_physical(props.skill)
	var def = props.from.defense() if physical else props.from.s_defense()
	props.mon.add_shield(ceilf(def * props.skill.value / 100), physical)

# Buff: value % mehr auf buff_stat für buff_turns eigene Züge des Ziels.
func add_buff(props):
	props.mon.add_buff(props.skill.buff_stat, props.skill.value / 100, props.skill.buff_turns)

# ─────────────────────────
# Absichten: Gegner planen ihren nächsten Zug im Voraus (Monster._intent, battle.gd _plan_intent),
# der Spieler sieht vorher, wen sie mit wie viel Schaden treffen werden.

# Trifft eine geplante Aktion dieses Monster? Flächen-Skills treffen alle auf der Seite des Ziels.
func action_hits(action: Dictionary, mon: Monster) -> bool:
	if action.target == mon:
		return true
	return targets_team(action.skill) and action.target != null and State.mons.has(action.target) == State.mons.has(mon)

# Schaden, den die geplanten Angriffe der attackers bei target anrichten werden:
# {"full": ohne Schild, "after": nach Abzug der aktuellen Schilde}. Physisch und magisch zählen getrennt gegen ihren Schild.
func incoming_damage(target: Monster, attackers: Array) -> Dictionary:
	var physical = 0.0
	var ability = 0.0
	for attacker: Monster in attackers:
		if not attacker.is_alive():
			continue
		for action in attacker._intent:
			if not is_damage_skill(action.skill) or not action_hits(action, target):
				continue
			if is_physical(action.skill):
				physical += calc_damage(attacker, target, action.skill)
			else:
				ability += calc_damage(attacker, target, action.skill)
	return {
		"full": physical + ability,
		"after": maxf(physical - target._shield, 0.0) + maxf(ability - target._s_shield, 0.0),
	}

# Bonus aller passiven Skills im Team auf einen Wert (z. B. +15 KP für jedes Monster im Team).
# Es gilt die Element-Regel: nur Monster, die den Skill einsetzen könnten, geben den Bonus.
func passive_bonus(mon: Monster, stat: String) -> float:
	var team = State.mons if State.mons.has(mon) else State.enemy_mons if State.enemy_mons.has(mon) else [mon]
	var bonus = 0.0
	for member in team:
		for skill in member._skills:
			if is_passive(skill) and skill.passive_stat == stat and can_use(member, skill):
				bonus += skill.value
	return bonus

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
	for list in [attack_skills, defensive_skills, buff_skills, passive_skills, area_skills, egg_skills, milestone_skills, bounty_skills, reward_skills]:
		for skill in list:
			if skill.name == skill_name:
				var copy = skill.duplicate()
				copy.id = Helper.generate_fake_uuid()
				return copy
	return {}

# Effekt-Skills, die wie Ei-Attacken im Biom-Pool auftauchen (die Basis-Blocks gehören fest zu den Arten).
func effect_skills() -> Array:
	return defensive_skills.filter(func(skill): return skill.has("effect")) + buff_skills + passive_skills + area_skills

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

# Ei-Attacken und Effekt-Skills (Schild, Buff, Passiv, Flächenschaden), deren Element zum Biom passt (biome_mask 0 = alle).
func get_biome_skills(biome_mask: int) -> Array:
	return (egg_skills + effect_skills()).filter(func(skill): return biome_mask == 0 or skill.nature & biome_mask != 0).map(
		func(skill): return skill.name)

# ─────────────────────────
# Lernen von Skills gefangener Monster

func knows_skill(mon: Monster, skill_name: String) -> bool:
	return mon._skills.any(func(skill): return skill.name == skill_name)

# ─────────────────────────
# Element-Regel: Ein Monster kann einen Skill nur einsetzen, wenn sein Typ alle Elemente des Skills enthält
# (Vulkan = Erde+Feuer+Wasser kann z. B. Erde, Feuer, Wasser, Magma, Schlamm, Dampf und Vulkan spielen).

func covers(type_mask: int, nature: int) -> bool:
	return nature & ~type_mask == 0

func can_use(mon: Monster, skill: Dictionary) -> bool:
	return covers(mon._type, skill.nature)

func can_use_name(mon: Monster, skill_name: String) -> bool:
	return covers(mon._type, get_skill(skill_name).nature)

# Einzelne Elemente, die dem Monster für diesen Skill noch fehlen.
func missing_elements(mon: Monster, skill: Dictionary) -> Array:
	return Enums.MON_TYPES.values().filter(func(element): return skill.nature & element and not mon._type & element)

# "Benötigt: Erde, Luft" für die Elemente, die dem Monster für diesen Skill noch fehlen ("" wenn spielbar).
func missing_elements_text(mon: Monster, skill: Dictionary) -> String:
	var missing = missing_elements(mon, skill)
	if missing.is_empty():
		return ""
	var labels = missing.map(func(element): return tr(ColorMap.get_combo(element).label))
	return tr("SKILL_NEEDS_ELEMENTS").format({"elements": ", ".join(PackedStringArray(labels))})

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
	{"key": "shield", "label": "EGG_CATEGORY_SHIELD", "icon": "res://assets/ui/icons/battle/shield.svg"},
	{"key": "buff", "label": "EGG_CATEGORY_BUFF", "icon": "res://assets/ui/icons/battle/buff.svg"},
	{"key": "passive", "label": "EGG_CATEGORY_PASSIVE", "icon": "res://assets/ui/icons/parchment.svg"},
]

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

# Basis-Angriff und -Block gibt es pro Element. Über die Werte bekommt jedes Element seinen Charakter:
# Feuer greift hart an und blockt kaum, Erde blockt viel und trifft schwächer, Wasser und Luft liegen dazwischen.
var attack_skills = [
	_basic_skill("SKILL_BASIC_ATTACK_EARTH", Enums.MON_TYPES.EARTH, 16.0, "SKILL_BASIC_ATTACK_DESC", func(props): deal_damage(props)),
	_basic_skill("SKILL_BASIC_ATTACK_FIRE", Enums.MON_TYPES.FIRE, 24.0, "SKILL_BASIC_ATTACK_DESC", func(props): deal_damage(props)),
	_basic_skill("SKILL_BASIC_ATTACK_WATER", Enums.MON_TYPES.WATER, 20.0, "SKILL_BASIC_ATTACK_DESC", func(props): deal_damage(props)),
	_basic_skill("SKILL_BASIC_ATTACK_AIR", Enums.MON_TYPES.AIR, 22.0, "SKILL_BASIC_ATTACK_DESC", func(props): deal_damage(props)),
]

# Basis-Blocks: value % der Verteidigung als Schild gegen physischen Schaden, ohne Abklingzeit.
# Die beiden Schild-Skills: value % der (Sp.) Verteidigung als Schild, mit Abklingzeit.
var defensive_skills = [
	_basic_skill("SKILL_BASIC_BLOCK_EARTH", Enums.MON_TYPES.EARTH, 40.0, "SKILL_BASIC_BLOCK_DESC", func(props): add_shield(props), Enums.CARD_TARGETS.SINGLE_FRIEND),
	_basic_skill("SKILL_BASIC_BLOCK_FIRE", Enums.MON_TYPES.FIRE, 10.0, "SKILL_BASIC_BLOCK_DESC", func(props): add_shield(props), Enums.CARD_TARGETS.SINGLE_FRIEND),
	_basic_skill("SKILL_BASIC_BLOCK_WATER", Enums.MON_TYPES.WATER, 30.0, "SKILL_BASIC_BLOCK_DESC", func(props): add_shield(props), Enums.CARD_TARGETS.SINGLE_FRIEND),
	_basic_skill("SKILL_BASIC_BLOCK_AIR", Enums.MON_TYPES.AIR, 20.0, "SKILL_BASIC_BLOCK_DESC", func(props): add_shield(props), Enums.CARD_TARGETS.SINGLE_FRIEND),
	_effect_skill("SKILL_STONE_GUARD", Enums.MON_TYPES.EARTH, 50.0, 1, Enums.SKILL_DAMAGE_TYPE.PHYSICAL, "shield",
		"SKILL_SHIELD_PHYSICAL_DESC", Enums.CARD_TARGETS.SINGLE_FRIEND, 2, func(props): add_shield(props)),
	_effect_skill("SKILL_MIST_VEIL", Enums.MON_TYPES.WATER, 50.0, 1, Enums.SKILL_DAMAGE_TYPE.ABILITY, "shield",
		"SKILL_SHIELD_ABILITY_DESC", Enums.CARD_TARGETS.SINGLE_FRIEND, 2, func(props): add_shield(props)),
]

func _basic_skill(skill_name: String, nature: int, value: float, description: String, handle: Callable,
		target: int = Enums.CARD_TARGETS.SINGLE_ENEMY) -> Dictionary:
	return {
		"cost": 1,
		"name": skill_name,
		"nature": nature,
		"value": value,
		"cooldown": 0,
		"damage_type": Enums.SKILL_DAMAGE_TYPE.PHYSICAL,
		"description": description,
		"target": target,
		"scouted": false,
		"tier": 1,
		"shop_cost": {"min": 5, "max": 15},
		"handle": handle
	}

# Buffs auf ein eigenes Monster, im Kampf als "Buff" am Monster angezeigt.
var buff_skills = [
	_with(_effect_skill("SKILL_TEMPERED_HIDE", Enums.MON_TYPES.FIRE, 30.0, 1, Enums.SKILL_DAMAGE_TYPE.PHYSICAL, "buff",
		"SKILL_BUFF_DEF_DESC", Enums.CARD_TARGETS.SINGLE_FRIEND, 2, func(props): add_buff(props)),
		{"buff_stat": "def", "buff_turns": 3}),
]

# Passive Skills: nicht ausspielbar, wirken einfach, solange das Monster sie kennt (können beim Lernen ersetzt werden).
var passive_skills = [
	_with(_effect_skill("SKILL_LIFE_SPRING", Enums.MON_TYPES.WATER, 15.0, 2, Enums.SKILL_DAMAGE_TYPE.ABILITY, "passive",
		"SKILL_PASSIVE_HP_DESC", Enums.CARD_TARGETS.TEAM_FRIEND, 0, func(_props): pass),
		{"cost": 0, "passive_stat": "hp"}),
]

# Flächenschaden: trifft alle Gegner, dafür schwächer als Skills auf ein Ziel.
var area_skills = [
	_effect_skill("SKILL_SQUALL", Enums.MON_TYPES.AIR, 15.0, 1, Enums.SKILL_DAMAGE_TYPE.ABILITY, "damage",
		"SKILL_AREA_ABILITY_DESC", Enums.CARD_TARGETS.TEAM_ENEMY, 1, func(props): deal_damage(props)),
	_with(_effect_skill("SKILL_FIRESTORM", Enums.MON_TYPES.FIRE, 40.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY, "damage",
		"SKILL_AREA_ABILITY_DESC", Enums.CARD_TARGETS.TEAM_ENEMY, 3, func(props): deal_damage(props)),
		{"cost": 2}),
]

func _effect_skill(skill_name: String, nature: int, value: float, tier: int, damage_type: int, effect: String,
		description: String, target: int, cooldown: int, handle: Callable) -> Dictionary:
	return {
		"cost": 1,
		"name": skill_name,
		"nature": nature,
		"value": value,
		"cooldown": cooldown,
		"damage_type": damage_type,
		"effect": effect,
		"description": description,
		"target": target,
		"scouted": false,
		"tier": tier,
		"shop_cost": {"min": 5 * tier, "max": 15 * tier},
		"handle": handle
	}

func _with(skill: Dictionary, extra: Dictionary) -> Dictionary:
	skill.merge(extra, true)
	return skill

# Einzigartige Skills aus dem Couvert der Bosse: stehen in keiner anderen Liste, also weder im Biom-Pool noch beim
# Trainer oder als Ei-Attacke. Vorerst pro Basis-Element je einer als Treffer, Flächenschaden, Schutz und Passiv.
var reward_skills = [
	_egg_skill("SKILL_QUAKE_HAMMER", Enums.MON_TYPES.EARTH, 70.0, 3, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_reward_area_skill("SKILL_LANDSLIDE", Enums.MON_TYPES.EARTH),
	_reward_shield_skill("SKILL_BEDROCK_WARD", Enums.MON_TYPES.EARTH, Enums.SKILL_DAMAGE_TYPE.PHYSICAL, "SKILL_SHIELD_PHYSICAL_DESC"),
	_reward_passive_skill("SKILL_DEEP_ROOTS", Enums.MON_TYPES.EARTH),
	_egg_skill("SKILL_SUNFORGE_BLOW", Enums.MON_TYPES.FIRE, 70.0, 3, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_reward_area_skill("SKILL_ASH_RAIN", Enums.MON_TYPES.FIRE),
	_reward_buff_skill("SKILL_KILN_HIDE", Enums.MON_TYPES.FIRE),
	_reward_passive_skill("SKILL_HEARTH_SOUL", Enums.MON_TYPES.FIRE),
	_egg_skill("SKILL_ABYSS_LANCE", Enums.MON_TYPES.WATER, 70.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_reward_area_skill("SKILL_RIPTIDE_WAVE", Enums.MON_TYPES.WATER),
	_reward_shield_skill("SKILL_PEARL_WARD", Enums.MON_TYPES.WATER, Enums.SKILL_DAMAGE_TYPE.ABILITY, "SKILL_SHIELD_ABILITY_DESC"),
	_reward_passive_skill("SKILL_WELLSPRING", Enums.MON_TYPES.WATER),
	_egg_skill("SKILL_SKY_RENDER", Enums.MON_TYPES.AIR, 70.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_reward_area_skill("SKILL_GALE_SWEEP", Enums.MON_TYPES.AIR),
	_reward_buff_skill("SKILL_ZEPHYR_MANTLE", Enums.MON_TYPES.AIR),
	_reward_passive_skill("SKILL_STORM_HEART", Enums.MON_TYPES.AIR),
]

func _reward_area_skill(skill_name: String, nature: int) -> Dictionary:
	return _with(_effect_skill(skill_name, nature, 45.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY, "damage",
		"SKILL_AREA_ABILITY_DESC", Enums.CARD_TARGETS.TEAM_ENEMY, 3, func(props): deal_damage(props)),
		{"cost": 2})

func _reward_shield_skill(skill_name: String, nature: int, damage_type: int, description: String) -> Dictionary:
	return _effect_skill(skill_name, nature, 90.0, 3, damage_type, "shield",
		description, Enums.CARD_TARGETS.SINGLE_FRIEND, 2, func(props): add_shield(props))

func _reward_buff_skill(skill_name: String, nature: int) -> Dictionary:
	return _with(_effect_skill(skill_name, nature, 45.0, 3, Enums.SKILL_DAMAGE_TYPE.PHYSICAL, "buff",
		"SKILL_BUFF_DEF_DESC", Enums.CARD_TARGETS.SINGLE_FRIEND, 2, func(props): add_buff(props)),
		{"buff_stat": "def", "buff_turns": 3})

func _reward_passive_skill(skill_name: String, nature: int) -> Dictionary:
	return _with(_effect_skill(skill_name, nature, 25.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY, "passive",
		"SKILL_PASSIVE_HP_DESC", Enums.CARD_TARGETS.TEAM_FRIEND, 0, func(_props): pass),
		{"cost": 0, "passive_stat": "hp"})

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

# Test-Skills für Ei-Attacken (alle Schaden auf ein Ziel), Stufe 1-4 bestimmt die Seltenheit.
var egg_skills = [
	_egg_skill("SKILL_GUST", Enums.MON_TYPES.AIR, 25.0, 1, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_SPLASH", Enums.MON_TYPES.WATER, 25.0, 1, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_EMBER", Enums.MON_TYPES.FIRE, 25.0, 1, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_PEBBLE_THROW", Enums.MON_TYPES.EARTH, 25.0, 1, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_WIND_BLADE", Enums.MON_TYPES.AIR, 40.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_TIDAL_SLAM", Enums.MON_TYPES.WATER, 40.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_FLAME_CLAW", Enums.MON_TYPES.FIRE, 40.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_ROCK_CRUSH", Enums.MON_TYPES.EARTH, 40.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_THUNDER_STRIKE", Enums.MON_TYPES.AIR | Enums.MON_TYPES.FIRE, 60.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_ICE_SPEAR", Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER, 60.0, 3, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_MAGMA_BURST", Enums.MON_TYPES.EARTH | Enums.MON_TYPES.FIRE, 60.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_CHAOS_NOVA", Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER | Enums.MON_TYPES.FIRE | Enums.MON_TYPES.EARTH, 90.0, 4, Enums.SKILL_DAMAGE_TYPE.ABILITY),
]

# Meilenstein-Ei-Attacken pro Art, nur im Grund-Element der Art: das Start-Monster kann sie immer einsetzen.
# Stufe 3 liegt etwas unter den Mehr-Element-Skills (60), braucht dafür aber keine weiteren Elemente.
var milestone_skills = [
	# Monster 1 (Luft)
	_egg_skill("SKILL_TAILWIND_STRIKE", Enums.MON_TYPES.AIR, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_CYCLONE", Enums.MON_TYPES.AIR, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_NORTHERN_GALE", Enums.MON_TYPES.AIR, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 2 (Wasser)
	_egg_skill("SKILL_UNDERTOW", Enums.MON_TYPES.WATER, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_MAELSTROM", Enums.MON_TYPES.WATER, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_NORTHERN_TIDE", Enums.MON_TYPES.WATER, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	# Monster 3 (Luft)
	_egg_skill("SKILL_PLUME_FLURRY", Enums.MON_TYPES.AIR, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_PHANTOM_DRAFT", Enums.MON_TYPES.AIR, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_SHADOW_SQUALL", Enums.MON_TYPES.AIR, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 4 (Feuer)
	_egg_skill("SKILL_SCORCHING_CHOP", Enums.MON_TYPES.FIRE, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_BLAZING_CLEAVE", Enums.MON_TYPES.FIRE, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_INFERNO_EXECUTION", Enums.MON_TYPES.FIRE, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	# Monster 5 (Luft)
	_egg_skill("SKILL_DUST_WHIRR", Enums.MON_TYPES.AIR, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_STARING_GAZE", Enums.MON_TYPES.AIR, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_MUDWING_DIVE", Enums.MON_TYPES.AIR, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	# Monster 6 (Erde)
	_egg_skill("SKILL_ROOT_LASH", Enums.MON_TYPES.EARTH, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_TWIN_AXE_SWEEP", Enums.MON_TYPES.EARTH, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_ANCIENT_TIMBER", Enums.MON_TYPES.EARTH, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	# Monster 7 (Erde)
	_egg_skill("SKILL_POLLEN_DRIFT", Enums.MON_TYPES.EARTH, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_BLOSSOM_CHORUS", Enums.MON_TYPES.EARTH, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_FOURFOLD_BLOOM", Enums.MON_TYPES.EARTH, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 8 (Feuer)
	_egg_skill("SKILL_SPARK_SPIT", Enums.MON_TYPES.FIRE, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_LAVA_TAIL", Enums.MON_TYPES.FIRE, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_EMBER_SPIRAL", Enums.MON_TYPES.FIRE, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 9 (Wasser)
	_egg_skill("SKILL_BUBBLE_SPRAY", Enums.MON_TYPES.WATER, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TENTACLE_LASH", Enums.MON_TYPES.WATER, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_TIDE_HEART", Enums.MON_TYPES.WATER, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 10 (Feuer)
	_egg_skill("SKILL_MAGMA_FIST", Enums.MON_TYPES.FIRE, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_SMOLDER_STOMP", Enums.MON_TYPES.FIRE, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_CORE_BLAST", Enums.MON_TYPES.FIRE, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 11 (Luft)
	_egg_skill("SKILL_FEATHER_PUFF", Enums.MON_TYPES.AIR, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_CLOUD_BURST", Enums.MON_TYPES.AIR, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_SKY_TWISTER", Enums.MON_TYPES.AIR, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	# Monster 12 (Luft)
	_egg_skill("SKILL_STATIC_TALON", Enums.MON_TYPES.AIR, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_THUNDER_WINGS", Enums.MON_TYPES.AIR, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_SKYFALL_STORM", Enums.MON_TYPES.AIR, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 13 (Erde)
	_egg_skill("SKILL_SHARD_SWIPE", Enums.MON_TYPES.EARTH, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_CRYSTAL_SPIKES", Enums.MON_TYPES.EARTH, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_GEODE_CRASH", Enums.MON_TYPES.EARTH, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	# Monster 14 (Wasser)
	_egg_skill("SKILL_SNOW_FLURRY", Enums.MON_TYPES.WATER, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_FROST_TAILS", Enums.MON_TYPES.WATER, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_GLACIAL_GRACE", Enums.MON_TYPES.WATER, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 15 (Wasser)
	_egg_skill("SKILL_MIST_TOUCH", Enums.MON_TYPES.WATER, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_VAPOR_COIL", Enums.MON_TYPES.WATER, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_PHANTOM_FOG", Enums.MON_TYPES.WATER, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 16 (Feuer)
	_egg_skill("SKILL_STATIC_ROLL", Enums.MON_TYPES.FIRE, 28.0, 1, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_VOLT_QUILLS", Enums.MON_TYPES.FIRE, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_BALL_LIGHTNING", Enums.MON_TYPES.FIRE, 55.0, 3, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
]

# Bounty-Hunter-Ei-Attacken pro Art, wie die Meilenstein-Skills nur im Grund-Element der Art.
# Gibt es nur über Kopfgelder, nie bei wilden Monstern oder im Biom-Pool.
var bounty_skills = [
	# Monster 1 (Luft)
	_egg_skill("SKILL_RAPTOR_DIVE", Enums.MON_TYPES.AIR, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_GALE", Enums.MON_TYPES.AIR, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_TEMPEST", Enums.MON_TYPES.AIR, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 2 (Wasser)
	_egg_skill("SKILL_SHARK_BITE", Enums.MON_TYPES.WATER, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_TIDE", Enums.MON_TYPES.WATER, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_TSUNAMI", Enums.MON_TYPES.WATER, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	# Monster 3 (Luft)
	_egg_skill("SKILL_SILENT_SWOOP", Enums.MON_TYPES.AIR, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_HAUNT", Enums.MON_TYPES.AIR, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_PHANTASM", Enums.MON_TYPES.AIR, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 4 (Feuer)
	_egg_skill("SKILL_HOT_HATCHET", Enums.MON_TYPES.FIRE, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_BLAZE", Enums.MON_TYPES.FIRE, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_PYRE", Enums.MON_TYPES.FIRE, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	# Monster 5 (Luft)
	_egg_skill("SKILL_STINGER_DART", Enums.MON_TYPES.AIR, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_GAZE", Enums.MON_TYPES.AIR, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_SWARM", Enums.MON_TYPES.AIR, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	# Monster 6 (Erde)
	_egg_skill("SKILL_SAP_CLEAVER", Enums.MON_TYPES.EARTH, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_GROVE", Enums.MON_TYPES.EARTH, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_TIMBERFALL", Enums.MON_TYPES.EARTH, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	# Monster 7 (Erde)
	_egg_skill("SKILL_THORN_EMBRACE", Enums.MON_TYPES.EARTH, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_BLOOM", Enums.MON_TYPES.EARTH, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_WILDWOOD", Enums.MON_TYPES.EARTH, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 8 (Feuer)
	_egg_skill("SKILL_CINDER_BITE", Enums.MON_TYPES.FIRE, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_FLAME", Enums.MON_TYPES.FIRE, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_ERUPTION", Enums.MON_TYPES.FIRE, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 9 (Wasser)
	_egg_skill("SKILL_JELLY_STING", Enums.MON_TYPES.WATER, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_CURRENT", Enums.MON_TYPES.WATER, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_TORRENT", Enums.MON_TYPES.WATER, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 10 (Feuer)
	_egg_skill("SKILL_BOULDER_PUNCH", Enums.MON_TYPES.FIRE, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_EMBER", Enums.MON_TYPES.FIRE, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_CALDERA", Enums.MON_TYPES.FIRE, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	# Monster 11 (Luft)
	_egg_skill("SKILL_DOWNDRAFT", Enums.MON_TYPES.AIR, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_BREEZE", Enums.MON_TYPES.AIR, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_TYPHOON", Enums.MON_TYPES.AIR, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 12 (Luft)
	_egg_skill("SKILL_GRYPH_STRIKE", Enums.MON_TYPES.AIR, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_THUNDER", Enums.MON_TYPES.AIR, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_HURRICANE", Enums.MON_TYPES.AIR, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	# Monster 13 (Erde)
	_egg_skill("SKILL_QUARRY_CLAW", Enums.MON_TYPES.EARTH, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_BOULDER", Enums.MON_TYPES.EARTH, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_AVALANCHE", Enums.MON_TYPES.EARTH, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	# Monster 14 (Wasser)
	_egg_skill("SKILL_ICICLE_FANG", Enums.MON_TYPES.WATER, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_FROST", Enums.MON_TYPES.WATER, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_BLIZZARD", Enums.MON_TYPES.WATER, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 15 (Wasser)
	_egg_skill("SKILL_WISP_GRASP", Enums.MON_TYPES.WATER, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_MIST", Enums.MON_TYPES.WATER, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_DELUGE", Enums.MON_TYPES.WATER, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	# Monster 16 (Feuer)
	_egg_skill("SKILL_SHOCK_NIP", Enums.MON_TYPES.FIRE, 42.0, 2, Enums.SKILL_DAMAGE_TYPE.PHYSICAL),
	_egg_skill("SKILL_HUNTERS_SPARK", Enums.MON_TYPES.FIRE, 58.0, 3, Enums.SKILL_DAMAGE_TYPE.ABILITY),
	_egg_skill("SKILL_TROPHY_SURGE", Enums.MON_TYPES.FIRE, 75.0, 4, Enums.SKILL_DAMAGE_TYPE.ABILITY),
]

# Aktionen, die ein Schadens-Skill kostet: ab dem ersten Wert 2, ab dem zweiten 3 (sonst 1).
# Pro Aktion bleiben starke Skills damit etwa gleich stark wie schwache, brauchen aber mehr vom Zug.
const COST_THRESHOLDS := [50.0, 80.0]

func _skill_cost(value: float) -> int:
	return 1 + COST_THRESHOLDS.filter(func(threshold): return value >= threshold).size()

func _egg_skill(skill_name: String, nature: int, value: float, tier: int, damage_type: int) -> Dictionary:
	return {
		"cost": _skill_cost(value),
		"name": skill_name,
		"nature": nature,
		"value": value,
		"cooldown": tier - 1,
		"damage_type": damage_type,
		"description": "SKILL_DAMAGE_PHYSICAL_DESC" if damage_type == Enums.SKILL_DAMAGE_TYPE.PHYSICAL else "SKILL_DAMAGE_ABILITY_DESC",
		"target": Enums.CARD_TARGETS.SINGLE_ENEMY,
		"scouted": false,
		"tier": tier,
		"shop_cost": {"min": 5 * tier, "max": 15 * tier},
		"handle": func(props): deal_damage(props)
	}
