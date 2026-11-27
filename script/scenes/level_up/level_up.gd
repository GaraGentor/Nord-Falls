extends Control

## Nach dem Kampf: links die Monster untereinander mit ihrem Level-Up, rechts das Schlachtfeld mit der Tasche
## und der zufällig verstreuten Beute. Beute gibt es nur, wenn man sie in die Tasche zieht; was liegen bleibt, ist beim Weitergehen weg.

const ESSENCE_ICON = preload("res://assets/ui/icons/monster_essence.svg")
const KEY_ICON = preload("res://assets/ui/icons/key.svg")
const BOX_ICON = preload("res://assets/ui/rewards/box.png")
const ENVELOPE_ICON = preload("res://assets/ui/rewards/envelop.png")
const GEM_BAG_ICON = preload("res://assets/ui/rewards/bag.png")
const COUPON_ICON = preload("res://assets/ui/icons/coupon.svg")
const BOSS_SHARD_ICON = preload("res://assets/ui/jailer/boss_tear.svg")
const EGG_ICON = preload("res://assets/ui/eggs/common_1.png")
const BAG_SIZE := Vector2(208, 196)
const BAG_FONT_SIZE := 32
const FIELD_MARGIN := 16
## so weit bleibt die Beute vom Bildrand weg, dort liegt der Wolkenrand
const LOOT_EDGE_MARGIN := 60.0
## Abstand der Beute untereinander
const LOOT_GAP := 16.0

## Stück Beute auf dem Schlachtfeld, lässt sich in die Tasche ziehen
class LootIcon extends VBoxContainer:
	const ICON_SIZE := Vector2(84, 84)
	const FONT_SIZE := 32

	signal drag_started

	## wird beim Ablegen in der Tasche aufgerufen
	var on_taken: Callable
	var _art: TextureRect

	func _init(texture: Texture2D, text: String, base_material: ShaderMaterial) -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		# die Mitte sitzt auf dem Ankerpunkt, den _scatter_loot setzt
		grow_horizontal = Control.GROW_DIRECTION_BOTH
		grow_vertical = Control.GROW_DIRECTION_BOTH
		_art = RewardDialog.texture_icon(texture) as TextureRect
		_art.custom_minimum_size = ICON_SIZE
		var art_material: ShaderMaterial = base_material.duplicate()
		art_material.set_shader_parameter("outline_color", SkillDetailPopup.GOLD)
		_art.material = art_material
		add_child(_art)
		var label := Label.new()
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 6)
		add_child(label)
		RewardDialog.ignore_mouse_below(self)

	func _get_drag_data(_at_position: Vector2):
		var art: Control = _art.duplicate(0)
		art.size = ICON_SIZE
		art.position = -ICON_SIZE / 2
		var holder := Control.new()
		holder.add_child(art)
		set_drag_preview(holder)
		modulate.a = 0.4
		drag_started.emit()
		return self

