extends ShopDialog

## Trainer: verkauft seltene Skills (ab Stufe 2), die Hälfte davon mit mehreren Elementen, damit
## sich der Weg lohnt. Gezogen auf ein Monster ist der Skill gelernt; hat es keinen freien Slot,
## wählt man, welcher Skill dafür vergessen wird. Bezahlt wird erst, wenn wirklich gelernt wurde.
## Auf jeder Karte zeigen kleine Bilder, welche Monster den Skill einsetzen können.
##
## Links liegen die Karten geneigt und überlappend in zwei Reihen. Ein Klick richtet eine Karte auf
## und schiebt die anderen ihrer Reihe zur Seite. Rechts hält der Trainer die eigenen Monster auf
## seinen Platten; ein Klick auf ein Monster öffnet dessen Skills über den Karten.

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

	func _gui_input(event: InputEvent) -> void:
		if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_press_pos = event.position
		elif event.position.distance_to(_press_pos) < RewardDialog.CLICK_MAX_MOVE:
			on_click.call()

	func set_selected(selected: bool) -> void:
		icon.material = Monmap.living_selected_material if selected else Monmap.LIVING_MATERIAL
		if _tween:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, "scale", SELECTED_SCALE if selected else Vector2.ONE, SELECT_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Tasche oben links, zeigt die Essenz (wie die Boss Tränen beim Kerkermeister), nur zur Anzeige
const BAG_SIZE := Vector2(104, 98)
const ESSENCE_SIZE := Vector2(34, 34)
const BAG_FONT_SIZE := 18
## so viel Essenz steht für ein sichtbares Stück in der Tasche
const ESSENCE_PER_ITEM := 25
const TRAINER_CARD_SIZE := Vector2(210, 0)
const TRAINER_TEXT_FONT_SIZE := 14
## Chips unter den Monstern: Abstand zum Monster, Zeilenhöhe
const CHIPS_GAP := 8.0
const CHIPS_HEIGHT := 36.0
const CARD_COLUMNS := 4
const MIN_TIER := 2
const SINGLE_ELEMENT_OFFERS := 2
const MULTI_ELEMENT_OFFERS := 2
## zusätzliche Skills in der zweiten Reihe, müssen zu keinem Monster passen
const EXTRA_OFFERS := 4

const CARD_TILT := deg_to_rad(-4.0)
## Anteil der Kartenbreite bzw. -höhe, der von der Nachbarkarte verdeckt wird
const CARD_OVERLAP := 0.09
const ROW_OVERLAP := 0.06
## Platz für die Ecken der geneigten Karten
const TILT_MARGIN := 20.0
## aufgerichtete Karte: Vergrößerung und Abstand zu den weggedrückten Nachbarn
const FOCUS_ZOOM := 1.2
const PUSH_GAP := 8.0
const CARD_MOVE_SECONDS := 0.25

