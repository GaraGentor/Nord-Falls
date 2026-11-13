extends Node2D

## Kurze Effekte über einem Monster im Kampf (siehe MonsterScene._play_skill_vfx), im Stil gezeichneter Anime-VFX:
## spitze, geschwungene Formen (Flammenzungen, Spritzerkronen, Kristalle, Windsicheln, Blitze) mit hellem Kern und
## weichem Schein, dazu echte Partikel (CPUParticles2D) für Funken, Glut, Tropfen, Brocken und Rauch.
## Alles wird in den SubViewport von battle_vfx_layer.gd gezeichnet, dessen Bild der "Lebende Pixel"-Shader zeigt:
## Formen und Partikel zerfallen dort wie die Monster in zitternde, geditherte Pixel.
##
## Physische Treffer als Hieb, magische Treffer je Element (Flammenausbruch, Wasserkrone, Erdspritzer, Windhose),
## Kombi-Elemente mit eigenem Treffer (Dampfwolken, Blitzeinschlag, Lavaspritzer, Eiskristall, Staub-Schockwelle,
## Schlammkrone, Giftsumpf, Aschesturm, Gewitter-Wirbel, Vulkan-Explosion, Chaos-Fluch), Schilde, Schildtreffer,
## Buff, Schwächung und Heilung. Jeder Effekt zeichnet sich in _draw aus seinem Fortschritt (0..1), startet seine
## Partikelstöße zu festen Zeitpunkten und löscht sich, sobald alles vorbei ist.

enum Kind { SLASH, FIRE, WATER, EARTH, AIR, SHIELD, S_SHIELD, SHIELD_HIT, S_SHIELD_HIT, BUFF,
	STEAM, LIGHTNING, MAGMA, ICE, DUST, MUD, POISON, ASH, THUNDER, ERUPTION, CHAOS, DEBUFF, HEAL }

const DURATIONS := {
	Kind.SLASH: 0.42,
	Kind.FIRE: 0.8,
	Kind.WATER: 0.8,
	Kind.EARTH: 0.8,
	Kind.AIR: 0.8,
	Kind.SHIELD: 0.75,
	Kind.S_SHIELD: 0.85,
	Kind.SHIELD_HIT: 0.4,
	Kind.S_SHIELD_HIT: 0.4,
	Kind.BUFF: 0.8,
	Kind.STEAM: 0.9,
	Kind.LIGHTNING: 0.6,
	Kind.MAGMA: 0.8,
	Kind.ICE: 0.85,
	Kind.DUST: 0.8,
	Kind.MUD: 0.8,
	Kind.POISON: 0.9,
	Kind.ASH: 0.9,
	Kind.THUNDER: 0.9,
	Kind.ERUPTION: 0.9,
	Kind.CHAOS: 1.0,
	Kind.DEBUFF: 0.8,
	Kind.HEAL: 0.8,
}

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

## Höhe des "Bodens" unter dem Monster in Radien (Spritzer, Krater, Bodenzeichen)
const GROUND := 0.6

const FIRE_COLORS := [Color(0.55, 0.07, 0.03), Color(1.0, 0.45, 0.08), Color(1.0, 0.82, 0.25), Color(1.0, 1.0, 0.8)]
const WATER_COLORS := [Color(0.16, 0.42, 0.6), Color(0.28, 0.66, 0.85), Color(0.6, 0.88, 0.97), Color(1, 1, 1)]
const EARTH_COLORS := [Color(0.34, 0.19, 0.1), Color(0.5, 0.3, 0.16), Color(0.68, 0.46, 0.27)]
const DUST_COLOR := Color(0.82, 0.72, 0.58)
const AIR_COLORS := [Color(0.15, 0.8, 0.7), Color(0.85, 1.0, 0.97)]
const STEAM_COLORS := [Color(0.72, 0.77, 0.82), Color(0.97, 0.98, 1.0)]
const LIGHTNING_COLOR := Color(1.0, 0.88, 0.25)
const MAGMA_COLORS := [Color(0.9, 0.25, 0.04), Color(1.0, 0.55, 0.08), Color(1.0, 0.85, 0.2), Color(1.0, 0.98, 0.65)]
const ICE_COLORS := [Color(0.35, 0.6, 1.0), Color(0.6, 0.82, 1.0), Color(0.88, 0.96, 1.0)]
const MUD_COLORS := [Color(0.22, 0.14, 0.08), Color(0.4, 0.26, 0.14), Color(0.56, 0.39, 0.23), Color(0.76, 0.6, 0.4)]
const SWAMP_COLORS := [Color(0.18, 0.2, 0.09), Color(0.31, 0.3, 0.13), Color(0.47, 0.47, 0.19), Color(0.72, 0.7, 0.42)]
const POISON_COLOR := Color(0.6, 0.95, 0.3)
const ASH_COLOR := Color(0.3, 0.27, 0.27)
const STORM_COLORS := [Color(0.25, 0.5, 1.0), Color(0.85, 0.93, 1.0)]
const CHAOS_COLORS := [Color(0.62, 0.32, 1.0), Color(0.32, 0.28, 0.38), Color(0.88, 0.72, 1.0)]
const SHIELD_COLOR := Color(0.55, 0.8, 1.0)
const S_SHIELD_COLOR := Color(0.85, 0.6, 1.0)
const BUFF_COLOR := Color(0.55, 1.0, 0.55)
const DEBUFF_COLOR := Color(1.0, 0.4, 0.35)
const HEAL_COLOR := Color(0.5, 1.0, 0.6)

## Gemeinsame Partikel- und Schein-Texturen, beim ersten Gebrauch erzeugt
static var _textures := {}

var kind: Kind
var radius: float
## Akzentfarbe, z. B. das Element eines physischen Hiebs
var color: Color
var _duration: float
var _time := 0.0
var _delay := 0.0
## beim Start gewürfelte Formen (Richtung, Tempo, Größe, ...), damit jeder Effekt etwas anders aussieht
var _parts: Array[Part] = []
var _flip := 1.0
var _seed := 0
## geplante Partikelstöße: {"at": Sekunden, "p": Einstellungen}
var _bursts: Array[Dictionary] = []
## Ende des Effekts samt nachfliegender Partikel
var _end := 0.0

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
	_end = _duration
	_flip = -1.0 if randf() < 0.5 else 1.0
	_seed = randi()
	_roll_parts()
	_plan_particles()
	visible = _delay <= 0.0

func _process(delta: float) -> void:
	if _delay > 0.0:
		_delay -= delta
		visible = _delay <= 0.0
		return
	_time += delta
	while not _bursts.is_empty() and _bursts[0].at <= _time:
		_spawn(_bursts.pop_front().p)
	if _time >= _end:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	if _delay > 0.0 or _time >= _duration:
		return
	var t := clampf(_time / _duration, 0.0, 1.0)
	match kind:
		Kind.SLASH: _draw_slash(t)
		Kind.FIRE: _draw_fire(t)
		Kind.WATER: _draw_crown(t, WATER_COLORS)
		Kind.EARTH: _draw_earth(t)
		Kind.AIR: _draw_tornado(t, AIR_COLORS, 1.0)
		Kind.SHIELD: _draw_shield(t)
		Kind.S_SHIELD: _draw_s_shield(t)
		Kind.SHIELD_HIT: _draw_shield_hit(t, SHIELD_COLOR, false)
		Kind.S_SHIELD_HIT: _draw_shield_hit(t, S_SHIELD_COLOR, true)
		Kind.BUFF: _draw_arrows(t, BUFF_COLOR, true)
		Kind.STEAM: _draw_steam(t)
		Kind.LIGHTNING: _draw_lightning(t)
		Kind.MAGMA: _draw_magma(t)
		Kind.ICE: _draw_ice(t)
		Kind.DUST: _draw_dust(t)
		Kind.MUD: _draw_crown(t, MUD_COLORS, 0.9, true)
		Kind.POISON: _draw_crown(t, SWAMP_COLORS, 1.0, true)
		Kind.ASH: _draw_ash(t)
		Kind.THUNDER: _draw_thunder(t)
		Kind.ERUPTION: _draw_eruption(t)
		Kind.CHAOS: _draw_chaos(t)
		Kind.DEBUFF: _draw_arrows(t, DEBUFF_COLOR, false)
		Kind.HEAL: _draw_heal(t)

func _roll_parts() -> void:
	var count := 0
	match kind:
		Kind.FIRE: count = 9
		Kind.WATER, Kind.MUD, Kind.POISON: count = 7
		Kind.EARTH: count = 9
		Kind.AIR: count = 8
		Kind.THUNDER: count = 9
		Kind.S_SHIELD: count = 8
		Kind.SHIELD_HIT, Kind.S_SHIELD_HIT: count = 5
		Kind.STEAM: count = 8
		Kind.LIGHTNING: count = 10
		Kind.MAGMA: count = 8
		Kind.ICE: count = 13
		Kind.DUST: count = 6
		Kind.ASH: count = 6
		Kind.ERUPTION: count = 14
		Kind.CHAOS: count = 8
		Kind.HEAL: count = 7
	for i in count:
		_parts.append(Part.new())

## Eine gewürfelte Form: Richtung, Tempo, Größe, seitlicher Versatz, Drehung und Startverzögerung
class Part:
	var angle := randf() * TAU
	var speed := randf_range(0.6, 1.0)
	var size := randf_range(0.6, 1.0)
	var offset := randf_range(-1.0, 1.0)
	var spin := randf_range(-1.0, 1.0)
	var delay := randf() * 0.25

