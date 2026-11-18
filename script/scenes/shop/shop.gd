extends ShopDialog

## Laden als freie Bühne im Stil des Kerkermeisters: rechts die Selbstzahler-Kasse mit der Sprechblase darüber,
## links vier Regale (2x2) mit je zwei Waren und Schildern, darunter die eigenen Monster von hinten (nur mit Typ),
## daneben die Tasche mit dem Geld und die Gutscheine.
## Ein Klick auf ein Monster fährt den ganzen Laden nach rechts, links erscheint die Übersicht seiner Attacken;
## nochmal angeklickt fährt der Laden zurück. Der Hintergrund bewegt sich dabei (und mit der Maus) leicht mit.
## Tränke und Edelsteine zieht man auf ein Monster, Relikte und Schlüssel in die Tasche; abgelegt ist die Ware gekauft.
## Tränke gibt es beliebig oft, alles andere nur einmal. Beim Ziehen und bei angeklickter Ware
## zeigen die Monster, was sich ändern würde. Ein Klick auf eine Ware öffnet ihre Beschreibung,
## die Ware bleibt dann golden umrandet, bis man sie nochmal anklickt.

const GemField = preload("res://script/scenes/gems/gems.gd")
const RelicReward = preload("res://script/scenes/relic_reward/relic_reward.gd")
const Treasure = preload("res://script/scenes/treasure/treasure.gd")

const SHELF_TEXTURE = preload("res://assets/ui/shop/shelf.svg")
const PROPS_MATERIAL = preload("res://script/scenes/jailer/jailer_props_material.tres")
const PIXEL_FONT = preload("res://script/ui/fonts/pxelfont/PixelifySans-VariableFont_wght.ttf")
const GOLD := SkillDetailPopup.GOLD
const NO_OUTLINE := Color(1, 1, 0, 0)

## Preise: grob ein Kampf bringt 10-30 EP, ein Biom also etwa 100-150 EP.
## Der Laden lohnt sich durch die Wahl: Tränke mit gezieltem Element (Schatzkisten haben nur zufällige),
## Trophäen mit frei wählbarem Wert (Beute ist zufällig) und Relikte, die es sonst nur als Boss-Belohnung gibt.
## Schlüssel gibt es hier nicht (mehr), die bringen nur Kämpfe.
const ELEMENT_PRICE := 45
## pro Trophäe, unabhängig von der Biom-Tiefe
const GEM_PRICE := 20
## pro Relikt; jedes angebotene Relikt lässt sich einzeln kaufen
const RELIC_PRICE := 35
const GEM_OFFERS := 2
const RELIC_OFFERS := 2

## Regale, alle Maße in Bühnen-Pixeln: zwei Reihen mit je zwei Brettern links der Kasse, je zwei Waren pro Brett.
## Index = Gruppe im Tutorial (tut_shop_shelf_<i>): oben die Tränke, unten links Trophäen, unten rechts Relikte.
const SHELF_HEIGHT := 46.0
const SHELF_ROWS_Y := [96.0, 266.0]
const SHELF_LAYOUT := [
	{"column": 0, "row": 0},
	{"column": 1, "row": 0},
	{"column": 0, "row": 1},
	{"column": 1, "row": 1},
]
const SHELF_POTIONS_LEFT := 0
const SHELF_POTIONS_RIGHT := 1
const SHELF_GEMS := 2
const SHELF_RELICS := 3
## Abstand der beiden Bretter einer Reihe und der Regale zur Kassen-Spalte
const SHELF_COLUMN_GAP := 56.0
const SHELF_RIGHT_GAP := 24.0
## Die Regale hängen nur vor der Holzwand des Hintergrunds: ihr rechter Rand (der Pfosten) als Anteil der Bildbreite,
## der Abstand dazu deckt auch den Ausschlag mit der Maus ab
const WALL_RIGHT := 820.0 / 1376.0
const WALL_GAP := 16.0
const MAX_TAG_WIDTH := 220.0

## Kassen-Spalte rechts: Breite, darin steht die Kasse, die Sprechblase darüber
const RIGHT_COLUMN_WIDTH := 340.0
## Kasse: Bildausschnitt als Anteil der Bildhöhe (darüber und darunter ist das Bild leer)
const CHECKOUT_TOP := 0.117
const CHECKOUT_BOTTOM := 0.88
## Oberkante des sichtbaren Körpers, unten steht die Kasse auf dem Bildschirmrand
const CHECKOUT_FIRST_Y := 300.0
const JUMP_HEIGHT := 40.0
const JUMP_SECONDS := 0.16

const BUBBLE_WIDTH := 300.0
## Zipfel der Blase berührt den Kopf der Kasse
const BUBBLE_OVERLAP := 6.0
const POPUP_GAP := 8.0
const BAG_OVERHANG := 2.0
## Gutscheine rechts neben der Tasche: Abstand zur Tasche und zum unteren Bildschirmrand
const COUPON_GAP := 4.0
const COUPON_BOTTOM := 12.0

## Monster unten links: Abstand zum Bildschirmrand und untereinander, die Tasche folgt nach dem zweiten Platz
const FIELD_SCREEN_GAP := 8.0
const FIELD_SPACING := 4.0
const BAG_GAP := 8.0

## Klick auf ein Monster: der Laden fährt so weit nach rechts, dass links davon nur noch so viel Laden zu sehen ist
## (beide Monster und das linke Regal), daneben steht die Attacken-Übersicht (MonSkillsModal)
const MON_VIEW_WIDTH := 520.0
const MODAL_GAP := 12.0
## Höhe der Übersicht wie beim Trainer: oben beginnt sie dort unter dessen Leiste (Tasche, Verlassen-Button),
## unten endet sie über dem Rand; beides in Bildschirm-Pixeln
const MODAL_TOP := 142.0
const MODAL_BOTTOM := 36.0
const PAN_SECONDS := 0.45
## Parallax des Hintergrunds: Anteil der Fahrt, um den er mitfährt, Ausschlag mit der Maus, Nachziehen pro Sekunde
const PARALLAX_PAN := 0.1
const PARALLAX_MOUSE := 12.0
const PARALLAX_FOLLOW := 6.0

