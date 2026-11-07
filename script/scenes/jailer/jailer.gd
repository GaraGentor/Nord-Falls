extends RewardDialog

## Kerkermeister: rechts steht er selbst, davor bis zu drei Monster-Arten in Vogelkäfigen, angekettet.
## Jede Kette ist eine fehlende Verbesserung (+1 Aktion pro Zug). Erst stellt er die Gefangenen vor
## (Klick springt zum nächsten Satz). Danach zieht man eine Boss Träne aus der Tasche oben links
## zu ihm und wählt den Käfig. Ist die letzte Kette weg, verschwindet der Käfig samt Platz; die anderen
## rücken nicht nach, die Lücke bleibt bis zum Neuwürfeln (oben rechts, kostet ME).

const CHAIN_TEXTURE = preload("res://assets/ui/jailer/chain.svg")
const CHAIN_BROKEN_TEXTURE = preload("res://assets/ui/jailer/chain_broken.svg")
const CAGE_BACK_TEXTURE = preload("res://assets/ui/jailer/birdcage_back.svg")
const CAGE_FRONT_TEXTURE = preload("res://assets/ui/jailer/birdcage_front.svg")
const PEDESTAL_TEXTURE = preload("res://assets/ui/jailer/pedestal.svg")
const SHARD_TEXTURE = preload("res://assets/ui/jailer/boss_tear.svg")
const REROLL_TEXTURE = preload("res://assets/ui/jailer/icon_reroll.svg")
const EXIT_TEXTURE = preload("res://assets/ui/jailer/icon_exit.svg")
## Pixel-Look für Käfig, Beutel, Kristalle, Podest und Buttons, passend zum Hintergrund
const PROPS_MATERIAL = preload("res://script/scenes/jailer/jailer_props_material.tres")
const PIXEL_FONT = preload("res://script/ui/fonts/pxelfont/PixelifySans-VariableFont_wght.ttf")
const MON_OFFERS := 3
const REROLL_COST := 25
## Fundorte, je als Ansage (JAILER_PLACE_0 ...) und als Name auf dem Schild (JAILER_ORIGIN_0 ...)
const PLACE_COUNT := 5
## Aktionen pro Zug ohne Verbesserung (Monster._initial_moves)
const BASE_MOVES := Monster.BASE_MOVES
const GOLD := Color(0.858824, 0.717647, 0.45098)
const TOO_EXPENSIVE_COLOR := Color(0.95, 0.38, 0.3)

## Bildausschnitt des Kerkermeisters, Anteile der Bildgröße: links und rechts der Figur, linker Rand des Gesichts
const FIGURE_LEFT := 0.14
const FIGURE_RIGHT := 0.87
const FACE_LEFT := 0.3
## Oberkante der Figur (darüber liegen die Buttons) und um wie viel Figur und Käfige in den Rand ragen
const JAILER_TOP := 76.0
const EDGE_MARGIN := 24.0
const CAGES_TOP := 130.0
const CAGES_GAP := 12.0
const BUBBLE_WIDTH := 470.0
const BUBBLE_TOP := 40.0
const BUBBLE_TAIL := 18.0
const SHARD_DRAG_SIZE := Vector2(64, 96)
## Vorstellung: Anzeigedauer pro Satz
const INTRO_BASE_SECONDS := 2.2
const INTRO_SECONDS_PER_CHAR := 0.035

## Offene Tasche: Rückwand, Boss Tränen, Vorderseite mit der Anzahl. Aus ihr zieht man eine Träne.
class ShardBag extends RewardDialog.RewardCard:
	const BAG_SIZE := Vector2(150, 142)
	const SHARD_SIZE := Vector2(40, 60)
	const FONT_SIZE := 22

	var _bag: OpenBag

	func _init() -> void:
		custom_minimum_size = BAG_SIZE
		size = BAG_SIZE
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(holder)
		_bag = OpenBag.new(BAG_SIZE, SHARD_TEXTURE, SHARD_SIZE, FONT_SIZE)
		holder.add_child(_bag)

	func show_count(count: int) -> void:
		_bag.label.text = str(count)
		_bag.show_items(count)

## Ein Kettenstück, gesprengte Ketten sind offen und rostig
class ChainLink extends TextureRect:
	var broken := false:
		set(value):
			broken = value
			texture = CHAIN_BROKEN_TEXTURE if broken else CHAIN_TEXTURE

	func _init() -> void:
		texture = CHAIN_TEXTURE
		expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		custom_minimum_size = Vector2(68, 40)
		mouse_filter = MOUSE_FILTER_IGNORE
		material = PROPS_MATERIAL

