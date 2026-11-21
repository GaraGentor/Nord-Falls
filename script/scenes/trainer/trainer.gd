extends ShopDialog

## Trainer: verkauft seltene Skills (ab Stufe 2), die Hälfte davon mit mehreren Elementen, damit
## sich der Weg lohnt. Gezogen auf ein Monster ist der Skill gelernt; hat es keinen freien Slot,
## wählt man, welcher Skill dafür vergessen wird. Bezahlt wird erst, wenn wirklich gelernt wurde.
## Auf jeder Karte zeigen kleine Bilder, welche Monster den Skill einsetzen können.
##
## Links liegen die Karten mit etwas Abstand in zwei Reihen, über jeder ihr Preis mit dem ME-Icon. Ein Klick
## vergrößert eine Karte und schiebt die anderen ihrer Reihe zur Seite. Empfohlene Skills tragen einen Stempel. Rechts hält der Trainer die eigenen Monster auf
## seinen Platten; ein Klick auf ein Monster fährt die Kamera nach rechts, rechts neben dem Trainer erscheinen dessen Skills.

## Monster auf der Platte: Ablegeziel für Karten, per Klick auswählbar
class PlateMon extends RewardDialog.DropTarget:
	const SELECTED_SCALE := Vector2(1.15, 1.15)
	const SELECT_SECONDS := 0.2

	var icon: Control
	var on_click: Callable
	## fehlende Elemente des aktuellen Skills als Chips, direkt unter dem Monster
	var chips: HBoxContainer
	var _press_pos := Vector2.ZERO
	var _tween: Tween
	var _selected := false
	var _highlighted := false

	func _gui_input(event: InputEvent) -> void:
		if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_press_pos = event.position
		elif event.position.distance_to(_press_pos) < RewardDialog.CLICK_MAX_MOVE:
			on_click.call()

	## Kein Rahmen: das Monster selbst bekommt den goldenen Umriss, wie beim Auswählen
	func set_highlight(on: bool) -> void:
		_highlighted = on
		_show_outline()

	func _show_outline() -> void:
		icon.material = Monmap.monster_selected_material if _selected or _highlighted else Monmap.MONSTER_MATERIAL

	func set_selected(selected: bool) -> void:
		_selected = selected
		_show_outline()
		if _tween:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, "scale", SELECTED_SCALE if selected else Vector2.ONE, SELECT_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Runder Stempel als Wasserzeichen: doppelter Ring, oben und unten der Text im Bogen, mittig ein Stern.
