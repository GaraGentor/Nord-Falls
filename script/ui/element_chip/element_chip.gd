extends Control

## Name eines Elements auf einer Eisenplatte in seiner Farbe, rechts daneben seine Stufe als Punkte
## (ElementGlyph). Element-Chips lassen sich anklicken und zeigen dann, woraus das Element besteht.
## Andere Chips (Seltenheit über _init_with_element) bleiben reine Anzeige.

const DARK_TEXT := Color(0.1, 0.1, 0.12)
## Abstand zwischen Text und Stufen-Punkten
const GLYPH_GAP := 6.0
const GLYPH_DOT_RADIUS := 3.0
const GLYPH_SPAN := 10.0
const HOVER_MODULATE := Color(1.25, 1.25, 1.2)

@export var label: Label
@export var plate: IronPlate

## Platz um den Text, die Platte ragt so weit über das Label hinaus (element_chip.tscn)
const PADDING := Vector2(16, 8)

## Element-Maske des Chips, -1 = kein Element (z. B. Seltenheit)
var element := -1
var _glyph: ElementGlyph

func _ready() -> void:
	# der Text ist mittig verankert, die Größe des Chips folgt ihm (erst im Baum ist die Pixel-Schrift bekannt)
	label.minimum_size_changed.connect(update_minimum_size)

func _get_minimum_size() -> Vector2:
	return label.get_combined_minimum_size() + PADDING if label else Vector2.ZERO

func _init_color(mon: Monster) -> void:
	set_element(mon._type)

## Chip für ein Element bzw. eine Verschmelzung: Name, Farbe, Stufe und klickbar
func set_element(mask: int) -> void:
	element = mask
	label.text = tr(ColorMap.get_combo(mask).label)
	_set_background(Helper.color_by_type(mask))
	_show_glyph(true)
	# PASS: Ziehen und Ablegen auf Ziele darunter (Belohnungs-Dialoge) klappt weiter
	plate.mouse_filter = Control.MOUSE_FILTER_PASS
	plate.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	plate.tooltip_text = tr("ELEMENT_INFO_HINT")
	if not plate.gui_input.is_connected(_on_plate_input):
		plate.gui_input.connect(_on_plate_input)
		plate.mouse_entered.connect(func(): plate.modulate = HOVER_MODULATE if element >= 0 else Color.WHITE)
		plate.mouse_exited.connect(func(): plate.modulate = Color.WHITE)

## Chip mit freiem Text in einer Farbe, z. B. die Seltenheit
func _init_with_element(data) -> void:
	element = -1
	label.text = tr(data.label)
	_set_background(data.color)
	_show_glyph(false)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.tooltip_text = ""

func _on_plate_input(event: InputEvent) -> void:
	if element >= 0 and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# nicht an Monster-Widgets o. Ä. darunter weitergeben
		accept_event()
		ElementInfoDialog.open(self, element)

## Punkte rechts im Label; der rechte Innenabstand des Labels hält ihnen Platz frei, so wächst der Chip mit
func _show_glyph(on: bool) -> void:
	if _glyph == null:
		_glyph = ElementGlyph.new()
		_glyph.dot_radius = GLYPH_DOT_RADIUS
		_glyph.span = GLYPH_SPAN
		_glyph.anchor_left = 1.0
		_glyph.anchor_right = 1.0
		_glyph.anchor_top = 0.5
		_glyph.anchor_bottom = 0.5
		_glyph.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_glyph.grow_vertical = Control.GROW_DIRECTION_BOTH
		label.add_child(_glyph)
	_glyph.visible = on
	_glyph.dot_color = label.get_theme_color("font_color")
	_glyph.line_color = _glyph.dot_color
	if on:
		_glyph.mask = element
	var margins := StyleBoxEmpty.new()
	# get_minimum_size rechnet sofort neu, die kombinierte Größe hinge noch an der alten Maske
	margins.content_margin_right = _glyph.get_minimum_size().x + GLYPH_GAP if on else 0.0
	label.add_theme_stylebox_override("normal", margins)
	# zentriert würde der Text über die volle Breite samt Punkten gesetzt; das Label ist ohnehin nur so breit
	# wie Text und Punkte, links ausgerichtet steht der Text also mittig in seinem Bereich
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if on else HORIZONTAL_ALIGNMENT_CENTER

func _set_background(color: Color) -> void:
	# auf hellen Farben (Luft) ist weißer Text nicht lesbar
	var light := color.get_luminance() > IronPlate.LIGHT_FILL
	label.add_theme_color_override("font_color", DARK_TEXT if light else Color.WHITE)
	plate.tint_element(color)
