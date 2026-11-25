class_name InfoDialog
extends Control

## Gemeinsamer Rahmen der Info-Dialoge (Biom, Element): abgedunkelter Hintergrund, mittiges Panel auf einer
## Eisenplatte mit farbigem Rand, Schließen-Button. Liegt auf einer eigenen Ebene über allem anderen;
## wird ein Dialog aus einem anderen heraus geöffnet, liegt er eine Ebene darüber.
## Unterklassen füllen _build(content) und geben über _accent() die Randfarbe an.

const LAYER := 50
const SECTION_FONT_SIZE := 32
const ROW_FONT_SIZE := 24
const NOTE_FONT_SIZE := 24
const NOTE_WIDTH := 640.0
const STRONG_COLOR := Color(0.55, 0.9, 0.45)
const WEAK_COLOR := SkillDetailPopup.MISSING_COLOR
const NEUTRAL_COLOR := Color(0.62, 0.62, 0.58)
## Abstand des Dialogs zum oberen und unteren Fensterrand zusammen, wenn die Liste scrollt (_scroll_list)
const SCROLL_SCREEN_MARGIN := 40.0

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

const GROUP := "info_dialog"

## Liegt gerade ein Info-Dialog offen? Dann dürfen Klicks darin nichts darunter schließen (Trainer, Laden)
static func any_open(tree: SceneTree) -> bool:
	return tree.get_nodes_in_group(GROUP).any(func(node): return not node.is_queued_for_deletion())

func _init() -> void:
	add_to_group(GROUP)
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
	if _has_close_button():
		content.add_child(_close_button())
	_animate_in.call_deferred()

## Fragen (ChoiceDialog) bringen eigene Antwort-Knöpfe mit
func _has_close_button() -> bool:
	return true

func _close_button() -> Button:
	var close_button := RewardDialog.plate_button(tr("BIOME_INFO_CLOSE"))
	close_button.size_flags_horizontal = SIZE_SHRINK_CENTER
	close_button.focus_mode = FOCUS_NONE
	close_button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	close_button.pressed.connect(close)
	return close_button

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

## Scrollbare Liste in content (alles davor und der Schließen-Button bleiben stehen): so hoch wie ihr Inhalt,
## höchstens so hoch, dass der ganze Dialog ins Fenster passt. Weiter befüllt wird die zurückgegebene Liste.
func _scroll_list(content: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	DragScroll.attach(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", content.get_theme_constant("separation"))
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)
	_scroll = scroll
	_list = list
	list.minimum_size_changed.connect(_fit_scroll)
	_fit_scroll.call_deferred()
	return list

var _scroll: ScrollContainer
var _list: VBoxContainer

func _fit_scroll() -> void:
	if not is_inside_tree() or _scroll == null:
		return
	var wanted := _list.get_combined_minimum_size()
	# alles außer der Liste (Titel, Schließen-Button, Ränder) braucht seinen Platz, der Rest gehört der Liste
	var others := _panel.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	var max_height := maxf(get_viewport_rect().size.y - others - SCROLL_SCREEN_MARGIN, 120.0)
	var scrolls := wanted.y > max_height
	# Platz für die Scroll-Leiste, damit sie nichts überdeckt
	var bar := _scroll.get_v_scroll_bar().get_combined_minimum_size().x + 8 if scrolls else 0.0
	_scroll.custom_minimum_size = Vector2(wanted.x + bar, minf(wanted.y, max_height))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _list:
		_fit_scroll()

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
