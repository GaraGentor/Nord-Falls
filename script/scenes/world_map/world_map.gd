extends Control

@export var scroll_container: ScrollContainer

@export var map_layout: ColorRect

@export var battle_c: TextureRect
@export var camp_c: ColorRect

# new logic
@export var grid_container: GridContainer
@export var boss_button: Button
@export var node_container: Panel
@export var node_name: Button
@export var line_node: UILine

@export var boss_shard_label: Label
@export var money_label: Label
@export var key_label: Label
@export var coupon_label: Label
@export var biome_trail: BiomeTrail
@export var team_bar: HBoxContainer

# Felder, Ereignisse und Dialoge holt sich die Karte erst, wenn sie gebraucht werden (load im Getter). Sie liegen
# schon seit dem Intro im Speicher (SceneLoader), so kostet die Karte selbst keine Ladezeit für sie.
var heal_camp_scene: PackedScene:
	get: return load("res://script/scenes/heal_camp/heal_camp.tscn")
var shop_scene: PackedScene:
	get: return load("res://script/scenes/shop/shop.tscn")
var jailer_scene: PackedScene:
	get: return load("res://script/scenes/jailer/jailer.tscn")
var trainer_scene: PackedScene:
	get: return load("res://script/scenes/trainer/trainer.tscn")
var treasure_scene: PackedScene:
	get: return load("res://script/scenes/treasure/treasure.tscn")
var RELIC_REWARD_SCENE: PackedScene:
	get: return load("res://script/scenes/relic_reward/relic_reward.tscn")
var GEM_SCENE: PackedScene:
	get: return load("res://script/scenes/gems/gems.tscn")
var SKILL_REWARD_SCENE: PackedScene:
	get: return load("res://script/scenes/skill_reward/skill_reward.tscn")
var WHEEL_EVENT: GDScript:
	get: return load("res://script/scenes/wheel_event/wheel_event.gd")
var VOID_EVENT: GDScript:
	get: return load("res://script/scenes/void_event/void_event.gd")
var CONFRONTATION_EVENT: GDScript:
	get: return load("res://script/scenes/confrontation_event/confrontation_event.gd")
var HUB_CAMP: GDScript:
	get: return load("res://script/scenes/hub_camp/hub_camp.gd")
## nur in Debug-Builds gebraucht
var DEBUG_MENU: GDScript:
	get: return load("res://script/scenes/world_map/map_debug_menu.gd")
var POTION_REWARD: GDScript:
	get: return load("res://script/scenes/potion_reward/potion_reward.gd")
var INVENTORY_DIALOG: GDScript:
	get: return load("res://script/scenes/world_map/inventory_dialog.gd")
const BATTLE_SCENE := "res://script/scenes/battle/battle.tscn"
## Boss-Felder sind halb so groß wie der Biom-Boss (64 statt 128 px), ihre Relikt-Bahn auch
const MAP_BOSS_ORBIT_SCALE := 0.55
## Tutorial: Pfeil über dem nächsten Feld (_point_to_next)
const TutorialPointerScript = preload("res://script/ui/tutorial/tutorial_pointer.gd")
var _pointer: Control

@export var view_container: Panel

@onready var map_ui: Control = $HBoxContainer
@onready var map_paper: Control = $HBoxContainer/Panel2/ScrollContainer/MarginContainer/MapPaper
@onready var map_panel: Control = $HBoxContainer/Panel2
@onready var desk_background: CanvasItem = $ColorRect
## Tasche oben links im Header: öffnet und schließt das Inventar
@onready var bag_icon: TextureRect = $HBoxContainer/Panel/BagIcon

var tweens = []
var _inventory: Control
var lines: Array[UILine] = []
var weather: MapWeather
# Biom, dessen Aussehen gerade gezeigt wird (weicht nur in der Vorschau mit Taste B vom echten Biom ab)
var shown_biome := 0

# Felder unter der aktuellen Position sind abgehakt und werden blass
const PASSED_MODULATE := Color(0.45, 0.45, 0.45, 0.8)
# Felder bleiben von Deko frei, der Wert ist der Radius ab Feldmitte
const NODE_CLEARANCE := 58.0
const BOSS_CLEARANCE := 110.0
# Der Hintergrund neben der Karte soll nur noch sanft wogen
const DESK_WAVE_BANDS := 5
const DESK_WAVE_AMP := 0.025
const DESK_WAVE_SPEED := 0.25
const NOISE_SHADER := preload("res://script/scenes/world_map/map_noise.gdshader")
const ENEMY_BADGE_NAME := "EnemyCount"