## Bildausschnitt des Trainers, Anteile der Bildgröße: so viel muss über die Höhe der Karten passen
## (der Rest verschwindet nach unten), Mitte der Platten, Plattenbreite, linker Rand des Gesichts
const TRAINER_VISIBLE_HEIGHT := 0.72
const PLATE_CENTERS: Array[Vector2] = [Vector2(0.244, 0.615), Vector2(0.756, 0.615)]
const PLATE_WIDTH := 0.40
const FACE_LEFT := 0.37
## Monster auf der Platte, bezogen auf die Plattenbreite
const MON_SIZE_ON_PLATE := 1.1
const BUBBLE_WIDTH := 320.0
## ragt nach oben aus der Bühne, damit die Blase nicht auf den Karten liegt
const BUBBLE_TOP := -30.0
const BUBBLE_TAIL := 18.0

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
var _open_plate: PlateMon
var _modal: MonSkillsModal
var _bag: OpenBag

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
	var exit_button := icon_button(EXIT_ICON)
	exit_button.tooltip_text = tr("SHOP_FINISH")
	exit_button.size_flags_vertical = SIZE_SHRINK_BEGIN
	exit_button.pressed.connect(close)
	bar.add_child(exit_button)
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
	_bubble = SpeechBubble.new(BUBBLE_WIDTH, true)
	_stage.add_child(_bubble)

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
	_bubble.position = origin + Vector2(FACE_LEFT * image_size.x - BUBBLE_WIDTH - BUBBLE_TAIL, BUBBLE_TOP)
	if _coupon_target:
		_coupon_target.position = origin
		_coupon_target.size = image_size

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
	var rows := ceili(_cards.size() / float(_card_columns))
	var fit_x := (area.x - TILT_MARGIN) / (card_size.x * (_card_columns - (_card_columns - 1) * CARD_OVERLAP))
	var fit_y := (area.y - TILT_MARGIN) / (card_size.y * (rows - (rows - 1) * ROW_OVERLAP))
	var base_scale := minf(fit_x, fit_y)
	var focus_scale := minf(base_scale * FOCUS_ZOOM, area.y / card_size.y)
	var scaled := card_size * base_scale
	var row_step := scaled.y * (1.0 - ROW_OVERLAP)
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
			var center := Vector2(centers[i], first_y + row * row_step)
			var card: RewardCard = cards[i]
			card.size = card_size
			card.pivot_offset = card_size / 2
			var is_focused := i == focused
			if is_focused:
				# aufgerichtete Karte bleibt ganz auf dem Tisch
				var half_height := card_size.y * focus_scale / 2
				center.y = clampf(center.y, half_height, area.y - half_height)
			var target_scale := Vector2.ONE * (focus_scale if is_focused else base_scale)
			var target_rotation := 0.0 if is_focused else CARD_TILT
			var target_position := center - card.pivot_offset
			if animate:
				_card_tween.tween_property(card, "position", target_position, CARD_MOVE_SECONDS)
				_card_tween.tween_property(card, "rotation", target_rotation, CARD_MOVE_SECONDS)
				_card_tween.tween_property(card, "scale", target_scale, CARD_MOVE_SECONDS)
			else:
				card.position = target_position
				card.rotation = target_rotation
				card.scale = target_scale

## Mittelpunkte der Karten einer Reihe. Mit aufgerichteter Karte (focused >= 0) rücken die anderen
## beiseite und überlappen sich untereinander so stark, wie es nötig ist, um auf dem Tisch zu bleiben.
func _row_centers(count: int, focused: int, card_width: float, focus_width: float, width: float) -> Array[float]:
	var centers: Array[float] = []
	var step := card_width * (1.0 - CARD_OVERLAP)
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

## Klick auf eine Karte richtet sie auf, nochmal Klicken legt sie zurück
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

## Klick auf ein Monster: Übersicht öffnen, wechseln oder wieder schließen
func _toggle_mon(plate: PlateMon) -> void:
	if _replace_picker:
		_bubble.say(tr("TRAINER_FINISH_CHOICE"))
		return
	var was_open := plate == _open_plate
	if _open_plate:
		_open_plate.set_selected(false)
		_open_plate = null
		_modal.queue_free()
	if was_open:
		return
	_open_plate = plate
	plate.set_selected(true)
	_modal = MonSkillsModal.new(plate.mon)
	_left_side.add_child(_modal)

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
	var rare = Skills.egg_skills.filter(func(skill): return skill.tier >= MIN_TIER)
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
	for pool in [rare, Skills.egg_skills]:
		var learnable = pool.filter(func(skill): return not names.has(skill.name) and State.mons.any(func(mon): return not Skills.knows_skill(mon, skill.name)))
		names.append_array(Skills.pick_weighted_unique(learnable.map(func(skill): return skill.name), SINGLE_ELEMENT_OFFERS + MULTI_ELEMENT_OFFERS + EXTRA_OFFERS - names.size(), State.map_level))
	return names.map(func(skill_name): return Skills.get_skill(skill_name))

func _add_skill_card(skill: Dictionary) -> void:
	var card := add_skill_card(skill, func(mon: Monster): _learn(_dragged, mon))
	card.on_click = _toggle_focus.bind(card)
	# in der Pixel-Schrift passt die Stats-Zeile sonst nicht in die Kartenbreite
	card.info.get_child(1).add_theme_font_size_override("font_size", TRAINER_TEXT_FONT_SIZE)
	# Text nicht auf den Papierrahmen setzen
	card.row.get_parent().add_theme_constant_override("margin_bottom", 14)
	set_price(card, randi_range(skill.shop_cost.min, skill.shop_cost.max))
	ignore_mouse_below(card)

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
