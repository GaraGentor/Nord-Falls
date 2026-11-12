class_name MonsterInfoDialog
extends Control

## Details eines eigenen Monsters über der ganzen Kartenfläche (der Header der Karte bleibt sichtbar):
## links Bild, Name und Typ, rechts Werte, gesammelte Edelsteine und darunter alle Attacken
## als große Karten wie im Kampf in einer waagerechten Scrollview (reine Anzeige, ohne Klick).

const BATTLE_CARD := preload("res://script/scenes/battle/battle_card.tscn")
const LEFT_WIDTH := 300.0
const PORTRAIT_SIZE := Vector2(0, 150)
const SKILL_CARD_SIZE := Vector2(220, 260)
const BACK_ICON := preload("res://assets/ui/icons/icon_back.svg")

var _mon: Monster

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
	# Trophäen stehen direkt unter ihrem Wert, ihr Anteil grün hinter der Zahl (wie im Trophäen-Feld)
	facts.add_child(StatsGrid.stacked_for(_mon, 18, true))
	var back := RewardDialog.icon_button(BACK_ICON)
	back.tooltip_text = tr("MONSTER_INFO_BACK")
	back.size_flags_vertical = SIZE_SHRINK_BEGIN
	back.pressed.connect(queue_free)
	top.add_child(back)
	box.add_child(_skill_cards())
	return box

## Alle Attacken als Kampfkarten nebeneinander. Die Karten nehmen keine Eingabe an,
## so landen Mausrad und Wischen direkt bei der Scrollview und ein Klick bewirkt nichts.
func _skill_cards() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	scroll.add_child(row)
	for skill in _mon._skills:
		var card := BATTLE_CARD.instantiate()
		card.mon = _mon
		card.skill = skill
		card.custom_minimum_size = SKILL_CARD_SIZE
		card.size_flags_vertical = SIZE_SHRINK_BEGIN
		card.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(card)
	return scroll
