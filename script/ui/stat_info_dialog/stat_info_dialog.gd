class_name StatInfoDialog
extends InfoDialog

## Was die Werte bedeuten (KP, ANG, VER, SAN, SVE, INI, GES) und worauf man beim Spielen der Karten achten sollte.
## Öffnet sich beim Klick auf eine Werte-Beschriftung (StatsGrid), der angeklickte Wert ist hervorgehoben.

const ORDER := ["hp", "atk", "def", "s_atk", "s_def", "speed", "bst"]
## Übersetzungs-Präfix pro Wert: _NAME und _DESC hängen dran
const KEYS := {
	"hp": "STAT_INFO_HP", "atk": "STAT_INFO_ATK", "def": "STAT_INFO_DEF", "s_atk": "STAT_INFO_SPA",
	"s_def": "STAT_INFO_SPD", "speed": "STAT_INFO_SPE", "bst": "STAT_INFO_BST",
}
const TIPS := ["STAT_INFO_TIP_TYPE", "STAT_INFO_TIP_SHIELD", "STAT_INFO_TIP_ELEMENT", "STAT_INFO_TIP_SPEED", "STAT_INFO_TIP_HIDDEN"]
const ICON_SIZE := Vector2(26, 26)
const NAME_WIDTH := 230.0
const DESC_WIDTH := 520.0
## passt samt Titel und Schließen-Button in die 720 px hohe Ansicht
const LIST_HEIGHT := 470.0
const HIGHLIGHT := Color(1, 1, 1, 0.07)

var _selected: String

static func open(host: Node, stat_key: String) -> InfoDialog:
	return InfoDialog.present(host, StatInfoDialog.new(stat_key))

func _init(stat_key: String) -> void:
	super()
	_selected = stat_key

func _accent() -> Color:
	return SkillDetailPopup.GOLD

func _build(content: VBoxContainer) -> void:
	content.add_child(_title(tr("STAT_INFO_TITLE"), SkillDetailPopup.GOLD))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(NAME_WIDTH + DESC_WIDTH + 60, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	DragScroll.attach(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)

	var selected_row: Control
	for key in ORDER:
		var row := _stat_row(key)
		list.add_child(row)
		if key == _selected:
			selected_row = row

	list.add_child(_section(tr("STAT_INFO_TIPS_TITLE")))
	for tip in TIPS:
		var label := _text("•  " + tr(tip), IronPlate.TEXT_COLOR, NOTE_FONT_SIZE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = NAME_WIDTH + DESC_WIDTH
		list.add_child(label)
	if selected_row:
		(func(): scroll.ensure_control_visible(selected_row)).call_deferred()

## Symbol, voller Name und Kürzel, daneben was der Wert bewirkt. Der angeklickte Wert ist hinterlegt.
func _stat_row(key: String) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = HIGHLIGHT if key == _selected else Color(0, 0, 0, 0)
	style.border_color = SkillDetailPopup.GOLD
	style.border_width_left = 3 if key == _selected else 0
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = StatsGrid.ICONS[key]
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = ICON_SIZE
	icon.size_flags_vertical = SIZE_SHRINK_BEGIN
	icon.modulate.a = StatsGrid.ICON_ALPHA
	row.add_child(icon)
	var name_label := _text(tr(KEYS[key] + "_NAME"), SkillDetailPopup.GOLD, ROW_FONT_SIZE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_label.custom_minimum_size.x = NAME_WIDTH
	row.add_child(name_label)
	var desc := _text(tr(KEYS[key] + "_DESC"), IronPlate.TEXT_COLOR, NOTE_FONT_SIZE)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = DESC_WIDTH
	row.add_child(desc)
	return panel
