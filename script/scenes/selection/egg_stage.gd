class_name EggStage
extends Control

## Bühne der Ei-Auswahl (linke Seite): Eier fliegen im hohen Bogen von links oder rechts auf den Bannkreis,
## springen auf, ein Blitz, und das Monster steht in der Mitte. Aufgedeckte Monster stehen auf einem Karussell:
## vorne groß in der Mitte, die übrigen kleiner und abgedunkelt links und rechts im Hintergrund.
## Ein Klick auf ein Monster dreht es nach vorne. Unten liegen die freigeschalteten Ei-Attacken des vorderen Monsters.

## Vorderes Monster hat gewechselt (index = Reihenfolge des Wurfs); clicked: vom Spieler angeklickt
signal front_changed(index: int, clicked: bool)
signal throw_finished

const EGG_TEXTURE := preload("res://assets/ui/eggs/common_1.png")
const EGG_CRACK_TEXTURE := preload("res://assets/ui/eggs/common_2.png")
const MOVES_BADGE := preload("res://script/ui/moves_badge/moves_badge.tscn")

## Plätze auf dem Karussell: vorne 0°, links -120°, rechts +120°
const SLOT_ANGLE := 120.0
## Größe des vorderen Monsters, die übrigen werden kleiner
const FIGURE_SIZE := Vector2(290, 290)
const BACK_SCALE := 0.6
const BACK_MODULATE := Color(0.45, 0.47, 0.55)
## Fußpunkte als Anteil der Bühne: vorne auf dem Bannkreis, hinten etwas höher
const FRONT_FLOOR := 0.645
const BACK_FLOOR := 0.56
## seitlicher Abstand der hinteren Plätze von der Mitte (Anteil der Breite)
const SIDE_OFFSET := 0.31
const SPIN_SECONDS := 0.55
const HOVER_MODULATE := Color(1.2, 1.2, 1.2)
## Zeichenreihenfolge der Monster: 1 (ganz hinten) bis 14 (vorne), unter fliegenden Eiern (15) und Karten (20)
const Z_BASE := 4

const EGG_SIZE := Vector2(70, 88)
const THROW_SECONDS := 0.95
## Scheitel des Bogens (Anteil der Höhe von oben)
const THROW_PEAK := 0.08
const THROW_START_Y := 0.55
const THROW_SPIN := 2.5
const CRACK_SECONDS := 0.3
const FLASH_ALPHA := 0.85
const FLASH_SECONDS := 0.45
const POP_SECONDS := 0.35
## So viel schneller läuft ein Wurf weiter, wenn schon das nächste Ei geworfen wurde
const HURRY_SPEED := 3.0
const BADGE_GAP := 6.0

## Ei-Attacken unten
const CARD_SIZE := Vector2(178, 204)
## links unten stehen die Symbol-Knöpfe (Einstellungen, Sammlung, Anleitung)
const CARDS_LEFT := 88.0
const CARD_GAP := 12
const CARD_BOTTOM := 14.0

## je Monster: {"mon", "node", "image", "angle"}
var _figures: Array[Dictionary] = []
var _flash: ColorRect
var _cards_scroll: ScrollContainer
var _cards: HBoxContainer
var _busy := false
var _spin_tween: Tween
## Tempo aller Animationen der Bühne (Faule Eier: doppelt so schnell)
var speed_scale := 1.0
## Laufender Wurf wurde beschleunigt (nächstes Ei schon geworfen)
var _hurried := false
## Tweens des laufenden Wurfs, die hurry() beschleunigt
var _throw_tweens: Array[Tween] = []
## so viele Eier des laufenden Wurfs sind noch nicht aufgeplatzt
var _hatching := 0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(_place_all)
	_build_cards_row()
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = MOUSE_FILTER_IGNORE
	# über Monstern und Karten
	_flash.z_index = 30
	add_child(_flash)
	_flash.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

func is_busy() -> bool:
	return _busy

func revealed_count() -> int:
	return _figures.size()

## Alle Monster weg, z. B. vor neu gewürfelten Eiern
func clear() -> void:
	for figure in _figures:
		figure.node.queue_free()
	_figures.clear()
	show_skills(null)

