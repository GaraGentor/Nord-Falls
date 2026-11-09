class_name BossRelicOverlay
extends Control

## Boss-Relikte im Kampf (BossRelics), liegt über dem ganzen Kampf und blockiert Eingaben, solange es läuft:
## - play_intro: zu Kampfbeginn tauchen die Relikte des Kampfs nacheinander mit ihrer Wirkung auf (ein Klick zeigt
##   alle sofort), der Button "Los geht's!" startet den Kampf.
##   Ohne Animation dieselbe Übersicht zum Nachlesen (Klick auf die Relikt-Leiste, BossRelicBar).
## - play_break: ist der letzte Gegner besiegt oder gefangen, glühen die Relikte auf, Strahlen brechen hervor und
##   mit einem weißen Blitz sind sie weg. Beim Fang mit vollen KP zerbricht nichts, sie bleiben einfach liegen.
## Mehrere Aufrufe warten aufeinander, der Kampf wartet über wait_idle.

const THEME := preload("res://script/ui/materials/pixel_font_theme.tres")
const FLAT_BUTTON_THEME := preload("res://script/scenes/battle/flat_button_theme.tres")
const BUTTON_MIN_WIDTH := 240
const BACKDROP_COLOR := Color(0, 0, 0, 0.8)
const GOLD := Color(0.858824, 0.717647, 0.45098)
const TEXT_COLOR := Color(0.92, 0.9, 0.85)
const FADE_SECONDS := 0.3
const TITLE_FONT_SIZE := 40
const NAME_FONT_SIZE := 26
const TEXT_FONT_SIZE := 20

## Vorstellung
const ENTRY_POP_SECONDS := 0.35
const ENTRY_DELAY := 0.3
const ENTRY_START_SCALE := 0.6
const INTRO_ICON_SIZE := Vector2(72, 72)
const INTRO_DESC_WIDTH := 420
const INTRO_MAX_HEIGHT := 480
## ab so vielen Relikten zweispaltig
const INTRO_TWO_COLUMNS_FROM := 4

## Zerbrechen
const BREAK_ICON_SIZE := Vector2(140, 140)
const GLOW_SECONDS := 1.1
const GLOW_COLOR := Color(3.0, 2.6, 1.6)
const GLOW_SCALE := 1.18
const GLOW_WOBBLE := 0.08
const RAYS_SECONDS := 0.7
const FLASH_IN_SECONDS := 0.08
const FLASH_OUT_SECONDS := 0.7
const MESSAGE_TYPE_SECONDS := 1.0
const MESSAGE_SECONDS := 2.8
const MESSAGE_WIDTH := 900

var _busy := false
var _clicked := false
var _backdrop: ColorRect
## alles, was zur gerade laufenden Animation gehört, wird danach wieder entfernt
var _parts: Array[Node] = []

func _ready() -> void:
	theme = THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_backdrop = ColorRect.new()
	_backdrop.color = BACKDROP_COLOR
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## _input statt _gui_input: der Klick zählt auch über Liste und Texten
func _input(event: InputEvent) -> void:
	if visible and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_clicked = true

## Wartet, bis keine Animation mehr läuft
func wait_idle() -> void:
	while _busy:
		await get_tree().process_frame

func is_busy() -> bool:
	return _busy

# ─────────────────────────
# Vorstellung