# Körniger, düsterer Look wie im Kampf über Papier, Deko und Wetter.
# All das liegt auf z_index -1 (auch in world_map.tscn), damit Felder, Wege, Lager, Shop & Co. normal darüber bleiben.
func add_noise_layer() -> void:
	var noise_material := ShaderMaterial.new()
	noise_material.shader = NOISE_SHADER
	var noise := ColorRect.new()
	noise.material = noise_material
	noise.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noise.z_index = -1
	map_panel.add_child(noise)
	noise.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	boss_button.material = Monmap.LIVING_MATERIAL

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# bis die Karte steht unsichtbar: sonst blitzt einen Frame lang der Boss oben auf der noch
	# ungescrollten Karte auf, auch wenn gleich zu Level-Up oder Boss-Belohnung weitergeleitet wird
	map_ui.modulate.a = 0.0
	State.ep_changed.connect(change_ep_text)
	State.boss_shards_changed.connect(monster_shard_changed)
	State.keys_changed.connect(change_key_text)
	State.coupons_changed.connect(change_coupon_text)
	State.pos_changed.connect(change_position)
	Relics.relics_changed.connect(refresh_encounter_info)
	Relics.relics_changed.connect(refresh_walkable_nodes)

	show_biome()
	monster_shard_changed(State.boss_shards)
	change_key_text(State.keys)
	change_coupon_text(State.coupons)
	# auf dem Handy per Finger scrollen, auch wenn der Finger auf einem Kartenfeld beginnt
	DragScroll.attach(scroll_container)
	weather = MapWeather.new()
	weather.scroll_container = scroll_container
	weather.z_index = -1
	map_panel.add_child(weather)
	add_noise_layer()
	shown_biome = State.current_biome()
	# nach Lager, Shop & Co. haben sich KP oder Elemente des Teams evtl. geändert
	view_container.child_exiting_tree.connect(func(_child): team_bar.refresh.call_deferred())
	team_bar.dialog_parent = view_container

	await get_tree().process_frame
	if State.killed_monsters >= 1 or State.has_pending_loot():
		get_tree().change_scene_to_file("res://script/scenes/level_up/level_up.tscn")
		return 
	# Tutorial: nach dem Biom-Boss baut sich die Karte auf, Reliktkiste und Couvert gehen auf, dann endet das
	# Tutorial (_tutorial_after_rewards)
	if State.is_boss_fight and not Tutorial.run_active:
		_finish_biome()
		return
	#Events.map_event_pressed.connect(_call_map_event)
	if not State.current_map:
		if Tutorial.run_active:
			Map.generate_tutorial_map()
		else:
			Map.generate_starting_points()
	set_map()
	apply_biome_look()
	# Fahrt von oben nach unten nur bei Run-Start oder neuem Biom, sonst direkt an die alte Stelle
	var scroll := scroll_container_to_bottom(State.current_map_position == State.NO_MAP_POSITION)
	map_ui.modulate.a = 1.0
	if State.current_map_position == State.NO_MAP_POSITION:
		change_position(Vector3.ZERO, true)
	else:
		change_position(State.current_map_position)
	change_ep_text(State.ep)
	add_settings_button()
	add_save_quit_button()
	# die Boss-Relikte stehen seit dem Betreten des Bioms fest und kreisen um den Boss
	if not Map.boss_relics.is_empty():
		boss_button.add_child(BossRelicOrbit.new(Map.boss_relics))
	if OS.is_debug_build():
		add_debug_button()
	show_pending_rewards()
	_setup_bag_button()
	team_bar.add_to_group("tut_map_team")
	$HBoxContainer/Panel/LegendButton.add_to_group("tut_map_legend")
	_add_currency_targets()
	# zu Beginn eines Runs, nie über Belohnungen hinweg. Erst nach der Fahrt über die Karte: während sie läuft,
	# wandern Felder und Ziele über den Bildschirm, Trainer und Blase würden ihnen hinterherspringen
	if State.current_map_position == State.NO_MAP_POSITION and Tutorial.should_show("map"):
		if scroll:
			# solange die Fahrt läuft, nimmt die Karte keine Klicks an: sonst wählt man ein Feld vor dem Tutorial
			var input_block := CanvasLayer.new()
			input_block.layer = TutorialOverlay.LAYER - 1
			var catcher := Control.new()
			catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			catcher.mouse_filter = Control.MOUSE_FILTER_STOP
			input_block.add_child(catcher)
			add_child(input_block)
			await scroll.finished
			input_block.queue_free()
		Tutorial.trigger("map")

# ─────────────────────────
# Inventar (One-Way-Items): die Tasche oben links schaltet es ein und aus. Monster-Details aus dem Header
# legen sich darüber, beide liegen im view_container.

