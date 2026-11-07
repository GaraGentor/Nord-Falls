extends RewardDialog

## Ereignis Void: links die eigenen Relikte, rechts der Void. Ein hineingeworfenes Relikt schrumpft
## spiralförmig, der Void fällt in sich zusammen, ein Teppich fährt herein und darauf liegen ein neues
## Relikt gleicher Seltenheit und die Tasche. Der Pfeil oben rechts überspringt das Ereignis,
## ist ein Relikt erst einmal im Void, muss das neue genommen werden.

const RELIC_REWARD := preload("res://script/scenes/relic_reward/relic_reward.gd")
const SWIRL_SHADER := preload("res://script/scenes/void_event/void_swirl.gdshader")
const ACCENT := Color(0.5, 0.2, 0.8)
const SKIP_MARGIN := 20
## Abstand von der Teppichmitte: neues Relikt links, Tasche rechts
const RUG_SPOT_OFFSET := 105.0
const SWALLOW_TIME := 0.9
const SWALLOW_TURNS := 1.5
const COLLAPSE_TIME := 0.45
const RUG_TIME := 0.8

## Wirbel und Partikel; füllt die ganze Fläche, greift aber nicht in die Maus ein
class VoidView extends Control:
	## Anteil der kürzeren Seite, den der Wirbel einnimmt
	const SWIRL_SHARE := 1.2
	## Radius, auf dem die Partikel starten, als Anteil des Wirbel-Durchmessers: etwas außerhalb seines sichtbaren Rands
	const PARTICLE_RING := 0.58
	const PIXEL_SIZE := 5.0
	const SPIN_SPEED := 1.0
	## so viel schneller dreht alles bei voller Sogkraft
	const PULL_SPEED := 2.0
	const PULL_RATE := 3.0

	## Sogkraft, auf die sich pull hinbewegt
	var pull_target := 0.0
	var pull := 0.0
	var _phase := 0.0
	var _swirl: ColorRect
	var _swirl_material: ShaderMaterial
	var _sparks: CPUParticles2D
	var _dust: CPUParticles2D

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		_swirl = ColorRect.new()
		_swirl.mouse_filter = MOUSE_FILTER_IGNORE
		_swirl_material = ShaderMaterial.new()
		_swirl_material.shader = SWIRL_SHADER
		_swirl.material = _swirl_material
		add_child(_swirl)
		_dust = _make_particles(120, 3.2, 8.0, 14.0, [Color(0.45, 0.18, 0.8, 0.0), Color(0.45, 0.18, 0.8, 0.9), Color(0.1, 0.02, 0.2, 0.0)])
		_sparks = _make_particles(220, 2.2, 4.0, 8.0, [Color(1, 0.75, 1, 0.0), Color(1, 0.75, 1), Color(0.65, 0.25, 1), Color(0.3, 0.05, 0.6, 0.0)])
		resized.connect(_fit)

	func _make_particles(amount: int, lifetime: float, min_size: float, max_size: float, colors: Array) -> CPUParticles2D:
		var particles := CPUParticles2D.new()
		particles.texture = VoidView.pixel_texture()
		particles.amount = amount
		particles.lifetime = lifetime
		# hängt am Control, damit die Partikel beim Zusammenfallen mitschrumpfen
		particles.local_coords = true
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
		particles.spread = 180.0
		particles.scale_amount_min = min_size
		particles.scale_amount_max = max_size
		var shrink := Curve.new()
		shrink.add_point(Vector2(0, 1))
		shrink.add_point(Vector2(1, 0.25))
		particles.scale_amount_curve = shrink
		var ramp := Gradient.new()
		ramp.colors = PackedColorArray(colors)
		var offsets := PackedFloat32Array()
		for i in colors.size():
			offsets.append(i / float(colors.size() - 1))
		ramp.offsets = offsets
		particles.color_ramp = ramp
		add_child(particles)
		return particles

	static func pixel_texture() -> Texture2D:
		var pixel := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		pixel.fill(Color.WHITE)
		return ImageTexture.create_from_image(pixel)

	func _fit() -> void:
		pivot_offset = size / 2
		var diameter := minf(size.x, size.y) * SWIRL_SHARE
		_swirl.size = Vector2.ONE * diameter
		_swirl.position = (size - _swirl.size) / 2
		_swirl_material.set_shader_parameter("cells", diameter / PIXEL_SIZE)
		for particles: CPUParticles2D in [_dust, _sparks]:
			var ring := diameter * PARTICLE_RING
			particles.position = size / 2
			particles.emission_sphere_radius = ring
			# Beschleunigung, mit der ein Partikel am Ende seiner Lebenszeit die Mitte erreicht
			var inward := 2.0 * ring / (particles.lifetime * particles.lifetime)
			particles.radial_accel_min = -inward
			particles.radial_accel_max = -inward
			particles.tangential_accel_min = -inward * 1.3
			particles.tangential_accel_max = -inward * 0.7

	func _process(delta: float) -> void:
		pull = move_toward(pull, pull_target, delta * PULL_RATE)
		var speed := SPIN_SPEED + pull * PULL_SPEED
		_phase += delta * speed
		_swirl_material.set_shader_parameter("phase", _phase)
		_swirl_material.set_shader_parameter("pull", pull)
		_dust.speed_scale = speed
		_sparks.speed_scale = speed