# ─────────────────────────
# Partikel: Einstellungen in Monster-Radien (Position, Tempo, Größe), Farbverlauf über die Lebenszeit

## Partikelstoß zum Zeitpunkt at (Anteil der Effektdauer) einplanen
func _burst(at: float, p: Dictionary) -> void:
	var start := at * _duration
	_bursts.append({"at": start, "p": p})
	_bursts.sort_custom(func(a: Dictionary, b: Dictionary): return a.at < b.at)
	var life: float = p.get("life", 0.6)
	_end = maxf(_end, start + life * (2.0 - float(p.get("explosive", 0.95))) + 0.05)

func _spawn(p: Dictionary) -> void:
	var r := radius
	var e := CPUParticles2D.new()
	var tex := _texture(p.get("tex", "glow"))
	e.texture = tex
	e.one_shot = true
	e.local_coords = true
	e.amount = p.get("amount", 8)
	e.lifetime = p.get("life", 0.6)
	e.lifetime_randomness = p.get("life_rand", 0.35)
	e.explosiveness = p.get("explosive", 0.95)
	var pos: Vector2 = p.get("pos", Vector2.ZERO)
	e.position = pos * r
	if p.has("box"):
		var box: Vector2 = p.box
		e.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		e.emission_rect_extents = box * r
	elif p.has("sphere"):
		var sphere: float = p.sphere
		e.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE if p.get("surface", false) else CPUParticles2D.EMISSION_SHAPE_SPHERE
		e.emission_sphere_radius = sphere * r
	var dir: Vector2 = p.get("dir", Vector2.UP)
	e.direction = dir
	e.spread = p.get("spread", 45.0)
	var vel: Vector2 = p.get("vel", Vector2(1.0, 2.0))
	e.initial_velocity_min = vel.x * r
	e.initial_velocity_max = vel.y * r
	var gravity: Vector2 = p.get("gravity", Vector2.ZERO)
	e.gravity = gravity * r
	var damping: Vector2 = p.get("damping", Vector2.ZERO)
	e.damping_min = damping.x * r
	e.damping_max = damping.y * r
	var radial: Vector2 = p.get("radial", Vector2.ZERO)
	e.radial_accel_min = radial.x * r
	e.radial_accel_max = radial.y * r
	var orbit: Vector2 = p.get("orbit", Vector2.ZERO)
	e.orbit_velocity_min = orbit.x
	e.orbit_velocity_max = orbit.y
	var spin: Vector2 = p.get("spin", Vector2.ZERO)
	e.angular_velocity_min = spin.x
	e.angular_velocity_max = spin.y
	var angle: Vector2 = p.get("angle", Vector2(0.0, 360.0))
	e.angle_min = angle.x
	e.angle_max = angle.y
	# Größe = längste Seite der Textur in Radien
	var size: Vector2 = p.get("size", Vector2(0.1, 0.2))
	var tex_size := float(maxi(tex.get_width(), tex.get_height()))
	e.scale_amount_min = size.x * r / tex_size
	e.scale_amount_max = size.y * r / tex_size
	e.scale_amount_curve = _curve(p.get("curve", "shrink"))
	e.color_ramp = _ramp(p.get("colors", [Color.WHITE, Color(1, 1, 1, 0)]))
	if p.has("tints"):
		e.color_initial_ramp = _ramp(p.tints)
	e.particle_flag_align_y = p.get("align", false)
	# Rauch hinter den gezeichneten Formen
	if p.get("behind", false):
		e.z_index = -1
	add_child(e)
	e.emitting = true

func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / maxf(1.0, colors.size() - 1))
	g.offsets = offsets
	g.colors = PackedColorArray(colors)
	return g

func _curve(shape: String) -> Curve:
	var c := Curve.new()
	match shape:
		"grow":
			c.add_point(Vector2(0, 0.4))
			c.add_point(Vector2(1, 1))
		"pop":
			c.add_point(Vector2(0, 0.2))
			c.add_point(Vector2(0.2, 1))
			c.add_point(Vector2(1, 0.7))
		"flat":
			c.add_point(Vector2(0, 1))
			c.add_point(Vector2(1, 1))
		_:
			c.add_point(Vector2(0, 1))
			c.add_point(Vector2(1, 0.1))
	return c

## Weiße Grundtexturen, eingefärbt über Partikel- bzw. Zeichenfarbe:
## glow (weicher Schein), dot (Tropfen/Glut), streak (länglicher Funke, mit align entlang der Flugbahn),
## smoke (weicher Rauch), puff (Wolke aus mehreren Kugeln), ring (Blase), chunk (Brocken), shard (Splitter)
static func _texture(id: String) -> Texture2D:
	if not _textures.has(id):
		_textures[id] = _make_texture(id)
	return _textures[id]

static func _make_texture(id: String) -> Texture2D:
	match id:
		"chunk":
			return _shape_texture(8, 8, func(_u: float, _v: float) -> float: return 1.0)
		"shard":
			return _shape_texture(10, 24, func(u: float, v: float) -> float:
				return 1.0 if absf(u - 0.5) / 0.5 + absf(v - 0.5) / 0.5 <= 1.0 else 0.0)
		"puff":
			var balls := [Vector3(0.5, 0.6, 0.3), Vector3(0.3, 0.62, 0.2), Vector3(0.7, 0.62, 0.2),
				Vector3(0.4, 0.4, 0.21), Vector3(0.62, 0.42, 0.19)]
			return _shape_texture(48, 48, func(u: float, v: float) -> float:
				var a := 0.0
				for b: Vector3 in balls:
					a = maxf(a, clampf((b.z - Vector2(u, v).distance_to(Vector2(b.x, b.y))) / (b.z * 0.3), 0.0, 1.0))
				return a)
	var stops: Array = [[0.0, 1.0], [0.2, 0.75], [0.5, 0.25], [1.0, 0.0]]
	var size := Vector2i(64, 64)
	match id:
		"dot":
			stops = [[0.0, 1.0], [0.55, 1.0], [0.8, 0.5], [1.0, 0.0]]
			size = Vector2i(24, 24)
		"streak":
			stops = [[0.0, 1.0], [0.35, 0.85], [1.0, 0.0]]
			size = Vector2i(12, 64)
		"smoke":
			stops = [[0.0, 0.9], [0.45, 0.7], [0.8, 0.25], [1.0, 0.0]]
		"ring":
			stops = [[0.0, 0.0], [0.5, 0.12], [0.72, 1.0], [0.88, 0.8], [1.0, 0.0]]
			size = Vector2i(24, 24)
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s: Array in stops:
		offsets.append(s[0])
		colors.append(Color(1, 1, 1, s[1]))
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = size.x
	tex.height = size.y
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex

static func _shape_texture(w: int, h: int, alpha_at: Callable) -> ImageTexture:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(1, 1, 1, alpha_at.call((x + 0.5) / w, (y + 0.5) / h)))
	return ImageTexture.create_from_image(img)

