extends ShopDialog

## Laden als freie Bühne im Stil des Kerkermeisters: in der Mitte die Selbstzahler-Kasse mit Sprechblase,
## links und rechts Regale mit der Ware und Schildern, unten links die eigenen Monster von hinten
## samt Typ und Werten in gleich großen Feldern, unter der Kasse die Tasche mit dem Geld, rechts daneben die Gutscheine.
## Tränke und Edelsteine zieht man auf ein Monster, Relikte und Schlüssel in die Tasche; abgelegt ist die Ware gekauft.
## Tränke gibt es beliebig oft, alles andere nur einmal. Beim Ziehen und bei angeklickter Ware
## zeigen die Monster, was sich ändern würde. Ein Klick auf eine Ware öffnet ihre Beschreibung,
## die Ware bleibt dann golden umrandet, bis man sie nochmal anklickt.

const GemField = preload("res://script/scenes/gems/gems.gd")
const RelicReward = preload("res://script/scenes/relic_reward/relic_reward.gd")
const Treasure = preload("res://script/scenes/treasure/treasure.gd")

const KEY_ICON = preload("res://assets/ui/icons/key.svg")
const SHELF_TEXTURE = preload("res://assets/ui/shop/shelf.svg")
const PROPS_MATERIAL = preload("res://script/scenes/jailer/jailer_props_material.tres")
const PIXEL_FONT = preload("res://script/ui/fonts/pxelfont/PixelifySans-VariableFont_wght.ttf")
const GOLD := SkillDetailPopup.GOLD
const NO_OUTLINE := Color(1, 1, 0, 0)

## Preise: grob ein Kampf bringt 10-30 EP, ein Biom also etwa 100-150 EP.
## Elemente sind die günstigste Ware, damit sich ein zweites Element früh lohnt. Edelsteine steigen
## mit der Tiefe (wie ihr Bonus). Relics sind die teuerste Ware, weil es sie sonst nur als Boss-Belohnung gibt.
const ELEMENT_PRICE := 45
## pro Biom-Tiefe (State.map_level)
const GEM_PRICES := [50, 65, 80, 100, 120]
const RELIC_PRICES := [150, 175, 200, 225, 250]
## vorläufig, bis feststeht, was ein Schlüssel öffnet
const KEY_PRICE := 75
const GEM_OFFERS := 2
const RELIC_OFFERS := 1

## Regale, alle Maße in Bühnen-Pixeln: innere Kante neben der Kasse, von dort gehen sie nach außen
const SHELF_INNER_GAP := 128.0
const SHELF_HEIGHT := 46.0
const SHELF_LAYOUT := [
	{"side": -1, "y": 90.0, "width": 370.0},
	{"side": 1, "y": 90.0, "width": 370.0},
	{"side": -1, "y": 296.0, "width": 345.0},
	{"side": 1, "y": 296.0, "width": 345.0},
]
const SHELF_POTIONS_LEFT := 0
const SHELF_POTIONS_RIGHT := 1
const SHELF_GEMS := 2
const SHELF_RELICS := 3
const MAX_TAG_WIDTH := 240.0

## Kasse: Bildausschnitt als Anteil der Bildhöhe (darüber und darunter ist das Bild leer)
const CHECKOUT_TOP := 0.117
const CHECKOUT_BOTTOM := 0.88
const CHECKOUT_FIRST_Y := 104.0
const CHECKOUT_LAST_Y := 560.0
const JUMP_HEIGHT := 46.0
const JUMP_SECONDS := 0.16

const BUBBLE_WIDTH := 350.0
const BUBBLE_LEFT := 142.0
const BUBBLE_TOP := 416.0
const POPUP_TOP := 8.0
const BAG_OVERHANG := 26.0
## Gutscheine rechts neben der Tasche: Abstand zur Tasche und zum unteren Bildschirmrand
const COUPON_GAP := 4.0
const COUPON_BOTTOM := 12.0

## Monster-Felder unten links: so weit endet die Bühne vor dem Bildschirmrand, so weit bleiben die Felder davon weg
const STAGE_MARGIN := 24.0
const FIELD_SCREEN_GAP := 8.0
const FIELD_SPACING := 4.0

## Sprechblase: Anzeigedauer pro Satz, danach der Dank
const LINE_BASE_SECONDS := 2.5
const LINE_SECONDS_PER_CHAR := 0.04
const THANKS_COUNT := 3
const HOWTO_LINES := ["SHOP_SAY_WELCOME", "SHOP_SAY_POTIONS", "SHOP_SAY_GEMS", "SHOP_SAY_RELICS", "SHOP_SAY_CLICK"]

