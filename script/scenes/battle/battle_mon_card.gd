class_name BattleMonCard
extends PanelContainer

## Karte eines Monsters neben dem Turn Wheel: Bild, Name, Stufe mit Seltenheits-Stern und Lebensanzeige.
## Ein Klick wählt das Monster aus, das ausgewählte Monster hat einen goldenen Rand.

## Dauer der HP-Animation, darauf wartet auch monster_scene.gd mit damage_animation_done
const HP_TWEEN_TIME := 0.3
const HEALTHY_COLOR := Color(0.07, 0.42, 0.16)
const HURT_COLOR := Color(0.88, 0.47, 0.08)
const CRITICAL_COLOR := Color(0.56, 0.05, 0.06)
## Über diesem Anteil der HP ist der Balken grün, darunter orange
const HEALTHY_SHARE := 0.8
## Unter diesem Anteil der HP ist der Balken rot
const CRITICAL_SHARE := 0.3

@export var plate: IronPlate
@export var icon: TextureRect
@export var name_label: Label
@export var level_label: Label
## Stern neben der Stufe in der Farbe der Seltenheit, Lebende Pixel wie die übrigen Icons
@export var rarity_star: TextureRect
## Übrige Züge, nur bei eigenen Monstern: Zahl mit Partikeln rechts neben dem Stern, bei 0 grau
@export var moves_badge: Control
@export var hp_bar: Control
## Schneidet den Balken ab: so behalten die Lebenden Pixel beim Schrumpfen ihren Platz
@export var hp_clip: Control
@export var hp_fill: ColorRect
@export var hp_label: Label

var mon: Monster
var selected := false

var _shown_hp := 0.0
var _hp_tween: Tween

func _ready() -> void:
	Events.refresh_ui_for_monster.connect(_animate_hp)
	Events.refresh_ui_for_monster.connect(_refresh_moves)
	Events.deal_damage_to_monster.connect(_on_mon_event.bind(_animate_hp))
	Events.monster_status_changed.connect(_on_mon_event.bind(_animate_hp))
	Events.monster_faints.connect(_on_mon_event.bind(hide))
	Events.mon_is_catched.connect(_on_mon_event.bind(hide))
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(plate.set_rim.bind(SkillDetailPopup.GOLD))
	mouse_exited.connect(_show_rim)
	hp_bar.resized.connect(_update_hp_bar)

func setup(_mon: Monster) -> void:
	mon = _mon
	Monmap.show_on(icon, mon._name, Monmap.TINY)
	name_label.text = Helper.mon_battle_name(mon)
	name_label.tooltip_text = name_label.text
	name_label.self_modulate = Helper.color_by_mon(mon)
	level_label.text = tr("BATTLE_MON_LEVEL") + " " + str(mon._level)
	var rarity := Monmap.rarity_of(mon._name)
	rarity_star.self_modulate = Monmap.RARITY_COLORS[rarity]
	rarity_star.tooltip_text = tr(Monmap.RARITY_LABELS[rarity])
	_shown_hp = _current_hp()
	_update_hp_bar()
	moves_badge.visible = State.mons.has(mon)
	moves_badge.tooltip_text = tr("BATTLE_MON_MOVES")
	moves_badge.show_number(mon._computed_moves, false, true)

## Poppt nur auf, wenn sich die Zahl geändert hat (refresh_ui_for_monster kommt für jedes Monster)
func _refresh_moves() -> void:
	if mon == null or not moves_badge.visible or moves_badge.label.text == str(mon._computed_moves):
		return
	moves_badge.show_number(mon._computed_moves, true, true)

func set_selected(value: bool) -> void:
	selected = value
	_show_rim()

func _show_rim() -> void:
	plate.set_rim(SkillDetailPopup.GOLD if selected else IronPlate.RIM)

func _on_mon_event(_mon: Monster, action: Callable) -> void:
	if _mon == mon:
		action.call()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Events.mouse_event.emit({"action": Enums.MOUSE_ACTION.SELECT_MONSTER, "mon": mon})

func _current_hp() -> float:
	return mon.hp() - mon._lost_hp

func _animate_hp() -> void:
	if mon == null or is_equal_approx(_shown_hp, _current_hp()):
		return
	if _hp_tween:
		_hp_tween.kill()
	_hp_tween = create_tween()
	_hp_tween.tween_method(_set_shown_hp, _shown_hp, _current_hp(), HP_TWEEN_TIME)

func _set_shown_hp(value: float) -> void:
	_shown_hp = value
	_update_hp_bar()

func _update_hp_bar() -> void:
	if mon == null:
		return
	var max_hp: float = mon.hp()
	var share := clampf(_shown_hp / max_hp, 0.0, 1.0) if max_hp > 0 else 0.0
	hp_clip.size = Vector2(hp_bar.size.x * share, hp_bar.size.y)
	hp_fill.size = hp_bar.size
	hp_fill.color = _hp_color(share)
	# genaue HP von Gegnern nur bei Arten, die man hat oder in diesem Run gefangen hat, sonst bleibt der Balken ohne Zahl
	if State.mons.has(mon) or State.is_mon_known(mon._name):
		hp_label.text = "%d / %d" % [roundi(_shown_hp), roundi(max_hp)]
	else:
		hp_label.text = ""

func _hp_color(share: float) -> Color:
	if share > HEALTHY_SHARE:
		return HEALTHY_COLOR
	if share >= CRITICAL_SHARE:
		return HURT_COLOR
	return CRITICAL_COLOR
