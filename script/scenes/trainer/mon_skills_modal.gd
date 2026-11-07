class_name MonSkillsModal
extends PanelContainer

## Übersicht eines Monsters beim Trainer: oben alle Infos zum gewählten Skill und das Monster,
## darunter die Skills als auswählbare Karten in einer waagerechten Scrollview.

## Hülle um eine Karte: erkennt den Klick. Die Karte selbst bleibt taub, ihre Eingabe startet
## Drag & Drop; alles andere läuft weiter zur Scrollview (Mausrad, Wischen).
class SkillSlot extends MarginContainer:
	var card: Control
	var on_click: Callable
	var _press_pos := Vector2.ZERO

	func _gui_input(event: InputEvent) -> void:
		if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
			return
		# global, denn beim Wischen wandert die Karte mit dem Finger mit
		if event.pressed:
			_press_pos = event.global_position
		elif event.global_position.distance_to(_press_pos) < RewardDialog.CLICK_MAX_MOVE:
			on_click.call()

const BATTLE_CARD := preload("res://script/scenes/battle/battle_card.tscn")
const ELEMENT_CHIP := preload("res://script/ui/element_chip/element_chip.tscn")
const LABEL_THEME := preload("res://script/ui/materials/battle_labels.tres")
const CHIP_HEIGHT := 32.0
const MON_SIZE := Vector2(170, 170)
const SKILL_CARD_SIZE := Vector2(170, 200)
const DESCRIPTION_FONT_SIZE := 16
const SKILL_TITLE_FONT_SIZE := 22
const OPEN_SECONDS := 0.15
const PIXEL_FONT = preload("res://script/ui/fonts/pxelfont/PixelifySans-VariableFont_wght.ttf")
const STAT_FONT_SIZE := 17
const STAT_COLUMNS := 3
## Anzeige -> Getter am Monster
const STATS := {
	"STAT_HP": "hp",
	"STAT_ATK": "attack",
	"STAT_DEF": "defense",
	"STAT_SPA": "s_attack",
	"STAT_SPD": "s_defense",
	"STAT_SPE": "speed",
}

var _skills: Array
var _details: RichTextLabel
var _slots: Array[SkillSlot] = []

func _init(mon: Monster) -> void:
	_skills = mon._skills
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	IronPlate.frame(self, box, 16, 16)
	var top := HBoxContainer.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 16)
	box.add_child(top)
	top.add_child(_build_details())
	top.add_child(_portrait(mon))
	box.add_child(_cards())

func _ready() -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, OPEN_SECONDS)
	if not _skills.is_empty():
		_select(0)

func _build_details() -> Control:
	_details = RichTextLabel.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.bbcode_enabled = true
	_details.add_theme_font_size_override("normal_font_size", DESCRIPTION_FONT_SIZE)
	return _details

## Karte hervorheben und ihre Infos anzeigen, es ist immer genau ein Skill gewählt
func _select(index: int) -> void:
	for i in _slots.size():
		_slots[i].card.set_selected(i == index)
	_details.text = _skill_text(_skills[index])

func _skill_text(skill: Dictionary) -> String:
	var color := SkillCardPaper.readable_color(Helper.color_by_type(skill.nature))
	var title := "[font_size=%d][color=#%s]%s[/color][/font_size]" % [SKILL_TITLE_FONT_SIZE, color.to_html(false), tr(skill.name)]
	var damage_type := tr("EGG_CATEGORY_PHYSICAL") if Skills.is_physical(skill) else tr("EGG_CATEGORY_MAGIC")
	var element := tr(ColorMap.get_combo(skill.nature).label)
	return "\n".join(PackedStringArray([
		title,
		"%s · %s" % [_kind_text(skill), damage_type],
		"",
		Helper.skill_description(skill),
		"",
		tr("TRAINER_ELEMENT").format({"element": element}),
		"%s: %s" % [tr("SKILL_HEADER_POWER"), Helper.format_number(skill.value)],
		"%s: %s" % [tr("SKILL_HEADER_COST"), skill.cost],
		"%s: %s" % [tr("SKILL_INFO_COOLDOWN"), skill.cooldown],
	]))

## Aktiv (Schaden und Schilde werden ausgespielt), Buff oder Passiv
func _kind_text(skill: Dictionary) -> String:
	if Skills.is_passive(skill):
		return tr("EGG_CATEGORY_PASSIVE")
	if skill.get("effect", "") == "buff":
		return tr("EGG_CATEGORY_BUFF")
	return tr("SKILL_KIND_ACTIVE")

func _portrait(mon: Monster) -> Control:
	var box := VBoxContainer.new()
	var icon := RewardDialog.mon_icon(mon)
	icon.custom_minimum_size = MON_SIZE
	box.add_child(icon)
	var label := Label.new()
	label.theme = LABEL_THEME
	label.text = Helper.mon_display_name(mon._name)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var chip := ELEMENT_CHIP.instantiate()
	chip.custom_minimum_size.y = CHIP_HEIGHT
	chip._init_color(mon)
	box.add_child(chip)
	box.add_child(_stats(mon))
	return box

## Werte wie im Shop: Pixelschrift auf einer Eisenplatte
func _stats(mon: Monster) -> Control:
	var plate := PanelContainer.new()
	var grid := GridContainer.new()
	grid.columns = STAT_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 0)
	IronPlate.frame(plate, grid, 10, 7)
	for key: String in STATS:
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_override("font", PIXEL_FONT)
		label.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
		label.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
		label.text = "%s %d" % [tr(key), roundi(mon.call(STATS[key]))]
		grid.add_child(label)
	return plate

func _cards() -> Control:
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	scroll.add_child(row)
	for i in _skills.size():
		var card := BATTLE_CARD.instantiate()
		card.skill = _skills[i]
		card.custom_minimum_size = SKILL_CARD_SIZE
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slot := SkillSlot.new()
		slot.card = card
		slot.on_click = _select.bind(i)
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slot.add_child(card)
		row.add_child(slot)
		_slots.append(slot)
	return scroll
