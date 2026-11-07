extends Control

## Infobereich im Kampf: oben das Turn Wheel, darunter Werte und Skills
## des Monsters, das gerade auf dem Feld ausgewählt ist (eigenes oder gegnerisches).

const SKILL_COLUMNS := ["SKILL_HEADER_SKILL", "SKILL_HEADER_COST", "SKILL_HEADER_CD", "SKILL_HEADER_POWER"]
const EGG_SKILL_COLOR := Color(0.858824, 0.717647, 0.45098, 1)
const EGG_LOCKED_COLOR := Color(0.5, 0.5, 0.5)
const EGG_TEXTURE := preload("res://assets/ui/eggs/common_1.png")

@export var turn_wheel: Control
@export var name_label: Label
@export var element_chip: Control
## Seltenheit der Art, rechts neben dem Typ
@export var rarity_chip: Control
## optional: freigeschaltete Züge (Aktionen pro Zug) der Art als Zahl mit Partikeln, rechts neben der Seltenheit
@export var moves_badge: Control
@export var stats_grid: GridContainer
@export var skill_grid: GridContainer
@export var skill_info_container: Control

@export var physical_texture: Texture2D
@export var magic_texture: Texture2D

## optionales Bild des Monsters (Ei-Auswahl), im Kampf steht es auf dem Feld
@export var monster_texture: TextureRect
## Werte und Skills immer zeigen (Start-Monster, die noch nicht im Team sind)
@export var reveal_all := false
## Statt der Skills eine Übersicht der Ei-Attacken der Art nach Kategorie (Start-Auswahl,
## die konkreten Attacken wählt man danach im Ei-Konfigurator)
@export var egg_skill_overview := false

var monster: Monster:
	set(mon):
		monster = mon
		refresh()

func refresh() -> void:
	if monster == null:
		return
	name_label.text = "%s  Lv. %d" % [Helper.mon_battle_name(monster), monster._level]
	name_label.self_modulate = Helper.color_by_mon(monster)
	element_chip._init_color(monster)
	if rarity_chip:
		var rarity := Monmap.rarity_of(monster._name)
		rarity_chip._init_with_element({"label": Monmap.RARITY_LABELS[rarity], "color": Monmap.RARITY_COLORS[rarity]})
	if moves_badge:
		# Grundzug plus beim Kerkermeister gesprengte Ketten, von maximal möglichen
		var max_moves: int = Monster.BASE_MOVES + Monmap.mon_metainfos_by_name(monster._name).get("max_upgrades", 0)
		moves_badge.set_moves(Monster.BASE_MOVES + monster._upgrades, max_moves)
	if monster_texture:
		Monmap.show_on(monster_texture, monster._name, Monmap.MEDIUM)
		_reveal_monster_pixels()
	stats_grid.init_with_mon(monster, _hidden_stats())
	skill_info_container.visible = false
	if egg_skill_overview:
		_build_egg_skill_overview()
	else:
		_build_skill_list()

## Eigene Werte sind bekannt. Bei Gegnern deckt ein Treffer (Sp.) Verteidigung bzw. (Sp.) Angriff auf
## (Skills.reveal_stats_by_hit), ein Fang der Art alle Werte.
func _hidden_stats() -> Array:
	if reveal_all or State.mons.has(monster) or State.is_mon_known(monster._name) or Relics.works("all_stats"):
		return []
	var hidden := ["hp", "speed", "bst"]
	for stat in ["atk", "def", "s_atk", "s_def"]:
		if not State.is_mon_stat_revealed(monster._name, stat):
			hidden.append(stat)
	return hidden

## Pixel-Partikel des Monsterbilds tauchen nacheinander auf (nur mit living_pixels-Shader)
func _reveal_monster_pixels() -> void:
	var shared := monster_texture.material as ShaderMaterial
	if shared == null or shared.get_shader_parameter("reveal") == null:
		return
	# eigene Kopie, sonst blenden alle Monsterbilder mit dem gleichen Material neu ein
	var mat := shared.duplicate() as ShaderMaterial
	monster_texture.material = mat
	create_tween().tween_method(func(v: float): mat.set_shader_parameter("reveal", v), 0.0, 1.0, 0.5)

func _clear_skill_grid(columns: int) -> void:
	for c in skill_grid.get_children():
		c.queue_free()
	skill_grid.columns = columns