## Sprechblase: Anzeigedauer pro Satz, danach der Dank
const LINE_BASE_SECONDS := 2.5
const LINE_SECONDS_PER_CHAR := 0.04
const THANKS_COUNT := 3
const HOWTO_LINES := ["SHOP_SAY_WELCOME", "SHOP_SAY_POTIONS", "SHOP_SAY_GEMS", "SHOP_SAY_RELICS", "SHOP_SAY_CLICK"]

## Ware im Regal: oben steht das Bild auf dem Brett, darunter hängt das Schild mit dem Namen.
## Die Beschreibung steht nur im Popup, das ein Klick öffnet.
class ShelfItem extends RewardDialog.RewardCard:
	const ART_SIZE := Vector2(68, 68)
	## das Bild hat etwas Rand, so steht die Ware sichtbar auf dem Brett
	const ART_SINK := 6.0
	const TITLE_FONT_SIZE := 16
	const PRICE_FONT_SIZE := 17
	const TAG_MARGIN := 7
	const SWITCH_SIZE := Vector2(30, 34)
	const SWITCH_FONT_SIZE := 26
	const SWITCH_Y := 10.0

	var art: Control
	var title: String
	var description: String
	var _holder: Control
	var _tag: PanelContainer
	var _plate: IronPlate
	var _title_label: Label
	var _price_label: Label
	## Material des Bildes, darin wird es golden
	var _gold_target: ShaderMaterial
	## Pfeile links und rechts vom Bild (Trophäen: Wert umschalten), leer bei anderer Ware
	var _switch_buttons: Array[Button] = []

	func _init(owner_dialog: RewardDialog, card_title: String, text: String, icon: Control, drag_data: Dictionary) -> void:
		dialog = owner_dialog
		title = card_title
		description = text
		drag = drag_data
		drag.title = card_title
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_holder = Control.new()
		add_child(_holder)
		_build_tag()
		set_art(icon)

	func _build_tag() -> void:
		_tag = PanelContainer.new()
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		_plate = IronPlate.frame(_tag, box, TAG_MARGIN, TAG_MARGIN - 2)
		_title_label = _tag_label(box, title, TITLE_FONT_SIZE, GOLD)
		_holder.add_child(_tag)

	## Ein umbrechendes Label misst seine Höhe an seiner aktuellen Breite. Vor dem ersten Layout ist die noch
	## winzig und das Schild bliebe riesig, darum bekommt das Label die Breite hier direkt gesetzt.
	func _fit_tag(width: float) -> void:
		_title_label.custom_minimum_size.x = width - 2 * TAG_MARGIN
		_title_label.size.x = _title_label.custom_minimum_size.x
		_title_label.update_minimum_size()
		_tag.reset_size()

	func _tag_label(parent: Control, text: String, font_size: int, color: Color) -> Label:
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_override("font", PIXEL_FONT)
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", color)
		parent.add_child(label)
		return label

	## Bild tauschen, es bekommt den Pixel-Look mit eigenem Umriss und bleibt an der Stelle des alten
	func set_art(icon: Control) -> void:
		var index := -1
		var spot := Vector2.ZERO
		if art:
			index = art.get_index()
			spot = art.position
			_holder.remove_child(art)
			art.queue_free()
		art = icon
		art.custom_minimum_size = ART_SIZE
		art.size = ART_SIZE
		art.position = spot
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_holder.add_child(art)
		if index >= 0:
			_holder.move_child(art, index)
		_gold_target = PROPS_MATERIAL.duplicate()
		art.material = _gold_target
		_ignore_mouse_below()

	## Kinder fangen keine Maus ab, nur die Pfeile bleiben anklickbar
	func _ignore_mouse_below() -> void:
		RewardDialog.ignore_mouse_below(self)
		for button in _switch_buttons:
			button.mouse_filter = Control.MOUSE_FILTER_STOP

	func set_text(card_title: String, text: String) -> void:
		title = card_title
		description = text
		drag.title = card_title
		_title_label.text = card_title

	## Pfeile neben dem Bild, on_switch(step) mit -1 (links) bzw. +1 (rechts)
	func add_switch(on_switch: Callable, tooltip: String) -> void:
		for step in [-1, 1]:
			var button := Button.new()
			button.text = "<" if step < 0 else ">"
			button.tooltip_text = tooltip
			button.focus_mode = Control.FOCUS_NONE
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.size = SWITCH_SIZE
			button.add_theme_font_override("font", PIXEL_FONT)
			button.add_theme_font_size_override("font_size", SWITCH_FONT_SIZE)
			RewardDialog.clear_button_styles(button, StyleBoxEmpty.new())
			button.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
			button.add_theme_color_override("font_hover_color", GOLD)
			button.add_theme_color_override("font_pressed_color", GOLD)
			button.add_theme_color_override("font_outline_color", Color.BLACK)
			button.add_theme_constant_override("outline_size", 6)
			button.pressed.connect(on_switch.bind(step))
			_holder.add_child(button)
			_switch_buttons.append(button)
		_ignore_mouse_below()

	func set_gold(gold: bool) -> void:
		_gold_target.set_shader_parameter("outline_color", GOLD if gold else NO_OUTLINE)
		_plate.set_rim(GOLD if gold else IronPlate.RIM)

	## Preis neben dem Bild
	func insert_detail(control: Control) -> void:
		_price_label = control
		_price_label.theme = null
		_price_label.add_theme_font_override("font", PIXEL_FONT)
		_price_label.add_theme_font_size_override("font_size", PRICE_FONT_SIZE)
		_price_label.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
		_price_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_price_label.add_theme_constant_override("outline_size", 4)
		_holder.add_child(_price_label)
		_ignore_mouse_below()

	## center: Mitte des Brettes unter der Ware, Bild steht darauf, Schild hängt darunter
	func place_on_shelf(center: Vector2, width: float) -> void:
		_fit_tag(width)
		position = center - Vector2(width / 2, ART_SIZE.y)
		art.position = Vector2((width - ART_SIZE.x) / 2, ART_SINK)
		if _price_label:
			_price_label.position = Vector2(art.position.x + ART_SIZE.x, ART_SIZE.y - 26)
		# Pfeile auf halber Höhe des Bildes, oberhalb des Preises
		for i in _switch_buttons.size():
			var x := art.position.x - SWITCH_SIZE.x if i == 0 else art.position.x + ART_SIZE.x
			_switch_buttons[i].position = Vector2(x, SWITCH_Y)
		_tag.position = Vector2(0, ART_SIZE.y + SHELF_HEIGHT / 2)
		size = Vector2(width, _tag.position.y + _tag.size.y)

