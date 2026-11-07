class_name MapWeather
extends Control

## Wetter über der Karte: Partikel, Wolken mit Schatten, Nebel, Blitze und Vögel.
## Der Wind pendelt, dadurch fliegen Wolken und Asche im Sturm hin und her.

const FOG_SHADER := preload("res://script/scenes/world_map/map_fog.gdshader")
const CLOUD_TEXTURES: Array[Texture2D] = [
	preload("res://assets/ui/map/deco/cloud_1.svg"),
	preload("res://assets/ui/map/deco/cloud_2.svg"),
	preload("res://assets/ui/map/deco/cloud_3.svg"),
]
const CLOUD_SHADOW_OFFSET := Vector2(26.0, 38.0)
const CLOUD_SHADOW_ALPHA := 0.16
## Wolken bewegen sich beim Scrollen langsamer mit als die Karte, das gibt Tiefe
const CLOUD_PARALLAX := 0.35
const BOLT_DURATION := 0.28

## dir/spread: Startrichtung, vel: Tempo, grav: Schwerkraft, gust: wie stark der Wind die Partikel schiebt
## shape: "soft" (weicher Punkt), "square" (Pixel), "streak" (in Flugrichtung gestreckt), "ring" (Blase)
const PARTICLES := {
	"ash": {"amount": 70, "life": 9.0, "dir": Vector2(0.1, 1.0), "spread": 25.0, "vel": [14.0, 34.0], "grav": Vector2(0, 5), "gust": 16.0, "scale": [2.0, 4.0], "color": "#c4bbb2", "shape": "square"},
	"ash_fine": {"amount": 90, "life": 7.0, "dir": Vector2(0.1, 1.0), "spread": 35.0, "vel": [20.0, 44.0], "grav": Vector2(0, 5), "gust": 26.0, "scale": [1.0, 2.0], "color": "#8f867d", "shape": "square"},
	"ash_storm": {"amount": 170, "life": 3.6, "dir": Vector2(1.0, 0.12), "spread": 12.0, "vel": [20.0, 60.0], "grav": Vector2(0, 12), "gust": 200.0, "scale": [1.0, 3.0], "color": "#d0c8bf", "shape": "square"},
	"ash_storm_big": {"amount": 36, "life": 4.5, "dir": Vector2(1.0, 0.1), "spread": 20.0, "vel": [10.0, 40.0], "grav": Vector2(0, 16), "gust": 130.0, "scale": [4.0, 7.0], "color": "#5a5149", "shape": "square"},
	"ember": {"amount": 46, "life": 5.0, "dir": Vector2(0.0, -1.0), "spread": 22.0, "vel": [24.0, 60.0], "grav": Vector2(0, -3), "gust": 22.0, "scale": [2.0, 3.0], "color": "#ffa13d", "end_color": "#ff3a10", "shape": "square"},
	"ember_big": {"amount": 12, "life": 4.5, "dir": Vector2(0.0, -1.0), "spread": 18.0, "vel": [34.0, 70.0], "grav": Vector2(0, -3), "gust": 22.0, "scale": [0.35, 0.6], "color": "#ffd46a", "end_color": "#ff4a10", "shape": "soft"},
	"smoke_fine": {"amount": 14, "life": 7.0, "dir": Vector2(0.0, -1.0), "spread": 15.0, "vel": [10.0, 20.0], "grav": Vector2.ZERO, "gust": 10.0, "scale": [1.2, 2.4], "color": "#1a0d0a", "alpha": 0.35, "shape": "soft"},
	"snow": {"amount": 90, "life": 8.0, "dir": Vector2(0.1, 1.0), "spread": 18.0, "vel": [26.0, 52.0], "grav": Vector2.ZERO, "gust": 30.0, "scale": [2.0, 3.0], "color": "#ffffff", "shape": "square"},
	"snow_big": {"amount": 22, "life": 7.0, "dir": Vector2(0.1, 1.0), "spread": 14.0, "vel": [40.0, 66.0], "grav": Vector2.ZERO, "gust": 40.0, "scale": [0.22, 0.4], "color": "#ffffff", "shape": "soft"},
	"glint": {"amount": 18, "life": 1.6, "dir": Vector2(0.0, -1.0), "spread": 180.0, "vel": [0.0, 3.0], "grav": Vector2.ZERO, "gust": 0.0, "scale": [2.0, 3.0], "color": "#ffffff", "shape": "square"},
	"rain": {"amount": 110, "life": 0.75, "dir": Vector2(0.14, 1.0), "spread": 2.0, "vel": [460.0, 620.0], "grav": Vector2.ZERO, "gust": 120.0, "scale": [0.45, 0.8], "color": "#a9c6df", "alpha": 0.6, "shape": "streak"},
	"rain_heavy": {"amount": 210, "life": 0.6, "dir": Vector2(0.28, 1.0), "spread": 3.0, "vel": [640.0, 860.0], "grav": Vector2.ZERO, "gust": 340.0, "scale": [0.6, 1.1], "color": "#cfe0ff", "alpha": 0.65, "shape": "streak"},
	"drizzle": {"amount": 34, "life": 0.9, "dir": Vector2(0.08, 1.0), "spread": 2.0, "vel": [300.0, 400.0], "grav": Vector2.ZERO, "gust": 40.0, "scale": [0.3, 0.5], "color": "#cdeaf5", "alpha": 0.45, "shape": "streak"},
	"bubble": {"amount": 20, "life": 7.0, "dir": Vector2(0.0, -1.0), "spread": 10.0, "vel": [12.0, 34.0], "grav": Vector2(0, -2), "gust": 6.0, "scale": [0.2, 0.55], "color": "#d8f4ff", "alpha": 0.7, "shape": "ring"},
	"dust": {"amount": 40, "life": 9.0, "dir": Vector2(1.0, -0.1), "spread": 40.0, "vel": [4.0, 16.0], "grav": Vector2.ZERO, "gust": 12.0, "scale": [1.5, 3.0], "color": "#f0dfb8", "alpha": 0.55, "shape": "square"},
	"leaf": {"amount": 14, "life": 9.0, "dir": Vector2(0.5, 1.0), "spread": 30.0, "vel": [20.0, 40.0], "grav": Vector2(0, 2), "gust": 40.0, "scale": [3.0, 5.0], "color": "#c6a24a", "shape": "square", "spin": true},
	"feather_fall": {"amount": 8, "life": 10.0, "dir": Vector2(0.4, 1.0), "spread": 40.0, "vel": [14.0, 30.0], "grav": Vector2.ZERO, "gust": 30.0, "scale": [0.3, 0.5], "color": "#ffffff", "shape": "soft", "spin": true},
	"sand": {"amount": 210, "life": 2.6, "dir": Vector2(1.0, 0.04), "spread": 6.0, "vel": [30.0, 90.0], "grav": Vector2(0, 6), "gust": 280.0, "scale": [1.0, 2.0], "color": "#8a6c38", "shape": "square"},
	"sand_fine": {"amount": 60, "life": 1.4, "dir": Vector2(1.0, 0.02), "spread": 3.0, "vel": [40.0, 110.0], "grav": Vector2.ZERO, "gust": 420.0, "scale": [0.4, 0.9], "color": "#6e5428", "alpha": 0.5, "shape": "streak"},
	"wind": {"amount": 26, "life": 1.8, "dir": Vector2(1.0, 0.0), "spread": 3.0, "vel": [40.0, 120.0], "grav": Vector2.ZERO, "gust": 340.0, "scale": [0.6, 1.3], "color": "#ffffff", "alpha": 0.35, "shape": "streak"},
	"steam": {"amount": 22, "life": 7.0, "dir": Vector2(0.0, -1.0), "spread": 14.0, "vel": [12.0, 30.0], "grav": Vector2(0, -2), "gust": 14.0, "scale": [1.2, 3.0], "color": "#ffffff", "alpha": 0.32, "shape": "soft"},
	"steam_fine": {"amount": 30, "life": 4.5, "dir": Vector2(0.0, -1.0), "spread": 20.0, "vel": [16.0, 40.0], "grav": Vector2(0, -2), "gust": 16.0, "scale": [0.3, 0.6], "color": "#ffffff", "alpha": 0.4, "shape": "soft"},
	"spark": {"amount": 34, "life": 0.9, "dir": Vector2(0.0, -1.0), "spread": 180.0, "vel": [40.0, 150.0], "grav": Vector2(0, 90), "gust": 30.0, "scale": [1.5, 2.5], "color": "#fff09a", "end_color": "#ffb020", "shape": "square"},
	"firefly": {"amount": 22, "life": 5.0, "dir": Vector2(0.0, -1.0), "spread": 180.0, "vel": [6.0, 20.0], "grav": Vector2.ZERO, "gust": 8.0, "scale": [0.2, 0.34], "color": "#e7ff6a", "shape": "soft", "blink": true},
	"spore": {"amount": 26, "life": 9.0, "dir": Vector2(0.0, -1.0), "spread": 50.0, "vel": [3.0, 12.0], "grav": Vector2.ZERO, "gust": 8.0, "scale": [1.0, 2.0], "color": "#dcebb0", "alpha": 0.6, "shape": "square"},
	"rift": {"amount": 60, "life": 3.6, "dir": Vector2(0.0, -1.0), "spread": 180.0, "vel": [6.0, 26.0], "grav": Vector2.ZERO, "gust": 90.0, "scale": [2.0, 4.0], "color": "#5cf2d6", "end_color": "#ff4fd8", "shape": "square", "orbit": 60.0},
	"rift_rise": {"amount": 18, "life": 4.0, "dir": Vector2(0.0, -1.0), "spread": 25.0, "vel": [20.0, 60.0], "grav": Vector2.ZERO, "gust": 40.0, "scale": [0.3, 0.6], "color": "#ffb3f0", "end_color": "#7b3fe4", "shape": "soft"},
}