func _setup_bag_button() -> void:
	bag_icon.mouse_filter = Control.MOUSE_FILTER_STOP
	bag_icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bag_icon.tooltip_text = tr("INVENTORY_OPEN")
	# eigenes Material: der goldene Umriss soll nur diese Tasche treffen
	bag_icon.material = bag_icon.material.duplicate()
	bag_icon.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			toggle_inventory())
	bag_icon.mouse_entered.connect(func(): RewardDialog.set_outline(bag_icon.material, true))
	bag_icon.mouse_exited.connect(func(): RewardDialog.set_outline(bag_icon.material, _inventory != null))
	bag_icon.add_to_group("tut_map_bag")
	_add_bag_count()

## Anzahl der Items in der Tasche auf der schwarzen Plakette in der Mitte der Tasche (leer: keine Zahl)
const BAG_PLAQUE_CENTER := Vector2(90, 124)
const BAG_TEXTURE_SIZE := Vector2(180, 170)
const BAG_COUNT_SIZE := Vector2(44, 40)
const BAG_COUNT_FONT_SIZE := 32

func _add_bag_count() -> void:
	var count_label := Label.new()
	count_label.add_theme_font_override("font", OpenBag.PIXEL_FONT)
	count_label.add_theme_font_size_override("font_size", BAG_COUNT_FONT_SIZE)
	count_label.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
	count_label.add_theme_color_override("font_outline_color", Color.BLACK)
	count_label.add_theme_constant_override("outline_size", 4)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.size = BAG_COUNT_SIZE
	# eigenes Material des Icons nicht erben (der Umriss würde sonst auch die Zahl umranden)
	count_label.use_parent_material = false
	bag_icon.add_child(count_label)
	var place := func():
		# das Bild sitzt mit Seitenverhältnis mittig im TextureRect
		var factor := minf(bag_icon.size.x / BAG_TEXTURE_SIZE.x, bag_icon.size.y / BAG_TEXTURE_SIZE.y)
		var offset := (bag_icon.size - BAG_TEXTURE_SIZE * factor) / 2
		count_label.position = offset + BAG_PLAQUE_CENTER * factor - BAG_COUNT_SIZE / 2
	bag_icon.resized.connect(place)
	place.call()
	var refresh := func():
		var count := Items.bag_count()
		count_label.text = str(count) if count > 0 else ""
	Items.items_changed.connect(refresh)
	tree_exiting.connect(func(): Items.items_changed.disconnect(refresh))
	refresh.call()

func toggle_inventory() -> void:
	if _inventory:
		_inventory.queue_free()
		return
	_inventory = INVENTORY_DIALOG.new()
	_inventory.tree_exiting.connect(func():
		_inventory = null
		RewardDialog.set_outline(bag_icon.material, false))
	view_container.add_child(_inventory)
	# offene Monster-Details bleiben obenauf
	view_container.move_child(_inventory, 0)
	RewardDialog.set_outline(bag_icon.material, true)

# Zahnrad im Header direkt links neben dem Legenden-Button, gleich groß wie dieser
func add_settings_button() -> void:
	var button := SettingsDialog.make_button(self)
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = -136.0
	button.offset_top = -72.0
	button.offset_right = -80.0
	button.offset_bottom = -16.0
	$HBoxContainer/Panel.add_child(button)

const DOOR_ICON := preload("res://assets/ui/icons/door.svg")

# Tür im Header links neben dem Zahnrad, gleich groß: Speichern und Beenden (RunSave). Nicht im Tutorial-Lauf.
func add_save_quit_button() -> void:
	if not RunSave.can_save():
		return
	var button := SettingsDialog.make_button(self)
	button.icon = DOOR_ICON
	button.tooltip_text = "MAP_SAVE_QUIT"
	# make_button öffnet die Einstellungen: diese Verbindung durch die Abfrage ersetzen
	for connection in button.pressed.get_connections():
		button.pressed.disconnect(connection.callable)
	button.pressed.connect(_ask_save_quit)
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = -200.0
	button.offset_top = -72.0
	button.offset_right = -144.0
	button.offset_bottom = -16.0
	$HBoxContainer/Panel.add_child(button)

## Speichern und Beenden oder Abbrechen
func _ask_save_quit() -> void:
	var dialog := ChoiceDialog.ask(self, "MAP_SAVE_QUIT_TITLE", "MAP_SAVE_QUIT_TEXT", "MAP_SAVE_QUIT_YES", "MAP_SAVE_QUIT_NO")
	if not await dialog.chosen:
		return
	if RunSave.save():
		get_tree().quit()

