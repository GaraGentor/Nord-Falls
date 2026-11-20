extends Control

## Ei-Auswahl: links der Raum mit dem Bannkreis (EggStage), oben der Biom-Pfad, rechts die schwarze Spalte.
## "Ei werfen" wirft die drei Start-Eier nacheinander auf den Bannkreis. Anleitung und Sammlung sind Symbol-Knöpfe unten links,
## die Fehlschläge stehen bis zum ersten Wurf unten auf dem Bild. Rechts stehen Name, Element, Seltenheit, Wachstum (Netzdiagramm) und Werte
## des vorderen Monsters. Sind alle Eier geworfen, verschwindet "Ei werfen" und "Reise beginnen" erscheint.

const ELEMENT_CHIP := preload("res://script/ui/element_chip/element_chip.tscn")
const GOLD := SkillDetailPopup.GOLD
const MUTED := IronPlate.TEXT_COLOR
## Werte unter dem Netzdiagramm (StatsGrid wie im Kampf)
const STATS_FONT_SIZE := 14
## Faule Eier fliegen doppelt so schnell herein
const REROLL_SPEED := 2.0
const EGG_COUNT := 3
## Chip mit den freigeschalteten Ei-Attacken (Gold wie die Ei-Attacken im Kampf)
const EGG_CHIP_COLOR := Color(0.858824, 0.717647, 0.45098)

## Zahnrad unten links (Größe und Abstand wie der Legenden-Button der Karte)
const SETTINGS_BUTTON_SIZE := 56.0
const SETTINGS_BUTTON_MARGIN := 16.0
const CORNER_BUTTON_GAP := 10.0
const GUIDE_ICON := preload("res://assets/ui/icons/guide_book.svg")
const COLLECTION_ICON := preload("res://assets/ui/icons/collection_eggs.svg")
const MENU_BUTTON_WIDTH := 280.0
const MENU_FONT_SIZE := 24
const ACTION_FONT_SIZE := 28
const FAILURES_FONT_SIZE := 20
## Abstand der Fehlschläge zum unteren Rand des Bildes
const FAILURES_BOTTOM := 24
const NAME_FONT_SIZE := 30
const RADAR_MIN_HEIGHT := 250.0
const FADE_SECONDS := 0.3

@export var stage: EggStage
@export var biome_path: Control
## rechte Spalte, Inhalte entstehen in _build_side
@export var side: Control

var mons: Array = []
var selected_egg := 0
## so viele Eier sind schon geworfen
var _thrown := 0
## so viele Eier sind schon geworfen, warten aber noch, bis das fliegende gelandet ist
var _queued := 0

var _spacer: Control
var _failures: Label
var _details: VBoxContainer
var _name_label: Label
var _chips: HFlowContainer
var _radar: GrowthRadar
var _stats: VBoxContainer
var _throw_button: Button
var _go_button: Button
var _reroll_button: Button

func _ready() -> void:
	_add_corner_buttons()
	_build_side()
	_add_failures()
	load_eggs()
	biome_path.show_path(Map.load_biome_path())
	stage.front_changed.connect(_on_front_changed)
	stage.throw_finished.connect(_on_throw_finished)
	_add_tutorial_targets()
	Tutorial.enabled_changed.connect(_on_tutorial_enabled_changed)
	Tutorial.trigger("selection")

func _exit_tree() -> void:
	Tutorial.enabled_changed.disconnect(_on_tutorial_enabled_changed)

## Im Einstellungen-Dialog eingeschaltet: von vorn, damit das Tutorial mit dem Werfen der Eier beginnen kann
func _on_tutorial_enabled_changed(on: bool) -> void:
	if on:
		get_tree().reload_current_scene.call_deferred()

## Gruppen, die das interaktive Tutorial hervorhebt (siehe Tutorial.SEQUENCES)
func _add_tutorial_targets() -> void:
	biome_path.add_to_group("tut_biome_path")
	stage.add_to_group("tut_eggs")
	_throw_button.add_to_group("tut_draw_egg")
	_details.add_to_group("tut_starter_info")
	_go_button.add_to_group("tut_begin_journey")

