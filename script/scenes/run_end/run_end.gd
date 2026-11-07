extends Control

# Endbildschirm eines Runs, für Sieg (world_map.gd) und Niederlage (battle.gd). Werte stehen in State.run_*.

const GOLD := SkillDetailPopup.GOLD
const TEXT_COLOR := IronPlate.TEXT_COLOR
const WIN_COLOR := GOLD
const LOSE_COLOR := Color(0.75, 0.22, 0.2, 1)

@export var background: TextureRect
@export var title_label: Label
@export var subtitle_label: Label
@export var biome_path: Control
@export var stats_grid: GridContainer
@export var team_label: Label
@export var unlock_label: Label
@export var killer_label: Label
@export var fallen_label: Label
@export var search_edit: LineEdit
@export var mon_list: ItemList
@export var detail_box: VBoxContainer
@export var biome_tabs: HBoxContainer

const FLAT_BUTTON_THEME := preload("res://script/scenes/battle/flat_button_theme.tres")

# Basiswerte für die Monster-Suche: Anteil am Wachstum * BST, wie die Base Stats in Ironmon
const SEARCH_STATS := [
	["STAT_HP", "hp"],
	["STAT_ATK", "atk"],
	["STAT_DEF", "def"],
	["STAT_SPA", "s_atk"],
	["STAT_SPD", "s_def"],
	["STAT_SPE", "speed"],
]

# höchster Basiswert aller Arten, damit die Balken zwischen den Monstern vergleichbar sind
var _bar_max := 1.0
# gewählte Tiefe in der Monster-Suche, -1 = alle Arten
var _biome_filter := -1
# Arten in deinem Besitz, nur diese sind in der Monster-Suche aufgedeckt
var _owned: Array = []
# Ansicht im Detailbereich: "stats" oder "skills"
var _detail_view := "stats"
var _shown_mon := ""

func _ready() -> void:
	var color = WIN_COLOR if State.run_won else LOSE_COLOR
	background.material.set_shader_parameter("top_color", color)
	title_label.text = tr("RUN_END_WIN" if State.run_won else "RUN_END_LOSE")
	# Hintergrund hat dieselbe Farbe, daher heller Text mit dunkler Kontur
	title_label.add_theme_color_override("font_color", color.lightened(0.6))
	title_label.add_theme_color_override("font_outline_color", color.darkened(0.6))
	title_label.add_theme_constant_override("outline_size", 10)
	subtitle_label.text = tr("RUN_END_WIN_SUB" if State.run_won else "RUN_END_LOSE_SUB")

	# map_level ist der Index des aktuellen Bioms, nach dem Sieg steht er auf map_settings.size()
	var total_depth = Map.map_settings.size()
	var reached = mini(State.map_level + 1, total_depth)
	if not State.biome_path.is_empty():
		biome_path.show_path(State.biome_path, reached)

	_add_stat("RUN_END_DEPTH", "%d / %d" % [reached, total_depth])
	_add_stat("RUN_END_FIGHTS", str(State.overall_progress_level))
	_add_stat("RUN_END_KILLS", str(State.run_kills))
	_add_stat("RUN_END_CATCHES", str(State.run_catches))
	_add_stat("RUN_END_EP", str(State.run_ep_earned))

	var names = State.run_team.map(func(mon_name): return Helper.mon_display_name(mon_name))
	team_label.text = tr("RUN_END_TEAM").format({"team": ", ".join(PackedStringArray(names))})
	team_label.visible = not names.is_empty()

	_show_deaths()
	_init_search()

	if State.run_won:
		_show_unlocks(Skills.add_milestone_progress(State.starter_name, "game_wins"))

# ─────────────────────────
# K.O.s eigener Monster (State.run_deaths), bei einer Niederlage ist der letzte der Run-beendende Treffer

func _show_deaths() -> void:
	var deaths = State.run_deaths
	if deaths.is_empty():
		return
	var fallen = deaths.duplicate()
	if not State.run_won:
		killer_label.text = tr("RUN_END_KILLED_BY") + "\n" + _death_line(fallen.pop_back())
		killer_label.visible = true
	if fallen.is_empty():
		return
	var lines = fallen.map(func(death): return "• " + _death_line(death))
	fallen_label.text = tr("RUN_END_FALLEN") + "\n" + "\n".join(PackedStringArray(lines))
	fallen_label.visible = true

func _death_line(death: Dictionary) -> String:
	var line = tr("RUN_END_DEATH_LINE").format({
		"killer": death.killer_display,
		"killer_level": death.killer_level,
		"victim": Helper.mon_display_name(death.victim),
		"victim_level": death.victim_level,
		"skill": tr(death.skill),
		"damage": roundi(death.damage),
		"hp_left": ceili(death.hp_left),
		"max_hp": roundi(death.max_hp),
	})
	if not is_equal_approx(death.multiplier, 1.0):
		line += " " + tr("RUN_END_ELEMENT").format({"mult": str(snappedf(death.multiplier, 0.01))})
	return line

