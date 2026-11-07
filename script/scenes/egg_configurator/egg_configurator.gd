extends Control

## Konfigurator nach "Reise beginnen": wähle 3 Ei-Attacken, die dein Monster in den Run mitnimmt.
## Zur Wahl stehen die Standard-Ei-Attacken der Art und alle freigeschalteten.
## Die gewählten stehen in der festen Box über der scrollbaren Auswahl, ein Klick lässt eine
## Attacke zwischen beiden hin- und herfliegen.

const SKILLS_TO_PICK := 3
const GOLD := SkillDetailPopup.GOLD
const TEXT_COLOR := IronPlate.TEXT_COLOR
const BG_TOP := Color(0.560784, 0.301961, 0.85098, 1)
const MISSING_COLOR := Color(1, 0.45, 0.45)
const MAP_BACKGROUND := preload("res://script/scenes/world_map/map_background.gdshader")
const BATTLE_CARD := preload("res://script/scenes/battle/battle_card.tscn")
const GO_ICON := preload("res://assets/ui/icons/check_go.svg")
const GRID_SEPARATION := 16
const EMPTY_SLOT_COLOR := Color(0.2, 0.2, 0.22, 0.85)
const EMPTY_SLOT_BORDER := Color(0.36, 0.36, 0.38)
const FLY_SECONDS := 0.35

var _mon: Monster
## Skill-Name pro Platz in der Box, "" = leer
var _slot_skills: Array[String] = []
var _slots: Array[Control] = []
var _available: Array = []
## Skill-Name -> Kachel, auch während sie fliegt
var _cards := {}
## Skill-Name -> Knoten im Grid (Kachel oder Platzhalter für eine zurückfliegende Kachel)
var _grid_nodes := {}
var _flying := {}
var _grid: GridContainer
var _scroll: ScrollContainer
## oberste Ebene, auf der die Kacheln fliegen
var _fly_layer: Control
var _counter_label: Label
var _go_button: Button
## Spielkarte der zuletzt angeklickten Attacke, wie sie im Kampf aussieht
var _detail_card: Control
## Unter der Karte: wie die verfügbare Attacke freigeschaltet wurde
var _detail_source: Label
## Hinweis unter der Karte: wie man sie freischaltet oder welche Elemente fehlen
var _detail_note: Label

func _ready() -> void:
	_mon = State.mons[0]
	_slot_skills.resize(SKILLS_TO_PICK)
	_slot_skills.fill("")
	# Vorauswahl: die beim Ei gewürfelten Attacken
	var filled := 0
	for skill in _mon._skills:
		if filled < SKILLS_TO_PICK and not _slot_skills.has(skill.name):
			_slot_skills[filled] = skill.name
			filled += 1
	_build()
	_refresh()