## Leicht gedreht und durchscheinend, damit Schrift und Symbole der Karte lesbar bleiben.
class TrainerStamp extends Control:
	const COLOR := Color(0.858824, 0.717647, 0.45098, 0.26)
	const TILT := -0.26
	## Außenradius als Anteil der Kartenbreite
	const RADIUS_SHARE := 0.42
	const FONT_SIZE := 24
	const RING_GAP := 5.0
	const TEXT_BAND := 22.0

	var text := ""
	var font: Font

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var radius := minf(size.x, size.y) * RADIUS_SHARE
		var frame := Transform2D(TILT, size / 2)
		draw_set_transform_matrix(frame)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, COLOR, 3.0, true)
		draw_arc(Vector2.ZERO, radius - RING_GAP, 0.0, TAU, 72, COLOR, 1.5, true)
		var inner := radius - RING_GAP - TEXT_BAND
		draw_arc(Vector2.ZERO, inner, 0.0, TAU, 60, COLOR, 1.5, true)
		_draw_star(inner * 0.55)
		var words := text.to_upper().split(" ", false, 1)
		var text_radius := radius - RING_GAP - TEXT_BAND / 2
		if words.size() > 0:
			_draw_arc_text(frame, words[0], text_radius, true)
		if words.size() > 1:
			_draw_arc_text(frame, words[1], text_radius, false)
		draw_set_transform_matrix(Transform2D.IDENTITY)

	## Buchstaben entlang des Kreises, oben im Uhrzeigersinn, unten gegen ihn: beide Hälften stehen aufrecht
	func _draw_arc_text(frame: Transform2D, word: String, radius: float, top: bool) -> void:
		if font == null or word.is_empty():
			return
		var widths: Array[float] = []
		var total := 0.0
		for i in word.length():
			var width := font.get_char_size(word.unicode_at(i), FONT_SIZE).x + 1.0
			widths.append(width)
			total += width
		var direction := 1.0 if top else -1.0
		var angle := (-PI / 2 if top else PI / 2) - direction * total / radius / 2
		# Grundlinie so, dass die Großbuchstaben mittig auf dem Kreis stehen
		var baseline := font.get_ascent(FONT_SIZE) * 0.35
		for i in word.length():
			var mid := angle + direction * widths[i] / 2 / radius
			var glyph := Transform2D(mid + direction * PI / 2, Vector2(cos(mid), sin(mid)) * radius)
			draw_set_transform_matrix(frame * glyph)
			draw_char(font, Vector2(-widths[i] / 2, baseline), word[i], FONT_SIZE, COLOR)
			angle += direction * widths[i] / radius
		draw_set_transform_matrix(frame)

	func _draw_star(radius: float) -> void:
		var points := PackedVector2Array()
		for i in 10:
			var r := radius if i % 2 == 0 else radius * 0.45
			var a := -PI / 2 + i * PI / 5
			points.append(Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(points, COLOR)

## Tasche oben links, zeigt die Essenz (wie die Boss Tränen beim Kerkermeister), nur zur Anzeige
const BAG_SIZE := Vector2(104, 98)
const ESSENCE_SIZE := Vector2(34, 34)
const BAG_FONT_SIZE := 24
## so viel Essenz steht für ein sichtbares Stück in der Tasche
const ESSENCE_PER_ITEM := 25
const TRAINER_CARD_SIZE := Vector2(210, 0)
## Höhe der Beschreibung auf der Karte, längere Texte scrollen von selbst (RewardDialog.scroll_description)
const DESCRIPTION_HEIGHT := 104.0
const TRAINER_TEXT_FONT_SIZE := 24
## obere und untere Kartenzeile (Kosten, Sterne, Abklingzeit, Wert, Element) vergrößert
const FACE_ROW_ZOOM := 1.3
## Chips unter den Monstern: Abstand zum Monster, Zeilenhöhe
const CHIPS_GAP := 8.0
const CHIPS_HEIGHT := 36.0
## vier pro Reihe: mit den Empfehlungen bleiben es zwei Reihen
const CARD_COLUMNS := 4
const MIN_TIER := 2
const SINGLE_ELEMENT_OFFERS := 2
const MULTI_ELEMENT_OFFERS := 2
## zusätzliche Skills in der zweiten Reihe, müssen zu keinem Monster passen
const EXTRA_OFFERS := 2
## Angriffe, die gegen das nächste Biom sehr effektiv sind, mit Stempel "Trainers Choice" (stehen vorn)
const RECOMMENDED_OFFERS := 2

## Preis über jeder Karte: Höhe der Zeile (Kartenpixel), Schrift und ME-Icon
const PRICE_HEIGHT := 46.0
const PRICE_FONT_SIZE := 48
const PRICE_ICON_SIZE := Vector2(36, 36)

## Karten so groß wie die Ei-Attacken auf dem Tisch im Ei-Konfigurator (dort CARD_SIZE.x * TABLE_SCALE,
## das Bild IMAGE_SIZE deckt den Bildschirm ab)
const EGG_TABLE_CARD_WIDTH := 180.0 * 0.88
const EGG_IMAGE_SIZE := Vector2(1376, 768)

## Abstand zwischen den Karten als Anteil der Kartenbreite bzw. der Höhe einer Reihe
const CARD_GAP := 0.04
const ROW_GAP := 0.05
## Rand um den Kartentisch
const TABLE_MARGIN := 20.0
## Breite des Kartentischs im Verhältnis zur Trainerseite
const TABLE_WIDTH_RATIO := 1.15
## aufgerichtete Karte: Vergrößerung und Abstand zu den weggedrückten Nachbarn
const FOCUS_ZOOM := 1.2
const PUSH_GAP := 8.0
const CARD_MOVE_SECONDS := 0.25

## Bildausschnitt des Trainers, Anteile der Bildgröße: so viel muss über die Höhe der Karten passen
## (der Rest verschwindet nach unten), Mitte der Platten, Plattenbreite
const TRAINER_VISIBLE_HEIGHT := 0.72
const PLATE_CENTERS: Array[Vector2] = [Vector2(0.244, 0.615), Vector2(0.756, 0.615)]
const PLATE_WIDTH := 0.40
## Monster auf der Platte, bezogen auf die Plattenbreite
const MON_SIZE_ON_PLATE := 1.1
const BUBBLE_WIDTH := 320.0
## Sprechblase über dem Kopf, Zipfel nach unten: Spitze zeigt auf diesen Punkt (Anteile der Bildgröße)
const BUBBLE_TARGET := Vector2(0.5, 0.09)
const BUBBLE_TAIL := 22.0

## Klick auf ein Monster: die Kamera fährt nach rechts, die ganze Bühne (Tisch und Trainer) also nach links,
## bis der Trainer mit den Monstern am linken Rand steht; rechts daneben erscheint die Attacken-Übersicht.
const MODAL_GAP := 12.0
## Oberkante der Monster-Übersicht, vom oberen Bildschirmrand
const MODAL_TOP := 72.0
const PAN_SECONDS := 0.45
## Parallax des Hintergrunds: Anteil der Fahrt, um den er mitfährt, Ausschlag mit der Maus, Nachziehen pro Sekunde
const PARALLAX_PAN := 0.1
const PARALLAX_MOUSE := 12.0
const PARALLAX_FOLLOW := 6.0

## Wellen-Hintergrund aus der Szene
@export var background: Control
## Trainerbild aus der Szene, dort lassen sich auch die Shader-Werte einstellen
@export var trainer_image: TextureRect

var _left_side: Control
var _card_layer: Control
var _cards: Array[RewardCard] = []
var _focused_card: RewardCard
var _card_tween: Tween
var _stage: Control
var _plates: Array[PlateMon] = []
var _bubble: SpeechBubble
var _bubble_target := Vector2.ZERO
var _open_plate: PlateMon
## hängt rechts neben dem Trainer und fährt mit der Bühne herein
var _modal_holder: Control
var _exit_button: Button
var _pan := 0.0
var _pan_width := 0.0
var _pan_tween: Tween
var _mouse_parallax := Vector2.ZERO
var _bag: OpenBag
## Namen der empfohlenen Skills (_pick_recommended)
var _recommended: Array = []

func _ready() -> void:
	use_scene_layout(background)
	_title.visible = false
	_build_sides()
	set_drag_hint("TRAINER_HINT")
	set_card_layout(CARD_COLUMNS, TRAINER_CARD_SIZE, true)
	for skill in _pick_offers():
		_add_skill_card(skill)
	_build_top_bar()
	_first_layout()
	trainer_image.add_to_group("tut_npc")
	_card_layer.add_to_group("tut_trn_cards")
	_bag.add_to_group("tut_trn_bag")
	for plate in _plates:
		plate.add_to_group("tut_trn_mons")
	# beim ersten Besuch erklärt der Trainer im Tutorial, danach sagt er wieder seinen Hinweis
	if Tutorial.trigger("trainer", set_drag_hint.bind("TRAINER_HINT")):
		_bubble.hide()

## Oben links die Tasche mit der Essenz und daneben die Gutscheine, oben rechts der Verlassen-Button.
## Erst aufrufen, wenn alle Karten einen Preis haben
func _build_top_bar() -> void:
	var bar := HBoxContainer.new()
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	_content.add_child(bar)
	_content.move_child(bar, 0)
	_bag = OpenBag.new(BAG_SIZE, ESSENCE_ICON, ESSENCE_SIZE, BAG_FONT_SIZE)
	bar.add_child(_bag)
	var gap := Control.new()
	gap.size_flags_horizontal = SIZE_EXPAND_FILL
	gap.mouse_filter = MOUSE_FILTER_IGNORE
	bar.add_child(gap)
	_exit_button = icon_button(EXIT_ICON)
	_exit_button.tooltip_text = tr("SHOP_FINISH")
	_exit_button.size_flags_vertical = SIZE_SHRINK_BEGIN
	_exit_button.pressed.connect(close)
	bar.add_child(_exit_button)
	_money_label = _bag.label
	_money_suffix = ""
	_watch_money()
	add_coupons(bar, trainer_image)
	bar.move_child(_coupon_stack, _bag.get_index() + 1)

func _coupon_applied() -> void:
	_bubble.say(tr("TRAINER_SAY_COUPON"))

func _money_changed(new_val) -> void:
	super(new_val)
	_bag.show_items(ceili(State.ep / float(ESSENCE_PER_ITEM)))

## Ersetzt die beiden Standard-Spalten: links Kartentisch, rechts der Trainer, je die halbe Breite
func _build_sides() -> void:
	_card_groups.visible = false
	_target_side.visible = false

	_left_side = Control.new()
	_left_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# etwas breiter als die Trainerseite, damit vier Karten in Ei-Attacken-Größe nebeneinander passen
	_left_side.size_flags_stretch_ratio = TABLE_WIDTH_RATIO
	_columns.add_child(_left_side)
	_card_layer = Control.new()
	_card_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_card_layer.gui_input.connect(_on_table_input)
	_card_layer.resized.connect(_layout_cards)
	_left_side.add_child(_card_layer)

	_stage = Control.new()
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.resized.connect(_layout_stage)
	_columns.add_child(_stage)
	trainer_image.reparent(_stage, false)
	for i in mini(State.mons.size(), PLATE_CENTERS.size()):
		_plates.append(_add_plate_mon(State.mons[i]))
	_bubble = SpeechBubble.new(BUBBLE_WIDTH, true, false, true)
	_bubble.resized.connect(_place_bubble)
	_stage.add_child(_bubble)
	_modal_holder = Control.new()
	_modal_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_holder.visible = false
	_stage.add_child(_modal_holder)
	# Position und Größe der Trainerseite stehen erst nach dem Ordnen der Spalten fest
	_stage.item_rect_changed.connect(_layout_pan)

func _add_plate_mon(mon: Monster) -> PlateMon:
	var plate := PlateMon.new()
	plate.dialog = self
	plate.mon = mon
	plate.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	plate.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	plate.icon = mon_icon(mon)
	plate.add_child(plate.icon)
	plate.on_click = _toggle_mon.bind(plate)
	ignore_mouse_below(plate)
	_stage.add_child(plate)
	plate.chips = HBoxContainer.new()
	plate.chips.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(plate.chips)
	return plate

## Umbrechende Karten kennen ihre Höhe erst nach dem Layout, solange bleibt der Tisch unsichtbar
func _first_layout() -> void:
	_card_layer.modulate.a = 0.0
	for card in _cards:
		card.size = TRAINER_CARD_SIZE
	await get_tree().process_frame
	await get_tree().process_frame
	_layout_cards()
	create_tween().tween_property(_card_layer, "modulate:a", 1.0, 0.15)

func _layout_stage() -> void:
	var texture_size := trainer_image.texture.get_size()
	var image_scale := minf(_stage.size.x / texture_size.x, _stage.size.y / (texture_size.y * TRAINER_VISIBLE_HEIGHT))
	var image_size := texture_size * image_scale
	var origin := Vector2((_stage.size.x - image_size.x) / 2, 0)
	trainer_image.position = origin
	trainer_image.size = image_size
	var mon_size := image_size.x * PLATE_WIDTH * MON_SIZE_ON_PLATE
	for i in _plates.size():
		var plate := _plates[i]
		plate.size = Vector2(mon_size, mon_size)
		# wächst beim Auswählen von der Platte aus nach oben
		plate.pivot_offset = Vector2(mon_size / 2, mon_size)
		plate.position = origin + PLATE_CENTERS[i] * image_size - plate.pivot_offset
		plate.chips.size = Vector2(mon_size, CHIPS_HEIGHT)
		plate.chips.position = plate.position + Vector2(0, mon_size + CHIPS_GAP)
	_bubble_target = origin + BUBBLE_TARGET * image_size
	_place_bubble()
	if _coupon_target:
		_coupon_target.position = origin
		_coupon_target.size = image_size

## Über dem Kopf des Trainers, mittig: die Höhe hängt vom Text ab, wächst also nach oben
func _place_bubble() -> void:
	_bubble.position = _bubble_target - Vector2(_bubble.size.x / 2, _bubble.size.y + BUBBLE_TAIL)

func _place_card(card: RewardCard) -> void:
	_card_layer.add_child(card)
	_cards.append(card)

## Karten reihenweise anordnen: so groß, dass beide Reihen die linke Hälfte füllen
func _layout_cards(animate := false) -> void:
	var area := _card_layer.size
	if _cards.is_empty() or area.x <= 0.0:
		return
	var card_size := TRAINER_CARD_SIZE
	for card in _cards:
		card_size.y = maxf(card_size.y, card.get_combined_minimum_size().y)
	# Platz einer Karte: darüber steht noch ihr Preis
	var slot := card_size + Vector2(0, PRICE_HEIGHT)
	var rows := ceili(_cards.size() / float(_card_columns))
	var fit_x := (area.x - TABLE_MARGIN) / (slot.x * (_card_columns + (_card_columns - 1) * CARD_GAP))
	var fit_y := (area.y - TABLE_MARGIN) / (slot.y * (rows + (rows - 1) * ROW_GAP))
	var viewport := get_viewport_rect().size
	var egg_scale := EGG_TABLE_CARD_WIDTH * maxf(viewport.x / EGG_IMAGE_SIZE.x, viewport.y / EGG_IMAGE_SIZE.y) / card_size.x
	var base_scale := minf(egg_scale, minf(fit_x, fit_y))
	var focus_scale := minf(base_scale * FOCUS_ZOOM, area.y / slot.y)
	var scaled := slot * base_scale
	var row_step := scaled.y * (1.0 + ROW_GAP)
	var first_y := (area.y - scaled.y - (rows - 1) * row_step) / 2 + scaled.y / 2

	if _card_tween:
		_card_tween.kill()
	if animate:
		_card_tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for row in rows:
		var cards := _cards.slice(row * _card_columns, (row + 1) * _card_columns)
		var focused: int = cards.find(_focused_card)
		var centers := _row_centers(cards.size(), focused, scaled.x, card_size.x * focus_scale, area.x)
		for i in cards.size():
			var slot_center := Vector2(centers[i], first_y + row * row_step)
			var card: RewardCard = cards[i]
			card.size = card_size
			card.pivot_offset = card_size / 2
			var is_focused := i == focused
			var card_scale := focus_scale if is_focused else base_scale
			if is_focused:
				# vergrößerte Karte bleibt samt Preis ganz auf dem Tisch
				var half_height := slot.y * focus_scale / 2
				slot_center.y = clampf(slot_center.y, half_height, area.y - half_height)
			# die Karte füllt den unteren Teil ihres Platzes, darüber steht der Preis
			var center := slot_center + Vector2(0, PRICE_HEIGHT * card_scale / 2)
			var target_scale := Vector2.ONE * card_scale
			var target_position := center - card.pivot_offset
			if animate:
				_card_tween.tween_property(card, "position", target_position, CARD_MOVE_SECONDS)
				_card_tween.tween_property(card, "scale", target_scale, CARD_MOVE_SECONDS)
			else:
				card.position = target_position
				card.scale = target_scale

## Mittelpunkte der Karten einer Reihe. Mit vergrößerter Karte (focused >= 0) rücken die anderen
## beiseite und überlappen sich untereinander nur so stark, wie es nötig ist, um auf dem Tisch zu bleiben.
func _row_centers(count: int, focused: int, card_width: float, focus_width: float, width: float) -> Array[float]:
	var centers: Array[float] = []
	var step := card_width * (1.0 + CARD_GAP)
	if focused < 0:
		var x := (width - card_width - (count - 1) * step) / 2
		for i in count:
			centers.append(x + card_width / 2 + i * step)
		return centers
	var sides := int(focused > 0) + int(focused < count - 1)
	var stacked := count - 1 - sides
	var peek := 0.0
	if stacked > 0:
		peek = clampf((width - focus_width - sides * (card_width + PUSH_GAP)) / stacked, 0.0, step)
	var x := (width - focus_width - sides * (card_width + PUSH_GAP) - stacked * peek) / 2
	for i in count:
		if i == focused:
			centers.append(x + focus_width / 2)
			x += focus_width + PUSH_GAP
		else:
			centers.append(x + card_width / 2)
			x += card_width + PUSH_GAP if i == focused - 1 else peek
	return centers

## Klick auf eine Karte vergrößert sie, nochmal Klicken legt sie zurück
func _toggle_focus(card: RewardCard) -> void:
	_set_focus(null if card == _focused_card else card)

func _set_focus(card: RewardCard) -> void:
	_focused_card = card
	for i in _cards.size():
		_card_layer.move_child(_cards[i], i)
	if _focused_card:
		_focused_card.move_to_front()
	_show_missing_elements(_focused_card)
	_layout_cards(true)

## Fehlende Elemente unter den Monstern zeigen: für die gezogene oder aufgerichtete Karte, sonst keine
func _show_missing_elements(card: RewardCard) -> void:
	for plate in _plates:
		for chip in plate.chips.get_children():
			plate.chips.remove_child(chip)
			chip.queue_free()
		if card == null or Skills.knows_skill(plate.mon, card.drag.skill.name):
			continue
		for element: int in Skills.missing_elements(plate.mon, card.drag.skill):
			add_element_chip(plate.chips, element)

func _tooltip_anchor(target: DropTarget) -> Rect2:
	return target.get_global_rect().merge((target as PlateMon).chips.get_global_rect())

## Gekaufte Karte verschwindet, die übrigen rücken zusammen
func pay(card: RewardCard) -> void:
	super(card)
	_price_labels.erase(card)
	_cards.erase(card)
	_card_layer.remove_child(card)
	card.queue_free()
	_set_focus(null)

func _on_table_input(event: InputEvent) -> void:
	if _focused_card and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_toggle_focus(_focused_card)

## Klick auf ein Monster: die Kamera fährt nach rechts, rechts erscheint die Übersicht seiner Attacken
## (dasselbe MonSkillsModal wie im Shop), das Monster bleibt markiert. Ein anderes Monster wechselt nur
## die Übersicht, dasselbe nochmal fährt zurück.
func _toggle_mon(plate: PlateMon) -> void:
	if _replace_picker:
		_bubble.say(tr("TRAINER_FINISH_CHOICE"))
		return
	if plate == _open_plate:
		_close_mon()
		return
	if _focused_card:
		_set_focus(null)
	if _open_plate:
		_open_plate.set_selected(false)
	_clear_modal()
	_open_plate = plate
	plate.set_selected(true)
	_modal_holder.add_child(MonSkillsModal.new(plate.mon))
	# solange die Übersicht offen ist, verlässt kein versehentlicher Klick oben rechts den Trainer
	_exit_button.visible = false
	_pan_to(_pan_width)

## Bühne zurückfahren, die Übersicht fährt rechts mit hinaus und verschwindet danach
func _close_mon() -> void:
	if _open_plate == null:
		return
	_open_plate.set_selected(false)
	_open_plate = null
	_exit_button.visible = true
	_pan_to(0.0)

func _clear_modal() -> void:
	for modal in _modal_holder.get_children():
		_modal_holder.remove_child(modal)
		modal.queue_free()

## Die Fahrt bringt den Trainer an die Stelle des Tisches; die Übersicht füllt rechts daneben alles bis zum Bildschirmrand
func _layout_pan() -> void:
	_pan_width = _stage.position.x
	var stage_left_after := _content.get_global_rect().position.x
	var width := get_global_rect().end.x - (stage_left_after + _stage.size.x) - 2 * MODAL_GAP
	# die Übersicht reicht über die Bühne hinaus nach oben bis MODAL_TOP (der Ausgang ist solange ausgeblendet)
	var lift := maxf(_stage.get_global_rect().position.y - get_global_rect().position.y - MODAL_TOP, 0.0)
	_modal_holder.position = Vector2(_stage.size.x + MODAL_GAP, -lift)
	_modal_holder.size = Vector2(maxf(width, 0.0), _stage.size.y + lift - MODAL_GAP)
	if not (_pan_tween and _pan_tween.is_running()):
		_set_pan(_pan_width if _open_plate else 0.0)

func _pan_to(target: float) -> void:
	if _pan_tween:
		_pan_tween.kill()
	_pan_tween = create_tween()
	_pan_tween.tween_method(_set_pan, _pan, target, PAN_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if target <= 0.0:
		_pan_tween.tween_callback(_clear_modal)

## Tisch, Trainer und Übersicht hängen aneinander, nur die obere Leiste bleibt stehen
func _set_pan(value: float) -> void:
	_pan = value
	_columns.position.x = -value
	_modal_holder.visible = value > 0.0

## Parallax wie im Shop: der Hintergrund fährt mit einem Bruchteil der Fahrt mit und weicht der Maus leicht aus.
## Er ist dafür um genau den größten Ausschlag größer als der Bildschirm, so bleibt nie ein Rand frei.
func _process(delta: float) -> void:
	super(delta)
	if _columns == null:
		return
	# die Spalten sitzen in einem Container, der sie beim Neuordnen zurücksetzt
	if _columns.position.x != -_pan:
		_columns.position.x = -_pan
	var view := get_viewport_rect().size
	var mouse := get_viewport().get_mouse_position() / view - Vector2(0.5, 0.5)
	_mouse_parallax = _mouse_parallax.lerp(-2.0 * PARALLAX_MOUSE * mouse.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)), minf(1.0, delta * PARALLAX_FOLLOW))
	# fährt nach links mit, darum reicht er rechts um die ganze Fahrt über den Bildschirm hinaus
	var shift := Vector2(-_pan * PARALLAX_PAN, 0.0) + _mouse_parallax
	background.offset_left = shift.x - PARALLAX_MOUSE
	background.offset_right = shift.x + _pan_width * PARALLAX_PAN + PARALLAX_MOUSE
	background.offset_top = shift.y - PARALLAX_MOUSE
	background.offset_bottom = shift.y + PARALLAX_MOUSE

