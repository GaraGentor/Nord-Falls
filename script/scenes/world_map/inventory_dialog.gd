extends Control

## Inventar über der Kartenfläche (der Header der Karte bleibt sichtbar), geöffnet über die Tasche oben links im Header:
## links die eigenen Monster untereinander mit je Items.SLOTS_PER_MON Plätzen, in der Mitte alle One-Way-Items der Tasche
## als Raster mit Items.BAG_COLUMNS Spalten (scrollt, sobald sie wächst), rechts Bild und Beschreibung des
## angeklickten Items. Items lassen sich überall hin ziehen: auf ein Monster, zurück in die Tasche oder auf einen
## anderen Platz (dort tauschen sie). Der angeklickte Platz hat den goldenen Rahmen wie ein ausgewähltes Monster.
## Monster-Details aus dem Header legen sich darüber.

const SLOT_SIZE := Vector2(84, 84)
const PORTRAIT_SIZE := Vector2(96, 96)
const DETAIL_WIDTH := 300.0
const DETAIL_ART_SIZE := Vector2(110, 110)
const TITLE_FONT_SIZE := 24
const TEXT_FONT_SIZE := 18
const BACK_ICON := preload("res://assets/ui/icons/icon_back.svg")
const HOVER_RIM := Color(0.5, 0.62, 0.63)
## so viele Zeilen teilen sich die Höhe der Team-Spalte (ein einzelnes Monster nimmt die Hälfte)
const TEAM_ROWS := 2

## Ein Platz am Monster oder in der Tasche: Ablegeziel und, wenn belegt, ziehbar
class InvSlot extends PanelContainer:
	var dialog: Control
	## {"mon": Monster oder null (Tasche), "index": int}
	var ref: Dictionary
	var item
	var plate: IronPlate
	var _press_pos := Vector2.ZERO

	func _init(owner_dialog: Control, slot_ref: Dictionary) -> void:
		dialog = owner_dialog
		ref = slot_ref
		item = Items.get_at(ref)
		custom_minimum_size = SLOT_SIZE
		var holder := CenterContainer.new()
		plate = IronPlate.frame(self, holder, 6, 6)
		if item != null:
			var art := Items.icon(item)
			art.custom_minimum_size = SLOT_SIZE - Vector2(20, 20)
			holder.add_child(art)
			tooltip_text = Items.title(item)
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		RewardDialog.ignore_mouse_below(self)
		mouse_entered.connect(func(): dialog.hover_slot(self, true))
		mouse_exited.connect(func(): dialog.hover_slot(self, false))

	func same_place(other: Dictionary) -> bool:
		return other.mon == ref.mon and other.index == ref.index

	func _gui_input(event: InputEvent) -> void:
		if item == null or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_press_pos = event.position
		elif event.position.distance_to(_press_pos) < RewardDialog.CLICK_MAX_MOVE:
			dialog.select(ref)

	func _get_drag_data(_at_position: Vector2):
		if item == null:
			return null
		var art := Items.icon(item)
		art.size = SLOT_SIZE
		art.position = -SLOT_SIZE / 2
		var preview := Control.new()
		preview.add_child(art)
		set_drag_preview(preview)
		modulate.a = 0.4
		dialog.select(ref)
		return {"type": "inventory_item", "ref": ref}

	func _can_drop_data(_at_position: Vector2, data) -> bool:
		return data is Dictionary and data.get("type") == "inventory_item" and not same_place(data.ref)

	func _drop_data(_at_position: Vector2, data) -> void:
		dialog.move(data.ref, ref)

var _left: VBoxContainer
var _grid: GridContainer
var _detail: VBoxContainer
## angeklickter Platz (zeigt seine Details), {} = keiner
var _selected := {}
var _slots: Array[InvSlot] = []

func _init() -> void:
	theme = RewardDialog.FONT_THEME
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	# Klicks gehen nicht auf die Karte darunter durch
	mouse_filter = MOUSE_FILTER_STOP

