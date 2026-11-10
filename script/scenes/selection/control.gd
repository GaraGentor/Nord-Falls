extends Control

var mons = []
var egg_picked_index = 1
var selected: int:
	set(value):
		selected = value
		Events.select_initial_mon.emit(value)

var common_egg = preload("res://assets/ui/eggs/common_1.png")
var common_egg_crack = preload("res://assets/ui/eggs/common_2.png")

@export var title_label: Label
@export var go_button: Button
## Erscheint mit vollen Ladungen, sobald alle Eier gezogen sind (SaveManager.REROLL_CHARGES_NEEDED)
@export var reroll_button: Button

## Ansicht des gewählten Eis wie im Kampf: Name, Bild, Typ, Werte, Skills
@export var info_panel: Control
@export var biome_path: Control
## Am selben Platz, solange noch kein Ei gewählt ist: Knöpfe für Anleitung und Sammlung
@export var menu: Control

var selected_egg: int = 0

## Zahnrad unten links (Größe und Abstand wie der Legenden-Button der Karte)
const SETTINGS_BUTTON_SIZE := 56.0
const SETTINGS_BUTTON_MARGIN := 16.0
const MENU_BUTTON_WIDTH := 280.0
const MENU_FONT_SIZE := 24

func _ready() -> void:
	_add_settings_button()
	_build_menu()
	load_eggs()
	biome_path.show_path(Map.load_biome_path())
	# display_mons()
	Events.select_initial_mon.connect(select_egg)
	# Events.select_initial_mon.emit(0)
	_add_tutorial_targets()
	Tutorial.enabled_changed.connect(_on_tutorial_enabled_changed)
	Tutorial.trigger("selection")

func _exit_tree() -> void:
	Tutorial.enabled_changed.disconnect(_on_tutorial_enabled_changed)

## Im Einstellungen-Dialog eingeschaltet: von vorn, damit das Tutorial mit dem Ziehen der Eier beginnen kann
func _on_tutorial_enabled_changed(on: bool) -> void:
	if on:
		get_tree().reload_current_scene.call_deferred()

func _build_menu() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	menu.add_child(column)
	column.add_child(_menu_button(tr("SELECTION_GUIDE"), func(): InfoDialog.present(self, GuideDialog.new())))
	column.add_child(_menu_button(tr("SELECTION_COLLECTION"), func(): InfoDialog.present(self, CollectionDialog.new())))

func _menu_button(text: String, on_pressed: Callable) -> Button:
	var button := RewardDialog.plate_button(text)
	button.add_theme_font_size_override("font_size", MENU_FONT_SIZE)
	button.custom_minimum_size.x = MENU_BUTTON_WIDTH
	button.focus_mode = FOCUS_NONE
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	button.pressed.connect(on_pressed)
	return button

## Gruppen, die das interaktive Tutorial hervorhebt (siehe Tutorial.SEQUENCES)
func _add_tutorial_targets() -> void:
	biome_path.add_to_group("tut_biome_path")
	$Selection/HBoxContainer.add_to_group("tut_eggs")
	$Selection/MarginContainer/VBoxContainer/Button.add_to_group("tut_draw_egg")
	info_panel.add_to_group("tut_starter_info")
	go_button.add_to_group("tut_begin_journey")

func _add_settings_button() -> void:
	var button := SettingsDialog.make_button(self)
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	button.offset_left = SETTINGS_BUTTON_MARGIN
	button.offset_right = SETTINGS_BUTTON_MARGIN + SETTINGS_BUTTON_SIZE
	button.offset_top = -SETTINGS_BUTTON_MARGIN - SETTINGS_BUTTON_SIZE
	button.offset_bottom = -SETTINGS_BUTTON_MARGIN
	add_child(button)

## Eier aus dem Spielstand, neue gibt es nur ohne gespeicherte (erster Start oder nach einem Run-Ende)
func load_eggs() -> void:
	var saved_eggs: Array = SaveManager.save_data["starter_eggs"]
	if saved_eggs.is_empty():
		roll_eggs()
		return
	mons = saved_eggs.map(Helper.mon_from_egg)
	show_egg_rarities()

func roll_eggs() -> void:
	mons = Helper.generate_mons({"count": 3, "initial": true})
	SaveManager.set_starter_eggs(mons.map(Helper.egg_to_save))
	show_egg_rarities()

func show_egg_rarities() -> void:
	for i in mons.size():
		egg_rect(i).material = Monmap.egg_material(Monmap.rarity_of(mons[i]._name))

## Lässt das Ei an Position index (0-2) von oben ins Feld fallen
func drop_egg(index: int) -> void:
	get_tree().create_tween().tween_method(egg_rect(index).set_position, Vector2(0, -450), Vector2(0, 0), 0.3)

## Ei-Bild an Position index (0-2)
func egg_rect(index: int) -> TextureRect:
	return $Selection.get_node("HBoxContainer/ColorRect%d/TextureRect%d" % [index + 1, index + 1])

func select_egg(index):
	go_button.disabled = false
	# Eier nach Seltenheit der Art eingefärbt, das gewählte zusätzlich mit gelbem Umriss
	for i in mons.size():
		egg_rect(i).material = Monmap.egg_material(Monmap.rarity_of(mons[i]._name), i == index)

	selected_egg = index
	menu.visible = false
	info_panel.visible = true
	info_panel.monster = mons[index]
	# ausgebrütet gilt als gesehen (Sammlung)
	SaveManager.add_seen_mon(mons[index]._name)

func select_mon(mon):
	State.mons = [mon]
	State.starter_name = mon._name
	State.starter = mon

func _on_button_pressed() -> void:
	select_mon(mons[selected_egg])
	# Ladungen werden erst beim Aufbruch verbraucht, und nur wenn neu gewürfelt wurde (auch vor einem Neustart)
	if SaveManager.save_data["eggs_rerolled"]:
		SaveManager.spend_reroll_charges()
	get_tree().change_scene_to_file("res://script/scenes/egg_configurator/egg_configurator.tscn")

func on_select_egg(event: InputEvent, index):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Events.select_initial_mon.emit(index)

func _on_gui_input1(event: InputEvent) -> void:
	on_select_egg(event, 0)
func _on_gui_input2(event: InputEvent) -> void:
	on_select_egg(event, 1)
func _on_gui_input3(event: InputEvent) -> void:
	on_select_egg(event, 2)


func _on_pick_egg_button_pressed() -> void:
	if egg_picked_index < 4:
		title_label.text = tr("SELECTION_PICK_WARRIOR")
		drop_egg(egg_picked_index - 1)
	if egg_picked_index == 3:
		title_label.text = tr("SELECTION_TIME_TO_GO")
		reroll_button.visible = SaveManager.has_full_reroll_charges()
	if egg_picked_index == 4:
		title_label.text = tr("SELECTION_NO_MORE_EGGS")
	egg_picked_index += 1

func _on_reroll_button_pressed() -> void:
	SaveManager.save_data["eggs_rerolled"] = true
	roll_eggs()
	for i in mons.size():
		drop_egg(i)
	# die alte Wahl gilt nicht mehr
	go_button.disabled = true
	info_panel.visible = false
	menu.visible = true
