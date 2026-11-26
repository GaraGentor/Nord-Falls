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
const MON_SIZE := Vector2(160, 160)
## Kartengröße; nur falls das Fenster doch zu niedrig ist, werden die Karten flacher (_fit_cards)
const SKILL_CARD_SIZE := Vector2(170, 200)
const MIN_CARD_HEIGHT := 130.0
const FRAME_PADDING := 16
const BOX_SEPARATION := 12
const DESCRIPTION_FONT_SIZE := SkillCardFace.TEXT_SIZE
const SKILL_TITLE_FONT_SIZE := SkillCardFace.TITLE_SIZE
const OPEN_SECONDS := 0.15
const PIXEL_FONT = preload("res://script/ui/fonts/m5x7/m5x7.ttf")
const STAT_FONT_SIZE := 24
const STAT_COLUMNS := 3
## Anzeige -> Getter am Monster
const STATS := {
	"STAT_HP": "hp",
	"STAT_ATK": "attack",
	"STAT_SPA": "s_attack",
	"STAT_DEF": "defense",
	"STAT_SPE": "speed",
	"STAT_BST": "",
}
## Anzeige -> Stat-Key (StatsGrid.ICONS)
const STAT_KEYS := {
	"STAT_HP": "hp", "STAT_ATK": "atk", "STAT_SPA": "s_atk", "STAT_DEF": "def", "STAT_SPE": "speed", "STAT_BST": "bst",
}

var _mon: Monster
var _skills: Array
var _details: RichTextLabel
var _details_scroll: AutoScrollContainer
var _slots: Array[SkillSlot] = []
var _top: HBoxContainer
var _card_scroll: ScrollContainer

func _init(mon: Monster) -> void:
	_mon = mon
	_skills = mon._skills
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", BOX_SEPARATION)
	IronPlate.frame(self, box, FRAME_PADDING, FRAME_PADDING)
	_top = HBoxContainer.new()
	_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_top.add_theme_constant_override("separation", 16)
	box.add_child(_top)
	_top.add_child(_build_details())
	_top.add_child(_portrait(mon))
	box.add_child(_cards())

func _enter_tree() -> void:
	var holder := get_parent_control()
	if holder and not holder.resized.is_connected(_fit_cards):
		holder.resized.connect(_fit_cards)
	_fit_cards.call_deferred()

func _exit_tree() -> void:
	var holder := get_parent_control()
	if holder and holder.resized.is_connected(_fit_cards):
		holder.resized.disconnect(_fit_cards)

func _ready() -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, OPEN_SECONDS)
	if not _skills.is_empty():
		_select(0)

## Infos zum Skill: zu lange Texte scrollen von selbst, gedrückt halten hält sie an,
## per Mausrad / Leiste lässt sich auch selbst scrollen
func _build_details() -> Control:
	_details_scroll = AutoScrollContainer.new()
	_details_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details = RichTextLabel.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.bbcode_enabled = true
	_details.fit_content = true
	_details.scroll_active = false
	_details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_details.add_theme_font_size_override("normal_font_size", DESCRIPTION_FONT_SIZE)
	_details_scroll.add_child(_details)
	return _details_scroll

## Karte hervorheben und ihre Infos anzeigen, es ist immer genau ein Skill gewählt
func _select(index: int) -> void:
	for i in _slots.size():
		_slots[i].card.set_selected(i == index)
	_details.text = _skill_text(_skills[index])
	_details_scroll.restart()

func _skill_text(skill: Dictionary) -> String:
	var color := SkillCardPaper.readable_color(Helper.color_by_type(skill.nature))
	var title := "[font_size=%d][color=#%s]%s[/color][/font_size]" % [SKILL_TITLE_FONT_SIZE, color.to_html(false), tr(skill.name)]
	var damage_type := tr("EGG_CATEGORY_PHYSICAL") if Skills.is_physical(skill) else tr("EGG_CATEGORY_MAGIC")
	var element := tr(ColorMap.get_combo(skill.nature).label)
	return "\n".join(PackedStringArray([
		title,
		"%s · %s" % [_kind_text(skill), damage_type],
		"",
		Helper.skill_description(skill, true, _mon),
		"",
		tr("TRAINER_ELEMENT").format({"element": element}),
		"%s: %s" % [tr("SKILL_HEADER_POWER"), Skills.power_text(skill, _mon)],
		"%s: %s" % [tr("SKILL_HEADER_COST"), skill.cost],
		"%s: %s" % [tr("SKILL_INFO_COOLDOWN"), skill.cooldown],
	]))

## Aktiv (Schaden und Schilde werden ausgespielt), Buff oder Passiv
func _kind_text(skill: Dictionary) -> String:
	if Skills.is_passive(skill):
		return tr("EGG_CATEGORY_PASSIVE")
	if Skills.is_buff_skill(skill):
		return tr("EGG_CATEGORY_BUFF")
	if Skills.is_debuff_skill(skill):
		return tr("SKILL_KIND_DEBUFF")
	return tr("SKILL_KIND_ACTIVE")

func _portrait(mon: Monster) -> Control:
	var box := VBoxContainer.new()
	var icon := RewardDialog.mon_icon(mon)
	icon.custom_minimum_size = MON_SIZE
	# Züge des Monsters als Rune unten links am Bild
	box.add_child(MovesBadge.attach_to_portrait(icon, mon))
	var label := Label.new()
	label.theme = LABEL_THEME
	label.text = Helper.mon_display_name(mon._name)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var chip := ELEMENT_CHIP.instantiate()
	chip.custom_minimum_size.y = CHIP_HEIGHT
	# der Chip würde sonst den restlichen Platz einnehmen, alles bleibt oben bündig untereinander
	chip.size_flags_vertical = Control.SIZE_FILL
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
		var value: float = mon._best_points if key == "STAT_BST" else mon.call(STATS[key])
		label.text = "%s %d" % [tr(key), roundi(value)]
		# Symbol davor wie in allen Werte-Tabellen, ein Klick erklärt die Werte
		var cell := StatsGrid.name_cell(self, STAT_KEYS[key], label, false)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
	return plate

func _cards() -> Control:
	var scroll := ScrollContainer.new()
	_card_scroll = scroll
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Platz für die Rand-Effekte der Karten, sonst schneidet die Scrollview sie ab
	var margin := SkillCardPaper.flame_margin()
	scroll.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SkillCardPaper.FLAME_GAP_X)
	margin.add_child(row)
	for i in _skills.size():
		var card := BATTLE_CARD.instantiate()
		card.mon = _mon
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

## Karten so hoch wie der Platz unter Infos und Monster erlaubt (samt Rand-Effekten), höchstens SKILL_CARD_SIZE
func _fit_cards() -> void:
	var pad := SkillCardPaper.FLAME_PAD
	# Höhe des Fensters, nicht die eigene: die wächst mit, solange die Karten zu hoch sind
	var free := get_parent_area_size().y - 2 * FRAME_PADDING - BOX_SEPARATION - _top.get_combined_minimum_size().y - pad.y - pad.w \
			- _card_scroll.get_h_scroll_bar().get_combined_minimum_size().y
	var height := clampf(free, MIN_CARD_HEIGHT, SKILL_CARD_SIZE.y)
	var card_size := Vector2(SKILL_CARD_SIZE.x * height / SKILL_CARD_SIZE.y, height).round()
	for slot in _slots:
		if slot.card.custom_minimum_size != card_size:
			slot.card.custom_minimum_size = card_size
