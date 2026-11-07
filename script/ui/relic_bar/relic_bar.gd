extends HBoxContainer

## Zeigt die gesammelten Relics als Icons, ein Klick öffnet ein Popup mit Name und Beschreibung.

const ICON_SIZE := Vector2(40, 40)
const ICON_MARGIN := 6
## Im Debug-Menü ausgeschaltete Relics bleiben sichtbar, aber blass
const INACTIVE_COLOR := Color(1, 1, 1, 0.35)
const INSET_BOX := preload("res://script/ui/materials/iron_inset_box.tres")
const FONT_THEME := preload("res://script/ui/materials/pixel_font_theme.tres")

var _popup: PopupPanel
var _popup_label: RichTextLabel
var _button_style: StyleBoxEmpty

func _ready() -> void:
	_button_style = StyleBoxEmpty.new()
	_button_style.set_content_margin_all(ICON_MARGIN)
	_popup = PopupPanel.new()
	_popup.theme = FONT_THEME
	var popup_style: StyleBoxFlat = INSET_BOX.duplicate()
	popup_style.set_content_margin_all(12)
	_popup.add_theme_stylebox_override("panel", popup_style)
	_popup_label = RichTextLabel.new()
	_popup_label.add_theme_color_override("default_color", IronPlate.TEXT_COLOR)
	_popup_label.bbcode_enabled = true
	_popup_label.fit_content = true
	_popup_label.custom_minimum_size = Vector2(260, 0)
	_popup.add_child(_popup_label)
	add_child(_popup)

	Relics.relics_changed.connect(refresh)
	refresh()

func _exit_tree() -> void:
	Relics.relics_changed.disconnect(refresh)

func refresh() -> void:
	for child in get_children():
		if child is Button:
			remove_child(child)
			child.queue_free()
	for id in State.relics:
		var relic = Relics.get_relic(id)
		var button := Button.new()
		button.custom_minimum_size = ICON_SIZE
		button.icon = load(relic.icon)
		button.expand_icon = true
		RewardDialog.clear_button_styles(button, _button_style)
		# derselbe Rahmen wie überall, wird beim Drüberfahren golden
		var plate := IronPlate.back(button)
		button.mouse_entered.connect(plate.set_rim.bind(SkillDetailPopup.GOLD))
		button.mouse_exited.connect(plate.set_rim.bind(IronPlate.RIM))
		button.pressed.connect(_show_info.bind(button, relic))
		if not Relics.is_active(id):
			button.modulate = INACTIVE_COLOR
		add_child(button)

func _show_info(button: Button, relic: Dictionary) -> void:
	_popup_label.text = "[color=#%s]%s[/color]\n%s" % [SkillDetailPopup.GOLD.to_html(false), tr(relic.name), tr(relic.description)]
	var pos := Vector2i(button.get_screen_position() + Vector2(0, button.size.y + 4))
	_popup.popup(Rect2i(pos, Vector2i.ZERO))