## Symbol-Knöpfe unten links übereinander: Einstellungen, darüber Sammlung und Anleitung
func _add_corner_buttons() -> void:
	var buttons := [
		SettingsDialog.make_button(self),
		_icon_button(COLLECTION_ICON, "SELECTION_COLLECTION", func(): InfoDialog.present(self, CollectionDialog.new())),
		_icon_button(GUIDE_ICON, "SELECTION_GUIDE", func(): InfoDialog.present(self, GuideDialog.new())),
	]
	for i in buttons.size():
		var button: Button = buttons[i]
		var bottom := SETTINGS_BUTTON_MARGIN + i * (SETTINGS_BUTTON_SIZE + CORNER_BUTTON_GAP)
		button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		button.offset_left = SETTINGS_BUTTON_MARGIN
		button.offset_right = SETTINGS_BUTTON_MARGIN + SETTINGS_BUTTON_SIZE
		button.offset_top = -bottom - SETTINGS_BUTTON_SIZE
		button.offset_bottom = -bottom
		add_child(button)

## Aufgebaut wie das Zahnrad (SettingsDialog.make_button)
func _icon_button(icon: Texture2D, tooltip: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.tooltip_text = tooltip
	button.icon = icon
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.focus_mode = FOCUS_NONE
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	button.material = RewardDialog.ICON_BUTTON_MATERIAL
	RewardDialog.clear_button_styles(button, StyleBoxEmpty.new())
	button.add_theme_color_override("icon_hover_color", RewardDialog.BUTTON_HOVER_COLOR)
	button.add_theme_color_override("icon_hover_pressed_color", RewardDialog.BUTTON_HOVER_COLOR)
	IronPlate.back(button)
	button.pressed.connect(on_pressed)
	return button

# ─────────────────────────
# Eier

## Eier aus dem Spielstand, neue gibt es nur ohne gespeicherte (erster Start oder nach einem Run-Ende)
func load_eggs() -> void:
	var saved_eggs: Array = SaveManager.save_data["starter_eggs"]
	if saved_eggs.is_empty():
		roll_eggs()
		return
	mons = saved_eggs.map(Helper.mon_from_egg)

func roll_eggs() -> void:
	mons = Helper.generate_mons({"count": EGG_COUNT, "initial": true})
	SaveManager.set_starter_eggs(mons.map(Helper.egg_to_save))

func _on_throw_pressed() -> void:
	if _thrown + _queued >= mons.size():
		return
	# beim ersten Wurf verschwinden die Fehlschläge
	if _failures.visible and _thrown == 0:
		_fade(_failures, false)
	if stage.is_busy():
		# fliegt noch ein Ei: das wird schneller fertig, das neue folgt direkt danach
		_queued += 1
		stage.hurry()
	else:
		_throw_next()
	if _thrown + _queued >= mons.size():
		_fade(_throw_button, false)

## Abwechselnd von links und rechts
func _throw_next() -> void:
	stage.throw_egg(mons[_thrown], _thrown, _thrown % 2 == 0)
	_thrown += 1

func _on_throw_finished() -> void:
	if _queued > 0:
		_queued -= 1
		_throw_next()
		# wartet schon das nächste Ei (vom Spieler geworfen), läuft auch dieser Wurf schneller
		if _queued > 0:
			stage.hurry()
		return
	if _thrown < mons.size():
		return
	stage.speed_scale = 1.0
	_fade(_go_button, true)
	_reroll_button.visible = SaveManager.has_full_reroll_charges()

## Neues Monster vorne: rechts seine Werte, unten seine Ei-Attacken
func _on_front_changed(index: int, clicked: bool) -> void:
	select_egg(index)
	if clicked:
		# Tutorial wartet auf das Antippen eines Monsters
		Events.select_initial_mon.emit(index)

func select_egg(index: int) -> void:
	selected_egg = index
	var mon: Monster = mons[index]
	if not _details.visible:
		_spacer.visible = false
		_fade(_details, true)
	_show_details(mon)
	stage.show_skills(mon)
	# ausgebrütet gilt als gesehen (Sammlung)
	SaveManager.add_seen_mon(mon._name)

func _on_go_pressed() -> void:
	var mon: Monster = mons[selected_egg]
	State.mons = [mon]
	State.starter_name = mon._name
	State.starter = mon
	# Ladungen werden erst beim Aufbruch verbraucht, und nur wenn neu gewürfelt wurde (auch vor einem Neustart)
	if SaveManager.save_data["eggs_rerolled"]:
		SaveManager.spend_reroll_charges()
	get_tree().change_scene_to_file("res://script/scenes/egg_configurator/egg_configurator.tscn")

## Faule Eier: neue würfeln, alle drei fliegen gleichzeitig herein
func _on_reroll_pressed() -> void:
	if stage.is_busy():
		return
	SaveManager.save_data["eggs_rerolled"] = true
	_reroll_button.visible = false
	_go_button.visible = false
	roll_eggs()
	stage.clear()
	stage.speed_scale = REROLL_SPEED
	_thrown = mons.size()
	_queued = 0
	stage.throw_all(mons)

# ─────────────────────────
# Rechte Spalte

func _build_side() -> void:
	var margin := MarginContainer.new()
	for key in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(key, 28)
	for key in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(key, 24)
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	side.add_child(margin)
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = MOUSE_FILTER_IGNORE
	margin.add_child(column)

	# vor dem ersten Wurf leer, hält die Knöpfe unten
	_spacer = Control.new()
	_spacer.size_flags_vertical = SIZE_EXPAND_FILL
	_spacer.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(_spacer)

	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 12)
	_details.size_flags_vertical = SIZE_EXPAND_FILL
	_details.mouse_filter = MOUSE_FILTER_IGNORE
	_details.visible = false
	column.add_child(_details)
	_build_details()

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	actions.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(actions)
	_go_button = _menu_button(tr("SELECTION_BEGIN_JOURNEY"), _on_go_pressed, ACTION_FONT_SIZE)
	_go_button.visible = false
	actions.add_child(_go_button)
	_reroll_button = _menu_button(tr("SELECTION_REROLL_EGGS"), _on_reroll_pressed, MENU_FONT_SIZE)
	_reroll_button.visible = false
	actions.add_child(_reroll_button)
	_throw_button = _menu_button(tr("SELECTION_DRAW_EGG"), _on_throw_pressed, ACTION_FONT_SIZE)
	actions.add_child(_throw_button)