## Tasche auf dem Schlachtfeld, Ablegeziel für die Beute. Auf der Plakette steht das Geld.
class LootBag extends Control:
	var art: OpenBag
	var _pop: Tween

	func _init() -> void:
		custom_minimum_size = BAG_SIZE
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
		pivot_offset = Vector2(BAG_SIZE.x / 2, BAG_SIZE.y)
		art = OpenBag.new(BAG_SIZE, null, Vector2.ZERO, BAG_FONT_SIZE)
		add_child(art)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is LootIcon

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		data.on_taken.call()
		if _pop:
			_pop.kill()
		scale = Vector2(1.15, 0.85)
		_pop = create_tween()
		_pop.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Boden des Schlachtfelds: fallen gelassene Beute bleibt dort liegen, wo sie losgelassen wird (frei verschiebbar,
## auch übereinander). Liegt die Tasche unter dem Mauszeiger, landet sie dort. Nimmt nur während des Ziehens Mausereignisse an.
class LootField extends Control:
	var bag: LootBag

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is LootIcon

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		if bag.get_global_rect().has_point(get_global_mouse_position()):
			bag._drop_data(Vector2.ZERO, data)
			return
		var loot: LootIcon = data
		var half := loot.size / 2
		var center := at_position.clamp(half, (size - half).max(half))
		# zuletzt abgelegt liegt obenauf
		move_child(loot, -1)
		for side in [SIDE_LEFT, SIDE_RIGHT]:
			loot.set_anchor_and_offset(side, center.x / size.x, 0.0, true)
		for side in [SIDE_TOP, SIDE_BOTTOM]:
			loot.set_anchor_and_offset(side, center.y / size.y, 0.0, true)

var debug=false
var debug_mons=2

@export var monster_scene1: Control
@export var monster_scene2: Control
## hält bei nur einem Monster den Platz des zweiten frei, damit die Karte nur die halbe Höhe nimmt
@export var empty_slot: Control

@export var go_button: Button
## Bild des Schlachtfelds aus der Szene, darauf liegen Tasche und Beute
@export var battlefield: Control
@export var battlefield_image: TextureRect

var _bag: LootBag
var _hint_panel: PanelContainer
## freie Fläche über dem ganzen Bild, darauf liegt die Beute verstreut
var _loot_field: LootField

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#if State.killed_monsters == 0:
	#	get_tree().change_scene_to_file("res://script/scenes/world_map/world_map.tscn")
	#	return
	if debug:
		for dm in debug_mons:
			var mon:Monster = Helper.generate_mons({"count": 1, "level": randi_range(10,30)})[0]
			mon._level_progress = randi_range(0,1)
			State.mons.append(mon)
			State.killed_monsters = 5
	monster_scene1.init_with_mon(State.mons[0])
	if State.mons.size() == 2:
		monster_scene2.init_with_mon(State.mons[1])
		monster_scene2.visible = true
	empty_slot.visible = not monster_scene2.visible
	battlefield_image.resized.connect(_update_cloud_size)
	_update_cloud_size()
	_build_battlefield()
	monster_scene1.add_to_group("tut_loot_team")
	monster_scene2.add_to_group("tut_loot_team")
	battlefield.add_to_group("tut_loot_field")
	# die Sequenz erklärt vor allem die Beute, ohne Beute wartet sie auf den nächsten Kampf
	if _loot_field.get_child_count() > 0:
		Tutorial.trigger("boss_loot" if State.is_boss_fight and Tutorial.run_active else "loot")
	_start()

## Der Wolkenrand rechnet in Pixeln und braucht dafür die Größe des Bildes
func _update_cloud_size() -> void:
	battlefield_image.material.set_shader_parameter("rect_size", battlefield_image.size)

## Beide Monster spielen ihre Level-Ups gleichzeitig ab. Weiter geht es jederzeit:
## der OK-Knopf verbucht, was noch nicht animiert wurde (_on_button_pressed).
func _start() -> void:
	var kills := State.killed_monsters
	var boss_kills := State.killed_bosses
	State.killed_monsters = 0
	State.killed_bosses = 0
	go_button.disabled = false
	for scene in _monster_scenes():
		scene.play_kills(kills, boss_kills)

func _monster_scenes() -> Array:
	return [monster_scene1, monster_scene2].filter(func(scene): return scene.mon != null)

## Oben der Hinweis, unten die Tasche, darüber die verstreute Beute
func _build_battlefield() -> void:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, FIELD_MARGIN)
	battlefield.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	_hint_panel = PanelContainer.new()
	_hint_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint := Label.new()
	hint.text = tr("LEVEL_UP_LOOT_HINT")
	hint.add_theme_font_size_override("font_size", 24)
	hint.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	IronPlate.frame(_hint_panel, hint, 12, 8)
	column.add_child(_hint_panel)

	_loot_field = LootField.new()
	_loot_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loot_field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battlefield.add_child(_loot_field)

	_bag = LootBag.new()
	column.add_child(_bag)
	_loot_field.bag = _bag
	State.ep_changed.connect(_show_money)
	_show_money(State.ep)

	if State.pending_ep > 0:
		_add_loot(ESSENCE_ICON, Helper.me_text(State.pending_ep), _take_essence)
	if State.pending_keys > 0:
		_add_loot(KEY_ICON, tr("KEY_LOOT_AMOUNT").format({"amount": State.pending_keys}), _take_keys)
	if State.pending_gems > 0:
		_add_loot(GEM_BAG_ICON, tr("GEM_LOOT_AMOUNT").format({"amount": State.pending_gems}), _take_gems)
	if State.pending_coupons > 0:
		_add_loot(COUPON_ICON, tr("COUPON_LOOT_AMOUNT").format({"amount": State.pending_coupons}), _take_coupons)
	if State.pending_relic_chest:
		_add_loot(BOX_ICON, tr("RELIC_CHEST_LOOT"), _take_relic_chest).add_to_group("tut_loot_chest")
	if State.pending_skill_envelope:
		_add_loot(ENVELOPE_ICON, tr("SKILL_ENVELOPE_LOOT"), _take_skill_envelope).add_to_group("tut_loot_envelope")
	if State.pending_boss_shards > 0:
		var shard_text := "JAILER_TEAR_COUNT_ONE" if State.pending_boss_shards == 1 else "JAILER_TEAR_COUNT_MANY"
		_add_loot(BOSS_SHARD_ICON, "+" + tr(shard_text).format({"amount": State.pending_boss_shards}), _take_boss_shards)
	if State.is_boss_fight:
		_add_egg_loot()
	# One-Way-Items: Beute und die Items gefallener Monster, jedes einzeln
	for item in State.pending_items.duplicate():
		_add_item_loot(item)
	_hint_panel.visible = _loot_field.get_child_count() > 0
	_scatter_loot()

