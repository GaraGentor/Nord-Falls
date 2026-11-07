extends Control

@export var mon_slot: int
@export var home_mons: bool
## Vorderansicht auch für eigene Monster, z.B. im Lager außerhalb des Kampfes
@export var show_front: bool

@export var texture_rect: TextureRect

var mon: Monster

@export var name_label: Label
@export var level_label: Label
@export var hp_bar: ProgressBar
## HP-Zahl im Balken: bei Gegnern leer, solange die Art unbekannt ist
@export var hp_label: Label
## Statuseffekte unter dem HP-Balken: Schilde, Buffs und bei Gegnern die Fangchance
@export var status_box: HBoxContainer
## Absichten, eine Zeile pro Zug, unter dem Status
@export var intent_box: VBoxContainer
## Partikel hinter der Züge-Zahl eigener Monster, laufen nur solange noch Züge übrig sind
@export var moves_particles: MovesParticlesView

@export var is_healing: bool

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Events.refresh_ui_for_monster.connect(printStuff)
	Events.deal_damage_to_monster.connect(_deal_damage)
	Events.monster_hit_with_element.connect(_show_hit_text)
	Events.monster_status_changed.connect(_on_status_changed)
	Events.monster_faints.connect(_remove_mon)
	Events.mon_is_catched.connect(_remove_mon)
	Events.intents_changed.connect(_refresh_intent)
	var mons = State.mons if home_mons else State.enemy_mons
	if mons.size() > mon_slot:
		mon = mons[mon_slot]
		visible = true
		# eigene Monster stehen mit dem Rücken zur Kamera, Gegner schauen her
		Monmap.show_on(texture_rect, mon._name, Monmap.SMALL, home_mons and not show_front)
		if home_mons and not show_front:
			# eigene Monster sitzen unten in ihrer Reihe und ragen etwas hinter die Kartenhand,
			# so wirken sie näher und größer als die Gegner; Name und HP bleiben oben sichtbar
			$AspectRatioContainer.alignment_vertical = AspectRatioContainer.ALIGNMENT_END
			$AspectRatioContainer/HBoxContainer/Info.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		name_label.text = Helper.mon_battle_name(mon)
		name_label.tooltip_text = name_label.text
		# Name in der Typfarbe, wie im Infobereich
		name_label.self_modulate = Helper.color_by_mon(mon)
		hp_bar.max_value = mon.hp()
		hp_bar.value = mon.hp()
		level_label.text = tr("BATTLE_MON_LEVEL") + " " + str(mon._level)
		_set_hp(mon.hp())
		printStuff()

func _deal_damage(_mon: Monster) -> void:
	if mon == _mon:
		printStuff()

const SUPER_EFFECTIVE_COLOR := Color(1.0, 0.55, 0.2)
const NOT_EFFECTIVE_COLOR := Color(0.6, 0.65, 0.7)

const STATUS_COLOR := Color(0.55, 0.8, 1.0)
## Sp.-Angriffe und Sp.-Schilde sind violett, physische Schilde blau: so passt man den Schild zum Angriff
const SPECIAL_COLOR := Color(0.85, 0.6, 1.0)

const ICON_ATTACK := preload("res://assets/ui/icons/sword.svg")
const ICON_S_ATTACK := preload("res://assets/ui/icons/battle/s_attack.svg")
const ICON_SHIELD := preload("res://assets/ui/icons/battle/shield.svg")
const ICON_S_SHIELD := preload("res://assets/ui/icons/battle/s_shield.svg")
const ICON_BUFF := preload("res://assets/ui/icons/battle/buff.svg")
const ICON_CATCH := preload("res://assets/ui/icons/battle/catch.svg")

## Kurznamen der Werte, die ein Buff erhöhen kann
const BUFF_STAT_KEYS := {"hp": "STAT_HP", "atk": "STAT_ATK", "def": "STAT_DEF", "s_atk": "STAT_SPA",
	"s_def": "STAT_SPD", "speed": "STAT_SPE"}

