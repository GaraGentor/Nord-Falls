extends Node2D

## Kurze, gezeichnete Effekte über einem Monster im Kampf (siehe MonsterScene._play_skill_vfx):
## physische Treffer als Hieb, magische Treffer je Element (Feuer-Explosion, Wasser-Spritzer, Steinbrocken, Windwirbel),
## Schilde (physisch: blaues Sechseck, magisch: violetter Runenkreis), Schildtreffer und Buffs.
## Kombi-Elemente haben eigene Treffer: Dampfwolke, Blitz, Lava, Eissplitter, Sandwirbel, Schlammspritzer,
## Giftblasen (Sumpf), Aschewolke mit Glut (Aschesturm), Gewitterwolke (Gewitter), Ausbruch (Vulkan) und Chaos-Ringe.
## Dazu Schwächung (rote Pfeile nach unten) und Heilung (grüne Kreuze).
## Jeder Effekt zeichnet sich in _draw aus seinem Fortschritt (0..1) und löscht sich danach selbst.

enum Kind { SLASH, FIRE, WATER, EARTH, AIR, SHIELD, S_SHIELD, SHIELD_HIT, S_SHIELD_HIT, BUFF,
	STEAM, LIGHTNING, MAGMA, ICE, DUST, MUD, POISON, ASH, THUNDER, ERUPTION, CHAOS, DEBUFF, HEAL }

const DURATIONS := {
	Kind.SLASH: 0.38,
	Kind.FIRE: 0.65,
	Kind.WATER: 0.7,
	Kind.EARTH: 0.7,
	Kind.AIR: 0.6,
	Kind.SHIELD: 0.75,
	Kind.S_SHIELD: 0.85,
	Kind.SHIELD_HIT: 0.4,
	Kind.S_SHIELD_HIT: 0.4,
	Kind.BUFF: 0.8,
	Kind.STEAM: 0.8,
	Kind.LIGHTNING: 0.5,
	Kind.MAGMA: 0.75,
	Kind.ICE: 0.7,
	Kind.DUST: 0.75,
	Kind.MUD: 0.7,
	Kind.POISON: 0.85,
	Kind.ASH: 0.85,
	Kind.THUNDER: 0.75,
	Kind.ERUPTION: 0.85,
	Kind.CHAOS: 0.9,
	Kind.DEBUFF: 0.8,
	Kind.HEAL: 0.8,
}

const STEAM_COLOR := Color(0.92, 0.95, 0.97)
const LIGHTNING_COLOR := Color(1.0, 0.95, 0.45)
const MAGMA_COLORS := [Color(1.0, 0.75, 0.2), Color(0.95, 0.35, 0.08), Color(0.3, 0.12, 0.08)]
const ICE_COLOR := Color(0.7, 0.92, 1.0)
const MUD_COLORS := [Color(0.42, 0.3, 0.18), Color(0.3, 0.22, 0.13)]
const POISON_COLOR := Color(0.6, 0.9, 0.3)
const ASH_COLOR := Color(0.32, 0.3, 0.3)
const STORM_CLOUD_COLOR := Color(0.28, 0.3, 0.38)
const DEBUFF_COLOR := Color(1.0, 0.45, 0.4)
const HEAL_COLOR := Color(0.5, 1.0, 0.6)
## Kombi-Element (Maske wie in ElementEffects) -> eigener Treffer-Effekt
const COMBO_KINDS := {
	ElementEffects.STEAM: Kind.STEAM,
	ElementEffects.LIGHTNING: Kind.LIGHTNING,
	ElementEffects.MAGMA: Kind.MAGMA,
	ElementEffects.ICE: Kind.ICE,
	ElementEffects.DUST: Kind.DUST,
	ElementEffects.MUD: Kind.MUD,
	ElementEffects.SWAMP: Kind.POISON,
	ElementEffects.ASH_STORM: Kind.ASH,
	ElementEffects.THUNDERSTORM: Kind.THUNDER,
	ElementEffects.VOLCANO: Kind.ERUPTION,
	ElementEffects.CHAOS: Kind.CHAOS,
}
const CHAOS_COLORS := [Color(0.55, 0.4, 0.22), Color(1.0, 0.5, 0.15), Color(0.35, 0.7, 1.0), Color(0.85, 0.97, 1.0)]

const SHIELD_COLOR := Color(0.55, 0.8, 1.0)
const S_SHIELD_COLOR := Color(0.85, 0.6, 1.0)
const BUFF_COLOR := Color(0.55, 1.0, 0.55)
const FIRE_COLORS := [Color(1.0, 0.95, 0.6), Color(1.0, 0.6, 0.15), Color(0.9, 0.25, 0.05)]
const WATER_COLOR := Color(0.35, 0.7, 1.0)
const EARTH_COLORS := [Color(0.55, 0.4, 0.22), Color(0.42, 0.3, 0.16), Color(0.68, 0.55, 0.35)]
const DUST_COLOR := Color(0.78, 0.68, 0.5)
const AIR_COLOR := Color(0.85, 0.97, 1.0)

var kind: Kind
var radius: float
## Akzentfarbe, z. B. das Element eines physischen Hiebs
var color: Color
var _duration: float
var _time := 0.0
var _delay := 0.0
## beim Start gewürfelte Partikel (Richtung, Tempo, Größe, ...), damit jeder Effekt etwas anders aussieht
var _parts: Array[Part] = []
var _flip := 1.0

