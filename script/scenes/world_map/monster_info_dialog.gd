class_name MonsterInfoDialog
extends Control

## Details eines eigenen Monsters über der ganzen Kartenfläche (der Header der Karte bleibt sichtbar):
## links Bild, Name, Typ und die Karte der gewählten Attacke, rechts Werte, gesammelte Edelsteine
## und die Attacken als Kacheln wie in der Ei-Attacken-Auswahl.

const GemField = preload("res://script/scenes/gems/gems.gd")
const BATTLE_CARD := preload("res://script/scenes/battle/battle_card.tscn")
const LEFT_WIDTH := 300.0
const PORTRAIT_SIZE := Vector2(0, 150)
const SKILL_COLUMNS := 3
const BACK_ICON := preload("res://assets/ui/icons/icon_back.svg")

var _mon: Monster
var _tiles: Array[Button] = []
var _detail_card: Control

func _init(mon: Monster) -> void:
	_mon = mon
	theme = RewardDialog.FONT_THEME
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	# Klicks gehen nicht auf die Karte darunter durch
	mouse_filter = MOUSE_FILTER_STOP

func _ready() -> void:
	offset_top = RewardDialog.MAP_HEADER_HEIGHT
	var panel := PanelContainer.new()
	RewardDialog.fit_to_map_area(panel)
	add_child(panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	IronPlate.frame(panel, columns, 24, 20)
	columns.add_child(_left_side())
	columns.add_child(_right_side())
	if not _mon._skills.is_empty():
		_select_skill(0)

func _left_side() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = LEFT_WIDTH
	box.add_theme_constant_override("separation", 6)
	var portrait := RewardDialog.mon_icon(_mon)
	portrait.custom_minimum_size = PORTRAIT_SIZE
	box.add_child(portrait)
	var name_label := Label.new()
	name_label.text = Helper.mon_battle_name(_mon)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", SkillCardPaper.readable_color(Helper.color_by_mon(_mon)))
	box.add_child(name_label)
	var chip_row := HBoxContainer.new()
	chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip_row.custom_minimum_size.y = 32
	RewardDialog.add_element_chip(chip_row, _mon._type)
	box.add_child(chip_row)
	_detail_card = BATTLE_CARD.instantiate()
	_detail_card.custom_minimum_size = Vector2(220, 200)
	_detail_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail_card.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	_detail_card.mouse_filter = MOUSE_FILTER_IGNORE
	_detail_card.visible = false
	box.add_child(_detail_card)
	return box

func _right_side() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	box.add_child(top)
	var facts := VBoxContainer.new()
	facts.size_flags_horizontal = SIZE_EXPAND_FILL
	facts.alignment = BoxContainer.ALIGNMENT_CENTER
	facts.add_theme_constant_override("separation", 10)
	top.add_child(facts)
	facts.add_child(StatsGrid.stacked_for(_mon, 18))
	facts.add_child(GemField.gem_counts(_mon))
	var back := RewardDialog.icon_button(BACK_ICON)
	back.tooltip_text = tr("MONSTER_INFO_BACK")
	back.size_flags_vertical = SIZE_SHRINK_BEGIN
	back.pressed.connect(queue_free)
	top.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = SKILL_COLUMNS
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for i in _mon._skills.size():
		var tile := SkillTile.create(_mon._skills[i], _mon)
		tile.toggle_mode = true
		tile.pressed.connect(_select_skill.bind(i))
		grid.add_child(tile)
		_tiles.append(tile)
	return box

## Es ist immer genau eine Attacke gewählt, links steht ihre Karte
func _select_skill(index: int) -> void:
	for i in _tiles.size():
		_tiles[i].set_pressed_no_signal(i == index)
	_detail_card.skill = _mon._skills[index]
	_detail_card.visible = true