## Eigenes Monster unten links, ohne Rahmen und ohne Werte: groß von hinten, darunter sein Typ.
## Golden umrandet, solange seine Übersicht offen ist oder Ware darüber schwebt. Das ganze Feld ist Ablegeziel.
## Trophäen zeigen über dem Monster kurz, wie sich der Wert ändern würde.
class MonField extends RewardDialog.DropTarget:
	const IMAGE_SIZE := 250.0
	const CHIPS_HEIGHT := 32.0
	const FIELD_SIZE := Vector2(250, IMAGE_SIZE + CHIPS_HEIGHT)
	const BOOST_FONT_SIZE := 18
	const STAT_GETTERS := {"hp": "hp", "atk": "attack", "def": "defense", "s_atk": "s_attack", "s_def": "s_defense", "speed": "speed"}
	const SELECTED_SCALE := Vector2(1.08, 1.08)
	const SELECT_SECONDS := 0.2

	var _image: TextureRect
	var _chips: HBoxContainer
	## goldene Zeile über dem Monster: Wert vorher -> nachher, nur bei Trophäen
	var _boost: Label
	var _pop: Tween
	## Attacken-Übersicht dieses Monsters ist offen: goldener Umriss, Bild etwas größer
	var _selected := false
	var _highlighted := false
	## Klick ohne Ziehen: Übersicht der Attacken (MonSkillsModal wie beim Trainer)
	var on_click: Callable
	var _press_pos := Vector2.ZERO

	func _gui_input(event: InputEvent) -> void:
		if not on_click.is_valid() or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_press_pos = event.position
		elif event.position.distance_to(_press_pos) < RewardDialog.CLICK_MAX_MOVE:
			on_click.call()

	func _init(owner_dialog: RewardDialog, monster: Monster) -> void:
		dialog = owner_dialog
		mon = monster
		# Klicks gehen durch bis zum Boden (_on_floor_input), Ablegen klappt trotzdem
		mouse_filter = Control.MOUSE_FILTER_PASS
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = Helper.mon_display_name(monster._name)
		custom_minimum_size = FIELD_SIZE
		size = FIELD_SIZE
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var holder := Control.new()
		add_child(holder)
		_image = RewardDialog.texture_icon(Monmap.texture(monster._name, IMAGE_SIZE, true)) as TextureRect
		_image.material = Monmap.MONSTER_MATERIAL
		_image.size = Vector2(IMAGE_SIZE, IMAGE_SIZE)
		_image.position = Vector2((FIELD_SIZE.x - IMAGE_SIZE) / 2, 0)
		_image.pivot_offset = Vector2(IMAGE_SIZE / 2, IMAGE_SIZE)
		holder.add_child(_image)
		_chips = HBoxContainer.new()
		_chips.alignment = BoxContainer.ALIGNMENT_CENTER
		_chips.add_theme_constant_override("separation", 4)
		_chips.position = Vector2(0, IMAGE_SIZE)
		_chips.size = Vector2(FIELD_SIZE.x, CHIPS_HEIGHT)
		holder.add_child(_chips)
		_boost = Label.new()
		_boost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_boost.position = Vector2(0, 0)
		_boost.size = Vector2(FIELD_SIZE.x, BOOST_FONT_SIZE + 8)
		_boost.add_theme_font_override("font", PIXEL_FONT)
		_boost.add_theme_font_size_override("font_size", BOOST_FONT_SIZE)
		_boost.add_theme_color_override("font_color", GOLD)
		_boost.add_theme_color_override("font_outline_color", Color.BLACK)
		_boost.add_theme_constant_override("outline_size", 6)
		holder.add_child(_boost)
		RewardDialog.ignore_mouse_below(self)
		show_preview({})

	func covers(global_point: Vector2) -> bool:
		return get_global_rect().has_point(global_point)

	## Aktueller Typ; drag (Ware in der Hand oder angeklickt) zeigt dazu, was sich ändern würde
	func show_preview(drag: Dictionary) -> void:
		RewardDialog.show_element_preview(_chips, mon, drag)
		var stat: String = drag.get("stat", "")
		_boost.visible = stat != ""
		if _boost.visible:
			var value: int = roundi(mon.call(STAT_GETTERS[stat]))
			_boost.text = "%s %d %s %d" % [tr(GemField.STATS[stat].stat).trim_suffix(":"), value, RewardDialog.PREVIEW_ARROW, value + drag.bonus]

	## Wie beim Trainer: das angeklickte Monster bekommt den goldenen Umriss und wächst etwas
	func set_selected(selected: bool) -> void:
		_selected = selected
		_show_gold()
		if _pop:
			_pop.kill()
		_pop = create_tween()
		_pop.tween_property(_image, "scale", _rest_scale(), SELECT_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	## Beim Ziehen leuchtet der Umriss nur, solange die Ware darüber schwebt, die Auswahl bleibt golden
	func set_highlight(on: bool) -> void:
		_highlighted = on
		_show_gold()

	func _show_gold() -> void:
		_image.material = Monmap.monster_selected_material if _selected or _highlighted else Monmap.MONSTER_MATERIAL

	func _rest_scale() -> Vector2:
		return SELECTED_SCALE if _selected else Vector2.ONE

	## Hat gerade etwas bekommen: kurz golden aufleuchten und wachsen
	func celebrate() -> void:
		_image.material = Monmap.monster_selected_material
		if _pop:
			_pop.kill()
		_pop = create_tween()
		_pop.tween_property(_image, "scale", _rest_scale() * 1.08, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_pop.tween_property(_image, "scale", _rest_scale(), 0.2)
		_pop.tween_interval(0.5)
		_pop.tween_callback(_show_gold)

## Offene Tasche neben den Monstern, auf der Plakette steht das Geld. Ablegeziel für Relikte und Schlüssel.
class ShopBag extends RewardDialog.DropTarget:
	const BAG_SIZE := Vector2(208, 196)
	const FONT_SIZE := 19

	var money: Label
	var _art: OpenBag
	var _pop: Tween
	## angeklickte Ware gehört in die Tasche / gezogene Ware schwebt darüber
	var _preview := false
	var _hovered := false

	func _init(owner_dialog: RewardDialog) -> void:
		dialog = owner_dialog
		# Klicks gehen durch bis zum Boden (_on_floor_input), Ablegen klappt trotzdem
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = BAG_SIZE
		size = BAG_SIZE
		pivot_offset = Vector2(BAG_SIZE.x / 2, BAG_SIZE.y)
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var holder := Control.new()
		add_child(holder)
		_art = OpenBag.new(BAG_SIZE, null, Vector2.ZERO, FONT_SIZE)
		holder.add_child(_art)
		money = _art.label
		RewardDialog.ignore_mouse_below(self)

	func covers(global_point: Vector2) -> bool:
		return get_global_rect().has_point(global_point)

	## Golden, solange angeklickte Ware in die Tasche gehört
	func set_gold(gold: bool) -> void:
		_preview = gold
		_art.set_gold(_preview or _hovered)

	## Golden, solange Ware für die Tasche darüber gezogen wird
	func set_highlight(on: bool) -> void:
		_hovered = on
		_art.set_gold(_preview or _hovered)

	func celebrate() -> void:
		if _pop:
			_pop.kill()
		scale = Vector2(1.15, 0.85)
		_pop = create_tween()
		_pop.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Beschreibung der angeklickten Ware, fliegt von ihrer Seite her über der Kasse ein
class ItemPopup extends PanelContainer:
	const WIDTH := 300.0
	const ART_SIZE := Vector2(80, 80)
	const FLY_IN := 60.0

	var _art_holder: CenterContainer
	var _title: Label
	var _price: Label
	var _description: Label
	var _hint: Label

	func _init(on_close: Callable) -> void:
		visible = false
		custom_minimum_size.x = WIDTH
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		IronPlate.frame(self, box, 16, 14)
		_art_holder = CenterContainer.new()
		box.add_child(_art_holder)
		_title = _label(box, 24, GOLD)
		_price = _label(box, 20, IronPlate.TEXT_COLOR)
		_description = _label(box, 19, IronPlate.TEXT_COLOR)
		_hint = _label(box, 16, GOLD)
		var close := RewardDialog.plate_button(tr("MONSTER_CLOSE_INFO"))
		close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		close.pressed.connect(on_close)
		box.add_child(close)

	func _label(parent: Control, font_size: int, color: Color) -> Label:
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = WIDTH - 32
		label.add_theme_font_override("font", PIXEL_FONT)
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", color)
		parent.add_child(label)
		return label

	func show_item(item: ShelfItem, center_x: float, top: float) -> void:
		for child in _art_holder.get_children():
			_art_holder.remove_child(child)
			child.queue_free()
		var copy: Control = item.art.duplicate(0)
		copy.custom_minimum_size = ART_SIZE
		_art_holder.add_child(copy)
		_title.text = item.title
		_price.text = Helper.me_text(item.dialog.price_of(item))
		_description.text = item.description
		_hint.text = tr("SHOP_DETAIL_BAG" if item.drag.get("bag", false) else "SHOP_DETAIL_MON")
		visible = true
		# wie bei den Schildern: Breite direkt setzen, sonst misst der erste Aufruf das Popup riesig
		for label: Label in [_title, _price, _description, _hint]:
			label.size.x = label.custom_minimum_size.x
			label.update_minimum_size()
		reset_size()
		var target_x := center_x - size.x / 2
		position = Vector2(target_x + (FLY_IN if item.global_position.x > global_position.x else -FLY_IN), top)
		modulate.a = 0.0
		var tween := create_tween().set_parallel()
		tween.tween_property(self, "position:x", target_x, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "modulate:a", 1.0, 0.2)

## Wellen-Hintergrund aus der Szene
@export var background: Control
## Bild der Kasse aus der Szene, dort lassen sich auch die Shader-Werte einstellen
@export var checkout_image: TextureRect

var _stage: Control
## der ganze Laden ohne Verlassen-Button und Attacken-Übersicht: fährt beim Klick auf ein Monster nach rechts
var _world: Control
var _item_layer: Control
var _shelves: Array[Dictionary] = []
## Regal, auf dem die nächste Ware landet
var _filling_shelf := 0
var _mon_fields: Array[MonField] = []
var _bag: ShopBag
var _bubble: SpeechBubble
var _bubble_holder: Control
var _popup: ItemPopup
var _exit_button: Button
## angeklickte Ware, deren Beschreibung offen ist
var _selected: ShelfItem
var _checkout_y := 0.0
var _jump: Tween
var _line_tween: Tween
## noch offene Sätze der Erklärung
var _lines: Array = []
var _explaining := false
## Bonus der Trophäen im Regal, hängt von der Biom-Tiefe ab
var _trophy_bonus := 0
## Fläche links neben dem Laden für die Attacken-Übersicht (_toggle_mon) und das Monster, dessen Übersicht offen ist
var _modal_holder: Control
var _open_field: MonField
## Bildschirm in Bühnen-Koordinaten, die Bühne selbst endet etwas vor dem Rand
var _screen := Rect2()
## wie weit der Laden gerade nach rechts gefahren ist und wie weit er für die Übersicht fährt
var _pan := 0.0
var _pan_width := 0.0
var _pan_tween: Tween
var _modal_left := 0.0
## Ausschlag des Hintergrunds mit der Maus, zieht weich nach
var _mouse_parallax := Vector2.ZERO

func _ready() -> void:
	use_scene_layout(background)
	_title.visible = false
	_columns.visible = false
	_build_stage()
	_fill_shelves()
	_money_label = _bag.money
	# aufs Beutelschild passt nur die Zahl, die Preise daneben nennen die Währung
	_money_suffix = ""
	_watch_money()
	add_coupons(_world, checkout_image)
	_add_tutorial_targets()
	# beim ersten Besuch erklärt die Kasse im Tutorial, mit Blick auf die Regale; danach bleibt der letzte Satz stehen
	if not Tutorial.trigger("shop", _after_tutorial):
		_explain()

## Gruppen, die das interaktive Tutorial hervorhebt (siehe Tutorial.SEQUENCES)
func _add_tutorial_targets() -> void:
	checkout_image.add_to_group("tut_npc")
	_bag.add_to_group("tut_shop_bag")
	for i in _mon_fields.size():
		_mon_fields[i].add_to_group("tut_shop_mon_%d" % i)
	# eine Gruppe pro Regal: Brett und Ware zusammen
	for i in _shelves.size():
		var group := "tut_shop_shelf_%d" % i
		_shelves[i].image.add_to_group(group)
		for item: Control in _shelves[i].items:
			item.add_to_group(group)

func _after_tutorial() -> void:
	_bubble.say(tr(HOWTO_LINES[-1]))

## Freie Bühne statt der Standard-Spalten: alles wird in _layout_stage platziert.
## Die Ware liegt über den Monstern, damit sich nichts verdecken lässt, was man anklicken will.
func _build_stage() -> void:
	_stage = Control.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.resized.connect(_layout_stage)
	_content.add_child(_stage)
	_panel.gui_input.connect(_on_floor_input)
	_world = Control.new()
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_world)

	checkout_image.reparent(_world, false)
	for layout: Dictionary in SHELF_LAYOUT:
		var shelf := TextureRect.new()
		shelf.texture = SHELF_TEXTURE
		shelf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shelf.stretch_mode = TextureRect.STRETCH_SCALE
		shelf.material = PROPS_MATERIAL
		shelf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_world.add_child(shelf)
		_shelves.append({"layout": layout, "image": shelf, "items": []})
	for i in mini(State.mons.size(), 2):
		var field := MonField.new(self, State.mons[i])
		field.on_click = _toggle_mon.bind(field)
		_world.add_child(field)
		_mon_fields.append(field)
	_item_layer = Control.new()
	_item_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(_item_layer)
	_bag = ShopBag.new(self)
	_world.add_child(_bag)
	# Zipfel nach unten zur Kasse, die Blase wächst nach oben
	_bubble = SpeechBubble.new(BUBBLE_WIDTH, true, false, true)
	_bubble.resized.connect(_place_bubble)
	# die Blase steht, wo die Beschreibung der Ware erscheint: solange die offen ist, schweigt die Kasse
	_bubble_holder = Control.new()
	_bubble_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(_bubble_holder)
	_bubble_holder.add_child(_bubble)
	_popup = ItemPopup.new(_set_selected.bind(null))
	_world.add_child(_popup)
	_modal_holder = Control.new()
	_modal_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_modal_holder)
	_exit_button = icon_button(EXIT_ICON)
	_exit_button.tooltip_text = tr("SHOP_FINISH")
	_exit_button.pressed.connect(close)
	_stage.add_child(_exit_button)

