extends Node

## Betrag in der Währung, z. B. "45 ME" (Monster Essenz)
func me_text(amount: int) -> String:
	return "%d ME" % amount

func generate_fake_uuid() -> String:
	return "%s-%s" % [str(randi()), str(Time.get_ticks_usec())]

func points_per_level(bst: int) -> float:
	return float(bst) / State.SETTING_LEVEL

## Grund-Fangchance pro Seltenheit (bei 0 HP und gleicher Stufe wie das eigene Team)
const CATCH_RARITY_BASE := {
	Enums.MON_RARITY.COMMON: 0.9,
	Enums.MON_RARITY.UNCOMMON: 0.7,
	Enums.MON_RARITY.RARE: 0.5,
	Enums.MON_RARITY.EPIC: 0.3,
	Enums.MON_RARITY.LEGENDARY: 0.15,
	# nur Bosse: mit sehr wenig KP um 7 %, mit vollen KP praktisch nie
	Enums.MON_RARITY.MYTHIC: 0.05,
}
## Anteil der Chance, der bei vollen HP wegfällt (0.75 = volle HP ergeben nur 25 % der Grundchance)
const CATCH_HP_WEIGHT := 0.75
## Chance-Abzug pro Stufe, die das Monster über dem eigenen Team liegt (darunter entsprechend Bonus)
const CATCH_LEVEL_STEP := 0.08
const CATCH_LEVEL_FACTOR_RANGE := [0.25, 1.3]
## Untergrenze 1 %: auch ein mythischer Boss mit vollen KP ist nicht ganz unmöglich
const CATCH_CHANCE_RANGE := [0.01, 0.95]
## Letzte Not: Monster mit höchstens so viel Anteil KP sind leichter zu fangen (Faktor auf die Chance).
## Wirkt für alle, auch Bosse und Kopfgeld-Monster; die Seltenheit steckt schon in der Grundchance,
## seltene Arten profitieren daher absolut weniger (gewöhnlich 10 %: 0.83 -> 0.95, mythisch 5 %: 0.05 -> 0.07).
const CATCH_LOW_HP_TIERS := [
	{"hp_share": 0.05, "factor": 1.5},
	{"hp_share": 0.10, "factor": 1.25},
]

## Fangchance 0..1: je weniger HP, desto leichter; höhere Stufe und Seltenheit machen es schwerer.
func catch_chance(mon: Monster) -> float:
	# Fang-Knopf im Kampf (Debug-Menü): jeder Fang klappt
	if DebugSettings.catches_for_sure():
		return 1.0
	var rarity: int = Monmap.rarity_of(mon._name)
	# Kopfgeld-Monster sind eine Seltenheitsstufe schwerer zu fangen (höchstens legendär, mythisch bleibt mythisch)
	if mon._bounty != "" and rarity < Enums.MON_RARITY.LEGENDARY:
		rarity += 1
	var hp_left = clampf(1.0 - mon._lost_hp / mon.hp(), 0.0, 1.0)
	var hp_factor = 1.0 - CATCH_HP_WEIGHT * hp_left
	var level_factor = clampf(1.0 - CATCH_LEVEL_STEP * (mon._level - _team_level()),
		CATCH_LEVEL_FACTOR_RANGE[0], CATCH_LEVEL_FACTOR_RANGE[1])
	var chance = CATCH_RARITY_BASE[rarity] * hp_factor * level_factor * low_hp_factor(hp_left)
	chance = Relics.modify("catch_chance", chance, mon)
	# Köder (One-Way-Item): fester Zuschlag für diesen Kampf
	chance += mon._item_marks.get("bait", 0.0)
	return clampf(chance,
		CATCH_CHANCE_RANGE[0], CATCH_CHANCE_RANGE[1])

## Bonus-Faktor der Fangchance bei so viel Anteil verbleibender KP (CATCH_LOW_HP_TIERS), sonst 1
func low_hp_factor(hp_left: float) -> float:
	for tier in CATCH_LOW_HP_TIERS:
		if hp_left <= tier.hp_share:
			return tier.factor
	return 1.0

