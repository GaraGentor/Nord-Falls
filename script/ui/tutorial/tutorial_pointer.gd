class_name TutorialPointer
extends Control

## Goldener Pfeil, der über einem Ziel auf und ab wippt und nach unten darauf zeigt.
## Im Tutorial-Lauf auf der Karte über dem nächsten Feld (world_map.gd _point_to_next), damit man nie rätselt,
## wohin es weitergeht. Ignoriert Klicks.

const SIZE := Vector2(44, 52)
## so weit wippt der Pfeil, und so lange dauert ein Hin und Her
const BOB := 12.0
const BOB_SECONDS := 0.9
## Abstand der Pfeilspitze über der Oberkante des Ziels
const GAP := 6.0
const FILL := SkillDetailPopup.GOLD
const OUTLINE := Color(0.08, 0.05, 0.02)
const OUTLINE_WIDTH := 4.0

var _time := 0.0
## true = gerade liegt etwas über dem Ziel (z. B. Shop über der Karte): der Pfeil bleibt so lange unsichtbar,
## sonst schiene er wegen z_index durch
var covered := Callable()

func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	size = SIZE
	z_index = 20

func _process(delta: float) -> void:
	visible = not (covered.is_valid() and covered.call())
	if not visible:
		return
	_time += delta
	var parent := get_parent() as Control
	if parent == null:
		return
	var bob := (sin(_time * TAU / BOB_SECONDS) + 1.0) / 2.0 * BOB
	position = Vector2((parent.size.x - SIZE.x) / 2.0, -SIZE.y - GAP - bob)

func _draw() -> void:
	var w := SIZE.x
	var h := SIZE.y
	var shaft := w * 0.36
	var head := h * 0.5
	var points := PackedVector2Array([
		Vector2((w - shaft) / 2.0, 0), Vector2((w + shaft) / 2.0, 0),
		Vector2((w + shaft) / 2.0, h - head), Vector2(w, h - head),
		Vector2(w / 2.0, h),
		Vector2(0, h - head), Vector2((w - shaft) / 2.0, h - head),
	])
	draw_colored_polygon(points, FILL)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, OUTLINE, OUTLINE_WIDTH, true)