## Richtet den Effekt vor dem add_child ein: center ist die Mitte des Monsters im Elternknoten, size sein ungefährer Radius.
func setup(center: Vector2, size: float, effect: Kind, accent := Color.WHITE, delay := 0.0) -> void:
	kind = effect
	radius = size
	color = accent
	position = center
	z_index = 9
	_delay = delay

## Effekt-Arten für ein Element (Bitmaske): Kombi-Elemente haben ihren eigenen Effekt, Grundelemente den ihres Elements.
static func element_kinds(nature: int) -> Array:
	if COMBO_KINDS.has(nature):
		return [COMBO_KINDS[nature]]
	var kinds := []
	if nature & Enums.MON_TYPES.FIRE:
		kinds.append(Kind.FIRE)
	if nature & Enums.MON_TYPES.WATER:
		kinds.append(Kind.WATER)
	if nature & Enums.MON_TYPES.EARTH:
		kinds.append(Kind.EARTH)
	if nature & Enums.MON_TYPES.AIR:
		kinds.append(Kind.AIR)
	return kinds

func _ready() -> void:
	_duration = DURATIONS[kind]
	_flip = -1.0 if randf() < 0.5 else 1.0
	_roll_parts()
	visible = _delay <= 0.0

func _process(delta: float) -> void:
	if _delay > 0.0:
		_delay -= delta
		visible = _delay <= 0.0
		return
	_time += delta
	if _time >= _duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	if _delay > 0.0:
		return
	var t := clampf(_time / _duration, 0.0, 1.0)
	match kind:
		Kind.SLASH: _draw_slash(t)
		Kind.FIRE: _draw_fire(t)
		Kind.WATER: _draw_water(t)
		Kind.EARTH: _draw_earth(t)
		Kind.AIR: _draw_air(t)
		Kind.SHIELD: _draw_shield(t)
		Kind.S_SHIELD: _draw_s_shield(t)
		Kind.SHIELD_HIT: _draw_shield_hit(t, SHIELD_COLOR, false)
		Kind.S_SHIELD_HIT: _draw_shield_hit(t, S_SHIELD_COLOR, true)
		Kind.BUFF: _draw_buff(t)
		Kind.STEAM: _draw_steam(t)
		Kind.LIGHTNING: _draw_lightning(t)
		Kind.MAGMA: _draw_magma(t)
		Kind.ICE: _draw_ice(t)
		Kind.DUST: _draw_dust(t)
		Kind.MUD: _draw_mud(t)
		Kind.POISON: _draw_poison(t)
		Kind.ASH: _draw_ash(t)
		Kind.THUNDER: _draw_thunder(t)
		Kind.ERUPTION: _draw_eruption(t)
		Kind.CHAOS: _draw_chaos(t)
		Kind.DEBUFF: _draw_debuff(t)
		Kind.HEAL: _draw_heal(t)

func _roll_parts() -> void:
	var count := 0
	match kind:
		Kind.SLASH: count = 6
		Kind.FIRE: count = 16
		Kind.WATER: count = 14
		Kind.EARTH: count = 10
		Kind.AIR: count = 5
		Kind.S_SHIELD: count = 8
		Kind.SHIELD_HIT, Kind.S_SHIELD_HIT: count = 5
		Kind.BUFF: count = 10
		Kind.STEAM: count = 9
		Kind.LIGHTNING: count = 8
		Kind.MAGMA: count = 10
		Kind.ICE: count = 10
		Kind.DUST: count = 18
		Kind.MUD: count = 10
		Kind.POISON: count = 12
		Kind.ASH: count = 14
		Kind.THUNDER: count = 10
		Kind.ERUPTION: count = 12
		Kind.CHAOS: count = 12
		Kind.DEBUFF: count = 8
		Kind.HEAL: count = 8
	for i in count:
		_parts.append(Part.new())

## Ein gewürfeltes Partikel: Richtung, Tempo, Größe, seitlicher Versatz, Drehung und Startverzögerung
class Part:
	var angle := randf() * TAU
	var speed := randf_range(0.6, 1.0)
	var size := randf_range(0.6, 1.0)
	var offset := randf_range(-1.0, 1.0)
	var spin := randf_range(-1.0, 1.0)
	var delay := randf() * 0.25

# ─────────────────────────
# Physischer Treffer: zwei Hiebe quer über das Monster, außen in der Akzentfarbe, innen weiß, dazu Funken

func _draw_slash(t: float) -> void:
	var r := radius
	_draw_slash_line(t, Vector2(0.75 * r * _flip, -0.8 * r), Vector2(-0.75 * r * _flip, 0.8 * r), r * 0.16)
	_draw_slash_line(clampf(t * 1.25 - 0.18, 0.0, 1.0), Vector2(0.95 * r * _flip, -0.35 * r), Vector2(-0.3 * r * _flip, 0.95 * r), r * 0.09)
	# Funken in der Mitte, sobald der Hieb durch ist
	if t > 0.25:
		var s := (t - 0.25) / 0.75
		for p: Part in _parts:
			var dir := Vector2.from_angle(p.angle)
			var a := r * (0.1 + 0.6 * s * p.speed)
			var b := a + r * 0.18 * (1.0 - s)
			draw_line(dir * a, dir * b, Color(1, 1, 1, 1.0 - s), 2.0 * p.size + 1.0, true)