## Ei eines Team-Monsters, das noch nicht freigeschaltet ist. Gelost wird erst hier, damit Fänge aus dem Judgement dabei sind.
## Die Art steht schon fest, damit das Ei nach ihrer Seltenheit eingefärbt werden kann.
func _add_egg_loot() -> void:
	var unlocked: Array = SaveManager.save_data.catched_monsters.duplicate()
	unlocked.append_array(State.INITIAL_MONS)
	# ein gerade gefangener Boss bringt nicht direkt sein eigenes Ei, das fühlt sich geschenkt an
	var missing := State.mons.filter(func(mon: Monster): return not unlocked.has(mon._name) and not mon._is_boss)
	# Tutorial: immer ein Ei, es erklärt nur das Freischalten (der Spielstand kommt am Ende zurück)
	if missing.is_empty() and Tutorial.run_active:
		missing = State.mons.duplicate()
	# ab jetzt zählt er als normales Team-Monster: sein Ei kann ein späterer Boss-Kampf bringen
	for mon: Monster in State.mons:
		mon._is_boss = false
	if missing.is_empty():
		return
	var mon_name: String = missing.pick_random()._name
	var loot := _add_loot(EGG_ICON, tr("EGG_LOOT"), SaveManager.add_catched_monster_mon.bind(mon_name), Monmap.egg_material(Monmap.rarity_of(mon_name)))
	loot.tooltip_text = tr("EGG_LOOT_DESC")
	loot.add_to_group("tut_loot_egg")

## One-Way-Item in der Farbe seiner Seltenheit, in die Tasche gezogen landet es im Inventar
func _add_item_loot(item: Dictionary) -> void:
	var art := Items.icon(item)
	var loot := _add_loot(art.texture, Items.title(item), _take_item.bind(item), art.material)
	loot.tooltip_text = "%s (%s)\n%s\n%s" % [Items.title(item), tr(Items.RARITY_LABELS[Items.rarity_of(item)]), Items.description(item), Items.use_hint(item)]
	art.free()

func _take_item(item: Dictionary) -> void:
	State.pending_items.erase(item)
	Items.add_to_bag(item)

func _add_loot(texture: Texture2D, text: String, on_taken: Callable, art_material: ShaderMaterial = RewardDialog.ICON_BUTTON_MATERIAL) -> LootIcon:
	var loot := LootIcon.new(texture, text, art_material)
	loot.on_taken = func():
		on_taken.call()
		_loot_field.remove_child(loot)
		loot.queue_free()
		_hint_panel.visible = _loot_field.get_child_count() > 0
	loot.drag_started.connect(_on_loot_drag_started)
	_loot_field.add_child(loot)
	return loot

## Während des Ziehens fängt keine Beute den Drop ab, auch wenn sie über der Tasche liegt: der Boden nimmt ihn an
func _on_loot_drag_started() -> void:
	_bag.art.set_gold(true)
	_loot_field.mouse_filter = Control.MOUSE_FILTER_STOP
	for loot: Control in _loot_field.get_children():
		loot.mouse_filter = Control.MOUSE_FILTER_IGNORE

## Verteilt die Beute zufällig auf dem Bild, frei von Hinweis, Tasche und anderer Beute.
## Bis dahin unsichtbar, denn deren Größen stehen erst nach dem ersten Layout fest.
func _scatter_loot() -> void:
	_loot_field.modulate.a = 0.0
	# erst nach dem zweiten Frame stehen Hinweis und Tasche an ihrem endgültigen Platz
	await get_tree().process_frame
	await get_tree().process_frame
	var area := Rect2(Vector2.ZERO, _loot_field.size).grow(-LOOT_EDGE_MARGIN)
	var bag_rect := _local_rect(_bag).grow(LOOT_GAP)
	var hint_rect := _local_rect(_hint_panel).grow(LOOT_GAP)
	var placed: Array[Rect2] = []
	var icons := _loot_field.get_children()
	icons.shuffle()
	for loot: LootIcon in icons:
		var rect := _pick_loot_rect(area, loot.get_combined_minimum_size(), placed, bag_rect, hint_rect)
		placed.append(rect)
		# Anteil statt Pixel: bleibt passend, wenn sich die Fläche ändert
		var center := rect.get_center() / _loot_field.size
		for side in [SIDE_LEFT, SIDE_RIGHT]:
			loot.set_anchor_and_offset(side, center.x, 0.0, true)
		for side in [SIDE_TOP, SIDE_BOTTOM]:
			loot.set_anchor_and_offset(side, center.y, 0.0, true)
	_loot_field.modulate.a = 1.0

