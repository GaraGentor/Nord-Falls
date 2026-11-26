extends RewardDialog

## Ereignis Auseinandersetzung: Ein Trupp Monster versperrt den Weg, deren Elemente gegen das aktuelle Biom
## stark sind (Feuer-Biom -> Wasser-Monster, Map.counter_elements). Man geht weiter oder stellt sich dem Kampf.
## Je tiefer das Biom, desto mehr Gegner (Map.roll_confrontation_enemies). Der Kampf zählt wie ein normaler Kampf.
## Aufbau wie das Glücksrad: Panel über der Kartenfläche, Titel und Anleitung oben, darunter die Elemente und Knöpfe.

const ACCENT := Color(0.75, 0.25, 0.2)
const BATTLE_SCENE := "res://script/scenes/battle/battle.tscn"
const EVENT_ICON := preload("res://assets/ui/icons/fist.svg")
const EVENT_ICON_SIZE := Vector2(96, 96)

var _enemies: Array[Monster] = []

func _ready() -> void:
	use_map_layout()
	set_accent(ACCENT)
	set_title(tr("EVENT_CONFRONTATION_TITLE"))
	# schon jetzt gewürfelt, damit Anzahl und Elemente im Text stimmen
	_enemies = Map.roll_confrontation_enemies()
	set_drag_hint(tr("EVENT_CONFRONTATION_DESC").format({"count": _enemies.size()}))
	# keine Preise und Ziele, nur Elemente und Knöpfe
	_columns.visible = false

	var icon := texture_icon(EVENT_ICON, ACCENT.lightened(0.3))
	icon.custom_minimum_size = EVENT_ICON_SIZE
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_footer(icon)

	var elements := HBoxContainer.new()
	elements.alignment = BoxContainer.ALIGNMENT_CENTER
	elements.add_theme_constant_override("separation", 8)
	var caption := Label.new()
	caption.theme = LABEL_THEME
	caption.text = tr("EVENT_CONFRONTATION_ELEMENTS")
	elements.add_child(caption)
	for element in _enemy_elements():
		add_element_chip(elements, element)
	add_footer(elements)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	var leave := plate_button(tr("EVENT_CONFRONTATION_LEAVE"))
	leave.pressed.connect(close)
	buttons.add_child(leave)
	var fight := plate_button(tr("EVENT_CONFRONTATION_FIGHT"))
	fight.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
	fight.pressed.connect(_fight)
	buttons.add_child(fight)
	add_footer(buttons)

## Grundelemente der Gegner, jedes einmal
func _enemy_elements() -> Array:
	var result := []
	for element in Enums.MON_TYPES.values():
		if _enemies.any(func(mon: Monster): return mon._type & element):
			result.append(element)
	return result

## Die gewürfelten Gegner holt sich der Kampf ab (battle.gd _take_enemies), Boss-Relikte gibt es keine
func _fight() -> void:
	Map.pending_enemies = _enemies
	Map.pending_relics = []
	SceneLoader.change_scene(BATTLE_SCENE)