## Der Trainer sagt die Hinweise selbst, statt dass sie dauerhaft als Text dastehen
func set_drag_hint(key: String) -> void:
	super(key)
	_bubble.say(tr(key))

func _show_blocked(reason: String) -> void:
	_bubble.say(reason)

## Die Monster stehen immer auf den Platten, beim Ziehen werden nur die gesperrt, die nicht lernen können
func _build_targets(card: RewardCard) -> void:
	var learners: Array = card.drag.mons.call()
	if learners.is_empty():
		_bubble.say(card.drag.no_target)
	for plate in _plates:
		plate.locked = not learners.has(plate.mon)
	_show_missing_elements(card)

func _hide_targets() -> void:
	super()
	for plate in _plates:
		plate.locked = false
		plate.modulate = Color.WHITE
		plate.set_highlight(false)
	_show_missing_elements(_focused_card)

func _drop_targets() -> Array:
	return _plates

static func element_count(nature: int) -> int:
	return Enums.MON_TYPES.values().filter(func(element): return nature & element).size()

## Ei-Attacken ab MIN_TIER, je zur Hälfte mit einem und mit mehreren Elementen.
## Nur Skills, die mindestens ein Monster im Team sofort einsetzen kann und noch nicht kennt;
## fehlen davon welche, wird mit den übrigen passenden Skills aufgefüllt.
## Dazu kommen EXTRA_OFFERS beliebige Skills, die noch mindestens ein Monster lernen kann.
## Mit der Biom-Tiefe werden höhere Stufen wahrscheinlicher.
func _pick_offers() -> Array:
	# Pool des Trainers: Ei-Attacken, Schilde, Buffs, Passive und Flächenschaden, aber keine Standard-, Kopfgeld-,
	# Couvert- oder Aufstiegs-Skills und keine mit "trainer": false (Skills.trainer_skills)
	var rare = Skills.trainer_skills(MIN_TIER)
	var usable = rare.filter(func(skill): return State.mons.any(func(mon): return Skills.can_use(mon, skill) and not Skills.knows_skill(mon, skill.name)))
	# passt gar nichts (sollte nicht vorkommen), lieber unpassende Skills als ein leerer Trainer
	if usable.is_empty():
		usable = rare
	var single = usable.filter(func(skill): return element_count(skill.nature) == 1).map(func(skill): return skill.name)
	var multi = usable.filter(func(skill): return element_count(skill.nature) > 1).map(func(skill): return skill.name)
	var names = Skills.pick_weighted_unique(single, SINGLE_ELEMENT_OFFERS, State.map_level)
	names.append_array(Skills.pick_weighted_unique(multi, MULTI_ELEMENT_OFFERS, State.map_level))
	var rest = usable.map(func(skill): return skill.name).filter(func(skill_name): return not names.has(skill_name))
	names.append_array(Skills.pick_weighted_unique(rest, SINGLE_ELEMENT_OFFERS + MULTI_ELEMENT_OFFERS - names.size(), State.map_level))
	# reichen die seltenen Skills nicht für alle Plätze, kommen niedrigere Stufen dazu
	for pool in [rare, Skills.trainer_skills(1)]:
		var learnable = pool.filter(func(skill): return not names.has(skill.name) and State.mons.any(func(mon): return not Skills.knows_skill(mon, skill.name)))
		names.append_array(Skills.pick_weighted_unique(learnable.map(func(skill): return skill.name), SINGLE_ELEMENT_OFFERS + MULTI_ELEMENT_OFFERS + EXTRA_OFFERS - names.size(), State.map_level))
	_recommended = _pick_recommended(names)
	return (_recommended + names).map(func(skill_name): return Skills.get_skill(skill_name))