var scroll_container: ScrollContainer

var _look: Dictionary = {}
var _time := 0.0
## -1 bis 1, Vorzeichen ist die Windrichtung
var _wind := 0.0
var _wind_cfg: Dictionary = {}
var _emitters: Array[Dictionary] = []
var _clouds: Array[Dictionary] = []
var _flyers: Array[Dictionary] = []
var _fog: ColorRect
var _fog_material: ShaderMaterial
var _fog_drift := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _next_bolt := 0.0
var _bolt_points := PackedVector2Array()
var _bolt_time := 0.0
var _flash := 0.0

static var _textures := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_fit_emitters)

func apply_look(look: Dictionary) -> void:
	_look = look
	for child in get_children():
		child.queue_free()
	_emitters.clear()
	_clouds.clear()
	_flyers.clear()
	_bolt_points = PackedVector2Array()
	_flash = 0.0
	_wind_cfg = look.get("wind", {"period": 30.0, "bias": 0.5})
	_build_fog(look.get("fog", {}))
	_build_clouds(look.get("clouds", {}))
	_build_flyers(look.get("flyers", {}))
	for preset_name in look.get("particles", []):
		_add_emitter(PARTICLES[preset_name])
	_fit_emitters()
	if look.has("lightning"):
		_next_bolt = _rng.randf_range(0.8, 2.0)

