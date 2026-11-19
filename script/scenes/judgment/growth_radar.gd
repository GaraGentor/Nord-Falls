class_name GrowthRadar
extends Control

## Netzdiagramm im Judgement-Screen: fünf Achsen (KP, Angriff, Verteidigung, Sp. Angriff, Initiative),
## jedes Monster als Fläche in seiner Farbe (wie der Rahmen seiner Werte). Gezeigt wird der Zuwachs pro Stufe,
## alle Flächen teilen sich einen Maßstab, damit sie sich vergleichen lassen.

const STATS := Growth.ATTRS
const STAT_LABELS := {"hp": "STAT_HP", "atk": "STAT_ATK", "def": "STAT_DEF", "s_atk": "STAT_SPA", "speed": "STAT_SPE"}
const RINGS := 4
const GRID_COLOR := Color(0.86, 0.83, 0.72, 0.18)
const AXIS_COLOR := Color(0.86, 0.83, 0.72, 0.3)
const FILL_ALPHA := 0.22
const LINE_WIDTH := 2.5
const ICON_SIZE := 18.0
## Platz zwischen Netz und Rand für die Symbole
const LABEL_SPACE := 16.0
## Luft über dem größten Wert
const HEADROOM := 1.1

## [{"mon": Monster, "color": Color}]
var _entries: Array = []

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_PASS
	resized.connect(queue_redraw)

func show_mons(entries: Array) -> void:
	_entries = entries
	tooltip_text = _values_text()
	queue_redraw()

func _draw() -> void:
	var center := size / 2
	var radius := minf(size.x, size.y) / 2 - LABEL_SPACE - ICON_SIZE / 2
	if radius <= 4:
		return
	for ring in range(1, RINGS + 1):
		var points := _ring(center, radius * ring / RINGS)
		points.append(points[0])
		draw_polyline(points, GRID_COLOR, 1.0, true)
	var outer := _ring(center, radius)
	for i in STATS.size():
		draw_line(center, outer[i], AXIS_COLOR, 1.0, true)
		var icon_center := center + _direction(i) * (radius + LABEL_SPACE)
		draw_texture_rect(StatsGrid.ICONS[STATS[i]], Rect2(icon_center - Vector2.ONE * ICON_SIZE / 2, Vector2.ONE * ICON_SIZE), false, Color(1, 1, 1, StatsGrid.ICON_ALPHA))
	var top := _max_value() * HEADROOM
	if top <= 0:
		return
	for entry in _entries:
		var points := PackedVector2Array()
		for i in STATS.size():
			points.append(center + _direction(i) * radius * entry.mon.growth_per_level(STATS[i]) / top)
		var fill: Color = entry.color
		fill.a = FILL_ALPHA
		draw_colored_polygon(points, fill)
		points.append(points[0])
		draw_polyline(points, entry.color, LINE_WIDTH, true)

## Werte aller Monster zum Nachlesen (Tooltip)
func _values_text() -> String:
	var lines := PackedStringArray([tr("JUDGEMENT_GROWTH")])
	for entry in _entries:
		var parts := PackedStringArray()
		for stat in STATS:
			parts.append("%s %.1f" % [tr(_stat_label(stat)).trim_suffix(":"), entry.mon.growth_per_level(stat)])
		lines.append("%s: %s" % [Helper.mon_battle_name(entry.mon), ", ".join(parts)])
	return "\n".join(lines)

func _stat_label(stat: String) -> String:
	return STAT_LABELS.get(stat, stat)

func _max_value() -> float:
	var top := 0.0
	for entry in _entries:
		for stat in STATS:
			top = maxf(top, entry.mon.growth_per_level(stat))
	return top

## Erste Achse zeigt nach oben, dann im Uhrzeigersinn
func _direction(i: int) -> Vector2:
	return Vector2.UP.rotated(TAU * i / STATS.size())

func _ring(center: Vector2, ring_radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in STATS.size():
		points.append(center + _direction(i) * ring_radius)
	return points
