class_name SkillDetailPopup
extends PanelContainer

## Detail-Popup eines Skills: fliegt neben einem Anker-Control (z. B. Infobereich) ein und zeigt die Karte wie im Kampf,
## Stufe, Kosten, Abklingzeit, Element, fehlende Elemente und bei Ei-Attacken, wie man sie freischaltet bzw. freigeschaltet hat.
## Liegt per top_level frei über der Szene, der Host hängt es nur als Kind an.

const BATTLE_CARD := preload("res://script/scenes/battle/battle_card.tscn")
const FONT_THEME := preload("res://script/ui/materials/pixel_font_theme.tres")
const GOLD := Color(0.858824, 0.717647, 0.45098, 1)
const MISSING_COLOR := Color(1, 0.45, 0.45)
const WIDTH := 300.0
const GAP := 16.0
const FONT_SIZE := 18

var _card: Control
var _stats: Label
var _element: Label
var _missing: Label
var _lock: Label
var _anchor: Control

func _init() -> void:
	top_level = true
	z_index = 10
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0)
	theme = FONT_THEME
	# umbrechende Labels kennen ihre Höhe erst nach dem Layout, dann nochmal auf den Inhalt schrumpfen
	minimum_size_changed.connect(_fit)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	IronPlate.frame(self, box, 16, 16)
	_card = BATTLE_CARD.instantiate()
	_card.custom_minimum_size = Vector2(220, 200)
	_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_card)
	_stats = _label(IronPlate.TEXT_COLOR)
	_element = _label(IronPlate.TEXT_COLOR)
	_missing = _label(MISSING_COLOR)
	_lock = _label(GOLD)
	_lock.add_theme_font_size_override("font_size", 15)
	for label in [_stats, _element, _missing, _lock]:
		box.add_child(label)

	var close := RewardDialog.plate_button(tr("MONSTER_CLOSE_INFO"))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.focus_mode = Control.FOCUS_NONE
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(hide_popup)
	box.add_child(close)

## mon: Monster, für das fehlende Elemente geprüft werden (null = keine Prüfung).
## lock_hint: [Sperr-Label, Freischalt-Hinweis] für gesperrte Ei-Attacken, sonst leer.
## source_hint: [Label, Beschreibung], wie eine verfügbare Ei-Attacke freigeschaltet wurde, sonst leer.
func show_skill(skill: Dictionary, mon: Monster, anchor: Control, lock_hint: Array = [], source_hint: Array = []) -> void:
	_anchor = anchor
	_card.skill = skill
	_card.modulate = Color(0.6, 0.6, 0.6) if not lock_hint.is_empty() else Color.WHITE
	_stats.text = "%s · %s" % [tr("CONFIGURATOR_TIER").format({"tier": skill.get("tier", 1)}),
		tr("CONFIGURATOR_SKILL_STATS").format({"cost": skill.cost, "cooldown": skill.cooldown}).trim_suffix(" ·")]
	_element.text = tr("EGG_DETAIL_ELEMENT").format({"element": tr(ColorMap.get_combo(skill.nature).label)})
	_element.add_theme_color_override("font_color", Helper.color_by_type(skill.nature))
	_missing.text = Skills.missing_elements_text(mon, skill) if mon else ""
	_missing.visible = not _missing.text.is_empty()
	var hint := lock_hint if not lock_hint.is_empty() else source_hint
	_lock.visible = not hint.is_empty()
	if _lock.visible:
		_lock.text = tr(hint[0]) + "\n" + tr(hint[1])

	visible = true
	_fit()
	# fliegt von der Seite des Ankers her ein
	var target_x := _target_x()
	var from_left := target_x > anchor.global_position.x
	position.x = target_x + (-60 if from_left else 60)
	modulate = Color(1, 1, 1, 0)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "position:x", target_x, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate", Color.WHITE, 0.2)

func hide_popup() -> void:
	visible = false

## links neben dem Anker, passt es dort nicht hin, rechts daneben
func _target_x() -> float:
	var rect := _anchor.get_global_rect()
	if rect.position.x - WIDTH - GAP >= 0:
		return rect.position.x - WIDTH - GAP
	return minf(rect.end.x + GAP, get_viewport_rect().size.x - WIDTH - GAP)

## Höhe auf den Inhalt schrumpfen und vertikal am Anker ausrichten, ohne aus dem Bild zu ragen
func _fit() -> void:
	if not visible or _anchor == null:
		return
	size = Vector2.ZERO
	reset_size()
	var max_y := get_viewport_rect().size.y - size.y - GAP
	var anchor_rect := _anchor.get_global_rect()
	var centered := anchor_rect.get_center().y - size.y / 2
	position.y = clampf(centered, GAP, maxf(max_y, GAP))

func _label(color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	# feste Breite, sonst bricht der Text nach jedem Zeichen um und das Popup wird bildschirmhoch
	label.custom_minimum_size = Vector2(WIDTH - 32, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