# ─────────────────────────
# Monster-Suche pro Biom: zeigt den gewürfelten Pool jeder Tiefe (State.biome_pools) und die Sichtungen.
# Nur Arten in deinem Besitz (Helper.get_all_owned_monster_names) sind aufgedeckt, egal ob in diesem Run gefangen.
# Alle anderen sind Silhouetten: gesehene mit Namen und Stufe, ungesehene als "???".

func _init_search() -> void:
	_owned = Helper.get_all_owned_monster_names()
	for meta_data in Monmap.mons:
		var stats = State.get_mon_stats(meta_data.name)
		for stat in SEARCH_STATS:
			_bar_max = maxf(_bar_max, stats.growth[stat[1]] * stats.best_points)
	_build_biome_tabs()
	search_edit.text_changed.connect(func(_query): _refresh_list())
	mon_list.item_selected.connect(func(index): _show_mon(mon_list.get_item_metadata(index)))
	_refresh_list()
	# bei einer Niederlage direkt den Gegner zeigen, der den Run beendet hat (falls in deinem Besitz)
	if not State.run_won and not State.run_deaths.is_empty():
		_select_mon(State.run_deaths.back().killer)

func _build_biome_tabs() -> void:
	var group = ButtonGroup.new()
	var depths = [-1]
	for i in maxi(State.biome_path.size(), State.biome_pools.size()):
		depths.append(i)
	for depth in depths:
		var button = Button.new()
		button.toggle_mode = true
		button.button_group = group
		_style_toggle(button)
		button.add_theme_font_size_override("font_size", 14)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if depth == -1:
			button.text = tr("RUN_END_SEARCH_ALL")
			button.button_pressed = true
		else:
			button.text = str(depth + 1)
			if depth < State.biome_path.size():
				var combo = ColorMap.get_combo(State.biome_path[depth])
				button.add_theme_color_override("font_color", Color(combo.color).lightened(0.25))
				button.tooltip_text = tr("RUN_END_SEARCH_BIOME").format({"n": depth + 1, "element": tr(combo.label)})
		button.pressed.connect(func():
			_biome_filter = depth
			_refresh_list())
		biome_tabs.add_child(button)

# Arten der gewählten Tiefe: erst der Pool, dann Arten, die trotzdem auftauchten (z. B. Kopfgeld-Monster)
func _species_for_filter() -> Array:
	if _biome_filter == -1:
		return Monmap.mons.map(func(meta): return meta.name)
	var names = []
	if _biome_filter < State.biome_pools.size():
		names.append_array(State.biome_pools[_biome_filter])
	if _biome_filter < State.run_sightings.size():
		for mon_name in State.run_sightings[_biome_filter]:
			if not names.has(mon_name):
				names.append(mon_name)
	return names

func _refresh_list() -> void:
	var query = search_edit.text.strip_edges().to_lower()
	mon_list.clear()
	for mon_name in _species_for_filter():
		var owned = _owned.has(mon_name)
		var seen = owned or State.is_mon_seen(mon_name, _biome_filter)
		var display = Helper.mon_display_name(mon_name) if seen else "???"
		# ungesehene Arten verraten sich nicht über die Suche
		if query != "" and (not seen or not display.to_lower().contains(query)):
			continue
		var sighting = _last_sighting(mon_name)
		if not sighting.is_empty():
			display += " · Lv. %d" % sighting.level
		var index = mon_list.add_item(display, Monmap.texture(mon_name, Monmap.ICON))
		mon_list.set_item_metadata(index, mon_name)
		if not owned:
			mon_list.set_item_selectable(index, false)
			mon_list.set_item_icon_modulate(index, Color.BLACK)
			mon_list.set_item_custom_fg_color(index, Color(TEXT_COLOR, 0.45 if seen else 0.25))
			mon_list.set_item_tooltip(index, tr("RUN_END_SEARCH_LOCKED"))
	for index in mon_list.item_count:
		if mon_list.is_item_selectable(index):
			mon_list.select(index)
			_show_mon(mon_list.get_item_metadata(index))
			return
	_show_locked()

func _select_mon(mon_name: String) -> void:
	for index in mon_list.item_count:
		if mon_list.get_item_metadata(index) == mon_name and mon_list.is_item_selectable(index):
			mon_list.select(index)
			# erst nach dem Layout ist die Listenhöhe bekannt
			mon_list.ensure_current_is_visible.call_deferred()
			_show_mon(mon_name)
			return