## Rechteck eines Controls in Koordinaten der Beutefläche
func _local_rect(control: Control) -> Rect2:
	return Rect2(control.global_position - _loot_field.global_position, control.size)

## Best-Candidate-Verfahren: viele zufällige Plätze probieren, der mit dem größten Abstand zur schon
## liegenden Beute gewinnt. Das streut gleichmäßig, ohne nach Raster auszusehen. Auf der Tasche landet nie
## etwas (dann ginge nichts mehr hinein); Überlappen mit Hinweis oder anderer Beute wird nur bestraft.
func _pick_loot_rect(area: Rect2, loot_size: Vector2, placed: Array[Rect2], bag_rect: Rect2, hint_rect: Rect2) -> Rect2:
	const CANDIDATES := 60
	var span := (area.size - loot_size).max(Vector2.ZERO)
	var best := Rect2()
	var best_score := -INF
	for i in CANDIDATES:
		var pos := area.position + Vector2(randf() * span.x, randf() * span.y)
		var rect := Rect2(pos, loot_size)
		if rect.intersects(bag_rect):
			continue
		var score := _loot_spacing(rect, placed)
		if rect.intersects(hint_rect):
			score -= 10000.0
		if score > best_score:
			best_score = score
			best = rect
	if best_score == -INF:
		# kein freier Platz neben der Tasche gefunden: links oder rechts daneben
		var x := bag_rect.position.x - loot_size.x if bag_rect.position.x - loot_size.x >= area.position.x else bag_rect.end.x
		best = Rect2(Vector2(x, bag_rect.get_center().y - loot_size.y / 2), loot_size)
	return best

## Abstand zur nächsten liegenden Beute (Rand zu Rand), Überlappen zählt negativ
func _loot_spacing(rect: Rect2, placed: Array[Rect2]) -> float:
	if placed.is_empty():
		return 0.0
	var nearest := INF
	for other in placed:
		var gap := Vector2(
			maxf(other.position.x - rect.end.x, rect.position.x - other.end.x),
			maxf(other.position.y - rect.end.y, rect.position.y - other.end.y))
		# beide negativ: Überlappung, je tiefer desto schlechter
		var distance := gap.length() if gap.x > 0 and gap.y > 0 else maxf(gap.x, gap.y)
		nearest = minf(nearest, distance)
	return nearest

func _take_essence() -> void:
	State.ep += State.pending_ep
	State.pending_ep = 0

func _take_keys() -> void:
	State.keys += State.pending_keys
	State.pending_keys = 0

func _take_coupons() -> void:
	State.coupons += State.pending_coupons
	State.pending_coupons = 0

## wie beim Kerkermeister auch im Spielstand
func _take_boss_shards() -> void:
	SaveManager.add_boss_shard(State.pending_boss_shards)
	State.boss_shards += State.pending_boss_shards
	State.pending_boss_shards = 0

## Edelsteine, Relic-Auswahl und Skill-Auswahl erscheinen beim nächsten Betreten der Karte (world_map.gd)
func _take_gems() -> void:
	State.pending_gem_rewards += State.pending_gems
	State.pending_gems = 0

func _take_relic_chest() -> void:
	State.pending_relic_chest = false
	State.pending_relic_reward = true

func _take_skill_envelope() -> void:
	State.pending_skill_envelope = false
	State.pending_skill_reward = true

func _show_money(ep: int) -> void:
	_bag.art.label.text = str(ep)

## Ablegen in der Tasche oder Fallenlassen woanders (dann bleibt die Beute liegen)
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _bag != null:
		_bag.art.set_gold(false)
		_loot_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for loot in _loot_field.get_children():
			loot.modulate.a = 1.0
			loot.mouse_filter = Control.MOUSE_FILTER_STOP

func _on_button_pressed() -> void:
	# noch laufende Level-Ups sofort verbuchen
	for scene in _monster_scenes():
		scene.finish_now()
	# Tutorial: Reliktkiste und Couvert gehen in jedem Fall auf
	if Tutorial.run_active:
		if State.pending_relic_chest:
			_take_relic_chest()
		if State.pending_skill_envelope:
			_take_skill_envelope()
	# was nicht in der Tasche liegt, bleibt auf dem Schlachtfeld
	State.clear_pending_loot()
	get_tree().change_scene_to_file("res://script/scenes/world_map/world_map.tscn")
