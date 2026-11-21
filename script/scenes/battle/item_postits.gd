extends Control

## One-Way-Items im Kampf: für jedes eigene Monster mit ausgerüsteten Items steckt am linken Rand ein Postit,
## eingefahren schaut nur das Bild des Monsters heraus. Ein Klick darauf fährt es aus (Item 2, Item 1, Monster)
## und wieder ein. Items zieht man auf ein Ziel (Monster oder Kampffeld), battle.gd setzt sie ein (Events.use_item).
## Einsetzen geht nur im Zug des Monsters, das das Item trägt; danach fährt das Postit wieder ein.
## Items, die von selbst wirken (Schildrune, Todes-Totem), stehen nur zur Info da.
## Antippen eines Items öffnet seine Erklärung als Dialog (ItemInfoDialog). Die Postits stehen mittig am Rand.

const CELL_SIZE := Vector2(64, 64)
const PORTRAIT_SIZE := Vector2(72, 72)
const GAP := 6
const MARGIN := 8
## so viel vom Postit schaut eingefahren heraus: das Monster samt Rand
const PEEK := PORTRAIT_SIZE.x + 2 * MARGIN
const SLIDE_SECONDS := 0.25
const SPACING := 10.0
const INACTIVE_MODULATE := Color(0.6, 0.6, 0.6)
const AUTO_MODULATE := Color(0.75, 0.75, 0.75, 0.8)

## Ein Platz auf dem Postit: zeigt das Item, lässt sich auf ein Ziel ziehen
class ItemCell extends PanelContainer:
	var postits: Node
	var mon: Monster
	var index: int
	var item
	var _press_pos := Vector2.ZERO

	func _init(owner_postits: Node, monster: Monster, slot_index: int) -> void:
		postits = owner_postits
		mon = monster
		index = slot_index
		item = monster._items[slot_index]
		custom_minimum_size = CELL_SIZE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.35)
		style.set_corner_radius_all(6)
		add_theme_stylebox_override("panel", style)
		if item == null:
			return
		var art := Items.icon(item)
		art.custom_minimum_size = CELL_SIZE - Vector2(8, 8)
		add_child(art)
		mouse_default_cursor_shape = Control.CURSOR_DRAG if usable() else Control.CURSOR_POINTING_HAND
		if Items.use_of(item) == Items.USE_AUTO:
			modulate = AUTO_MODULATE

	func usable() -> bool:
		return item != null and Items.use_of(item) != Items.USE_AUTO and postits.can_use.call(mon)

	## Antippen (ohne Ziehen) öffnet die Erklärung als Dialog, Tooltips gibt es am Handy nicht
	func _gui_input(event: InputEvent) -> void:
		if item == null or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_press_pos = event.position
		elif event.position.distance_to(_press_pos) < RewardDialog.CLICK_MAX_MOVE:
			InfoDialog.present(postits, ItemInfoDialog.new(item, mon, usable()))

	func _get_drag_data(_at_position: Vector2):
		if not usable():
			return null
		var art := Items.icon(item)
		art.size = CELL_SIZE
		art.position = -CELL_SIZE / 2
		var holder := Control.new()
		holder.add_child(art)
		set_drag_preview(holder)
		modulate.a = 0.4
		return {"type": "battle_item", "item": item, "carrier": mon, "index": index}

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END and item != null and Items.use_of(item) != Items.USE_AUTO:
			modulate.a = 1.0

## Erklärung eines Items im Kampf (wie die Skill-Details der Gegner als Dialog): Bild, Name, Seltenheit,
## Wirkung, wie man es einsetzt und wer es trägt
class ItemInfoDialog extends InfoDialog:
	const ART_SIZE := Vector2(110, 110)
	var item: Dictionary
	var mon: Monster
	var usable_now: bool

	func _init(battle_item: Dictionary, carrier: Monster, can_use_now: bool) -> void:
		super()
		item = battle_item
		mon = carrier
		usable_now = can_use_now

	func _accent() -> Color:
		return Items.rarity_color(item)

	func _build(content: VBoxContainer) -> void:
		var art_holder := CenterContainer.new()
		var art := Items.icon(item)
		art.custom_minimum_size = ART_SIZE
		art_holder.add_child(art)
		content.add_child(art_holder)
		content.add_child(_title(Items.title(item), SkillDetailPopup.GOLD))
		content.add_child(_text(tr(Items.RARITY_LABELS[Items.rarity_of(item)]), Items.rarity_color(item), NOTE_FONT_SIZE))
		var mon_name := Helper.mon_battle_name(mon)
		content.add_child(_text(tr("BATTLE_ITEM_CARRIER").format({"mon": mon_name}), IronPlate.TEXT_COLOR, NOTE_FONT_SIZE))
		var description := _note(Items.description(item), IronPlate.TEXT_COLOR)
		description.modulate.a = 1.0
		description.custom_minimum_size.x = SkillDetailPopup.WIDTH + 100
		description.add_theme_font_size_override("font_size", ROW_FONT_SIZE + 3)
		content.add_child(description)
		content.add_child(_text(Items.use_hint(item), SkillDetailPopup.GOLD, ROW_FONT_SIZE))
		if not usable_now and Items.use_of(item) != Items.USE_AUTO:
			content.add_child(_text(tr("BATTLE_ITEM_WAIT_TURN").format({"mon": mon_name}), INACTIVE_MODULATE, NOTE_FONT_SIZE))