func _layout_stage() -> void:
	var area := _stage.size
	_world.size = area
	# die Bühne endet etwas vor dem Bildschirmrand, Monster, Tasche und Kasse sollen aber bis an den Rand reichen
	var own := get_global_rect()
	_screen = Rect2(own.position - _stage.get_global_rect().position, own.size)
	var column_left := _screen.end.x - RIGHT_COLUMN_WIDTH
	var column_center := column_left + RIGHT_COLUMN_WIDTH / 2
	_pan_width = maxf(_screen.size.x - MON_VIEW_WIDTH, 0.0)

	# Kasse: der sichtbare Körper reicht von CHECKOUT_FIRST_Y bis an den unteren Bildschirmrand
	var checkout_height := (_screen.end.y - CHECKOUT_FIRST_Y) / (CHECKOUT_BOTTOM - CHECKOUT_TOP)
	var texture_size := checkout_image.texture.get_size()
	checkout_image.size = texture_size * checkout_height / texture_size.y
	_checkout_y = CHECKOUT_FIRST_Y - CHECKOUT_TOP * checkout_height
	checkout_image.position = Vector2(column_center - checkout_image.size.x / 2, _checkout_y)
	checkout_image.pivot_offset = Vector2(checkout_image.size.x / 2, CHECKOUT_BOTTOM * checkout_image.size.y)
	_place_bubble()

	var shelves_left := _screen.position.x + FIELD_SCREEN_GAP
	var shelves_right := minf(column_left - SHELF_RIGHT_GAP, _wall_right() - WALL_GAP)
	var shelf_width := (shelves_right - shelves_left - SHELF_COLUMN_GAP) / 2
	for shelf in _shelves:
		_layout_shelf(shelf, shelves_left, shelf_width)

	# Monster nebeneinander am unteren Rand, die Tasche folgt immer nach dem zweiten Platz
	var slot_width := MonField.FIELD_SIZE.x + FIELD_SPACING
	var field_top := _screen.end.y - FIELD_SCREEN_GAP - MonField.FIELD_SIZE.y
	for i in _mon_fields.size():
		_mon_fields[i].position = Vector2(_screen.position.x + FIELD_SCREEN_GAP + i * slot_width, field_top)
	_bag.position = Vector2(_screen.position.x + FIELD_SCREEN_GAP + 2 * slot_width + BAG_GAP, _screen.end.y + BAG_OVERHANG - ShopBag.BAG_SIZE.y)
	_coupon_stack.reset_size()
	_coupon_stack.position = Vector2(_bag.position.x + ShopBag.BAG_SIZE.x + COUPON_GAP, _screen.end.y - COUPON_BOTTOM - _coupon_stack.size.y)
	# nur der Körper der Kasse, die Sprechblase darüber bleibt frei
	_coupon_target.position = Vector2(checkout_image.position.x, CHECKOUT_FIRST_Y)
	_coupon_target.size = Vector2(checkout_image.size.x, _screen.end.y - CHECKOUT_FIRST_Y)

	_exit_button.position = Vector2(area.x - ICON_BUTTON_SIZE.x, 0)
	# Attacken-Übersicht: füllt links alles, was die Fahrt freigibt
	_modal_left = _screen.position.x + MODAL_GAP
	_modal_holder.size = Vector2(_pan_width - 2 * MODAL_GAP, _screen.size.y - MODAL_TOP - MODAL_BOTTOM)
	_modal_holder.position.y = _screen.position.y + MODAL_TOP
	if not (_pan_tween and _pan_tween.is_running()):
		_set_pan(_pan_width if _open_field else 0.0)

