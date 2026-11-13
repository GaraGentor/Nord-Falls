extends Control

@export var mon_slot: int
@export var home_mons: bool
## Vorderansicht auch für eigene Monster, z.B. im Lager außerhalb des Kampfes
@export var show_front: bool

@export var texture_rect: TextureRect

var mon: Monster

## Statuseffekte über dem Monster: Schilde, Buffs und bei Gegnern die Fangchance
@export var status_box: HFlowContainer
## Slots über dem Status: bei Gegnern die Absichten, bei eigenen Monstern die eingehenden Angriffe
@export var intent_box: HFlowContainer

@export var is_healing: bool

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Events.refresh_ui_for_monster.connect(printStuff)
	Events.deal_damage_to_monster.connect(_deal_damage)
	Events.monster_hit_with_element.connect(_show_hit_text)
	Events.monster_status_changed.connect(_on_status_changed)
	Events.monster_effect_text.connect(_show_effect_text)
	Events.monster_faints.connect(_remove_mon)
	Events.mon_is_catched.connect(_remove_mon)
	Events.intents_changed.connect(_refresh_intent)
	Events.skill_vfx.connect(_play_skill_vfx)
	Events.status_vfx.connect(_play_status_vfx)
	var mons = State.mons if home_mons else State.enemy_mons
	if mons.size() > mon_slot:
		mon = mons[mon_slot]
		visible = true
		# eigene Monster stehen mit dem Rücken zur Kamera, Gegner schauen her
		Monmap.show_on(texture_rect, mon._name, Monmap.SMALL, home_mons and not show_front)
		printStuff()

func _deal_damage(_mon: Monster) -> void:
	if mon == _mon:
		printStuff()

const BattleVfxScript := preload("res://script/scenes/battle/battle_vfx.gd")
const BattleVfxLayer := preload("res://script/scenes/battle/battle_vfx_layer.gd")
## kurz nach dem Zusammenzucken des Angreifers, damit Angriff und Treffer nacheinander wirken
const VFX_HIT_DELAY := 0.08

# Effekte am Ziel eines Skills: physische Angriffe als Hieb in der Elementfarbe, magische je Element
# (Feuer-Explosion, Wasser-Spritzer, Steinbrocken, Windwirbel, bei Kombi-Elementen deren eigener Effekt wie Dampfwolke,
# Blitz, Lava oder Eissplitter), Schildtreffer, wenn der Schild etwas abfängt, neue Schilde (physisch/magisch) und Buffs.
# Physische Kombi-Treffer zeigen zum Hieb auch den Kombi-Effekt. Schwächungen, Verstärkungen und Heilungen ohne eigene
# Karte kommen über Events.status_vfx (_play_status_vfx).
func _play_skill_vfx(_mon: Monster, skill: Dictionary, blocked: float) -> void:
	if mon != _mon or not is_inside_tree() or Skills.is_passive(skill):
		return
	var physical := Skills.is_physical(skill)
	if Skills.is_damage_skill(skill):
		if physical:
			var accent := Color(ColorMap.get_combo(skill.nature).get("color", "#FFFFFF"))
			_spawn_vfx(BattleVfxScript.Kind.SLASH, accent, VFX_HIT_DELAY)
			if Map.count_elements(skill.nature) > 1:
				for kind in BattleVfxScript.element_kinds(skill.nature):
					_spawn_vfx(kind, Color.WHITE, VFX_HIT_DELAY + 0.1)
		else:
			for kind in BattleVfxScript.element_kinds(skill.nature):
				_spawn_vfx(kind, Color.WHITE, VFX_HIT_DELAY)
		if blocked > 0:
			_spawn_vfx(BattleVfxScript.Kind.SHIELD_HIT if physical else BattleVfxScript.Kind.S_SHIELD_HIT, Color.WHITE, VFX_HIT_DELAY)
	elif skill.get("effect", "") == "buff":
		_spawn_vfx(BattleVfxScript.Kind.BUFF)
	else:
		_spawn_vfx(BattleVfxScript.Kind.SHIELD if physical else BattleVfxScript.Kind.S_SHIELD)

func _play_status_vfx(_mon: Monster, kind: String) -> void:
	if mon != _mon or not is_inside_tree():
		return
	match kind:
		"buff": _spawn_vfx(BattleVfxScript.Kind.BUFF, Color.WHITE, VFX_HIT_DELAY)
		"debuff": _spawn_vfx(BattleVfxScript.Kind.DEBUFF, Color.WHITE, VFX_HIT_DELAY)
		"heal": _spawn_vfx(BattleVfxScript.Kind.HEAL, Color.WHITE, VFX_HIT_DELAY)