## Pro Kategorie: freigeschaltete / alle Ei-Attacken der Art in Weiß, gesperrte Kategorien grau.
## Ein Klick auf eine Kategorie listet ihre Attacken im Info-Fenster.
func _build_egg_skill_overview() -> void:
	# eine Spalte: oben die Überschrift über die ganze Breite, darunter eine Zeile pro Kategorie
	_clear_skill_grid(1)
	var egg_skills := Skills.get_all_egg_skills(monster._name)
	var by_category := {}
	for skill_name in egg_skills.available + egg_skills.locked:
		var key := Skills.egg_skill_category(Skills.get_skill(skill_name))
		if not by_category.has(key):
			by_category[key] = {"available": [], "locked": []}
		by_category[key]["available" if egg_skills.available.has(skill_name) else "locked"].append(skill_name)

	var total: int = egg_skills.available.size() + egg_skills.locked.size()
	var title := _label("%s  %d/%d" % [tr("EGG_OVERVIEW_TITLE"), egg_skills.available.size(), total], EGG_SKILL_COLOR)
	title.add_theme_font_size_override("font_size", EGG_CATEGORY_FONT_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# langer Titel bricht um, statt die Spalte über den Rand der Platte zu drücken
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skill_grid.add_child(title)

	for category in Skills.EGG_SKILL_CATEGORIES:
		if not by_category.has(category.key):
			continue
		var entry: Dictionary = by_category[category.key]
		entry["hints"] = egg_skills.hints
		var color := IronPlate.TEXT_COLOR if entry.available.size() > 0 else EGG_LOCKED_COLOR
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_show_egg_category_info(category, entry))
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = load(category.icon)
		icon.modulate = color
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var category_label := _label(tr(category.label), color)
		category_label.add_theme_font_size_override("font_size", EGG_CATEGORY_FONT_SIZE)
		category_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		category_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(category_label)
		var count_label := _label("%d/%d" % [entry.available.size(), entry.available.size() + entry.locked.size()], color)
		count_label.add_theme_font_size_override("font_size", EGG_CATEGORY_FONT_SIZE)
		row.add_child(count_label)
		skill_grid.add_child(row)

## Attacken der Kategorie in ihrer Element-Farbe, gesperrte blasser; ein Klick öffnet die Details daneben.
func _show_egg_category_info(category: Dictionary, entry: Dictionary) -> void:
	if _egg_skill_list == null:
		_egg_skill_list = VBoxContainer.new()
		# Abstand zwischen den Blöcken "Freigeschaltet" und "Gesperrt"
		_egg_skill_list.add_theme_constant_override("separation", EGG_GROUP_SEPARATION)
		var info_box: Node = skill_info_container.skill_description.get_parent()
		info_box.add_child(_egg_skill_list)
		info_box.move_child(_egg_skill_list, skill_info_container.skill_description.get_index() + 1)
	for c in _egg_skill_list.get_children():
		c.queue_free()
	for group in [["EGG_OVERVIEW_UNLOCKED", entry.available, false], ["EGG_OVERVIEW_LOCKED", entry.locked, true]]:
		if group[1].is_empty():
			continue
		var group_box := VBoxContainer.new()
		group_box.add_theme_constant_override("separation", 4)
		_egg_skill_list.add_child(group_box)
		var divider := ColorRect.new()
		divider.color = IronPlate.RIM
		divider.custom_minimum_size.y = EGG_DIVIDER_HEIGHT
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group_box.add_child(divider)
		var group_label := _label(tr(group[0]), EGG_SKILL_COLOR)
		group_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		group_label.add_theme_font_size_override("font_size", 15)
		group_box.add_child(group_label)
		for skill_name in group[1]:
			var skill := Skills.get_skill(skill_name)
			var locked: bool = group[2]
			var skill_label := _label(tr(skill_name), Helper.color_by_type(skill.nature))
			skill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			# lange Namen brechen um, statt aus der Box zu laufen
			skill_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if locked:
				skill_label.modulate = Color(1, 1, 1, 0.55)
			skill_label.mouse_filter = Control.MOUSE_FILTER_STOP
			skill_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			skill_label.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					_show_egg_skill_detail(skill, entry.hints.get(skill_name, [])))
			group_box.add_child(skill_label)
	skill_info_container.skill_name.text = tr(category.label)
	skill_info_container.skill_name.self_modulate = EGG_SKILL_COLOR
	skill_info_container.skill_name.add_theme_font_size_override("font_size", SKILL_FONT_SIZE)
	skill_info_container.skill_description.visible = false
	_egg_skill_list.visible = true
	skill_info_container.visible = true