## Biom, auf das sich der Trainer vorbereitet: das nächste, im letzten Biom das aktuelle (Endboss)
static func next_biome() -> int:
	if State.biome_path.is_empty():
		return 0
	return State.biome_path[mini(State.map_level + 1, State.biome_path.size() - 1)]

## Ist der Skill gegen die Elemente des Bioms sehr effektiv? Nur magischer Schaden zählt, physische Angriffe
## treffen immer neutral (Skills.skill_element_multiplier).
static func is_recommended(skill: Dictionary, biome: int) -> bool:
	return biome != 0 and Skills.is_damage_skill(skill) and not Skills.is_physical(skill) and Skills.element_score(skill.nature, biome) > 0

## RECOMMENDED_OFFERS Angriffe gegen das nächste Biom, die noch nicht angeboten werden und die ein Monster lernen kann;
## bevorzugt welche, die es auch gleich einsetzen kann
func _pick_recommended(taken: Array) -> Array:
	var biome := next_biome()
	var candidates := Skills.trainer_skills(1).filter(func(skill): return is_recommended(skill, biome) and not taken.has(skill.name) and _learnable(skill))
	var usable := candidates.filter(func(skill): return State.mons.any(func(mon): return Skills.can_use(mon, skill)))
	var picked := Skills.pick_weighted_unique(usable.map(func(skill): return skill.name), RECOMMENDED_OFFERS, State.map_level)
	var rest := candidates.map(func(skill): return skill.name).filter(func(skill_name): return not picked.has(skill_name))
	picked.append_array(Skills.pick_weighted_unique(rest, RECOMMENDED_OFFERS - picked.size(), State.map_level))
	return picked

