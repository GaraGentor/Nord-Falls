extends VBoxContainer

## Monster im Lager: Name, Stufe und Lebensanzeige auf einer Eisenplatte über dem Bild, ohne Kampfwerte.

@export var name_label: Label
@export var level_label: Label
@export var hp_bar: ProgressBar
@export var hp_label: Label
@export var texture_rect: TextureRect

var mon: Monster

func _ready() -> void:
	Events.deal_damage_to_monster.connect(_on_hp_changed)
	name_label.text = Helper.mon_battle_name(mon)
	# aufgehellt wie in der Team-Leiste, sonst sind dunkle Farben auf der Eisenplatte kaum lesbar
	name_label.self_modulate = Helper.color_by_mon(mon).lightened(0.4)
	level_label.text = tr("BATTLE_MON_LEVEL") + " " + str(mon._level)
	Monmap.show_on(texture_rect, mon._name, Monmap.SMALL)
	hp_bar.max_value = mon.hp()
	_show_hp()

func _on_hp_changed(changed: Monster) -> void:
	if changed != mon:
		return
	_show_hp()
	# Monster._lost_hp wartet nach jeder Änderung auf dieses Signal
	Events.damage_animation_done.emit.call_deferred(mon)

func _show_hp() -> void:
	var hp_left: float = mon.hp() - mon._lost_hp
	hp_bar.value = hp_left
	hp_label.text = "%d / %d" % [roundi(hp_left), roundi(hp_bar.max_value)]
