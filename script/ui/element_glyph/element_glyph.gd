class_name ElementGlyph
extends Control

## Stufe eines Elements als Punkte: ein Grundelement ist ein Punkt, eine Verschmelzung aus zwei Elementen
## zwei verbundene Punkte, aus drei ein Dreieck, aus allen vier ein Viereck. Die Punkte stehen in der
## Reihenfolge des Element-Kreises, beim Viereck sind die Kanten also genau die Stärken des Kreises.
## Mit plates sind die Punkte kleine Eisenplatten in der Farbe ihres Elements, wie die Element-Chips.

const ALL_ELEMENTS := Enums.MON_TYPES.EARTH | Enums.MON_TYPES.FIRE | Enums.MON_TYPES.WATER | Enums.MON_TYPES.AIR

var mask := 0:
	set(value):
		mask = value
		update_minimum_size()
		_sync_plates()
		queue_redraw()
var dot_radius := 2.5
## Abstand der äußeren Punkte zueinander
var span := 9.0
var line_width := 1.0
## Punkte und Striche in einer Farbe (Chip) oder jeder Punkt in der Farbe seines Elements
var dot_color := Color.WHITE
var line_color := Color.WHITE
var element_colors := false
var outline_color := Color(0, 0, 0, 0)
var outline_width := 0.0
## Punkte als Element-Platten (Shader der Element-Chips) statt gezeichneter Kreise
var plates := false:
	set(value):
		plates = value
		_sync_plates()
		queue_redraw()

var _plates: Array[IronPlate] = []

## Grundelemente einer Maske in der Reihenfolge des Element-Kreises (Wasser, Feuer, Luft, Erde)
static func elements_of(element_mask: int) -> Array:
	var order := [Enums.MON_TYPES.WATER]
	while order.size() < Skills.STRONG_AGAINST.size():
		order.append(Skills.STRONG_AGAINST[order.back()])
	return order.filter(func(element): return element_mask & element)

## 1 = Grundelement, 2-4 = Verschmelzung aus so vielen Elementen
static func level(element_mask: int) -> int:
	return elements_of(element_mask).size()

func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = TEXTURE_FILTER_NEAREST

func _notification(what: int) -> void:
	# außerhalb des Baums meldet Godot keine Größenänderung, daher auch beim Eintritt neu setzen
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_READY:
		_place_plates()

func _get_minimum_size() -> Vector2:
	var count := level(mask)
	var shape := Vector2(span if count >= 2 else 0.0, span if count >= 3 else 0.0)
	return shape + Vector2.ONE * (dot_radius + outline_width) * 2

## Lage der Punkte im Feld 0..1, Dreieck mit der Spitze oben, Viereck im Uhrzeigersinn
func _shape(count: int) -> Array:
	match count:
		1: return [Vector2(0.5, 0.5)]
		2: return [Vector2(0, 0.5), Vector2(1, 0.5)]
		3: return [Vector2(0.5, 0), Vector2(1, 1), Vector2(0, 1)]
		4: return [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	return []

func _points() -> Array:
	var inset := Vector2.ONE * (dot_radius + outline_width)
	var area := size - inset * 2
	var points := []
	for unit: Vector2 in _shape(level(mask)):
		points.append((inset + unit * area).round())
	return points

## Eine Platte je Grundelement, in seiner Farbe getönt
func _sync_plates() -> void:
	var elements := elements_of(mask) if plates else []
	while _plates.size() > elements.size():
		_plates.pop_back().queue_free()
	while _plates.size() < elements.size():
		var plate := IronPlate.new()
		add_child(plate)
		_plates.append(plate)
	for i in elements.size():
		_plates[i].tint_element(Helper.color_by_type(elements[i]))
	_place_plates()

func _place_plates() -> void:
	var points := _points()
	var plate_size := Vector2.ONE * dot_radius * 2
	for i in mini(_plates.size(), points.size()):
		_plates[i].position = points[i] - plate_size / 2
		_plates[i].size = plate_size

func _draw() -> void:
	var points := _points()
	# Striche zwischen benachbarten Punkten, ab drei Punkten geschlossen; liegen unter den Platten
	if points.size() >= 2:
		var closed := points.size() >= 3
		for i in points.size() if closed else 1:
			var from: Vector2 = points[i]
			var to: Vector2 = points[(i + 1) % points.size()]
			if outline_width > 0:
				draw_line(from, to, outline_color, line_width + outline_width * 2)
			draw_line(from, to, line_color, line_width)
	if plates:
		return
	var elements := elements_of(mask)
	for i in points.size():
		if outline_width > 0:
			draw_circle(points[i], dot_radius + outline_width, outline_color)
		var color := Helper.color_by_type(elements[i]) if element_colors else dot_color
		draw_circle(points[i], dot_radius, color)
