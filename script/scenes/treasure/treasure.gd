extends ChestRewardDialog

## Schatz: die Truhe öffnet sich nur mit einem Schlüssel. Darin liegen Häufchen Monster Essenz,
## die einzeln in die Tasche gezogen werden. Ohne Schlüssel oder wenn man ihn behalten will, geht man weiter.
## Die Trank-Karte nutzt der Shop.

signal _opened

const ACCENT := Color(0.74, 0.75, 0.29)

const PILES_MIN := 2
const PILES_MAX := 4
## Essenz pro Häufchen: Grundbetrag plus Zuschlag pro Biom-Tiefe (State.map_level)
const PILE_GOLD_MIN := 10
const PILE_GOLD_MAX := 25
const PILE_GOLD_PER_DEPTH := 5

const ELEMENTS := [Enums.MON_TYPES.EARTH, Enums.MON_TYPES.AIR, Enums.MON_TYPES.WATER, Enums.MON_TYPES.FIRE]

const ESSENCE_ICON = preload("res://assets/ui/icons/monster_essence.svg")
const KEY_ICON = preload("res://assets/ui/icons/key.svg")
const FLASK_TEXTURE = preload("res://assets/ui/shop/potion_flask.svg")
const LIQUID_TEXTURE = preload("res://assets/ui/shop/potion_liquid.svg")
const PROPS_MATERIAL = preload("res://script/scenes/jailer/jailer_props_material.tres")

var _buttons: HBoxContainer

func _ready() -> void:
	use_chest_layout()
	set_accent(ACCENT)
	set_title(tr("TREASURE_LOCKED"))
	set_drag_hint("TREASURE_KEY_HINT" if State.keys > 0 else "TREASURE_NO_KEY")
	show_fixed_targets([], true)
	for i in randi_range(PILES_MIN, PILES_MAX):
		var gold := randi_range(PILE_GOLD_MIN, PILE_GOLD_MAX) + State.map_level * PILE_GOLD_PER_DEPTH
		add_bag_card(tr("TREASURE_GOLD"), Helper.me_text(gold), texture_icon(ESSENCE_ICON), _on_gold_taken.bind(gold))
	_build_buttons()
	play_chest_intro()

func _build_buttons() -> void:
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 16)
	var open_button := plate_button(tr("TREASURE_OPEN").format({"keys": State.keys}))
	open_button.icon = KEY_ICON
	open_button.add_theme_constant_override("icon_max_width", 28)
	open_button.disabled = State.keys <= 0
	open_button.pressed.connect(_open)
	_buttons.add_child(open_button)
	var leave_button := plate_button(tr("TREASURE_LEAVE"))
	leave_button.pressed.connect(close)
	_buttons.add_child(leave_button)
	add_footer(_buttons)

func _open() -> void:
	State.keys -= 1
	_buttons.queue_free()
	set_title(tr("TREASURE_CHOOSE"))
	set_drag_hint("TREASURE_HINT")
	_opened.emit()

func _wait_before_burst() -> void:
	await _opened

func _on_gold_taken(gold: int) -> void:
	State.ep += gold

## Der Dialog bleibt offen, bis alle Häufchen in der Tasche sind
func _taken(card: RewardCard) -> void:
	_loot.erase(card)
	card.queue_free()
	if _loot.is_empty():
		close()

# ── Element-Trank ─────────────────────────

## Trank-Karte: wird auf ein Monster gezogen, dem das Element noch fehlt.
## Die Liste wird erst beim Ziehen bestimmt, damit sie im Shop nach jedem Kauf stimmt.
## Was aus dem Monster wird, zeigt der Typ am Ziel (RewardDialog.show_element_preview).
static func add_potion_card(dialog: RewardDialog, element: int) -> RewardDialog.RewardCard:
	var element_name = dialog.tr(ColorMap.get_combo(element).label)
	var text = dialog.tr("TREASURE_POTION_DESC").format({"element": element_name})
	var potion_title = dialog.tr("TREASURE_POTION").format({"element": element_name})
	var give := func(mon: Monster):
		mon.gain_element(element)
	return dialog.add_mon_card(potion_title, text, potion_art(element), dialog.tr("TREASURE_POTION_CHOOSE_MON"), func(): return mons_without(element), give, Callable(), {"element": element})

static func mons_without(element: int) -> Array:
	return State.mons.filter(func(mon): return not ColorMap.has_element(mon._type, element))

## Flasche im Pixel-Look, die Flüssigkeit hat die Farbe des Elements. Glas und Korken bleiben ungefärbt.
static func potion_art(element: int) -> Control:
	var liquid := texture_icon(LIQUID_TEXTURE)
	liquid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var liquid_material: ShaderMaterial = PROPS_MATERIAL.duplicate()
	liquid_material.set_shader_parameter("tint_color", Helper.color_by_type(element))
	liquid.material = liquid_material
	var flask := texture_icon(FLASK_TEXTURE)
	flask.material = PROPS_MATERIAL
	flask.add_child(liquid)
	return flask