## animated = false: alles steht sofort da (Nachlesen über die Relikt-Leiste)
func play_intro(relic_ids: Array, animated := true) -> void:
	if relic_ids.is_empty():
		return
	await _begin()
	var box := _center_box()
	box.add_child(_label(tr("BOSS_RELIC_INTRO_TITLE"), TITLE_FONT_SIZE, GOLD))
	box.add_child(_label(tr("BOSS_RELIC_INTRO_HINT"), TEXT_FONT_SIZE, TEXT_COLOR))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2 if relic_ids.size() >= INTRO_TWO_COLUMNS_FROM else 1
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	var entries: Array[Control] = []
	for id in relic_ids:
		var entry := _intro_entry(id)
		if animated:
			entry.modulate.a = 0.0
		grid.add_child(entry)
		entries.append(entry)

	# erst dieser Button schließt die Übersicht, bei der Vorstellung startet damit der Kampf
	var button := _plate_button(tr("BOSS_RELIC_START" if animated else "BOSS_RELIC_CLOSE"))
	if animated:
		button.modulate.a = 0.0
		button.disabled = true
	var button_row := CenterContainer.new()
	button_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button_row.add_child(button)
	box.add_child(button_row)
	# erst nach dem Layout stehen die Größen fest
	await get_tree().process_frame
	scroll.custom_minimum_size.y = minf(grid.get_combined_minimum_size().y, INTRO_MAX_HEIGHT)
	await get_tree().process_frame

	_clicked = false
	if animated:
		for entry in entries:
			entry.pivot_offset = entry.size / 2
			entry.scale = Vector2.ONE * ENTRY_START_SCALE
			var pop := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			pop.tween_property(entry, "modulate:a", 1.0, ENTRY_POP_SECONDS)
			pop.tween_property(entry, "scale", Vector2.ONE, ENTRY_POP_SECONDS)
			# ein Klick zeigt den Rest sofort
			if not _clicked:
				await get_tree().create_timer(ENTRY_DELAY).timeout
		await create_tween().tween_property(button, "modulate:a", 1.0, FADE_SECONDS).finished
		button.disabled = false
	await button.pressed
	await _end()

## Text-Button auf einer Eisenplatte wie "Neuen Lauf starten!" (run_end.tscn), Gold beim Drüberfahren
func _plate_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.theme = FLAT_BUTTON_THEME
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size.x = BUTTON_MIN_WIDTH
	button.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	button.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, GOLD)
	var padding := StyleBoxEmpty.new()
	padding.content_margin_left = 24
	padding.content_margin_right = 24
	padding.content_margin_top = 12
	padding.content_margin_bottom = 12
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, padding)
	IronPlate.back(button)
	return button

## Symbol, Name und Wirkung eines Relikts
func _intro_entry(id: String) -> Control:
	var relic: Dictionary = BossRelics.get_relic(id)
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 10)
	entry.add_child(_relic_icon(id, INTRO_ICON_SIZE))
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 2)
	texts.add_child(_label(tr(relic.name), NAME_FONT_SIZE, GOLD, false))
	var desc := _label(BossRelics.description(id), TEXT_FONT_SIZE, TEXT_COLOR, false)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = INTRO_DESC_WIDTH
	texts.add_child(desc)
	entry.add_child(texts)
	return entry

# ─────────────────────────
# Zerbrechen

## forgotten: Fang mit vollen KP, das Relikt bleibt heil liegen statt zu zerbrechen
func play_break(relic_ids: Array, forgotten: bool) -> void:
	if relic_ids.is_empty():
		return
	await _begin()
	var box := _center_box()
	box.add_theme_constant_override("separation", 24)
	var icon_row := HBoxContainer.new()
	icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	icon_row.add_theme_constant_override("separation", 40)
	box.add_child(icon_row)
	var icons: Array[Control] = []
	for id in relic_ids:
		var icon := _relic_icon(id, BREAK_ICON_SIZE)
		icon_row.add_child(icon)
		icons.append(icon)
	var names := ", ".join(PackedStringArray(relic_ids.map(func(id): return tr(BossRelics.get_relic(id).name))))
	box.add_child(_label(names, NAME_FONT_SIZE, GOLD))
	var message := _label("", NAME_FONT_SIZE, TEXT_COLOR)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = MESSAGE_WIDTH
	box.add_child(message)
	await get_tree().process_frame

	var many := relic_ids.size() > 1
	if forgotten:
		await _type_in(message, tr("BOSS_RELIC_FORGOTTEN_MANY" if many else "BOSS_RELIC_FORGOTTEN"))
	else:
		await _shatter(icons)
		await _type_in(message, tr("BOSS_RELIC_BROKEN_MANY" if many else "BOSS_RELIC_BROKEN"))
	await get_tree().create_timer(MESSAGE_SECONDS).timeout
	await _end()

