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
@export var depth_level: Label
@export var biome_path_label: RichTextLabel
@export var team_bar: HBoxContainer

@export var heal_camp_scene: PackedScene
@export var shop_scene: PackedScene
# gogogo
@export var jailer_scene: PackedScene
@export var trainer_scene: PackedScene
@export var treasure_scene: PackedScene

const RELIC_REWARD_SCENE := preload("res://script/scenes/relic_reward/relic_reward.tscn")
const GEM_SCENE := preload("res://script/scenes/gems/gems.tscn")
const SKILL_REWARD_SCENE := preload("res://script/scenes/skill_reward/skill_reward.tscn")
const WHEEL_EVENT := preload("res://script/scenes/wheel_event/wheel_event.gd")
const VOID_EVENT := preload("res://script/scenes/void_event/void_event.gd")
const HUB_CAMP := preload("res://script/scenes/hub_camp/hub_camp.gd")
const DEBUG_MENU := preload("res://script/scenes/world_map/map_debug_menu.gd")

@export var view_container: Panel

@onready var map_ui: Control = $HBoxContainer
@onready var map_paper: Control = $HBoxContainer/Panel2/ScrollContainer/MarginContainer/MapPaper
@onready var map_panel: Control = $HBoxContainer/Panel2
@onready var desk_background: CanvasItem = $ColorRect

var tweens = []
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
	# Klick auf ein Biom der Route bzw. das aktuelle Biom zeigt seine Stärken und Schwächen
	biome_path_label.meta_clicked.connect(func(meta): _open_biome_info(int(str(meta))))
	biome_path_label.tooltip_text = tr("BIOME_INFO_HINT")
	depth_level.tooltip_text = tr("BIOME_INFO_HINT")
	depth_level.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_open_biome_info(State.map_level))
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
	if State.is_boss_fight:
		_finish_biome()
		return
	#Events.map_event_pressed.connect(_call_map_event)
	if not State.current_map:
		Map.generate_starting_points()
	set_map()
	apply_biome_look()
	# Fahrt von oben nach unten nur bei Run-Start oder neuem Biom, sonst direkt an die alte Stelle
	scroll_container_to_bottom(State.current_map_position == State.NO_MAP_POSITION)
	map_ui.modulate.a = 1.0
	if State.current_map_position == State.NO_MAP_POSITION:
		change_position(Vector3.ZERO, true)
	else:
		change_position(State.current_map_position)
	change_ep_text(State.ep)
	add_settings_button()
	if OS.is_debug_build():
		add_debug_button()
	show_pending_rewards()
	team_bar.add_to_group("tut_map_team")
	$HBoxContainer/Panel/LegendButton.add_to_group("tut_map_legend")
	Tutorial.enabled_changed.connect(_on_tutorial_enabled_changed)
	# zu Beginn eines Runs oder direkt nach dem Übungskampf, nie über Belohnungen hinweg
	if State.current_map_position == State.NO_MAP_POSITION or Tutorial.take_back_from_practice():
		Tutorial.trigger("map")

## Im Einstellungen-Dialog eingeschaltet: es geht gleich mit dem Übungskampf los, danach erklärt sich die Karte
func _on_tutorial_enabled_changed(on: bool) -> void:
	if on and Tutorial.wants_practice():
		Tutorial.start_practice()

# Zahnrad im Header direkt links neben dem Legenden-Button, gleich groß wie dieser
func add_settings_button() -> void:
	var button := SettingsDialog.make_button(self)
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = -136.0
	button.offset_top = -72.0
	button.offset_right = -80.0
	button.offset_bottom = -16.0
	$HBoxContainer/Panel.add_child(button)

# Nur in Debug-Builds: links neben dem Einstellungen-Button im Header
func add_debug_button() -> void:
	var button := RewardDialog.plate_button("DEBUG")
	button.add_theme_font_size_override("font_size", 16)
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = -236.0
	button.offset_top = -60.0
	button.offset_right = -144.0
	button.offset_bottom = -16.0
	button.pressed.connect(func():
		var menu = DEBUG_MENU.new()
		menu.map = self
		view_container.add_child(menu))
	$HBoxContainer/Panel.add_child(button)

#func _enter_tree() -> void:
#	Events.map_event_pressed.disconnect(_call_map_event)

func _exit_tree() -> void:
	if Tutorial.enabled_changed.is_connected(_on_tutorial_enabled_changed):
		Tutorial.enabled_changed.disconnect(_on_tutorial_enabled_changed)
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
	badge.add_theme_font_size_override("font_size", 28)
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
		get_tree().change_scene_to_file("res://script/scenes/battle/battle.tscn")

