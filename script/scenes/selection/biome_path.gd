extends Control

## Biom-Pfad des Runs von links nach rechts im Stil des Ladens: Felder auf Eisenplatten mit dem Rand in der
## Farbe ihres Bioms, dazwischen Ketten aus Pixeln. Die Felder fliegen nacheinander ein, danach hüpft ein
## goldener Pixel von Feld zu Feld und lässt jedes kurz aufleuchten.

@export var font: Font
@export var node_height := 56.0
@export var connector_width := 36.0
@export var reveal_time := 0.25

# nicht erreichte Biome (Endbildschirm) werden abgedunkelt
const UNREACHED_MODULATE := Color(0.55, 0.55, 0.55, 0.85)
const GOLD := SkillDetailPopup.GOLD
const DEPTH_FONT_SIZE := 14
const NAME_FONT_SIZE := 18
const PLATE_MARGIN := 8
const FLY_IN := 30.0
const CHAIN_PIXELS := 3
const CHAIN_PIXEL_SIZE := 6.0
const CHAIN_PIXEL_SECONDS := 0.05
const HOPPER_SIZE := 9.0
const HOP_HEIGHT := 26.0
const HOP_SECONDS := 0.32
## der Hüpfer bewegt sich in groben Schritten, wie die Partikel der Platten
const HOP_STEP := 3.0
const HOP_PAUSE := 0.12
const LOOP_PAUSE := 1.2
const LAND_SECONDS := 0.5

# Anzahl erreichter Biome, -1 = alle (Ei-Auswahl)
var _reached := -1
var _hbox: HBoxContainer
## je Feld: panel, plate, color
var _fields: Array[Dictionary] = []
## je Verbindung ihre Pixel
var _chains: Array[Array] = []
var _hopper: ColorRect
var _hop_tween: Tween
var _reveal_tween: Tween

func show_path(biomes: Array, reached := -1) -> void:
	_reached = reached
	_build(biomes)
	await get_tree().process_frame
	_animate_reveal()

func _build(biomes: Array) -> void:
	for running in [_reveal_tween, _hop_tween]:
		if running:
			running.kill()
	for child in get_children():
		child.queue_free()
	_fields.clear()
	_chains.clear()

	_hbox = HBoxContainer.new()
	_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_hbox.add_theme_constant_override("separation", 0)
	add_child(_hbox)

	for i in biomes.size():
		if i > 0:
			_hbox.add_child(_create_connector(Color(ColorMap.get_combo(biomes[i - 1])["color"])))
		_hbox.add_child(_create_biome(i, biomes[i]))

	# liegt über den Feldern, damit man ihn beim Landen sieht
	_hopper = ColorRect.new()
	_hopper.color = GOLD
	_hopper.size = Vector2(HOPPER_SIZE, HOPPER_SIZE)
	_hopper.modulate.a = 0
	_hopper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hopper)

func _create_connector(color: Color) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(connector_width, node_height)
	var chain := []
	for i in CHAIN_PIXELS:
		var chain_pixel := ColorRect.new()
		chain_pixel.color = color
		chain_pixel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chain_pixel.anchor_left = (i + 0.5) / CHAIN_PIXELS
		chain_pixel.anchor_right = chain_pixel.anchor_left
		chain_pixel.anchor_top = 0.5
		chain_pixel.anchor_bottom = 0.5
		chain_pixel.offset_left = -CHAIN_PIXEL_SIZE / 2
		chain_pixel.offset_right = CHAIN_PIXEL_SIZE / 2
		chain_pixel.offset_top = -CHAIN_PIXEL_SIZE / 2
		chain_pixel.offset_bottom = CHAIN_PIXEL_SIZE / 2
		chain_pixel.modulate.a = 0
		holder.add_child(chain_pixel)
		chain.append(chain_pixel)
	_chains.append(chain)
	return holder

