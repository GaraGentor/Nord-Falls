extends Control

@export var mon_slot: int
@export var home_mons: bool
## Vorderansicht auch für eigene Monster, z.B. im Lager außerhalb des Kampfes
@export var show_front: bool

@export var texture_rect: TextureRect

var mon: Monster

## Statuseffekte über dem Monster: Schilde, Buffs und bei Gegnern die Fangchance
@export var status_box: HFlowContainer
## Slots über dem Status: bei Gegnern die Absichten (bei eigenen Monstern leer)
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
	Events.monster_revived.connect(_on_revived)
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

## Ein Monster betritt mitten im Kampf diesen Platz (Endboss-Relikt Buddy, battle.gd _spawn_buddy)
func show_mon(new_mon: Monster) -> void:
	mon = new_mon
	visible = true
	texture_rect.material = Monmap.MONSTER_MATERIAL
	Monmap.show_on(texture_rect, mon._name, Monmap.SMALL, home_mons and not show_front)
	_refresh_intent()
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
# Blitz, Lava oder Eissplitter), Schildtreffer, wenn der Schild etwas abfängt, neue Schilde und Buffs.
# Physische Kombi-Treffer zeigen zum Hieb auch den Kombi-Effekt. Schwächungen, Verstärkungen und Heilungen ohne eigene
# Karte kommen über Events.status_vfx (_play_status_vfx).
func _play_skill_vfx(_mon: Monster, skill: Dictionary, blocked: float) -> void:
	if mon != _mon or not is_inside_tree() or Skills.is_passive(skill):
		return
	var physical := Skills.is_physical(skill)
	# mit geliehenem Element (ElementLoan) zeigt der Treffer den Kombi-Effekt
	var nature := ElementEffects.effect_nature(skill)
	if Skills.is_damage_skill(skill):
		if physical:
			var accent := Color(ColorMap.get_combo(nature).get("color", "#FFFFFF"))
			_spawn_vfx(BattleVfxScript.Kind.SLASH, accent, VFX_HIT_DELAY)
			if Map.count_elements(nature) > 1:
				for kind in BattleVfxScript.element_kinds(nature):
					_spawn_vfx(kind, Color.WHITE, VFX_HIT_DELAY + 0.1)
		else:
			for kind in BattleVfxScript.element_kinds(nature):
				_spawn_vfx(kind, Color.WHITE, VFX_HIT_DELAY)
		if blocked > 0:
			_spawn_vfx(BattleVfxScript.Kind.SHIELD_HIT, Color.WHITE, VFX_HIT_DELAY)
	elif skill.get("effect", "") in ["buff", "boon"]:
		_spawn_vfx(BattleVfxScript.Kind.BUFF)
	elif Skills.is_debuff_skill(skill):
		_spawn_vfx(BattleVfxScript.Kind.DEBUFF, Color.WHITE, VFX_HIT_DELAY)
	else:
		_spawn_vfx(BattleVfxScript.Kind.SHIELD)

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
## Sp.-Angriffe sind violett, der Schild blau (er blockt physische und magische Angriffe)
const SPECIAL_COLOR := Color(0.85, 0.6, 1.0)

const ICON_ATTACK := preload("res://assets/ui/icons/sword.svg")
const ICON_S_ATTACK := preload("res://assets/ui/icons/battle/s_attack.svg")
const ICON_SHIELD := preload("res://assets/ui/icons/battle/shield.svg")
const ICON_BUFF := preload("res://assets/ui/icons/battle/buff.svg")
const ICON_CATCH := preload("res://assets/ui/icons/battle/catch.svg")

## Kurznamen der Werte, die ein Buff erhöhen kann
const BUFF_STAT_KEYS := {"hp": "STAT_HP", "atk": "STAT_ATK", "def": "STAT_DEF", "s_atk": "STAT_SPA",
	"speed": "STAT_SPE"}