## Aufglühen mit Wackeln, Strahlen, weißer Blitz: danach sind die Symbole weg
func _shatter(icons: Array[Control]) -> void:
	var glow := create_tween().set_parallel()
	for icon in icons:
		icon.pivot_offset = icon.size / 2
		glow.tween_property(icon, "modulate", GLOW_COLOR, GLOW_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		glow.tween_property(icon, "scale", Vector2.ONE * GLOW_SCALE, GLOW_SECONDS)
		var wobble := icon.create_tween().set_loops(int(GLOW_SECONDS / 0.1))
		wobble.tween_property(icon, "rotation", GLOW_WOBBLE, 0.05)
		wobble.tween_property(icon, "rotation", -GLOW_WOBBLE, 0.05)
	await glow.finished

	var rays := Rays.new()
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_part(rays)
	rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var first: Control = icons[0]
	var last: Control = icons[icons.size() - 1]
	rays.center = (first.global_position + last.global_position + last.size * last.scale) / 2 - global_position
	await create_tween().tween_property(rays, "amount", 1.0, RAYS_SECONDS).set_ease(Tween.EASE_IN).finished

	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_part(flash)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await create_tween().tween_property(flash, "color:a", 1.0, FLASH_IN_SECONDS).finished
	for icon in icons:
		icon.modulate.a = 0.0
	rays.visible = false
	_spawn_shards(rays.center)
	create_tween().tween_property(flash, "color:a", 0.0, FLASH_OUT_SECONDS)

## Goldene Splitter fliegen aus der Mitte
func _spawn_shards(at: Vector2) -> void:
	var shards := CPUParticles2D.new()
	var pixel := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	pixel.fill(Color.WHITE)
	shards.texture = ImageTexture.create_from_image(pixel)
	shards.amount = 90
	shards.lifetime = 1.4
	shards.one_shot = true
	shards.explosiveness = 0.9
	shards.position = at
	shards.direction = Vector2.UP
	shards.spread = 180.0
	shards.initial_velocity_min = 200.0
	shards.initial_velocity_max = 520.0
	shards.gravity = Vector2(0, 420)
	shards.scale_amount_min = 4.0
	shards.scale_amount_max = 11.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color.WHITE, GOLD, Color(GOLD, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	shards.color_ramp = ramp
	_add_part(shards)

## Strahlen aus der Mitte, amount 0..1 macht sie länger und deckender
class Rays extends Control:
	const COUNT := 14
	const HALF_WIDTH := 0.07
	const MIN_LENGTH := 60.0
	const MAX_LENGTH := 900.0
	const SPIN_SPEED := 0.6
	const COLOR := Color(1.0, 0.92, 0.65)

	var center := Vector2.ZERO
	var amount := 0.0:
		set(value):
			amount = value
			queue_redraw()
	var _spin := 0.0

	func _process(delta: float) -> void:
		_spin += delta * SPIN_SPEED
		queue_redraw()

	func _draw() -> void:
		var length := lerpf(MIN_LENGTH, MAX_LENGTH, amount)
		var color := Color(COLOR, 0.85 * amount)
		for i in COUNT:
			var angle := _spin + TAU * i / COUNT
			draw_colored_polygon(PackedVector2Array([
				center,
				center + Vector2.from_angle(angle - HALF_WIDTH) * length,
				center + Vector2.from_angle(angle + HALF_WIDTH) * length,
			]), color)

# ─────────────────────────
# Gemeinsames

func _begin() -> void:
	await wait_idle()
	_busy = true
	visible = true
	modulate.a = 0.0
	await create_tween().tween_property(self, "modulate:a", 1.0, FADE_SECONDS).finished

func _end() -> void:
	await create_tween().tween_property(self, "modulate:a", 0.0, FADE_SECONDS).finished
	for part in _parts:
		part.queue_free()
	_parts = []
	visible = false
	_busy = false

func _add_part(part: Node) -> void:
	add_child(part)
	_parts.append(part)

## Spalte in der Bildschirmmitte
func _center_box() -> VBoxContainer:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_part(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)
	return box

func _relic_icon(id: String, icon_size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(BossRelics.get_relic(id).icon)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = icon_size
	icon.material = BossRelics.RELIC_MATERIAL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _label(text: String, font_size: int, color: Color, centered := true) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

## Text tippt sich ein
func _type_in(label: Label, text: String) -> void:
	label.text = text
	label.visible_ratio = 0.0
	await create_tween().tween_property(label, "visible_ratio", 1.0, MESSAGE_TYPE_SECONDS).finished