func _create_biome(depth_index: int, mask: int) -> Control:
	var combo = ColorMap.get_combo(mask)
	var color := Color(combo["color"])

	# Container setzen scale zurück, daher wird ein inneres Panel animiert
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, node_height)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate.a = 0
	holder.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 0)
	var plate := IronPlate.frame(panel, vbox, PLATE_MARGIN, PLATE_MARGIN)
	plate.set_rim(color)

	vbox.add_child(_create_label(tr("BIOME_DEPTH").format({"depth": depth_index + 1}), DEPTH_FONT_SIZE, IronPlate.TEXT_COLOR))
	vbox.add_child(_create_label(tr(combo["label"]), NAME_FONT_SIZE, color.lightened(0.25)))

	_fields.append({"panel": panel, "plate": plate, "color": color})
	return holder

func _create_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font:
		label.add_theme_font_override("font", font)
	return label

func _animate_reveal() -> void:
	var tween := create_tween()
	_reveal_tween = tween
	for i in _fields.size():
		var panel: Control = _fields[i].panel
		panel.pivot_offset = panel.size / 2
		panel.position.y = -FLY_IN
		var target := Color.WHITE if i < _reached_count() else UNREACHED_MODULATE
		tween.tween_property(panel, "modulate", target, reveal_time * 0.6)
		tween.parallel().tween_property(panel, "position:y", 0.0, reveal_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if i < _chains.size():
			# Kette i führt zu Biom i + 1
			for chain_pixel: ColorRect in _chains[i]:
				var alpha := UNREACHED_MODULATE.a if i + 1 >= _reached_count() else 1.0
				tween.tween_property(chain_pixel, "modulate:a", alpha, CHAIN_PIXEL_SECONDS)
	tween.tween_callback(_start_hopping)

func _reached_count() -> int:
	return _fields.size() if _reached < 0 else clampi(_reached, 0, _fields.size())

func _start_hopping() -> void:
	if _reached_count() < 2:
		return
	if _hop_tween:
		_hop_tween.kill()
	_hop_tween = create_tween().set_loops()
	_hop_tween.tween_callback(_appear)
	_hop_tween.tween_interval(HOP_PAUSE)
	for i in range(1, _reached_count()):
		_hop_tween.tween_method(_hop.bind(i - 1, i), 0.0, 1.0, HOP_SECONDS)
		_hop_tween.tween_callback(_land.bind(i))
		_hop_tween.tween_interval(HOP_PAUSE)
	_hop_tween.tween_property(_hopper, "modulate:a", 0.0, 0.15)
	_hop_tween.tween_interval(LOOP_PAUSE)

func _appear() -> void:
	_hopper.position = _field_top(0)
	_hopper.modulate.a = 1.0
	_land(0)

func _hop(t: float, from: int, to: int) -> void:
	var point := _field_top(from).lerp(_field_top(to), t)
	point.y -= sin(t * PI) * HOP_HEIGHT
	_hopper.position = point.snapped(Vector2(HOP_STEP, HOP_STEP))

## Das Feld federt unter dem Hüpfer nach, sein Rand leuchtet golden auf
func _land(index: int) -> void:
	var field: Dictionary = _fields[index]
	var panel: Control = field.panel
	var plate: IronPlate = field.plate
	var color: Color = field.color
	panel.scale = Vector2(1.06, 0.92)
	# hängt am Feld, damit es nicht weiterläuft, wenn der Pfad neu aufgebaut wird
	var tween := panel.create_tween().set_parallel()
	tween.tween_property(panel, "scale", Vector2.ONE, LAND_SECONDS).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(rim: Color): plate.set_rim(rim), GOLD, color, LAND_SECONDS)

## Punkt, auf dem der Hüpfer auf dem oberen Rand des Feldes sitzt
func _field_top(index: int) -> Vector2:
	var holder: Control = _fields[index].panel.get_parent()
	return Vector2(holder.position.x + (holder.size.x - HOPPER_SIZE) / 2, holder.position.y - HOPPER_SIZE)