# Nur in Debug-Builds: links neben der Tür im Header
func add_debug_button() -> void:
	var button := RewardDialog.plate_button("DEBUG")
	button.add_theme_font_size_override("font_size", 24)
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = -300.0
	button.offset_top = -60.0
	button.offset_right = -208.0
	button.offset_bottom = -16.0
	button.pressed.connect(func():
		var menu = DEBUG_MENU.new()
		menu.map = self
		view_container.add_child(menu))
	$HBoxContainer/Panel.add_child(button)

#func _enter_tree() -> void:
#	Events.map_event_pressed.disconnect(_call_map_event)

func _exit_tree() -> void:
	State.ep_changed.disconnect(change_ep_text)
	State.boss_shards_changed.disconnect(monster_shard_changed)
	State.keys_changed.disconnect(change_key_text)
	State.coupons_changed.disconnect(change_coupon_text)
	State.pos_changed.disconnect(change_position)
	Relics.relics_changed.disconnect(refresh_encounter_info)
	Relics.relics_changed.disconnect(refresh_walkable_nodes)

func set_map():
	var _to_clear_children = grid_container.get_children()
	for child in _to_clear_children:
		grid_container.remove_child(child)
		child.queue_free()
	for line in lines:
		line.queue_free()
	lines.clear()

	var screen_width = grid_container.size.x
	var gap = 100
	var map_y_height = State.current_map[0].size()
	for i in 8:
		for j in map_y_height:
			var new_container = node_container.duplicate()
			new_container.visible = true
			grid_container.add_child(new_container)
	# set map
	var grid_children = grid_container.get_children()
	for x_path_index in State.current_map.size():
		var x_path = State.current_map[x_path_index]
		for y_path_index in x_path.size():
			var y_path = x_path[y_path_index]
			var g_container = grid_children[y_path_index * State.current_map.size() + x_path_index]
			var d: Button = node_name.duplicate()
			if y_path != null:
				d.icon = Map.ICONS[y_path._type]
				d.material = Monmap.LIVING_MATERIAL
				d.tooltip_text = tr(Map.type_label(y_path._type))
				d.pressed.connect(func(): call_map_event(y_path))
				if y_path._pos.y == 0:
					d.add_to_group("tut_map_start")
				d.visible = true
				y_path._ui_item = d
				g_container._path = y_path
				# if is below current path, reset all to done...
				# todo
				if State.current_map_position.y >= y_path._pos.y:
					reset_animation_state(y_path)
				# Boss-Felder vor einem zeigen ihre Relikte wie der Biom-Boss, nur kleiner
				elif y_path._type == Map.PATH_TYPE.BOSS and not y_path._boss_relics.is_empty():
					d.add_child(BossRelicOrbit.new(y_path._boss_relics, MAP_BOSS_ORBIT_SCALE))
			g_container.add_child(d)
	# reverse...
	var children = grid_container.get_children()
	children.reverse()
	draw_lines()

	for child in children:
		grid_container.remove_child(child)

	for child in children:
		grid_container.add_child(child)
	refresh_encounter_info()

# Was die Relikte über die Kämpfe verraten. Läuft auch, wenn auf der Karte ein Relikt dazukommt oder getauscht wird.
func refresh_encounter_info() -> void:
	if State.current_map.is_empty():
		return
	for column in State.current_map:
		for node in column:
			if node != null and node._ui_item != null:
				show_encounter_info(node._ui_item, tr(Map.type_label(node._type)), node._enemies)
	show_encounter_info(boss_button, tr("WORLDMAP_BOSS"), Map.boss_enemies, false)

# Spyglass: Anzahl der Gegner direkt auf dem Feld. Super Catcher: "?" bei Arten, die du noch nicht besitzt (Start-Monster und
# catched_monsters im Spielstand). Mit beiden Relikten steht dort z. B. "2?". Der Biom-Boss bekommt kein Badge.
# Der Tooltip nennt nur die Art des Feldes, keine Monster.
func show_encounter_info(button: Button, title: String, enemies: Array[Monster], show_badge := true) -> void:
	var badge: Label = button.get_node_or_null(ENEMY_BADGE_NAME)
	var badge_text := str(enemies.size()) if show_badge and Relics.works("spyglass") and not enemies.is_empty() else ""
	var owned := Helper.get_all_owned_monster_names()
	if show_badge and Relics.works("super_catcher") and enemies.any(func(mon: Monster): return not owned.has(mon._name)):
		badge_text += "?"
	if badge == null and badge_text != "":
		badge = make_enemy_badge()
		button.add_child(badge)
	if badge != null:
		badge.visible = badge_text != ""
		badge.text = badge_text
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	button.tooltip_text = title

