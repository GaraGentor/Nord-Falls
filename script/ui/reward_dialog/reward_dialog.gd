class_name RewardDialog
extends Control

## Gemeinsamer Belohnungs-Dialog über der Karte (Schatz, Edelstein-Feld, Relic-Belohnung, Shop,
## Trainer, Jailer):
## Panel mit Überschrift, darunter die Anleitung. Links stehen die Preise, rechts die Ziele: eigene
## Monster oder die Tasche. Sie sind immer zu sehen, aber abgedunkelt, bis ein passender Preis gezogen wird.
## Ablegen auf einem Ziel bestätigt die Wahl, Fallenlassen woanders bricht ab.
## Standardmäßig schließt der Dialog nach der ersten Wahl, Unterklassen (Shop) können das über
## _taken() und _drag_blocked() ändern.
## Der Aufbau passiert in _init(), damit Unterklassen in _ready() direkt Karten anlegen können.

const CARD_SIZE := Vector2(340, 110)
const ICON_SIZE := Vector2(90, 90)
## vertikale Karten: kleineres Bild und Titel, damit zwei Reihen auf den Bildschirm passen
const VERTICAL_ICON_SIZE := Vector2(72, 72)
const VERTICAL_TITLE_FONT_SIZE := 22
const TARGET_SIZE := Vector2(120, 150)
## Höhe des Karten-Headers (world_map.tscn): darunter beginnt die Kartenfläche
const MAP_HEADER_HEIGHT := 184.0
## Abstand der Dialoge auf der Kartenfläche zum Bildschirmrand: links bis zur Tasche im Header, rechts und unten wie der Header
const MAP_DIALOG_MARGIN_LEFT := 10.0
const MAP_DIALOG_MARGIN := 8.0
## zeigt im Typ-Chip, was ein Trank aus dem Monster macht
const PREVIEW_ARROW := ">"
## Bild des Preises am Mauszeiger
const DRAG_ICON_SIZE := Vector2(84, 84)
## Skill-Karte am Mauszeiger: kleiner als auf dem Tisch und leicht durchscheinend
const DRAG_PREVIEW_SCALE := 0.8
const DRAG_PREVIEW_ALPHA := 0.8
## Bilder auf der Skill-Karte: Monster fehlen Elemente / kennt den Skill schon
const PORTRAIT_SIZE := Vector2(48, 48)
const UNUSABLE_MODULATE := Color(0.3, 0.3, 0.3)
const KNOWN_MODULATE := Color(1, 1, 1, 0.25)
## so weit darf sich die Maus bei einem Klick auf eine Karte bewegen, sonst ist es ein Ziehen
const CLICK_MAX_MOVE := 10.0
const FONT_THEME = preload("res://script/ui/materials/pixel_font_theme.tres")
const LABEL_THEME = preload("res://script/ui/materials/battle_labels.tres")
const BAG_ICON = preload("res://assets/ui/icons/bag.svg")
const HOVER_COLOR := Color(1.3, 1.3, 1.0)
const LOCKED_COLOR := Color(0.45, 0.45, 0.45)
const SOLD_ALPHA := 0.35
const BUTTON_THEME = preload("res://script/scenes/battle/flat_button_theme.tres")
## Icon-Buttons auf Eisenplatte (Kerkermeister, Trainer), Pixel-Look passend zum Hintergrund
const ICON_BUTTON_MATERIAL = preload("res://script/scenes/jailer/jailer_props_material.tres")
const ICON_BUTTON_SIZE := Vector2(72, 72)
const BUTTON_HOVER_COLOR := Color(1.35, 1.35, 1.2)
const BUTTON_DISABLED_COLOR := Color(0.5, 0.5, 0.5)
const ELEMENT_CHIP := preload("res://script/ui/element_chip/element_chip.tscn")
## Platz um den Text eines Element-Chips
const CHIP_PADDING := Vector2(16, 8)