## Effekte laufen auf einer gemeinsamen Bühne über dem Monsterbild, mit "Lebende Pixel"-Shader (battle_vfx_layer.gd)
func _spawn_vfx(kind: int, accent := Color.WHITE, delay := 0.0) -> void:
	BattleVfxLayer.for_target(self, texture_rect).play(kind, accent, delay)

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

# Schwebender Hinweis der Element-Effekte ("Gift -12", "Betäubt!", "Ausbruch!"), etwas höher als der Schadenstext,
# damit sich beide nicht überdecken.
func _show_effect_text(_mon: Monster, text: String, color: Color) -> void:
	if mon != _mon or not is_inside_tree():
		return
	var row := _icon_row([text], color, 24)
	row.z_index = 10
	add_child(row)
	row.size = row.get_combined_minimum_size()
	row.position = _texture_offset() + Vector2((texture_rect.size.x - row.size.x) / 2, 0)
	var tween := row.create_tween()
	tween.set_parallel()
	tween.tween_property(row, "position:y", row.position.y - 50, 1.4)
	tween.tween_property(row, "modulate:a", 0.0, 0.6).set_delay(0.8)
	tween.chain().tween_callback(row.queue_free)

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

func _clear_box(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

func _format_multiplier(multiplier: float) -> String:
	return String.num(multiplier, 2)

# Status über dem Monster: bei Gegnern die Fangchance (Hypnose-Spirale),
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
	# Verstärkungen als Pfeil hoch, Schwächungen als Pfeil runter, dahinter die Symbole der betroffenen Werte.
	# Ein Klick öffnet eine kleine Liste, was genau wie lange verändert ist (StatusPopup).
	if mon.is_buffed():
		status_box.add_child(_clickable(_icon_row([ICON_BUFF] + _stat_icons(StatusPopup.buffed_stats(mon)), BUFF_COLOR, STATUS_FONT_SIZE)))
	if mon.is_debuffed():
		status_box.add_child(_clickable(_icon_row([ICON_DEBUFF] + _stat_icons(StatusPopup.debuffed_stats(mon)),
			ElementEffects.DEBUFF_COLOR, STATUS_FONT_SIZE)))
	# Statuseffekte der Element-Effekte bis Kampfende, Gift mit seinen Stapeln
	for status in mon._statuses:
		var text := tr(ElementEffects.STATUS_LABELS[status])
		if status == ElementEffects.POISON:
			text += " x%d" % mon.status_stacks(status)
		status_box.add_child(_clickable(_icon_row([text], ElementEffects.STATUS_COLORS[status], STATUS_FONT_SIZE)))

const ICON_DEBUFF := preload("res://assets/ui/icons/battle/debuff.svg")

## Symbole der Werte (wie in der Werte-Tabelle), kleiner als das Pfeil-Symbol davor
func _stat_icons(stats: Array) -> Array:
	return stats.map(func(stat): return StatsGrid.ICONS.get(stat, ICON_BUFF))

## Zeile im Status anklickbar machen: zeigt, was das Monster gerade verstärkt oder schwächt
func _clickable(row: Control) -> Control:
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			row.accept_event()
			StatusPopup.open(row, mon))
	return row

func printStuff() -> void:
	if mon:
		# die übrigen Züge eigener Monster stehen auf ihrer Karte im Infobereich (BattleMonCard)
		_refresh_status()
		# die Lebensanzeige liegt auf der Karte im Infobereich, der Kampf wartet auf ihre Animation
		if get_tree():
			await get_tree().create_timer(BattleMonCard.HP_TWEEN_TIME).timeout
		Events.damage_animation_done.emit(mon)

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

## Pfeil rechts neben dem Monster, das gerade am Zug ist; zeigt nach links auf das Monster und wippt leicht
const TURN_ARROW_COLOR := Color(1.0, 0.85, 0.25)
const TURN_ARROW_SIZE := 30.0
const TURN_ARROW_BOB := 6.0
var _turn_arrow: Control
var _turn_arrow_time := 0.0

func set_turn_active(active: bool) -> void:
	if active and _turn_arrow == null:
		_turn_arrow = Control.new()
		_turn_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_turn_arrow.z_index = 10
		_turn_arrow.draw.connect(_draw_turn_arrow)
		add_child(_turn_arrow)
	if _turn_arrow:
		_turn_arrow.visible = active
		_turn_arrow_time = 0.0
		_update_turn_arrow(0.0)