# ─────────────────────────
# Details eines Skills im Popup neben dem Panel (SkillDetailPopup): Ei-Attacken der Auswahl und Skills im Kampf.

const EGG_CATEGORY_FONT_SIZE := 20
const EGG_GROUP_SEPARATION := 20
const EGG_DIVIDER_HEIGHT := 2.0
const SKILL_FONT_SIZE := 18

var _egg_skill_list: VBoxContainer
var _detail_popup: SkillDetailPopup

func _show_egg_skill_detail(skill: Dictionary, lock_hint: Array) -> void:
	_popup().show_skill(skill, monster, self, lock_hint, Skills.get_egg_skill_source(monster._name, skill.name))

func _popup() -> SkillDetailPopup:
	if _detail_popup == null:
		_detail_popup = SkillDetailPopup.new()
		add_child(_detail_popup)
		# schließt das Info-Fenster (oder wechselt das Monster), verschwindet auch das Popup
		skill_info_container.visibility_changed.connect(func():
			if not skill_info_container.visible:
				_detail_popup.hide_popup())
	return _detail_popup

func _build_skill_list() -> void:
	_clear_skill_grid(SKILL_COLUMNS.size() + 1)
	skill_grid.add_child(Control.new())
	for header in SKILL_COLUMNS:
		skill_grid.add_child(_label(tr(header), EGG_SKILL_COLOR))
	# eigene Skills sind bekannt, gegnerische erst nachdem sie eingesetzt wurden
	var known_all := reveal_all or State.mons.has(monster)
	for skill in monster._skills:
		var known: bool = known_all or skill.scouted
		# Ei-Attacken, die durch Fangen + Opfern freigeschaltet werden können, sind immer markiert
		var is_egg_skill := Skills.is_unlockable_egg_skill(monster, skill)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if is_egg_skill:
			icon.texture = EGG_TEXTURE
			icon.material = Monmap.egg_material(Monmap.rarity_of(monster._name))
			icon.tooltip_text = tr("EGG_SKILL_HINT")
		elif known:
			icon.texture = physical_texture if skill.damage_type == Enums.SKILL_DAMAGE_TYPE.PHYSICAL else magic_texture
		skill_grid.add_child(icon)

		# unbekannte Skills verraten Element (Farbe) und Stufe, damit man gezielt Monster jagen kann
		var name_color := Helper.color_by_type(skill.nature)
		var name_text := tr(skill.name) if known else tr("BATTLE_UNKNOWN_SKILL").format({"tier": skill.get("tier", 1)})
		if is_egg_skill:
			name_color = EGG_SKILL_COLOR
			name_text = tr("EGG_SKILL_TAG").format({"skill": name_text})
		var skill_name := _label(name_text, name_color)
		if is_egg_skill:
			skill_name.tooltip_text = tr("EGG_SKILL_HINT")
			skill_name.mouse_filter = Control.MOUSE_FILTER_STOP
		elif not known:
			skill_name.tooltip_text = tr("BATTLE_UNKNOWN_SKILL_HINT")
			skill_name.mouse_filter = Control.MOUSE_FILTER_STOP
		skill_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		skill_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		skill_name.clip_text = true
		if known:
			skill_name.mouse_filter = Control.MOUSE_FILTER_STOP
			skill_name.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			skill_name.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					_show_skill_info(skill))
		skill_grid.add_child(skill_name)
		for value in [skill.cost, skill.cooldown, skill.get("value", skill.get("damage", ""))]:
			skill_grid.add_child(_label(Helper.format_number(value) if known else "?"))

func _label(text: String, color: Color = IronPlate.TEXT_COLOR) -> Label:
	var label := Label.new()
	label.text = text
	label.self_modulate = color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", SKILL_FONT_SIZE)
	return label

## Skills in der Liste öffnen das Detail-Popup neben dem Panel (Karten auf der Hand nicht)
func _show_skill_info(skill) -> void:
	var lock_hint := ["CONFIGURATOR_LOCKED", "EGG_SKILL_HINT"] if Skills.is_unlockable_egg_skill(monster, skill) else []
	skill_info_container.visible = false
	_popup().show_skill(skill, monster, self, lock_hint)