## Rechter Rand der Holzwand auf der Bühne, gemessen am Hintergrund in Ruhelage (keine Fahrt, Maus in der Mitte,
## siehe _process); das Bild füllt den Hintergrund und wird dafür mittig beschnitten
func _wall_right() -> float:
	var extra := _pan_width * PARALLAX_PAN
	var rect := Rect2(-extra - PARALLAX_MOUSE, -PARALLAX_MOUSE, size.x + extra + 2 * PARALLAX_MOUSE, size.y + 2 * PARALLAX_MOUSE)
	var texture_size := (background as TextureRect).texture.get_size()
	var image_scale := maxf(rect.size.x / texture_size.x, rect.size.y / texture_size.y)
	var image_left := rect.position.x + (rect.size.x - texture_size.x * image_scale) / 2
	return _screen.position.x + image_left + WALL_RIGHT * texture_size.x * image_scale

## Blase über der Kasse, ihr Zipfel zeigt nach unten auf den Kopf; lange Texte wachsen nach oben,
## höchstens bis unter den Verlassen-Button
func _place_bubble() -> void:
	if _world == null or checkout_image.size == Vector2.ZERO:
		return
	var tail := SpeechBubble.TAIL_SIZE.x + SpeechBubble.TAIL_POSITION.x
	var x := checkout_image.position.x + (checkout_image.size.x - _bubble.size.x) / 2
	x = minf(x, _screen.end.x - FIELD_SCREEN_GAP - _bubble.size.x)
	var y := CHECKOUT_FIRST_Y + BUBBLE_OVERLAP - tail - _bubble.size.y
	_bubble.position = Vector2(x, maxf(y, ICON_BUTTON_SIZE.y + POPUP_GAP))

