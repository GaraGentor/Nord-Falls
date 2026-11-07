class_name OpenBag
extends Control

## Offene Tasche von vorne: Rückwand, darin ein paar Gegenstände, Vorderseite mit Plakette.
## Reine Anzeige (Kerkermeister: Boss Tränen, Trainer: Essenz, Laden und Level-Up: Geld),
## Eingaben behandelt der Besitzer.

const BACK_TEXTURE = preload("res://assets/ui/jailer/bag_back.svg")
const FRONT_TEXTURE = preload("res://assets/ui/jailer/bag_front.svg")
const PROPS_MATERIAL = preload("res://script/scenes/jailer/jailer_props_material.tres")
const PIXEL_FONT = preload("res://script/ui/fonts/pxelfont/PixelifySans-VariableFont_wght.ttf")
## sichtbare Gegenstände: Mitte als Anteil der Taschengröße und Neigung in Grad, hinten zuerst
const SPOTS := [[0.5, 0.2, 0.0], [0.27, 0.25, -18.0], [0.73, 0.25, 18.0], [0.38, 0.32, -7.0], [0.63, 0.32, 8.0]]
const PLAQUE_CENTER := Vector2(0.5, 0.73)
const PLAQUE_SIZE_SHARE := Vector2(0.5, 0.3)
const NO_OUTLINE := Color(1, 1, 0, 0)

## Text auf der Plakette
var label: Label
var _item_texture: Texture2D
var _item_size: Vector2
var _items: Control
## eigenes Material beider Taschenteile, es trägt den Umriss (set_gold)
var _outline_material: ShaderMaterial

func _init(bag_size: Vector2, item_texture: Texture2D, item_size: Vector2, font_size: int) -> void:
	_item_texture = item_texture
	_item_size = item_size
	custom_minimum_size = bag_size
	size = bag_size
	mouse_filter = MOUSE_FILTER_IGNORE
	_outline_material = PROPS_MATERIAL.duplicate()
	add_child(_layer(BACK_TEXTURE))
	_items = Control.new()
	_items.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_items)
	add_child(_layer(FRONT_TEXTURE))
	label = Label.new()
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.size = bag_size * PLAQUE_SIZE_SHARE
	label.position = bag_size * PLAQUE_CENTER - label.size / 2
	add_child(label)

func _layer(texture: Texture2D) -> TextureRect:
	var layer := RewardDialog.texture_icon(texture) as TextureRect
	layer.size = custom_minimum_size
	layer.material = _outline_material
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	return layer

## Goldener Umriss: die Tasche ist das Ziel der Ware in der Hand
func set_gold(gold: bool) -> void:
	_outline_material.set_shader_parameter("outline_color", SkillDetailPopup.GOLD if gold else NO_OUTLINE)

## So viele Gegenstände schauen oben heraus (höchstens SPOTS.size())
func show_items(count: int) -> void:
	for item in _items.get_children():
		_items.remove_child(item)
		item.queue_free()
	for spot in SPOTS.slice(0, clampi(count, 0, SPOTS.size())):
		var item := RewardDialog.texture_icon(_item_texture)
		item.mouse_filter = MOUSE_FILTER_IGNORE
		item.material = PROPS_MATERIAL
		item.size = _item_size
		item.pivot_offset = _item_size / 2
		item.position = Vector2(spot[0], spot[1]) * custom_minimum_size - _item_size / 2
		item.rotation_degrees = spot[2]
		_items.add_child(item)