## Partikelstöße je Effekt
func _plan_particles() -> void:
	var g := GROUND
	match kind:
		Kind.SLASH:
			var dir := Vector2(-0.75 * _flip, 0.8).normalized()
			_burst(0.15, {"tex": "streak", "amount": 12, "life": 0.35, "dir": dir, "spread": 40.0, "vel": Vector2(3.0, 5.5),
				"damping": Vector2(8, 12), "align": true, "size": Vector2(0.14, 0.26),
				"colors": [Color.WHITE, color.lightened(0.3), _with_alpha(color, 0.0)]})
			_burst(0.15, {"tex": "dot", "amount": 8, "life": 0.4, "spread": 180.0, "vel": Vector2(1.0, 2.2),
				"damping": Vector2(3, 5), "size": Vector2(0.04, 0.08), "colors": [Color.WHITE, _with_alpha(color, 0.0)]})
		Kind.FIRE:
			_burst(0.05, {"tex": "streak", "amount": 16, "life": 0.6, "pos": Vector2(0, 0.3), "sphere": 0.3,
				"spread": 70.0, "vel": Vector2(1.5, 3.2), "gravity": Vector2(0, -1.5), "damping": Vector2(1.5, 2.5),
				"align": true, "size": Vector2(0.08, 0.16),
				"colors": [FIRE_COLORS[3], FIRE_COLORS[2], FIRE_COLORS[1], _with_alpha(FIRE_COLORS[0], 0.0)]})
			_burst(0.3, {"tex": "smoke", "amount": 6, "life": 0.6, "pos": Vector2(0, 0.0), "sphere": 0.4,
				"spread": 40.0, "vel": Vector2(0.3, 0.7), "size": Vector2(0.6, 1.0), "curve": "grow", "behind": true,
				"colors": [Color(0.3, 0.1, 0.06, 0.0), Color(0.22, 0.1, 0.08, 0.55), Color(0.16, 0.13, 0.13, 0.0)]})
		Kind.WATER:
			_droplets(WATER_COLORS[3], WATER_COLORS[2], WATER_COLORS[1])
			_burst(0.0, {"tex": "smoke", "amount": 5, "life": 0.6, "pos": Vector2(0, g), "box": Vector2(0.5, 0.05),
				"spread": 60.0, "vel": Vector2(0.2, 0.5), "size": Vector2(0.4, 0.7), "curve": "grow", "behind": true,
				"colors": [Color(1, 1, 1, 0.0), Color(0.85, 0.95, 1.0, 0.45), Color(0.85, 0.95, 1.0, 0.0)]})
		Kind.EARTH:
			_burst(0.05, {"tex": "chunk", "amount": 12, "life": 0.7, "pos": Vector2(0, g - 0.1), "box": Vector2(0.4, 0.05),
				"spread": 55.0, "vel": Vector2(2.5, 4.0), "gravity": Vector2(0, 8.0), "spin": Vector2(-500, 500),
				"size": Vector2(0.08, 0.16), "curve": "flat", "tints": [EARTH_COLORS[0], EARTH_COLORS[1], EARTH_COLORS[2]],
				"colors": [Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)]})
			_burst(0.1, {"tex": "smoke", "amount": 7, "life": 0.7, "pos": Vector2(0, g), "box": Vector2(0.55, 0.05),
				"spread": 80.0, "vel": Vector2(0.4, 0.9), "size": Vector2(0.5, 0.9), "curve": "grow", "behind": true,
				"colors": [_with_alpha(DUST_COLOR, 0.0), _with_alpha(DUST_COLOR, 0.5), _with_alpha(DUST_COLOR, 0.0)]})
		Kind.AIR:
			_burst(0.0, {"tex": "streak", "amount": 16, "life": 0.7, "pos": Vector2(0, 0.2), "sphere": 0.8,
				"spread": 180.0, "vel": Vector2(0.2, 0.5), "orbit": Vector2(0.9 * _flip, 1.5 * _flip),
				"gravity": Vector2(0, -2.0), "explosive": 0.6, "size": Vector2(0.08, 0.14),
				"colors": [_with_alpha(AIR_COLORS[1], 0.0), AIR_COLORS[1], _with_alpha(AIR_COLORS[0], 0.0)]})
		Kind.SHIELD_HIT, Kind.S_SHIELD_HIT:
			var c := SHIELD_COLOR if kind == Kind.SHIELD_HIT else S_SHIELD_COLOR
			_burst(0.0, {"tex": "streak", "amount": 10, "life": 0.35, "pos": Vector2(0.25 * _flip, -0.6), "spread": 75.0,
				"vel": Vector2(2.0, 4.0), "damping": Vector2(6, 9), "gravity": Vector2(0, 3.0), "align": true,
				"size": Vector2(0.1, 0.18), "colors": [Color.WHITE, c, _with_alpha(c, 0.0)]})
		Kind.S_SHIELD:
			_burst(0.15, {"tex": "glow", "amount": 10, "life": 0.6, "pos": Vector2(0, 0.4), "box": Vector2(0.7, 0.1),
				"vel": Vector2(0.8, 1.6), "spread": 15.0, "explosive": 0.5, "size": Vector2(0.12, 0.2), "curve": "pop",
				"colors": [Color.WHITE, S_SHIELD_COLOR, _with_alpha(S_SHIELD_COLOR, 0.0)]})
		Kind.SHIELD:
			_burst(0.3, {"tex": "glow", "amount": 8, "life": 0.45, "sphere": 1.0, "surface": true, "spread": 180.0,
				"vel": Vector2(0.3, 0.7), "size": Vector2(0.1, 0.18), "curve": "pop",
				"colors": [Color.WHITE, SHIELD_COLOR, _with_alpha(SHIELD_COLOR, 0.0)]})
		Kind.BUFF:
			_rising_motes(BUFF_COLOR, true)
		Kind.DEBUFF:
			_rising_motes(DEBUFF_COLOR.darkened(0.3), false)
		Kind.HEAL:
			_rising_motes(HEAL_COLOR, true)
		Kind.STEAM:
			_burst(0.0, {"tex": "puff", "amount": 10, "life": 0.8, "pos": Vector2(0, 0.35), "box": Vector2(0.55, 0.15),
				"spread": 35.0, "vel": Vector2(0.6, 1.3), "damping": Vector2(0.5, 1.0), "size": Vector2(0.45, 0.8),
				"curve": "grow", "explosive": 0.75, "spin": Vector2(-40, 40),
				"colors": [_with_alpha(STEAM_COLORS[1], 0.0), _with_alpha(STEAM_COLORS[1], 0.85), _with_alpha(STEAM_COLORS[0], 0.0)]})
			_burst(0.0, {"tex": "streak", "amount": 8, "life": 0.35, "pos": Vector2(0, 0.2), "spread": 50.0,
				"vel": Vector2(3.0, 4.5), "damping": Vector2(6, 9), "align": true, "size": Vector2(0.12, 0.22),
				"colors": [Color.WHITE, _with_alpha(STEAM_COLORS[1], 0.0)]})
		Kind.LIGHTNING:
			var hit := Vector2(0, 0.25)
			_burst(0.08, {"tex": "streak", "amount": 18, "life": 0.45, "pos": hit, "spread": 85.0, "vel": Vector2(2.5, 5.0),
				"gravity": Vector2(0, 5.0), "damping": Vector2(2, 3), "align": true, "size": Vector2(0.1, 0.2),
				"colors": [Color.WHITE, LIGHTNING_COLOR, _with_alpha(Color(1.0, 0.5, 0.1), 0.0)]})
			_burst(0.08, {"tex": "chunk", "amount": 8, "life": 0.55, "pos": hit, "spread": 50.0, "vel": Vector2(2.0, 3.5),
				"gravity": Vector2(0, 7.0), "spin": Vector2(-600, 600), "size": Vector2(0.04, 0.08), "curve": "flat",
				"colors": [Color(1.0, 0.97, 0.8), Color(0.8, 0.78, 0.7), Color(0.8, 0.78, 0.7, 0.0)]})
		Kind.MAGMA:
			_burst(0.08, {"tex": "dot", "amount": 14, "life": 0.7, "pos": Vector2(0, g - 0.25), "box": Vector2(0.4, 0.05),
				"spread": 55.0, "vel": Vector2(2.5, 4.0), "gravity": Vector2(0, 8.0), "size": Vector2(0.08, 0.16),
				"colors": [MAGMA_COLORS[3], MAGMA_COLORS[2], MAGMA_COLORS[1], _with_alpha(MAGMA_COLORS[0].darkened(0.5), 0.0)]})
			_burst(0.15, {"tex": "streak", "amount": 8, "life": 0.6, "pos": Vector2(0, g - 0.2), "box": Vector2(0.5, 0.05),
				"spread": 30.0, "vel": Vector2(1.0, 2.0), "gravity": Vector2(0, -1.0), "align": true, "size": Vector2(0.06, 0.12),
				"colors": [MAGMA_COLORS[3], MAGMA_COLORS[1], _with_alpha(MAGMA_COLORS[0], 0.0)]})
		Kind.ICE:
			_burst(0.0, {"tex": "smoke", "amount": 8, "life": 0.8, "sphere": 0.5, "spread": 180.0, "vel": Vector2(0.2, 0.5),
				"size": Vector2(0.6, 1.1), "curve": "grow", "behind": true,
				"colors": [_with_alpha(ICE_COLORS[1], 0.0), _with_alpha(ICE_COLORS[1], 0.45), _with_alpha(ICE_COLORS[0], 0.0)]})
			_burst(0.1, {"tex": "glow", "amount": 10, "life": 0.5, "sphere": 0.9, "spread": 180.0, "vel": Vector2(0.1, 0.3),
				"size": Vector2(0.08, 0.16), "curve": "pop", "explosive": 0.4,
				"colors": [Color.WHITE, ICE_COLORS[2], _with_alpha(ICE_COLORS[1], 0.0)]})
			_burst(0.6, {"tex": "shard", "amount": 16, "life": 0.55, "sphere": 0.5, "spread": 180.0, "vel": Vector2(1.5, 3.0),
				"gravity": Vector2(0, 4.0), "spin": Vector2(-500, 500), "size": Vector2(0.08, 0.17), "curve": "flat",
				"colors": [Color.WHITE, ICE_COLORS[1], _with_alpha(ICE_COLORS[0], 0.0)]})
		Kind.DUST:
			_burst(0.05, {"tex": "chunk", "amount": 14, "life": 0.6, "sphere": 0.15, "spread": 180.0, "vel": Vector2(1.5, 3.0),
				"damping": Vector2(2, 4), "gravity": Vector2(0, 2.0), "spin": Vector2(-400, 400), "size": Vector2(0.04, 0.08),
				"curve": "flat", "colors": [Color(0.75, 0.12, 0.08), Color(0.6, 0.1, 0.07), Color(0.6, 0.1, 0.07, 0.0)]})
			_burst(0.1, {"tex": "smoke", "amount": 10, "life": 0.7, "pos": Vector2(0, 0.2), "sphere": 0.4, "surface": true,
				"spread": 180.0, "vel": Vector2(0.5, 1.0), "radial": Vector2(0.5, 1.0), "size": Vector2(0.4, 0.7),
				"curve": "grow", "colors": [_with_alpha(DUST_COLOR, 0.0), _with_alpha(DUST_COLOR, 0.55), _with_alpha(DUST_COLOR, 0.0)]})
		Kind.MUD:
			_droplets(MUD_COLORS[2], MUD_COLORS[1], MUD_COLORS[0])
			_burst(0.05, {"tex": "chunk", "amount": 6, "life": 0.6, "pos": Vector2(0, g - 0.3), "box": Vector2(0.4, 0.05),
				"spread": 50.0, "vel": Vector2(2.0, 3.5), "gravity": Vector2(0, 8.0), "spin": Vector2(-400, 400),
				"size": Vector2(0.06, 0.12), "curve": "flat", "colors": [EARTH_COLORS[1], EARTH_COLORS[0], _with_alpha(EARTH_COLORS[0], 0.0)]})
		Kind.POISON:
			_droplets(SWAMP_COLORS[2], SWAMP_COLORS[1], SWAMP_COLORS[0])
			_burst(0.15, {"tex": "ring", "amount": 12, "life": 0.6, "pos": Vector2(0, 0.3), "box": Vector2(0.6, 0.2),
				"spread": 10.0, "vel": Vector2(0.8, 1.6), "explosive": 0.4, "size": Vector2(0.08, 0.16), "curve": "grow",
				"colors": [POISON_COLOR, POISON_COLOR, _with_alpha(POISON_COLOR, 0.0)]})
			_burst(0.1, {"tex": "smoke", "amount": 7, "life": 0.8, "sphere": 0.6, "spread": 180.0, "vel": Vector2(0.2, 0.4),
				"size": Vector2(0.6, 1.0), "curve": "grow", "behind": true,
				"colors": [_with_alpha(POISON_COLOR.darkened(0.4), 0.0), _with_alpha(POISON_COLOR.darkened(0.4), 0.4),
					_with_alpha(POISON_COLOR.darkened(0.5), 0.0)]})
		Kind.ASH:
			_burst(0.0, {"tex": "smoke", "amount": 12, "life": 0.85, "pos": Vector2(0, 0.3), "box": Vector2(0.6, 0.2),
				"spread": 40.0, "vel": Vector2(0.5, 1.2), "damping": Vector2(0.3, 0.6), "size": Vector2(0.7, 1.1),
				"curve": "grow", "explosive": 0.7, "spin": Vector2(-60, 60),
				"colors": [Color(0.5, 0.2, 0.08, 0.0), Color(0.34, 0.3, 0.3, 0.85), _with_alpha(ASH_COLOR, 0.0)]})
			_burst(0.1, {"tex": "streak", "amount": 16, "life": 0.7, "pos": Vector2(0, 0.3), "box": Vector2(0.6, 0.2),
				"spread": 30.0, "vel": Vector2(1.0, 2.2), "gravity": Vector2(0, -1.0), "explosive": 0.5, "align": true,
				"size": Vector2(0.06, 0.12), "colors": [FIRE_COLORS[3], FIRE_COLORS[1], _with_alpha(FIRE_COLORS[0], 0.0)]})
		Kind.THUNDER:
			_burst(0.0, {"tex": "chunk", "amount": 12, "life": 0.8, "pos": Vector2(0, g), "box": Vector2(0.45, 0.05),
				"spread": 25.0, "vel": Vector2(0.6, 1.4), "orbit": Vector2(0.6 * _flip, 1.2 * _flip), "gravity": Vector2(0, -0.6),
				"explosive": 0.6, "spin": Vector2(-400, 400), "size": Vector2(0.04, 0.09), "curve": "flat",
				"colors": [Color(0.85, 0.82, 0.75), Color(0.7, 0.68, 0.62), Color(0.7, 0.68, 0.62, 0.0)]})
			_burst(0.3, {"tex": "streak", "amount": 12, "life": 0.4, "pos": Vector2(0, 0.1), "spread": 180.0,
				"vel": Vector2(2.0, 4.0), "damping": Vector2(4, 6), "align": true, "size": Vector2(0.1, 0.18),
				"colors": [Color.WHITE, STORM_COLORS[0], _with_alpha(STORM_COLORS[0], 0.0)]})
		Kind.ERUPTION:
			_burst(0.0, {"tex": "smoke", "amount": 12, "life": 0.85, "pos": Vector2(0, g - 0.1), "box": Vector2(0.35, 0.05),
				"spread": 60.0, "vel": Vector2(0.6, 1.5), "damping": Vector2(0.8, 1.5), "size": Vector2(0.6, 1.0),
				"curve": "grow", "spin": Vector2(-60, 60),
				"colors": [Color(1.0, 0.55, 0.15, 0.9), Color(0.36, 0.32, 0.3, 0.85), Color(0.3, 0.28, 0.27, 0.0)]})
			_burst(0.05, {"tex": "chunk", "amount": 10, "life": 0.7, "pos": Vector2(0, g - 0.1), "box": Vector2(0.3, 0.05),
				"spread": 50.0, "vel": Vector2(2.5, 4.0), "gravity": Vector2(0, 7.0), "spin": Vector2(-500, 500),
				"size": Vector2(0.06, 0.12), "curve": "flat", "colors": [Color(0.3, 0.2, 0.15), Color(0.2, 0.15, 0.12), Color(0.2, 0.15, 0.12, 0.0)]})
		Kind.CHAOS:
			_burst(0.0, {"tex": "smoke", "amount": 14, "life": 0.9, "pos": Vector2(0, g - 0.1), "box": Vector2(0.5, 0.1),
				"spread": 70.0, "vel": Vector2(0.5, 1.2), "damping": Vector2(0.6, 1.0), "size": Vector2(0.7, 1.1),
				"curve": "grow", "explosive": 0.8, "spin": Vector2(-80, 80), "behind": true,
				"colors": [_with_alpha(CHAOS_COLORS[1], 0.0), _with_alpha(CHAOS_COLORS[1], 0.8), _with_alpha(CHAOS_COLORS[1], 0.0)]})
			_burst(0.1, {"tex": "shard", "amount": 14, "life": 0.8, "pos": Vector2(0, 0.2), "sphere": 0.9, "spread": 180.0,
				"vel": Vector2(0.2, 0.6), "orbit": Vector2(0.5 * _flip, 1.1 * _flip), "gravity": Vector2(0, -0.8),
				"explosive": 0.5, "spin": Vector2(-300, 300), "size": Vector2(0.06, 0.13), "curve": "flat",
				"tints": [CHAOS_COLORS[0], CHAOS_COLORS[1], CHAOS_COLORS[2]],
				"colors": [Color(1, 1, 1, 0), Color.WHITE, Color(1, 1, 1, 0)]})