## Preis auf der linken Seite, lässt sich auf die Ziele ziehen
class RewardCard extends PanelContainer:
	var dialog: RewardDialog
	var drag: Dictionary
	## Bild des Preises, fliegt beim Ziehen mit
	var icon: Control
	## Icon und Text, nebeneinander oder (vertikale Karten) untereinander
	var row: BoxContainer
	## Titel und Beschreibung, Unterklassen können dazwischen etwas einfügen (insert_detail)
	var info: VBoxContainer
	var sold := false
	## optional: wird beim Klick ohne Ziehen aufgerufen (Trainer: Skill-Details)
	var on_click: Callable
	var _press_pos := Vector2.ZERO

	func _gui_input(event: InputEvent) -> void:
		if not on_click.is_valid() or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_press_pos = event.position
		elif event.position.distance_to(_press_pos) < CLICK_MAX_MOVE:
			on_click.call()

	## Zeile direkt unter dem Titel, z. B. der Preis im Shop
	func insert_detail(control: Control) -> void:
		info.add_child(control)
		info.move_child(control, 1)

	func _get_drag_data(_at_position: Vector2):
		if sold:
			return null
		var reason := dialog._drag_blocked(self)
		if reason != "":
			dialog._show_blocked(reason)
			return null
		set_drag_preview(dialog._make_drag_preview(self))
		dialog._show_targets(self)
		return drag

## Ziel auf der rechten Seite: ein Monster, eine Monster-Art (String) oder (mon == null) die Tasche
class DropTarget extends PanelContainer:
	var dialog: RewardDialog
	var mon: Variant
	## gesperrt (drag.can_drop), z. B. zu teuer: ausgegraut, Ablegen nicht möglich
	var locked := false
	## Bild, Name und was Unterklassen ergänzen (Edelsteine: Werte)
	var box: VBoxContainer
	## optional: Werte des Monsters, zeigen beim Drüberziehen die Änderung durch den Edelstein
	var stats: StatsGrid
	## optional: Typ des Monsters, zeigt beim Ziehen die Änderung durch einen Trank
	var type_row: HBoxContainer

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return not locked and dialog._dragged != null and is_same(data, dialog._dragged.drag)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		var card := dialog._dragged
		if mon:
			data.on_drop.call(mon)
		else:
			data.on_drop.call()
		dialog._taken(card)

var _dim: ColorRect
var _center: CenterContainer
var _panel: PanelContainer
var _panel_plate: IronPlate
var _title: Label
var _content: VBoxContainer
var _columns: BoxContainer
## Spalte mit den Kartengruppen, neue Karten landen immer in der letzten Gruppe
var _card_groups: VBoxContainer
## nur auf der Kartenfläche: dort können die Preise höher sein als der Platz
var _card_scroll: ScrollContainer
var _card_grid: GridContainer
var _card_columns := 1
var _target_side: VBoxContainer
var _target_header: Label
var _target_grid: GridContainer
var _tooltip: PanelContainer
var _tooltip_label: Label
## gerade gezogene Karte, null wenn nichts gezogen wird
var _dragged: RewardCard
## dauerhaft sichtbare Ziele (show_fixed_targets)
var _fixed_targets: Array[DropTarget] = []
var _drag_hint := ""
var _card_size := CARD_SIZE
## Bild oben, Text darunter statt Bild links (Shop)
var _vertical_cards := false
## gerade offene Auswahl, welcher Skill vergessen wird (null = keine)
var _replace_picker: SkillReplacePicker