# Schwebender Schadenstext über dem Monster, bei Element-Vorteil/-Nachteil mit Hinweis und Faktor,
# vom Schild abgefangener Schaden steht mit Schild-Symbol darunter.
func _show_hit_text(_mon: Monster, damage: float, multiplier: float, blocked: float = 0.0) -> void:
	if mon != _mon:
		return
	var color = Color.WHITE
	var font_size = 36 if multiplier > 1.0 else 28
	var box := _new_row_box(true)
	if multiplier > 1.0:
		color = SUPER_EFFECTIVE_COLOR
		box.add_child(_icon_row([tr("BATTLE_SUPER_EFFECTIVE") + " x" + _format_multiplier(multiplier)], color, font_size))
	elif multiplier < 1.0:
		color = NOT_EFFECTIVE_COLOR
		box.add_child(_icon_row([tr("BATTLE_NOT_EFFECTIVE") + " x" + _format_multiplier(multiplier)], color, font_size))
	box.add_child(_icon_row(["-%d" % roundi(damage)], color, font_size))
	if blocked > 0:
		box.add_child(_icon_row([ICON_SHIELD, "-%d" % roundi(blocked)], STATUS_COLOR, 24))
	box.z_index = 10
	add_child(box)
	box.size = box.get_combined_minimum_size()
	box.position = _texture_offset() + Vector2((texture_rect.size.x - box.size.x) / 2, texture_rect.size.y * 0.2)
	var tween := box.create_tween()
	tween.set_parallel()
	tween.tween_property(box, "position:y", box.position.y - 60, 1.2)
	tween.tween_property(box, "modulate:a", 0.0, 0.6).set_delay(0.6)
	tween.chain().tween_callback(box.queue_free)

## Zeile aus Symbolen und Text: Texture2D = Symbol in der Zeilenfarbe, String = Text,
## Monster = kleines Bild des Monsters (als Ziel einer Absicht).
func _icon_row(items: Array, color: Color, font_size: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for item in items:
		if item is String:
			var label := Label.new()
			label.text = item
			label.add_theme_font_size_override("font_size", font_size)
			label.add_theme_color_override("font_color", color)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 6)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(label)
			continue
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if item is Monster:
			Monmap.show_on(icon, item._name, Monmap.TINY)
			icon.custom_minimum_size = Vector2.ONE * font_size * 1.8
		else:
			icon.texture = item
			icon.self_modulate = color
			icon.custom_minimum_size = Vector2.ONE * font_size * 1.1
		row.add_child(icon)
	return row

func _new_row_box(vertical: bool) -> BoxContainer:
	var box: BoxContainer
	if vertical:
		box = VBoxContainer.new()
	else:
		box = HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0 if vertical else 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box

func _clear_box(box: BoxContainer) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

func _format_multiplier(multiplier: float) -> String:
	return String.num(multiplier, 2)

# Status unter dem HP-Balken: bei Gegnern die Fangchance (Hypnose-Spirale),
# Schild-Symbole mit ihrem Wert, Buffs als Pfeil.
const STATUS_FONT_SIZE := 18
const CATCH_COLOR := Color(1.0, 0.85, 0.4)

func _on_status_changed(_mon: Monster) -> void:
	# Schilde und Buffs jedes Monsters können den angekündigten Schaden ändern
	_refresh_intent()
	if mon == _mon:
		_refresh_status()

func _refresh_status() -> void:
	_clear_box(status_box)
	if not home_mons:
		var chance := "%d%%" % roundi(Helper.catch_chance(mon) * 100)
		status_box.add_child(_icon_row([ICON_CATCH, chance], CATCH_COLOR, STATUS_FONT_SIZE))
	if mon._shield > 0:
		status_box.add_child(_icon_row([ICON_SHIELD, str(roundi(mon._shield))], STATUS_COLOR, STATUS_FONT_SIZE))
	if mon._s_shield > 0:
		status_box.add_child(_icon_row([ICON_S_SHIELD, str(roundi(mon._s_shield))], SPECIAL_COLOR, STATUS_FONT_SIZE))
	if mon.is_buffed():
		status_box.add_child(_icon_row([ICON_BUFF], BUFF_COLOR, STATUS_FONT_SIZE))

# Übrige Züge eigener Monster: Zahl mit Partikeln über dem Monster-Bild, poppt bei jeder Änderung auf, bei 0 grau.
const MOVES_COLOR := Color.WHITE
const MOVES_EMPTY_COLOR := Color(0.55, 0.55, 0.55)

var _moves_label: Label