## Tropfen, die von einer Spritzerkrone hochfliegen und wieder fallen
func _droplets(light: Color, mid: Color, dark: Color) -> void:
	_burst(0.12, {"tex": "dot", "amount": 16, "life": 0.7, "pos": Vector2(0, GROUND - 0.6), "box": Vector2(0.55, 0.15),
		"spread": 45.0, "vel": Vector2(2.0, 3.5), "gravity": Vector2(0, 7.5), "size": Vector2(0.06, 0.13), "curve": "flat",
		"colors": [light, mid, _with_alpha(dark, 0.0)]})

## Leuchtende Punkte, die am Monster auf- oder absteigen (Buff, Heilung, Schwächung)
func _rising_motes(c: Color, up: bool) -> void:
	_burst(0.05, {"tex": "glow", "amount": 14, "life": 0.7, "pos": Vector2(0, 0.6 if up else -0.6), "box": Vector2(0.75, 0.15),
		"dir": Vector2.UP if up else Vector2.DOWN, "spread": 10.0, "vel": Vector2(0.8, 1.8), "explosive": 0.5,
		"size": Vector2(0.1, 0.2), "curve": "pop", "colors": [Color.WHITE, c, _with_alpha(c, 0.0)]})

# ─────────────────────────
# Physischer Treffer: zwei sichelförmige Hiebe quer über das Monster, außen in der Akzentfarbe, innen weiß

func _draw_slash(t: float) -> void:
	var r := radius
	if t > 0.12 and t < 0.7:
		var s := (t - 0.12) / 0.58
		_glow(Vector2.ZERO, r * 1.8 * (0.6 + 0.4 * s), _with_alpha(color, 0.45 * (1.0 - s)))
	_draw_slash_line(t, Vector2(0.75 * r * _flip, -0.8 * r), Vector2(-0.75 * r * _flip, 0.8 * r), r * 0.18)
	_draw_slash_line(clampf(t * 1.25 - 0.18, 0.0, 1.0), Vector2(0.95 * r * _flip, -0.35 * r), Vector2(-0.3 * r * _flip, 0.95 * r), r * 0.1)
	if t < 0.2:
		_glow(Vector2.ZERO, r * 0.9, Color(1, 1, 1, 0.8 * (1.0 - t / 0.2)))

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
	var steps := 16
	for layer in 3:
		var factor: float = [2.2, 1.4, 1.0][layer]
		var c: Color = [_with_alpha(color, 0.3 * alpha), _with_alpha(color.lightened(0.3), 0.85 * alpha), Color(1, 1, 1, alpha)][layer]
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for i in steps + 1:
			var u := lerpf(tail, head, float(i) / steps)
			var center := a.lerp(b, u) + normal * sin(PI * u) * bend
			# spitz an beiden Enden, die Spitze vorne schlanker
			var w := width * sin(PI * pow(float(i) / steps, 0.7)) * factor
			left.append(center + normal * w)
			right.append(center - normal * w * 0.35)
		_strip(left, right, c)

# ─────────────────────────
# Feuer: ein Bündel spitzer Flammenzungen schießt hoch, dunkelroter Schein, gelber Kern, Glut fliegt auf