## Ware im Regal: oben steht das Bild auf dem Brett, darunter hängt das Schild mit dem Namen.
## Die Beschreibung steht nur im Popup, das ein Klick öffnet.
class ShelfItem extends RewardDialog.RewardCard:
	const ART_SIZE := Vector2(84, 84)
	## das Bild hat etwas Rand, so steht die Ware sichtbar auf dem Brett
	const ART_SINK := 7.0
	const TITLE_FONT_SIZE := 16
	const PRICE_FONT_SIZE := 17
	const TAG_MARGIN := 7

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

	## Bild tauschen, es bekommt den Pixel-Look mit eigenem Umriss
	func set_art(icon: Control) -> void:
		if art:
			art.queue_free()
		art = icon
		art.custom_minimum_size = ART_SIZE
		art.size = ART_SIZE
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_holder.add_child(art)
		_gold_target = PROPS_MATERIAL.duplicate()
		art.material = _gold_target
		RewardDialog.ignore_mouse_below(self)

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
		RewardDialog.ignore_mouse_below(self)

	## center: Mitte des Brettes unter der Ware, Bild steht darauf, Schild hängt darunter
	func place_on_shelf(center: Vector2, width: float) -> void:
		_fit_tag(width)
		position = center - Vector2(width / 2, ART_SIZE.y)
		art.position = Vector2((width - ART_SIZE.x) / 2, ART_SINK)
		if _price_label:
			_price_label.position = Vector2(art.position.x + ART_SIZE.x, ART_SIZE.y - 26)
		_tag.position = Vector2(0, ART_SIZE.y + SHELF_HEIGHT / 2)
		size = Vector2(width, _tag.position.y + _tag.size.y)