# Schwebender Schadenstext über dem Monster, bei Element-Vorteil/-Nachteil mit Hinweis und Faktor,
# vom Schild abgefangener Schaden steht mit Schild-Symbol darunter.
func _show_hit_text(_mon: Monster, damage: float, multiplier: float, blocked: float = 0.0) -> void:
	if mon != _mon:
		return
	var color = Color.WHITE
	var font_size = 56 if multiplier > 1.0 else 40
	var box := _new_row_box(true)
	if multiplier > 1.0:
		color = SUPER_EFFECTIVE_COLOR
		box.add_child(_icon_row([tr("BATTLE_SUPER_EFFECTIVE") + " x" + _format_multiplier(multiplier)], color, font_size))
	elif multiplier < 1.0:
		color = NOT_EFFECTIVE_COLOR
		box.add_child(_icon_row([tr("BATTLE_NOT_EFFECTIVE") + " x" + _format_multiplier(multiplier)], color, font_size))
	box.add_child(_icon_row(["-%d" % roundi(damage)], color, font_size))
	# eigene Monster: nur der Schaden, keine Rechnung mit dem Schild (den Schildtreffer zeigt der Effekt)
	if blocked > 0 and not home_mons:
		box.add_child(_icon_row([ICON_SHIELD, "-%d" % roundi(blocked)], STATUS_COLOR, 40))
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
	var row := _icon_row([text], color, 40)
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
const STATUS_FONT_SIZE := 24
const CATCH_COLOR := Color(1.0, 0.85, 0.4)

func _on_status_changed(_mon: Monster) -> void:
	# Schilde und Buffs jedes Monsters können den angekündigten Schaden ändern
	_refresh_intent()
	if mon == _mon:
		_refresh_status()

func _refresh_status() -> void:
	_clear_box(status_box)
	if not home_mons and not mon._minion:
		var chance := "%d%%" % roundi(Helper.catch_chance(mon) * 100)
		var catch_row := _icon_row([ICON_CATCH, chance], CATCH_COLOR, STATUS_FONT_SIZE)
		# das Tutorial hebt die Fangchance beim Erklären der Hypnose hervor
		catch_row.add_to_group("tut_bat_catch_chance")
		status_box.add_child(catch_row)
	if mon.shield() > 0:
		status_box.add_child(_icon_row([ICON_SHIELD, str(roundi(mon.shield()))], STATUS_COLOR, STATUS_FONT_SIZE))
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

## Todes-Totem: das Monster steht wieder auf dem Feld
func _on_revived(_mon) -> void:
	if _mon == mon:
		visible = true
		_refresh_status()


## Drag & Drop: Skill-Karten und One-Way-Items (Postits) können auf passende Ziele gezogen werden
func _can_drop_data(_at_position: Vector2, data) -> bool:
	if not visible or mon == null or not mon.is_alive():
		return false
	if data is Dictionary and data.get("type") == "battle_item":
		# Items ohne Ziel wirken auch, wenn sie auf einem Monster landen
		return Items.battle_target_ok(data.item, null if Items.use_of(data.item) == Items.USE_FIELD else mon)
	# Element-Leihgabe: Kugel des Partners auf das eigene Monster am Zug
	if data is Dictionary and data.get("type") == "element_orb":
		return home_mons and ElementLoan.can_borrow(mon, data.lender, data.element)
	if not (data is Dictionary and data.get("type") == "skill_card"):
		return false
	match data.skill.get("target", Enums.CARD_TARGETS.SINGLE_ENEMY):
		Enums.CARD_TARGETS.SINGLE_ENEMY, Enums.CARD_TARGETS.TEAM_ENEMY:
			return not home_mons
		Enums.CARD_TARGETS.SINGLE_FRIEND, Enums.CARD_TARGETS.TEAM_FRIEND:
			return home_mons
		# Selbst-Karten nur auf das Monster, das am Zug ist (battle.gd prüft das beim Ausspielen genau)
		Enums.CARD_TARGETS.SELF:
			return home_mons
	return false

