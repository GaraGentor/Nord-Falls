class_name FallenSoul
extends Control

## Fällt im Kampf ein Monster, verlässt seine Seele den Körper: der Körper zerfällt in seine lebenden Pixel, aus
## seiner Mitte löst sich ein Irrlicht in der Form der Element-Kugeln (ElementOrbs.Orb.draw_orb), hell in der
## Farbe seines Elements. Es steigt schwankend auf, der Schweif weht nach unten hinterher, Funken lösen sich, dann
## verblasst es. So sieht man, wer gefallen ist, und das Ende des Kampfs kommt nicht schlagartig
## (battle.gd wartet DURATION ab).

## Dauer vom Verlassen des Körpers bis zum vollständigen Verblassen
const DURATION := 1.6
## Zerfall des Körpers in Pixel
const DISSOLVE := 0.55
## Herauslösen der Seele aus dem Körper (wächst aus der Mitte)
const EMERGE := 0.3
const RISE := 170.0
## seitliches Schwanken beim Aufsteigen
const WOBBLE := 9.0
## Seelenfarbe: Elementfarbe, so weit aufgehellt und ins Bläuliche gezogen
const SOUL_TINT := Color(0.75, 0.92, 1.0)
const SOUL_MIX := 0.45
const BODY_TINT := Color(0.55, 0.85, 1.0)
## Funken pro Sekunde, die sich vom Schweif lösen
const SPARKS_PER_SECOND := 22.0

var _body: TextureRect
var _wisp: Wisp
var _time := 0.0
var _spark_debt := 0.0
var _home := Vector2.ZERO

## Setzt die Seele genau über das gezeichnete Bild des Monsters (scene: MonsterScene mit texture_rect und
## drawn_image_rect) und lässt sie aufsteigen. host: Ebene über dem Kampffeld
static func spawn(scene: Control, host: Node) -> void:
	var body: TextureRect = scene.texture_rect if scene else null
	if body == null or body.texture == null or not scene.is_visible_in_tree() or host == null:
		return
	var image: Rect2 = scene.drawn_image_rect()
	if image.size == Vector2.ZERO:
		return
	var soul := FallenSoul.new()
	soul.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(soul)
	soul.size = image.size
	soul.global_position = scene.global_position + image.position
	soul._build(body, _soul_color(scene.get("mon")))
	soul._play()

static func _soul_color(mon) -> Color:
	var color := SOUL_TINT
	if mon is Monster:
		color = Color(Helper.color_by_type(mon._type)).lerp(SOUL_TINT, SOUL_MIX)
	return color

func _build(body: TextureRect, color: Color) -> void:
	# Körper: dasselbe Bild, bläulich, zerfällt über reveal des Living-Shaders in seine Pixel
	_body = TextureRect.new()
	_body.texture = body.texture
	_body.flip_h = body.flip_h
	_body.flip_v = body.flip_v
	_body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_body.stretch_mode = TextureRect.STRETCH_SCALE
	_body.material = Monmap.MONSTER_MATERIAL.duplicate()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.self_modulate = BODY_TINT
	_body.size = size
	add_child(_body)
	# Seele: in der Mitte des Körpers, so groß wie zum Monster passend
	var radius := clampf(size.x * 0.1, 12.0, 24.0)
	_wisp = Wisp.new(color, radius)
	_home = Vector2(size.x / 2, size.y * 0.55)
	_wisp.position = _home
	_wisp.scale = Vector2.ZERO
	add_child(_wisp)

func _play() -> void:
	var tween := create_tween().set_parallel()
	# Körper leuchtet kurz auf und zerfällt
	tween.tween_property(_body, "modulate", Color(1.8, 1.8, 2.0, 0.85), 0.12)
	tween.tween_property(_body.material, "shader_parameter/reveal", 0.0, DISSOLVE).set_delay(0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_body, "modulate:a", 0.0, DISSOLVE).set_delay(0.12)
	# Seele wächst aus dem Körper, schwillt kurz über und steigt dann immer schneller auf
	tween.tween_property(_wisp, "scale", Vector2.ONE * 1.2, EMERGE).set_delay(0.08) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_wisp, "scale", Vector2.ONE * 0.75, DURATION - EMERGE - 0.08).set_delay(EMERGE + 0.08)
	tween.tween_property(_wisp, "rise", RISE, DURATION - 0.2).set_delay(0.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(_wisp, "modulate:a", 0.0, 0.5).set_delay(DURATION - 0.5)
	tween.chain().tween_callback(queue_free)

func _process(delta: float) -> void:
	_time += delta
	if _wisp == null:
		return
	_wisp.position = _home + Vector2(sin(_time * 6.0) * WOBBLE * minf(_time * 2.0, 1.0), -_wisp.rise)
	# Funken lösen sich vom Schweif und sinken verglühend zurück
	if _wisp.scale.x > 0.5 and _wisp.modulate.a > 0.2:
		_spark_debt += delta * SPARKS_PER_SECOND
		while _spark_debt >= 1.0:
			_spark_debt -= 1.0
			var spark := Spark.new(_wisp.color.lightened(0.4))
			spark.position = _wisp.position + Vector2(randf_range(-0.6, 0.6), randf_range(0.6, 2.2)) * _wisp.radius
			add_child(spark)
			# hinter der Seele
			move_child(spark, _wisp.get_index())


## Das Irrlicht selbst: Element-Kugel, auf den Kopf gestellt, damit der Schweif beim Aufsteigen nach unten weht.
## Position = Mitte des Körpers
class Wisp extends Control:
	var color: Color
	var radius: float
	## wie weit die Seele schon aufgestiegen ist (getweent)
	var rise := 0.0
	var _time := 0.0

	func _init(soul_color: Color, soul_radius: float) -> void:
		color = soul_color
		radius = soul_radius
		mouse_filter = MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		# weicher Schein um die Seele
		for i in 5:
			draw_circle(Vector2.ZERO, radius * (1.4 + 0.45 * (5 - i)), Color(color, 0.035 * (i + 1)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, -1))
		ElementOrbs.Orb.draw_orb(self, Vector2.ZERO, radius, color, _time * 1.6, false, true, true)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		# heller Kern
		draw_circle(Vector2.ZERO, radius * 0.45, Color(1, 1, 1, 0.55))


## Funke, der sich von der Seele löst: sinkt leicht, schrumpft und verglüht
class Spark extends Control:
	var _color: Color
	var _life := 0.0
	var _max_life := randf_range(0.35, 0.7)
	var _radius := randf_range(1.5, 3.2)
	var _velocity := Vector2(randf_range(-18.0, 18.0), randf_range(10.0, 40.0))

	func _init(color: Color) -> void:
		_color = color
		mouse_filter = MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_life += delta
		if _life >= _max_life:
			queue_free()
			return
		position += _velocity * delta
		queue_redraw()

	func _draw() -> void:
		var t := _life / _max_life
		draw_circle(Vector2.ZERO, _radius * (1.0 - t) * 2.2, Color(_color, 0.18 * (1.0 - t)))
		draw_circle(Vector2.ZERO, _radius * (1.0 - t), Color(_color, 1.0 - t))