func scroll_container_to_bottom(animate := true) -> void:
	var cur_pos = State.current_map_position
	var map_height = grid_container.get_child_count() / grid_container.columns
	var damn_bro = scroll_container.get_v_scroll_bar().max_value - scroll_container.size.y
	var scroll_pos = damn_bro - ((damn_bro / map_height) * cur_pos.y)
	if not animate:
		scroll_container.scroll_vertical = int(scroll_pos)
		return
	var tween = get_tree().create_tween()
	tween.tween_property(
		scroll_container, "scroll_vertical",
		scroll_pos, map_height * .1 + 1
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func call_map_event(path_type) -> void:
	if path_type:
		if State.current_map_position == State.NO_MAP_POSITION and path_type._pos.y == 0:
			Map.pending_enemies = path_type._enemies
			call_event_by_type(path_type._type)
			State.current_map_position = path_type._pos
			#reset_animation_state(path_type)
		if can_walk_to(path_type, State.current_map_position):
			Map.pending_enemies = path_type._enemies
			call_event_by_type(path_type._type)
			State.current_map_position = path_type._pos
			#reset_animation_state(path_type)

## Immer nur eine Reihe weiter, die Lane darf nur der Fliegende Teppich wechseln
func can_walk_to(node, pos: Vector3) -> bool:
	return node._pos.y == pos.y + 1 and (node._pos.z == pos.z or Relics.works("flying_carpet"))

func call_event_by_type(type) -> void:
	if type == Map.PATH_TYPE.COMBAT:
		get_tree().change_scene_to_file("res://script/scenes/battle/battle.tscn")
		pass
	if type == Map.PATH_TYPE.BOSS:
		State.is_map_boss = true
		get_tree().change_scene_to_file("res://script/scenes/battle/battle.tscn")
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
	var event = Map.roll_event()
	print("random event", event)
	match event:
		Map.EVENT_TYPE.CAMP:
			open_heal_camp()
		Map.EVENT_TYPE.WHEEL:
			open_wheel_event()
		Map.EVENT_TYPE.VOID:
			open_void_event()

func open_wheel_event() -> void:
	view_container.add_child(WHEEL_EVENT.new())

func open_void_event() -> void:
	view_container.add_child(VOID_EVENT.new())

func open_heal_camp() -> void:
	var hcs = heal_camp_scene.instantiate()
	view_container.add_child(hcs)
	hcs.visible = true


func _on_boss_button_pressed() -> void:
	if State.current_map.size() > 0:
		if State.current_map_position.y + 1 == State.current_map[0].size():
			start_biome_boss()

## Biom-Boss besiegt und Beute abgehandelt: weiter ins nächste Biom, nach dem letzten endet der Run mit einem Sieg.
## Boss-Felder auf der Karte zählen nicht für den Meilenstein und die Faule-Eier-Ladung.
func _finish_biome() -> void:
	State.is_boss_fight = false
	var unlocked: Array = Skills.add_milestone_progress(State.starter_name, "biome_boss_kills")
	if not unlocked.is_empty():
		Helper.show_unlock_message(tr("MILESTONE_UNLOCKED").format({
			"mon": Helper.mon_display_name(State.starter_name),
			"skills": ", ".join(PackedStringArray(unlocked.map(func(skill_name): return tr(skill_name)))),
		}))
	SaveManager.add_reroll_charge()
	State.map_level += 1
	State.biome_fight_index = 0
	if State.map_level == Map.map_settings.size():
		State.end_run(true)
		get_tree().change_scene_to_file("res://script/scenes/run_end/run_end.tscn")
		return
	Map.generate_starting_points()
	get_tree().change_scene_to_file("res://script/scenes/world_map/world_map.tscn")

func start_biome_boss() -> void:
	State.is_boss_fight = true
	Map.pending_enemies = Map.boss_enemies
	if State.map_level == Map.map_settings.size() - 1:
		State.is_final_boss = true
	get_tree().change_scene_to_file("res://script/scenes/battle/battle.tscn")
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

# Name des aktuellen Bioms in seiner Farbe, dazu die Tiefe
func show_biome(mask := State.current_biome()) -> void:
	var biome = ColorMap.get_combo(mask)
	depth_level.text = tr("MAP_HEADER_BIOME").format({"biome": tr(biome.label), "depth": State.map_level + 1})
	depth_level.add_theme_color_override("font_color", Color(biome.color).lightened(0.4))
	show_biome_path()

# Alle Biome des Runs als Route: geschaffte blass, das aktuelle hervorgehoben, kommende in ihrer Farbe
func show_biome_path() -> void:
	var parts = []
	var passed := Color(IronPlate.TEXT_COLOR, 0.35).to_html()
	for depth in State.biome_path.size():
		var combo = ColorMap.get_combo(State.biome_path[depth])
		# jedes Biom ist ein Link auf seine Tiefe (siehe _open_biome_info)
		var text = "[url=%d]%d %s[/url]" % [depth, depth + 1, tr(combo.label)]
		if depth < State.map_level:
			parts.append("[color=#%s]%s[/color]" % [passed, text])
		elif depth == State.map_level:
			parts.append("[b][u][color=#%s]%s[/color][/u][/b]" % [Color(combo.color).lightened(0.4).to_html(false), text])
		else:
			parts.append("[color=#%s]%s[/color]" % [Color(combo.color).lightened(0.2).to_html(false), text])
	biome_path_label.text = "[color=#%s]%s[/color] %s" % [SkillDetailPopup.GOLD.to_html(false), tr("MAP_HEADER_ROUTE"), (" [color=#%s]›[/color] " % passed).join(parts)]

func _open_biome_info(depth: int) -> void:
	if depth >= 0 and depth < State.biome_path.size():
		BiomeInfoDialog.open(self, State.biome_path[depth], depth)

func reset_animation_state(ele) -> void:
	ele._ui_item.scale = Vector2(1,1)
	ele._ui_item.modulate = PASSED_MODULATE

# Geloottes nacheinander abhandeln, erst hier, damit Level-Up und Boss-Belohnung vorher durch sind:
# Relic-Kiste, Skill-Couvert, dann einzelne Edelsteine. Schließt ein Dialog, kommt der nächste.
func show_pending_rewards() -> void:
	var dialog := _next_pending_reward()
	if dialog == null:
		return
	dialog.tree_exited.connect(show_pending_rewards, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
	view_container.add_child(dialog)
	dialog.visible = true

func _next_pending_reward() -> Control:
	if State.pending_relic_reward:
		State.pending_relic_reward = false
		if not Relics.get_unowned().is_empty():
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
	return null