## Eigenes Monster unten links, immer gleich groß und in einem Rahmen: oben links das Bild von hinten,
## daneben Name und Typ, unten die Reihe mit allen Werten. Das ganze Feld ist Ablegeziel.
class MonField extends RewardDialog.DropTarget:
	## die Höhe nutzt den Platz unter den Schildern der Regale
	const FIELD_SIZE := Vector2(504, 136)
	const IMAGE_SIZE := 84.0
	const NAME_FONT_SIZE := 20
	const STAT_FONT_SIZE := 16
	const STAT_GETTERS := {"hp": "hp", "atk": "attack", "def": "defense", "s_atk": "s_attack", "s_def": "s_defense", "speed": "speed"}

	var _image: TextureRect
	var _chips: HBoxContainer
	## Wert -> Labels für Bezeichnung und Zahl, untereinander
	var _stat_labels := {}
	var _pop: Tween

	func _init(owner_dialog: RewardDialog, monster: Monster) -> void:
		dialog = owner_dialog
		mon = monster
		# Klicks gehen durch bis zum Boden (_on_floor_input), Ablegen klappt trotzdem
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = FIELD_SIZE
		size = FIELD_SIZE
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		IronPlate.frame(self, box, 10, 5)

		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		box.add_child(top)
		_image = RewardDialog.texture_icon(Monmap.texture(monster._name, IMAGE_SIZE, true)) as TextureRect
		_image.material = Monmap.LIVING_MATERIAL
		_image.custom_minimum_size = Vector2(IMAGE_SIZE, IMAGE_SIZE)
		_image.pivot_offset = Vector2(IMAGE_SIZE / 2, IMAGE_SIZE)
		top.add_child(_image)
		var mon_text := VBoxContainer.new()
		mon_text.alignment = BoxContainer.ALIGNMENT_CENTER
		mon_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mon_text.add_theme_constant_override("separation", 6)
		top.add_child(mon_text)
		var name_label := Label.new()
		name_label.text = Helper.mon_display_name(monster._name)
		name_label.add_theme_font_override("font", PIXEL_FONT)
		name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
		name_label.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
		mon_text.add_child(name_label)
		_chips = HBoxContainer.new()
		_chips.add_theme_constant_override("separation", 4)
		mon_text.add_child(_chips)

		var stats := HBoxContainer.new()
		stats.add_theme_constant_override("separation", 0)
		box.add_child(stats)
		for stat in GemField.STATS:
			var column := VBoxContainer.new()
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			column.add_theme_constant_override("separation", -4)
			stats.add_child(column)
			var stat_name := _stat_label(column)
			stat_name.text = tr(GemField.STATS[stat].stat).trim_suffix(":")
			_stat_labels[stat] = {"name": stat_name, "value": _stat_label(column)}

		RewardDialog.ignore_mouse_below(self)
		show_preview({})

	func _stat_label(parent: Control) -> Label:
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", PIXEL_FONT)
		label.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
		parent.add_child(label)
		return label

	func covers(global_point: Vector2) -> bool:
		return get_global_rect().has_point(global_point)

	## Aktueller Stand; drag (Ware in der Hand oder angeklickt) zeigt dazu, was sich ändern würde
	func show_preview(drag: Dictionary) -> void:
		RewardDialog.show_element_preview(_chips, mon, drag)
		for stat in _stat_labels:
			var labels: Dictionary = _stat_labels[stat]
			var value: int = roundi(mon.call(STAT_GETTERS[stat]))
			var boosted: bool = drag.get("stat", "") == stat
			labels.value.text = str(value)
			if boosted:
				labels.value.text += " %s %d" % [RewardDialog.PREVIEW_ARROW, value + drag.bonus]
			var color: Color = GOLD if boosted else IronPlate.TEXT_COLOR
			labels.name.add_theme_color_override("font_color", color)
			labels.value.add_theme_color_override("font_color", color)

	## Hat gerade etwas bekommen: kurz golden aufleuchten und wachsen
	func celebrate() -> void:
		_image.material = Monmap.living_selected_material
		if _pop:
			_pop.kill()
		_pop = create_tween()
		_pop.tween_property(_image, "scale", Vector2(1.08, 1.08), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_pop.tween_property(_image, "scale", Vector2.ONE, 0.2)
		_pop.tween_interval(0.5)
		_pop.tween_callback(func(): _image.material = Monmap.LIVING_MATERIAL)

## Offene Tasche in der Mitte, auf der Plakette steht das Geld. Ablegeziel für Relikte und Schlüssel.
class ShopBag extends RewardDialog.DropTarget:
	const BAG_SIZE := Vector2(208, 196)
	const FONT_SIZE := 19

	var money: Label
	var _art: OpenBag
	var _pop: Tween

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

	## Golden, solange Ware für die Tasche gezogen wird oder angeklickt ist
	func set_gold(gold: bool) -> void:
		_art.set_gold(gold)

	func celebrate() -> void:
		if _pop:
			_pop.kill()
		scale = Vector2(1.15, 0.85)
		_pop = create_tween()
		_pop.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Beschreibung der angeklickten Ware, fliegt von ihrer Seite her oben in der Mitte ein
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
var _item_layer: Control
var _shelves: Array[Dictionary] = []
## Regal, auf dem die nächste Ware landet
var _filling_shelf := 0
var _mon_fields: Array[MonField] = []
var _bag: ShopBag
var _bubble: SpeechBubble
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
	add_coupons(_stage, checkout_image)
	_explain()

## Freie Bühne statt der Standard-Spalten: alles wird in _layout_stage platziert.
## Die Ware liegt über den Monstern, damit sich nichts verdecken lässt, was man anklicken will.
func _build_stage() -> void:
	_stage = Control.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.resized.connect(_layout_stage)
	_content.add_child(_stage)
	_panel.gui_input.connect(_on_floor_input)

	checkout_image.reparent(_stage, false)
	for layout: Dictionary in SHELF_LAYOUT:
		var shelf := TextureRect.new()
		shelf.texture = SHELF_TEXTURE
		shelf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shelf.stretch_mode = TextureRect.STRETCH_SCALE
		shelf.material = PROPS_MATERIAL
		shelf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(shelf)
		_shelves.append({"layout": layout, "image": shelf, "items": []})
	for i in mini(State.mons.size(), 2):
		var field := MonField.new(self, State.mons[i])
		_stage.add_child(field)
		_mon_fields.append(field)
	_item_layer = Control.new()
	_item_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_item_layer)
	_bag = ShopBag.new(self)
	_stage.add_child(_bag)
	_bubble = SpeechBubble.new(BUBBLE_WIDTH, true, true)
	_stage.add_child(_bubble)
	_popup = ItemPopup.new(_set_selected.bind(null))
	_stage.add_child(_popup)
	_exit_button = icon_button(EXIT_ICON)
	_exit_button.tooltip_text = tr("SHOP_FINISH")
	_exit_button.pressed.connect(close)
	_stage.add_child(_exit_button)

