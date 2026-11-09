extends TextureRect

## Bühne für Kampf-Effekte (battle_vfx.gd) über einem Monsterbild: die Effekte werden in einen eigenen SubViewport
## gezeichnet und dessen Bild mit dem "Lebende Pixel"-Shader angezeigt, damit sie wie die Monster aussehen.
## Wird bei Bedarf angelegt (siehe for_target) und löscht sich, sobald kein Effekt mehr läuft.

const BATTLE_VFX := preload("res://script/scenes/battle/battle_vfx.gd")
## Effekte ragen über das Monsterbild hinaus (Brocken von oben, Funken, Schild): so viel größer ist die Bühne
const PADDING := 1.6
## Radius der Effekte im Verhältnis zum Monsterbild
const RADIUS_FACTOR := 0.4
## Name des Knotens im Elternknoten, damit alle Effekte eines Monsters dieselbe Bühne nutzen
const NODE_NAME := "BattleVfxLayer"

static var _material: ShaderMaterial

var _viewport: SubViewport
var _radius: float

## Bühne über target (ein Control im Elternknoten parent) holen oder anlegen
static func for_target(parent: Control, target: Control) -> Node:
	var layer = parent.get_node_or_null(NODE_NAME)
	if layer == null or layer.is_queued_for_deletion():
		layer = load("res://script/scenes/battle/battle_vfx_layer.gd").new()
		layer.name = NODE_NAME
		parent.add_child(layer)
	layer.fit_to(parent, target)
	return layer

static func _living_material() -> ShaderMaterial:
	if _material == null:
		_material = Monmap.LIVING_MATERIAL.duplicate()
		_material.set_shader_parameter("keep_alpha", true)
		# auch die zarten Teile (Rauch, Schildfüllung, Ausblenden) bleiben sichtbar
		_material.set_shader_parameter("alpha_cutoff", 0.02)
	return _material

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 9
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	material = _living_material()
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	texture = _viewport.get_texture()

## Bühne mittig über target legen, mit Platz für überstehende Effekte
func fit_to(parent: Control, target: Control) -> void:
	var target_pos := target.global_position - parent.global_position
	var stage := (target.size * PADDING).ceil()
	position = target_pos + target.size / 2.0 - stage / 2.0
	size = stage
	_viewport.size = Vector2i(stage)
	_radius = minf(target.size.x, target.size.y) * RADIUS_FACTOR

## Effekt abspielen, accent färbt z. B. den Hieb in der Elementfarbe
func play(kind: int, accent := Color.WHITE, delay := 0.0) -> void:
	var vfx: Node2D = BATTLE_VFX.new()
	vfx.setup(size / 2.0, _radius, kind, accent, delay)
	_viewport.add_child(vfx)

func _process(_delta: float) -> void:
	# letzter Effekt vorbei: Bühne samt Viewport wieder weg
	if _viewport.get_children().all(func(child: Node): return child.is_queued_for_deletion()):
		queue_free()