func _drop_data(_at_position: Vector2, data) -> void:
	modulate = Color.WHITE
	if data.get("type") == "battle_item":
		Events.use_item.emit(data.carrier, data.index, null if Items.use_of(data.item) == Items.USE_FIELD else mon)
		return
	if data.get("type") == "element_orb":
		ElementLoan.set_preview(0)
		ElementLoan.borrow(mon, data.lender, data.element)
		return
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
		# kein z_index: sonst liegt der Pfeil über der Kartenhand und dem Boss-Relikt-Overlay
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
	var image := drawn_image_rect()
	var drawn := image.size
	var origin := image.position
	var bob := sin(_turn_arrow_time * 5.0) * TURN_ARROW_BOB
	# etwas über der Mitte, damit der Pfeil die Statusanzeige nicht verdeckt
	_turn_arrow.position = origin + Vector2(drawn.x + 4 + bob, drawn.y * 0.3)

func _process(delta: float) -> void:
	_update_turn_arrow(delta)
	# gültiges Ziel unter einer gezogenen Karte hervorheben
	var drag_data = get_viewport().gui_get_drag_data() if get_viewport().gui_is_dragging() else null
	var hovered = drag_data != null and _has_point(get_local_mouse_position()) \
		and _can_drop_data(Vector2.ZERO, drag_data)
	modulate = Color(1.3, 1.3, 1.0) if hovered else Color.WHITE
	_update_drag_preview(drag_data)

# Während eine Angriffskarte gezogen wird, zeigt jedes mögliche Ziel seinen Element-Faktor an.
var _preview_label: Label

func _update_drag_preview(drag_data) -> void:
	var show_preview = drag_data != null and not home_mons and drag_data is Dictionary and drag_data.get("type") == "skill_card" \
		and _can_drop_data(Vector2.ZERO, drag_data) and Skills.is_damage_skill(drag_data.skill)
	if not show_preview:
		if _preview_label:
			_preview_label.visible = false
		return
	# schlummernde Skills treffen nur mit den Elementen des Wirkers (Skills.effective_skill)
	# physische Angriffe treffen immer neutral (Skills.skill_element_multiplier)
	var multiplier = Skills.skill_element_multiplier(Skills.effective_skill(drag_data.get("mon"), drag_data.skill), mon._type)
	if _preview_label == null:
		_preview_label = Label.new()
		_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_preview_label.add_theme_font_size_override("font_size", 40)
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
# eigene Monster zeigen hier nichts (nur ihren Status mit Schilden und Buffs).
const INTENT_COLOR := Color(1.0, 0.45, 0.4)
const INTENT_BLOCKED_COLOR := Color(0.55, 0.8, 1.0)
const BUFF_COLOR := Color(0.55, 1.0, 0.55)
const INTENT_FONT_SIZE := 24