func make_enemy_badge() -> Label:
	var badge := Label.new()
	badge.name = ENEMY_BADGE_NAME
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_font_size_override("font_size", 40)
	badge.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 8)
	return badge

func draw_lines() -> void:
	var all_items = grid_container.get_children()
	for i in grid_container.columns:
		#path i
		var ally_nodes = all_items.filter(func(n): 
			if n != null and n._path != null:
				print(n._path._pos.z == i)
				return n._path._pos.z == i
			)
		for y_node in ally_nodes:
			print("gen line", ally_nodes.filter(func(n): return y_node._path._pos.y + 1 == n._path._pos.y).size())
			# get all next nodes
			var allnext_nodes = ally_nodes.filter(func(n): return y_node._path._pos.y + 1 == n._path._pos.y)
			for next_node in allnext_nodes:
				print("will draw")
				add_line(y_node, next_node)
			pass
		pass
	pass
	# Vom letzten Feld jedes Pfads geht es zum Boss
	var last_row: int = State.current_map[0].size() - 1
	for item in all_items:
		if item._path != null and item._path._pos.y == last_row:
			add_line(item, boss_button)

func add_line(from: Control, to: Control) -> void:
	var line = line_node.duplicate(DUPLICATE_SCRIPTS | DUPLICATE_USE_INSTANTIATION)
	line.from_node = from
	line.to_node = to
	map_layout.add_child(line)
	lines.append(line)

func _on_button_pressed() -> void:
	print("Map.gen_map()", State.current_map)
	Map.generate_starting_points()
	set_map()
	apply_biome_look()
	change_position(Vector3.ZERO, true)


func _call_map_event(map_node) -> void:
	if map_node._pos.y == State.map_progress_level:
		print("same level, go!")
		SceneLoader.change_scene(BATTLE_SCENE)