## Gewonnene und verlorene Runs bisher, unten mittig auf dem Bild (bis zum ersten Wurf)
func _add_failures() -> void:
	_failures = Label.new()
	var failed := int(SaveManager.save_data["failed_runs"])
	# gewonnen ist jeder beendete Run, der kein Fehlschlag war (SaveManager.add_finished_run)
	var won := maxi(int(SaveManager.save_data["runs"]) - failed, 0)
	_failures.text = tr("SELECTION_RECORD").format({"wins": won, "count": failed})
	_failures.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_failures.add_theme_font_size_override("font_size", FAILURES_FONT_SIZE)
	_failures.add_theme_color_override("font_color", MUTED)
	_failures.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_failures.add_theme_constant_override("outline_size", 6)
	_failures.mouse_filter = MOUSE_FILTER_IGNORE
	# das Tutorial stellt Trainer und Sprechblase nicht darüber
	_failures.add_to_group("tut_keep_clear")
	stage.add_child(_failures)
	_failures.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM, PRESET_MODE_MINSIZE, FAILURES_BOTTOM)
	_failures.grow_horizontal = GROW_DIRECTION_BOTH

func _menu_button(text: String, on_pressed: Callable, font_size := MENU_FONT_SIZE) -> Button:
	var button := RewardDialog.plate_button(text)
	button.add_theme_font_size_override("font_size", font_size)
	button.custom_minimum_size.x = MENU_BUTTON_WIDTH
	button.size_flags_horizontal = SIZE_SHRINK_CENTER
	button.focus_mode = FOCUS_NONE
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	button.pressed.connect(on_pressed)
	return button

