class_name JudgementDialog
extends Control

## Modaler Dialog im Judgement-Screen: Attacke lehren (Attacke -> Ziel-Monster -> ggf. zu vergessende Attacke),
## Wiederbelebung (welcher Fang opfert sich), Letzter Wille (Erbstück -> Erbe -> ggf. zu vergessende Attacke) und einfache Rückfragen.
## Alle Abläufe laufen per await und liefern das Ergebnis zurück.

signal _choice(result: Dictionary)

const GOLD := SkillDetailPopup.GOLD
const TEXT_COLOR := IronPlate.TEXT_COLOR
const MUTED := IronPlate.TEXT_COLOR
const FLAT_THEME = preload("res://script/scenes/battle/flat_button_theme.tres")
const GemField = preload("res://script/scenes/gems/gems.gd")
const PANEL_WIDTH := 900.0
# Vier statt drei Karten pro Reihe, sonst passen sehr viele Erbstücke nicht in die Höhe
const WIDE_PANEL_WIDTH := 1180.0
const MAX_CARDS_NORMAL_WIDTH := 9

var _panel: PanelContainer
var _title: Label
var _warning: Label
var _content: HFlowContainer
var _back: Button
var _cancel: Button
var _confirm: Button

func _ready() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	IronPlate.frame(_panel, box, 20, 20)

	_title = _label(22, GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_warning = _label(14, GOLD)
	box.add_child(_warning)
	_content = HFlowContainer.new()
	_content.alignment = FlowContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("h_separation", 12)
	_content.add_theme_constant_override("v_separation", 12)
	box.add_child(_content)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	_back = _action_button("JUDGEMENT_BACK", {"back": true})
	_cancel = _action_button("COMMON_CANCEL", {"cancel": true})
	_confirm = _action_button("", {"confirm": true})
	_confirm.add_theme_color_override("font_color", GOLD)
	for button in [_back, _cancel, _confirm]:
		buttons.add_child(button)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_choice.emit({"cancel": true})
		get_viewport().set_input_as_handled()

# Liefert {skill, target, replace} (replace = Index der vergessenen Attacke oder -1) oder {} bei Abbruch.
func teach(teacher: Monster, targets: Array, warning: String) -> Dictionary:
	var step := 0
	var skill := {}
	var target: Monster = null
	visible = true
	while true:
		_reset(warning)
		_back.visible = step > 0
		match step:
			0:
				_title.text = tr("JUDGEMENT_TEACH_PICK_SKILL").format({"mon": Helper.mon_battle_name(teacher)})
				for teacher_skill in teacher._skills:
					var learnable = targets.any(func(member): return not Skills.knows_skill(member, teacher_skill.name))
					var card = _skill_card(teacher_skill, "" if learnable else tr("JUDGEMENT_TEACH_KNOWN_ALL"))
					if not learnable:
						_disable(card)
					card.pressed.connect(_choice.emit.bind({"value": teacher_skill}))
			1:
				_title.text = tr("JUDGEMENT_TEACH_PICK_TARGET").format({"skill": _skill_name(skill)})
				for member in targets:
					var card = _mon_card(member, _learn_note(member, skill), Skills.knows_skill(member, skill.name))
					card.pressed.connect(_choice.emit.bind({"value": member}))
			2:
				_title.text = tr("JUDGEMENT_TEACH_PICK_REPLACE").format({
					"mon": Helper.mon_battle_name(target), "max": Skills.MAX_SKILLS, "skill": _skill_name(skill)})
				for i in target._skills.size():
					var card = _skill_card(target._skills[i], "")
					card.pressed.connect(_choice.emit.bind({"value": i}))
		var result: Dictionary = await _choice
		if result.has("cancel"):
			break
		if result.has("back"):
			step -= 1
			continue
		match step:
			0:
				skill = result.value
				step = 1
			1:
				target = result.value
				if target._skills.size() < Skills.MAX_SKILLS:
					visible = false
					return {"skill": skill, "target": target, "replace": -1}
				step = 2
			2:
				visible = false
				return {"skill": skill, "target": target, "replace": result.value}
	visible = false
	return {}

# Liefert den Fang, der sein Leben gibt, oder null beim Überspringen.
func revive(fallen: Monster, catches: Array, hp_percent: int) -> Monster:
	var fallen_name = Helper.mon_battle_name(fallen)
	_reset(tr("REVIVE_INTRO").format({"mon": fallen_name, "hp": hp_percent}))
	_cancel.text = "REVIVE_SKIP"
	_back.visible = false
	_title.text = tr("REVIVE_TITLE").format({"mon": fallen_name})
	for catch in catches:
		var card = _mon_card(catch, tr("REVIVE_CARD_NOTE"), false)
		card.pressed.connect(_choice.emit.bind({"value": catch}))
	visible = true
	var result: Dictionary = await _choice
	visible = false
	return result.get("value")

# Liefert {gift, target, replace} oder {} bei Ablehnung. gift siehe _will_gifts.
func last_will(fallen: Monster, heirs: Array) -> Dictionary:
	var step := 0
	var gift := {}
	var target: Monster = null
	var fallen_name = Helper.mon_battle_name(fallen)
	visible = true
	while true:
		_reset(tr("LAST_WILL_INTRO").format({"mon": fallen_name}))
		_cancel.text = "LAST_WILL_DECLINE"
		_back.visible = step > 0
		match step:
			0:
				_title.text = tr("LAST_WILL_PICK_GIFT").format({"mon": fallen_name})
				var gifts = _will_gifts(fallen)
				if gifts.size() > MAX_CARDS_NORMAL_WIDTH:
					_panel.custom_minimum_size.x = WIDE_PANEL_WIDTH
				for option in gifts:
					var card = _gift_card(option, heirs)
					card.pressed.connect(_choice.emit.bind({"value": option}))
			1:
				_title.text = tr("LAST_WILL_PICK_HEIR").format({"gift": gift_name(gift)})
				for heir in heirs:
					var card = _mon_card(heir, _heir_note(heir, gift), not _accepts(heir, gift))
					card.pressed.connect(_choice.emit.bind({"value": heir}))
			2:
				_title.text = tr("JUDGEMENT_TEACH_PICK_REPLACE").format({
					"mon": Helper.mon_battle_name(target), "max": Skills.MAX_SKILLS, "skill": gift_name(gift)})
				for i in target._skills.size():
					var card = _skill_card(target._skills[i], "")
					card.pressed.connect(_choice.emit.bind({"value": i}))
		var result: Dictionary = await _choice
		if result.has("cancel"):
			break
		if result.has("back"):
			step -= 1
			continue
		match step:
			0:
				gift = result.value
				step = 1
			1:
				target = result.value
				if gift.kind != "skill" or target._skills.size() < Skills.MAX_SKILLS:
					visible = false
					return {"gift": gift, "target": target, "replace": -1}
				step = 2
			2:
				visible = false
				return {"gift": gift, "target": target, "replace": result.value}
	visible = false
	return {}

# Gibt es etwas, das mindestens ein Erbe annehmen kann?
func can_inherit(fallen: Monster, heirs: Array) -> bool:
	return _will_gifts(fallen).any(func(gift): return _accepted_by_any(gift, heirs))

func gift_name(gift: Dictionary) -> String:
	match gift.kind:
		"gems":
			return tr("LAST_WILL_GEMS")
		"element":
			return tr(ColorMap.get_combo(gift.element).label)
	return _skill_name(gift.skill)

# Mögliche Erbstücke: {"kind": "gems", "gems": Dictionary}, {"kind": "element", "element": int} oder {"kind": "skill", "skill": Dictionary}
func _will_gifts(fallen: Monster) -> Array:
	var gifts = []
	if not fallen._gems.is_empty():
		# Anzeige mit Relikt-Bonus, vererbt werden die gespeicherten Werte (judgement.gd)
		var shown_gems := {}
		for stat in fallen._gems:
			shown_gems[stat] = fallen.gem_bonus(stat)
		gifts.append({"kind": "gems", "gems": shown_gems})
	for element in Enums.MON_TYPES.values():
		if fallen._gained_elements & element:
			gifts.append({"kind": "element", "element": element})
	for skill in fallen._skills:
		gifts.append({"kind": "skill", "skill": skill})
	return gifts

func _accepts(heir: Monster, gift: Dictionary) -> bool:
	match gift.kind:
		"element":
			return not ColorMap.has_element(heir._type, gift.element)
		"skill":
			return not Skills.knows_skill(heir, gift.skill.name)
	return true

func _accepted_by_any(gift: Dictionary, heirs: Array) -> bool:
	return heirs.any(func(heir): return _accepts(heir, gift))

func _gift_card(gift: Dictionary, heirs: Array) -> Button:
	var possible = _accepted_by_any(gift, heirs)
	var card: Button
	if gift.kind == "skill":
		card = _skill_card(gift.skill, "" if possible else tr("JUDGEMENT_TEACH_KNOWN_ALL"))
	else:
		card = _card(Vector2(270, 150))
		var lines := _card_lines(card)
		var name_label := _label(19, GOLD if gift.kind == "gems" else Helper.color_by_type(gift.element))
		name_label.text = gift_name(gift)
		lines.add_child(name_label)
		var desc := _label(14, TEXT_COLOR)
		desc.text = _gems_text(gift.gems) if gift.kind == "gems" else tr("LAST_WILL_ELEMENT_DESC")
		lines.add_child(desc)
		if not possible:
			var note := _label(13, GOLD)
			note.text = tr("LAST_WILL_ALL_HAVE_ELEMENT")
			lines.add_child(note)
	if not possible:
		_disable(card)
	return card

func _gems_text(gems: Dictionary) -> String:
	var parts = []
	for stat in gems:
		parts.append("+%d %s" % [gems[stat], tr(GemField.STATS[stat].stat).trim_suffix(":")])
	return ", ".join(PackedStringArray(parts))

func _heir_note(heir: Monster, gift: Dictionary) -> String:
	var lines = []
	match gift.kind:
		"element":
			if _accepts(heir, gift):
				lines.append("%s %s" % [tr("SHOP_CHANGES_TO"), tr(ColorMap.get_combo(ColorMap.add_element(heir._type, gift.element)).label)])
			else:
				lines.append(tr("LAST_WILL_HAS_ELEMENT"))
		"skill":
			lines.append(_learn_note(heir, gift.skill))
	if not State.mons.has(heir):
		lines.append(tr("LAST_WILL_HEIR_CATCH"))
	return "\n".join(PackedStringArray(lines))

func confirm(title: String, text: String, confirm_label: String) -> bool:
	_reset(text)
	_title.text = title
	_back.visible = false
	_confirm.visible = true
	_confirm.text = confirm_label
	visible = true
	var result: Dictionary = await _choice
	visible = false
	return result.has("confirm")

# ─────────────────────────
# Aufbau

func _reset(warning: String) -> void:
	for child in _content.get_children():
		child.queue_free()
	_warning.text = warning
	_warning.visible = warning != ""
	_confirm.visible = false
	_cancel.text = "COMMON_CANCEL"
	_panel.custom_minimum_size.x = PANEL_WIDTH

func _skill_name(skill: Dictionary) -> String:
	return tr(skill.name) if skill.scouted else tr("BATTLE_UNKNOWN_SKILL").format(skill)

func _skill_card(skill: Dictionary, note: String) -> Button:
	var card := _card(Vector2(270, 150))
	var lines := _card_lines(card)
	var name_label := _label(19, SkillCardPaper.readable_color(Helper.color_by_type(skill.nature)))
	name_label.text = _skill_name(skill)
	lines.add_child(name_label)
	var stats := _label(14, TEXT_COLOR)
	var desc := _label(13, MUTED)
	desc.max_lines_visible = 3
	if skill.scouted:
		stats.text = "{cost}: {c}    {cd}: {d}    {power}: {v}".format({
			"cost": tr("SKILL_HEADER_COST"), "cd": tr("SKILL_HEADER_CD"), "power": tr("SKILL_HEADER_POWER"),
			"c": skill.cost, "d": skill.cooldown, "v": Helper.format_number(skill.value)})
		desc.text = Helper.skill_description(skill)
	else:
		desc.text = tr("BATTLE_UNKNOWN_SKILL_HINT")
	lines.add_child(stats)
	lines.add_child(desc)
	if note != "":
		var note_label := _label(13, GOLD)
		note_label.text = note
		lines.add_child(note_label)
	SkillCardPaper.attach(card, skill)
	# Text nicht auf den Papierrahmen setzen
	for side in ["left", "right", "top", "bottom"]:
		lines.get_parent().add_theme_constant_override("margin_" + side, 16)
	return card

# Schon bekannt oder fehlende Elemente, sonst ""
func _learn_note(mon: Monster, skill: Dictionary) -> String:
	return tr("JUDGEMENT_LEARN_KNOWN") if Skills.knows_skill(mon, skill.name) else Skills.missing_elements_text(mon, skill)

# Ziel-Monster mit Bild und Hinweis; blocked sperrt die Auswahl
func _mon_card(mon: Monster, note_text: String, blocked: bool) -> Button:
	var card := _card(Vector2(270, 150))
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	_card_lines(card).add_child(row)
	var picture := TextureRect.new()
	Monmap.show_on(picture, mon._name, Monmap.ICON)
	picture.custom_minimum_size = Vector2(100, 100)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(picture)
	var lines := VBoxContainer.new()
	lines.mouse_filter = MOUSE_FILTER_IGNORE
	lines.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(lines)
	var name_label := _label(19, GOLD)
	name_label.text = Helper.mon_battle_name(mon)
	lines.add_child(name_label)
	var count := _label(14, MUTED)
	count.text = tr("JUDGEMENT_TEACH_SKILL_COUNT").format({"count": mon._skills.size(), "max": Skills.MAX_SKILLS})
	lines.add_child(count)
	var note := _label(13, GOLD)
	note.text = note_text
	if blocked:
		_disable(card)
	lines.add_child(note)
	return card

func _card(min_size: Vector2) -> Button:
	var card := Button.new()
	card.theme = FLAT_THEME
	card.custom_minimum_size = min_size
	RewardDialog.clear_button_styles(card, StyleBoxEmpty.new())
	# Hover zeigt der Rand der Platte; Skill-Karten ersetzen sie durch ihr Papier
	var plate := IronPlate.back(card)
	card.mouse_entered.connect(plate.set_rim.bind(GOLD))
	card.mouse_exited.connect(plate.set_rim.bind(IronPlate.RIM))
	_content.add_child(card)
	return card

func _disable(card: Button) -> void:
	card.disabled = true
	card.modulate.a = 0.45

func _card_lines(card: Button) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	card.add_child(margin)
	var lines := VBoxContainer.new()
	lines.mouse_filter = MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 4)
	margin.add_child(lines)
	return lines

func _action_button(text_key: String, result: Dictionary) -> Button:
	var button := RewardDialog.plate_button(text_key)
	button.custom_minimum_size = Vector2(180, 44)
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(_choice.emit.bind(result))
	return button

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = MOUSE_FILTER_IGNORE
	return label
