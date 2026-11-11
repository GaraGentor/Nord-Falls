class_name BossRelicOrbit
extends Control

## Karte: die schon gewürfelten Boss-Relikte des Biom-Bosses (Map.boss_relics) kreisen um sein Symbol,
## damit man sich vor dem Kampf darauf einstellen kann. Hinter dem Boss (obere Bahnhälfte) werden sie kleiner und
## verschwinden hinter ihm. Tooltip mit Name und Wirkung; ein Klick öffnet die Übersicht wie im Kampf
## (BossRelicOverlay), solange die Maus auf einem Relikt ist, hält die Bahn an.
## Hängt am Boss-Button und legt die Relikte direkt daneben ab, nur sie nehmen Klicks an.

const ICON_SIZE := Vector2(46, 46)
## Halbachsen der Bahn um die Mitte des Boss-Symbols (128 px)
const RADIUS := Vector2(120, 76)
## Umdrehungen pro Sekunde
const SPEED := 0.08
## leichtes Auf und Ab jedes Relikts
const BOB_HEIGHT := 4.0
const BOB_SPEED := 2.2
## Größe hinten bzw. vorne auf der Bahn
const BACK_SCALE := 0.75
const FRONT_SCALE := 1.1
## Helligkeit hinten (hinter dem Boss), vorne volle Helligkeit
const BACK_SHADE := 0.6
## über der Karte und ihren Dialogen
const OVERLAY_LAYER := 60

var _relics: Array = []
var _icons: Array[TextureRect] = []
var _angle := 0.0
var _time := 0.0
var _hovered := false
var _overlay: BossRelicOverlay

func _init(relics: Array) -> void:
	_relics = relics

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	for id in _relics:
		_icons.append(_icon(id))
	# Nachlesen über allem anderen auf einer eigenen Ebene
	var layer := CanvasLayer.new()
	layer.layer = OVERLAY_LAYER
	add_child(layer)
	_overlay = BossRelicOverlay.new()
	layer.add_child(_overlay)
	_place()

func _icon(id: String) -> TextureRect:
	var relic: Dictionary = BossRelics.get_relic(id)
	var icon := TextureRect.new()
	icon.texture = load(relic.icon)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = ICON_SIZE
	icon.pivot_offset = ICON_SIZE / 2
	# eigene Kopie: der goldene Umriss beim Drüberfahren gilt nur für dieses Relikt
	icon.material = BossRelics.RELIC_MATERIAL.duplicate()
	icon.tooltip_text = tr(relic.name) + "\n" + BossRelics.description(id)
	icon.mouse_filter = MOUSE_FILTER_STOP
	icon.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	icon.mouse_entered.connect(_on_hover.bind(icon, true))
	icon.mouse_exited.connect(_on_hover.bind(icon, false))
	icon.gui_input.connect(_on_icon_input)
	# direkt am Boss-Button, nur so können sie hinter sein Symbol (show_behind_parent)
	get_parent().add_child.call_deferred(icon)
	return icon

func _exit_tree() -> void:
	for icon in _icons:
		if is_instance_valid(icon):
			icon.queue_free()

func _process(delta: float) -> void:
	_time += delta
	if not _hovered:
		_angle = fmod(_angle + delta * SPEED * TAU, TAU)
	_place()

## Relikte gleichmäßig auf der Bahn verteilt; die obere Hälfte liegt hinter dem Boss
func _place() -> void:
	var center := size / 2
	for i in _icons.size():
		var icon := _icons[i]
		var a := _angle + TAU * i / _icons.size()
		var depth := (sin(a) + 1.0) / 2.0
		var bob := sin(_time * BOB_SPEED + i) * BOB_HEIGHT
		icon.position = center + Vector2(cos(a) * RADIUS.x, sin(a) * RADIUS.y + bob) - ICON_SIZE / 2
		icon.scale = Vector2.ONE * lerpf(BACK_SCALE, FRONT_SCALE, depth)
		icon.show_behind_parent = depth < 0.5
		var shade := lerpf(BACK_SHADE, 1.0, depth)
		icon.self_modulate = Color(shade, shade, shade)

func _on_hover(icon: TextureRect, on: bool) -> void:
	_hovered = on
	RewardDialog.set_outline(icon.material, on)

func _on_icon_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not _overlay.is_busy():
			_overlay.play_intro(_relics, false)
