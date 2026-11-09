class_name BossRelicBar
extends VBoxContainer

## Leiste mit den Boss-Relikten des Kampfs (BossRelics.active) am rechten Rand des Kampffelds, an der Naht
## zum Infobereich. Sie füllt sich von unten (über der Kartenhand, neben den eigenen Monstern) nach oben.
## Tooltip zeigt Name und Wirkung, ein Klick die Übersicht aller Relikte (pressed, siehe battle.gd).

signal pressed

const ICON_SIZE := Vector2(56, 56)
const PADDING := 5
const BACKGROUND := Color(0, 0, 0, 0.6)
const BORDER := Color(0.858824, 0.717647, 0.45098)
const BORDER_HOVER := Color(1.0, 0.92, 0.65)
const MARGIN := 8

func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# rechter Rand des Kampffelds, von oben bis zur Kartenhand
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.7
	offset_left = -(ICON_SIZE.x + 2 * PADDING + MARGIN)
	offset_right = -MARGIN
	offset_top = MARGIN
	offset_bottom = -MARGIN
	refresh()

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	# unten beginnen: das erste Relikt steht ganz unten
	for i in range(BossRelics.active.size() - 1, -1, -1):
		add_child(_slot(BossRelics.active[i]))

func _slot(id: String) -> PanelContainer:
	var relic: Dictionary = BossRelics.get_relic(id)
	var slot := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(PADDING)
	slot.add_theme_stylebox_override("panel", style)
	slot.tooltip_text = tr(relic.name) + "\n" + BossRelics.description(id)
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot.mouse_entered.connect(func(): style.border_color = BORDER_HOVER)
	slot.mouse_exited.connect(func(): style.border_color = BORDER)
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit())
	var icon := TextureRect.new()
	icon.texture = load(relic.icon)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = ICON_SIZE
	icon.material = BossRelics.RELIC_MATERIAL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)
	return slot