## Durchschnittsstufe der noch kämpfenden eigenen Monster
func _team_level() -> float:
	var alive = State.mons.filter(func(m: Monster): return m.is_alive())
	if alive.is_empty():
		return 0.0
	return alive.reduce(func(sum, m: Monster): return sum + m._level, 0) / float(alive.size())

func will_catch_mon(mon) -> bool:
	return Tutorial.catches_for_sure(mon) or DebugSettings.catches_for_sure() or randf() < catch_chance(mon)

func generate_mons(props: Dictionary = {
	"count": 1,
	"level": 1,
	"initial": false,
}) -> Array[Monster]:
	
	var default_props = {
		"count": 1,
		"level": State.INITIAL_LEVEL,
		"initial": false,
	}
	default_props.merge(props, true)
	print(OS.get_user_data_dir())
	# wilde Monster: Pool des aktuellen Bioms, ohne gewürfelte Pools alle Arten aus Monmap
	var mons_to_pick = Map.wild_species().map(func(meta): return meta.name)
	if State.map_level < State.biome_pools.size() and not State.biome_pools[State.map_level].is_empty():
		mons_to_pick = State.biome_pools[State.map_level]
	var mons: Array[Monster] = []
	if default_props.initial:
		# jede Art höchstens einmal zur Wahl, im Tutorial nur die Start-Monster
		var comp_mons = State.INITIAL_MONS.duplicate() if Tutorial.run_active else get_all_owned_monster_names()
		comp_mons.shuffle()
		var initial_mons = comp_mons.slice(0, default_props.count)
		for i in initial_mons:
			mons.append(initial_mon(i, default_props.level))
		return mons

	# optional ein Kopfgeld-Monster (Eintrag aus Skills.BOUNTIES) als erster Gegner
	var bounty: Dictionary = props.get("bounty", {})
	# optional feste Arten der Reihe nach (Bosse, siehe BossRelics.roll_species), danach wieder aus dem Pool
	var species: Array = props.get("species", [])
	# Das erste wilde Monster würfelt seine Seltenheit (Map.RARITY_SPAWN_WEIGHTS), die Begleiter sind nie seltener.
	# So ist ein seltenes Monster ein Ereignis des Kampfs und nicht in jedem zweiten Kampf irgendwo dabei.
	var max_rarity: int = Enums.MON_RARITY.LEGENDARY
	for i in default_props.count:
		var species_name: String = species[i] if i < species.size() else Map.pick_wild_species(mons_to_pick, max_rarity)
		if i >= species.size() and i == 0:
			max_rarity = Monmap.rarity_of(species_name)
		var mon_meta_data = Monmap.mon_metainfos_by_name(Skills.bounty_mon(bounty) if i == 0 and not bounty.is_empty() else species_name)
		var newMon = Monster.new(default_props.level, mon_meta_data)
		# eigene Kopfgeld-Arten (Monmap bounty_target) sind auch bei normalem Auftauchen das Kopfgeld-Monster
		newMon._bounty = bounty.key if i == 0 and not bounty.is_empty() else mon_meta_data.get("bounty_target", "")
		# Auseinandersetzung (Map.roll_confrontation_enemies): Gegner behalten ihr eigenes Element
		if props.get("biome_element", true):
			add_biome_element(newMon)
		roll_wild_skills(newMon, mon_meta_data)
		roll_egg_skill(newMon)
		ensure_wild_attack(newMon, mon_meta_data)
		if mon_meta_data.get("final_boss", false):
			add_final_boss_skills(newMon)
		mons.append(newMon)
	return mons

# So viele wilde Monster tragen das volle Element des Bioms, der Rest liegt eine Ebene darunter.
const FULL_BIOME_TYPE_CHANCE := 0.25

