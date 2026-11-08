class_name TutorialPanel
extends ScrollContainer

## Startbildschirm: rechts, solange noch kein Ei gewählt ist, erklärt eine scrollbare Liste das Spiel.
## Jeder Abschnitt steht auf einer Eisenplatte: Bild, Überschrift (TUTORIAL_<ID>_TITLE) und Text (TUTORIAL_<ID>).
## Seltenheit und Karte zeigen zusätzlich die Eier bzw. die Feld-Symbole.

const PROPS_MATERIAL = preload("res://script/scenes/jailer/jailer_props_material.tres")
const EGG_TEXTURE = preload("res://assets/ui/eggs/common_1.png")
const GOLD := SkillDetailPopup.GOLD
const ICON_SIZE := Vector2(56, 56)
const SMALL_ICON_SIZE := Vector2(34, 34)
const HEADER_FONT_SIZE := 24
const TITLE_FONT_SIZE := 19
const TEXT_FONT_SIZE := 15
const SMALL_FONT_SIZE := 13

## Reihenfolge der Abschnitte; icon "egg" ist ein gewöhnliches Ei
const SECTIONS := [
	{"id": "GOAL", "icon": "res://assets/ui/map/node_boss.svg"},
	{"id": "START", "icon": "egg"},
	{"id": "RARITY", "icon": "res://assets/ui/icons/rarity_star.svg"},
	{"id": "MAP", "icon": "res://assets/ui/icons/parchment.svg"},
	{"id": "BATTLE", "icon": "res://assets/ui/icons/sword.svg"},
	{"id": "ELEMENTS", "icon": "res://assets/ui/icons/sparkle.svg"},
	{"id": "CATCH", "icon": "res://assets/ui/icons/battle/hypnosis_button.svg"},
	{"id": "TEAM", "icon": "res://assets/ui/icons/battle/catch.svg"},
	{"id": "EGG_MOVES", "icon": "egg"},
	{"id": "STRONGER", "icon": "res://assets/ui/map/node_gem.svg"},
	{"id": "RELICS", "icon": "res://assets/ui/rewards/box.png"},
	{"id": "ESSENCE", "icon": "res://assets/ui/icons/monster_essence.svg"},
	{"id": "LOOT", "icon": "res://assets/ui/icons/bag.svg"},
]
## Felder der Karte, Bild: res://assets/ui/map/node_<id>.svg, Name: MAP_NODE_<ID>
const MAP_NODES := ["combat", "boss", "camp", "shop", "trainer", "jailer", "event", "treasure", "gem"]

func _ready() -> void:
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	margin.add_child(list)

	var header := _label(tr("TUTORIAL_TITLE"), HEADER_FONT_SIZE, GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(header)
	var hint := _label(tr("TUTORIAL_SCROLL_HINT"), SMALL_FONT_SIZE, IronPlate.TEXT_COLOR)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(hint)
	for section: Dictionary in SECTIONS:
		list.add_child(_section(section))
	# nur die ScrollContainer selbst nimmt Mausrad und Ziehen an
	RewardDialog.ignore_mouse_below(margin)
	margin.mouse_filter = MOUSE_FILTER_IGNORE

func _section(section: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	IronPlate.frame(panel, row, 12, 10)
	var icon := _icon(section.icon, ICON_SIZE)
	icon.size_flags_vertical = SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 4)
	row.add_child(text_box)
	text_box.add_child(_label(tr("TUTORIAL_%s_TITLE" % section.id), TITLE_FONT_SIZE, GOLD))
	text_box.add_child(_label(tr("TUTORIAL_%s" % section.id), TEXT_FONT_SIZE, IronPlate.TEXT_COLOR))
	match section.id:
		"RARITY":
			text_box.add_child(_rarity_row())
		"MAP":
			text_box.add_child(_map_legend())
	return panel

## Ein Ei pro Seltenheit, eingefärbt wie bei der Auswahl, darunter der Name in der Farbe der Seltenheit
func _rarity_row() -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 6)
	for rarity: int in Monmap.RARITY_COLORS:
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 0)
		var egg := RewardDialog.texture_icon(EGG_TEXTURE)
		egg.material = Monmap.egg_material(rarity)
		egg.custom_minimum_size = SMALL_ICON_SIZE
		entry.add_child(egg)
		var label := _label(tr(Monmap.RARITY_LABELS[rarity]), SMALL_FONT_SIZE, Monmap.RARITY_COLORS[rarity])
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		entry.add_child(label)
		row.add_child(entry)
	return row

## Feld-Symbole der Karte mit ihren Namen, zweispaltig
func _map_legend() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	for node: String in MAP_NODES:
		var entry := HBoxContainer.new()
		entry.size_flags_horizontal = SIZE_EXPAND_FILL
		entry.add_theme_constant_override("separation", 6)
		entry.add_child(_icon("res://assets/ui/map/node_%s.svg" % node, SMALL_ICON_SIZE))
		var label := _label(tr("MAP_NODE_%s" % node.to_upper()), SMALL_FONT_SIZE, IronPlate.TEXT_COLOR)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		entry.add_child(label)
		grid.add_child(entry)
	return grid

func _icon(path: String, icon_size: Vector2) -> Control:
	var icon: Control
	if path == "egg":
		icon = RewardDialog.texture_icon(EGG_TEXTURE)
		icon.material = Monmap.egg_material(Enums.MON_RARITY.COMMON)
	else:
		icon = RewardDialog.texture_icon(load(path))
		icon.material = PROPS_MATERIAL
	icon.custom_minimum_size = icon_size
	return icon

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