func _draw_fire(t: float) -> void:
	var r := radius
	var late := clampf((t - 0.35) / 0.65, 0.0, 1.0)
	var fade := 1.0 - late
	var grow0 := _ease_out(clampf(t / 0.25, 0.0, 1.0))
	_glow(Vector2(0, 0.0), r * 2.8 * (0.6 + 0.4 * grow0), _with_alpha(FIRE_COLORS[0], 0.55 * fade))
	_glow(Vector2(0, 0.25 * r), r * 1.9 * grow0, _with_alpha(FIRE_COLORS[1], 0.55 * fade))
	# Zungen schichtweise: erst alle dunklen, dann orange, gelb und der helle Kern
	var layers := [[1.0, 1.0, FIRE_COLORS[0], 0.9], [0.82, 0.72, FIRE_COLORS[1], 1.0], [0.6, 0.48, FIRE_COLORS[2], 1.0],
		[0.32, 0.28, FIRE_COLORS[3], 1.0]]
	for layer: Array in layers:
		for p: Part in _parts:
			var s := _ease_out(clampf((t - p.delay * 0.3) / 0.28, 0.0, 1.0))
			if s <= 0.0:
				continue
			var dir := Vector2.from_angle(-PI / 2.0 + p.offset * 1.15)
			var length := r * (0.75 + 0.8 * p.speed) * (1.0 - absf(p.offset) * 0.35)
			var base := Vector2(p.offset * 0.2 * r, 0.45 * r) + dir * length * 0.55 * late
			var c: Color = layer[2]
			_tongue(base, dir, length * s * (1.0 - 0.35 * late) * layer[0], r * 0.36 * p.size * (1.0 - 0.75 * late) * layer[1],
				p.spin * 0.35, _with_alpha(c, float(layer[3]) * (1.0 - late * late)))
	_glow(Vector2(0, 0.35 * r), r * 1.0 * grow0, _with_alpha(FIRE_COLORS[3], 0.9 * fade))
	if t < 0.12:
		_glow(Vector2(0, 0.2 * r), r * 2.2, Color(1, 1, 0.85, 0.75 * (1.0 - t / 0.12)))

# ─────────────────────────
# Spritzerkrone (Wasser, Schlamm, Sumpf): Zacken stehen aus einem Ring am Boden hoch, die äußeren kippen nach
# außen, helle Innenseite, weiße Glanzlichter, Tropfen lösen sich, dann sinkt alles zusammen

func _draw_crown(t: float, pal: Array, w_scale := 1.0, puddle := false) -> void:
	var r := radius
	var base := Vector2(0, GROUND * r)
	var rise := _ease_out(clampf(t / 0.3, 0.0, 1.0))
	var sink := clampf((t - 0.45) / 0.55, 0.0, 1.0)
	var alpha := 1.0 - sink * sink
	var half_w := r * (0.5 + 0.3 * rise) * w_scale
	var height := r * 1.3 * rise * (1.0 - 0.55 * sink)
	var lean := r * 0.45 * rise
	if puddle:
		var rx := half_w * (1.1 + 0.3 * rise)
		_draw_poly(_ellipse(base, rx, rx * 0.24), _with_alpha(pal[0], 0.85 * alpha))
		_draw_ellipse_arc(base, rx, rx * 0.24, _with_alpha(pal[2], 0.7 * alpha), r * 0.03 + 1.0)
	# Wellenringe am Boden
	for i in 2:
		var s := clampf((t - i * 0.2) / 0.8, 0.0, 1.0)
		if s > 0.0 and s < 1.0:
			var rx := half_w * (1.0 + 0.9 * _ease_out(s))
			_draw_ellipse_arc(base, rx, rx * 0.24, _with_alpha(pal[0] if not puddle else pal[3], 0.8 * (1.0 - s)), r * 0.035 + 1.0)
	if height < 1.0:
		return
	var outer := _crown_shape(base, half_w, height, lean)
	_draw_poly(outer[0], _with_alpha(pal[1], alpha))
	var inner := _crown_shape(base + Vector2(0, -r * 0.03), half_w * 0.74, height * 0.72, lean * 0.7)
	_draw_poly(inner[0], _with_alpha(pal[2], alpha))
	# Glanzlichter in den Zacken
	var tips: PackedVector2Array = outer[1]
	for i in tips.size():
		var tip := tips[i]
		var from := base + Vector2((tip.x - base.x) * 0.55, -height * 0.12)
		_tongue(from, (tip - from).normalized(), (tip - from).length() * 0.85, r * 0.075, 0.0, _with_alpha(pal[3], 0.85 * alpha))
		# Tropfen lösen sich von den Spitzen
		var p: Part = _parts[i]
		if p.size > 0.72:
			var drop := tip + (tip - base).normalized() * r * (0.1 + 0.25 * rise + 0.45 * sink)
			draw_circle(drop, r * 0.05 * p.size, _with_alpha(pal[2], alpha))
	# Gischtsaum vorne
	_draw_ellipse_arc(base, half_w, half_w * 0.24, _with_alpha(pal[3], 0.9 * alpha), r * 0.05 + 1.0, 0.0, PI)

## Umriss einer Spritzerkrone und die Lage der Spitzen: [Polygon, Spitzen]
func _crown_shape(base: Vector2, half_w: float, height: float, lean: float) -> Array:
	var points := PackedVector2Array()
	var tips := PackedVector2Array()
	var n := _parts.size()
	points.append(base + Vector2(-half_w, 0))
	for i in n:
		var p: Part = _parts[i]
		var u := (i + 0.5) / n
		var side := u * 2.0 - 1.0
		if i > 0:
			var valley := lerpf(-half_w, half_w, float(i) / n)
			points.append(base + Vector2(valley, -height * 0.24 * (1.0 - absf(side) * 0.5)))
		var x := lerpf(-half_w, half_w, u) + p.offset * half_w / n * 0.4
		var h := height * (0.45 + 0.55 * p.speed) * (1.0 - 0.45 * absf(side))
		var tip := base + Vector2(x + side * lean, -h)
		points.append(tip)
		tips.append(tip)
	points.append(base + Vector2(half_w, 0))
	var ry := half_w * 0.24
	for i in range(1, 12):
		var a := PI * i / 12.0
		points.append(base + Vector2(cos(a) * half_w, sin(a) * ry))
	return [points, tips]

# ─────────────────────────
# Erde: dicke Erdsträhnen spritzen fächerförmig aus dem Boden und fliegen davon, Brocken und Staub

func _draw_earth(t: float) -> void:
	var r := radius
	var base_y := GROUND * r
	var late := clampf((t - 0.4) / 0.6, 0.0, 1.0)
	var mound := _ease_out(clampf(t / 0.2, 0.0, 1.0)) * (1.0 - late)
	if mound > 0.0:
		_draw_poly(_ellipse(Vector2(0, base_y), r * 0.6 * mound + 1.0, r * 0.2 * mound + 1.0), _with_alpha(EARTH_COLORS[0], 1.0 - late))
	for layer in 2:
		for p: Part in _parts:
			var s := _ease_out(clampf((t - p.delay * 0.2) / 0.28, 0.0, 1.0))
			if s <= 0.0:
				continue
			var dir := Vector2.from_angle(-PI / 2.0 + p.offset * 1.0)
			var length := r * (0.8 + 0.8 * p.speed)
			var base := Vector2(p.offset * 0.3 * r, base_y) + dir * length * 0.7 * late
			var width := r * 0.42 * p.size * (1.0 - 0.4 * late)
			var bend := signf(p.offset) * absf(p.spin) * 0.3
			var a := 1.0 - late * late
			if layer == 0:
				_tongue(base, dir, length * s * (1.0 - 0.5 * late), width, bend, _with_alpha(EARTH_COLORS[0], a), true)
			else:
				_tongue(base + dir * length * 0.08, dir, length * s * (1.0 - 0.5 * late) * 0.75, width * 0.45, bend,
					_with_alpha(EARTH_COLORS[2], a), true)

# ─────────────────────────
# Windhose (Luft, Gewitter): leuchtende Sicheln kreisen übereinander, unten eng, oben weit

func _draw_tornado(t: float, pal: Array, size_factor: float) -> void:
	var r := radius * size_factor
	var appear := clampf(t / 0.2, 0.0, 1.0)
	var fade := 1.0 - clampf((t - 0.7) / 0.3, 0.0, 1.0)
	var n := _parts.size()
	_glow(Vector2(0, -0.1 * r), r * 2.4, _with_alpha(pal[0], 0.3 * appear * fade))
	for layer in 2:
		for i in n:
			var p: Part = _parts[i]
			var level := float(i) / maxf(1.0, n - 1)
			if appear < level * 0.8:
				continue
			var y := lerpf(GROUND * radius, -0.95 * r, level)
			var rx := r * (0.22 + 0.68 * level) * (0.8 + 0.2 * p.size)
			var sway := sin(t * 7.0 + i * 0.8) * r * 0.08 * level
			var start: float = p.angle + _flip * t * TAU * 1.7 * p.speed
			var arc := PI * (0.65 + 0.45 * p.speed)
			var width := r * (0.06 + 0.07 * level)
			if layer == 0:
				_tapered_arc(Vector2(sway, y), rx, rx * 0.3, start, arc, width * 2.6, _with_alpha(pal[0], 0.55 * fade))
			else:
				_tapered_arc(Vector2(sway, y), rx, rx * 0.3, start, arc, width, _with_alpha(pal[1], fade))

# ─────────────────────────
# Physischer Schild: blaues Sechseck springt auf, ein Glanz läuft darüber, dann verblasst es