func _refresh_intent() -> void:
	if mon == null or not is_inside_tree():
		return
	_clear_box(intent_box)
	# über eigenen Monstern keine Schadensrechnung: dort stehen nur Schilde und Buffs (Status),
	# den angekündigten Schaden zeigen die Absichten der Gegner
	if home_mons:
		return
	for row in _enemy_intent_rows():
		intent_box.add_child(row)

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
			var hits := Skills.hit_count(mon, skill)
			var damage_text := "-%d" % roundi(Skills.calc_damage(mon, target, skill))
			var items = [ICON_ATTACK if physical else ICON_S_ATTACK, damage_text if hits <= 1 else "%dx %s" % [hits, damage_text]]
			var row := _icon_row(items + targets, INTENT_COLOR if physical else SPECIAL_COLOR, INTENT_FONT_SIZE)
			_add_loan_tag(row, action)
			rows.append(row)
		elif Skills.is_flat_buff(skill):
			rows.append(_icon_row([ICON_BUFF, "+%d %s" % [roundi(skill.value), Skills.stat_label(skill.buff_stat)]] + targets, BUFF_COLOR, INTENT_FONT_SIZE))
		elif skill.get("effect", "") == "buff":
			var stat = tr(BUFF_STAT_KEYS.get(skill.buff_stat, "")).trim_suffix(":")
			rows.append(_icon_row([ICON_BUFF, "+%d%% %s" % [roundi(skill.value), stat]] + targets, BUFF_COLOR, INTENT_FONT_SIZE))
		elif Skills.is_debuff_skill(skill):
			# Schwächung: Name der Karte, in der Farbe der Schwächungen
			rows.append(_icon_row([ICON_DEBUFF, tr(skill.name)] + targets, ElementEffects.DEBUFF_COLOR, INTENT_FONT_SIZE))
		elif skill.get("effect", "") == "boon":
			# Sonder-Verstärkung: Name der Karte statt einer Zahl
			rows.append(_icon_row([ICON_BUFF, tr(skill.name)] + targets, BUFF_COLOR, INTENT_FONT_SIZE))
		else:
			# gleiche Rechnung wie Skills.add_shield, Wert kommt vom Wirker
			var amount = Skills.shield_amount(mon, skill)
			var row := _icon_row([ICON_SHIELD, "+%d" % amount] + targets, INTENT_BLOCKED_COLOR, INTENT_FONT_SIZE)
			_add_loan_tag(row, action)
			rows.append(row)
	return rows

## Geplante Element-Leihgabe (battle.gd _plan_loans): Kugel des Elements und das Kombi-Element, das daraus wird,
## z. B. "+Blitz". Tooltip: von wem geliehen und was der Effekt macht (sicher).
func _add_loan_tag(row: HBoxContainer, action: Dictionary) -> void:
	if not action.has("loan"):
		return
	var mask := ElementLoan.loan_nature(mon, action.skill, action.loan)
	if mask == 0:
		return
	var combo := ColorMap.get_combo(mask)
	var color := Color(combo.get("color", "#FFFFFF"))
	row.add_child(ElementOrbs.badge(action.loan, INTENT_FONT_SIZE * 1.6))
	row.add_child(_icon_row(["+" + tr(combo.label)], color, INTENT_FONT_SIZE))
	var lender: Monster = action.get("lender")
	var shown: Dictionary = action.skill.duplicate()
	shown.effect_nature = mask
	shown._loaned = true
	row.tooltip_text = tr("LOAN_INTENT_TOOLTIP").format({
		"element": tr(ColorMap.get_combo(action.loan).label),
		"lender": Helper.mon_battle_name(lender) if lender != null else "",
		"effect": Helper.highlight(ElementEffects.skill_effect_text(shown), false)})
	row.mouse_filter = Control.MOUSE_FILTER_STOP

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

## Tatsächlich gezeichnetes Monsterbild relativ zu dieser Szene. Keep Centered zeichnet das Bild in Originalgröße
## (darf über das Rechteck hinausragen, bei Gegnern nach unten bis zu den eigenen Monstern), sonst eingepasst.
func drawn_image_rect() -> Rect2:
	if texture_rect == null or texture_rect.texture == null:
		return Rect2()
	var rect_size := texture_rect.size
	var tex_size := texture_rect.texture.get_size()
	var scale_factor := 1.0 if texture_rect.stretch_mode == TextureRect.STRETCH_KEEP_CENTERED \
		else minf(rect_size.x / tex_size.x, rect_size.y / tex_size.y)
	var drawn := tex_size * scale_factor
	return Rect2(_texture_offset() + (rect_size - drawn) / 2, drawn)

## Klick- und Ablagefläche: die Szene selbst plus das ganze gezeichnete Bild, damit sich Karten auch auf den Teil des
## Monsters ziehen lassen, der über die Szene hinausragt
func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(point) or (visible and drawn_image_rect().has_point(point))