# Wilde Monster nehmen Elemente des aktuellen Bioms an: meist eine Ebene unter dem Biom, ab und zu das Biom selbst.
# Dampf (Wasser+Feuer) -> Wasser und Feuer, ein paar Dampf. Gewitter (Luft+Wasser+Feuer) -> Dampf, Eis und Blitz,
# ein paar Gewitter. Einzelelement-Biome ändern nichts, dort tauchen die Arten des Elements selbst auf.
# Nie mehr als Monster.MAX_ELEMENTS: Im Chaos-Biom tragen die Monster Dreier-Kombis (Sumpf, Vulkan, ...), Chaos hat nur
# der Endboss als Art-Element.
func add_biome_element(mon: Monster) -> void:
	var biome = State.current_biome()
	var size = Map.count_elements(biome)
	if size <= 1:
		return
	var target_size: int = size if randf() < FULL_BIOME_TYPE_CHANCE else size - 1
	target_size = mini(target_size, Monster.MAX_ELEMENTS)
	var candidates = Enums.MON_TYPES.values().filter(func(element): return biome & element and not mon._type & element)
	candidates.shuffle()
	for element in candidates.slice(0, maxi(target_size - Map.count_elements(mon._type & biome), 0)):
		if Map.count_elements(mon._type) >= Monster.MAX_ELEMENTS:
			break
		mon._type |= element

const WILD_SKILL_COUNT := 3

# Wilde Monster: ein Skill ihrer Art, der Rest aus dem Pool des aktuellen Bioms (tiefere Biome -> stärkere Skills).
# Gezogen werden nur Skills, die das Monster mit seinem Typ wach einsetzen kann (Gegner schlummern nie, Skills.is_awake).
## Universelle Skills (Chaos: Mut & Wille, Goldener Schild, ...) ziehen wilde Monster erst ab so vielen Elementen
## aus dem Biom-Pool, sonst hätte sie fast jedes wilde Monster (sie passen ja zu jedem Element).
const WILD_UNIVERSAL_MIN_ELEMENTS := 3

func roll_wild_skills(mon: Monster, mon_meta_data: Dictionary) -> void:
	var usable = func(skill_name): return Skills.is_awake_name(mon, skill_name)
	var species_pool = mon_meta_data.default_egg_skills.filter(usable)
	# Art ohne passende (existierende) Ei-Attacke: pick_weighted liefert "", dann nur aus dem Biom-Pool
	var skill_names = [Skills.pick_weighted(species_pool)].filter(func(skill_name): return skill_name != "")
	var not_picked = func(skill_name): return not skill_names.has(skill_name)
	var universal_ok := Map.count_elements(mon._type) >= WILD_UNIVERSAL_MIN_ELEMENTS
	var biome_pool = Skills.get_biome_skills(State.current_biome()).filter(usable).filter(not_picked).filter(
		func(skill_name): return universal_ok or not Skills.is_universal(Skills.get_skill(skill_name)))
	skill_names.append_array(Skills.pick_weighted_unique(biome_pool, WILD_SKILL_COUNT - skill_names.size(), State.map_level))
	# zu wenig passende Biom-Skills: mit den Skills der Art auffüllen
	skill_names.append_array(Skills.pick_weighted_unique(species_pool.filter(not_picked), WILD_SKILL_COUNT - skill_names.size()))
	for skill_name in skill_names:
		var skill = Skills.get_skill(skill_name)
		if not skill.is_empty():
			mon._skills.append(skill)

## Ab dieser Seltenheit trägt ein wildes Monster immer mindestens eine Attacke (nicht nur Buffs und Schilde)
const WILD_ATTACK_MIN_RARITY := Enums.MON_RARITY.EPIC