func _draw_shield(t: float) -> void:
	var r := radius * 1.05
	var pop := _ease_back(clampf(t / 0.35, 0.0, 1.0))
	var alpha := 1.0 - clampf((t - 0.6) / 0.4, 0.0, 1.0)
	var size := r * (0.6 + 0.4 * pop)
	_glow(Vector2.ZERO, size * 2.5, _with_alpha(SHIELD_COLOR, 0.3 * alpha))
	var hex := _polygon(Vector2.ZERO, size, 6, PI / 6.0)
	_draw_poly(hex, _with_alpha(SHIELD_COLOR, 0.2 * alpha))
	for i in 6:
		var a := PI / 6.0 + i * TAU / 6.0
		draw_line(Vector2.ZERO, Vector2.from_angle(a) * size, _with_alpha(SHIELD_COLOR, 0.25 * alpha), 1.5, true)
	_draw_closed(_polygon(Vector2.ZERO, size * 0.5, 6, PI / 6.0), _with_alpha(SHIELD_COLOR, 0.35 * alpha), 1.5)
	_draw_closed(hex, _with_alpha(SHIELD_COLOR, 0.5 * alpha), r * 0.14 + 1.0)
	_draw_closed(hex, _with_alpha(SHIELD_COLOR.lightened(0.5), alpha), r * 0.05 + 1.0)
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
	_glow(Vector2.ZERO, size * 2.6, _with_alpha(S_SHIELD_COLOR, 0.35 * alpha))
	draw_circle(Vector2.ZERO, size, _with_alpha(S_SHIELD_COLOR, 0.15 * alpha))
	draw_arc(Vector2.ZERO, size, 0, TAU, 48, _with_alpha(S_SHIELD_COLOR, 0.5 * alpha), r * 0.12 + 1.0, true)
	draw_arc(Vector2.ZERO, size, 0, TAU, 48, _with_alpha(S_SHIELD_COLOR.lightened(0.5), alpha), r * 0.04 + 1.0, true)
	draw_arc(Vector2.ZERO, size * 0.82, 0, TAU, 48, _with_alpha(S_SHIELD_COLOR, 0.6 * alpha), 1.5, true)
	for i in 6:
		var a := rot + i * TAU / 6.0
		var c := Vector2.from_angle(a) * size * 0.91
		_draw_poly(_polygon(c, r * 0.07, 4, a), _with_alpha(Color.WHITE, alpha))
	_draw_closed(_polygon(Vector2.ZERO, size * 0.6, 3, -rot), _with_alpha(S_SHIELD_COLOR, 0.45 * alpha), 1.5)
	_draw_closed(_polygon(Vector2.ZERO, size * 0.6, 3, -rot + PI), _with_alpha(S_SHIELD_COLOR, 0.45 * alpha), 1.5)

# ─────────────────────────
# Schildtreffer: der Schild blitzt am Einschlag auf und bekommt Risse, Funken spritzen ab

func _draw_shield_hit(t: float, c: Color, round: bool) -> void:
	var r := radius * 1.05
	var alpha := 1.0 - t
	var size := r * (1.0 + 0.08 * t)
	if round:
		draw_circle(Vector2.ZERO, size, _with_alpha(c, 0.22 * alpha))
		draw_arc(Vector2.ZERO, size, 0, TAU, 48, _with_alpha(c.lightened(0.4), alpha), r * 0.06 + 1.0, true)
	else:
		var hex := _polygon(Vector2.ZERO, size, 6, PI / 6.0)
		_draw_poly(hex, _with_alpha(c, 0.22 * alpha))
		_draw_closed(hex, _with_alpha(c.lightened(0.4), alpha), r * 0.06 + 1.0)
	var hit := Vector2(r * 0.25 * _flip, -size * 0.55)
	_glow(hit, r * 1.2 * (0.6 + t), _with_alpha(c, 0.7 * alpha))
	_glow(hit, r * 0.5, Color(1, 1, 1, alpha))
	for p: Part in _parts:
		var dir := Vector2.from_angle(PI / 2.0 + p.offset * 1.2)
		var mid := hit + dir * r * 0.25 * p.speed + dir.orthogonal() * r * 0.08 * p.spin
		var end := hit + dir * r * 0.5 * p.speed * minf(1.0, t * 3.0)
		draw_polyline(PackedVector2Array([hit, mid, end]), Color(1, 1, 1, alpha), 2.0, true)

# ─────────────────────────
# Buff / Schwächung: leuchtende Pfeile steigen auf bzw. sinken herab, dazu ein Schein