## Postit eines Monsters, fährt per Klick auf das Monster aus und ein
class Postit extends PanelContainer:
	var postits: Node
	var mon: Monster
	var open := false
	var _tween: Tween

	func _init(owner_postits: Node, monster: Monster) -> void:
		postits = owner_postits
		mon = monster
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", GAP)
		IronPlate.frame(self, row, MARGIN, MARGIN)
		# wie in der Skizze: Item 2, Item 1, dann das Monster am Rand
		for i in range(mon._items.size() - 1, -1, -1):
			row.add_child(ItemCell.new(owner_postits, mon, i))
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = PORTRAIT_SIZE
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.material = Monmap.MONSTER_MATERIAL
		portrait.mouse_filter = Control.MOUSE_FILTER_STOP
		portrait.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		portrait.tooltip_text = tr("BATTLE_ITEMS_HINT")
		Monmap.show_on(portrait, mon._name, Monmap.TINY)
		portrait.gui_input.connect(_on_portrait_input)
		row.add_child(portrait)

	func _on_portrait_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			set_open(not open)

	func set_open(value: bool, animate := true) -> void:
		open = value
		var target_x := 0.0 if open else -(get_combined_minimum_size().x - PEEK)
		if _tween:
			_tween.kill()
		if not animate:
			position.x = target_x
			return
		_tween = create_tween()
		_tween.tween_property(self, "position:x", target_x, SLIDE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Darf mon gerade ein Item einsetzen? (battle.gd: eigener Zug genau dieses Monsters)
var can_use: Callable = func(_mon): return false
## Kampffeld (GameWindow): die Postits liegen über ihm, aber über dem Eingabe-Blocker, damit man sie auch
## im Zug der Gegner ausfahren kann. Items ohne Ziel lassen sich überall darauf ziehen.
var field: Control

var _postits: Array[Postit] = []

func _init(battle_field: Control) -> void:
	field = battle_field

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	anchor_left = field.anchor_left
	anchor_top = field.anchor_top
	anchor_right = field.anchor_right
	anchor_bottom = field.anchor_bottom
	offset_left = field.offset_left
	offset_top = field.offset_top
	offset_right = field.offset_right
	offset_bottom = field.offset_bottom
	field.set_drag_forwarding(Callable(), _can_drop_on_field, _drop_on_field)
	Events.monster_faints.connect(_on_monster_event)
	Events.monster_revived.connect(_on_monster_event)
	resized.connect(_layout)
	refresh()

func _exit_tree() -> void:
	Events.monster_faints.disconnect(_on_monster_event)
	Events.monster_revived.disconnect(_on_monster_event)
	if is_instance_valid(field):
		field.set_drag_forwarding(Callable(), Callable(), Callable())

func _on_monster_event(_mon) -> void:
	refresh.call_deferred()

func _can_drop_on_field(_at: Vector2, data) -> bool:
	return data is Dictionary and data.get("type") == "battle_item" and Items.use_of(data.item) == Items.USE_FIELD \
		and Items.battle_target_ok(data.item, null)

func _drop_on_field(_at: Vector2, data) -> void:
	Events.use_item.emit(data.carrier, data.index, null)

## Neu aufbauen: nach einem Einsatz, Zugwechsel, K.O. oder Wiederbeleben. Offen bleibt nur, was offen war und
## noch Items hat, eingesetzte Items lassen ihr Postit einfahren.
func refresh() -> void:
	var was_open := {}
	for postit in _postits:
		was_open[postit.mon] = {"open": postit.open, "count": postit.mon._items.filter(func(i): return i != null).size()}
		remove_child(postit)
		postit.queue_free()
	_postits.clear()
	for mon: Monster in State.mons:
		if not mon.is_alive() or not Items.has_items(mon):
			continue
		var postit := Postit.new(self, mon)
		add_child(postit)
		_postits.append(postit)
		# das Tutorial im Übungskampf hebt die Postits hervor (nicht die ganze Fläche)
		postit.add_to_group("tut_bat_items")
		var before: Dictionary = was_open.get(mon, {})
		var count := mon._items.filter(func(i): return i != null).size()
		postit.modulate = Color.WHITE if can_use.call(mon) else INACTIVE_MODULATE
		postit.set_open.call_deferred(before.get("open", false) and before.get("count", 0) == count, false)
	_layout.call_deferred()

## Postits untereinander, als Gruppe mittig über der Höhe des Kampffelds
func _layout() -> void:
	var total := 0.0
	for postit in _postits:
		postit.reset_size()
		total += postit.size.y
	total += SPACING * maxi(_postits.size() - 1, 0)
	var y := maxf((size.y - total) / 2, 0.0)
	for postit in _postits:
		postit.reset_size()
		postit.position.y = y
		y += postit.size.y + SPACING