# Letzte Sichtung in der gewählten Tiefe, bei "Alle" die tiefste, mit "depth" ergänzt
func _last_sighting(mon_name: String) -> Dictionary:
	var depths = [_biome_filter] if _biome_filter >= 0 else range(State.run_sightings.size() - 1, -1, -1)
	for depth in depths:
		if depth < State.run_sightings.size() and State.run_sightings[depth].has(mon_name):
			var sighting = State.run_sightings[depth][mon_name].duplicate()
			sighting.depth = depth
			return sighting
	return {}

func _clear_detail() -> void:
	for child in detail_box.get_children():
		child.queue_free()
	detail_box.get_parent().scroll_vertical = 0

func _show_locked() -> void:
	_clear_detail()
	var hint = _label(tr("RUN_END_SEARCH_LOCKED"), 14)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(TEXT_COLOR, 0.6))
	detail_box.add_child(hint)

func _show_mon(mon_name: String) -> void:
	_clear_detail()
	_shown_mon = mon_name
	var meta_data = Monmap.mon_metainfos_by_name(mon_name)
	var sighting = _last_sighting(mon_name)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	var portrait = TextureRect.new()
	Monmap.show_on(portrait, mon_name, 64)
	portrait.custom_minimum_size = Vector2(64, 64)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(portrait)
	var info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	var mon_title = _label(Helper.mon_display_name(mon_name), 20)
	mon_title.add_theme_color_override("font_color", GOLD)
	info.add_child(mon_title)
	# gesehene Monster hatten zusätzlich Elemente des Bioms
	var type = sighting.get("type", meta_data.initial_type)
	var element = _label(tr(ColorMap.get_combo(type).label), 14)
	element.add_theme_color_override("font_color", Helper.color_by_type(type).lightened(0.25))
	info.add_child(element)
	info.add_child(_label("%s %d" % [tr("STAT_BST"), State.get_mon_stats(mon_name).best_points], 14))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(info)
	header.add_child(_view_toggle())
	detail_box.add_child(header)

	if _detail_view == "skills":
		_show_skills(mon_name, sighting)
	else:
		_show_stats(mon_name, sighting)

# Umschalter Werte / Fähigkeiten, die Auswahl bleibt beim Wechsel des Monsters erhalten
func _view_toggle() -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var group = ButtonGroup.new()
	for view in [["stats", "RUN_END_VIEW_STATS"], ["skills", "RUN_END_VIEW_SKILLS"]]:
		var button = Button.new()
		button.toggle_mode = true
		button.button_group = group
		_style_toggle(button)
		button.text = tr(view[1])
		button.add_theme_font_size_override("font_size", 12)
		button.button_pressed = _detail_view == view[0]
		button.pressed.connect(func():
			_detail_view = view[0]
			_show_mon(_shown_mon))
		box.add_child(button)
	return box

func _show_stats(mon_name: String, sighting: Dictionary) -> void:
	var stats = State.get_mon_stats(mon_name)
	# Basiswerte und, falls gesehen, die echten Werte bei der letzten Sichtung
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	for text in ["", "", tr("RUN_END_SEARCH_BASE"), "Lv. %d" % sighting.level if not sighting.is_empty() else ""]:
		var head = _label(text, 12)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_theme_color_override("font_color", GOLD)
		grid.add_child(head)
	for stat in SEARCH_STATS:
		var share: float = stats.growth[stat[1]]
		var value = share * stats.best_points
		var stat_name = _label(tr(stat[0]), 14)
		stat_name.add_theme_color_override("font_color", GOLD)
		grid.add_child(stat_name)
		grid.add_child(_stat_bar(value))
		var value_label = _label("%d (%d%%)" % [roundi(value), roundi(share * 100)], 14)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value_label)
		var seen_label = _label(str(roundi(sighting.stats[stat[1]])) if not sighting.is_empty() else "", 14)
		seen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(seen_label)
	detail_box.add_child(grid)

	var notes = []
	if State.run_team_levels.has(mon_name):
		notes.append(tr("RUN_END_SEARCH_IN_TEAM").format({"level": State.run_team_levels[mon_name]}))
	if sighting.is_empty():
		notes.append(tr("RUN_END_SEARCH_NOT_SEEN"))
	else:
		notes.append(tr("RUN_END_SEARCH_LAST_SEEN").format({"level": sighting.level, "n": sighting.depth + 1, "count": sighting.count}))
	# was dieses Monster in diesem Run angerichtet hat
	var kills = State.run_deaths.filter(func(death): return death.killer == mon_name)
	if not kills.is_empty():
		var hardest = kills.reduce(func(a, b): return a if a.damage >= b.damage else b)
		notes.append(tr("RUN_END_SEARCH_KILLS").format({"count": kills.size(), "skill": tr(hardest.skill), "damage": roundi(hardest.damage)}))
	var note = _label("\n".join(PackedStringArray(notes)), 13)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color(1, 0.55, 0.5, 1) if not kills.is_empty() else TEXT_COLOR)
	detail_box.add_child(note)