## Fahrt zur aktuellen Reihe; mit animate kommt der Tween zurück (sonst null)
func scroll_container_to_bottom(animate := true) -> Tween:
	var cur_pos = State.current_map_position
	var map_height = grid_container.get_child_count() / grid_container.columns
	var damn_bro = scroll_container.get_v_scroll_bar().max_value - scroll_container.size.y
	var scroll_pos = damn_bro - ((damn_bro / map_height) * cur_pos.y)
	if not animate:
		scroll_container.scroll_vertical = int(scroll_pos)
		return null
	# an die Karte gebunden: verlässt man sie vorher, endet die Fahrt mit ihr
	var tween = create_tween()
	tween.tween_property(
		scroll_container, "scroll_vertical",
		scroll_pos, map_height * .1 + 1
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween

func call_map_event(path_type) -> void:
	if path_type:
		if State.current_map_position == State.NO_MAP_POSITION and path_type._pos.y == 0:
			Map.pending_enemies = path_type._enemies
			Map.pending_relics = path_type._boss_relics
			Map.pending_ref_half = Map.ref_half_for_row(int(path_type._pos.y))
			call_event_by_type(path_type._type)
			State.current_map_position = path_type._pos
			#reset_animation_state(path_type)
			return
		if can_walk_to(path_type, State.current_map_position):
			Map.pending_enemies = path_type._enemies
			Map.pending_relics = path_type._boss_relics
			# auch für Auseinandersetzungen auf Event-Feldern
			Map.pending_ref_half = Map.ref_half_for_row(int(path_type._pos.y))
			call_event_by_type(path_type._type)
			State.current_map_position = path_type._pos
			#reset_animation_state(path_type)

## Immer nur eine Reihe weiter, die Lane darf nur der Fliegende Teppich wechseln.
## Debug-Menü "JEDES FELD": jedes Feld der Karte ist betretbar, auch zurück und quer.
func can_walk_to(node, pos: Vector3) -> bool:
	if DebugSettings.free_walk_enabled():
		return true
	return node._pos.y == pos.y + 1 and (node._pos.z == pos.z or Relics.works("flying_carpet"))

func call_event_by_type(type) -> void:
	if type == Map.PATH_TYPE.COMBAT:
		SceneLoader.change_scene(BATTLE_SCENE)
		pass
	if type == Map.PATH_TYPE.BOSS:
		State.is_map_boss = true
		SceneLoader.change_scene(BATTLE_SCENE)
	if type == Map.PATH_TYPE.CAMP:
		open_heal_camp()
	if type == Map.PATH_TYPE.HUB:
		view_container.add_child(HUB_CAMP.new())
	if type == Map.PATH_TYPE.EVENT:
		call_random_event()
	if type == Map.PATH_TYPE.SHOP:
		var shops = shop_scene.instantiate()
		view_container.add_child(shops)
		shops.visible = true
		pass
	if type == Map.PATH_TYPE.TRAINER:
		var trainer = trainer_scene.instantiate()
		view_container.add_child(trainer)
		trainer.visible = true
		pass
	if type == Map.PATH_TYPE.TREASURE:
		var treasure = treasure_scene.instantiate()
		# gefundene Tränke fallen danach aus der Tasche
		treasure.tree_exited.connect(show_pending_rewards, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
		view_container.add_child(treasure)
		treasure.visible = true
		pass
	if type == Map.PATH_TYPE.GEM:
		view_container.add_child(GEM_SCENE.instantiate())
	if type == Map.PATH_TYPE.JAILER:
		var jailer = jailer_scene.instantiate()
		view_container.add_child(jailer)
		jailer.visible = true
		pass
	print("call event", type)

# EVENT-Feld: welches Ereignis kommt, wird über Map.event_chances ausgewürfelt
func call_random_event() -> void:
	# Tutorial: immer das Glücksrad (Variante "Ewiges Pech", wheel_event.gd)
	var event = Map.EVENT_TYPE.WHEEL if Tutorial.run_active else Map.roll_event()
	print("random event", event)
	match event:
		Map.EVENT_TYPE.CAMP:
			open_heal_camp()
		Map.EVENT_TYPE.WHEEL:
			open_wheel_event()
		Map.EVENT_TYPE.VOID:
			open_void_event()
		Map.EVENT_TYPE.CONFRONTATION:
			open_confrontation_event()

func open_wheel_event() -> void:
	view_container.add_child(WHEEL_EVENT.new())

func open_confrontation_event() -> void:
	view_container.add_child(CONFRONTATION_EVENT.new())

func open_void_event() -> void:
	view_container.add_child(VOID_EVENT.new())

func open_heal_camp() -> void:
	var hcs = heal_camp_scene.instantiate()
	view_container.add_child(hcs)
	hcs.visible = true


func _on_boss_button_pressed() -> void:
	if State.current_map.size() > 0:
		if State.current_map_position.y + 1 == State.current_map[0].size() or DebugSettings.free_walk_enabled():
			start_biome_boss()

## Biom-Boss besiegt und Beute abgehandelt: weiter ins nächste Biom, nach dem letzten endet der Run mit einem Sieg.
## Boss-Felder auf der Karte zählen nicht für die Meilensteine und die Faule-Eier-Ladung.
func _finish_biome() -> void:
	# Tutorial: der Biom-Boss ist das letzte Feld, danach endet das Tutorial
	if Tutorial.run_active:
		Tutorial.finish()
		return
	State.is_boss_fight = false
	SaveManager.add_reroll_charge()
	State.map_level += 1
	# Meilensteine "n-ter Biom-Boss" zählen State.map_level, "ohne K.O." nur solange noch kein eigenes Monster fiel
	if State.run_deaths.is_empty():
		State.run_flawless_bosses += 1
	Skills.check_milestones()
	State.biome_fight_index = 0
	# die Referenzstufe läuft über die Biome weiter: alle möglichen K.O.s des besten Pfads samt Biom-Boss
	State.level_ref_half += Map.biome_ref_kills
	if State.map_level == Map.map_settings.size():
		State.end_run(true)
		get_tree().change_scene_to_file("res://script/scenes/run_end/run_end.tscn")
		return
	Map.generate_starting_points()
	get_tree().change_scene_to_file("res://script/scenes/world_map/world_map.tscn")

func start_biome_boss() -> void:
	State.is_boss_fight = true
	Map.pending_enemies = Map.boss_enemies
	Map.pending_relics = Map.boss_relics
	if State.map_level == Map.map_settings.size() - 1:
		State.is_final_boss = true
	SceneLoader.change_scene(BATTLE_SCENE)
	State.current_map_position = State.NO_MAP_POSITION

func change_position(pos, initial = false) -> void:
	for tween: Tween in tweens:
		tween.kill()
	tweens = []
	var all_nodes = []
	for i in State.current_map.size():
		all_nodes.append_array(State.current_map[i])
	
	var possible_walkable_nodes = all_nodes.filter(func(node): return node != null).filter(func(node): return can_walk_to(node, pos)) if initial == false else all_nodes.filter(func(node): return node != null).filter(func(node): return node._pos.y == pos.y)
	# reset all positions here...
	var walked_ndoes = all_nodes.filter(func(node): return node != null).filter(func(node): return node._pos.y == pos.y)
	for walked_nodes in walked_ndoes:
		reset_animation_state(walked_nodes)
	update_line_states(State.NO_MAP_POSITION if initial else pos)

	for walkable_node in possible_walkable_nodes:
		if (walkable_node._ui_item):
			print("animate pos:", walkable_node._pos, State.current_map_position)
			var ub: Button = walkable_node._ui_item
			var tween = create_tween()
			tween.set_loops()
			tween.tween_property(ub, "scale", Vector2(1.2, 1.2), 3)
			tween.tween_property(ub, "scale", Vector2(1, 1), 3)
			tweens.append(tween)
			ub.modulate = Color.WHITE
	_point_to_next(possible_walkable_nodes, pos)

## Vorräte oben im Header (Symbol + Zahl) für das Tutorial; nach dem ersten Schlüssel (Glücksrad, Feld 3) werden sie
## erklärt, sobald kein Dialog mehr über der Karte liegt
func _add_currency_targets() -> void:
	for pair in [["map_cur_essence", money_label, "EssenceIcon"], ["map_cur_tears", boss_shard_label, "ShardIcon"],
			["map_cur_keys", key_label, "KeyIcon"], ["map_cur_coupons", coupon_label, "CouponIcon"]]:
		var label: Label = pair[1]
		for node: Control in [label.get_parent().get_node(pair[2]), label]:
			node.add_to_group("tut_" + pair[0])
			node.add_to_group("tut_map_currencies")
	if not Tutorial.should_show("currencies"):
		return
	view_container.child_exiting_tree.connect(func(_child): _tutorial_currencies.call_deferred())

func _tutorial_currencies() -> void:
	if State.keys <= 0 or not Tutorial.should_show("currencies") or Tutorial.is_running():
		return
	if view_container.get_children().any(func(child): return not child.is_queued_for_deletion() and child.visible):
		return
	Tutorial.trigger("currencies")

## Tutorial-Lauf: ein Pfeil zeigt immer auf das nächste Feld (nach dem letzten Feld auf den Biom-Boss),
## damit nach einer Erklärung niemand rätselt, wohin es weitergeht
func _point_to_next(walkable: Array, pos: Vector3) -> void:
	if is_instance_valid(_pointer):
		_pointer.queue_free()
	_pointer = null
	if not Tutorial.run_active:
		return
	var target: Control = null
	for node in walkable:
		if node._ui_item:
			target = node._ui_item
			break
	if target == null and State.current_map.size() > 0 and pos.y + 1 == State.current_map[0].size():
		target = boss_button
	if target:
		_pointer = TutorialPointerScript.new()
		# Shop, Lager, Schatz, Inventar & Co. liegen im view_container über der Karte
		_pointer.covered = func() -> bool:
			return view_container.get_children().any(
				func(child): return not child.is_queued_for_deletion() and child.visible)
		target.add_child(_pointer)

## Kommt der Fliegende Teppich auf der Karte dazu oder geht er (Shop, Void), ändern sich die begehbaren Felder.
## Vor dem ersten Feld ist ohnehin die ganze erste Reihe frei.
func refresh_walkable_nodes() -> void:
	var pos := State.current_map_position
	if lines.is_empty() or pos == State.NO_MAP_POSITION:
		return
	for column in State.current_map:
		for node in column:
			if node != null and node._pos.y == pos.y + 1:
				node._ui_item.scale = Vector2.ONE
				node._ui_item.modulate = node_name.modulate
	change_position(pos)

# Wege ab der aktuellen Position leuchten, zurückgelegte Abschnitte treten zurück
func update_line_states(pos: Vector3) -> void:
	for line in lines:
		var from_pos: Vector3 = line.from_node._path._pos
		if from_pos == pos or (from_pos.y == pos.y and Relics.works("flying_carpet")):
			line.set_state(UILine.LineState.WALKABLE)
		elif line.to_node != boss_button and line.to_node._path._pos.y <= pos.y:
			line.set_state(UILine.LineState.PASSED)
		else:
			line.set_state(UILine.LineState.LOCKED)

# Hintergrund, Papier, Wege, Deko und Wetter passend zum Biom. Der Seed hängt am Run und der Tiefe,
# damit die Deko nach einem Kampf wieder an derselben Stelle steht.
func apply_biome_look() -> void:
	var look := MapBiomeTheme.get_look(shown_biome)
	var rng_seed := absi(hash([State.map_level, shown_biome, State.biome_pools]))
	var paper_dark := Color(look.paper_dark)
	var desk: ShaderMaterial = desk_background.material
	desk.set_shader_parameter("top_color", paper_dark.darkened(0.45))
	desk.set_shader_parameter("bottom_color", paper_dark.darkened(0.72))
	desk.set_shader_parameter("total_phases", DESK_WAVE_BANDS)
	desk.set_shader_parameter("wave_amp", DESK_WAVE_AMP)
	desk.set_shader_parameter("wave_time_mul", DESK_WAVE_SPEED)
	desk.set_shader_parameter("flicker", 0.04)
	map_paper.apply_look(look, rng_seed)
	for line in lines:
		# auf der abgedunkelten Karte ist nur helle Tinte noch sichtbar
		line.apply_look(Color(look.paper_light).lightened(0.3), Color(look.accent))
	weather.apply_look(look)
	# Deko braucht die endgültigen Positionen der Felder, die stehen erst nach dem Layout
	await get_tree().process_frame
	scatter_deco(look.deco, rng_seed)

func scatter_deco(deco: Array, rng_seed: int) -> void:
	var origin: Vector2 = map_paper.deco_layer.get_global_rect().position
	var clear_points := [[boss_button.get_global_rect().get_center() - origin, BOSS_CLEARANCE]]
	for child in grid_container.get_children():
		if child._path != null and child._path._ui_item != null:
			clear_points.append([child._path._ui_item.get_global_rect().get_center() - origin, NODE_CLEARANCE])
	var clear_segments := []
	for line in lines:
		var ends: Array[Vector2] = line.endpoints()
		clear_segments.append([ends[0] - origin, ends[1] - origin])
	map_paper.deco_layer.scatter(deco, rng_seed, clear_points, clear_segments)

# Vorschau zum Ausprobieren: B schaltet das Aussehen durch alle Biome, der Run selbst bleibt unverändert.
func _input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not event is InputEventKey:
		return
	if event.pressed and not event.echo and event.keycode == KEY_B and not lines.is_empty():
		var order := MapBiomeTheme.PREVIEW_ORDER
		shown_biome = order[(order.find(shown_biome) + 1) % order.size()]
		show_biome(shown_biome)
		apply_biome_look()

func monster_shard_changed(amount) -> void:
	boss_shard_label.text = str(amount)

func change_ep_text(ep) -> void:
	money_label.text = str(ep)

func change_key_text(keys) -> void:
	key_label.text = str(keys)

func change_coupon_text(coupons) -> void:
	coupon_label.text = str(coupons)

# Biom-Pfad des Runs im Header: Kästchen pro Biom, das aktuelle umrahmt, darunter "Pfad: <Biom>".
# Klick darauf öffnet den großen Pfad (BiomePathDialog), von dort jedes Biom mit Stärken und Schwächen.
# mask bleibt für die Debug-Vorschau (Taste B), der Header zeigt immer den echten Pfad.
func show_biome(_mask := State.current_biome()) -> void:
	biome_trail.show_path(State.biome_path, State.map_level)

func reset_animation_state(ele) -> void:
	ele._ui_item.scale = Vector2(1,1)
	ele._ui_item.modulate = PASSED_MODULATE

# Geloottes nacheinander abhandeln, erst hier, damit Level-Up und Boss-Belohnung vorher durch sind:
# Relic-Kiste, Skill-Couvert, dann einzelne Edelsteine, zuletzt Tränke aus einer Schatzkiste.
# Schließt ein Dialog, kommt der nächste.
func show_pending_rewards() -> void:
	var dialog := _next_pending_reward()
	if dialog == null:
		_tutorial_after_rewards()
		return
	dialog.tree_exited.connect(show_pending_rewards, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
	view_container.add_child(dialog)
	dialog.visible = true

## Tutorial, alle Belohnungen erledigt: nach dem Biom-Boss endet das Tutorial (Tutorial.finish),
## nach dem Schatz (Feld 4) geht das Inventar auf und wird erklärt
func _tutorial_after_rewards() -> void:
	if not Tutorial.run_active:
		return
	if State.is_boss_fight:
		State.is_boss_fight = false
		Tutorial.finish()
		return
	if int(State.current_map_position.y) != 3 or not Tutorial.should_show("inventory"):
		return
	if State.bag.all(func(item): return item == null):
		return
	if not _inventory:
		toggle_inventory()
	Tutorial.trigger("inventory")

func _next_pending_reward() -> Control:
	if State.pending_relic_reward:
		State.pending_relic_reward = false
		if not Relics.chest_offers(State.relic_chest_rarity).is_empty():
			return RELIC_REWARD_SCENE.instantiate()
	if State.pending_skill_reward:
		State.pending_skill_reward = false
		if not Skills.reward_offers().is_empty():
			return SKILL_REWARD_SCENE.instantiate()
	if State.pending_gem_rewards > 0:
		State.pending_gem_rewards -= 1
		var gem := GEM_SCENE.instantiate()
		gem.gem_choices = 1
		return gem
	if not State.pending_potions.is_empty():
		var potion = POTION_REWARD.new()
		potion.element = State.pending_potions.pop_front()
		return potion
	return null