var _stage: Control
var _rug: TextureRect
var _void: VoidView
var _void_target: DropTarget
var _skip_button: Button
var _relic_cards: Array[RewardCard] = []
## steht fest, sobald ein Relikt im Void landet, ab dann kommen neue Karten auf den Teppich
var _new_relic := ""
var _new_card: RewardCard

func _ready() -> void:
	use_map_layout()
	set_accent(ACCENT)
	set_title(tr("EVENT_VOID_TITLE"))
	set_drag_hint("EVENT_VOID_HINT")
	_build_stage()
	for id in State.relics:
		_add_relic(id)
	_build_skip_button()

## Rechte Seite: die ganze Fläche nimmt das Relikt an, darunter liegt schon der Teppich bereit
func _build_stage() -> void:
	_target_grid.visible = false
	_stage = Control.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# der Teppich kommt von unten herein und ist vorher nicht zu sehen
	_stage.clip_contents = true
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_side_content(_stage)

	_rug = texture_icon(ChestRewardDialog.RUG_TEXTURE) as TextureRect
	_rug.material = ChestRewardDialog.STAGE_MATERIAL
	_rug.modulate = ChestRewardDialog.RUG_TINT
	_rug.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rug.visible = false
	_stage.add_child(_rug)
	_rug.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	_void = VoidView.new()
	_stage.add_child(_void)
	_void.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	_void_target = DropTarget.new()
	_void_target.dialog = self
	_void_target.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_stage.add_child(_void_target)
	_void_target.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_fixed_targets.append(_void_target)
	_lock_targets()

func _build_skip_button() -> void:
	_skip_button = icon_button(ShopDialog.EXIT_ICON)
	_skip_button.tooltip_text = tr("EVENT_VOID_SKIP")
	_skip_button.pressed.connect(close)
	add_child(_skip_button)
	_skip_button.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT, PRESET_MODE_KEEP_SIZE, SKIP_MARGIN)

func _add_relic(id: String) -> void:
	var card: RewardCard = RELIC_REWARD.add_relic_card(self, id)
	card.drag.header = tr("EVENT_VOID_DRAG_HEADER")
	card.drag.on_drop = _feed_void.bind(id)
	card.drag.relic_id = id
	_relic_cards.append(card)
	# ohne zweites Relikt dieser Seltenheit gibt es nichts zu tauschen
	if Relics.swap_offers(id).is_empty():
		card.modulate = LOCKED_COLOR
		card.mouse_default_cursor_shape = Control.CURSOR_ARROW
		card.tooltip_text = tr("EVENT_VOID_NO_MATCH")

func _drag_blocked(card: RewardCard) -> String:
	if card != _new_card and Relics.swap_offers(card.drag.relic_id).is_empty():
		return tr("EVENT_VOID_NO_MATCH")
	return super(card)

## Das neue Relikt wird gewählt, solange das alte noch als gesammelt zählt: es kann nicht zurückkommen
func _feed_void(id: String) -> void:
	_new_relic = Relics.swap_offers(id).pick_random()
	Relics.remove_relic(id)

func _taken(card: RewardCard) -> void:
	if card == _new_card:
		close()
	else:
		_swallow(card)

func _process(delta: float) -> void:
	super(delta)
	if _void and _new_relic == "":
		var hovered := _dragged != null and _void_target.get_global_rect().has_point(get_global_mouse_position())
		_void.pull_target = 1.0 if hovered else (0.5 if _dragged else 0.0)