func _ready() -> void:
	offset_top = RewardDialog.MAP_HEADER_HEIGHT
	var panel := PanelContainer.new()
	RewardDialog.fit_to_map_area(panel)
	add_child(panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	IronPlate.frame(panel, columns, 24, 20)

	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 12)
	columns.add_child(_left)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 8)
	columns.add_child(middle)
	middle.add_child(_heading(tr("INVENTORY_BAG")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# kein DragScroll: Ziehen gehört hier den Items, gescrollt wird mit dem Mausrad bzw. der Leiste
	middle.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(center)
	_grid = GridContainer.new()
	_grid.columns = Items.BAG_COLUMNS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	center.add_child(_grid)

	# Details zwischen Tasche und Zurück-Button, oben ausgerichtet; langer Text scrollt statt alles zu strecken
	var detail_scroll := ScrollContainer.new()
	detail_scroll.custom_minimum_size.x = DETAIL_WIDTH
	detail_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DragScroll.attach(detail_scroll)
	columns.add_child(detail_scroll)
	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = SIZE_EXPAND_FILL
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 10)
	IronPlate.frame(detail_panel, _detail, 16, 14)
	detail_scroll.add_child(detail_panel)

	# Zurück zeigt nach rechts: der Dialog schließt zur Karte hin
	var back := RewardDialog.icon_button(_mirrored(BACK_ICON))
	back.tooltip_text = tr("MONSTER_INFO_BACK")
	back.size_flags_vertical = SIZE_SHRINK_BEGIN
	back.pressed.connect(queue_free)
	columns.add_child(back)

	Items.normalize_bag()
	Items.items_changed.connect(_rebuild)
	_rebuild()

func _exit_tree() -> void:
	if Items.items_changed.is_connected(_rebuild):
		Items.items_changed.disconnect(_rebuild)

## Ziehen vom einen Platz auf den anderen: tauschen bzw. verschieben, die Auswahl wandert mit
func move(from: Dictionary, to: Dictionary) -> void:
	Items.swap(from, to)
	_selected = to if Items.get_at(to) != null else {}
	_rebuild()

func select(ref: Dictionary) -> void:
	_selected = ref
	_show_selection()

func hover_slot(slot: InvSlot, over: bool) -> void:
	if not _is_selected(slot):
		slot.plate.set_rim(HOVER_RIM if over else IronPlate.RIM)

func _is_selected(slot: InvSlot) -> bool:
	return not _selected.is_empty() and slot.same_place(_selected)

func _rebuild() -> void:
	_slots.clear()
	for child in _left.get_children() + _grid.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	_left.add_child(_heading(tr("INVENTORY_TEAM")))
	# jedes Monster bekommt die Hälfte der Höhe, auch wenn nur eins im Team ist
	for i in maxi(State.mons.size(), TEAM_ROWS):
		var entry: Control = _mon_entry(State.mons[i]) if i < State.mons.size() else Control.new()
		entry.size_flags_vertical = SIZE_EXPAND_FILL
		_left.add_child(entry)
	for i in State.bag.size():
		var slot := InvSlot.new(self, {"mon": null, "index": i})
		_grid.add_child(slot)
		_slots.append(slot)
	if not _selected.is_empty() and Items.get_at(_selected) == null:
		_selected = {}
	_show_selection()

## Monster mit Bild und Namen (ohne eigenen Rahmen), das Bild füllt die Höhe der Zeile,
## rechts dicht daneben seine Plätze untereinander
func _mon_entry(mon: Monster) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	var portrait: TextureRect = RewardDialog.mon_icon(mon)
	portrait.custom_minimum_size = PORTRAIT_SIZE
	# Breite folgt der Höhe, das Bild wächst mit der Zeile
	portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = SIZE_EXPAND_FILL
	info.add_child(portrait)
	var name_label := Label.new()
	name_label.text = Helper.mon_battle_name(mon)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Helper.color_by_mon(mon).lightened(0.4))
	info.add_child(name_label)
	row.add_child(info)
	var slots := VBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 8)
	for i in Items.SLOTS_PER_MON:
		var slot := InvSlot.new(self, {"mon": mon, "index": i})
		slots.add_child(slot)
		_slots.append(slot)
	row.add_child(slots)
	return row

## Spiegelbild eines Symbols (Zurück-Pfeil nach rechts)
static func _mirrored(texture: Texture2D) -> Texture2D:
	var image := texture.get_image()
	image.flip_x()
	return ImageTexture.create_from_image(image)

## Goldener Rahmen am angeklickten Platz, rechts seine Details
func _show_selection() -> void:
	for slot in _slots:
		slot.plate.set_rim(Monmap.SELECTED_OUTLINE_COLOR if _is_selected(slot) else IronPlate.RIM)
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	var item = null if _selected.is_empty() else Items.get_at(_selected)
	if item == null:
		var hint := _text(tr("INVENTORY_EMPTY_DETAIL" if Items.bag_count() == 0 and not _any_equipped() else "INVENTORY_PICK_ITEM"), TEXT_FONT_SIZE, IronPlate.TEXT_COLOR)
		_detail.add_child(hint)
		return
	var art_holder := CenterContainer.new()
	var art := Items.icon(item)
	art.custom_minimum_size = DETAIL_ART_SIZE
	art_holder.add_child(art)
	_detail.add_child(art_holder)
	_detail.add_child(_text(Items.title(item), TITLE_FONT_SIZE, SkillDetailPopup.GOLD))
	_detail.add_child(_text(tr(Items.RARITY_LABELS[Items.rarity_of(item)]), TEXT_FONT_SIZE - 2, Items.rarity_color(item)))
	_detail.add_child(_text(Items.description(item), TEXT_FONT_SIZE, IronPlate.TEXT_COLOR))
	_detail.add_child(_text(Items.use_hint(item), TEXT_FONT_SIZE - 2, SkillDetailPopup.GOLD))
	if _selected.mon == null:
		_detail.add_child(_text(tr("INVENTORY_EQUIP_HINT"), TEXT_FONT_SIZE - 3, IronPlate.TEXT_COLOR))

func _any_equipped() -> bool:
	return State.mons.any(Items.has_items)

func _heading(text: String) -> Label:
	return _text(text, 20, SkillDetailPopup.GOLD)

func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = DETAIL_WIDTH - 40
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

## Abgebrochenes Ziehen: das Item erscheint wieder voll
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		for slot in _slots:
			if is_instance_valid(slot):
				slot.modulate.a = 1.0
