extends ChestRewardDialog

## Trank aus einer Schatzkiste: nachdem die Kiste zu ist, springt wie bei den Trophäen die Tasche aus dem Karten-Header auf,
## der Trank fällt auf den Teppich und wird von dort auf ein Monster gezogen, dem das Element noch fehlt.
## Die Monster-Ziele zeigen ihren Typ und beim Ziehen, was daraus wird. Siehe world_map.gd show_pending_rewards.

const Treasure = preload("res://script/scenes/treasure/treasure.gd")

const ACCENT := Treasure.ACCENT

## Element des Tranks, vor add_child setzen
var element: int

func _ready() -> void:
	# dieselbe Tasche wie oben links im Karten-Header: dort ist der Trank hineingewandert
	use_chest_layout(BAG_ICON)
	_chest.material = OpenBag.PROPS_MATERIAL
	set_accent(ACCENT)
	set_title(tr("POTION_REWARD_TITLE"))
	set_drag_hint("TREASURE_POTION_CHOOSE_MON")
	show_fixed_targets(State.mons, false)
	show_element_chips()
	Treasure.add_potion_card(self, element)
	play_chest_intro()