func _build() -> void:
	var background := ColorRect.new()
	var bg_material := ShaderMaterial.new()
	bg_material.shader = MAP_BACKGROUND
	bg_material.set_shader_parameter("bottom_color", Color.BLACK)
	bg_material.set_shader_parameter("top_color", BG_TOP)
	bg_material.set_shader_parameter("wave_amp", 0.115)
	bg_material.set_shader_parameter("wave_size", 1.0)
	bg_material.set_shader_parameter("wave_time_mul", 0.933)
	bg_material.set_shader_parameter("total_phases", 8)
	# Pixel-Look wie im Laden
	bg_material.set_shader_parameter("living_pixels", true)
	bg_material.set_shader_parameter("pixel_size", 4.0)
	bg_material.set_shader_parameter("amplitude", 0.0)
	bg_material.set_shader_parameter("loop_seconds", 19.365)
	bg_material.set_shader_parameter("particle_min_size", 1.0)
	bg_material.set_shader_parameter("particle_max_size", 1.2)
	bg_material.set_shader_parameter("flicker", 0.15)
	bg_material.set_shader_parameter("color_levels", 8.0)
	bg_material.set_shader_parameter("dither_strength", 1.0)
	bg_material.set_shader_parameter("dither_scale", 2.0)
	bg_material.set_shader_parameter("dither_fps", 10.0)
	background.material = bg_material
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 40)
	margin.add_child(content)

	# links: oben im Rahmen das gewählte Monster mit Typ und Werten, darunter frei die Karte der angeklickten Attacke
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", GRID_SEPARATION)
	content.add_child(left)
	var mon_box := VBoxContainer.new()
	mon_box.custom_minimum_size = Vector2(300, 0)
	mon_box.add_theme_constant_override("separation", 4)
	var mon_panel := PanelContainer.new()
	IronPlate.frame(mon_panel, mon_box, 16, 16)
	left.add_child(mon_panel)
	var texture := TextureRect.new()
	Monmap.show_on(texture, _mon._name, Monmap.MEDIUM)
	texture.material = Monmap.LIVING_MATERIAL
	texture.custom_minimum_size = Vector2(120, 120)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mon_box.add_child(texture)
	mon_box.add_child(_label(Helper.mon_display_name(_mon._name), 26, SkillCardPaper.readable_color(Helper.color_by_mon(_mon))))
	var chip_row := HBoxContainer.new()
	chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip_row.custom_minimum_size.y = 32
	RewardDialog.add_element_chip(chip_row, _mon._type)
	mon_box.add_child(chip_row)
	mon_box.add_child(StatsGrid.stacked_for(_mon))

	_detail_card = BATTLE_CARD.instantiate()
	_detail_card.custom_minimum_size = Vector2(220, 200)
	_detail_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_detail_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_card.visible = false
	left.add_child(_detail_card)
	_detail_source = _label("", 14, GOLD)
	_detail_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_source.custom_minimum_size = Vector2(300, 0)
	_detail_source.visible = false
	left.add_child(_detail_source)
	_detail_note = _label(tr("CONFIGURATOR_PICK_HINT"), 14, TEXT_COLOR)
	_detail_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_note.custom_minimum_size = Vector2(300, 0)
	left.add_child(_detail_note)

	# rechts: oben Zähler und Aufbruch, darunter die feste Box, darunter die scrollbare Auswahl
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", GRID_SEPARATION)
	content.add_child(right)
	right.add_child(_build_top_row())
	right.add_child(_build_slot_box())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = SKILLS_TO_PICK
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", GRID_SEPARATION)
	_grid.add_theme_constant_override("v_separation", GRID_SEPARATION)
	_scroll.add_child(_grid)

	_available = Skills.get_available_egg_skills(_mon._name)
	for skill_name in _available:
		var card := SkillTile.create(Skills.get_skill(skill_name), _mon)
		card.pressed.connect(_on_card_pressed.bind(skill_name))
		_cards[skill_name] = card
		var slot_index := _slot_skills.find(skill_name)
		if slot_index >= 0:
			_slots[slot_index].add_child(card)
		else:
			_grid.add_child(card)
			_grid_nodes[skill_name] = card
	for skill_name in Skills.get_locked_egg_skills(_mon._name):
		_add_locked_card(Skills.get_skill(skill_name), "CONFIGURATOR_LOCKED", "EGG_SKILL_HINT")
	for milestone in Skills.get_locked_milestones(_mon._name):
		_add_locked_card(Skills.get_skill(milestone.skill), "CONFIGURATOR_LOCKED_MILESTONE", milestone.hint)
	for bounty in Skills.get_locked_bounties(_mon._name):
		_add_locked_card(Skills.get_skill(bounty.skill), "CONFIGURATOR_LOCKED_BOUNTY", bounty.hint)

	_fly_layer = Control.new()
	_fly_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fly_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fly_layer)

func _build_top_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", GRID_SEPARATION)
	_counter_label = _label("", 22, TEXT_COLOR)
	var counter_panel := PanelContainer.new()
	counter_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	IronPlate.frame(counter_panel, _counter_label, 16, 10)
	row.add_child(counter_panel)
	_go_button = RewardDialog.icon_button(GO_ICON)
	_go_button.tooltip_text = tr("CONFIGURATOR_GO")
	_go_button.focus_mode = Control.FOCUS_NONE
	_go_button.pressed.connect(_on_go_pressed)
	row.add_child(_go_button)
	return row

## Box mit den gewählten Attacken, bleibt beim Scrollen der Auswahl stehen
func _build_slot_box() -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GRID_SEPARATION)
	IronPlate.frame(panel, row, 12, 12)
	var empty := StyleBoxFlat.new()
	empty.bg_color = EMPTY_SLOT_COLOR
	empty.border_color = EMPTY_SLOT_BORDER
	empty.set_border_width_all(2)
	for i in SKILLS_TO_PICK:
		var slot := PanelContainer.new()
		slot.custom_minimum_size.y = SkillTile.HEIGHT
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.add_theme_stylebox_override("panel", empty)
		row.add_child(slot)
		_slots.append(slot)
	return panel