## Kennt mindestens ein Monster im Team den Skill noch nicht?
static func _learnable(skill: Dictionary) -> bool:
	return State.mons.any(func(mon): return not Skills.knows_skill(mon, skill.name))

## Stempel "Trainers Choice" als Wasserzeichen: liegt direkt auf dem Papier, hinter Text und Symbolen
func _add_recommended_stamp(card: RewardCard) -> void:
	var stamp := TrainerStamp.new()
	stamp.text = tr("TRAINER_CHOICE_STAMP")
	stamp.font = LABEL_THEME.get_font("font", "Label")
	card.add_child(stamp)
	var paper_index := 0
	for child in card.get_children():
		if child is SkillCardPaper:
			paper_index = child.get_index()
	card.move_child(stamp, paper_index + 1)
	card.tooltip_text += "\n" + tr("TRAINER_RECOMMENDED_HINT").format({"biome": tr(ColorMap.get_combo(next_biome()).label)})

## Preis aus der Karte nehmen und mit dem ME-Icon über die Karte stellen (wächst mit der Karte mit)
func _add_price_tag(card: RewardCard) -> void:
	var label: Label = _price_labels[card]
	label.get_parent().remove_child(label)
	label.add_theme_font_size_override("font_size", PRICE_FONT_SIZE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# der Container der Karte zieht jedes Kind auf ihre Größe, der Preis braucht eine Hülle
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(holder)
	var tag := HBoxContainer.new()
	tag.alignment = BoxContainer.ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_constant_override("separation", 6)
	var icon := texture_icon(ESSENCE_ICON)
	icon.custom_minimum_size = PRICE_ICON_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(icon)
	tag.add_child(label)
	holder.add_child(tag)
	tag.set_anchors_preset(Control.PRESET_TOP_WIDE)
	tag.offset_top = -PRICE_HEIGHT
	tag.offset_bottom = -4.0

## Neben dem Icon reicht die Zahl
func _show_price(card: RewardCard) -> void:
	super(card)
	_price_labels[card].text = str(price_of(card))

func _add_skill_card(skill: Dictionary) -> void:
	var card := add_skill_card(skill, func(mon: Monster): _learn(_dragged, mon))
	card.on_click = _toggle_focus.bind(card)
	# in der Pixel-Schrift passt die Beschreibung sonst nicht in die Kartenbreite
	card.info.get_child(1).add_theme_font_size_override("font_size", TRAINER_TEXT_FONT_SIZE)
	# lange Beschreibungen scrollen von selbst, alle Karten bleiben gleich hoch
	scroll_description(card, DESCRIPTION_HEIGHT)
	# Text nicht auf den Papierrahmen setzen (card.row liegt in der VBox mit Kopf- und Fußzeile, darüber der Rand)
	card.row.get_parent().get_parent().add_theme_constant_override("margin_bottom", 14)
	# Kosten, Abklingzeit, Wert und Element etwas größer, auf der verkleinerten Karte sonst kaum lesbar
	var face := card.row.get_parent()
	_enlarge(face.get_child(0), FACE_ROW_ZOOM)
	_enlarge(face.get_child(face.get_child_count() - 1), FACE_ROW_ZOOM)
	set_price(card, randi_range(skill.shop_cost.min, skill.shop_cost.max))
	_add_price_tag(card)
	if _recommended.has(skill.name):
		_add_recommended_stamp(card)
	ignore_mouse_below(card)

## Schriften, Icons und Mindestgrößen eines Kartenteils samt Kindern um factor vergrößern
static func _enlarge(node: Node, factor: float) -> void:
	# Wert und Art-Symbol hängen schon an der Größe des Namens (SkillCardFace.BottomRow)
	if node.has_meta("keep_font_size"):
		return
	if node is Label:
		node.add_theme_font_size_override("font_size", roundi(node.get_theme_font_size("font_size") * factor))
	elif node is Control and node.custom_minimum_size != Vector2.ZERO:
		node.custom_minimum_size *= factor
	for child in node.get_children():
		_enlarge(child, factor)

func _learn(card: RewardCard, mon: Monster) -> void:
	if await learn_skill(card.drag.skill, mon, _left_side):
		pay(card)

## Bezahlt wird in _learn, erst wenn der Skill wirklich gelernt ist
func _taken(_card: RewardCard) -> void:
	pass

func _drag_blocked(card: RewardCard) -> String:
	if _replace_picker:
		return tr("TRAINER_FINISH_CHOICE")
	return super(card)