func _draw_turn_arrow() -> void:
	var s := TURN_ARROW_SIZE
	# Spitze bei (0, 0), Pfeil zeigt nach links
	var points := PackedVector2Array([Vector2(0, 0), Vector2(s * 0.6, -s * 0.5), Vector2(s * 0.6, -s * 0.22),
		Vector2(s * 1.2, -s * 0.22), Vector2(s * 1.2, s * 0.22), Vector2(s * 0.6, s * 0.22), Vector2(s * 0.6, s * 0.5)])
	_turn_arrow.draw_colored_polygon(points, TURN_ARROW_COLOR)
	var outline := points.duplicate()
	outline.append(points[0])
	_turn_arrow.draw_polyline(outline, Color.BLACK, 3.0, true)

## Rechte Kante des tatsächlich gezeichneten Monsterbilds (das Bild ist zentriert und behält sein Seitenverhältnis)
func _update_turn_arrow(delta: float) -> void:
	if _turn_arrow == null or not _turn_arrow.visible or texture_rect.texture == null:
		return
	_turn_arrow_time += delta
	var rect_size := texture_rect.size
	var tex_size := texture_rect.texture.get_size()
	var scale_factor := minf(rect_size.x / tex_size.x, rect_size.y / tex_size.y)
	var drawn := tex_size * scale_factor
	var origin := _texture_offset() + (rect_size - drawn) / 2
	var bob := sin(_turn_arrow_time * 5.0) * TURN_ARROW_BOB
	# etwas über der Mitte, damit der Pfeil die Statusanzeige nicht verdeckt
	_turn_arrow.position = origin + Vector2(drawn.x + 4 + bob, drawn.y * 0.3)

func _process(delta: float) -> void:
	_update_turn_arrow(delta)
	# gültiges Ziel unter einer gezogenen Karte hervorheben
	var drag_data = get_viewport().gui_get_drag_data() if get_viewport().gui_is_dragging() else null
	var hovered = drag_data != null and get_global_rect().has_point(get_global_mouse_position()) \
		and _can_drop_data(Vector2.ZERO, drag_data)
	modulate = Color(1.3, 1.3, 1.0) if hovered else Color.WHITE
	_update_drag_preview(drag_data)

# Während eine Angriffskarte gezogen wird, zeigt jedes mögliche Ziel seinen Element-Faktor an.
var _preview_label: Label

func _update_drag_preview(drag_data) -> void:
	var show_preview = drag_data != null and not home_mons and _can_drop_data(Vector2.ZERO, drag_data) \
		and Skills.is_damage_skill(drag_data.skill)
	if not show_preview:
		if _preview_label:
			_preview_label.visible = false
		return
	# schlummernde Skills treffen nur mit den Elementen des Wirkers (Skills.effective_skill)
	var multiplier = Skills.element_multiplier(Skills.effective_skill(drag_data.get("mon"), drag_data.skill).nature, mon._type)
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

# Slots über dem Status, als Symbole:
# Gegner zeigen ihren geplanten Zug (Schwert = Angriff, Stern = Sp.-Angriff, Schild, Buff-Pfeil, dahinter das Bild des Ziels),
# eigene Monster je Slot einen Angriff, der im nächsten Zug der Gegner auf sie zukommt, mit und ohne Schild (Schwert -12, Schild -4).
const INTENT_COLOR := Color(1.0, 0.45, 0.4)
const INTENT_BLOCKED_COLOR := Color(0.55, 0.8, 1.0)
const BUFF_COLOR := Color(0.55, 1.0, 0.55)
const INTENT_FONT_SIZE := 18

func _refresh_intent() -> void:
	if mon == null or not is_inside_tree():
		return
	_clear_box(intent_box)
	for row in (_own_intent_rows() if home_mons else _enemy_intent_rows()):
		intent_box.add_child(row)

func _own_intent_rows() -> Array:
	var rows = []
	for hit in Skills.incoming_hits(mon, State.enemy_mons):
		var attack_icon = ICON_ATTACK if hit.physical else ICON_S_ATTACK
		var full = roundi(hit.full)
		var after = roundi(hit.after)
		# Blau, wenn der Schild etwas abfängt: so sieht man direkt, dass sich Blocken gelohnt hat
		if after < full:
			rows.append(_icon_row([attack_icon, "-%d" % full, ICON_SHIELD if hit.physical else ICON_S_SHIELD, "-%d" % after],
				INTENT_BLOCKED_COLOR, INTENT_FONT_SIZE))
		else:
			rows.append(_icon_row([attack_icon, "-%d" % full], INTENT_COLOR if hit.physical else SPECIAL_COLOR, INTENT_FONT_SIZE))
	return rows

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
			var amount = Skills.shield_amount(mon, skill)
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
