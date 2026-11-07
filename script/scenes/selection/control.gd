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

var selected_egg: int = 0

func _ready() -> void:
	load_eggs()
	biome_path.show_path(Map.load_biome_path())
	# display_mons()
	Events.select_initial_mon.connect(select_egg)
	# Events.select_initial_mon.emit(0)

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
	info_panel.visible = true
	info_panel.monster = mons[index]

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