func _draw_arrows(t: float, c: Color, up: bool) -> void:
	var r := radius
	_glow(Vector2(0, r * 0.2), r * 2.2, _with_alpha(c, 0.3 * sin(PI * t)))
	for i in 3:
		var s := clampf((t - i * 0.15) / 0.7, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var x := (i - 1) * r * 0.5
		var y := lerpf(r * 0.6, -r * 0.8, _ease_out(s)) if up else lerpf(-r * 0.8, r * 0.6, _ease_out(s))
		var w := r * 0.22
		var tip := -1.0 if up else 1.0
		var points := PackedVector2Array([Vector2(x - w, y - tip * w * 0.7), Vector2(x, y), Vector2(x + w, y - tip * w * 0.7)])
		var a := sin(PI * s)
		draw_polyline(points, _with_alpha(c, 0.4 * a), r * 0.2 + 2.0, true)
		draw_polyline(points, _with_alpha(c.lightened(0.5), a), r * 0.07 + 1.0, true)

# ─────────────────────────
# Dampf: Wolken quellen auf und ziehen nach oben, zwischen ihnen kräuseln sich Schwaden

func _draw_steam(t: float) -> void:
	var r := radius
	var puff := _texture("puff")
	for p: Part in _parts:
		var s := clampf((t - p.delay * 0.4) / 0.8, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var pos := Vector2(p.offset * 0.65 * r, 0.4 * r - s * 1.0 * r * p.speed)
		var size := r * (0.55 + 0.65 * _ease_out(s)) * p.size
		var a := sqrt(sin(PI * s))
		var shade := Rect2(pos + Vector2(size * 0.08, size * 0.1) - Vector2(size, size) / 2.0, Vector2(size, size))
		draw_texture_rect(puff, shade, false, _with_alpha(STEAM_COLORS[0], 0.8 * a))
		draw_texture_rect(puff, Rect2(pos - Vector2(size, size) / 2.0, Vector2(size, size)), false, _with_alpha(STEAM_COLORS[1], a))
	# Schwaden: geschwungene, spitz auslaufende Bänder
	for i in 3:
		var s := clampf(t * 1.3 - i * 0.12, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var x0 := (i - 1) * r * 0.55
		var points := PackedVector2Array()
		for k in 12:
			var u := k / 11.0
			var y := lerpf(0.4 * r, -1.3 * r * (0.5 + 0.5 * s), u)
			points.append(Vector2(x0 + sin(u * 7.0 + t * 8.0 + i * 2.0) * r * 0.14 * u, y))
		_ribbon(points, r * 0.09, _with_alpha(STEAM_COLORS[1], 0.75 * sin(PI * s)))

# ─────────────────────────
# Blitz: gezackter Strahl mit Verästelungen schlägt ein, Sternenblitz am Boden, Risse, Funken und Splitter

func _draw_lightning(t: float) -> void:
	var r := radius
	var hit := Vector2(0, 0.25 * r)
	# alle 0.05 s neue Zacken, damit der Blitz flackert
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + int(_time * 20.0)
	if t < 0.55:
		var alpha := (1.0 - t / 0.55) * (0.6 + 0.4 * rng.randf())
		var points := _bolt(Vector2(0.35 * r * _flip, -1.9 * r), hit, r * 0.45, 4, rng)
		_glow(hit + Vector2(0, -0.8 * r), r * 1.5, _with_alpha(LIGHTNING_COLOR, 0.3 * alpha))
		for b in 2:
			var from := points[rng.randi_range(3, points.size() - 6)]
			var to := from + Vector2.from_angle(PI / 2.0 + rng.randf_range(-1.1, 1.1)) * r * rng.randf_range(0.4, 0.7)
			_draw_bolt(_bolt(from, to, r * 0.15, 3, rng), r * 0.05, alpha * 0.8)
		_draw_bolt(points, r * 0.09, alpha)
	# Einschlag: Stern aus spitzen Strahlen, flach wie auf dem Boden
	if t < 0.6:
		var s := t / 0.6
		var a := 1.0 - s
		_glow(hit, r * 2.0 * (0.6 + 0.4 * s), _with_alpha(LIGHTNING_COLOR, 0.6 * a))
		for p: Part in _parts:
			var dir := Vector2(cos(p.angle), sin(p.angle) * 0.4).normalized()
			_tongue(hit, dir, r * (0.45 + 0.6 * p.speed) * _ease_out(minf(1.0, s * 3.0)), r * 0.07, 0.0, Color(1, 1, 0.9, a))
		_glow(hit, r * 0.8, Color(1, 1, 1, a))
	# Risse im Boden
	if t > 0.05:
		var s := clampf((t - 0.05) / 0.95, 0.0, 1.0)
		var crack_rng := RandomNumberGenerator.new()
		crack_rng.seed = _seed
		for i in 5:
			var ang := crack_rng.randf() * TAU
			var end := hit + Vector2(cos(ang), sin(ang) * 0.35) * r * crack_rng.randf_range(0.5, 0.9) * _ease_out(minf(1.0, s * 4.0))
			var crack := _bolt(hit, end, r * 0.08, 2, crack_rng)
			draw_polyline(crack, _with_alpha(LIGHTNING_COLOR, 0.8 * (1.0 - s)), r * 0.035 + 1.0, true)

## Zickzack-Linie von a nach b (Mittelpunkt-Verschiebung)
func _bolt(a: Vector2, b: Vector2, jag: float, depth: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var points := PackedVector2Array([a, b])
	var disp := jag
	for d in depth:
		var next := PackedVector2Array()
		for i in points.size() - 1:
			var p0 := points[i]
			var p1 := points[i + 1]
			next.append(p0)
			next.append((p0 + p1) / 2.0 + (p1 - p0).orthogonal().normalized() * rng.randf_range(-disp, disp))
		next.append(points[points.size() - 1])
		points = next
		disp *= 0.5
	return points

func _draw_bolt(points: PackedVector2Array, width: float, alpha: float) -> void:
	draw_polyline(points, _with_alpha(LIGHTNING_COLOR, 0.3 * alpha), width * 3.0, true)
	draw_polyline(points, _with_alpha(LIGHTNING_COLOR, 0.9 * alpha), width * 1.2, true)
	draw_polyline(points, Color(1, 1, 1, alpha), width * 0.45 + 1.0, true)

# ─────────────────────────
# Magma: glühende, zähflüssige Strähnen mit runden Tropfen am Ende, Lavapfütze und orangefarbener Schein

func _draw_magma(t: float) -> void:
	var r := radius
	var base_y := GROUND * r
	var late := clampf((t - 0.45) / 0.55, 0.0, 1.0)
	var a := 1.0 - late * late
	var grow0 := _ease_out(clampf(t / 0.25, 0.0, 1.0))
	_glow(Vector2(0, base_y - 0.4 * r), r * 2.6 * grow0, _with_alpha(MAGMA_COLORS[0], 0.5 * a))
	var rx := r * 0.75 * grow0 + 1.0
	_draw_poly(_ellipse(Vector2(0, base_y), rx, rx * 0.24), _with_alpha(MAGMA_COLORS[1], a))
	_draw_poly(_ellipse(Vector2(0, base_y - r * 0.02), rx * 0.7, rx * 0.15), _with_alpha(MAGMA_COLORS[2], a))
	for layer in 3:
		for p: Part in _parts:
			var s := _ease_out(clampf((t - p.delay * 0.25) / 0.3, 0.0, 1.0))
			if s <= 0.0:
				continue
			var dir := Vector2.from_angle(-PI / 2.0 + p.offset * 0.9)
			var length := r * (0.6 + 0.7 * p.speed) * s * (1.0 - 0.6 * late)
			var base := Vector2(p.offset * 0.35 * r, base_y)
			var width := r * 0.24 * p.size
			var bend := p.spin * 0.4
			var c: Color = MAGMA_COLORS[layer + 1]
			var f: float = [1.0, 0.6, 0.3][layer]
			_tongue(base, dir, length, width * f, bend, _with_alpha(c, a), true)
			# runder Tropfen an der Spitze, wie zähe Lava
			var tip := base + dir * length + dir.orthogonal() * bend * length
			draw_circle(tip, width * 0.5 * f + 0.5, _with_alpha(c, a))

# ─────────────────────────
# Eis: eine Blüte aus Kristallen schießt aus dem Monster, Frostnebel, dann zerspringen sie in Splitter

func _draw_ice(t: float) -> void:
	var r := radius
	var shatter := clampf((t - 0.6) / 0.25, 0.0, 1.0)
	var a := 1.0 - shatter
	_glow(Vector2.ZERO, r * 2.6 * _ease_out(clampf(t / 0.3, 0.0, 1.0)), _with_alpha(ICE_COLORS[0], 0.5 * (1.0 - clampf((t - 0.6) / 0.4, 0.0, 1.0))))
	if a > 0.0:
		var n := _parts.size()
		for i in n:
			var p: Part = _parts[i]
			var grow := _ease_back(clampf((t - p.delay * 0.3) / 0.22, 0.0, 1.0))
			if grow <= 0.0:
				continue
			var ang := -PI / 2.0 + (float(i) / (n - 1) - 0.5) * PI * 1.35 + p.spin * 0.12
			var dir := Vector2.from_angle(ang)
			var length := r * (0.55 + 0.7 * p.speed) * grow * (1.0 - 0.35 * absf(sin(ang + PI / 2.0)) * 0.6)
			_crystal(Vector2(0, 0.1 * r) + dir * r * 0.05, dir, length, r * 0.2 * p.size * grow, a)
	if t < 0.15:
		_glow(Vector2.ZERO, r * 1.8, Color(1, 1, 1, 0.8 * (1.0 - t / 0.15)))

## Ein Eiskristall mit heller und dunkler Facette und weißer Kante
func _crystal(base: Vector2, dir: Vector2, length: float, width: float, alpha: float) -> void:
	var n := dir.orthogonal()
	var tip := base + dir * length
	var side1 := base + dir * length * 0.32 + n * width
	var side2 := base + dir * length * 0.32 - n * width
	var back := base - dir * length * 0.08
	_glow(base + dir * length * 0.5, length * 1.1, _with_alpha(ICE_COLORS[0], 0.35 * alpha))
	_draw_poly(PackedVector2Array([back, side1, tip, side2]), _with_alpha(ICE_COLORS[0].lerp(ICE_COLORS[1], 0.4), 0.95 * alpha))
	_draw_poly(PackedVector2Array([back, side1, tip]), _with_alpha(ICE_COLORS[2], 0.95 * alpha))
	draw_polyline(PackedVector2Array([side1, tip, side2]), Color(1, 1, 1, alpha), maxf(1.0, width * 0.12), true)

# ─────────────────────────
# Staub: senkrechter Lichtstrahl, zerrissene Staubringe breiten sich am Boden aus, rote Splitter

func _draw_dust(t: float) -> void:
	var r := radius
	var center := Vector2(0, 0.2 * r)
	if t < 0.45:
		var s := t / 0.45
		var a := 1.0 - s
		draw_texture_rect(_texture("glow"), Rect2(center + Vector2(-0.12 * r, -1.6 * r), Vector2(0.24 * r, 1.9 * r)), false,
			Color(1.0, 0.75, 0.65, 0.8 * a))
		draw_line(center + Vector2(0, -1.3 * r), center, Color(1, 1, 1, a), r * 0.03 + 1.0, true)
		_glow(center, r * 0.9, Color(1.0, 0.85, 0.8, a))
	for ring in 2:
		var s := clampf((t - ring * 0.15) / 0.8, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var rx := r * (0.3 + 1.2 * _ease_out(s))
		var ry := rx * 0.35
		var width := r * 0.16 * (1.0 - s) + 1.0
		var rot := _flip * s * 0.8 + ring * 0.7
		# Ring aus abgerissenen Stücken
		for p: Part in _parts:
			var start: float = rot + p.angle
			_tapered_arc(center, rx, ry, start, 0.6 + 0.5 * p.size, width * p.size, _with_alpha(DUST_COLOR, 0.9 * (1.0 - s)))

# ─────────────────────────
# Aschesturm: dunkle Rauchwalze mit glühendem Kern, aus der Glut aufsteigt

func _draw_ash(t: float) -> void:
	var r := radius
	var a := sin(PI * t)
	_glow(Vector2(0, 0.3 * r), r * 1.8, Color(1.0, 0.4, 0.1, 0.45 * a * (0.8 + 0.2 * sin(t * 40.0))))
	var smoke := _texture("smoke")
	for p: Part in _parts:
		var s := clampf((t - p.delay * 0.3) / 0.85, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var pos := Vector2(p.offset * 0.6 * r + sin(s * 4.0 + p.spin * 3.0) * r * 0.1, 0.3 * r - s * 0.9 * r * p.speed)
		var size := r * (0.8 + 0.6 * s) * p.size
		draw_texture_rect(smoke, Rect2(pos - Vector2(size, size) / 2.0, Vector2(size, size)), false, _with_alpha(ASH_COLOR, 0.75 * sin(PI * s)))

# ─────────────────────────
# Gewitter: blauer Wirbelsturm, um den Blitze zucken, ein Blitz schlägt mittendrin ein

func _draw_thunder(t: float) -> void:
	var r := radius
	_draw_tornado(t, STORM_COLORS, 1.05)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + int(_time * 16.0)
	var fade := 1.0 - clampf((t - 0.7) / 0.3, 0.0, 1.0)
	# kurze Entladungen am Wirbel
	for i in 2:
		if rng.randf() < 0.5:
			continue
		var y := rng.randf_range(-0.8, 0.4) * r
		var a := Vector2(rng.randf_range(-0.6, 0.6) * r, y)
		var b := a + Vector2.from_angle(rng.randf() * TAU) * r * 0.45
		var arc := _bolt(a, b, r * 0.12, 3, rng)
		draw_polyline(arc, _with_alpha(STORM_COLORS[0], 0.6 * fade), r * 0.08, true)
		draw_polyline(arc, Color(1, 1, 1, fade), r * 0.025 + 1.0, true)
	if t > 0.28 and t < 0.6:
		var s := (t - 0.28) / 0.32
		var points := _bolt(Vector2(0.2 * r * _flip, -1.9 * r), Vector2(0, 0.1 * r), r * 0.35, 4, rng)
		draw_polyline(points, _with_alpha(STORM_COLORS[0], 0.4 * (1.0 - s)), r * 0.24, true)
		draw_polyline(points, _with_alpha(STORM_COLORS[1], 1.0 - s), r * 0.09, true)
		draw_polyline(points, Color(1, 1, 1, 1.0 - s), r * 0.035 + 1.0, true)
		_glow(Vector2(0, 0.1 * r), r * 1.6, _with_alpha(STORM_COLORS[1], 0.7 * (1.0 - s)))

# ─────────────────────────
# Vulkan: Explosion am Boden, dunkle Rauchballen, Brocken ziehen lange Rauchspuren hinter sich her

func _draw_eruption(t: float) -> void:
	var r := radius
	var base := Vector2(0, (GROUND - 0.1) * r)
	var sec := maxf(0.0, _time - 0.03)
	var fade := 1.0 - clampf((t - 0.6) / 0.4, 0.0, 1.0)
	# Lichtblitz am Boden
	if t < 0.35:
		var s := t / 0.35
		draw_texture_rect(_texture("glow"), Rect2(base - Vector2(1.6 * r, 0.25 * r), Vector2(3.2 * r, 0.5 * r)), false,
			Color(1, 0.95, 0.85, 0.8 * (1.0 - s)))
	_glow(base, r * 1.6, Color(1.0, 0.5, 0.1, 0.8 * fade))
	_glow(base, r * 0.6, Color(1.0, 0.9, 0.6, fade))
	# Rauchspuren: Wurfparabeln, der Kopf glüht
	var g := 2.2 * r
	for p: Part in _parts:
		var dir := Vector2.from_angle(-PI / 2.0 + p.offset * 1.3)
		var v := r * (2.6 + 1.8 * p.speed)
		var points := PackedVector2Array()
		var head := sec
		var tail := maxf(0.0, sec - 0.35)
		for k in 9:
			var tau := lerpf(tail, head, k / 8.0)
			points.append(base + dir * v * tau + Vector2(0, g * tau * tau))
		_ribbon(points, r * 0.07 * p.size, Color(0.55, 0.52, 0.5, 0.7 * fade), true)
		draw_circle(points[points.size() - 1], r * 0.035 * p.size + 0.5, _with_alpha(Color(1.0, 0.6, 0.2), fade))

# ─────────────────────────
# Chaos: Fluchkreis am Boden, darüber eine Rauchkuppel, violetter Schein und wirbelnde Splitter

func _draw_chaos(t: float) -> void:
	var r := radius
	var appear := _ease_out(clampf(t / 0.25, 0.0, 1.0))
	var fade := 1.0 - clampf((t - 0.7) / 0.3, 0.0, 1.0)
	var a := appear * fade
	var center := Vector2(0, (GROUND + 0.1) * r)
	var rx := r * 1.15 * (0.6 + 0.4 * appear)
	var ry := rx * 0.36
	var rot := _flip * t * 1.5
	_glow(center, rx * 2.0, _with_alpha(CHAOS_COLORS[0], 0.35 * a))
	_draw_ellipse_arc(center, rx, ry, _with_alpha(CHAOS_COLORS[0], 0.5 * a), r * 0.1 + 1.0)
	_draw_ellipse_arc(center, rx, ry, _with_alpha(CHAOS_COLORS[2], a), r * 0.03 + 1.0)
	_draw_ellipse_arc(center, rx * 0.8, ry * 0.8, _with_alpha(CHAOS_COLORS[0], 0.8 * a), r * 0.02 + 1.0)
	# Fünfstern im Kreis
	var star := PackedVector2Array()
	for i in 6:
		var ang := rot + (i * 2 % 5) * TAU / 5.0
		star.append(center + Vector2(cos(ang) * rx * 0.8, sin(ang) * ry * 0.8))
	draw_polyline(star, _with_alpha(CHAOS_COLORS[0], 0.85 * a), r * 0.025 + 1.0, true)
	# Runen zwischen den Ringen
	for i in 10:
		var ang := -rot * 0.6 + i * TAU / 10.0
		var pos := center + Vector2(cos(ang) * rx * 0.9, sin(ang) * ry * 0.9)
		_draw_poly(_polygon(pos, r * 0.045, 4, ang), _with_alpha(CHAOS_COLORS[2], a))
	# Energiekern über dem Kreis
	var pulse := 0.85 + 0.15 * sin(t * 30.0)
	_glow(Vector2(0, 0.1 * r), r * 1.8 * pulse, _with_alpha(CHAOS_COLORS[0], 0.5 * a))
	_glow(Vector2(0, 0.1 * r), r * 0.6 * pulse, _with_alpha(CHAOS_COLORS[2], 0.6 * a))

# ─────────────────────────
# Heilung: weiches grünes Leuchten, Kreuze steigen auf

func _draw_heal(t: float) -> void:
	var r := radius
	_glow(Vector2(0, r * 0.1), r * 2.3, _with_alpha(HEAL_COLOR, 0.35 * sin(PI * t)))
	for p: Part in _parts:
		var s := clampf((t - p.delay) / 0.75, 0.0, 1.0)
		if s <= 0.0 or s >= 1.0:
			continue
		var pos := Vector2(p.offset * r * 0.7, r * 0.6 - s * r * 1.3 * p.speed)
		var size := r * 0.09 * p.size
		var a := sin(PI * s)
		_glow(pos, size * 4.0, _with_alpha(HEAL_COLOR, 0.5 * a))
		var c := _with_alpha(HEAL_COLOR.lightened(0.5), a)
		draw_line(pos - Vector2(size, 0), pos + Vector2(size, 0), c, size * 0.6 + 1.0, true)
		draw_line(pos - Vector2(0, size), pos + Vector2(0, size), c, size * 0.6 + 1.0, true)

# ─────────────────────────
# Hilfen

## Weicher Schein (Durchmesser size)
func _glow(pos: Vector2, size: float, c: Color) -> void:
	if size <= 0.0 or c.a <= 0.0:
		return
	draw_texture_rect(_texture("glow"), Rect2(pos - Vector2(size, size) / 2.0, Vector2(size, size)), false, c)

## Band aus Dreiecken zwischen zwei gleich langen Rändern (ohne Triangulierung, daher auch bei Krümmung stabil)
func _strip(left: PackedVector2Array, right: PackedVector2Array, c: Color) -> void:
	var n := mini(left.size(), right.size())
	if n < 2 or c.a <= 0.0:
		return
	var points := left.slice(0, n) + right.slice(0, n)
	var indices := PackedInt32Array()
	for i in n - 1:
		indices.append_array(PackedInt32Array([i, i + 1, n + i, i + 1, n + i + 1, n + i]))
	var colors := PackedColorArray()
	colors.resize(points.size())
	colors.fill(c)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors)

## Spitze Zunge von base in Richtung dir (Flamme, Strähne): bend krümmt sie zur Seite,
## wedge = am Fuß am breitesten (Spritzer), sonst blattförmig mit Spitzen an beiden Enden (Flamme)
func _tongue(base: Vector2, dir: Vector2, length: float, width: float, bend: float, c: Color, wedge := false) -> void:
	if length < 1.0 or width < 0.3 or c.a <= 0.0:
		return
	var n := dir.orthogonal()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var steps := 10
	for i in steps + 1:
		var u := float(i) / steps
		var center := base + dir * length * u + n * bend * length * u * u
		var tangent := (dir * length + n * 2.0 * bend * length * u).normalized()
		var side := tangent.orthogonal()
		var w := width * 0.5 * (pow(1.0 - u, 0.8) if wedge else sin(PI * pow(u, 0.55)))
		left.append(center + side * w)
		right.append(center - side * w)
	_strip(left, right, c)

## Spitz auslaufendes Band entlang einer Linie; to_head = dünn am Anfang, dick am Ende (Rauchspur)
func _ribbon(points: PackedVector2Array, width: float, c: Color, to_head := false) -> void:
	var n := points.size()
	if n < 2 or c.a <= 0.0:
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n:
		var u := float(i) / (n - 1)
		var nrm := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).orthogonal().normalized()
		var w := width * 0.5 * (u if to_head else sin(PI * u))
		left.append(points[i] + nrm * w)
		right.append(points[i] - nrm * w)
	_strip(left, right, c)

## Sichel entlang einer Ellipse, in der Mitte am dicksten
func _tapered_arc(center: Vector2, rx: float, ry: float, start: float, arc: float, width: float, c: Color) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var steps := 18
	for i in steps + 1:
		var u := float(i) / steps
		var a := start + arc * u
		var p := center + Vector2(cos(a) * rx, sin(a) * ry)
		var nrm := Vector2(cos(a) / maxf(rx, 0.01), sin(a) / maxf(ry, 0.01)).normalized()
		var w := width * 0.5 * sin(PI * u)
		left.append(p + nrm * w)
		right.append(p - nrm * w)
	_strip(left, right, c)

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

func _ellipse(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 24:
		var a := i * TAU / 24.0
		points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return points

func _draw_ellipse_arc(center: Vector2, rx: float, ry: float, c: Color, width: float, start := 0.0, arc := TAU) -> void:
	if c.a <= 0.0:
		return
	var points := PackedVector2Array()
	var steps := 32
	for i in steps + 1:
		var a := start + arc * float(i) / steps
		points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(points, c, width, true)

func _with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0))

func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)

func _ease_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