func _layout_stage() -> void:
	var area := _stage.size
	var center_x := area.x / 2
	var checkout_height := (CHECKOUT_LAST_Y - CHECKOUT_FIRST_Y) / (CHECKOUT_BOTTOM - CHECKOUT_TOP)
	var texture_size := checkout_image.texture.get_size()
	checkout_image.size = texture_size * checkout_height / texture_size.y
	_checkout_y = CHECKOUT_FIRST_Y - CHECKOUT_TOP * checkout_height
	checkout_image.position = Vector2(center_x - checkout_image.size.x / 2, _checkout_y)
	checkout_image.pivot_offset = Vector2(checkout_image.size.x / 2, CHECKOUT_BOTTOM * checkout_image.size.y)
	for shelf in _shelves:
		_layout_shelf(shelf, center_x)
	# von unten gestapelt: ein einzelnes Monster bleibt gleich groß und steht ganz unten
	var field_bottom := area.y + STAGE_MARGIN - FIELD_SCREEN_GAP
	for i in _mon_fields.size():
		var row := _mon_fields.size() - i
		_mon_fields[i].position = Vector2(FIELD_SCREEN_GAP - STAGE_MARGIN, field_bottom - row * MonField.FIELD_SIZE.y - (row - 1) * FIELD_SPACING)
	_bag.position = Vector2(center_x - ShopBag.BAG_SIZE.x / 2, area.y + BAG_OVERHANG - ShopBag.BAG_SIZE.y)
	_bubble.position = Vector2(center_x + BUBBLE_LEFT + SpeechBubble.TAIL_SIZE.x, BUBBLE_TOP)
	_exit_button.position = Vector2(area.x - ICON_BUTTON_SIZE.x, 0)
	_coupon_stack.reset_size()
	_coupon_stack.position = Vector2(_bag.position.x + ShopBag.BAG_SIZE.x + COUPON_GAP, area.y + STAGE_MARGIN - COUPON_BOTTOM - _coupon_stack.size.y)
	# nur der Körper der Kasse zwischen den Regalen, die Tasche und der Stapel selbst bleiben frei
	_coupon_target.position = Vector2(center_x - SHELF_INNER_GAP, CHECKOUT_FIRST_Y)
	_coupon_target.size = Vector2(2 * SHELF_INNER_GAP, _bag.position.y - CHECKOUT_FIRST_Y)

## Brett neben die Kasse setzen, die Ware gleichmäßig darauf verteilen
func _layout_shelf(shelf: Dictionary, center_x: float) -> void:
	var layout: Dictionary = shelf.layout
	var side: float = layout.side
	var width: float = layout.width
	var left: float = center_x + SHELF_INNER_GAP if side > 0 else center_x - SHELF_INNER_GAP - width
	var image: TextureRect = shelf.image
	image.size = Vector2(width, SHELF_HEIGHT)
	image.position = Vector2(left, layout.y)
	var count: int = shelf.items.size()
	var tag_width := minf(width / maxi(count, 1) - 10.0, MAX_TAG_WIDTH)
	for i in count:
		var center := Vector2(left + width * (i + 0.5) / count, layout.y)
		shelf.items[i].place_on_shelf(center, tag_width)

func _fill_shelves() -> void:
	var elements: Array = Treasure.ELEMENTS
	for i in elements.size():
		_filling_shelf = SHELF_POTIONS_LEFT if i < elements.size() / 2 else SHELF_POTIONS_RIGHT
		set_price(Treasure.add_potion_card(self, elements[i]), ELEMENT_PRICE, true)
	_filling_shelf = SHELF_GEMS
	_add_gem_offers()
	_filling_shelf = SHELF_RELICS
	_add_relic_offers()
	_add_key_offer()
	# die Bühne kennt ihre Größe erst nach dem ersten Layout
	await get_tree().process_frame
	_layout_stage()

func _depth() -> int:
	return clampi(State.map_level, 0, GEM_PRICES.size() - 1)

func _add_gem_offers() -> void:
	var bonus: int = GemField.BONUS_BY_DEPTH[_depth()]
	var stats = GemField.STATS.keys()
	stats.shuffle()
	for stat in stats.slice(0, GEM_OFFERS):
		var card: ShelfItem = GemField.add_gem_card(self, stat, bonus)
		set_price(card, GEM_PRICES[_depth()])

func _add_relic_offers() -> void:
	var unowned = Relics.get_unowned()
	unowned.shuffle()
	for id in unowned.slice(0, RELIC_OFFERS):
		set_price(RelicReward.add_relic_card(self, id), RELIC_PRICES[_depth()])

func _add_key_offer() -> void:
	var take := func(): State.keys += 1
	set_price(add_bag_card(tr("KEY_NAME"), tr("KEY_DESC"), texture_icon(KEY_ICON), take), KEY_PRICE)

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

func _toggle_item(item: ShelfItem) -> void:
	if not item.sold:
		_set_selected(null if item == _selected else item)

func _set_selected(item: ShelfItem) -> void:
	if _selected:
		_selected.set_gold(false)
	_selected = item
	if item:
		item.set_gold(true)
		_popup.show_item(item, _stage.size.x / 2, POPUP_TOP)
	else:
		_popup.visible = false
	_update_previews()

## Klick ins Leere legt die angeklickte Ware zurück
func _on_floor_input(event: InputEvent) -> void:
	if _selected and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_set_selected(null)

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
	_bag.set_gold(into_bag)

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

## Ziel unter der gezogenen Ware hervorheben; was sich ändert, zeigen die Monster selbst
func _process(_delta: float) -> void:
	if _dragged == null:
		return
	var mouse := get_global_mouse_position()
	for target in _drop_targets():
		if target.locked:
			target.modulate = LOCKED_COLOR
		else:
			target.modulate = HOVER_COLOR if target.covers(mouse) else Color.WHITE
