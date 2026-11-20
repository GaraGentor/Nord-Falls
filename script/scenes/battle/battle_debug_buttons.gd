class_name BattleDebugButtons
extends HBoxContainer

## Kampf-Cheats aus dem Debug-Menü (DebugSettings), oben rechts links neben den BattleControls im selben Stil:
##   Sofortsieg: ein Klick besiegt alle Gegner (battle.gd _debug_win)
##   Fang 100 %: schaltet die Fangchance auf 100 % und wieder zurück (DebugSettings.sure_catch, Helper.catch_chance)
## Jeder Knopf erscheint nur, wenn sein Schalter im Debug-Menü an ist.

signal win_pressed

const WIN_ICON := preload("res://assets/ui/icons/firework (1).svg")
const CATCH_ICON := preload("res://assets/ui/icons/battle/catch.svg")
const SIZE := BattleControls.SIZE
const ICON_OFF := Color(0.55, 0.5, 0.4)

var _catch_style: StyleBoxFlat
var _catch_icon: TextureRect
var _catch_label: Label

## Gibt es überhaupt einen Knopf?
static func wanted() -> bool:
	return DebugSettings.win_button_enabled() or DebugSettings.catch_button_enabled()

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# rechts oben, links neben der Spalte der BattleControls
	var right := -(SIZE.x + BattleControls.MARGIN * 2)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = right
	offset_left = right
	offset_top = BattleControls.MARGIN
	offset_bottom = BattleControls.MARGIN
	if DebugSettings.catch_button_enabled():
		var catch_slot := _slot(tr("BATTLE_DEBUG_CATCH_TOOLTIP"), CATCH_ICON, "100%", _on_catch_input)
		_catch_style = catch_slot.get_theme_stylebox("panel")
		_catch_icon = catch_slot.get_child(0).get_child(0)
		_catch_label = catch_slot.get_child(0).get_child(1)
		add_child(catch_slot)
		_apply_catch()
	if DebugSettings.win_button_enabled():
		add_child(_slot(tr("BATTLE_DEBUG_WIN_TOOLTIP"), WIN_ICON, "", func(button: int):
			if button == MOUSE_BUTTON_LEFT:
				win_pressed.emit()))

## Feld wie in BattleControls, mit Symbol (und kurzem Text) statt nur Text
func _slot(tooltip: String, icon: Texture2D, text: String, on_input: Callable) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = BattleControls.BACKGROUND
	style.border_color = BattleControls.BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(BattleControls.PADDING)
	slot.add_theme_stylebox_override("panel", style)
	slot.tooltip_text = tooltip
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot.mouse_entered.connect(func(): style.border_color = BattleControls.BORDER_HOVER)
	slot.mouse_exited.connect(func(): style.border_color = BattleControls.BORDER)
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			on_input.call(event.button_index)
			slot.accept_event())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(row)
	var texture := TextureRect.new()
	texture.texture = icon
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.custom_minimum_size = Vector2(SIZE.y - BattleControls.PADDING * 2, SIZE.y - BattleControls.PADDING * 2)
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texture)
	var label := Label.new()
	label.text = text
	label.visible = text != ""
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", BattleControls.TEXT_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return slot

func _on_catch_input(button: int) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	DebugSettings.sure_catch = not DebugSettings.sure_catch
	_apply_catch()
	# die angezeigte Fangchance über den Gegnern neu berechnen
	for mon: Monster in State.enemy_mons:
		Events.monster_status_changed.emit(mon)

## Eingeschaltet hell auf goldenem Grund, sonst abgedunkelt wie AUTO in BattleControls
func _apply_catch() -> void:
	var on := DebugSettings.sure_catch
	_catch_style.bg_color = BattleControls.BACKGROUND_ON if on else BattleControls.BACKGROUND
	_catch_icon.modulate = Color.WHITE if on else ICON_OFF
	_catch_label.add_theme_color_override("font_color", BattleControls.TEXT_COLOR if on else BattleControls.TEXT_OFF)