## Hat ein wildes Monster ab WILD_ATTACK_MIN_RARITY keine Attacke, tauscht es einen Skill gegen eine:
## bevorzugt eine Attacke seiner Art, sonst aus dem Biom-Pool. Ei-Attacken (egg_skill) bleiben.
func ensure_wild_attack(mon: Monster, mon_meta_data: Dictionary) -> void:
	if mon_meta_data.get("rarity", 0) < WILD_ATTACK_MIN_RARITY or mon._skills.is_empty():
		return
	if mon._skills.any(func(skill): return Skills.is_damage_skill(skill)):
		return
	var attack_ok = func(skill_name): return Skills.is_awake_name(mon, skill_name) \
		and Skills.is_damage_skill(Skills.get_skill(skill_name)) and not Skills.knows_skill(mon, skill_name)
	var skill_name := Skills.pick_weighted(mon_meta_data.default_egg_skills.filter(attack_ok))
	if skill_name == "":
		skill_name = Skills.pick_weighted(Skills.get_biome_skills(State.current_biome()).filter(attack_ok), State.map_level)
	if skill_name == "":
		skill_name = Skills.pick_weighted(Skills.get_biome_skills(0).filter(attack_ok), State.map_level)
	var skill := Skills.get_skill(skill_name)
	if skill.is_empty():
		return
	# ersetzt wird der letzte Skill, der keine Ei-Attacke ist
	for i in range(mon._skills.size() - 1, -1, -1):
		if not mon._skills[i].get("egg_skill", false):
			mon._skills[i] = skill
			return
	mon._skills.append(skill)

## Der Endboss trägt zusätzlich immer eine Fähigkeit mit mindestens drei Elementen und eine Chaos-Fähigkeit
## (universell, Buff oder Schwächung, keine Passive), beide gewichtet nach Biom-Tiefe.
func add_final_boss_skills(mon: Monster) -> void:
	var fresh = func(skill_name): return Skills.is_awake_name(mon, skill_name) and not Skills.knows_skill(mon, skill_name)
	var pool: Array = Skills.get_biome_skills(0).filter(fresh)
	var triple := pool.filter(func(skill_name):
		var skill := Skills.get_skill(skill_name)
		return not Skills.is_universal(skill) and not Skills.is_passive(skill) and Map.count_elements(skill.nature) >= 3)
	var chaos := pool.filter(func(skill_name):
		var skill := Skills.get_skill(skill_name)
		return Skills.is_universal(skill) and not Skills.is_passive(skill))
	for skill_name in [Skills.pick_weighted(triple, State.map_level), Skills.pick_weighted(chaos, State.map_level)]:
		var skill := Skills.get_skill(skill_name)
		if not skill.is_empty():
			mon._skills.append(skill)

const EGG_SKILL_CHANCE := 0.35

# Wilde Monster tragen mit etwas Glück genau eine noch nicht freigeschaltete Ei-Attacke ihrer Art.
func roll_egg_skill(mon: Monster) -> void:
	if randf() <= EGG_SKILL_CHANCE:
		add_egg_skill(mon)

# Gibt dem Monster eine noch nicht freigeschaltete Ei-Attacke seiner Art, falls es noch eine gibt.
# Nur Arten aus der Ei-Auswahl tragen Ei-Attacken, alle anderen könnten sie ohnehin nicht freischalten.
func add_egg_skill(mon: Monster) -> void:
	if not Skills.can_unlock_egg_skills(mon._name):
		return
	var locked = Skills.get_locked_egg_skills(mon._name)
	if locked.is_empty():
		return
	# bevorzugt Ei-Attacken, die das Monster selbst wach einsetzen kann
	var usable_locked = locked.filter(func(skill_name): return Skills.is_awake_name(mon, skill_name))
	var skill = Skills.get_skill(Skills.pick_weighted(usable_locked if not usable_locked.is_empty() else locked, State.map_level))
	if skill.is_empty() or mon._skills.is_empty():
		return
	skill.egg_skill = true
	# trägt das Monster den Skill schon (aus dem Biom-Pool), wird genau dieser markiert
	var index = mon._skills.map(func(s): return s.name).find(skill.name)
	mon._skills[index if index != -1 else mon._skills.size() - 1] = skill
	
func color_by_mon(mon: Monster) -> Color:
	return ColorMap.get_combo(mon._type).color

func mon_display_name(mon_name: String) -> String:
	return tr("MONSTER_" + mon_name)

