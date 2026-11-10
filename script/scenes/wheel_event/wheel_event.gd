extends RewardDialog

## Ereignis Glücksrad: einmal drehen, die Hälfte des aktuellen Goldes gewinnen oder verlieren.
## Das Ergebnis wird vorher gewürfelt, das Rad dreht sich dann passend auf die Gewinn- bzw. Verlust-Hälfte.
## Aufbau wie die anderen Felder der Karte: Panel über der Kartenfläche, Titel und Anleitung oben,
## darunter füllt das Rad den Platz.

const ACCENT := Color(0.85, 0.65, 0.2)
const WIN_COLOR := Color(0.25, 0.6, 0.3)
const LOSE_COLOR := Color(0.7, 0.2, 0.2)

## Anteil des aktuellen Goldes, der gewonnen oder verloren wird
const GOLD_SHARE := 0.5
const WIN_CHANCE := 0.5

const WHEEL_MIN_SIZE := Vector2(240, 240)
const SPIN_TIME := 3.0
const SPIN_TURNS := 5

## Rad mit Gewinn-Hälfte (lokal 0..PI) und Verlust-Hälfte (PI..2PI), Zeiger oben
class Wheel extends Control:
	const TEXT_SIZE := 26

	var win_text := ""
	var lose_text := ""
	var angle := 0.0:
		set(val):
			angle = val
			queue_redraw()

	func _draw() -> void:
		var center := size / 2
		var radius := minf(size.x, size.y) / 2 - 16
		_draw_half(center, radius, 0.0, WIN_COLOR, win_text)
		_draw_half(center, radius, PI, LOSE_COLOR, lose_text)
		draw_arc(center, radius, 0, TAU, 64, IronPlate.RIM, 4)
		# Zeiger oben, zeigt nach unten aufs Rad
		var tip := Vector2(center.x, center.y - radius + 14)
		draw_colored_polygon(PackedVector2Array([tip, Vector2(center.x - 14, tip.y - 30), Vector2(center.x + 14, tip.y - 30)]), SkillDetailPopup.GOLD)

	func _draw_half(center: Vector2, radius: float, from: float, color: Color, text: String) -> void:
		var points := PackedVector2Array([center])
		for i in 33:
			points.append(center + Vector2.from_angle(angle + from + PI * i / 32) * radius)
		draw_colored_polygon(points, color)
		var font := get_theme_font("font", "Label")
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE)
		var pos := center + Vector2.from_angle(angle + from + PI / 2) * radius * 0.55
		draw_string(font, pos + Vector2(-text_size.x / 2, TEXT_SIZE / 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, IronPlate.TEXT_COLOR)

var _wheel: Wheel
var _result: Label
var _spin_button: Button
var _ok_button: Button
var _amount: int

func _ready() -> void:
	use_map_layout()
	set_accent(ACCENT)
	set_title(tr("EVENT_WHEEL_TITLE"))
	_amount = int(State.ep * GOLD_SHARE)
	set_drag_hint(tr("EVENT_WHEEL_DESC").format({"amount": _amount}))
	# keine Preise und Ziele, nur Rad und Knöpfe
	_columns.visible = false

	_wheel = Wheel.new()
	_wheel.custom_minimum_size = WHEEL_MIN_SIZE
	_wheel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wheel.win_text = "+ " + Helper.me_text(_amount)
	_wheel.lose_text = "- " + Helper.me_text(_amount)
	add_footer(_wheel)

	_result = Label.new()
	_result.theme = LABEL_THEME
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.visible = false
	add_footer(_result)

	_spin_button = plate_button(tr("EVENT_WHEEL_SPIN"))
	_spin_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_spin_button.pressed.connect(_spin)
	add_footer(_spin_button)

	_ok_button = plate_button(tr("COMMON_OK"))
	_ok_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ok_button.visible = false
	_ok_button.pressed.connect(close)
	add_footer(_ok_button)

func _spin() -> void:
	_spin_button.disabled = true
	var won := randf() < WIN_CHANCE
	# lokaler Winkel, der am Ende unter dem Zeiger (oben, 3/2 PI) steht, nicht zu nah an der Grenze
	var landing := randf_range(0.15, 0.85) * PI + (0.0 if won else PI)
	var target := 1.5 * PI - landing + SPIN_TURNS * TAU
	await create_tween().tween_property(_wheel, "angle", target, SPIN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).finished
	if won:
		State.ep += _amount
	else:
		State.ep -= _amount
	_result.text = tr("EVENT_WHEEL_WIN" if won else "EVENT_WHEEL_LOSE").format({"amount": _amount})
	_result.add_theme_color_override("font_color", WIN_COLOR if won else LOSE_COLOR)
	_result.visible = true
	_spin_button.visible = false
	_ok_button.visible = true