func _init() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	theme = FONT_THEME
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.7)
	_dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_dim)
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_center)
	_panel = PanelContainer.new()
	_center.add_child(_panel)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 20)
	_panel_plate = IronPlate.frame(_panel, _content, 24, 24)
	_title = Label.new()
	_title.theme = LABEL_THEME
	_title.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(_title)

	_columns = BoxContainer.new()
	_columns.add_theme_constant_override("separation", 30)
	_content.add_child(_columns)
	_card_groups = VBoxContainer.new()
	_card_groups.add_theme_constant_override("separation", 30)
	_columns.add_child(_card_groups)
	new_card_group()

	_target_side = VBoxContainer.new()
	_target_side.add_theme_constant_override("separation", 12)
	_target_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.add_child(_target_side)
	# Anleitung direkt unter dem Titel, beim Ziehen steht hier, wohin der Preis soll
	_target_header = Label.new()
	_target_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target_header.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	_content.add_child(_target_header)
	_content.move_child(_target_header, 1)
	_target_header.visible = false
	_target_grid = GridContainer.new()
	_target_grid.add_theme_constant_override("h_separation", 12)
	_target_grid.add_theme_constant_override("v_separation", 12)
	_target_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_target_side.add_child(_target_grid)

	# eigener Tooltip, weil Godot während eines Drags keine Tooltips zeigt
	_tooltip = PanelContainer.new()
	_tooltip.top_level = true
	_tooltip.mouse_filter = MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	_tooltip_label = Label.new()
	_tooltip_label.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	IronPlate.frame(_tooltip, _tooltip_label, 12, 10)
	add_child(_tooltip)
	_hide_targets()

func set_title(text: String) -> void:
	_title.text = text

## Rahmenfarbe des Panels, unterscheidet die Belohnungsarten
func set_accent(color: Color) -> void:
	_panel_plate.set_rim(color)

## Wie viele Preise nebeneinander stehen (der Shop hat mehr Ware, als in eine Spalte passt).
## vertical: Bild oben, Text darunter. Gilt für Karten, die danach angelegt werden.
func set_card_layout(columns: int, card_size: Vector2, vertical := false) -> void:
	_card_columns = columns
	_card_grid.columns = columns
	_card_size = card_size
	_vertical_cards = vertical

## Neue Kartengruppe (eigenes Grid mit Abstand), z. B. eine pro Warenart im Shop
func new_card_group() -> void:
	_card_grid = GridContainer.new()
	_card_grid.columns = _card_columns
	_card_grid.add_theme_constant_override("h_separation", 12)
	_card_grid.add_theme_constant_override("v_separation", 12)
	_card_groups.add_child(_card_grid)

## Eigene Szene statt Overlay über der Karte: background ersetzt die Abdunklung, das Panel füllt
## den Bildschirm ohne Rahmen und die Ziele nehmen den ganzen Platz rechts ein
func use_scene_layout(background: Control) -> void:
	_dim.queue_free()
	move_child(background, 0)
	_center.remove_child(_panel)
	_center.queue_free()
	add_child(_panel)
	move_child(_panel, 1)
	_panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_panel_plate.visible = false
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL

## Kleine Events: das Panel füllt die ganze Kartenfläche, nur der Header der Karte bleibt sichtbar
func use_map_layout() -> void:
	offset_top = MAP_HEADER_HEIGHT
	_dim.queue_free()
	_center.remove_child(_panel)
	_center.queue_free()
	add_child(_panel)
	move_child(_panel, 0)
	fit_to_map_area(_panel)
	_content.add_theme_constant_override("separation", 12)
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_target_header.visible = true
	_card_scroll = ScrollContainer.new()
	_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_columns.remove_child(_card_groups)
	_card_scroll.add_child(_card_groups)
	_columns.add_child(_card_scroll)
	_columns.move_child(_card_scroll, 0)

## Eigene Fläche statt der Kartenspalte (nach use_map_layout), die Preise legt dann _place_card darauf
func use_card_stage(stage: Control) -> void:
	_columns.remove_child(_card_scroll)
	_card_scroll.queue_free()
	_card_scroll = null
	_columns.add_child(stage)
	_columns.move_child(stage, 0)

## Panel eines Dialogs auf der Kartenfläche: mit Abstand zum Rand, die Karte bleibt ringsum sichtbar
static func fit_to_map_area(panel: Control) -> void:
	panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	panel.offset_left = MAP_DIALOG_MARGIN_LEFT
	panel.offset_right = -MAP_DIALOG_MARGIN
	panel.offset_bottom = -MAP_DIALOG_MARGIN

