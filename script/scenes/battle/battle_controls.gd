class_name BattleControls
extends VBoxContainer

## Knöpfe am rechten Rand des Kampffelds (oben, über der Boss-Relikt-Leiste, gleicher Stil wie BossRelicBar):
##   Geschwindigkeit: stellt die Animationen des Kampfs um (1x, 2x, 5x, 10x). Wirkt über Engine.time_scale,
##     also auf Tweens, Timer und Animationen gleichermaßen. Linksklick schneller, Rechtsklick langsamer.
##   Auto-Zugende: ist es an, endet der eigene Zug von selbst, sobald keine Karte mehr spielbar ist (siehe battle.gd).
## Beide Einstellungen bleiben für spätere Kämpfe erhalten, außerhalb des Kampfs läuft alles wieder in
## normaler Geschwindigkeit (siehe _exit_tree).

signal auto_end_toggled(enabled: bool)

const SPEEDS := [1.0, 2.0, 5.0, 10.0]
const SIZE := Vector2(66, 40)
const PADDING := 5
const BACKGROUND := Color(0, 0, 0, 0.6)
const BACKGROUND_ON := Color(0.858824, 0.717647, 0.45098, 0.35)
const BORDER := Color(0.858824, 0.717647, 0.45098)
const BORDER_HOVER := Color(1.0, 0.92, 0.65)
const TEXT_COLOR := Color(0.858824, 0.717647, 0.45098)
const TEXT_OFF := Color(0.55, 0.5, 0.4)
const FONT_SIZE := 18
const MARGIN := 8

## gewählte Stufe (Index in SPEEDS), gilt für alle Kämpfe des Spiels
static var speed_index := 0
## Zug automatisch beenden, wenn nichts mehr spielbar ist
static var auto_end := false

var _speed_label: Label
var _auto_label: Label
var _auto_style: StyleBoxFlat

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -(SIZE.x + MARGIN)
	offset_right = -MARGIN
	offset_top = MARGIN
	offset_bottom = MARGIN
	var speed := _slot(tr("BATTLE_SPEED_TOOLTIP"), _on_speed_input)
	_speed_label = speed.get_child(0)
	add_child(speed)
	var auto := _slot(tr("BATTLE_AUTO_END_TOOLTIP"), _on_auto_input)
	_auto_label = auto.get_child(0)
	_auto_style = auto.get_theme_stylebox("panel")
	add_child(auto)
	_apply_speed()
	_apply_auto()

func _slot(tooltip: String, on_input: Callable) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(PADDING)
	slot.add_theme_stylebox_override("panel", style)
	slot.tooltip_text = tooltip
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot.mouse_entered.connect(func(): style.border_color = BORDER_HOVER)
	slot.mouse_exited.connect(func(): style.border_color = BORDER)
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			on_input.call(event.button_index)
			slot.accept_event())
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)
	return slot

func _on_speed_input(button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		speed_index = (speed_index + 1) % SPEEDS.size()
	elif button == MOUSE_BUTTON_RIGHT:
		speed_index = (speed_index - 1 + SPEEDS.size()) % SPEEDS.size()
	else:
		return
	_apply_speed()

func _on_auto_input(button: int) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	auto_end = not auto_end
	_apply_auto()
	auto_end_toggled.emit(auto_end)

func _apply_speed() -> void:
	var speed: float = SPEEDS[speed_index]
	Engine.time_scale = speed
	_speed_label.text = "%dx >>" % int(speed)

func _apply_auto() -> void:
	_auto_label.text = "AUTO"
	_auto_label.add_theme_color_override("font_color", TEXT_COLOR if auto_end else TEXT_OFF)
	_auto_style.bg_color = BACKGROUND_ON if auto_end else BACKGROUND

func _exit_tree() -> void:
	Engine.time_scale = 1.0