## Wirft das Ei des Monsters (index = Wurf-Reihenfolge) auf den Bannkreis, from_left: Seite, von der es kommt
func throw_egg(mon: Monster, index: int, from_left: bool) -> void:
	_begin_throw(1)
	_free_front()
	_fly_egg(mon, from_left, 0.0, func(): _hatch(mon, index, 0.0))

## Alle Eier gleichzeitig (Faule Eier): das erste landet vorne, die übrigen links und rechts.
## Danach steht das erste vorne (front_changed mit Index 0).
func throw_all(mons: Array) -> void:
	_begin_throw(mons.size())
	var angles := [0.0, -SLOT_ANGLE, SLOT_ANGLE]
	for i in mini(mons.size(), angles.size()):
		var angle: float = angles[i]
		# links und rechts kommen von ihrer Seite, das vordere abwechselnd
		var from_left := angle < 0 or (angle == 0 and randf() < 0.5)
		_fly_egg(mons[i], from_left, angle, _hatch.bind(mons[i], i, angle))

func _begin_throw(eggs: int) -> void:
	_busy = true
	_hurried = false
	_hatching = eggs
	_throw_tweens.clear()

## Ei im hohen Bogen auf den Platz mit dem Winkel angle, landed: nach dem Aufplatzen
func _fly_egg(mon: Monster, from_left: bool, angle: float, landed: Callable) -> void:
	var slot := _slot(angle)
	var egg := TextureRect.new()
	egg.texture = EGG_TEXTURE
	egg.material = Monmap.egg_material(Monmap.rarity_of(mon._name))
	egg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	egg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	egg.size = EGG_SIZE
	egg.pivot_offset = EGG_SIZE / 2
	# weiter hinten landet es kleiner
	egg.scale = Vector2.ONE * slot.scale
	egg.mouse_filter = MOUSE_FILTER_IGNORE
	# fliegt über die Monster im Hintergrund
	egg.z_index = 15
	add_child(egg)
	var start := Vector2(-EGG_SIZE.x if from_left else size.x, size.y * THROW_START_Y)
	var land := Vector2(slot.x - EGG_SIZE.x / 2, slot.floor_y - EGG_SIZE.y)
	var spin := TAU * THROW_SPIN * (1.0 if from_left else -1.0)
	var tween := _tween()
	tween.tween_method(func(t: float):
		var pos := start.lerp(land, t)
		# hoher Bogen: Parabel, deren Scheitel nahe THROW_PEAK liegt
		pos.y -= (minf(start.y, land.y) - size.y * THROW_PEAK) * 4.0 * t * (1.0 - t)
		egg.position = pos
		egg.rotation = spin * t, 0.0, 1.0, THROW_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# aufgeschlagen: kurz springen und aufplatzen
	tween.tween_callback(func(): egg.texture = EGG_CRACK_TEXTURE)
	tween.tween_property(egg, "position:y", land.y - 14, CRACK_SECONDS * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(egg, "position:y", land.y, CRACK_SECONDS * 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
	tween.tween_callback(func():
		egg.queue_free()
		landed.call())

## Platz vorne frei machen: das Karussell dreht so, dass der leere Platz nach vorne kommt
func _free_front() -> void:
	var taken := _figures.map(func(figure): return roundi(figure.angle))
	# erster freier Platz in dieser Reihenfolge, so wandert das erste Monster nach links
	for empty in [0, roundi(SLOT_ANGLE), -roundi(SLOT_ANGLE)]:
		if not taken.has(empty):
			if empty != 0:
				_spin(-empty)
			return

## Aufgeplatzt: Blitz, darin steht das Monster auf seinem Platz
func _hatch(mon: Monster, index: int, angle: float) -> void:
	var figure := _make_figure(mon, index)
	figure.angle = angle
	_figures.append(figure)
	_place(figure, angle)
	_flash.color.a = FLASH_ALPHA
	var flash := _tween()
	flash.tween_property(_flash, "color:a", 0.0, FLASH_SECONDS).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	var node: Control = figure.node
	var target_scale := node.scale
	var target_modulate := node.modulate
	node.scale = target_scale * 0.3
	node.modulate = Color(3, 3, 3)
	var pop := _tween().set_parallel()
	pop.tween_property(node, "scale", target_scale, POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(node, "modulate", target_modulate, POP_SECONDS * 1.5)
	pop.chain().tween_callback(func():
		_hatching -= 1
		if _hatching <= 0:
			_busy = false
			throw_finished.emit())
	if angle == 0:
		front_changed.emit(index, false)

func _make_figure(mon: Monster, index: int) -> Dictionary:
	var node := Control.new()
	node.size = FIGURE_SIZE
	node.pivot_offset = Vector2(FIGURE_SIZE.x / 2, FIGURE_SIZE.y)
	node.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(node)
	move_child(node, _cards_scroll.get_index())
	var image := TextureRect.new()
	Monmap.show_on(image, mon._name, Monmap.MEDIUM)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = MOUSE_FILTER_STOP
	image.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	node.add_child(image)
	# die Bilder haben durchsichtige Ränder: die sichtbaren Füße stehen auf dem Boden, die Rune sitzt direkt über dem Kopf
	var visible_rect := _visible_rect(image.texture)
	image.position = Vector2(0, FIGURE_SIZE.y - visible_rect.end.y)
	image.size = FIGURE_SIZE
	var badge: Control = MOVES_BADGE.instantiate()
	node.add_child(badge)
	badge.size = badge.custom_minimum_size
	badge.position = Vector2((FIGURE_SIZE.x - badge.size.x) / 2, image.position.y + visible_rect.position.y - badge.size.y - BADGE_GAP)
	badge.set_moves(Monster.BASE_MOVES + mon._upgrades, Monster.BASE_MOVES + Monmap.mon_metainfos_by_name(mon._name).get("max_upgrades", 0))
	var figure := {"mon": mon, "index": index, "node": node, "image": image, "angle": 0.0}
	image.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_on_figure_clicked(figure))
	image.mouse_entered.connect(func(): image.self_modulate = HOVER_MODULATE)
	image.mouse_exited.connect(func(): image.self_modulate = Color.WHITE)
	return figure

## Sichtbarer Teil des Bildes in Koordinaten der Figur (Bild mittig in FIGURE_SIZE eingepasst)
func _visible_rect(texture: Texture2D) -> Rect2:
	var full := Rect2(Vector2.ZERO, FIGURE_SIZE)
	var source := texture.get_image() if texture else null
	if source == null or source.is_empty():
		return full
	if source.is_compressed():
		source = source.duplicate()
		source.decompress()
	var used := source.get_used_rect()
	if used.size == Vector2i.ZERO:
		return full
	var texture_size := Vector2(source.get_size())
	var fit := minf(FIGURE_SIZE.x / texture_size.x, FIGURE_SIZE.y / texture_size.y)
	var offset := (FIGURE_SIZE - texture_size * fit) / 2
	return Rect2(offset + Vector2(used.position) * fit, Vector2(used.size) * fit)

func _on_figure_clicked(figure: Dictionary) -> void:
	if _busy:
		return
	var angle: float = figure.angle
	if not is_zero_approx(angle):
		_spin(-angle)
	front_changed.emit(figure.index, true)

## Dreht das Karussell um turn Grad
func _spin(turn: float) -> void:
	if _spin_tween and _spin_tween.is_running():
		_spin_tween.custom_step(SPIN_SECONDS)
	var starts := _figures.map(func(figure): return figure.angle)
	_spin_tween = _tween()
	_spin_tween.tween_method(func(t: float):
		for i in _figures.size():
			_place(_figures[i], starts[i] + turn * t), 0.0, 1.0, SPIN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in _figures.size():
		_figures[i].angle = float(roundi(wrapf(starts[i] + turn, -180.0, 180.0)))

func _place_all() -> void:
	for figure in _figures:
		_place(figure, figure.angle)

## Setzt ein Monster auf seinen Winkel: vorne groß und hell, hinten kleiner, höher und dunkler
func _place(figure: Dictionary, angle: float) -> void:
	var slot := _slot(angle)
	var node: Control = figure.node
	node.position = Vector2(slot.x - FIGURE_SIZE.x / 2, slot.floor_y - FIGURE_SIZE.y)
	node.scale = Vector2.ONE * slot.scale
	node.modulate = slot.modulate
	node.z_index = slot.z

## Platz auf dem Karussell für einen Winkel: Fußpunkt (x, floor_y), Größe, Abdunkelung und Zeichenreihenfolge
func _slot(angle: float) -> Dictionary:
	var rad := deg_to_rad(angle)
	# 1 = ganz vorne, 0 = auf den seitlichen Plätzen, darunter hinter der Mitte
	var depth := (cos(rad) + 0.5) / 1.5
	return {
		"x": size.x / 2 + sin(rad) * size.x * SIDE_OFFSET / sin(deg_to_rad(SLOT_ANGLE)),
		"floor_y": size.y * lerpf(BACK_FLOOR, FRONT_FLOOR, depth),
		"scale": lerpf(BACK_SCALE, 1.0, depth),
		"modulate": BACK_MODULATE.lerp(Color.WHITE, clampf(depth, 0.0, 1.0)),
		# hinter der Mitte wird depth negativ (bis -1/3): Z_BASE hält z über 0, sonst rutscht die Figur beim
		# Durchdrehen hinter das Hintergrundbild und ist kurz unsichtbar
		"z": Z_BASE + roundi(depth * 10),
	}

# ─────────────────────────
# Ei-Attacken des vorderen Monsters

func _build_cards_row() -> void:
	_cards_scroll = ScrollContainer.new()
	_cards_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cards_scroll.mouse_filter = MOUSE_FILTER_PASS
	_cards_scroll.z_index = 20
	add_child(_cards_scroll)
	_cards_scroll.anchor_left = 0.0
	_cards_scroll.anchor_right = 1.0
	_cards_scroll.anchor_top = 1.0
	_cards_scroll.anchor_bottom = 1.0
	# die Scrollview schneidet ab: oben, unten und an den Seiten Platz für die Rand-Effekte (SkillCardPaper.FLAME_PAD),
	# die Karten selbst bleiben, wo sie waren
	var pad := SkillCardPaper.FLAME_PAD
	_cards_scroll.offset_left = CARDS_LEFT - pad.x
	_cards_scroll.offset_right = -24 + pad.z
	_cards_scroll.offset_top = -CARD_SIZE.y - CARD_BOTTOM - 4 - pad.y
	_cards_scroll.offset_bottom = minf(-CARD_BOTTOM + pad.w, 0.0)
	var margin := SkillCardPaper.flame_margin()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.size_flags_vertical = SIZE_EXPAND_FILL
	# unten nur so viel Rand, wie bis zum Bildrand Platz ist (sonst rutschen die Karten nach oben)
	margin.add_theme_constant_override("margin_bottom", int(minf(pad.w, CARD_BOTTOM)))
	_cards_scroll.add_child(margin)
	var center := CenterContainer.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	center.size_flags_vertical = SIZE_EXPAND_FILL
	center.mouse_filter = MOUSE_FILTER_IGNORE
	margin.add_child(center)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", maxi(CARD_GAP, SkillCardPaper.FLAME_GAP_X))
	_cards.mouse_filter = MOUSE_FILTER_IGNORE
	center.add_child(_cards)

## Alle freigeschalteten Ei-Attacken der Art als Karten (null: keine)
func show_skills(mon: Monster) -> void:
	for card in _cards.get_children():
		card.queue_free()
	if mon == null:
		return
	for skill_name in Skills.get_available_egg_skills(mon._name):
		var skill := Skills.carried_egg_skill(skill_name)
		if skill.is_empty():
			continue
		var card := EggSkillCard.create(skill, mon)
		card.custom_minimum_size = CARD_SIZE
		card.size_flags_horizontal = SIZE_SHRINK_CENTER
		card.modulate.a = 0.0
		_cards.add_child(card)
		_tween().tween_property(card, "modulate:a", 1.0, 0.25).set_delay(0.04 * card.get_index())

## Laufenden Wurf (Flug, Aufplatzen, Blitz, Drehen) schneller zu Ende bringen, weil schon das nächste Ei geworfen wurde
func hurry() -> void:
	if not _busy or _hurried:
		return
	_hurried = true
	for tween in _throw_tweens:
		if tween.is_valid():
			tween.set_speed_scale(_current_speed())

func _current_speed() -> float:
	return speed_scale * (HURRY_SPEED if _hurried else 1.0)

## Tween mit dem Tempo der Bühne, gehört zum laufenden Wurf
func _tween() -> Tween:
	var tween := create_tween().set_speed_scale(_current_speed())
	if _busy:
		_throw_tweens.append(tween)
	return tween
