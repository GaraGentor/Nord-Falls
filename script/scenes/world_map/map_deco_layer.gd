class_name MapDecoLayer
extends Control

## Verteilt die Biom-Icons auf dem Papier, ohne Felder und Wege zu verdecken.

## Bewegung pro Icon: sway (wiegt im Wind), bob (schaukelt), flicker (lodert), spin (dreht langsam), pulse (atmet)
const ICON_ANIM := {
	"pine": "sway", "tree": "sway", "bush": "sway", "mushroom": "sway", "cactus": "sway", "dead_tree": "sway", "reed": "sway",
	"wave": "bob", "fish": "bob", "lily": "bob", "iceberg": "bob", "feather": "bob", "cloud_small": "bob", "bird": "bob",
	"flame": "flicker", "geyser": "flicker", "tentacle": "sway",
	"swirl": "spin", "star": "spin", "snowflake": "spin",
	"crystal": "pulse", "eye": "pulse", "bolt": "pulse",
}
## Grundgröße in Pixeln, alles Ungenannte ist DEFAULT_SIZE
const ICON_SIZE := {
	"mountain": 118.0, "volcano": 122.0, "dune": 104.0, "iceberg": 76.0, "tree": 70.0, "pine": 68.0, "ruin": 62.0, "cloud_small": 84.0,
	"dead_tree": 66.0, "bone": 40.0, "feather": 40.0, "bird": 36.0, "fish": 42.0, "lily": 44.0, "bolt": 46.0, "star": 40.0, "snowflake": 42.0,
}
const DEFAULT_SIZE := 54.0
## Größter Abstand zwischen zwei Icons, gelöchert wird danach durch die Freiräume um Felder und Wege
const SPACING := 132.0
const LINE_CLEARANCE := 14.0
const EDGE_INSET := 6.0
## Anteil der Icons, die nicht zum Hauptmotiv ihrer Region passen (sonst nur Wälder und Gebirge am Stück)
const STRAY_CHANCE := 0.28
const ICON_ALPHA := 0.72

var _items: Array[Dictionary] = []
var _time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## clear_points: [Position, Radius] der Felder, clear_segments: [Start, Ende] der Wege, jeweils in lokalen Koordinaten
func scatter(deco: Array, rng_seed: int, clear_points: Array, clear_segments: Array) -> void:
	_items.clear()
	if deco.is_empty():
		queue_redraw()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	# gleiche Motive sollen sich zu Regionen zusammenballen, wie Wälder und Gebirge auf einer Karte
	var regions := FastNoiseLite.new()
	regions.seed = rng_seed
	regions.frequency = 0.0035

	var y := EDGE_INSET
	while y < size.y - EDGE_INSET:
		var x := EDGE_INSET
		while x < size.x - EDGE_INSET:
			var pos := Vector2(x, y) + Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.1, 0.9)) * SPACING
			var index := clampi(int((regions.get_noise_2dv(pos) * 0.5 + 0.5) * deco.size()), 0, deco.size() - 1)
			if rng.randf() < STRAY_CHANCE:
				index = rng.randi_range(0, deco.size() - 1)
			var icon: String = deco[index][0]
			var icon_size: float = ICON_SIZE.get(icon, DEFAULT_SIZE) * rng.randf_range(0.8, 1.2)
			if _is_free(pos, icon_size, clear_points, clear_segments):
				_items.append({
					"texture": load("res://assets/ui/map/deco/%s.svg" % icon),
					"pos": pos,
					"size": icon_size,
					"anim": ICON_ANIM.get(icon, ""),
					"tint": Color(deco[index][1], ICON_ALPHA),
					"phase": rng.randf() * TAU,
					"flip": rng.randf() < 0.5,
				})
			x += SPACING
		y += SPACING
	# von hinten nach vorn zeichnen, damit sich Bäume korrekt überlappen
	_items.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	queue_redraw()

func _is_free(pos: Vector2, icon_size: float, clear_points: Array, clear_segments: Array) -> bool:
	if pos.x < icon_size * 0.5 or pos.x > size.x - icon_size * 0.5 or pos.y < icon_size * 0.5 or pos.y > size.y - icon_size * 0.5:
		return false
	var radius := icon_size * 0.5
	for point in clear_points:
		if pos.distance_to(point[0]) < point[1] + radius:
			return false
	for segment in clear_segments:
		var nearest := Geometry2D.get_closest_point_to_segment(pos, segment[0], segment[1])
		if pos.distance_to(nearest) < LINE_CLEARANCE + radius:
			return false
	return true

func _process(delta: float) -> void:
	_time += delta
	if not _items.is_empty():
		queue_redraw()

func _draw() -> void:
	for item in _items:
		var phase: float = _time + item.phase
		var rot := 0.0
		var stretch := Vector2.ONE
		var lift := 0.0
		# gedreht wird um den Fußpunkt, nur spin und pulse um die Mitte
		var centered := false
		match item.anim:
			"sway":
				rot = sin(phase * 1.3) * 0.05
			"bob":
				rot = sin(phase * 0.9) * 0.06
				lift = sin(phase * 1.2) * 3.0
			"flicker":
				stretch = Vector2(1.0 + sin(phase * 7.0) * 0.05, 1.0 + sin(phase * 5.0 + 1.0) * 0.1)
			"spin":
				rot = phase * 0.25
				centered = true
			"pulse":
				stretch = Vector2.ONE * (1.0 + sin(phase * 1.6) * 0.07)
				centered = true
		var half: float = item.size * 0.5
		var anchor: Vector2 = item.pos + Vector2(0.0, lift)
		var offset := Vector2(-half, -half)
		if not centered:
			anchor.y += half
			offset.y = -item.size
		if item.flip:
			stretch.x = -stretch.x
		draw_set_transform(anchor, rot, stretch)
		draw_texture_rect(item.texture, Rect2(offset, Vector2(item.size, item.size)), false, item.tint)
	draw_set_transform(Vector2.ZERO)