# Fähigkeiten der letzten Sichtung und alle Ei-Attacken der Art (gesperrte abgedunkelt)
func _show_skills(mon_name: String, sighting: Dictionary) -> void:
	var lines = []
	if sighting.is_empty():
		lines.append(_dim(tr("RUN_END_SEARCH_NOT_SEEN")))
	else:
		lines.append(_dim(tr("RUN_END_SKILLS_SEEN").format({"level": sighting.level, "n": sighting.depth + 1})))
		for seen_skill in sighting.skills:
			var line = "  " + _skill_text(Skills.get_skill(seen_skill.name))
			if seen_skill.egg:
				line += " " + _dim(tr("RUN_END_SKILLS_EGG"))
			lines.append(line)
	var meta = Monmap.mon_metainfos_by_name(mon_name)
	var groups = [
		["RUN_END_EGG_DEFAULT", meta.get("default_egg_skills", [])],
		["RUN_END_EGG_UNLOCKABLE", meta.get("unlockable_egg_skills", [])],
		["RUN_END_EGG_MILESTONE", meta.get("milestone_egg_skills", {}).values()],
		["RUN_END_EGG_BOUNTY", meta.get("bounty_egg_skills", {}).values()],
	]
	var default_skills: Array = meta.get("default_egg_skills", [])
	for group in groups:
		if group[1].is_empty():
			continue
		var names = []
		for skill_name in group[1]:
			var unlocked = default_skills.has(skill_name) or SaveManager.is_egg_skill_unlocked(mon_name, skill_name)
			names.append(_skill_text(Skills.get_skill(skill_name)) if unlocked else _dim(tr(skill_name)))
		lines.append(_dim(tr(group[0])) + " " + ", ".join(PackedStringArray(names)))
	var text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.add_theme_font_size_override("normal_font_size", 13)
	text.add_theme_color_override("default_color", TEXT_COLOR)
	text.text = "\n".join(PackedStringArray(lines))
	detail_box.add_child(text)

# Skill-Name in seiner Element-Farbe mit Stärke, z. B. "Glut (28)"
func _skill_text(skill: Dictionary) -> String:
	if skill.is_empty():
		return ""
	var color = Helper.color_by_type(skill.nature).lightened(0.25)
	var power = " (%d)" % roundi(skill.value) if Skills.is_damage_skill(skill) else ""
	return "[color=#%s]%s[/color]%s" % [color.to_html(false), tr(skill.name), power]

func _dim(text: String) -> String:
	return "[color=#%s]%s[/color]" % [Color(TEXT_COLOR, 0.5).to_html(), text]

func _stat_bar(value: float) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = _bar_max
	bar.value = value
	bar.custom_minimum_size = Vector2(70, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var background = StyleBoxFlat.new()
	background.bg_color = Color(1, 1, 1, 0.1)
	var fill = StyleBoxFlat.new()
	# rot (schwach) -> grün (stark), relativ zum stärksten Wert aller Arten
	fill.bg_color = Color.from_hsv(0.33 * clampf(value / _bar_max, 0.0, 1.0), 0.6, 0.85)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

func _label(text: String, font_size: int) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	return label

func _add_stat(key: String, value: String) -> void:
	var name_label = Label.new()
	name_label.text = tr(key)
	name_label.add_theme_color_override("font_color", GOLD)
	name_label.add_theme_font_size_override("font_size", 18)
	stats_grid.add_child(name_label)
	var value_label = Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", TEXT_COLOR)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_grid.add_child(value_label)

func _show_unlocks(skill_names: Array) -> void:
	if skill_names.is_empty():
		return
	var names = skill_names.map(func(skill_name): return tr(skill_name))
	unlock_label.text = tr("MILESTONE_UNLOCKED").format({
		"mon": Helper.mon_display_name(State.starter_name),
		"skills": ", ".join(PackedStringArray(names)),
	})
	unlock_label.visible = true

func _on_new_run_pressed() -> void:
	State.reset()
	get_tree().change_scene_to_file("res://script/scenes/selection/selection.tscn")

# Tabs und Umschalter: Text wie auf den Eisenplatten, der aktive bekommt einen goldenen Rahmen
func _style_toggle(button: Button) -> void:
	button.theme = FLAT_BUTTON_THEME
	var idle = StyleBoxEmpty.new()
	idle.set_content_margin_all(4)
	RewardDialog.clear_button_styles(button, idle)
	var active = StyleBoxFlat.new()
	active.bg_color = Color(GOLD, 0.15)
	active.border_color = GOLD
	active.set_border_width_all(2)
	active.set_content_margin_all(4)
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_stylebox_override("hover_pressed", active)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, GOLD)