## Ziele sind ab jetzt immer da und abgedunkelt: die Monster nebeneinander, die Tasche unter dem ersten
func show_fixed_targets(mons: Array, with_bag: bool) -> void:
	_target_grid.columns = maxi(mons.size(), 1)
	for mon in mons:
		_add_target(Helper.mon_display_name(mon_name(mon)), mon_icon(mon), mon)
	if with_bag:
		var bag := texture_icon(BAG_ICON)
		bag.material = ICON_BUTTON_MATERIAL
		_add_target(tr("REWARD_BAG"), bag, null)
		for i in _target_grid.columns - 1:
			var gap := Control.new()
			gap.mouse_filter = MOUSE_FILTER_IGNORE
			_target_grid.add_child(gap)
	_lock_targets()

## Monster-Ziele zeigen ihren Typ und beim Ziehen eines Tranks, was daraus wird
func show_element_chips() -> void:
	for target in _fixed_targets:
		if target.mon == null:
			continue
		target.type_row = HBoxContainer.new()
		target.type_row.alignment = BoxContainer.ALIGNMENT_CENTER
		target.type_row.custom_minimum_size.y = 32
		target.type_row.add_theme_constant_override("separation", 4)
		target.box.add_child(target.type_row)
		show_element_preview(target.type_row, target.mon)

## Typ des Monsters als Chip; drag (Ware in der Hand) zeigt dazu, was ein Trank daraus macht
static func show_element_preview(row: Control, mon: Monster, drag := {}) -> void:
	for chip in row.get_children():
		row.remove_child(chip)
		chip.queue_free()
	add_element_chip(row, mon._type)
	if drag.has("element") and not ColorMap.has_element(mon._type, drag.element):
		var arrow := Label.new()
		arrow.text = PREVIEW_ARROW
		arrow.mouse_filter = MOUSE_FILTER_IGNORE
		arrow.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
		arrow.add_theme_color_override("font_outline_color", Color.BLACK)
		arrow.add_theme_constant_override("outline_size", 4)
		row.add_child(arrow)
		add_element_chip(row, ColorMap.add_element(mon._type, drag.element))

## Eigener Inhalt unter den Zielen, z. B. die Auswahl, welcher Skill vergessen wird (Trainer)
func add_side_content(control: Control) -> void:
	_target_side.add_child(control)

## Text rechts, solange nichts gezogen wird (Übersetzungs-Key)
func set_drag_hint(key: String) -> void:
	_drag_hint = key
	if _dragged == null:
		_target_header.text = tr(key)

## Zeile unter Preisen und Zielen, z. B. Geld und Fertig-Button im Shop
func add_footer(control: Control) -> void:
	_content.add_child(control)

func close() -> void:
	queue_free()

## Debug-Menü: vergibt alle Preise auf einmal (Monster-Preise an das erste passende Monster),
## schließt den Dialog und liefert die Titel der vergebenen Preise
func take_all() -> PackedStringArray:
	var titles := PackedStringArray()
	for card: RewardCard in _takeable_cards():
		if card.drag.get("bag", false):
			card.drag.on_drop.call()
		else:
			var mons: Array = card.drag.mons.call() if card.drag.mons is Callable else card.drag.mons
			if mons.is_empty():
				continue
			card.drag.on_drop.call(mons[0])
		titles.append(card.drag.title)
	close()
	return titles

## Alle Preise, die take_all vergibt
func _takeable_cards() -> Array:
	return _card_grid.get_children()

## Nach einer Wahl: standardmäßig ist der Dialog damit fertig
func _taken(_card: RewardCard) -> void:
	close()

## Grund, warum die Karte gerade nicht gezogen werden darf ("" = darf gezogen werden)
func _drag_blocked(_card: RewardCard) -> String:
	return tr("TRAINER_FINISH_CHOICE") if _replace_picker else ""

## Was beim Ziehen am Mauszeiger hängt: standardmäßig das Bild des Preises, bei Skills die ganze Karte
func _make_drag_preview(card: RewardCard) -> Control:
	if card.drag.has("skill"):
		return _skill_card_preview(card)
	var art: Control = card.icon.duplicate(0)
	art.custom_minimum_size = DRAG_ICON_SIZE
	art.size = DRAG_ICON_SIZE
	art.position = -DRAG_ICON_SIZE / 2
	var holder := Control.new()
	holder.add_child(art)
	return holder