## Brett an seinen Platz im 2x2-Raster setzen, die Ware gleichmäßig darauf verteilen
func _layout_shelf(shelf: Dictionary, shelves_left: float, width: float) -> void:
	var layout: Dictionary = shelf.layout
	var left: float = shelves_left + layout.column * (width + SHELF_COLUMN_GAP)
	var y: float = SHELF_ROWS_Y[layout.row]
	var image: TextureRect = shelf.image
	image.size = Vector2(width, SHELF_HEIGHT)
	image.position = Vector2(left, y)
	var count: int = shelf.items.size()
	var tag_width := minf(width / maxi(count, 1) - 10.0, MAX_TAG_WIDTH)
	for i in count:
		var center := Vector2(left + width * (i + 0.5) / count, y)
		shelf.items[i].place_on_shelf(center, tag_width)

## Beschreibung der Ware über der Kasse, unter dem Verlassen-Button
func _show_popup(item: ShelfItem) -> void:
	_popup.show_item(item, checkout_image.position.x + checkout_image.size.x / 2, ICON_BUTTON_SIZE.y + POPUP_GAP)

func _fill_shelves() -> void:
	var elements: Array = Treasure.ELEMENTS
	for i in elements.size():
		_filling_shelf = SHELF_POTIONS_LEFT if i < elements.size() / 2 else SHELF_POTIONS_RIGHT
		set_price(Treasure.add_potion_card(self, elements[i]), ELEMENT_PRICE, true)
	_filling_shelf = SHELF_GEMS
	_add_gem_offers()
	_filling_shelf = SHELF_RELICS
	_add_relic_offers()
	# die Bühne kennt ihre Größe erst nach dem ersten Layout
	await get_tree().process_frame
	_layout_stage()

