extends ChestRewardDialog

## Schatz: die Truhe öffnet sich nur mit einem Schlüssel. Darin liegen Häufchen Monster Essenz,
## die einzeln in die Tasche gezogen werden, manchmal auch ein Element-Trank. Der fällt nach der Kiste
## aus der Tasche (potion_reward.gd) und wird dort einem Monster gegeben.
## Ohne Schlüssel oder wenn man ihn behalten will, geht man weiter.
## Die Trank-Karte nutzen Shop und Trank-Belohnung.

signal _opened

const ACCENT := Color(0.74, 0.75, 0.29)

const PILES_MIN := 2
const PILES_MAX := 4
## Essenz pro Häufchen: Grundbetrag plus Zuschlag pro Biom-Tiefe (State.map_level)
const PILE_GOLD_MIN := 10
const PILE_GOLD_MAX := 25
const PILE_GOLD_PER_DEPTH := 5
## so oft liegt zusätzlich ein Element-Trank mit zufälligem Element darin (leicht gewichtet, siehe pick_potion_element).
## Gezielt ein bestimmtes Element gibt es nur im Shop.
const POTION_CHANCE := 0.35

const ELEMENTS := [Enums.MON_TYPES.EARTH, Enums.MON_TYPES.AIR, Enums.MON_TYPES.WATER, Enums.MON_TYPES.FIRE]

const ESSENCE_ICON = preload("res://assets/ui/icons/monster_essence.svg")
const KEY_ICON = preload("res://assets/ui/icons/key.svg")
const FLASK_TEXTURE = preload("res://assets/ui/shop/potion_flask.svg")
const LIQUID_TEXTURE = preload("res://assets/ui/shop/potion_liquid.svg")
const PROPS_MATERIAL = preload("res://script/scenes/jailer/jailer_props_material.tres")
## Belohnung beim Aufstieg in ein Kombi-Element durch einen Trank
const ElementGainOverlayScript = preload("res://script/ui/element_gain_overlay/element_gain_overlay.gd")

var _buttons: HBoxContainer
var _is_open := false

func _ready() -> void:
	use_chest_layout()
	set_accent(ACCENT)
	set_title(tr("TREASURE_LOCKED"))
	set_drag_hint("TREASURE_KEY_HINT" if State.keys > 0 else "TREASURE_NO_KEY")
	show_fixed_targets([], true)
	# nur Elemente, die noch jemand im Team trinken kann
	var drinkable := ELEMENTS.filter(func(element): return not mons_without(element).is_empty())
	var with_potion := not drinkable.is_empty() and randf() < POTION_CHANCE
	# der Teppich hat höchstens PILES_MAX Liegeplätze, der Trank nimmt einen davon
	for i in randi_range(PILES_MIN, PILES_MAX - (1 if with_potion else 0)):
		var gold := randi_range(PILE_GOLD_MIN, PILE_GOLD_MAX) + State.map_level * PILE_GOLD_PER_DEPTH
		add_bag_card(tr("TREASURE_GOLD"), Helper.me_text(gold), texture_icon(ESSENCE_ICON), _on_gold_taken.bind(gold))
	if with_potion:
		var element: int = pick_potion_element(drinkable)
		# nach der Kiste fällt er wie eine Trophäe aus der Tasche auf den Teppich (world_map.gd show_pending_rewards)
		add_bag_card(potion_title(self, element), tr("TREASURE_POTION_BAG_DESC"), potion_art(element), func(): State.pending_potions.append(element))
	_build_buttons()
	play_chest_intro()
	_buttons.add_to_group("tut_treasure_buttons")
	Tutorial.trigger("treasure")

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
	_is_open = true
	_opened.emit()

func _wait_before_burst() -> void:
	# schon offen, wenn der Schlüssel benutzt wurde, bevor die Kiste fertig aufgesprungen ist: dann kommt kein Signal mehr
	if not _is_open:
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
	var give := func(mon: Monster):
		var old_type: int = mon._type
		mon.gain_element(element)
		Skills.announce_awakened(mon, old_type)
		# Aufstieg in ein Kombi-Element: das Monster lernt dessen Aufstiegs-Skill (läuft für sich, auch wenn der Dialog schließt)
		ElementGainOverlayScript.reward(mon, old_type)
	return dialog.add_mon_card(potion_title(dialog, element), text, potion_art(element), dialog.tr("TREASURE_POTION_CHOOSE_MON"), func(): return mons_without(element), give, Callable(), {"element": element})

static func potion_title(dialog: Node, element: int) -> String:
	return dialog.tr("TREASURE_POTION").format({"element": dialog.tr(ColorMap.get_combo(element).label)})

## Gewicht eines Trank-Elements, das einem Monster im Team für einen seiner Skills fehlt
## (weckt eine schlummernde Attacke bzw. macht eine unspielbare spielbar). Alle anderen zählen 1.
const NEEDED_POTION_WEIGHT := 2.0

## Zufälliges Trank-Element, leicht bevorzugt die, die eine Attacke im Team voranbringen
static func pick_potion_element(elements: Array) -> int:
	var weights := elements.map(func(element):
		var needed: bool = mons_without(element).any(func(mon: Monster):
			return mon._skills.any(func(skill): return Skills.missing_elements(mon, skill).has(element)))
		return NEEDED_POTION_WEIGHT if needed else 1.0)
	var total: float = weights.reduce(func(sum, weight): return sum + weight, 0.0)
	var roll := randf() * total
	for i in elements.size():
		roll -= weights[i]
		if roll <= 0.0:
			return elements[i]
	return elements.back()

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
