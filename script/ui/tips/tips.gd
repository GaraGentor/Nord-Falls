class_name Tips
extends PanelContainer

## Tipp oben in der schwarzen Spalte der Ei-Auswahl: Titel, darunter die Beschreibung und "Mehr Tipps", ohne Rahmen
## direkt auf dem Schwarzen. Hinter dem ganzen Text liegt groß und blass das "???"-Zeichen (_draw), immer an derselben
## Stelle: Es hängt nicht am Layout, langer oder kurzer Text verschiebt es nicht.
## Die Tipps stehen in TIPS_PATH (Liste aus {"title", "description"}, Texte dürfen auch Übersetzungs-Keys sein) und
## laufen der Reihe nach durch: jeder neue Run zeigt den nächsten (advance beim Aufbruch), "Mehr Tipps" schaltet sofort
## weiter. Nach dem letzten geht es wieder beim ersten los. Die Position steht im Spielstand (tip_index).

const TIPS_PATH := "res://data/tips.json"
const TITLE_FONT_SIZE := 32
const TEXT_FONT_SIZE := 24
const BUTTON_FONT_SIZE := 24

## "???" hinter dem Text: Schriftgröße, Deckkraft und die feste Fläche, in deren Mitte es steht
## (so hoch ist der Tipp mindestens, längerer Text wächst darüber hinaus, ohne das Zeichen zu bewegen)
const MARK_TEXT := "???"
const MARK_FONT_SIZE := 180
const MARK_ALPHA := 0.12
const MARK_AREA_HEIGHT := 220

var _title: Label
var _description: Label
var _tips: Array = []

## Die Tipps aus der JSON, leere oder kaputte Einträge fallen weg
static func load_tips() -> Array:
	if not FileAccess.file_exists(TIPS_PATH):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TIPS_PATH))
	if not parsed is Array:
		push_warning("Tipps: %s ist keine Liste" % TIPS_PATH)
		return []
	return parsed.filter(func(tip): return tip is Dictionary and str(tip.get("description", "")) != "")

## Nächster Run, nächster Tipp
static func advance() -> void:
	SaveManager.save_data["tip_index"] = int(SaveManager.save_data.get("tip_index", 0)) + 1
	SaveManager.save_game()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	custom_minimum_size.y = MARK_AREA_HEIGHT
	_tips = load_tips()
	visible = not _tips.is_empty()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_title = _label(TITLE_FONT_SIZE, SkillDetailPopup.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	_description = _label(TEXT_FONT_SIZE, IronPlate.TEXT_COLOR)
	_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size.x = 1
	column.add_child(_description)

	var more := RewardDialog.plate_button(tr("TIPS_MORE"))
	more.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	more.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	more.focus_mode = Control.FOCUS_NONE
	more.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	more.pressed.connect(_on_more_pressed)
	column.add_child(more)
	_show_current()

## Das "???" liegt unter den Kindern (Titel, Text, Knopf), mittig in der festen Fläche oben
func _draw() -> void:
	var font := get_theme_default_font()
	var color: Color = SkillDetailPopup.GOLD
	color.a = MARK_ALPHA
	var baseline := MARK_AREA_HEIGHT * 0.5 + (font.get_ascent(MARK_FONT_SIZE) - font.get_descent(MARK_FONT_SIZE)) * 0.5
	draw_string(font, Vector2(0, baseline), MARK_TEXT, HORIZONTAL_ALIGNMENT_CENTER, size.x, MARK_FONT_SIZE, color)

func _show_current() -> void:
	if _tips.is_empty():
		return
	var tip: Dictionary = _tips[posmod(int(SaveManager.save_data.get("tip_index", 0)), _tips.size())]
	_title.text = tr(str(tip.get("title", "TIPS_TITLE")))
	_description.text = tr(str(tip.description))

func _on_more_pressed() -> void:
	advance()
	# kurz ausblenden und mit dem neuen Tipp wieder einblenden
	var tween := create_tween()
	for label in [_title, _description]:
		tween.parallel().tween_property(label, "modulate:a", 0.0, 0.12)
	tween.tween_callback(_show_current)
	for label in [_title, _description]:
		tween.parallel().tween_property(label, "modulate:a", 1.0, 0.18)

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