func _depth() -> int:
	return maxi(State.map_level, 0)

## Trophäen starten mit verschiedenen Werten, die Pfeile schalten den Wert frei um
func _add_gem_offers() -> void:
	_trophy_bonus = DebugSettings.trophy_bonus(_depth())
	var stats = GemField.STATS.keys()
	stats.shuffle()
	for stat in stats.slice(0, GEM_OFFERS):
		var card: ShelfItem = GemField.add_gem_card(self, stat, _trophy_bonus)
		card.add_switch(_switch_trophy.bind(card), tr("SHOP_TROPHY_SWITCH"))
		set_price(card, GEM_PRICE)

## Nächster bzw. vorheriger Wert: Name, Text, Bild und was beim Ablegen passiert wechseln mit
func _switch_trophy(step: int, item: ShelfItem) -> void:
	if item.sold:
		return
	var stats: Array = GemField.STATS.keys()
	var stat: String = stats[posmod(stats.find(item.drag.stat) + step, stats.size())]
	var parts := GemField.gem_card_parts(self, stat, _trophy_bonus)
	item.drag.merge(parts.drag, true)
	item.set_text(parts.title, parts.text)
	item.set_art(GemField.gem_icon(stat))
	# der neue Name kann anders umbrechen, das Schild passt sich an
	_layout_stage()
	item.set_gold(item == _selected or item.get_global_rect().has_point(get_global_mouse_position()))
	if item == _selected:
		_show_popup(item)
	_update_previews()

## Mehrere Relikte, jedes einzeln kaufbar: wer eins kauft, behält die anderen im Regal
func _add_relic_offers() -> void:
	var unowned = Relics.shop_offers()
	unowned.shuffle()
	for id in unowned.slice(0, RELIC_OFFERS):
		set_price(RelicReward.add_relic_card(self, id), RELIC_PRICE)

## Karten der gemeinsamen Helfer (Trank, Edelstein, Relikt, Schlüssel) landen als Ware im aktuellen Regal
func _add_card(card_title: String, text: String, icon: Control, drag: Dictionary) -> RewardCard:
	var item := ShelfItem.new(self, card_title, text, icon, drag)
	item.on_click = _toggle_item.bind(item)
	item.mouse_entered.connect(_hover_item.bind(item, true))
	item.mouse_exited.connect(_hover_item.bind(item, false))
	_item_layer.add_child(item)
	_shelves[_filling_shelf].items.append(item)
	return item

## Golden, solange die Maus darauf liegt oder die Ware angeklickt ist: zeigt, dass man sie anklicken kann
func _hover_item(item: ShelfItem, over: bool) -> void:
	if not item.sold and _dragged == null:
		item.set_gold(over or item == _selected)

## Die Beschreibung der Ware und die Attacken-Übersicht sind nie zugleich offen
func _toggle_item(item: ShelfItem) -> void:
	if not item.sold:
		_close_mon()
		_set_selected(null if item == _selected else item)

func _set_selected(item: ShelfItem) -> void:
	if _selected:
		_selected.set_gold(false)
	_selected = item
	if item:
		item.set_gold(true)
		_show_popup(item)
	else:
		_popup.visible = false
	_bubble_holder.visible = item == null
	_update_previews()

## Klick ins Leere legt die angeklickte Ware zurück
func _on_floor_input(event: InputEvent) -> void:
	if _selected and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_set_selected(null)

## Klick auf ein Monster: der Laden fährt nach rechts, links daneben erscheint die Übersicht seiner Attacken
## (dasselbe MonSkillsModal wie beim Trainer), das Monster bleibt markiert. Ein anderes Monster wechselt nur
## die Übersicht, dasselbe nochmal fährt den Laden zurück.
func _toggle_mon(field: MonField) -> void:
	if field == _open_field:
		_close_mon()
		return
	_set_selected(null)
	if _open_field:
		_open_field.set_selected(false)
	_clear_modal()
	_open_field = field
	field.set_selected(true)
	_modal_holder.add_child(MonSkillsModal.new(field.mon))
	# solange die Übersicht offen ist, verlässt kein versehentlicher Klick oben rechts den Laden
	_exit_button.visible = false
	_pan_to(_pan_width)

## Laden zurückfahren, die Übersicht fährt links mit hinaus und verschwindet danach
func _close_mon() -> void:
	if _open_field == null:
		return
	_open_field.set_selected(false)
	_open_field = null
	_exit_button.visible = true
	_pan_to(0.0)

func _clear_modal() -> void:
	for modal in _modal_holder.get_children():
		_modal_holder.remove_child(modal)
		modal.queue_free()

func _pan_to(target: float) -> void:
	if _pan_tween:
		_pan_tween.kill()
	_pan_tween = create_tween()
	_pan_tween.tween_method(_set_pan, _pan, target, PAN_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if target <= 0.0:
		_pan_tween.tween_callback(_clear_modal)

## Laden und Übersicht hängen aneinander: die Übersicht steht immer direkt links vom Laden
func _set_pan(value: float) -> void:
	_pan = value
	_world.position.x = value
	_modal_holder.position.x = _modal_left + value - _pan_width
	_modal_holder.visible = value > 0.0

## Parallax: der Hintergrund fährt mit einem Bruchteil der Fahrt mit und weicht der Maus leicht aus.
## Er ist dafür um genau den größten Ausschlag größer als der Bildschirm, so bleibt nie ein Rand frei.
func _process(delta: float) -> void:
	super(delta)
	if _world == null:
		return
	var view := get_viewport_rect().size
	var mouse := get_viewport().get_mouse_position() / view - Vector2(0.5, 0.5)
	_mouse_parallax = _mouse_parallax.lerp(-2.0 * PARALLAX_MOUSE * mouse.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)), minf(1.0, delta * PARALLAX_FOLLOW))
	var shift := Vector2(_pan * PARALLAX_PAN, 0.0) + _mouse_parallax
	background.offset_left = shift.x - _pan_width * PARALLAX_PAN - PARALLAX_MOUSE
	background.offset_right = shift.x + PARALLAX_MOUSE
	background.offset_top = shift.y - PARALLAX_MOUSE
	background.offset_bottom = shift.y + PARALLAX_MOUSE