# ── Aufbau ─────────────────────────────

func _build_fog(cfg: Dictionary) -> void:
	_fog = null
	if cfg.is_empty() and not _look.has("lightning"):
		return
	_fog_material = ShaderMaterial.new()
	_fog_material.shader = FOG_SHADER
	_fog_material.set_shader_parameter("fog_color", Color(cfg.get("color", "#ffffff")))
	_fog_material.set_shader_parameter("amount", cfg.get("amount", 0.0))
	_fog_material.set_shader_parameter("scale", cfg.get("scale", 320.0))
	if _look.has("lightning"):
		_fog_material.set_shader_parameter("flash_color", Color(_look.lightning.color))
	_fog = ColorRect.new()
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.material = _fog_material
	add_child(_fog)
	_fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build_clouds(cfg: Dictionary) -> void:
	for i in cfg.get("count", 0):
		var cloud_size := _rng.randf_range(cfg.size[0], cfg.size[1])
		_clouds.append({
			"texture": CLOUD_TEXTURES.pick_random(),
			"x": _rng.randf_range(-cloud_size, maxf(size.x, 1280.0)),
			"y": _rng.randf(),
			"size": cloud_size,
			"color": Color(cfg.color, cfg.alpha * _rng.randf_range(0.75, 1.0)),
			# große Wolken wirken näher und ziehen schneller
			"speed": cfg.speed * remap(cloud_size, cfg.size[0], cfg.size[1], 0.65, 1.2),
			"phase": _rng.randf() * TAU,
			"flip": _rng.randf() < 0.5,
		})