## Ein sichelförmiger Hieb von a nach b: die Spitze läuft vorneweg, das Ende folgt, danach verblasst er.
func _draw_slash_line(t: float, a: Vector2, b: Vector2, width: float) -> void:
	if t <= 0.0:
		return
	var head := clampf(t / 0.45, 0.0, 1.0)
	var tail := clampf((t - 0.3) / 0.6, 0.0, 1.0)
	if head - tail < 0.02:
		return
	var alpha := 1.0 - clampf((t - 0.6) / 0.4, 0.0, 1.0)
	var normal := (b - a).orthogonal().normalized()
	var bend := (b - a).length() * 0.12
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var steps := 14
	for i in steps + 1:
		var u := lerpf(tail, head, float(i) / steps)
		var center := a.lerp(b, u) + normal * sin(PI * u) * bend
		var w := width * sin(PI * float(i) / steps)
		left.append(center + normal * w)
		right.append(center - normal * w * 0.4)
	right.reverse()
	var glow := color
	glow.a = 0.55 * alpha
	_draw_poly(_scaled_strip(left, right, 1.6), glow)
	_draw_poly(left + right, Color(1, 1, 1, alpha))

## Verbreitert ein Band aus zwei Rändern um factor (für den farbigen Schein hinter dem Hieb)
func _scaled_strip(left: PackedVector2Array, right: PackedVector2Array, factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := left.size()
	for i in n:
		var mid := (left[i] + right[n - 1 - i]) / 2.0
		out.append(mid + (left[i] - mid) * factor)
	for i in n:
		var mid := (right[i] + left[n - 1 - i]) / 2.0
		out.append(mid + (right[i] - mid) * factor)
	return out

# ─────────────────────────
# Feuer: heller Blitz, Feuerball, fliegende Glut und etwas Rauch

func _draw_fire(t: float) -> void:
	var r := radius
	# Rauchring zum Schluss
	if t > 0.35:
		var s := (t - 0.35) / 0.65
		draw_circle(Vector2(0, -r * 0.15 * s), r * (0.55 + 0.35 * s), Color(0.25, 0.22, 0.2, 0.35 * (1.0 - s)))
	# Feuerball: wächst schnell und fällt dann in sich zusammen
	var grow := _ease_out(clampf(t / 0.3, 0.0, 1.0))
	var shrink := clampf((t - 0.3) / 0.6, 0.0, 1.0)
	var ball := r * 0.75 * grow * (1.0 - 0.6 * shrink)
	var fade := 1.0 - shrink
	if ball > 0.0:
		draw_circle(Vector2.ZERO, ball, _with_alpha(FIRE_COLORS[2], 0.85 * fade))
		draw_circle(Vector2(0, -ball * 0.08), ball * 0.72, _with_alpha(FIRE_COLORS[1], 0.95 * fade))
		draw_circle(Vector2(0, -ball * 0.12), ball * 0.42, _with_alpha(FIRE_COLORS[0], fade))
	# Blitz am Anfang
	if t < 0.18:
		draw_circle(Vector2.ZERO, r * (0.4 + t * 2.0), Color(1, 1, 0.85, 0.7 * (1.0 - t / 0.18)))
	# Glut fliegt nach außen und steigt leicht auf
	for p: Part in _parts:
		var s := clampf((t - p.delay * 0.4) / 0.85, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var dir := Vector2.from_angle(p.angle)
		var pos := dir * r * (0.2 + 0.95 * _ease_out(s) * p.speed) + Vector2(0, -r * 0.35 * s * s)
		var c: Color = FIRE_COLORS[0].lerp(FIRE_COLORS[2], s)
		draw_circle(pos, r * 0.07 * p.size * (1.0 - s), _with_alpha(c, 1.0 - s * 0.6))

# ─────────────────────────
# Wasser: Wellenringe und Tropfen, die hochspritzen und wieder fallen

func _draw_water(t: float) -> void:
	var r := radius
	for i in 2:
		var s := clampf((t - i * 0.18) / 0.7, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var ring := r * (0.25 + 0.8 * _ease_out(s))
		_draw_ellipse_arc(Vector2(0, r * 0.25), ring, ring * 0.45, _with_alpha(WATER_COLOR, 0.9 * (1.0 - s)), r * 0.06 * (1.0 - s) + 1.5)
	# kurzer Platscher in der Mitte
	if t < 0.3:
		var s := t / 0.3
		draw_circle(Vector2(0, r * 0.1), r * 0.45 * _ease_out(s), Color(0.75, 0.9, 1.0, 0.6 * (1.0 - s)))
	for p: Part in _parts:
		var s := clampf((t - p.delay * 0.3) / 0.9, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		# Wurfparabel: seitlich nach außen, erst hoch, dann runter
		var side: float = p.offset
		var up: float = 1.6 * p.speed
		var pos := Vector2(side * r * 0.9 * s, r * 0.15 - up * r * s + 2.2 * r * s * s)
		var drop := r * 0.07 * p.size * (1.0 - s * 0.5)
		draw_circle(pos, drop, _with_alpha(WATER_COLOR.lightened(0.25 * p.size), 1.0 - s * s))
		draw_circle(pos + Vector2(-drop * 0.3, -drop * 0.3), drop * 0.35, Color(1, 1, 1, 0.7 * (1.0 - s)))

# ─────────────────────────
# Erde: Steinbrocken krachen herab und zerspringen, Staubwolke am Boden

func _draw_earth(t: float) -> void:
	var r := radius
	# Staubwolke
	if t > 0.2:
		var s := (t - 0.2) / 0.8
		for i in 3:
			var x := (i - 1) * r * 0.45 * (0.6 + s)
			draw_circle(Vector2(x, r * 0.55), r * (0.25 + 0.3 * s), _with_alpha(DUST_COLOR, 0.28 * (1.0 - s)))
	# großer Brocken fällt von oben auf das Monster
	if t < 0.25:
		var s := t / 0.25
		var pos := Vector2(r * 0.2 * _flip, lerpf(-r * 1.4, 0.0, s * s))
		_draw_rock(pos, r * 0.32, s * 1.5, EARTH_COLORS[0])
	# danach Splitter in alle Richtungen
	else:
		var s := (t - 0.25) / 0.75
		for p: Part in _parts:
			var dir := Vector2(cos(p.angle), -absf(sin(p.angle)))
			var pos := dir * r * 0.9 * p.speed * _ease_out(s) + Vector2(0, r * 1.2 * s * s)
			var c: Color = EARTH_COLORS[int(p.size * 10) % EARTH_COLORS.size()]
			_draw_rock(pos, r * 0.11 * p.size * (1.0 - s * 0.4), p.spin * 6.0 * s, _with_alpha(c, 1.0 - s * s))
		# Aufprall-Blitz
		if s < 0.25:
			draw_circle(Vector2.ZERO, r * 0.5 * (1.0 + s), Color(1, 0.95, 0.8, 0.5 * (1.0 - s / 0.25)))

func _draw_rock(pos: Vector2, size: float, rot: float, c: Color) -> void:
	var points := PackedVector2Array()
	for i in 5:
		var a := rot + i * TAU / 5.0
		var d := size * (0.75 + 0.25 * sin(i * 2.3))
		points.append(pos + Vector2.from_angle(a) * d)
	_draw_poly(points, c)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, c.darkened(0.45), maxf(1.0, size * 0.12), true)

# ─────────────────────────
# Luft: Windböen wirbeln um das Monster und ziehen sich zusammen

func _draw_air(t: float) -> void:
	var r := radius
	var alpha := sin(PI * t)
	for i in _parts.size():
		var p: Part = _parts[i]
		var ring := r * (1.0 - 0.45 * t) * (0.55 + 0.45 * p.size)
		var start: float = p.angle + _flip * t * TAU * 1.1 * p.speed
		var arc := PI * (0.5 + 0.35 * p.speed)
		var y := (float(i) / maxf(1.0, _parts.size() - 1) - 0.5) * r * 0.9
		_draw_ellipse_arc(Vector2(0, y), ring, ring * 0.35, _with_alpha(AIR_COLOR, 0.85 * alpha), r * 0.05 + 1.0, start, arc)
	# kurze Windlinien
	for i in 4:
		var s := clampf(t * 1.4 - i * 0.12, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var y := (i - 1.5) * r * 0.35
		var x := lerpf(-r * 1.1, r * 1.1, s) * _flip
		draw_line(Vector2(x - r * 0.35 * _flip, y), Vector2(x, y), Color(1, 1, 1, 0.7 * sin(PI * s)), 2.0, true)

# ─────────────────────────
# Physischer Schild: blaues Sechseck springt auf, ein Glanz läuft darüber, dann verblasst es

func _draw_shield(t: float) -> void:
	var r := radius * 1.05
	var pop := _ease_back(clampf(t / 0.35, 0.0, 1.0))
	var alpha := 1.0 - clampf((t - 0.6) / 0.4, 0.0, 1.0)
	var size := r * (0.6 + 0.4 * pop)
	var hex := _polygon(Vector2.ZERO, size, 6, PI / 6.0)
	_draw_poly(hex, _with_alpha(SHIELD_COLOR, 0.22 * alpha))
	# inneres Wabenmuster
	for i in 6:
		var a := PI / 6.0 + i * TAU / 6.0
		draw_line(Vector2.ZERO, Vector2.from_angle(a) * size, _with_alpha(SHIELD_COLOR, 0.25 * alpha), 1.5, true)
	_draw_closed(_polygon(Vector2.ZERO, size * 0.5, 6, PI / 6.0), _with_alpha(SHIELD_COLOR, 0.35 * alpha), 1.5)
	_draw_closed(hex, _with_alpha(SHIELD_COLOR.lightened(0.3), alpha), r * 0.06 + 1.0)
	# Glanz läuft von links oben nach rechts unten
	var sweep := clampf((t - 0.2) / 0.4, 0.0, 1.0)
	if sweep > 0.0 and sweep < 1.0:
		var x := lerpf(-size, size, sweep)
		var dir := Vector2(1, -1).normalized() * size * 0.35
		draw_line(Vector2(x, 0) - dir, Vector2(x, 0) + dir, Color(1, 1, 1, 0.8 * sin(PI * sweep)), r * 0.07, true)

# Magischer Schild: violetter Runenkreis dreht sich, Kugel leuchtet auf, Funken steigen auf

func _draw_s_shield(t: float) -> void:
	var r := radius * 1.05
	var pop := _ease_back(clampf(t / 0.35, 0.0, 1.0))
	var alpha := 1.0 - clampf((t - 0.6) / 0.4, 0.0, 1.0)
	var size := r * (0.55 + 0.45 * pop)
	var rot := t * PI * 1.2
	draw_circle(Vector2.ZERO, size, _with_alpha(S_SHIELD_COLOR, 0.18 * alpha))
	draw_arc(Vector2.ZERO, size, 0, TAU, 48, _with_alpha(S_SHIELD_COLOR.lightened(0.3), alpha), r * 0.05 + 1.0, true)
	draw_arc(Vector2.ZERO, size * 0.82, 0, TAU, 48, _with_alpha(S_SHIELD_COLOR, 0.6 * alpha), 1.5, true)
	# Runen: kleine Rauten, die sich im Ring drehen
	for i in 6:
		var a := rot + i * TAU / 6.0
		var c := Vector2.from_angle(a) * size * 0.91
		_draw_poly(_polygon(c, r * 0.07, 4, a), _with_alpha(Color.WHITE, alpha))
	# Hexagramm in der Mitte, gegenläufig
	_draw_closed(_polygon(Vector2.ZERO, size * 0.6, 3, -rot), _with_alpha(S_SHIELD_COLOR, 0.45 * alpha), 1.5)
	_draw_closed(_polygon(Vector2.ZERO, size * 0.6, 3, -rot + PI), _with_alpha(S_SHIELD_COLOR, 0.45 * alpha), 1.5)
	for p: Part in _parts:
		var s := clampf((t - p.delay) / 0.75, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var pos := Vector2(p.offset * size * 0.8, size * 0.5 - s * size * 1.3 * p.speed)
		_draw_sparkle(pos, r * 0.06 * p.size, Color(1, 0.9, 1, sin(PI * s)))

# ─────────────────────────
# Schildtreffer: der Schild blitzt kurz am Einschlag auf und bekommt Risse

func _draw_shield_hit(t: float, c: Color, round: bool) -> void:
	var r := radius * 1.05
	var alpha := 1.0 - t
	var size := r * (1.0 + 0.08 * t)
	if round:
		draw_circle(Vector2.ZERO, size, _with_alpha(c, 0.25 * alpha))
		draw_arc(Vector2.ZERO, size, 0, TAU, 48, _with_alpha(c.lightened(0.4), alpha), r * 0.06 + 1.0, true)
	else:
		var hex := _polygon(Vector2.ZERO, size, 6, PI / 6.0)
		_draw_poly(hex, _with_alpha(c, 0.25 * alpha))
		_draw_closed(hex, _with_alpha(c.lightened(0.4), alpha), r * 0.06 + 1.0)
	# Einschlagstelle oben, Risse laufen davon weg
	var hit := Vector2(r * 0.25 * _flip, -size * 0.55)
	draw_circle(hit, r * 0.25 * (0.5 + t), Color(1, 1, 1, 0.8 * alpha))
	for p: Part in _parts:
		var dir := Vector2.from_angle(PI / 2.0 + p.offset * 1.2)
		var mid := hit + dir * r * 0.25 * p.speed + dir.orthogonal() * r * 0.08 * p.spin
		var end := hit + dir * r * 0.5 * p.speed * minf(1.0, t * 3.0)
		draw_polyline(PackedVector2Array([hit, mid, end]), Color(1, 1, 1, alpha), 2.0, true)

# ─────────────────────────
# Buff: grüne Pfeile und Funken steigen am Monster auf

func _draw_buff(t: float) -> void:
	var r := radius
	draw_circle(Vector2(0, r * 0.2), r * 0.8, _with_alpha(BUFF_COLOR, 0.15 * sin(PI * t)))
	for i in 3:
		var s := clampf((t - i * 0.15) / 0.7, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var x := (i - 1) * r * 0.5
		var y := lerpf(r * 0.6, -r * 0.8, _ease_out(s))
		var w := r * 0.2
		var a := sin(PI * s)
		draw_polyline(PackedVector2Array([Vector2(x - w, y + w * 0.7), Vector2(x, y), Vector2(x + w, y + w * 0.7)]),
			_with_alpha(BUFF_COLOR, a), r * 0.08 + 1.0, true)
	for p: Part in _parts:
		var s := clampf((t - p.delay) / 0.75, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var pos := Vector2(p.offset * r * 0.8, r * 0.7 - s * r * 1.5 * p.speed)
		_draw_sparkle(pos, r * 0.05 * p.size, _with_alpha(BUFF_COLOR.lightened(0.4), sin(PI * s)))

# ─────────────────────────
# Dampf: weiße Wolken quellen auf und ziehen nach oben, dazu zischende Strahlen

func _draw_steam(t: float) -> void:
	var r := radius
	for p: Part in _parts:
		var s := clampf((t - p.delay * 0.5) / 0.85, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var pos := Vector2(p.offset * r * 0.7, r * 0.3 - s * r * 1.1 * p.speed)
		var size := r * (0.18 + 0.28 * _ease_out(s)) * p.size
		draw_circle(pos, size, _with_alpha(STEAM_COLOR, 0.55 * sin(PI * s)))
		draw_circle(pos + Vector2(-size * 0.3, -size * 0.25), size * 0.55, _with_alpha(Color.WHITE, 0.4 * sin(PI * s)))
	# Zischen: kurze Strahlen schräg nach außen
	if t < 0.45:
		var s := t / 0.45
		for i in 4:
			var dir := Vector2.from_angle(-PI / 2.0 + (i - 1.5) * 0.45)
			draw_line(dir * r * 0.2, dir * r * (0.35 + 0.6 * s), Color(1, 1, 1, 0.7 * (1.0 - s)), 2.0, true)

# Blitz: gezackter Strahl von oben ins Monster, greller Blitz und Funken

func _draw_lightning(t: float) -> void:
	var r := radius
	if t < 0.55:
		var alpha := 1.0 - t / 0.55
		var points := PackedVector2Array()
		var steps := 7
		for i in steps + 1:
			var u := float(i) / steps
			var jag := 0.0 if i == 0 or i == steps else _parts[i % _parts.size()].offset * r * 0.22
			points.append(Vector2(jag * _flip, lerpf(-r * 1.5, 0.0, u)))
		draw_polyline(points, _with_alpha(LIGHTNING_COLOR, 0.6 * alpha), r * 0.14, true)
		draw_polyline(points, Color(1, 1, 1, alpha), r * 0.05 + 1.0, true)
	if t < 0.2:
		draw_circle(Vector2.ZERO, r * (0.5 + t * 2.0), Color(1, 1, 0.8, 0.6 * (1.0 - t / 0.2)))
	for p: Part in _parts:
		var s := clampf((t - 0.1 - p.delay * 0.3) / 0.6, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var dir := Vector2.from_angle(p.angle)
		var a := r * (0.15 + 0.7 * s * p.speed)
		var mid := dir * (a + r * 0.06) + dir.orthogonal() * r * 0.06 * p.spin
		draw_polyline(PackedVector2Array([dir * a, mid, dir * (a + r * 0.14)]), _with_alpha(LIGHTNING_COLOR, 1.0 - s), 2.0, true)

# Magma: glühende Lavaklumpen spritzen und kühlen zu dunkler Kruste ab, der Boden glüht

func _draw_magma(t: float) -> void:
	var r := radius
	draw_circle(Vector2(0, r * 0.35), r * 0.7 * _ease_out(clampf(t / 0.3, 0.0, 1.0)), _with_alpha(MAGMA_COLORS[1], 0.35 * (1.0 - t)))
	for p: Part in _parts:
		var s := clampf((t - p.delay * 0.4) / 0.85, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var pos := Vector2(p.offset * r * 0.9 * s, r * 0.2 - 1.3 * p.speed * r * s + 2.0 * r * s * s)
		var c: Color = (MAGMA_COLORS[0] as Color).lerp(MAGMA_COLORS[2], s)
		var size := r * 0.1 * p.size
		draw_circle(pos, size, _with_alpha(c, 1.0 - s * 0.4))
		draw_circle(pos, size * 0.5, _with_alpha(MAGMA_COLORS[0], 0.8 * (1.0 - s)))

# Eis: Eissplitter schießen sternförmig heraus, ein Frostring legt sich um das Monster

func _draw_ice(t: float) -> void:
	var r := radius
	var ring := _ease_out(clampf(t / 0.4, 0.0, 1.0))
	var alpha := 1.0 - clampf((t - 0.5) / 0.5, 0.0, 1.0)
	_draw_closed(_polygon(Vector2.ZERO, r * 0.75 * ring, 6, 0.0), _with_alpha(ICE_COLOR, 0.8 * alpha), 2.0)
	for p: Part in _parts:
		var s := clampf((t - p.delay * 0.3) / 0.7, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var dir := Vector2.from_angle(p.angle)
		var center := dir * r * (0.15 + 0.8 * _ease_out(s) * p.speed)
		var length := r * 0.2 * p.size
		var width := length * 0.3
		var shard := PackedVector2Array([center + dir * length, center + dir.orthogonal() * width,
			center - dir * length * 0.4, center - dir.orthogonal() * width])
		_draw_poly(shard, _with_alpha(ICE_COLOR, 1.0 - s * s))
		_draw_closed(shard, _with_alpha(Color.WHITE, 0.8 * (1.0 - s)), 1.0)

# Staub: Sandkörner wirbeln in einer Spirale um das Monster, dazu ein bräunlicher Schleier

func _draw_dust(t: float) -> void:
	var r := radius
	draw_circle(Vector2(0, r * 0.2), r * 0.85, _with_alpha(DUST_COLOR, 0.2 * sin(PI * t)))
	for p: Part in _parts:
		var a: float = p.angle + _flip * t * TAU * 1.3 * p.speed
		var dist := r * (0.9 - 0.5 * t) * (0.5 + 0.5 * p.size)
		var pos := Vector2(cos(a) * dist, sin(a) * dist * 0.45 + p.offset * r * 0.4)
		draw_circle(pos, r * 0.035 * p.size + 1.0, _with_alpha(DUST_COLOR.darkened(0.2 * p.size), sin(PI * t)))
	_draw_ellipse_arc(Vector2.ZERO, r * (1.0 - 0.4 * t), r * 0.35, _with_alpha(DUST_COLOR, 0.6 * sin(PI * t)), 2.0,
		_flip * t * TAU, PI * 1.2)

# Schlamm: zähe Klumpen klatschen gegen das Monster und rutschen ab

func _draw_mud(t: float) -> void:
	var r := radius
	for p: Part in _parts:
		var s := clampf((t - p.delay * 0.3) / 0.8, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var start := Vector2.from_angle(p.angle) * r * 0.25
		var pos := start + Vector2(p.offset * r * 0.5 * s, r * 0.9 * s * s)
		var c: Color = MUD_COLORS[int(p.size * 10) % MUD_COLORS.size()]
		var size := r * 0.13 * p.size * (1.0 + 0.3 * s)
		draw_circle(pos, size, _with_alpha(c, 1.0 - s * s))
		draw_circle(pos + Vector2(size * 0.6, -size * 0.2), size * 0.5, _with_alpha(c, 0.8 * (1.0 - s)))
	if t < 0.3:
		draw_circle(Vector2.ZERO, r * 0.45 * _ease_out(t / 0.3), _with_alpha(MUD_COLORS[0], 0.5 * (1.0 - t / 0.3)))

# Sumpf (Gift): giftgrüne Blasen steigen auf und platzen, eine Giftwolke hängt über dem Monster

func _draw_poison(t: float) -> void:
	var r := radius
	draw_circle(Vector2(0, -r * 0.1), r * 0.8, _with_alpha(POISON_COLOR.darkened(0.3), 0.22 * sin(PI * t)))
	for p: Part in _parts:
		var s := clampf((t - p.delay) / 0.75, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var pos := Vector2(p.offset * r * 0.7 + sin(s * 6.0 + p.spin * 3.0) * r * 0.05, r * 0.6 - s * r * 1.3 * p.speed)
		var size := r * 0.07 * p.size * (0.6 + s)
		if s < 0.85:
			draw_arc(pos, size, 0, TAU, 16, _with_alpha(POISON_COLOR, 0.9), 2.0, true)
			draw_circle(pos + Vector2(-size * 0.3, -size * 0.3), size * 0.25, Color(1, 1, 1, 0.7))
		else:
			# Blase platzt: kleiner Spritzer
			for i in 4:
				var dir := Vector2.from_angle(i * TAU / 4.0 + p.angle)
				draw_line(pos + dir * size, pos + dir * size * 1.8, _with_alpha(POISON_COLOR, 1.0 - (s - 0.85) / 0.15), 1.5, true)

# Aschesturm (Verbrennung): dunkle Aschewolke, aus der Glut aufsteigt

func _draw_ash(t: float) -> void:
	var r := radius
	for i in 3:
		var s := clampf(t * 1.2 - i * 0.12, 0.0, 1.0)
		var x := (i - 1) * r * 0.45
		draw_circle(Vector2(x, -r * 0.1 - s * r * 0.3), r * (0.3 + 0.25 * s), _with_alpha(ASH_COLOR, 0.45 * sin(PI * s)))
	for p: Part in _parts:
		var s := clampf((t - p.delay) / 0.75, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var pos := Vector2(p.offset * r * 0.8 + sin(s * 5.0 + p.spin) * r * 0.08, r * 0.5 - s * r * 1.4 * p.speed)
		var c: Color = FIRE_COLORS[0].lerp(FIRE_COLORS[2], s)
		draw_circle(pos, r * 0.035 * p.size + 1.0, _with_alpha(c, 1.0 - s))

# Gewitter (Lähmung): dunkle Wolke über dem Monster, Regen und ein Blitz hinein

func _draw_thunder(t: float) -> void:
	var r := radius
	var alpha := sin(PI * t)
	var cloud_y := -r * 0.95
	for i in 3:
		draw_circle(Vector2((i - 1) * r * 0.35, cloud_y + absf(i - 1) * r * 0.08), r * 0.3, _with_alpha(STORM_CLOUD_COLOR, 0.85 * alpha))
	for p: Part in _parts:
		var s := fmod(t * 2.0 * p.speed + p.delay, 1.0)
		var x := p.offset * r * 0.6
		var y := lerpf(cloud_y + r * 0.2, r * 0.5, s)
		draw_line(Vector2(x, y), Vector2(x - r * 0.04, y + r * 0.12), _with_alpha(Color(0.7, 0.8, 1.0), 0.7 * alpha), 1.5, true)
	if t > 0.25 and t < 0.6:
		var s := (t - 0.25) / 0.35
		var points := PackedVector2Array([Vector2(0, cloud_y + r * 0.2), Vector2(r * 0.15 * _flip, -r * 0.45),
			Vector2(-r * 0.05 * _flip, -r * 0.3), Vector2(r * 0.1 * _flip, 0)])
		draw_polyline(points, _with_alpha(LIGHTNING_COLOR, 1.0 - s), r * 0.08 + 1.0, true)
		draw_circle(Vector2.ZERO, r * 0.4, Color(1, 1, 0.8, 0.4 * (1.0 - s)))

# Vulkan (Ausbruch): eine Lavasäule schießt hoch, Gesteinsbrocken und Glut fliegen heraus

func _draw_eruption(t: float) -> void:
	var r := radius
	var up := _ease_out(clampf(t / 0.35, 0.0, 1.0))
	var fade := 1.0 - clampf((t - 0.45) / 0.55, 0.0, 1.0)
	var column := PackedVector2Array([Vector2(-r * 0.35, r * 0.5), Vector2(-r * 0.12, r * 0.5 - r * 1.5 * up),
		Vector2(r * 0.12, r * 0.5 - r * 1.5 * up), Vector2(r * 0.35, r * 0.5)])
	_draw_poly(column, _with_alpha(MAGMA_COLORS[1], 0.8 * fade))
	_draw_poly(_scaled_strip(PackedVector2Array([column[0], column[1]]), PackedVector2Array([column[2], column[3]]), 0.5),
		_with_alpha(MAGMA_COLORS[0], fade))
	for p: Part in _parts:
		var s := clampf((t - 0.15 - p.delay * 0.3) / 0.7, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var pos := Vector2(p.offset * r * 1.1 * s, -r * 0.9 - 0.8 * p.speed * r * s + 2.2 * r * s * s)
		if p.size > 0.8:
			_draw_rock(pos, r * 0.09, p.spin * 5.0 * s, _with_alpha(EARTH_COLORS[1], 1.0 - s * s))
		else:
			draw_circle(pos, r * 0.06 * p.size, _with_alpha((MAGMA_COLORS[0] as Color).lerp(MAGMA_COLORS[1], s), 1.0 - s))

# Chaos: Ringe in den vier Elementfarben drehen sich gegeneinander, dazu ein Sternenblitz

func _draw_chaos(t: float) -> void:
	var r := radius
	var alpha := sin(PI * t)
	for i in CHAOS_COLORS.size():
		var rot := (t * TAU * (1.0 + i * 0.3)) * (1.0 if i % 2 == 0 else -1.0)
		var size := r * (0.45 + i * 0.15) * (0.6 + 0.4 * _ease_out(clampf(t / 0.4, 0.0, 1.0)))
		draw_arc(Vector2.ZERO, size, rot, rot + PI * 1.3, 32, _with_alpha(CHAOS_COLORS[i], 0.9 * alpha), r * 0.05 + 1.0, true)
	for p: Part in _parts:
		var s := clampf((t - p.delay) / 0.7, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var pos := Vector2.from_angle(p.angle) * r * (0.2 + 0.9 * _ease_out(s) * p.speed)
		_draw_sparkle(pos, r * 0.05 * p.size, _with_alpha(CHAOS_COLORS[int(p.size * 10) % CHAOS_COLORS.size()].lightened(0.3), 1.0 - s))

# Schwächung: rote Pfeile sinken am Monster herab

func _draw_debuff(t: float) -> void:
	var r := radius
	draw_circle(Vector2(0, r * 0.2), r * 0.8, _with_alpha(DEBUFF_COLOR, 0.12 * sin(PI * t)))
	for i in 3:
		var s := clampf((t - i * 0.15) / 0.7, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var x := (i - 1) * r * 0.5
		var y := lerpf(-r * 0.8, r * 0.6, _ease_out(s))
		var w := r * 0.2
		draw_polyline(PackedVector2Array([Vector2(x - w, y - w * 0.7), Vector2(x, y), Vector2(x + w, y - w * 0.7)]),
			_with_alpha(DEBUFF_COLOR, sin(PI * s)), r * 0.08 + 1.0, true)

# Heilung: grüne Kreuze steigen auf, ein weiches Leuchten

func _draw_heal(t: float) -> void:
	var r := radius
	draw_circle(Vector2(0, r * 0.1), r * 0.85, _with_alpha(HEAL_COLOR, 0.18 * sin(PI * t)))
	for p: Part in _parts:
		var s := clampf((t - p.delay) / 0.75, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var pos := Vector2(p.offset * r * 0.7, r * 0.6 - s * r * 1.3 * p.speed)
		var size := r * 0.08 * p.size
		var c := _with_alpha(HEAL_COLOR, sin(PI * s))
		draw_line(pos - Vector2(size, 0), pos + Vector2(size, 0), c, size * 0.6 + 1.0, true)
		draw_line(pos - Vector2(0, size), pos + Vector2(0, size), c, size * 0.6 + 1.0, true)

# ─────────────────────────
# Hilfen

func _draw_poly(points: PackedVector2Array, c: Color) -> void:
	if points.size() < 3 or c.a <= 0.0:
		return
	# ungültige (z. B. sich selbst schneidende) Polygone wirft Godot weg, statt abzustürzen
	if Geometry2D.triangulate_polygon(points).is_empty():
		return
	draw_colored_polygon(points, c)

func _draw_closed(points: PackedVector2Array, c: Color, width: float) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, c, width, true)

func _polygon(center: Vector2, size: float, corners: int, rot: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in corners:
		points.append(center + Vector2.from_angle(rot + i * TAU / corners) * size)
	return points

func _draw_ellipse_arc(center: Vector2, rx: float, ry: float, c: Color, width: float, start := 0.0, arc := TAU) -> void:
	var points := PackedVector2Array()
	var steps := 32
	for i in steps + 1:
		var a := start + arc * float(i) / steps
		points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(points, c, width, true)

## Vierzackiger Glitzer-Stern
func _draw_sparkle(pos: Vector2, size: float, c: Color) -> void:
	_draw_poly(PackedVector2Array([pos + Vector2(0, -size * 2), pos + Vector2(size * 0.4, 0),
		pos + Vector2(0, size * 2), pos + Vector2(-size * 0.4, 0)]), c)
	_draw_poly(PackedVector2Array([pos + Vector2(-size * 2, 0), pos + Vector2(0, -size * 0.4),
		pos + Vector2(size * 2, 0), pos + Vector2(0, size * 0.4)]), c)

func _with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0))

func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)

func _ease_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