# Anzeigename eines konkreten Monsters, Kopfgeld-Monster tragen ihren Titel ("Alpha 1").
func mon_battle_name(mon: Monster) -> String:
	if mon._bounty == "":
		return mon_display_name(mon._name)
	return tr(Skills.get_bounty(mon._bounty).label).format({"mon": mon_display_name(mon._name)})

# Kurzer Hinweis oben auf dem Bildschirm, der von selbst verblasst (bleibt auch bei Szenenwechseln stehen).
func show_unlock_message(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme = preload("res://script/ui/materials/pixel_font_theme.tres")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Color(0.858824, 0.717647, 0.45098, 1))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.position.y = 40
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(label)
	label.position.x = (get_tree().root.get_visible_rect().size.x - label.get_minimum_size().x) / 2
	var tween := label.create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(label.queue_free)

func type_name_by_mon(mon: Monster) -> String:
	return ColorMap.get_combo(mon._type).label
	# return Enums.MON_TYPE_MAP[str(mon._type)]

func color_by_type(type: int) -> Color:
	return ColorMap.get_combo(type).color

## Zahlen für die Anzeige: ganze Floats ohne ".0" (78.0 -> 78), sonst eine Nachkommastelle
func format_number(v) -> String:
	if v is float:
		return str(roundi(v)) if is_equal_approx(v, roundf(v)) else str(snappedf(v, 0.1))
	return str(v)

## Farbe für wichtige Stellen in Beschreibungen (Werte, Schadensart), siehe highlight
const HIGHLIGHT_COLOR := Color(1.0, 0.84, 0.25)

## Übersetzungen markieren wichtige Stellen mit [hl]...[/hl]. rich = als BBCode gelb färben (RichTextLabel),
## sonst die Markierungen entfernen (normale Labels)
func highlight(text: String, rich := false) -> String:
	if rich:
		return text.replace("[hl]", "[color=#%s]" % HIGHLIGHT_COLOR.to_html(false)).replace("[/hl]", "[/color]")
	return text.replace("[hl]", "").replace("[/hl]", "")

## Grau für Werte und Element-Effekte, die ein schlummernder Skill nicht hat (skill_description)
const INACTIVE_COLOR := Color(0.55, 0.53, 0.5)

## Skill-Beschreibung mit eingesetzten Werten, Zahlen wie in format_number,
## bei Kombi-Elementen mit dem Element-Effekt als zweiter Zeile (ElementEffects).
## rich = wichtige Stellen als BBCode gelb (für RichTextLabel mit bbcode_enabled)
## mon: Besitzer. Schlummert der Skill bei ihm (Skills.effective_skill), steht der volle Wert grau durchgestrichen
## vor dem abgeschwächten, der Element-Effekt ist grau durchgestrichen und darunter steht, was ihn weckt.
## Ohne rich gibt es kein Durchstreichen: dann nur der abgeschwächte Wert und "Inaktiv: ..." vor dem Effekt.
func skill_description(skill: Dictionary, rich := false, mon: Monster = null) -> String:
	var used := Skills.effective_skill(mon, skill)
	var dormant: bool = used.get("_dormant", false)
	var values := {}
	for key in used:
		values[key] = format_number(used[key]) if used[key] is float else used[key]
	# Auslösechance von Statuseffekt-Karten in Prozent (0.25 -> 25)
	if used.get("chance") is float:
		values.chance = roundi(used.chance * 100)
	var full_value = Skills.level_value(mon, skill) if skill.has("per_level") else skill.get("value")
	if dormant and rich and used.has("value") and used.value != full_value:
		values.value = _inactive(format_number(full_value)) + " " + values.value
	# Platzhalter für Buffs und Passive: {stat} = Kurzname des Werts, {element} = Element der Element-Passive
	values.stat = Skills.stat_label(skill.get("buff_stat", skill.get("passive_stat", "")))
	values.element = tr(ColorMap.get_combo(skill.get("passive_element", skill.nature)).label)
	var lines := PackedStringArray([tr(skill.description).format(values)])
	lines.append_array(Skills.extras_text(skill))
	var effect := ElementEffects.skill_effect_text(skill)
	if effect != "":
		if not dormant:
			lines.append(effect)
		elif rich:
			lines.append(_inactive(highlight(effect)))
		else:
			lines.append(tr("SKILL_EFFECT_INACTIVE").format({"effect": effect}))
	if dormant:
		lines.append(Skills.dormant_text(mon, skill))
	return highlight("\n".join(lines), rich)