## Die Karte selbst fliegt mit dem Mauszeiger mit (Kopie ohne Skripte, nur zum Anschauen)
func _skill_card_preview(card: RewardCard) -> Control:
	var preview: Control = card.duplicate(0)
	preview.size = card.size
	preview.rotation = 0.0
	preview.pivot_offset = Vector2.ZERO
	preview.scale = card.scale * DRAG_PREVIEW_SCALE
	preview.modulate.a = DRAG_PREVIEW_ALPHA
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# hängt mittig unter dem Mauszeiger
	preview.position = -preview.size * preview.scale / 2
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(preview)
	return holder

## Zeigt, warum die Karte nicht gezogen werden darf
func _show_blocked(reason: String) -> void:
	_target_header.text = reason

## Ausgegraut und nicht mehr ziehbar
func mark_sold(card: RewardCard) -> void:
	card.sold = true
	card.modulate.a = SOLD_ALPHA
	card.mouse_default_cursor_shape = Control.CURSOR_ARROW

static func texture_icon(texture: Texture2D, color: Color = Color.WHITE) -> Control:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.modulate = color
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon

## Die Platte ist Teil des Icons bzw. eine IronPlate, der Button selbst zeichnet keine Fläche
static func clear_button_styles(button: Button, style: StyleBox) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, style)

static func icon_button(texture: Texture2D) -> Button:
	var button := Button.new()
	button.theme = BUTTON_THEME
	button.icon = texture
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.material = ICON_BUTTON_MATERIAL
	clear_button_styles(button, StyleBoxEmpty.new())
	button.add_theme_color_override("icon_hover_color", BUTTON_HOVER_COLOR)
	button.add_theme_color_override("icon_hover_pressed_color", BUTTON_HOVER_COLOR)
	button.add_theme_color_override("icon_disabled_color", BUTTON_DISABLED_COLOR)
	button.custom_minimum_size = ICON_BUTTON_SIZE
	button.size = ICON_BUTTON_SIZE
	return button

## Text-Button auf Eisenplatte (Kerkermeister, Shop)
static func plate_button(text: String) -> Button:
	var button := Button.new()
	button.theme = BUTTON_THEME
	button.add_theme_font_size_override("font_size", 22)
	button.text = text
	var margins := StyleBoxEmpty.new()
	margins.content_margin_left = 16
	margins.content_margin_right = 16
	margins.content_margin_top = 10
	margins.content_margin_bottom = 10
	clear_button_styles(button, margins)
	button.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", SkillDetailPopup.GOLD)
	button.add_theme_color_override("font_pressed_color", SkillDetailPopup.GOLD)
	IronPlate.back(button)
	return button

## Chip mit dem Namen und der Farbe eines Elements bzw. einer Kombination, in eine Zeile eingereiht
static func add_element_chip(row: Control, element: int) -> void:
	var chip := ELEMENT_CHIP.instantiate()
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip.size_flags_vertical = Control.SIZE_FILL
	chip._init_with_element({"label": ColorMap.get_combo(element).label, "color": Helper.color_by_type(element)})
	row.add_child(chip)
	# der Chip selbst hat keine Mindestgröße, sein Text ist mittig darin verankert
	chip.custom_minimum_size = chip.label.get_minimum_size() + CHIP_PADDING
	ignore_mouse_below(chip)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

## Art eines Ziels: eigene Monster oder Arten als String
static func mon_name(mon: Variant) -> String:
	return mon if mon is String else mon._name

## Bild eines eigenen Monsters bzw. einer Art, als Ziel für Edelsteine, Tränke und Boss Tränen
static func mon_icon(mon: Variant) -> Control:
	var icon := texture_icon(Monmap.texture(mon_name(mon), Monmap.SMALL))
	icon.material = Monmap.LIVING_MATERIAL
	return icon