func _update_previews() -> void:
	var drag: Dictionary = {}
	if _dragged:
		drag = _dragged.drag
	elif _selected:
		drag = _selected.drag
	var into_bag: bool = drag.get("bag", false)
	var buyers := [] if drag.is_empty() or into_bag else _buyers(drag)
	for field in _mon_fields:
		field.show_preview(drag if buyers.has(field.mon) else {})
	# beim Ziehen leuchtet die Tasche erst, wenn die Ware darüber schwebt (set_highlight)
	_bag.set_gold(into_bag and _dragged == null)

## Monster, die diese Ware bekommen können
func _buyers(drag: Dictionary) -> Array:
	return drag.mons.call() if drag.mons is Callable else drag.mons

# ── Erklärung und Dank in der Sprechblase ─────────────────────────

## Von vorn erklären, wie der Laden funktioniert; der letzte Satz bleibt stehen
func _explain() -> void:
	_lines = HOWTO_LINES.duplicate()
	_explaining = true
	_next_line()

func _next_line() -> void:
	if _line_tween:
		_line_tween.kill()
	if _lines.is_empty():
		_explaining = false
		return
	var text := tr(_lines.pop_front())
	_bubble.say(text)
	if _lines.is_empty():
		_explaining = false
		return
	_line_tween = _after_reading(text, _next_line)

## Etwas zwischendurch sagen, danach beginnt die Erklärung von vorn
func _interrupt(text: String) -> void:
	if _line_tween:
		_line_tween.kill()
	_explaining = false
	_bubble.say(text)
	_line_tween = _after_reading(text, _explain)

func _after_reading(text: String, then: Callable) -> Tween:
	var tween := create_tween()
	tween.tween_interval(LINE_BASE_SECONDS + text.length() * LINE_SECONDS_PER_CHAR)
	tween.tween_callback(then)
	return tween

## Ein Klick springt zum nächsten Satz der Erklärung, der Klick selbst wirkt normal weiter
func _input(event: InputEvent) -> void:
	if _explaining and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_next_line()

## Die Kasse hüpft zweimal vor Freude
func _jump_for_joy() -> void:
	if _jump:
		_jump.kill()
	checkout_image.position.y = _checkout_y
	checkout_image.rotation_degrees = 0.0
	_jump = create_tween()
	for hop: float in [1.0, 0.55]:
		_jump.tween_property(checkout_image, "position:y", _checkout_y - JUMP_HEIGHT * hop, JUMP_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_jump.parallel().tween_property(checkout_image, "rotation_degrees", 3.0 * hop, JUMP_SECONDS)
		_jump.tween_property(checkout_image, "position:y", _checkout_y, JUMP_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_jump.parallel().tween_property(checkout_image, "rotation_degrees", 0.0, JUMP_SECONDS)

# ── Kaufen ─────────────────────────

## Verkaufte Einzelstücke verschwinden aus dem Regal, die übrige Ware bleibt an ihrem Platz
func mark_sold(card: RewardCard) -> void:
	super(card)
	card.visible = false

## Gekauft, sobald die Ware auf einem Ziel liegt
func _taken(card: RewardCard) -> void:
	var mouse := get_global_mouse_position()
	pay(card)
	for field in _mon_fields:
		if field.covers(mouse):
			field.celebrate()
	if card.drag.get("bag", false):
		_bag.celebrate()
	_jump_for_joy()
	_interrupt(tr("SHOP_SAY_THANKS_%d" % randi_range(0, THANKS_COUNT - 1)).format({"item": card.drag.title}))

func _show_blocked(reason: String) -> void:
	_interrupt(reason)

## Offene Beschreibung schließen, sie zeigt noch den alten Preis
func _coupon_applied() -> void:
	_set_selected(null)
	_jump_for_joy()
	_interrupt(tr("SHOP_SAY_COUPON"))

func _show_targets(card: RewardCard) -> void:
	_set_selected(null)
	super(card)
	(card as ShelfItem).set_gold(false)

## Beim Ziehen bleiben alle Ziele stehen, gesperrt wird, wer die Ware nicht nehmen kann
func _build_targets(card: RewardCard) -> void:
	var into_bag: bool = card.drag.get("bag", false)
	_bag.locked = not into_bag
	var buyers := [] if into_bag else _buyers(card.drag)
	for field in _mon_fields:
		field.locked = not buyers.has(field.mon)
	if not into_bag and buyers.is_empty():
		_interrupt(tr("REWARD_NO_TARGET"))
	_update_previews()

func _hide_targets() -> void:
	super()
	if _bag == null:
		return
	for target in _drop_targets():
		target.locked = false
		target.modulate = Color.WHITE
		target.set_highlight(false)
	_update_previews()

func _drop_targets() -> Array:
	var targets: Array = _mon_fields.duplicate()
	targets.append(_bag)
	return targets

## Am Mauszeiger hängt das Bild der Ware
func _make_drag_preview(card: RewardCard) -> Control:
	var art: Control = (card as ShelfItem).art.duplicate(0)
	art.size = ShelfItem.ART_SIZE
	art.position = -ShelfItem.ART_SIZE / 2
	var holder := Control.new()
	holder.add_child(art)
	return holder