## grau und durchgestrichen (BBCode)
func _inactive(text: String) -> String:
	return "[color=#%s][s]%s[/s][/color]" % [INACTIVE_COLOR.to_html(false), text]

func between(v, min, max) -> bool:
	return v >= min and v <= max

## Start-Monster der Ei-Auswahl mit einem Vorschlag aus den verfügbaren Ei-Attacken (im Konfigurator noch änderbar):
## wache Attacken zuerst, schlummernde und nicht spielbare nur zum Auffüllen
func initial_mon(mon_name: String, level := -1) -> Monster:
	var mon := Monster.new(level if level >= 0 else State.INITIAL_LEVEL, Monmap.mon_metainfos_by_name(mon_name))
	var available = Skills.get_available_egg_skills(mon_name)
	var usable = available.filter(func(skill_name): return Skills.is_awake_name(mon, skill_name))
	var proposal = Skills.pick_weighted_unique(usable, 3)
	proposal.append_array(Skills.pick_weighted_unique(available.filter(func(skill_name): return not proposal.has(skill_name)), 3 - proposal.size()))
	for skill_name in proposal:
		var skill = Skills.carried_egg_skill(skill_name)
		if skill.is_empty():
			continue
		skill.scouted = true
		mon._skills.append(skill)
	return mon

func get_all_owned_monster_names() -> Array:
	# Start-Monster und gefangene Arten, jede Art nur einmal
	var all_mons = []
	for mon_name in State.INITIAL_MONS + SaveManager.save_data.catched_monsters:
		if not all_mons.has(mon_name):
			all_mons.append(mon_name)
	return all_mons

# Ei der Start-Auswahl als JSON-taugliche Daten für den Spielstand: Art, gewürfelte Stats, Attacken-Vorschlag
func egg_to_save(mon: Monster) -> Dictionary:
	var growth := {}
	for attr in Growth.ATTRS:
		growth[attr] = mon._growth[attr]
	return {
		"name": mon._name,
		"best_points": mon._best_points,
		"growth": growth,
		"skills": mon._skills.map(func(skill): return skill.name),
	}

# Gegenstück zu egg_to_save. Stats gelten pro Art, daher zuerst die Art wiederherstellen und dann das Monster erzeugen.
func mon_from_egg(egg: Dictionary) -> Monster:
	State.restore_mon_stats(egg.name, int(egg.best_points), egg.growth)
	var mon := Monster.new(State.INITIAL_LEVEL, Monmap.mon_metainfos_by_name(egg.name))
	# Skills, die es nicht mehr gibt (älterer Spielstand), fallen weg und werden mit Standard-Skills der Art aufgefüllt
	# nur Ei-Attacken, die die Art aktuell hat (gelöschte oder aus der Liste der Art entfernte fallen weg)
	var available := Skills.get_available_egg_skills(egg.name)
	var names: Array = egg.skills.filter(func(skill_name): return available.has(skill_name))
	for skill_name in available:
		if names.size() >= EGG_SKILL_COUNT:
			break
		if not names.has(skill_name):
			names.append(skill_name)
	for skill_name in names:
		var skill = Skills.carried_egg_skill(skill_name)
		if skill.is_empty():
			continue
		skill.scouted = true
		mon._skills.append(skill)
	return mon

## So viele Attacken bringt ein Ei der Start-Auswahl mit (wie im Ei-Konfigurator)
const EGG_SKILL_COUNT := 3
#func balance_growth_rate(max_level) -> Dictionary:
	
# send message
# animation helper
# wait timer