func _refresh_moves() -> void:
	if _moves_label == null:
		_moves_label = Label.new()
		_moves_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_moves_label.add_theme_font_size_override("font_size", 24)
		_moves_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_moves_label.add_theme_constant_override("outline_size", 7)
		_moves_label.tooltip_text = tr("BATTLE_MON_MOVES")
		_moves_label.mouse_filter = Control.MOUSE_FILTER_PASS
		_moves_label.z_index = 6
		add_child(_moves_label)
	var text = str(mon._computed_moves)
	var changed = _moves_label.text != text
	_moves_label.text = text
	_moves_label.add_theme_color_override("font_color", MOVES_COLOR if mon._computed_moves > 0 else MOVES_EMPTY_COLOR)
	_moves_label.visible = mon.is_alive()
	if moves_particles:
		moves_particles.visible = mon.is_alive()
		moves_particles.emitting = mon.is_alive() and mon._computed_moves > 0
	_place_moves_label()
	if changed:
		_moves_label.pivot_offset = _moves_label.size / 2
		var tween := _moves_label.create_tween()
		_moves_label.scale = Vector2.ONE * 1.6
		_moves_label.modulate = Color(2, 2, 2)
		tween.set_parallel()
		tween.tween_property(_moves_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(_moves_label, "modulate", Color.WHITE, 0.35)

func _place_moves_label() -> void:
	if _moves_label == null:
		return
	_moves_label.size = _moves_label.get_combined_minimum_size()
	_moves_label.position = _texture_offset() + Vector2((texture_rect.size.x - _moves_label.size.x) / 2, -_moves_label.size.y * 0.3)
	if moves_particles:
		moves_particles.center_on(_moves_label.position + _moves_label.size / 2)

func printStuff() -> void:
	if mon:
		if home_mons:
			_refresh_moves()
		_refresh_status()
		if get_tree():
			await get_tree().create_tween().tween_method(_set_hp, hp_bar.value, mon.hp() - mon._lost_hp, 0.3).finished
		Events.damage_animation_done.emit(mon)

func _set_hp(value: float) -> void:
	hp_bar.value = value
	# genaue HP von Gegnern nur bei Arten, die man hat oder in diesem Run gefangen hat, sonst bleibt der Balken ohne Zahl
	if home_mons or State.is_mon_known(mon._name):
		hp_label.text = "%d / %d" % [roundi(value), roundi(hp_bar.max_value)]
	else:
		hp_label.text = ""

func _remove_mon(_mon) -> void:
	if _mon == mon:
		visible = false


## Drag & Drop: Skill-Karten können auf passende Ziele gezogen werden
func _can_drop_data(_at_position: Vector2, data) -> bool:
	if not visible or mon == null or not mon.is_alive():
		return false
	if not (data is Dictionary and data.get("type") == "skill_card"):
		return false
	match data.skill.get("target", Enums.CARD_TARGETS.SINGLE_ENEMY):
		Enums.CARD_TARGETS.SINGLE_ENEMY, Enums.CARD_TARGETS.TEAM_ENEMY:
			return not home_mons
		Enums.CARD_TARGETS.SINGLE_FRIEND, Enums.CARD_TARGETS.TEAM_FRIEND:
			return home_mons
	return false

func _drop_data(_at_position: Vector2, data) -> void:
	modulate = Color.WHITE
	Events.mouse_event.emit({"action": Enums.MOUSE_ACTION.SELECT_MONSTER, "mon": mon})
	Events.mouse_event.emit({"action": Enums.MOUSE_ACTION.PLAY_CARD, "skill": data.skill, "mon": mon})

func _process(_delta: float) -> void:
	# gültiges Ziel unter einer gezogenen Karte hervorheben
	var drag_data = get_viewport().gui_get_drag_data() if get_viewport().gui_is_dragging() else null
	var hovered = drag_data != null and get_global_rect().has_point(get_global_mouse_position()) \
		and _can_drop_data(Vector2.ZERO, drag_data)
	modulate = Color(1.3, 1.3, 1.0) if hovered else Color.WHITE
	_update_drag_preview(drag_data)
	# das Layout kann sich verschieben (z. B. wenn ein Monster ausscheidet)
	_place_moves_label()

# Während eine Angriffskarte gezogen wird, zeigt jedes mögliche Ziel seinen Element-Faktor an.
var _preview_label: Label

func _update_drag_preview(drag_data) -> void:
	var show_preview = drag_data != null and not home_mons and _can_drop_data(Vector2.ZERO, drag_data) \
		and Skills.is_damage_skill(drag_data.skill)
	if not show_preview:
		if _preview_label:
			_preview_label.visible = false
		return
	var multiplier = Skills.element_multiplier(drag_data.skill.nature, mon._type)
	if _preview_label == null:
		_preview_label = Label.new()
		_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_preview_label.add_theme_font_size_override("font_size", 26)
		_preview_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_preview_label.add_theme_constant_override("outline_size", 8)
		_preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_preview_label.z_index = 10
		add_child(_preview_label)
	_preview_label.text = "x" + _format_multiplier(multiplier)
	var color = Color.WHITE
	if multiplier > 1.0:
		color = SUPER_EFFECTIVE_COLOR
	elif multiplier < 1.0:
		color = NOT_EFFECTIVE_COLOR
	_preview_label.add_theme_color_override("font_color", color)
	_preview_label.visible = true
	_preview_label.position = _texture_offset() + Vector2((texture_rect.size.x - _preview_label.get_minimum_size().x) / 2, 0)

# Absichten unter dem Status, als Symbole:
# Gegner zeigen ihren geplanten Zug (Schwert = Angriff, Stern = Sp.-Angriff, Schild, Buff-Pfeil, dahinter das Bild des Ziels),
# eigene Monster den Schaden, der im nächsten Zug der Gegner auf sie zukommt, mit und ohne Schild (Schwert -12, Schild -4).
const INTENT_COLOR := Color(1.0, 0.45, 0.4)
const INTENT_BLOCKED_COLOR := Color(0.55, 0.8, 1.0)
const BUFF_COLOR := Color(0.55, 1.0, 0.55)
const INTENT_FONT_SIZE := 18

func _refresh_intent() -> void:
	if mon == null or not is_inside_tree():
		return
	_clear_box(intent_box)
	for row in (_own_intent_rows() if home_mons else _enemy_intent_rows()):
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		intent_box.add_child(row)
	intent_box.visible = mon.is_alive() and intent_box.get_child_count() > 0

func _own_intent_rows() -> Array:
	var incoming = Skills.incoming_damage(mon, State.enemy_mons)
	if incoming.full <= 0:
		return []
	var full = roundi(incoming.full)
	var after = roundi(incoming.after)
	# Blau, wenn der Schild etwas abfängt: so sieht man direkt, dass sich Blocken gelohnt hat
	if after < full:
		return [_icon_row([ICON_ATTACK, "-%d" % full, ICON_SHIELD, "-%d" % after], INTENT_BLOCKED_COLOR, INTENT_FONT_SIZE)]
	return [_icon_row([ICON_ATTACK, "-%d" % full], INTENT_COLOR, INTENT_FONT_SIZE)]

func _enemy_intent_rows() -> Array:
	var rows = []
	for action in mon._intent:
		var target: Monster = action.target
		if target == null:
			continue
		var skill: Dictionary = action.skill
		var physical = Skills.is_physical(skill)
		# Flächen-Skills zeigen alle Monster, die sie treffen
		var targets = [target]
		if Skills.targets_team(skill):
			var side = State.mons if State.mons.has(target) else State.enemy_mons
			targets = side.filter(func(m: Monster): return m.is_alive())
		if Skills.is_damage_skill(skill):
			var items = [ICON_ATTACK if physical else ICON_S_ATTACK, "-%d" % roundi(Skills.calc_damage(mon, target, skill))]
			rows.append(_icon_row(items + targets, INTENT_COLOR if physical else SPECIAL_COLOR, INTENT_FONT_SIZE))
		elif skill.get("effect", "") == "buff":
			var stat = tr(BUFF_STAT_KEYS.get(skill.buff_stat, "")).trim_suffix(":")
			rows.append(_icon_row([ICON_BUFF, "+%d%% %s" % [roundi(skill.value), stat]] + targets, BUFF_COLOR, INTENT_FONT_SIZE))
		else:
			# gleiche Rechnung wie Skills.add_shield, Wert kommt vom Wirker
			var def = mon.defense() if physical else mon.s_defense()
			var amount = ceilf(def * skill.value / 100)
			rows.append(_icon_row([ICON_SHIELD if physical else ICON_S_SHIELD, "+%d" % amount] + targets,
				INTENT_BLOCKED_COLOR if physical else SPECIAL_COLOR, INTENT_FONT_SIZE))
	return rows

func _on_gui_input(event: InputEvent) -> void:
	print(event)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			print("Linke Maustaste losgelassen!")
			# Events.call_skill_card.emit({"action": selected_skill})
			Events.mouse_event.emit({"action": Enums.MOUSE_ACTION.SELECT_MONSTER, "mon": mon})

# Position des Monster-Bilds relativ zu dieser Szene (es liegt in einem VBoxContainer).
func _texture_offset() -> Vector2:
	return texture_rect.global_position - global_position