func _add_locked_card(skill: Dictionary, locked_label: String, hint: String) -> void:
	var card := SkillTile.create(skill, _mon, locked_label)
	card.pressed.connect(_show_detail.bind(skill, tr(locked_label) + "\n" + tr(hint), GOLD, true))
	_grid.add_child(card)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _show_detail(skill: Dictionary, note: String, note_color: Color, locked: bool) -> void:
	_detail_card.skill = skill
	_detail_card.modulate = Color(0.6, 0.6, 0.6) if locked else Color.WHITE
	_detail_card.visible = true
	var source := [] if locked else Skills.get_egg_skill_source(_mon._name, skill.name)
	_detail_source.visible = not source.is_empty()
	if _detail_source.visible:
		_detail_source.text = tr(source[0]) + "\n" + tr(source[1])
	_detail_note.text = note
	_detail_note.add_theme_color_override("font_color", note_color)

func _on_card_pressed(skill_name: String) -> void:
	var skill := Skills.get_skill(skill_name)
	_show_detail(skill, Skills.missing_elements_text(_mon, skill), MISSING_COLOR, false)
	if _flying.has(skill_name):
		return
	var slot_index := _slot_skills.find(skill_name)
	if slot_index >= 0:
		_slot_skills[slot_index] = ""
		_fly_to_grid(skill_name)
	else:
		var free_slot := _slot_skills.find("")
		if free_slot < 0:
			return
		_slot_skills[free_slot] = skill_name
		_fly_to_slot(skill_name, free_slot)
	_refresh()

## Aus der Auswahl nach oben auf den grauen Platz. Die Auswahl rückt sofort zusammen.
func _fly_to_slot(skill_name: String, slot_index: int) -> void:
	_grid_nodes.erase(skill_name)
	var slot := _slots[slot_index]
	_fly(skill_name, slot.get_global_rect(), func(card: Control): slot.add_child(card))

## Aus der Box zurück an den Platz in der Auswahl, den die Reihenfolge vorgibt.
## Erst hält ein Platzhalter die Stelle frei, seine Position steht nach dem nächsten Layout fest.
func _fly_to_grid(skill_name: String) -> void:
	var placeholder := Control.new()
	placeholder.custom_minimum_size.y = SkillTile.HEIGHT
	placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var index := _grid_index(skill_name)
	_grid.add_child(placeholder)
	_grid.move_child(placeholder, index)
	_grid_nodes[skill_name] = placeholder
	_flying[skill_name] = true
	await get_tree().process_frame
	await get_tree().process_frame
	var target := placeholder.get_global_rect()
	# liegt der Platz außerhalb der Scroll-Ansicht, fliegt die Kachel bis an deren Rand
	var view := _scroll.get_global_rect()
	target.position.y = clampf(target.position.y, view.position.y, maxf(view.end.y - target.size.y, view.position.y))
	_fly(skill_name, target, func(card: Control):
		_grid.add_child(card)
		_grid.move_child(card, placeholder.get_index())
		_grid_nodes[skill_name] = card
		_grid.remove_child(placeholder)
		placeholder.queue_free())

## Stelle in der Auswahl: hinter den noch dort liegenden Attacken, die in der Reihenfolge davor stehen
func _grid_index(skill_name: String) -> int:
	var index := 0
	for other in _available:
		if other == skill_name:
			break
		if _grid_nodes.has(other):
			index += 1
	return index

## Die Kachel löst sich aus ihrem Container und fliegt auf der obersten Ebene zum Ziel
func _fly(skill_name: String, target: Rect2, on_arrived: Callable) -> void:
	var card: Control = _cards[skill_name]
	_flying[skill_name] = true
	var from := card.get_global_rect()
	card.get_parent().remove_child(card)
	_fly_layer.add_child(card)
	card.global_position = from.position
	card.size = from.size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(card, "global_position", target.position, FLY_SECONDS)
	tween.tween_property(card, "size", target.size, FLY_SECONDS)
	tween.chain().tween_callback(func():
		_fly_layer.remove_child(card)
		on_arrived.call(card)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		_flying.erase(skill_name))

func _selected() -> Array[String]:
	return _slot_skills.filter(func(skill_name): return skill_name != "")

func _refresh() -> void:
	var selected := _selected()
	# mindestens eine Attacke muss mit dem Start-Element spielbar sein
	var has_usable = selected.any(func(skill_name): return Skills.can_use_name(_mon, skill_name))
	_counter_label.text = tr("CONFIGURATOR_COUNTER").format({"count": selected.size(), "max": SKILLS_TO_PICK})
	if selected.size() == SKILLS_TO_PICK and not has_usable:
		_counter_label.text = tr("CONFIGURATOR_NEED_USABLE")
	_go_button.disabled = selected.size() != SKILLS_TO_PICK or not has_usable

func _on_go_pressed() -> void:
	_mon._skills = []
	for skill_name in _selected():
		var skill = Skills.get_skill(skill_name)
		skill.scouted = true
		_mon._skills.append(skill)
	get_tree().change_scene_to_file("res://script/scenes/world_map/world_map.tscn")