## Name, Element und Seltenheit, darunter Wachstum pro Stufe als Netzdiagramm wie im Judgement und die Werte
func _build_details() -> void:
	_name_label = _label(NAME_FONT_SIZE, MUTED)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_details.add_child(_name_label)
	# Element, Seltenheit und Ei-Attacken, bei wenig Platz in zwei Zeilen
	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", 10)
	_chips.add_theme_constant_override("v_separation", 8)
	_chips.custom_minimum_size.y = 32
	_details.add_child(_chips)

	var radar_panel := PanelContainer.new()
	radar_panel.mouse_filter = MOUSE_FILTER_PASS
	var radar_box := VBoxContainer.new()
	radar_box.add_theme_constant_override("separation", 6)
	radar_box.mouse_filter = MOUSE_FILTER_IGNORE
	IronPlate.frame(radar_panel, radar_box, 10, 8)
	_details.add_child(radar_panel)
	var heading := _label(17, GOLD)
	heading.text = tr("JUDGEMENT_GROWTH")
	radar_box.add_child(heading)
	_radar = GrowthRadar.new()
	_radar.custom_minimum_size.y = RADAR_MIN_HEIGHT
	radar_box.add_child(_radar)
	# Werte in derselben Platte unter dem Netzdiagramm
	_stats = VBoxContainer.new()
	_stats.mouse_filter = MOUSE_FILTER_IGNORE
	radar_box.add_child(_stats)

func _show_details(mon: Monster) -> void:
	_name_label.text = Helper.mon_battle_name(mon)
	_name_label.self_modulate = Helper.color_by_mon(mon)
	for chip in _chips.get_children():
		chip.queue_free()
	var element_chip: Control = ELEMENT_CHIP.instantiate()
	_chips.add_child(element_chip)
	element_chip.size_flags_horizontal = SIZE_SHRINK_BEGIN
	element_chip.set_element(mon._type)
	var rarity := Monmap.rarity_of(mon._name)
	var rarity_chip: Control = ELEMENT_CHIP.instantiate()
	_chips.add_child(rarity_chip)
	rarity_chip.size_flags_horizontal = SIZE_SHRINK_BEGIN
	rarity_chip._init_with_element({"label": Monmap.RARITY_LABELS[rarity], "color": Monmap.RARITY_COLORS[rarity]})
	# freigeschaltete Ei-Attacken der Art von allen, der Rest fehlt noch
	var egg_skills := Skills.get_all_egg_skills(mon._name)
	var unlocked: int = egg_skills.available.size()
	var total: int = unlocked + egg_skills.locked.size()
	var counts := {"unlocked": unlocked, "total": total, "missing": total - unlocked}
	var egg_chip: Control = ELEMENT_CHIP.instantiate()
	_chips.add_child(egg_chip)
	egg_chip.size_flags_horizontal = SIZE_SHRINK_BEGIN
	egg_chip._init_with_element({"label": tr("SELECTION_EGG_MOVES").format(counts), "color": EGG_CHIP_COLOR})
	egg_chip.tooltip_text = tr("SELECTION_EGG_MOVES_HINT").format(counts)
	egg_chip.mouse_filter = MOUSE_FILTER_STOP
	_radar.show_mons([{"mon": mon, "color": Helper.color_by_mon(mon)}])
	# Werte wie im Kampf (Symbol und Name über der Zahl, inkl. BST)
	for old in _stats.get_children():
		old.queue_free()
	_stats.add_child(StatsGrid.stacked_for(mon, STATS_FONT_SIZE))

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

## Blendet ein Control weich ein oder aus
func _fade(control: Control, on: bool) -> void:
	if on:
		control.modulate.a = 0.0
		control.visible = true
		create_tween().tween_property(control, "modulate:a", 1.0, FADE_SECONDS)
	else:
		var tween := create_tween()
		tween.tween_property(control, "modulate:a", 0.0, FADE_SECONDS)
		tween.tween_callback(control.hide)
