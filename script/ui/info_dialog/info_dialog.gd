class_name InfoDialog
extends Control

## Gemeinsamer Rahmen der Info-Dialoge (Biom, Element): abgedunkelter Hintergrund, mittiges Panel auf einer
## Eisenplatte mit farbigem Rand, Schließen-Button. Liegt auf einer eigenen Ebene über allem anderen;
## wird ein Dialog aus einem anderen heraus geöffnet, liegt er eine Ebene darüber.
## Unterklassen füllen _build(content) und geben über _accent() die Randfarbe an.

const LAYER := 50
const SECTION_FONT_SIZE := 22
const ROW_FONT_SIZE := 16
const NOTE_FONT_SIZE := 15
const NOTE_WIDTH := 640.0
const STRONG_COLOR := Color(0.55, 0.9, 0.45)
const WEAK_COLOR := SkillDetailPopup.MISSING_COLOR
const NEUTRAL_COLOR := Color(0.62, 0.62, 0.58)

var _panel: PanelContainer

## Hängt dialog auf einer eigenen Ebene an host und liefert ihn zurück
static func present(host: Node, dialog: InfoDialog) -> InfoDialog:
	var layer := CanvasLayer.new()
	layer.layer = LAYER
	var parent := host.get_parent()
	while parent:
		if parent is CanvasLayer:
			layer.layer = maxi(LAYER, parent.layer + 1)
			break
		parent = parent.get_parent()
	layer.add_child(dialog)
	host.add_child(layer)
	return dialog

func _init() -> void:
	theme = RewardDialog.FONT_THEME
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP

func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	# Klick neben das Panel schließt
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	center.add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	IronPlate.frame(_panel, content, 28, 22).set_rim(_accent())
	_build(content)

	var close_button := RewardDialog.plate_button(tr("BIOME_INFO_CLOSE"))
	close_button.size_flags_horizontal = SIZE_SHRINK_CENTER
	close_button.focus_mode = FOCUS_NONE
	close_button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	close_button.pressed.connect(close)
	content.add_child(close_button)
	_animate_in.call_deferred()

func _accent() -> Color:
	return IronPlate.RIM

func _build(_content: VBoxContainer) -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	# die eigene Ebene geht mit
	get_parent().queue_free()

## Panel federt aus der Mitte auf
func _animate_in() -> void:
	_panel.pivot_offset = _panel.size / 2
	_panel.scale = Vector2(0.9, 0.9)
	_panel.modulate.a = 0
	var tween := create_tween().set_parallel()
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.2)

func _title(text: String, color: Color) -> Label:
	var title := Label.new()
	title.theme = RewardDialog.LABEL_THEME
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", color)
	return title

func _section(text: String) -> Label:
	var label := _text(text, SkillDetailPopup.GOLD, SECTION_FONT_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label

func _note(text: String, color: Color) -> Label:
	var label := _text(text, color, NOTE_FONT_SIZE)
	label.custom_minimum_size.x = NOTE_WIDTH
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate.a = 0.8
	return label

func _text(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

## Zeile in box: farbiger Strich, Beschriftung und daneben die Fläche für die Einträge (bricht bei Platzmangel um)
func _captioned_row(box: Container, caption: String, color: Color, entries_width: float) -> HFlowContainer:
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size.y = 32
	var marker := ColorRect.new()
	marker.color = color
	marker.custom_minimum_size = Vector2(6, 0)
	row.add_child(marker)
	var label := _text(caption, color, ROW_FONT_SIZE)
	label.custom_minimum_size.x = 150
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(label)
	var flow := HFlowContainer.new()
	flow.custom_minimum_size.x = entries_width
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 6)
	row.add_child(flow)
	return flow

func _none_label() -> Label:
	var none := _text(tr("BIOME_INFO_NONE"), NEUTRAL_COLOR, ROW_FONT_SIZE)
	none.custom_minimum_size.y = 32
	return none

## Element-Chip, optional mit kleinem Zusatztext dahinter
func _chip_entry(element: int, note := "", note_color := Color.WHITE) -> Control:
	var item := HBoxContainer.new()
	item.custom_minimum_size.y = 32
	item.add_theme_constant_override("separation", 4)
	RewardDialog.add_element_chip(item, element)
	if note != "":
		item.add_child(_text(note, note_color, NOTE_FONT_SIZE))
	return item