func _swallow(card: RewardCard) -> void:
	# ab hier gibt es kein Zurück mehr: nicht überspringen, kein zweites Relikt
	_skip_button.queue_free()
	_fixed_targets.erase(_void_target)
	_void_target.queue_free()
	set_drag_hint("EVENT_VOID_TAKE_HINT")
	_relic_cards.erase(card)
	for other in _relic_cards:
		mark_sold(other)
	card.queue_free()

	await _spiral_into_void(card.icon.texture)
	await _collapse_void()
	await _bring_rug()
	await _reveal_new_relic()

## Das Bild des Relikts kreist von der Abwurfstelle zur Mitte und schrumpft dabei auf nichts
func _spiral_into_void(texture: Texture2D) -> void:
	_void.pull_target = 1.0
	var image := texture_icon(texture)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.size = DRAG_ICON_SIZE
	image.pivot_offset = DRAG_ICON_SIZE / 2
	_stage.add_child(image)
	var center := _stage.size / 2
	var from := get_global_mouse_position() - _stage.global_position - center
	var fall := func(progress: float):
		var left := 1.0 - progress
		image.position = center + from.rotated(-progress * SWALLOW_TURNS * TAU) * left - DRAG_ICON_SIZE / 2
		image.scale = Vector2.ONE * left
	fall.call(0.0)
	await create_tween().tween_method(fall, 0.0, 1.0, SWALLOW_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).finished
	image.queue_free()

func _collapse_void() -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(_void, "scale", Vector2.ZERO, COLLAPSE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(_void, "rotation_degrees", -180.0, COLLAPSE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	_void.queue_free()
	_void = null
	_burst()

## Funken an der Stelle, an der der Void gerade verschwunden ist
func _burst() -> void:
	var sparks := CPUParticles2D.new()
	sparks.texture = VoidView.pixel_texture()
	sparks.position = _stage.size / 2
	sparks.amount = 70
	sparks.lifetime = 0.7
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.spread = 180.0
	sparks.initial_velocity_min = 80.0
	sparks.initial_velocity_max = 340.0
	sparks.scale_amount_min = 3.0
	sparks.scale_amount_max = 7.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color.WHITE, Color(0.8, 0.4, 1), Color(0.3, 0.05, 0.6, 0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	sparks.color_ramp = ramp
	sparks.finished.connect(sparks.queue_free)
	_stage.add_child(sparks)
	sparks.emitting = true

func _bring_rug() -> void:
	_rug.position.y = _stage.size.y
	_rug.visible = true
	await create_tween().tween_property(_rug, "position:y", 0.0, RUG_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).finished

## Relikt und Tasche springen auf dem Teppich auf, erst danach lässt sich das Relikt ziehen
func _reveal_new_relic() -> void:
	show_fixed_targets([], true)
	var bag: DropTarget = _fixed_targets.back()
	_target_grid.remove_child(bag)
	_stage.add_child(bag)
	_center_on_rug(bag, RUG_SPOT_OFFSET)
	bag.scale = Vector2.ZERO

	_new_card = RELIC_REWARD.add_relic_card(self, _new_relic)
	_new_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_on_rug(_new_card, -RUG_SPOT_OFFSET)
	_new_card.scale = Vector2.ZERO
	# der umbrochene Text kennt seine Höhe erst nach dem Layout
	await get_tree().process_frame
	await get_tree().process_frame
	ChestRewardDialog.pop_container(bag)
	await ChestRewardDialog.pop_container(_new_card).finished
	_new_card.mouse_filter = Control.MOUSE_FILTER_STOP

## Anker in der Mitte: bleibt passend, wenn sich die Fläche ändert
func _center_on_rug(control: Control, offset_x: float) -> void:
	control.grow_horizontal = GROW_DIRECTION_BOTH
	control.grow_vertical = GROW_DIRECTION_BOTH
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		control.set_anchor_and_offset(side, 0.5, offset_x, true)
	for side in [SIDE_TOP, SIDE_BOTTOM]:
		control.set_anchor_and_offset(side, 0.5, 0.0, true)

## Das neue Relikt liegt ohne Platte auf dem Teppich, die alten stehen als Karten in der Spalte
func _build_card(card: RewardCard, card_title: String, text: String) -> void:
	if _new_relic != "":
		ChestRewardDialog.build_loot_card(card, card_title, text)
	else:
		super(card, card_title, text)

func _place_card(card: RewardCard) -> void:
	if _new_relic != "":
		_stage.add_child(card)
	else:
		super(card)