## Preis, der in die Tasche gezogen wird (Gold, Relic)
func add_bag_card(card_title: String, text: String, icon: Control, on_taken: Callable) -> RewardCard:
	return _add_card(card_title, text, icon, {"header": tr("REWARD_BAG_HEADER"), "bag": true, "on_drop": on_taken})

## Preis, der auf eins der mons gezogen wird. on_given(mon) vergibt ihn,
## tooltip(mon) liefert den Text, der beim Drüberziehen erscheint.
## mons darf auch ein Callable sein, dann wird die Liste erst beim Ziehen bestimmt
## (im Shop ändert sich nach einem Kauf, wer einen Trank noch trinken kann).
## extra: target_title(mon) beschriftet die Ziele, can_drop(mon) sperrt einzelne Ziele,
## no_target ersetzt den Text, wenn kein Ziel übrig ist.
func add_mon_card(card_title: String, text: String, icon: Control, header: String, mons: Variant, on_given: Callable, tooltip: Callable, extra := {}) -> RewardCard:
	var drag := {"header": header, "mons": mons, "on_drop": on_given, "tooltip": tooltip}
	drag.merge(extra)
	return _add_card(card_title, text, icon, drag)

## Skill auf Kartenpapier (Trainer, Couvert), wird auf ein Monster gezogen, das ihn noch nicht kennt.
## on_given(mon) bringt ihn bei, die Bilder auf der Karte zeigen, wer ihn einsetzen kann.
func add_skill_card(skill: Dictionary, on_given: Callable) -> RewardCard:
	var element_name = tr(ColorMap.get_combo(skill.nature).label)
	var stats := "%s · %s" % [tr("CONFIGURATOR_TIER").format({"tier": skill.get("tier", 1)}),
		tr("CONFIGURATOR_SKILL_STATS").format({"cost": skill.cost, "cooldown": skill.cooldown}).trim_suffix(" ·")]
	var text = Helper.skill_description(skill) + "\n" + tr("TRAINER_ELEMENT").format({"element": element_name}) + "\n" + stats
	var learners := func(): return State.mons.filter(func(mon): return not Skills.knows_skill(mon, skill.name))
	var card := add_mon_card(tr(skill.name), text, _skill_portraits(skill), tr("TRAINER_CHOOSE_MON"), learners,
		on_given, _skill_target_tooltip.bind(skill), {"no_target": tr("TRAINER_ALL_KNOW"), "skill": skill})
	# Titel in der Farbe des Elements
	card.info.get_child(0).add_theme_color_override("font_color", SkillCardPaper.readable_color(Helper.color_by_type(skill.nature)))
	SkillCardPaper.attach(card, skill)
	card.tooltip_text = _skill_fits_text(skill)
	return card

## Bilder der eigenen Monster: hell = kann den Skill einsetzen, dunkel = Elemente fehlen,
## durchscheinend = kennt ihn schon
func _skill_portraits(skill: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for mon: Monster in State.mons:
		var portrait := mon_icon(mon)
		portrait.custom_minimum_size = PORTRAIT_SIZE
		if Skills.knows_skill(mon, skill.name):
			portrait.modulate = KNOWN_MODULATE
		elif not Skills.can_use(mon, skill):
			portrait.modulate = UNUSABLE_MODULATE
		row.add_child(portrait)
	return row

## "Passt zu: ..." mit den Monstern, die den Skill lernen und sofort einsetzen können
func _skill_fits_text(skill: Dictionary) -> String:
	var fits = State.mons.filter(func(mon): return Skills.can_use(mon, skill) and not Skills.knows_skill(mon, skill.name))
	if fits.is_empty():
		return tr("TRAINER_FITS_NONE")
	var names = fits.map(func(mon): return Helper.mon_display_name(mon._name))
	return tr("TRAINER_FITS").format({"mons": ", ".join(PackedStringArray(names))})

## Beim Drüberziehen: kennt es den Skill schon, kann es ihn einsetzen, muss es dafür einen vergessen?
func _skill_target_tooltip(mon: Monster, skill: Dictionary) -> String:
	if Skills.knows_skill(mon, skill.name):
		return tr("TRAINER_ALREADY_KNOWS")
	var lines := PackedStringArray()
	if Skills.can_use(mon, skill):
		lines.append(tr("TRAINER_CAN_USE"))
	if mon._skills.size() >= Skills.MAX_SKILLS:
		lines.append(tr("TRAINER_REPLACES"))
	return "\n".join(lines)

## Bringt mon den Skill bei. Hat es keinen freien Slot, wählt man mittig über picker_parent, welcher vergessen wird.
## Liefert false, wenn das abgebrochen wurde.
func learn_skill(skill: Dictionary, mon: Monster, picker_parent: Control) -> bool:
	var learned := Skills.learnable_copy(skill)
	if mon._skills.size() < Skills.MAX_SKILLS:
		mon._skills.append(learned)
		return true
	_replace_picker = SkillReplacePicker.new(mon)
	var picker_box := _picker_box(tr(skill.name), picker_parent)
	var index: int = await _replace_picker.picked
	picker_box.queue_free()
	_replace_picker = null
	if index == -1:
		return false
	mon._skills[index] = learned
	return true

func _picker_box(skill_title: String, parent: Control) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	IronPlate.frame(panel, box, 20, 20)
	var title := Label.new()
	title.theme = LABEL_THEME
	title.text = skill_title
	title.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_replace_picker)
	parent.add_child(center)
	return center

