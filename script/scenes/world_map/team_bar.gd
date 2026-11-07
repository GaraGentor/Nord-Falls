extends HBoxContainer

## Aktuelles Team im Header der Karte: Bild, Name, Stufe und KP jedes eigenen Monsters im Rahmen.
## Ein Klick öffnet die Details des Monsters über der Kartenfläche, nochmal Klicken schließt sie wieder.

const PORTRAIT_SIZE := Vector2(64, 64)
const HOVER_RIM := Color(0.5, 0.62, 0.63)
const BAR_SIZE := Vector2(150, 8)
const FONT_SIZE := 16
const HP_COLOR := Color(0.35, 0.8, 0.35)
const BAR_BACKGROUND := Color(0.05, 0.07, 0.085)
const LOW_HP_COLOR := Color(0.9, 0.3, 0.25)
## darunter wird der Balken rot
const LOW_HP_SHARE := 0.3

## refresh ist schon für das Ende des Frames vorgemerkt (beim Heilen ändern sich die KP jeden Frame)
var _refresh_queued := false
## hierhin kommt der Monster-Dialog (world_map.gd)
var dialog_parent: Control
## Monster mit offenem Dialog
var _open_mon: Monster
var _dialog: MonsterInfoDialog
## Monster -> {"plate": IronPlate, "portrait": TextureRect}
var _entries := {}

func _ready() -> void:
	add_theme_constant_override("separation", 24)
	# KP ändern sich auch auf der Karte (Lager, Ereignisse), Elemente im Shop
	Events.deal_damage_to_monster.connect(_on_monster_changed)
	Events.refresh_ui_for_monster.connect(refresh)
	refresh()

func _exit_tree() -> void:
	Events.deal_damage_to_monster.disconnect(_on_monster_changed)
	Events.refresh_ui_for_monster.disconnect(refresh)

func _on_monster_changed(_mon) -> void:
	if not _refresh_queued:
		_refresh_queued = true
		refresh.call_deferred()

func refresh() -> void:
	_refresh_queued = false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_entries.clear()
	for mon: Monster in State.mons:
		add_child(_entry(mon))
	_show_toggled()

func _entry(mon: Monster) -> Control:
	var frame := PanelContainer.new()
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 8)
	var plate := IronPlate.frame(frame, entry, 8, 1)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = PORTRAIT_SIZE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	portrait.texture = Monmap.texture(mon._name, PORTRAIT_SIZE.x)
	portrait.material = Monmap.LIVING_MATERIAL
	entry.add_child(portrait)

	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 2)
	entry.add_child(info)

	var name_label := Label.new()
	name_label.text = tr("MAP_TEAM_ENTRY").format({"name": Helper.mon_battle_name(mon), "level": mon._level})
	name_label.add_theme_font_size_override("font_size", FONT_SIZE)
	name_label.add_theme_color_override("font_color", Helper.color_by_mon(mon).lightened(0.4))
	info.add_child(name_label)

	var max_hp: float = mon.hp()
	var hp := clampf(max_hp - mon._lost_hp, 0.0, max_hp)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = BAR_SIZE
	bar.show_percentage = false
	bar.max_value = max_hp
	bar.value = hp
	var fill := StyleBoxFlat.new()
	fill.bg_color = LOW_HP_COLOR if hp < max_hp * LOW_HP_SHARE else HP_COLOR
	bar.add_theme_stylebox_override("fill", fill)
	var background := StyleBoxFlat.new()
	background.bg_color = BAR_BACKGROUND
	bar.add_theme_stylebox_override("background", background)
	info.add_child(bar)

	var hp_label := Label.new()
	hp_label.text = tr("MAP_TEAM_HP").format({"hp": roundi(hp), "max": roundi(max_hp)})
	hp_label.add_theme_font_size_override("font_size", FONT_SIZE - 3)
	hp_label.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	info.add_child(hp_label)

	RewardDialog.ignore_mouse_below(frame)
	frame.gui_input.connect(_on_entry_input.bind(mon))
	frame.mouse_entered.connect(_on_entry_hover.bind(mon, true))
	frame.mouse_exited.connect(_on_entry_hover.bind(mon, false))
	_entries[mon] = {"plate": plate, "portrait": portrait}
	return frame

func _on_entry_input(event: InputEvent, mon: Monster) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_toggle(mon)

func _on_entry_hover(mon: Monster, over: bool) -> void:
	if mon != _open_mon:
		_entries[mon].plate.set_rim(HOVER_RIM if over else IronPlate.RIM)

## Dialog öffnen, zu einem anderen Monster wechseln oder wieder schließen
func _toggle(mon: Monster) -> void:
	var was_open := mon == _open_mon
	if _dialog:
		# ohne Bezug, damit das Schließen hier nicht als "Zurück" zählt
		_dialog.tree_exiting.disconnect(_on_dialog_closed)
		_dialog.queue_free()
		_dialog = null
	_open_mon = null if was_open else mon
	if not was_open:
		_dialog = MonsterInfoDialog.new(mon)
		_dialog.tree_exiting.connect(_on_dialog_closed)
		dialog_parent.add_child(_dialog)
	_show_toggled()

func _on_dialog_closed() -> void:
	_dialog = null
	_open_mon = null
	_show_toggled()

## Gewähltes Monster in der Farbe für alles Ausgewählte: goldener Rahmen und Umriss
func _show_toggled() -> void:
	for mon: Monster in _entries:
		var selected := mon == _open_mon
		_entries[mon].plate.set_rim(Monmap.SELECTED_OUTLINE_COLOR if selected else IronPlate.RIM)
		_entries[mon].portrait.material = Monmap.living_selected_material if selected else Monmap.LIVING_MATERIAL
