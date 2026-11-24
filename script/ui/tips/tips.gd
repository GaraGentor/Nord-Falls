class_name Tips
extends PanelContainer

## Tipp oben in der schwarzen Spalte der Ei-Auswahl: Titel, dahinter das "???"-Zeichen, darunter die Beschreibung
## und "Mehr Tipps". Die Tipps stehen in TIPS_PATH (Liste aus {"title", "description"}, Texte dürfen auch
## Übersetzungs-Keys sein) und laufen der Reihe nach durch: jeder neue Run zeigt den nächsten (advance beim Aufbruch),
## "Mehr Tipps" schaltet sofort weiter. Nach dem letzten geht es wieder beim ersten los.
## Die Position steht im Spielstand (tip_index).

const TIPS_PATH := "res://data/tips.json"
const TITLE_FONT_SIZE := 32
const TEXT_FONT_SIZE := 24
const MARK_FONT_SIZE := 24
const BUTTON_FONT_SIZE := 24

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
	_tips = load_tips()
	visible = not _tips.is_empty()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	IronPlate.frame(self, column, 14, 10)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	_title = _label(TITLE_FONT_SIZE, SkillDetailPopup.GOLD)
	head.add_child(_title)
	head.add_child(_mark())

	_description = _label(TEXT_FONT_SIZE, IronPlate.TEXT_COLOR)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size.x = 1
	column.add_child(_description)

	var more := RewardDialog.plate_button(tr("TIPS_MORE"))
	more.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	more.size_flags_horizontal = Control.SIZE_SHRINK_END
	more.focus_mode = Control.FOCUS_NONE
	more.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	more.pressed.connect(_on_more_pressed)
	column.add_child(more)
	_show_current()

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
	tween.tween_property(_description, "modulate:a", 0.0, 0.12)
	tween.tween_callback(_show_current)
	tween.tween_property(_description, "modulate:a", 1.0, 0.18)

## "???" hinter dem Titel: zeigt, dass es ein Tipp ist (reine Kennzeichnung)
func _mark() -> Control:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mark := _label(MARK_FONT_SIZE, SkillDetailPopup.GOLD)
	mark.text = "???"
	IronPlate.frame(chip, mark, 6, 0)
	return chip

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