func _add_card(card_title: String, text: String, icon: Control, drag: Dictionary) -> RewardCard:
	var card := RewardCard.new()
	card.dialog = self
	card.icon = icon
	drag.title = card_title
	card.drag = drag
	card.mouse_default_cursor_shape = Control.CURSOR_DRAG
	# das Mausrad soll auch über den Karten scrollen, Ziehen klappt trotzdem
	if _card_scroll:
		card.mouse_filter = Control.MOUSE_FILTER_PASS
	_build_card(card, card_title, text)
	ignore_mouse_below(card)
	_place_card(card)
	return card

## Aussehen der Karte: Bild und Text auf einer Eisenplatte. Unterklassen können es ersetzen (Edelsteine)
func _build_card(card: RewardCard, card_title: String, text: String) -> void:
	var icon := card.icon
	card.custom_minimum_size = _card_size
	card.row = VBoxContainer.new() if _vertical_cards else HBoxContainer.new()
	card.row.add_theme_constant_override("separation", 8 if _vertical_cards else 12)
	IronPlate.frame(card, card.row, 12, 12)
	icon.custom_minimum_size = VERTICAL_ICON_SIZE if _vertical_cards else ICON_SIZE
	card.row.add_child(icon)

	card.info = VBoxContainer.new()
	card.info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.info.alignment = BoxContainer.ALIGNMENT_BEGIN if _vertical_cards else BoxContainer.ALIGNMENT_CENTER
	card.row.add_child(card.info)
	var label := Label.new()
	label.theme = LABEL_THEME
	label.text = card_title
	label.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
	# lange Namen nur an Wortgrenzen umbrechen
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	card.info.add_child(label)
	var description := Label.new()
	description.text = text
	description.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.info.add_child(description)
	if _vertical_cards:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", VERTICAL_TITLE_FONT_SIZE)
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## Karte ins Layout setzen, Unterklassen können sie selbst anordnen (Trainer)
func _place_card(card: RewardCard) -> void:
	_card_grid.add_child(card)

func _add_target(target_title: String, icon: Control, mon: Variant) -> void:
	var target := DropTarget.new()
	target.dialog = self
	target.mon = mon
	target.custom_minimum_size = TARGET_SIZE
	target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target.size_flags_vertical = Control.SIZE_EXPAND_FILL

	target.box = VBoxContainer.new()
	IronPlate.frame(target, target.box, 8, 8)
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	target.box.add_child(icon)
	var label := Label.new()
	label.text = target_title
	label.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	target.box.add_child(label)

	ignore_mouse_below(target)
	_target_grid.add_child(target)
	_fixed_targets.append(target)

