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

# ── Werte an den Achsen (Level-Up, level_up_monster_scene.gd) ─────────────────
## Statt nur der Symbole steht an jeder Achse Symbol, aktueller Wert und der Zuwachs beim letzten Level-Up (grün),
## so ersetzt das Netz die Werte-Liste. Ein Klick auf einen Wert erklärt die Werte (StatInfoDialog).
const VALUE_FONT_SIZE := 24
const VALUE_ICON_SIZE := 24.0
## Abstand zwischen Netzspitze und Beschriftung bzw. zwischen Symbol, Zahl und Zuwachs
const VALUE_GAP := 6.0
var _value_mon: Monster
## Schrift der Werte (sonst die Standardschrift), level_up_monster_scene.gd nimmt die der Werte-Liste
var value_font: Font
## Stat-Key -> Rect2 der Beschriftung (für Klicks)
var _value_rects := {}

func show_values(mon: Monster) -> void:
	_value_mon = mon
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	queue_redraw()

## Angezeigter Wert (abgeschnitten wie in StatsGrid)
static func stat_value(mon: Monster, stat: String) -> int:
	match stat:
		"hp": return int(mon.hp())
		"atk": return int(mon.attack())
		"s_atk": return int(mon.s_attack())
		"def": return int(mon.defense())
		"speed": return int(mon.speed())
		"bst": return mon._best_points
	return 0

func _value_parts(stat: String) -> Array:
	var parts := [str(stat_value(_value_mon, stat))]
	var gain: int = _gains.get(stat, 0)
	if gain != 0:
		parts.append("%+d" % gain)
	return parts

## Breite und Höhe der Beschriftung einer Achse
func _value_size(font: Font, stat: String) -> Vector2:
	var width := VALUE_ICON_SIZE
	for part in _value_parts(stat):
		width += VALUE_GAP + font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, VALUE_FONT_SIZE).x
	return Vector2(width, maxf(VALUE_ICON_SIZE, font.get_height(VALUE_FONT_SIZE)))

func _draw_value(font: Font, stat: String, rect: Rect2) -> void:
	var icon_rect := Rect2(rect.position + Vector2(0, (rect.size.y - VALUE_ICON_SIZE) / 2), Vector2.ONE * VALUE_ICON_SIZE)
	draw_texture_rect(StatsGrid.ICONS[stat], icon_rect, false, Color(1, 1, 1, StatsGrid.ICON_ALPHA))
	var x := rect.position.x + VALUE_ICON_SIZE
	var baseline := rect.position.y + (rect.size.y - font.get_height(VALUE_FONT_SIZE)) / 2 + font.get_ascent(VALUE_FONT_SIZE)
	var parts := _value_parts(stat)
	for i in parts.size():
		x += VALUE_GAP
		var color := IronPlate.TEXT_COLOR if i == 0 else GAIN_COLOR
		draw_string(font, Vector2(x, baseline), parts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, VALUE_FONT_SIZE, color)
		x += font.get_string_size(parts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, VALUE_FONT_SIZE).x

func _gui_input(event: InputEvent) -> void:
	if _value_mon == null or not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	for stat in _value_rects:
		if _value_rects[stat].grow(VALUE_GAP).has_point(event.position):
			accept_event()
			StatInfoDialog.open(self, stat)
			return

func _draw() -> void:
	var center := size / 2
	var font := value_font if value_font else get_theme_default_font()
	var value_sizes := {}
	var radius := minf(size.x, size.y) / 2 - LABEL_SPACE - ICON_SIZE / 2
	if _value_mon:
		# Platz für die breiteste Beschriftung links/rechts und eine Zeile oben/unten
		var widest := 0.0
		var height := 0.0
		for stat in STATS:
			value_sizes[stat] = _value_size(font, stat)
			widest = maxf(widest, value_sizes[stat].x)
			height = maxf(height, value_sizes[stat].y)
		radius = minf(size.x / 2 - widest - VALUE_GAP, size.y / 2 - height - VALUE_GAP)
	if radius <= 4:
		return
	for ring in range(1, RINGS + 1):
		var points := _ring(center, radius * ring / RINGS)
		points.append(points[0])
		draw_polyline(points, GRID_COLOR, 1.0, true)
	var outer := _ring(center, radius)
	_value_rects = {}
	for i in STATS.size():
		draw_line(center, outer[i], AXIS_COLOR, 1.0, true)
		if _value_mon:
			# Beschriftung nach außen an die Spitze gelegt
			var dir := _direction(i)
			var box: Vector2 = value_sizes[STATS[i]]
			var anchor := center + dir * (radius + VALUE_GAP)
			var rect := Rect2(anchor + Vector2((dir.x - 1) * box.x / 2, (dir.y - 1) * box.y / 2), box)
			_value_rects[STATS[i]] = rect
			_draw_value(font, STATS[i], rect)
			continue
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
	_draw_gains(center, radius)

# ── Zuwachs beim Level-Up (level_up_monster_scene.gd) ─────────────────────────
## Gewonnene Punkte pro Wert als "+N" an der Achse, blenden nach GAIN_SECONDS aus. Dazu leuchtet die Fläche kurz auf:
## so sieht man, dass die Form des Netzes bestimmt, welche Werte beim Aufstieg wachsen.
const GAIN_SECONDS := 2.0
const GAIN_FONT_SIZE := 20
const GAIN_COLOR := StatsGrid.GAIN_COLOR
var _gains := {}
var _gain_alpha := 0.0

## gains: Stat-Key -> Zuwachs (z. B. {"hp": 3, "atk": 1})
func show_gains(gains: Dictionary) -> void:
	_gains = gains
	var tween := create_tween()
	tween.tween_method(_set_gain_alpha, 1.0, 1.0, GAIN_SECONDS * 0.7)
	tween.tween_method(_set_gain_alpha, 1.0, 0.0, GAIN_SECONDS * 0.3)
	var pulse := create_tween()
	pivot_offset = size / 2
	pulse.tween_property(self, "scale", Vector2.ONE * 1.08, 0.15).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_SINE)

func _set_gain_alpha(alpha: float) -> void:
	_gain_alpha = alpha
	queue_redraw()

func _draw_gains(center: Vector2, radius: float) -> void:
	if _gain_alpha <= 0.0 or _gains.is_empty():
		return
	var font := get_theme_default_font()
	var color := GAIN_COLOR
	color.a = _gain_alpha
	for i in STATS.size():
		var gain: int = _gains.get(STATS[i], 0)
		# mit Werten an den Achsen steht der Zuwachs dauerhaft hinter dem Wert (_draw_value)
		if gain == 0 or _value_mon:
			continue
		var text := "%+d" % gain
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, GAIN_FONT_SIZE)
		# neben dem Symbol, nach außen versetzt
		var at := center + _direction(i) * (radius + LABEL_SPACE + ICON_SIZE)
		draw_string_outline(font, at - text_size / 2 + Vector2(0, text_size.y * 0.75), text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, GAIN_FONT_SIZE, 4, Color(0, 0, 0, _gain_alpha))
		draw_string(font, at - text_size / 2 + Vector2(0, text_size.y * 0.75), text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, GAIN_FONT_SIZE, color)
	# Fläche leuchtet mit
	var top := _max_value() * HEADROOM
	if top <= 0:
		return
	for entry in _entries:
		var points := PackedVector2Array()
		for i in STATS.size():
			points.append(center + _direction(i) * radius * entry.mon.growth_per_level(STATS[i]) / top)
		var glow := color
		glow.a = 0.25 * _gain_alpha
		draw_colored_polygon(points, glow)

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