## Platz einer Monster-Art: Vogelkäfig mit Monster und Ketten, darunter das Schild, ganz unten das Podest
class CageSlot extends VBoxContainer:
	const CAGE_SIZE := Vector2(280, 320)
	## im Käfigbild: Standfläche des Monsters, Mitte des Sockelrings, Monstergröße
	const FLOOR_Y := 268.0
	const BAND_Y := 296.0
	const MON_SIZE := 205.0
	const PEDESTAL_HEIGHT := 44.0
	const SIGN_FONT_SIZE := 18
	const SIGN_TITLE_SIZE := 24
	const SIGN_MARGIN_X := 11
	const SIGN_MARGIN_Y := 10
	const REVEAL_SECONDS := 0.8

	var jailer: Node
	var mon_name: String
	## alle Ketten gesprengt: der Platz bleibt leer stehen
	var freed := false
	var _cage: Control
	var _back: TextureRect
	var _monster: TextureRect
	var _front: TextureRect
	var _chains: HBoxContainer
	var _sign: IronPlate
	var _sign_plate: Control
	var _cost_label: Label
	var _effect_label: Label

	func _init(owner_dialog: Node, species: String, origin: String) -> void:
		jailer = owner_dialog
		mon_name = species
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_theme_constant_override("separation", 0)
		mouse_filter = Control.MOUSE_FILTER_STOP

		# freies Control, damit die Animationen nicht vom Container überschrieben werden
		_cage = Control.new()
		_cage.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_cage.resized.connect(_layout_cage)
		add_child(_cage)
		_back = RewardDialog.texture_icon(CAGE_BACK_TEXTURE) as TextureRect
		_back.material = PROPS_MATERIAL
		_cage.add_child(_back)
		_monster = RewardDialog.mon_icon(mon_name) as TextureRect
		_cage.add_child(_monster)
		_front = RewardDialog.texture_icon(CAGE_FRONT_TEXTURE) as TextureRect
		_front.material = PROPS_MATERIAL
		_cage.add_child(_front)
		_chains = HBoxContainer.new()
		_chains.add_theme_constant_override("separation", 4)
		_front.add_child(_chains)
		for i in jailer.max_level(mon_name):
			_chains.add_child(ChainLink.new())

		_sign_plate = _build_sign(origin)
		add_child(_sign_plate)
		# bis zur Vorstellung unsichtbar, aber per Alpha statt visible, damit das Layout schon steht
		_monster.modulate.a = 0.0
		_sign_plate.modulate.a = 0.0
		var pedestal := TextureRect.new()
		pedestal.texture = PEDESTAL_TEXTURE
		pedestal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pedestal.stretch_mode = TextureRect.STRETCH_SCALE
		pedestal.custom_minimum_size.y = PEDESTAL_HEIGHT
		pedestal.material = PROPS_MATERIAL
		add_child(pedestal)
		RewardDialog.ignore_mouse_below(self)
		refresh()
		set_glow(false)

	func _build_sign(origin: String) -> Control:
		var plate := PanelContainer.new()
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		_sign = IronPlate.frame(plate, box, SIGN_MARGIN_X, SIGN_MARGIN_Y)
		var title := _sign_label(box, Helper.mon_display_name(mon_name), SIGN_TITLE_SIZE)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_sign_label(box, tr("JAILER_ORIGIN").format({"place": origin}), SIGN_FONT_SIZE)
		_cost_label = _sign_label(box, "", SIGN_FONT_SIZE)
		_effect_label = _sign_label(box, "", SIGN_FONT_SIZE)
		return plate

	func _sign_label(parent: Control, text: String, font_size: int) -> Label:
		var label := Label.new()
		label.text = text
		# kein Umbruch: der würde vor dem ersten Layout die Mindesthöhe des ganzen Platzes aufblähen
		label.clip_text = true
		label.add_theme_font_override("font", PIXEL_FONT)
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
		parent.add_child(label)
		return label

	## Käfig steht unten auf dem Schild, das Monster auf dem Käfigboden, die Ketten am Sockelring
	func _layout_cage() -> void:
		var cage_scale := minf(_cage.size.x / CAGE_SIZE.x, _cage.size.y / CAGE_SIZE.y)
		var cage_size := CAGE_SIZE * cage_scale
		var origin := Vector2((_cage.size.x - cage_size.x) / 2, _cage.size.y - cage_size.y)
		for layer in [_back, _front]:
			layer.position = origin
			layer.size = cage_size
		var mon_size := MON_SIZE * cage_scale
		_monster.size = Vector2(mon_size, mon_size)
		_monster.pivot_offset = _monster.size / 2
		_monster.position = origin + Vector2(CAGE_SIZE.x / 2, FLOOR_Y) * cage_scale - Vector2(mon_size / 2, mon_size)
		_chains.size = _chains.get_combined_minimum_size()
		_chains.position = Vector2(cage_size.x / 2, BAND_Y * cage_scale) - _chains.size / 2
		_cage.pivot_offset = Vector2(_cage.size.x / 2, _cage.size.y)

	func refresh() -> void:
		var level: int = jailer.upgrade_level(mon_name)
		for i in _chains.get_child_count():
			_chains.get_child(i).broken = i < level
		# freigekommen: das Schild blendet mit dem alten Stand aus, eine nächste Stufe gibt es nicht
		if freed:
			return
		var moves: int = BASE_MOVES + level
		_cost_label.text = tr("JAILER_PRICE").format({"cost": jailer.tear_count_text(jailer.upgrade_cost(mon_name))})
		_cost_label.add_theme_color_override("font_color", IronPlate.TEXT_COLOR if jailer.affordable(mon_name) else TOO_EXPENSIVE_COLOR)
		_effect_label.text = tr("JAILER_EFFECT").format({"now": moves, "next": moves + 1})

	## Monster und Schild erscheinen, sobald der Kerkermeister sie vorstellt
	func reveal() -> void:
		var fade := create_tween().set_parallel()
		fade.tween_property(_monster, "modulate:a", 1.0, REVEAL_SECONDS)
		fade.tween_property(_sign_plate, "modulate:a", 1.0, REVEAL_SECONDS)

	## Hervorhebung beim Vorstellen und Auswählen: Umriss ums Monster, goldener Rand am Schild
	func set_glow(glowing: bool) -> void:
		_monster.material = Monmap.living_selected_material if glowing else Monmap.LIVING_MATERIAL
		_sign.set_rim(GOLD if glowing else IronPlate.RIM)

	## choosable: nach dem Abgeben der Träne anklickbar; locked: ausgegraut
	func set_choosable(choosable: bool, locked: bool) -> void:
		set_glow(choosable)
		modulate = RewardDialog.LOCKED_COLOR if locked else Color.WHITE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if choosable else Control.CURSOR_ARROW

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			jailer.cage_clicked(self)

	## Kette springt ab und der Käfig wackelt; bei der letzten Kette hebt er ab und der Platz wird frei
	func break_chain() -> void:
		freed = jailer.is_free(mon_name)
		var link: Control = _chains.get_child(jailer.upgrade_level(mon_name) - 1)
		link.pivot_offset = link.size / 2
		var pop := create_tween()
		pop.tween_property(link, "scale", Vector2(1.6, 1.6), 0.12)
		pop.tween_callback(refresh)
		pop.tween_property(link, "scale", Vector2.ONE, 0.15)
		var rattle := create_tween()
		for degrees in [3.0, -3.0, 2.0, -2.0, 0.0]:
			rattle.tween_property(_cage, "rotation_degrees", degrees, 0.06)
		if not freed:
			return
		set_choosable(false, false)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lift := -_cage.size.y
		rattle.tween_property(_back, "position:y", _back.position.y + lift, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		rattle.parallel().tween_property(_front, "position:y", _front.position.y + lift, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		rattle.parallel().tween_property(_back, "modulate:a", 0.0, 0.6)
		rattle.parallel().tween_property(_front, "modulate:a", 0.0, 0.6)
		rattle.tween_property(_monster, "scale", Vector2(1.2, 1.2), 0.2)
		rattle.tween_property(self, "modulate:a", 0.0, 0.4)

## Wellen-Hintergrund aus der Szene
@export var background: Control
## Bild des Kerkermeisters aus der Szene, dort lassen sich auch die Shader-Werte einstellen
@export var jailer_image: TextureRect

var _stage: Control
var _cages: HBoxContainer
var _slots: Array[CageSlot] = []
var _jailer_target: DropTarget
var _bubble: SpeechBubble
var _bag: ShardBag
var _reroll_button: Button
var _reroll_price: Label
var _exit_button: Button
var _cancel_button: Button
## Die Träne liegt beim Kerkermeister, man wählt gerade den Käfig
var _choosing := false
## noch offene Sätze der Vorstellung, je {text, slot}
var _intro: Array[Dictionary] = []
var _intro_running := false
var _intro_tween: Tween

func _ready() -> void:
	use_scene_layout(background)
	_title.visible = false
	_columns.visible = false
	_build_stage()
	State.boss_shards_changed.connect(_shards_changed)
	State.ep_changed.connect(_ep_changed)
	_refresh_bag()
	_ep_changed(State.ep)
	_roll_offers()

func _exit_tree() -> void:
	State.boss_shards_changed.disconnect(_shards_changed)
	State.ep_changed.disconnect(_ep_changed)

## Freie Bühne statt der Standard-Spalten: alles wird in _layout_stage platziert
func _build_stage() -> void:
	_stage = Control.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.resized.connect(_layout_stage)
	_content.add_child(_stage)

	_cages = HBoxContainer.new()
	_cages.add_theme_constant_override("separation", 14)
	_stage.add_child(_cages)
	jailer_image.reparent(_stage, false)

	_jailer_target = DropTarget.new()
	_jailer_target.dialog = self
	_jailer_target.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_stage.add_child(_jailer_target)

	_bag = ShardBag.new()
	_bag.dialog = self
	_bag.drag = {"title": tr("JAILER_SHARD"), "header": "", "bag": true, "on_drop": _bribe}
	_stage.add_child(_bag)

	_cancel_button = plate_button(tr("JAILER_CANCEL"))
	_cancel_button.position = Vector2(ShardBag.BAG_SIZE.x + 12, 20)
	_cancel_button.visible = false
	_cancel_button.pressed.connect(_cancel_choice)
	_stage.add_child(_cancel_button)

	_reroll_button = _icon_button(REROLL_TEXTURE)
	_reroll_button.pressed.connect(_reroll)
	_reroll_price = Label.new()
	_reroll_price.theme = LABEL_THEME
	_reroll_price.add_theme_font_size_override("font_size", 20)
	_reroll_price.text = Helper.me_text(REROLL_COST)
	_reroll_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reroll_price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reroll_price.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_reroll_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reroll_button.add_child(_reroll_price)
	_exit_button = _icon_button(EXIT_TEXTURE)
	_exit_button.tooltip_text = tr("JAILER_FINISH")
	_exit_button.pressed.connect(close)

	_bubble = SpeechBubble.new(BUBBLE_WIDTH, true)
	_stage.add_child(_bubble)

func _icon_button(texture: Texture2D) -> Button:
	var button := icon_button(texture)
	_stage.add_child(button)
	return button

func _layout_stage() -> void:
	var area := _stage.size
	var texture_size := jailer_image.texture.get_size()
	var image_size := texture_size * (area.y + EDGE_MARGIN - JAILER_TOP) / texture_size.y
	var origin := Vector2(area.x + EDGE_MARGIN - FIGURE_RIGHT * image_size.x, JAILER_TOP)
	jailer_image.position = origin
	jailer_image.size = image_size
	var figure_left := origin.x + FIGURE_LEFT * image_size.x
	_jailer_target.position = Vector2(figure_left, origin.y)
	_jailer_target.size = Vector2((FIGURE_RIGHT - FIGURE_LEFT) * image_size.x, image_size.y)
	_cages.position = Vector2(0, CAGES_TOP)
	_cages.size = Vector2(figure_left - CAGES_GAP, area.y + EDGE_MARGIN - CAGES_TOP)
	_bubble.position = Vector2(origin.x + FACE_LEFT * image_size.x - BUBBLE_WIDTH - BUBBLE_TAIL, BUBBLE_TOP)
	_exit_button.position = Vector2(area.x - ICON_BUTTON_SIZE.x, 0)
	_reroll_button.position = _exit_button.position - Vector2(ICON_BUTTON_SIZE.x + 12, 0)

static func upgrade_level(mon_name: String) -> int:
	return SaveManager.save_data.monsters.get(mon_name, {}).get("upgrade", 0)

static func max_level(mon_name: String) -> int:
	return Monmap.mon_metainfos_by_name(mon_name).max_upgrades

## "1 Boss Träne" bzw. "3 Boss Tränen"
static func tear_count_text(amount: int) -> String:
	var key := "JAILER_TEAR_COUNT_ONE" if amount == 1 else "JAILER_TEAR_COUNT_MANY"
	return TranslationServer.translate(key).format({"amount": amount})

static func upgrade_cost(mon_name: String) -> int:
	return upgrade_level(mon_name) * 2 + 1

static func is_free(mon_name: String) -> bool:
	return upgrade_level(mon_name) >= max_level(mon_name)

func affordable(mon_name: String) -> bool:
	return State.boss_shards >= upgrade_cost(mon_name)

func _chained(mon_name: String) -> bool:
	return not is_free(mon_name)

## Arten, die schon verbessert wurden, Start-Monster sind oder gefangen wurden und noch Ketten tragen
func _prisoners() -> Array:
	var pool: Array = SaveManager.save_data.monsters.keys()
	for mon_name in Helper.get_all_owned_monster_names():
		if not pool.has(mon_name):
			pool.append(mon_name)
	return pool.filter(_chained)

## Bis zu MON_OFFERS Arten, jede an einem anderen Fundort gefangen. Fehlt eine, bleibt ihr Platz leer.
func _roll_offers() -> void:
	var pool := _prisoners()
	pool.shuffle()
	var places := range(PLACE_COUNT)
	places.shuffle()
	for child in _cages.get_children():
		_cages.remove_child(child)
		child.queue_free()
	_slots.clear()
	var offers := pool.slice(0, MON_OFFERS)
	var lines: Array[Dictionary] = []
	for i in MON_OFFERS:
		if i >= offers.size():
			var gap := Control.new()
			gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_cages.add_child(gap)
			continue
		var slot := CageSlot.new(self, offers[i], tr("JAILER_ORIGIN_%d" % places[i]))
		_cages.add_child(slot)
		_slots.append(slot)
		lines.append({"slot": slot, "text": _intro_text(i, offers.size(), offers[i], tr("JAILER_PLACE_%d" % places[i]))})
	_update_slots()
	_start_intro(lines)

## Erster, mittlerer oder letzter Gefangener in der Vorstellung
func _intro_text(index: int, count: int, mon_name: String, place: String) -> String:
	var key := "JAILER_SAY_INTRO_FIRST" if index == 0 else ("JAILER_SAY_INTRO_LAST" if index == count - 1 else "JAILER_SAY_INTRO_NEXT")
	return tr(key).format({"mon": Helper.mon_display_name(mon_name), "place": place, "cost": tear_count_text(upgrade_cost(mon_name))})

func _update_slots() -> void:
	for slot in _slots:
		if slot.freed:
			continue
		var can_pick := affordable(slot.mon_name)
		slot.set_choosable(_choosing and can_pick, _choosing and not can_pick)
		slot.refresh()

func _start_intro(lines: Array[Dictionary]) -> void:
	_intro = lines
	_intro_running = true
	_next_intro_line()

## Nächster Satz, mit dem vorgestellten Käfig hervorgehoben; danach kommt die Erklärung
func _next_intro_line() -> void:
	if _intro_tween:
		_intro_tween.kill()
	_highlight_only(null)
	if _intro.is_empty():
		_intro_running = false
		# wurde die Vorstellung übersprungen, sind noch nicht alle zu sehen
		for slot in _slots:
			slot.reveal()
		_bubble.say(_explanation())
		return
	var line: Dictionary = _intro.pop_front()
	line.slot.reveal()
	_highlight_only(line.slot)
	_bubble.say(line.text)
	_intro_tween = create_tween()
	_intro_tween.tween_interval(INTRO_BASE_SECONDS + line.text.length() * INTRO_SECONDS_PER_CHAR)
	_intro_tween.tween_callback(_next_intro_line)

func _highlight_only(highlighted: CageSlot) -> void:
	for slot in _slots:
		if not slot.freed:
			slot.set_glow(slot == highlighted)

## Vorstellung sofort beenden, z. B. wenn schon eine Träne gezogen wird
func _end_intro() -> void:
	if not _intro_running:
		return
	_intro.clear()
	_next_intro_line()

## Was der Kerkermeister sagt, solange nichts läuft
func _explanation() -> String:
	if _slots.all(func(slot): return slot.freed):
		return tr("JAILER_SAY_EMPTY")
	if not _slots.any(func(slot): return not slot.freed and affordable(slot.mon_name)):
		return tr("JAILER_SAY_POOR")
	return tr("JAILER_SAY_HOWTO")

## Ein Klick überspringt den aktuellen Satz der Vorstellung, der Klick selbst wirkt normal weiter
func _input(event: InputEvent) -> void:
	if _intro_running and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_next_intro_line()

## Träne beim Kerkermeister abgelegt: jetzt den Käfig wählen
func _bribe() -> void:
	_set_choosing(true)
	_bubble.say(tr("JAILER_SAY_WHO"))

func cage_clicked(slot: CageSlot) -> void:
	if _intro_running:
		return
	if not _choosing:
		_bubble.say(_explanation())
		return
	var mon_name := slot.mon_name
	if not affordable(mon_name):
		_bubble.say(tr("JAILER_NOT_ENOUGH_SHARDS"))
		return
	var cost := upgrade_cost(mon_name)
	State.boss_shards -= cost
	SaveManager.subtract_boss_shard(cost)
	SaveManager.add_mon_upgrade(mon_name)
	Events.mon_upgraded.emit(mon_name)
	_choosing = false
	_cancel_button.visible = false
	slot.break_chain()
	_update_slots()
	_refresh_bag()
	var display_name := Helper.mon_display_name(mon_name)
	if slot.freed:
		_bubble.say(tr("JAILER_SAY_FREED").format({"mon": display_name}))
	else:
		_bubble.say(tr("JAILER_SAY_CHAIN").format({"mon": display_name, "moves": BASE_MOVES + upgrade_level(mon_name)}))

func _cancel_choice() -> void:
	_set_choosing(false)
	_bubble.say(tr("JAILER_SAY_CANCEL"))

func _set_choosing(choosing: bool) -> void:
	_choosing = choosing
	_cancel_button.visible = choosing
	_update_slots()
	_refresh_bag()

## Die gezogene oder abgegebene Träne fehlt in der Tasche
func _refresh_bag() -> void:
	_bag.show_count(State.boss_shards - (1 if _dragged != null or _choosing else 0))

## Die Tasche bleibt beim Ziehen sichtbar, nur eine Träne wandert heraus
func _show_targets(card: RewardCard) -> void:
	super(card)
	card.modulate.a = 1.0
	_end_intro()
	_refresh_bag()

func _hide_targets() -> void:
	super()
	if _bag:
		_refresh_bag()

## Am Mauszeiger hängt die Träne selbst
func _make_drag_preview(_card: RewardCard) -> Control:
	var shard := texture_icon(SHARD_TEXTURE)
	shard.material = PROPS_MATERIAL
	shard.size = SHARD_DRAG_SIZE
	shard.position = -SHARD_DRAG_SIZE / 2
	var holder := Control.new()
	holder.add_child(shard)
	return holder

## Der Dialog bleibt nach einer Wahl offen
func _taken(_card: RewardCard) -> void:
	pass

## Ziel ist immer der Kerkermeister selbst
func _build_targets(_card: RewardCard) -> void:
	pass

func _drop_targets() -> Array:
	return [_jailer_target]

func _drag_blocked(_card: RewardCard) -> String:
	if _choosing:
		return tr("JAILER_SAY_WHO")
	var explanation := _explanation()
	return "" if explanation == tr("JAILER_SAY_HOWTO") else explanation

func _show_blocked(reason: String) -> void:
	_end_intro()
	_bubble.say(reason)

func _process(delta: float) -> void:
	super(delta)
	var over := _dragged != null and _jailer_target.get_global_rect().has_point(get_global_mouse_position())
	jailer_image.modulate = HOVER_COLOR if over else Color.WHITE

func _reroll() -> void:
	if State.ep < REROLL_COST:
		return
	if _prisoners().is_empty():
		_end_intro()
		_bubble.say(tr("JAILER_SAY_EMPTY"))
		return
	State.ep -= REROLL_COST
	_set_choosing(false)
	_roll_offers()

func _shards_changed(_shards: int) -> void:
	_refresh_bag()
	_update_slots()

func _ep_changed(ep: int) -> void:
	_reroll_button.tooltip_text = tr("JAILER_REROLL").format({"cost": REROLL_COST, "money": ep})
	_reroll_button.disabled = ep < REROLL_COST
	_reroll_price.modulate = LOCKED_COLOR if _reroll_button.disabled else Color.WHITE