## Kinder sollen weder Drag noch Drop abfangen, das macht die Karte bzw. das Ziel selbst
static func ignore_mouse_below(control: Control) -> void:
	for child in control.find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _show_targets(card: RewardCard) -> void:
	_dragged = card
	card.modulate.a = 0.4
	_target_header.text = card.drag.header
	_build_targets(card)

## Nur die Ziele freigeben, die den gezogenen Preis nehmen können: die Tasche oder die Monster aus drag.mons
func _build_targets(card: RewardCard) -> void:
	var into_bag: bool = card.drag.get("bag", false)
	var mons: Array = []
	if not into_bag:
		mons = card.drag.mons.call() if card.drag.mons is Callable else card.drag.mons
		if mons.is_empty():
			_target_header.text = card.drag.get("no_target", tr("REWARD_NO_TARGET"))
	var can_drop: Callable = card.drag.get("can_drop", Callable())
	for target in _fixed_targets:
		if target.mon == null:
			target.locked = not into_bag
		else:
			target.locked = not mons.has(target.mon) or (can_drop.is_valid() and not can_drop.call(target.mon))
		target.modulate = LOCKED_COLOR if target.locked else Color.WHITE
		if target.type_row and not target.locked:
			show_element_preview(target.type_row, target.mon, card.drag)

func _lock_targets() -> void:
	for target in _fixed_targets:
		target.locked = true
		# Werte und Typ sollen auch vor dem Ziehen lesbar sein
		target.modulate = Color.WHITE if target.stats or target.type_row else LOCKED_COLOR
		if target.stats:
			target.stats.show_gem_preview(target.mon)
		if target.type_row:
			show_element_preview(target.type_row, target.mon)

func _hide_targets() -> void:
	_lock_targets()
	_target_header.text = tr(_drag_hint)
	_tooltip.visible = false
	if _dragged:
		_dragged.modulate.a = SOLD_ALPHA if _dragged.sold else 1.0
		_dragged = null

func _notification(what: int) -> void:
	# Drop auf ein Ziel oder Fallenlassen woanders (= Abbruch)
	if what == NOTIFICATION_DRAG_END and is_node_ready():
		_hide_targets()

## Ziele, die beim Ziehen hervorgehoben werden
func _drop_targets() -> Array:
	return _fixed_targets

## Bereich, unter dem der Tooltip eines Ziels erscheint
func _tooltip_anchor(target: DropTarget) -> Rect2:
	return target.get_global_rect()

func _process(_delta: float) -> void:
	if _dragged == null:
		return
	# Ziel unter dem gezogenen Preis hervorheben und seinen Tooltip zeigen
	var mouse := get_global_mouse_position()
	var hovered: DropTarget = null
	for target: DropTarget in _drop_targets():
		var over := target.get_global_rect().has_point(mouse)
		if target.locked:
			target.modulate = LOCKED_COLOR
		else:
			target.modulate = HOVER_COLOR if over else Color.WHITE
		if over:
			hovered = target
		if target.stats:
			target.stats.show_gem_preview(target.mon, _dragged.drag.get("stat", "") if over and not target.locked else "", _dragged.drag.get("bonus", 0))
	var tooltip: Callable = _dragged.drag.get("tooltip", Callable())
	# zeigt das Ziel die Änderung selbst an, braucht es keinen Tooltip (Skills ändern weder Werte noch Typ)
	var shows_change: bool = hovered != null and (hovered.stats != null or hovered.type_row != null) and not _dragged.drag.has("skill")
	var wants_tooltip: bool = hovered != null and hovered.mon != null and not shows_change and tooltip.is_valid()
	var text: String = tooltip.call(hovered.mon) if wants_tooltip else ""
	_tooltip.visible = text != ""
	if _tooltip.visible:
		_tooltip_label.text = text
		_tooltip.reset_size()
		var rect := _tooltip_anchor(hovered)
		var pos := Vector2(rect.get_center().x - _tooltip.size.x / 2, rect.end.y + 8)
		_tooltip.global_position = pos.clamp(Vector2.ZERO, get_viewport_rect().size - _tooltip.size)