func _build_flyers(cfg: Dictionary) -> void:
	if cfg.is_empty():
		return
	var texture: Texture2D = load("res://assets/ui/map/deco/%s.svg" % cfg.icon)
	for i in cfg.count:
		_flyers.append({
			"texture": texture,
			"x": _rng.randf_range(0.0, maxf(size.x, 1280.0)),
			"y": _rng.randf(),
			"size": cfg.size * _rng.randf_range(0.75, 1.15),
			"color": Color(cfg.color),
			"speed": cfg.speed * _rng.randf_range(0.8, 1.25) * (1.0 if _rng.randf() < 0.5 else -1.0),
			"phase": _rng.randf() * TAU,
		})

func _add_emitter(preset: Dictionary) -> void:
	var particles := CPUParticles2D.new()
	particles.amount = preset.amount
	particles.lifetime = preset.life
	particles.preprocess = preset.life
	particles.randomness = 0.6
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.direction = preset.dir
	particles.spread = preset.spread
	particles.gravity = preset.grav
	particles.initial_velocity_min = preset.vel[0]
	particles.initial_velocity_max = preset.vel[1]
	particles.scale_amount_min = preset.scale[0]
	particles.scale_amount_max = preset.scale[1]
	particles.texture = _texture_for(preset.shape)
	particles.color_ramp = _ramp_for(preset)
	if preset.shape == "streak":
		particles.particle_flag_align_y = true
	if preset.get("spin", false):
		particles.angular_velocity_min = -120.0
		particles.angular_velocity_max = 120.0
		particles.angle_min = -180.0
		particles.angle_max = 180.0
	if preset.has("orbit"):
		particles.tangential_accel_min = preset.orbit * 0.5
		particles.tangential_accel_max = preset.orbit
	add_child(particles)
	_emitters.append({"node": particles, "grav": preset.grav, "gust": preset.gust})

func _ramp_for(preset: Dictionary) -> Gradient:
	var color := Color(preset.color)
	var alpha: float = preset.get("alpha", 1.0)
	var end_color: Color = Color(preset.end_color) if preset.has("end_color") else color
	var gradient := Gradient.new()
	if preset.get("blink", false):
		gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.3, 0.5, 0.6, 0.8, 1.0])
		var off := Color(color, 0.0)
		gradient.colors = PackedColorArray([off, color, off, color, off, color, off])
		return gradient
	# Partikel entstehen über die ganze Fläche, sie müssen daher ein- und ausblenden
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.7, 1.0])
	gradient.colors = PackedColorArray([Color(color, 0.0), Color(color, alpha), Color(color.lerp(end_color, 0.7), alpha), Color(end_color, 0.0)])
	return gradient

func _texture_for(shape: String) -> Texture2D:
	if not _textures.has(shape):
		_textures[shape] = _make_texture(shape)
	return _textures[shape]

func _make_texture(shape: String) -> Texture2D:
	match shape:
		"square":
			var pixel := Image.create(1, 1, false, Image.FORMAT_RGBA8)
			pixel.fill(Color.WHITE)
			return ImageTexture.create_from_image(pixel)
		"streak":
			var streak := Image.create(2, 22, false, Image.FORMAT_RGBA8)
			for y in 22:
				var alpha := 1.0 - absf(y - 11.0) / 11.0
				streak.set_pixel(0, y, Color(1, 1, 1, alpha))
				streak.set_pixel(1, y, Color(1, 1, 1, alpha))
			return ImageTexture.create_from_image(streak)
		"ring":
			return _radial_texture(PackedFloat32Array([0.0, 0.62, 0.72, 0.9, 1.0]), PackedColorArray([
				Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.12), Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)]))
		_:
			return _radial_texture(PackedFloat32Array([0.0, 0.25, 1.0]), PackedColorArray([
				Color(1, 1, 1, 1), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)]))

func _radial_texture(offsets: PackedFloat32Array, colors: PackedColorArray) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture

func _fit_emitters() -> void:
	for emitter in _emitters:
		emitter.node.position = size * 0.5
		emitter.node.emission_rect_extents = size * 0.5 + Vector2(40.0, 40.0)

# ── Laufzeit ───────────────────────────

func _process(delta: float) -> void:
	if _look.is_empty():
		return
	_time += delta
	var bias: float = _wind_cfg.bias
	_wind = lerpf(sin(_time * TAU / _wind_cfg.period), 1.0, bias)
	for emitter in _emitters:
		emitter.node.gravity = emitter.grav + Vector2(_wind * emitter.gust, 0.0)
	for cloud in _clouds:
		cloud.x += cloud.speed * _wind * delta
		cloud.x = wrapf(cloud.x, -cloud.size * 1.2, size.x + cloud.size * 0.2)
	for flyer in _flyers:
		flyer.x = wrapf(flyer.x + flyer.speed * delta, -60.0, size.x + 60.0)
	if _fog:
		_fog_drift += Vector2(_wind, 0.2) * _look.get("fog", {}).get("speed", 0.05) * delta
		_fog_material.set_shader_parameter("drift", _fog_drift)
	if _look.has("lightning"):
		_update_lightning(delta)
	queue_redraw()

func _update_lightning(delta: float) -> void:
	_next_bolt -= delta
	if _next_bolt <= 0.0:
		_next_bolt = _rng.randf_range(_look.lightning.min, _look.lightning.max)
		_strike()
	_bolt_time = maxf(_bolt_time - delta, 0.0)
	# zweimal zucken wie ein echter Blitz
	var t := _bolt_time / BOLT_DURATION
	_flash = maxf(_flash - delta * 3.0, 0.0)
	if t > 0.0 and t < 0.55 and _flash < 0.3:
		_flash = 0.5
	if _fog_material:
		_fog_material.set_shader_parameter("flash", _flash)

func _strike() -> void:
	_bolt_time = BOLT_DURATION
	_flash = 0.85
	_bolt_points = PackedVector2Array()
	var pos := Vector2(_rng.randf_range(size.x * 0.1, size.x * 0.9), -10.0)
	var bottom := _rng.randf_range(size.y * 0.5, size.y * 0.95)
	while pos.y < bottom:
		_bolt_points.append(pos)
		pos += Vector2(_rng.randf_range(-42.0, 42.0), _rng.randf_range(18.0, 46.0))
	_bolt_points.append(pos)

func _draw() -> void:
	var scroll := float(scroll_container.scroll_vertical) if scroll_container else 0.0
	var band := size.y + 200.0
	for cloud in _clouds:
		var y := fposmod(cloud.y * band - scroll * CLOUD_PARALLAX, band) - 100.0 + sin(_time * 0.3 + cloud.phase) * 12.0
		var cloud_size := Vector2(cloud.size, cloud.size * 0.5)
		var rect := Rect2(cloud.x, y - cloud_size.y * 0.5, cloud.size * (-1.0 if cloud.flip else 1.0), cloud_size.y)
		if cloud.flip:
			rect.position.x += cloud.size
		var shadow := rect
		shadow.position += CLOUD_SHADOW_OFFSET
		draw_texture_rect(cloud.texture, shadow, false, Color(0, 0, 0, CLOUD_SHADOW_ALPHA))
		draw_texture_rect(cloud.texture, rect, false, cloud.color)
	for flyer in _flyers:
		var y: float = flyer.y * size.y + sin(_time * 0.7 + flyer.phase) * 18.0
		var flap := 0.55 + 0.45 * absf(sin(_time * 5.5 + flyer.phase))
		draw_set_transform(Vector2(flyer.x, y), 0.0, Vector2(signf(flyer.speed), flap))
		var half: float = flyer.size * 0.5
		draw_texture_rect(flyer.texture, Rect2(-half, -half, flyer.size, flyer.size), false, flyer.color)
	draw_set_transform(Vector2.ZERO)
	if _bolt_time > 0.0 and _bolt_points.size() >= 2:
		var alpha := _bolt_time / BOLT_DURATION
		var color := Color(_look.lightning.color)
		draw_polyline(_bolt_points, Color(color, alpha * 0.35), 9.0)
		draw_polyline(_bolt_points, Color(Color.WHITE.lerp(color, 0.3), alpha), 3.0)
