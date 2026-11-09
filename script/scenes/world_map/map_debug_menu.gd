extends RewardDialog

## Debug-Menü der Karte (nur in Debug-Builds, siehe world_map.gd add_debug_button): öffnet mit dem
## aktuellen Team jeden Ort des Spiels, unabhängig von der Position auf der Karte. Die Orte laufen über
## ihre normalen Abläufe, Fortschritt zählt also wie im echten Spiel. Texte nur auf Deutsch, Spieler sehen sie nie.

const ACCENT := Color(0.85, 0.3, 0.3)
const COLUMNS := 6
const BUTTON_SIZE := Vector2(170, 44)
const BUTTON_FONT_SIZE := 16
const HEADER_FONT_SIZE := 18
const MON_COLUMNS := 8
const MON_BUTTON_SIZE := Vector2(130, 120)
const MON_ICON_SIZE := 72
const PREVIEW_COLUMNS := 5
const PREVIEW_IMAGE_SIZE := Vector2(210, 210)
## Höhe der Vorschau-Liste, zeigt zwei Reihen und passt samt Titel und Buttons in die 720 px hohe Ansicht
const PREVIEW_LIST_HEIGHT := 480
const UNPICKED_COLOR := Color(0.65, 0.65, 0.65)
const EGG_LABEL_WIDTH := 170
const EGG_BUTTON_SIZE := Vector2(300, 44)
const STAT_NAMES := {"hp": "KP", "atk": "Angriff", "def": "Verteidigung", "s_atk": "Sp. Angriff", "s_def": "Sp. Verteidigung", "speed": "Initiative"}
const STAT_VALUE_WIDTH := 70
const STAT_STEP_SIZE := Vector2(60, 40)
const STATS_EXAMPLE_BST := 200
const RELIC_ICON_SIZE := Vector2(44, 44)
const RELIC_NAME_WIDTH := 200
const RELIC_DESC_WIDTH := 420
## Höhe der Relikt-Liste, passt samt Titel und Buttons in die 720 px hohe Ansicht
const RELIC_LIST_HEIGHT := 480
const DEBUG_ESSENCE := 500
const DEBUG_SHARDS := 5
const DEBUG_KEYS := 5
## So viel Edelstein-Bonus trägt das gefallene Test-Monster, damit Edelsteine vererbt werden können
const FALLEN_GEM_BONUS := 20
## Mit so vielen K.O.s startet der Level-Up-Bildschirm (2 K.O.s = +1 Stufe)
const LEVEL_UP_KILLS := 2
## So viele Gegner-Slots hat der Kampf (battle.tscn)
const MAX_ENEMIES := 3
## Trophäen-Zähler der Boss-Ausstattung
const TROPHY_COLUMNS := 3
const TROPHY_LABEL_WIDTH := 170
const TROPHY_VALUE_WIDTH := 50
const TROPHY_STEP_SIZE := Vector2(50, 40)

const BATTLE_PATH := "res://script/scenes/battle/battle.tscn"
const JUDGEMENT_PATH := "res://script/scenes/judgment/judgement.tscn"
const LEVEL_UP_PATH := "res://script/scenes/level_up/level_up.tscn"
const RUN_END_PATH := "res://script/scenes/run_end/run_end.tscn"
const WORLD_MAP_PATH := "res://script/scenes/world_map/world_map.tscn"
const SELECTION_PATH := "res://script/scenes/selection/selection.tscn"
const RELIC_REWARD_SCENE := preload("res://script/scenes/relic_reward/relic_reward.tscn")

## Die Karte (world_map.gd), über die die Felder geöffnet werden
var map: Control

var _main: VBoxContainer
var _fight_page: VBoxContainer
## Startet den Kampf, für den gerade die Gegnerzahl gewählt wird
var _fight_start: Callable
## Boss-Ausstattung auf der Gegnerzahl-Seite, nur bei Boss-Kämpfen sichtbar
var _boss_options: VBoxContainer
var _boss_relic_picks: Array = []
var _trophy_mode_button: Button
var _trophy_custom := false
## Stat-Key -> Anzahl Trophäen dieser Art pro Boss
var _trophy_counts := {}
var _trophy_labels := {}
var _picker: VBoxContainer
## Arten, die im Judgement als Fänge bereitliegen
var _picked: Array[String] = []
var _fallen_check: CheckBox
var _start_button: Button
var _rotten_eggs_button: Button
var _egg_page: VBoxContainer
var _egg_rows: VBoxContainer
## Art, deren Ei-Attacken gerade angezeigt werden
var _egg_species: String
var _stats_page: VBoxContainer
var _stats_summary: Label
## Wert -> Label mit dem reservierten Anteil
var _stat_values := {}
var _relic_page: VBoxContainer
var _relic_rows: VBoxContainer
var _preview_page: VBoxContainer
## Art -> Bild in der Vorschau
var _preview_images := {}
var _preview_back := false
var _preview_view_button: Button
var _vfx_page: VBoxContainer
## Monster auf der VFX-Seite, an dem die Effekte abgespielt werden
var _vfx_target: TextureRect
var _vfx_back := false
var _vfx_view_button: Button
## Sicherheitsabfrage vor dem Löschen des Spielstands
var _reset_page: VBoxContainer

func _ready() -> void:
	set_accent(ACCENT)
	set_title("DEBUG")
	# keine Preise und Ziele, nur Buttons
	_columns.visible = false
	_build_main()
	_build_fight_page()
	_build_picker()
	_build_egg_page()
	_build_stats_page()
	_build_relic_page()
	_build_preview_page()
	_build_vfx_page()
	_build_reset_page()
	_show_page(_main)

func _build_main() -> void:
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 8)
	add_footer(_main)

	var is_last_biome: bool = State.map_level == Map.map_settings.size() - 1
	_add_section(_main, "Kämpfe", [
		[tr(Map.type_label(Map.PATH_TYPE.COMBAT)) + " ...", _open_fight_page.bind(_change_scene.bind(BATTLE_PATH))],
		["BOSS-FELD ...", _open_fight_page.bind(_start_map_boss, true)],
		["ENDBOSS ..." if is_last_biome else "BIOM-BOSS ...", _open_fight_page.bind(map.start_biome_boss, true)],
	])

	var fields := []
	for type in [Map.PATH_TYPE.CAMP, Map.PATH_TYPE.HUB, Map.PATH_TYPE.SHOP, Map.PATH_TYPE.TRAINER, Map.PATH_TYPE.JAILER, Map.PATH_TYPE.GEM, Map.PATH_TYPE.TREASURE]:
		fields.append([tr(Map.type_label(type)), _open_field.bind(type)])
	fields.append(["SCHATZ AUTOMATISCH", _collect_treasure])
	fields.append(["GLÜCKSRAD", _open_wheel])
	fields.append(["VOID", _open_void])
	_add_section(_main, "Felder", fields)

	_add_section(_main, "Nach dem Kampf", [
		["JUDGEMENT ...", func(): _show_page(_picker)],
		["LEVEL-UP", _open_level_up],
		["RELIC-AUSWAHL", _open_relic_reward],
		["FÄHIGKEITEN-AUSWAHL", _open_skill_reward],
		["RUN-ENDE SIEG", _end_run.bind(true)],
		["RUN-ENDE NIEDERL.", _end_run.bind(false)],
	])

	var biomes := []
	for depth in State.biome_path.size():
		biomes.append(["%d %s" % [depth + 1, tr(ColorMap.get_combo(State.biome_path[depth]).label)], _switch_biome.bind(depth)])
	_add_section(_main, "Biom wechseln (neue Karte)", biomes)

	var extras := _add_section(_main, "Ressourcen und nächster Run", [
		["+%d ESSENZ" % DEBUG_ESSENCE, _add_essence],
		["+%d BOSS TRÄNEN" % DEBUG_SHARDS, _add_shards],
		["+%d SCHLÜSSEL" % DEBUG_KEYS, _add_keys],
		["+1 GUTSCHEIN", _add_coupon],
	])
	_rotten_eggs_button = _make_button(_rotten_eggs_text(), _toggle_rotten_eggs)
	extras.add_child(_rotten_eggs_button)
	extras.add_child(_make_button("EI-ATTACKEN ...", func(): _show_page(_egg_page)))
	extras.add_child(_make_button("WERTE-VERTEILUNG ...", func(): _show_page(_stats_page)))
	extras.add_child(_make_button("RELIKTE ...", func(): _show_page(_relic_page)))
	extras.add_child(_make_button("MONSTER-VORSCHAU ...", func(): _show_page(_preview_page)))
	extras.add_child(_make_button("VFX-VORSCHAU ...", func(): _show_page(_vfx_page)))
	extras.add_child(_make_button("SPIELSTAND LÖSCHEN ...", func(): _show_page(_reset_page)))

	var close_button := _make_button("SCHLIESSEN", close)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_main.add_child(close_button)

## Gegnerzahl vor dem Kampfstart. WIE IM SPIEL lässt das Biom bzw. den Boss entscheiden.
func _build_fight_page() -> void:
	_fight_page = VBoxContainer.new()
	_fight_page.add_theme_constant_override("separation", 12)
	add_footer(_fight_page)

	var entries := [["WIE IM SPIEL", _start_fight.bind(0)]]
	for count in range(1, MAX_ENEMIES + 1):
		entries.append([str(count), _start_fight.bind(count)])
	_add_section(_fight_page, "Gegen wie viele Monster?", entries)
	_build_boss_options()

	var back_button := _make_button("ZURÜCK", _show_page.bind(_main))
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_fight_page.add_child(back_button)

## Judgement-Auswahl: beliebig viele Arten als Fänge, die dort bereitliegen
func _build_picker() -> void:
	_picker = VBoxContainer.new()
	_picker.add_theme_constant_override("separation", 12)
	add_footer(_picker)

	_picker.add_child(_make_header("Judgement: Welche Monster liegen als neue Fänge bereit?"))
	var grid := GridContainer.new()
	grid.columns = MON_COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_picker.add_child(grid)
	for meta in Monmap.mons:
		var button := _make_mon_button(meta.name)
		button.toggled.connect(func(on: bool):
			if on:
				_picked.append(meta.name)
			else:
				_picked.erase(meta.name)
			_refresh_start())
		grid.add_child(button)

	_fallen_check = CheckBox.new()
	_fallen_check.text = "Zusätzlich ein gefallenes Monster (Wiederbelebung und Letzter Wille)"
	_fallen_check.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	_fallen_check.toggled.connect(func(_on): _refresh_start())
	_picker.add_child(_fallen_check)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_make_button("ZURÜCK", _show_page.bind(_main)))
	_start_button = _make_button("JUDGEMENT STARTEN", _start_judgement)
	row.add_child(_start_button)
	_picker.add_child(row)
	_refresh_start()

## Ei-Attacken: oben die Art, darunter ihre freischaltbaren Attacken als Schalter
func _build_egg_page() -> void:
	_egg_page = VBoxContainer.new()
	_egg_page.add_theme_constant_override("separation", 12)
	add_footer(_egg_page)

	_egg_page.add_child(_make_header("Ei-Attacken (dauerhaft im Spielstand, Gold = freigeschaltet)"))
	var grid := GridContainer.new()
	grid.columns = MON_COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_egg_page.add_child(grid)
	_egg_rows = VBoxContainer.new()
	_egg_rows.add_theme_constant_override("separation", 8)
	var species_group := ButtonGroup.new()
	var first: Button
	for meta in Monmap.mons:
		var button := _make_mon_button(meta.name)
		button.button_group = species_group
		button.toggled.connect(func(on: bool):
			if on:
				_show_egg_skills(meta.name))
		grid.add_child(button)
		if first == null:
			first = button
	_egg_page.add_child(_egg_rows)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_make_button("ZURÜCK", _show_page.bind(_main)))
	row.add_child(_make_button("ALLE DIESER ART", func(): _set_species_unlocked(true)))
	row.add_child(_make_button("KEINE DIESER ART", func(): _set_species_unlocked(false)))
	row.add_child(_make_button("ALLE ARTEN", _unlock_all_species))
	_egg_page.add_child(row)
	first.button_pressed = true

## Alle Monster auf einen Blick, mit demselben Material wie im Spiel
func _build_preview_page() -> void:
	_preview_page = VBoxContainer.new()
	_preview_page.add_theme_constant_override("separation", 12)
	add_footer(_preview_page)

	_preview_page.add_child(_make_header("Monster-Vorschau"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = PREVIEW_LIST_HEIGHT
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_preview_page.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = PREVIEW_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for meta in Monmap.mons:
		var entry := VBoxContainer.new()
		var image := TextureRect.new()
		_preview_images[meta.name] = image
		image.custom_minimum_size = PREVIEW_IMAGE_SIZE
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		entry.add_child(image)
		var label := Label.new()
		label.text = Helper.mon_display_name(meta.name)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.x = PREVIEW_IMAGE_SIZE.x
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
		entry.add_child(label)
		grid.add_child(entry)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_make_button("ZURÜCK", _show_page.bind(_main)))
	_preview_view_button = _make_button("", _toggle_preview_view)
	row.add_child(_preview_view_button)
	_preview_page.add_child(row)
	_refresh_preview()

func _toggle_preview_view() -> void:
	_preview_back = not _preview_back
	_refresh_preview()

func _refresh_preview() -> void:
	_preview_view_button.text = "ANSICHT: HINTEN" if _preview_back else "ANSICHT: VORNE"
	for species in _preview_images:
		Monmap.show_on(_preview_images[species], species, PREVIEW_IMAGE_SIZE.x, _preview_back)

## Kampf-Effekte (BattleVfx) an einem Monster ansehen, ohne einen Kampf zu starten.
## Größe wie im Kampf: Radius = 40 % des Monsterbilds (siehe MonsterScene._spawn_vfx).
const BATTLE_VFX := preload("res://script/scenes/battle/battle_vfx.gd")
const BATTLE_VFX_LAYER := preload("res://script/scenes/battle/battle_vfx_layer.gd")
const VFX_TARGET_SIZE := Vector2(256, 256)
## Platz um das Monster, damit überstehende Effekte (Brocken von oben, Funken) nicht in die Buttons ragen
const VFX_STAGE_SIZE := Vector2(420, 420)
## Buttons pro Reihe in der scrollbaren Liste links
const VFX_COLUMNS := 3
## Höhe der Liste, passt samt Titel und Steuerung oben in die 720 px hohe Ansicht
const VFX_LIST_HEIGHT := 480
## Pause zwischen zwei Effekten bei ALLE NACHEINANDER
const VFX_SEQUENCE_PAUSE := 1.0

## Oben die Steuerung, darunter links die Kategorien zum Scrollen, rechts das Monster als Bühne
func _build_vfx_page() -> void:
	_vfx_page = VBoxContainer.new()
	_vfx_page.add_theme_constant_override("separation", 12)
	add_footer(_vfx_page)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	controls.add_child(_make_button("ZURÜCK", _show_page.bind(_main)))
	controls.add_child(_make_button("ALLE NACHEINANDER", _play_all_vfx))
	_vfx_view_button = _make_button("", _toggle_vfx_view)
	controls.add_child(_vfx_view_button)
	_vfx_page.add_child(controls)
	_vfx_page.add_child(_make_header("VFX-Vorschau: Effekte am Monster wie im Kampf"))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	_vfx_page.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = VFX_LIST_HEIGHT
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var kinds = BATTLE_VFX.Kind
	_add_section(list, "Physischer Hieb (in der Elementfarbe)", [
		["HIEB ERDE", _play_vfx.bind(kinds.SLASH, Enums.MON_TYPES.EARTH)],
		["HIEB FEUER", _play_vfx.bind(kinds.SLASH, Enums.MON_TYPES.FIRE)],
		["HIEB WASSER", _play_vfx.bind(kinds.SLASH, Enums.MON_TYPES.WATER)],
		["HIEB LUFT", _play_vfx.bind(kinds.SLASH, Enums.MON_TYPES.AIR)],
	], VFX_COLUMNS)
	_add_section(list, "Magische Angriffe", [
		["FEUER", _play_vfx.bind(kinds.FIRE)],
		["WASSER", _play_vfx.bind(kinds.WATER)],
		["ERDE", _play_vfx.bind(kinds.EARTH)],
		["LUFT", _play_vfx.bind(kinds.AIR)],
		["MAGMA (KOMBI)", _play_vfx_kinds.bind(BATTLE_VFX.element_kinds(Enums.MON_TYPES.EARTH | Enums.MON_TYPES.FIRE))],
	], VFX_COLUMNS)
	_add_section(list, "Schilde", [
		["SCHILD", _play_vfx.bind(kinds.SHIELD)],
		["MAG. SCHILD", _play_vfx.bind(kinds.S_SHIELD)],
		["SCHILD-TREFFER", _play_vfx.bind(kinds.SHIELD_HIT)],
		["MAG. SCHILD-TREFFER", _play_vfx.bind(kinds.S_SHIELD_HIT)],
	], VFX_COLUMNS)
	_add_section(list, "Buffs", [
		["BUFF", _play_vfx.bind(kinds.BUFF)],
	], VFX_COLUMNS)

	var stage := CenterContainer.new()
	stage.custom_minimum_size = VFX_STAGE_SIZE
	stage.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(stage)
	_vfx_target = TextureRect.new()
	_vfx_target.custom_minimum_size = VFX_TARGET_SIZE
	_vfx_target.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vfx_target.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_vfx_target.material = Monmap.MONSTER_MATERIAL
	stage.add_child(_vfx_target)
	_refresh_vfx_target()

## Erstes eigenes Monster, sonst das erste bekannte
func _vfx_species() -> String:
	return State.mons[0]._name if not State.mons.is_empty() else Monmap.mons[0].name

func _toggle_vfx_view() -> void:
	_vfx_back = not _vfx_back
	_refresh_vfx_target()

func _refresh_vfx_target() -> void:
	_vfx_view_button.text = "ANSICHT: HINTEN" if _vfx_back else "ANSICHT: VORNE"
	Monmap.show_on(_vfx_target, _vfx_species(), VFX_TARGET_SIZE.x, _vfx_back)

## Wie im Kampf über die Effekt-Bühne mit "Lebende Pixel"-Shader (battle_vfx_layer.gd)
func _play_vfx(kind: int, nature := 0) -> void:
	var accent := Color(ColorMap.get_combo(nature).color) if nature != 0 else Color.WHITE
	BATTLE_VFX_LAYER.for_target(_vfx_target, _vfx_target).play(kind, accent)

func _play_vfx_kinds(kinds: Array) -> void:
	for kind in kinds:
		_play_vfx(kind)

func _play_all_vfx() -> void:
	var kinds = BATTLE_VFX.Kind
	var sequence := [[kinds.SLASH, Enums.MON_TYPES.FIRE], [kinds.FIRE, 0], [kinds.WATER, 0], [kinds.EARTH, 0], [kinds.AIR, 0],
		[kinds.SHIELD, 0], [kinds.SHIELD_HIT, 0], [kinds.S_SHIELD, 0], [kinds.S_SHIELD_HIT, 0], [kinds.BUFF, 0]]
	for entry in sequence:
		# Seite gewechselt oder Menü geschlossen: Abfolge abbrechen
		if not is_inside_tree() or not _vfx_page.visible:
			return
		_play_vfx(entry[0], entry[1])
		await get_tree().create_timer(VFX_SEQUENCE_PAUSE).timeout

func _show_page(page: VBoxContainer) -> void:
	for other in [_main, _fight_page, _picker, _egg_page, _stats_page, _relic_page, _preview_page, _vfx_page, _reset_page]:
		other.visible = other == page

func _refresh_start() -> void:
	# ohne Fang und Gefallenen würde das Judgement sofort zurück zur Karte springen
	_start_button.disabled = _picked.is_empty() and not _fallen_check.button_pressed

func _add_section(parent: Control, title: String, entries: Array, columns := COLUMNS) -> GridContainer:
	parent.add_child(_make_header(title))
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	for entry in entries:
		grid.add_child(_make_button(entry[0], entry[1]))
	return grid

func _make_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	label.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
	return label

func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := plate_button(text)
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.custom_minimum_size = BUTTON_SIZE
	button.pressed.connect(on_pressed)
	return button

## Schalter: eingeschaltet hell mit goldener Schrift, sonst abgedunkelt
func _make_toggle_button(text: String) -> Button:
	var button := plate_button(text)
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.add_theme_color_override("font_hover_pressed_color", SkillDetailPopup.GOLD)
	button.toggle_mode = true
	button.modulate = UNPICKED_COLOR
	button.toggled.connect(func(on: bool): button.modulate = Color.WHITE if on else UNPICKED_COLOR)
	return button

func _make_mon_button(mon_species: String) -> Button:
	var button := _make_toggle_button(Helper.mon_display_name(mon_species))
	button.custom_minimum_size = MON_BUTTON_SIZE
	button.icon = Monmap.texture(mon_species, Monmap.ICON)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.add_theme_constant_override("icon_max_width", MON_ICON_SIZE)
	return button

# ─────────────────────────
# Orte

func _change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

func _open_fight_page(start: Callable, boss := false) -> void:
	_fight_start = start
	_boss_options.visible = boss
	_show_page(_fight_page)

func _start_fight(enemy_count: int) -> void:
	DebugSettings.next_enemy_count = enemy_count
	var boss := _boss_options.visible
	DebugSettings.next_boss_relics = _boss_relic_picks.duplicate() if boss and not _boss_relic_picks.is_empty() else null
	DebugSettings.next_boss_trophies = _trophy_counts.duplicate() if boss and _trophy_custom else null
	_fight_start.call()

# ─────────────────────────
# Boss-Ausstattung (nur für Boss-Kämpfe auf der Gegnerzahl-Seite)

## Relikte als Schalter (keins = wie im Spiel), Trophäen pro Art mit Zähler (WIE IM SPIEL oder EIGENE)
func _build_boss_options() -> void:
	_boss_options = VBoxContainer.new()
	_boss_options.add_theme_constant_override("separation", 8)
	_fight_page.add_child(_boss_options)

	_boss_options.add_child(_make_header("Boss-Relikte des Kampfs (keins gewählt = wie im Spiel, %d zufällig)" % BossRelics.RELICS_PER_BATTLE))
	var relic_grid := GridContainer.new()
	relic_grid.columns = COLUMNS
	relic_grid.add_theme_constant_override("h_separation", 8)
	relic_grid.add_theme_constant_override("v_separation", 8)
	_boss_options.add_child(relic_grid)
	for id in BossRelics.RELICS:
		var button := _make_toggle_button(tr(BossRelics.get_relic(id).name))
		button.custom_minimum_size = BUTTON_SIZE
		button.tooltip_text = BossRelics.description(id)
		button.toggled.connect(func(on: bool):
			if on:
				_boss_relic_picks.append(id)
			else:
				_boss_relic_picks.erase(id))
		relic_grid.add_child(button)

	var default_count: int = BossRelics.default_trophies(Map.encounter_depth()).values()[0]
	_boss_options.add_child(_make_header("Trophäen pro Boss, Anzahl je Art (wie im Spiel in diesem Biom: je %dx)" % default_count))
	_trophy_mode_button = _make_toggle_button("")
	_trophy_mode_button.custom_minimum_size = BUTTON_SIZE
	_trophy_mode_button.toggled.connect(func(on: bool):
		_trophy_custom = on
		_refresh_trophy_mode())
	_boss_options.add_child(_trophy_mode_button)
	var trophy_grid := GridContainer.new()
	trophy_grid.columns = TROPHY_COLUMNS
	trophy_grid.add_theme_constant_override("h_separation", 24)
	trophy_grid.add_theme_constant_override("v_separation", 8)
	_boss_options.add_child(trophy_grid)
	for stat in DebugSettings.STATS:
		_trophy_counts[stat] = default_count
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		var label := _make_header(STAT_NAMES[stat])
		label.custom_minimum_size.x = TROPHY_LABEL_WIDTH
		cell.add_child(label)
		cell.add_child(_make_trophy_step_button(stat, -1))
		var value := _make_header("")
		value.custom_minimum_size.x = TROPHY_VALUE_WIDTH
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(value)
		_trophy_labels[stat] = value
		cell.add_child(_make_trophy_step_button(stat, 1))
		trophy_grid.add_child(cell)
	_refresh_trophy_mode()

## Ein Zähler schaltet auf eigene Trophäen um
func _make_trophy_step_button(stat: String, step: int) -> Button:
	var button := _make_button("%+d" % step, func():
		_trophy_counts[stat] = maxi(_trophy_counts[stat] + step, 0)
		_trophy_mode_button.button_pressed = true
		_refresh_trophy_mode())
	button.custom_minimum_size = TROPHY_STEP_SIZE
	return button

func _refresh_trophy_mode() -> void:
	_trophy_mode_button.text = "TROPHÄEN: " + ("EIGENE" if _trophy_custom else "WIE IM SPIEL")
	for stat in _trophy_labels:
		_trophy_labels[stat].text = "%dx" % _trophy_counts[stat]
		_trophy_labels[stat].modulate = Color.WHITE if _trophy_custom else UNPICKED_COLOR

func _start_map_boss() -> void:
	State.is_map_boss = true
	_change_scene(BATTLE_PATH)

func _open_field(type: Map.PATH_TYPE) -> void:
	close()
	map.call_event_by_type(type)

func _open_wheel() -> void:
	close()
	map.open_wheel_event()

func _open_void() -> void:
	if not Relics.can_swap() and not _prepare_relic_swap():
		Helper.show_unlock_message("Void braucht zwei aktive Relikte gleicher Seltenheit")
		return
	close()
	map.open_void_event()

## Tauschen braucht ein Relikt im Besitz und eins gleicher Seltenheit, das noch frei ist: stellt das her
func _prepare_relic_swap() -> bool:
	for id in Relics.RELICS:
		var partners: Array = Relics.RELICS.keys().filter(func(other): return other != id and Relics.is_active(other) and Relics.RELICS[other].rarity == Relics.RELICS[id].rarity)
		if not partners.is_empty():
			Relics.add_relic(id)
			Relics.remove_relic(partners[0])
			return true
	return false

## Öffnet den Schatz ohne Auswahl: Essenz und Bonus-Preis kommen direkt an
func _collect_treasure() -> void:
	close()
	var treasure: RewardDialog = map.treasure_scene.instantiate()
	map.view_container.add_child(treasure)
	Helper.show_unlock_message("Schatz: " + ", ".join(treasure.take_all()))

func _open_level_up() -> void:
	State.killed_monsters = LEVEL_UP_KILLS
	State.pending_ep = DEBUG_ESSENCE
	State.pending_keys = 1
	State.pending_gems = 1
	State.pending_coupons = 1
	State.pending_boss_shards = 1
	State.pending_relic_chest = not Relics.get_unowned().is_empty()
	State.pending_skill_envelope = not Skills.reward_offers().is_empty()
	_change_scene(LEVEL_UP_PATH)

func _open_relic_reward() -> void:
	if Relics.get_unowned().is_empty():
		Helper.show_unlock_message("Alle Relics sind schon gesammelt oder ausgeschaltet")
		return
	close()
	map.view_container.add_child(RELIC_REWARD_SCENE.instantiate())

func _open_skill_reward() -> void:
	if Skills.reward_offers().is_empty():
		Helper.show_unlock_message("Alle einzigartigen Skills sind schon gelernt")
		return
	close()
	map.view_container.add_child(map.SKILL_REWARD_SCENE.instantiate())

func _end_run(won: bool) -> void:
	State.end_run(won)
	_change_scene(RUN_END_PATH)

func _switch_biome(depth: int) -> void:
	State.map_level = depth
	State.biome_fight_index = 0
	State.current_map_position = State.NO_MAP_POSITION
	Map.generate_starting_points()
	_change_scene(WORLD_MAP_PATH)

func _add_essence() -> void:
	State.ep += DEBUG_ESSENCE
	Helper.show_unlock_message("+%d Essenz" % DEBUG_ESSENCE)

func _add_shards() -> void:
	# wie beim Boss-Sieg auch im Spielstand, der Kerkermeister zieht sie dort wieder ab
	SaveManager.add_boss_shard(DEBUG_SHARDS)
	State.boss_shards += DEBUG_SHARDS
	Helper.show_unlock_message("+%d Boss Tränen" % DEBUG_SHARDS)

func _add_keys() -> void:
	State.keys += DEBUG_KEYS
	Helper.show_unlock_message("+%d Schlüssel" % DEBUG_KEYS)

func _add_coupon() -> void:
	State.coupons += 1
	Helper.show_unlock_message("+1 Gutschein")

func _rotten_eggs_text() -> String:
	return "FAULE EIER: " + ("AN" if SaveManager.has_full_reroll_charges() else "AUS")

## Volle Ladungen zeigen in der nächsten Ei-Auswahl den Button "Faule Eier", AUS leert sie
func _toggle_rotten_eggs() -> void:
	SaveManager.set_reroll_charges(0 if SaveManager.has_full_reroll_charges() else SaveManager.REROLL_CHARGES_NEEDED)
	_rotten_eggs_button.text = _rotten_eggs_text()

# ─────────────────────────
# Werte-Verteilung

## Reserve pro Wert
func _build_stats_page() -> void:
	_stats_page = VBoxContainer.new()
	_stats_page.add_theme_constant_override("separation", 10)
	add_footer(_stats_page)

	_stats_page.add_child(_make_header("Werte-Verteilung: fester Anteil der BST pro Wert"))
	for stat in DebugSettings.STATS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := _make_header(STAT_NAMES[stat])
		label.custom_minimum_size.x = EGG_LABEL_WIDTH
		row.add_child(label)
		for step in [-5, -1]:
			row.add_child(_make_step_button(stat, step))
		var value := _make_header("")
		value.custom_minimum_size.x = STAT_VALUE_WIDTH
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(value)
		_stat_values[stat] = value
		for step in [1, 5]:
			row.add_child(_make_step_button(stat, step))
		_stats_page.add_child(row)
	_stats_summary = _make_header("")
	_stats_page.add_child(_stats_summary)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_make_button("ZURÜCK", _show_page.bind(_main)))
	row.add_child(_make_button("STANDARD", func():
		DebugSettings.reset_reserved()
		_refresh_stats_page()))
	_stats_page.add_child(row)
	_refresh_stats_page()

func _make_step_button(stat: String, step: int) -> Button:
	var button := _make_button("%+d" % step, func():
		DebugSettings.set_reserved(stat, DebugSettings.reserved(stat) + step)
		_refresh_stats_page())
	button.custom_minimum_size = STAT_STEP_SIZE
	return button

func _refresh_stats_page() -> void:
	for stat in DebugSettings.STATS:
		_stat_values[stat].text = "%d %%" % DebugSettings.reserved(stat)
	var total := DebugSettings.reserved_total()
	_stats_summary.text = "Reserviert: %d %%, üblicher Weg: %d %%. Bei %d BST: %d fest, %d werden wie gewohnt verteilt. Gilt sofort, auch im laufenden Run." % [
		total, 100 - total, STATS_EXAMPLE_BST, STATS_EXAMPLE_BST * total / 100, STATS_EXAMPLE_BST * (100 - total) / 100]

# ─────────────────────────
# Relikte

## Pro Relikt zwei Schalter: BESITZ gibt es direkt oder nimmt es wieder weg, AKTIV schaltet es ganz ab
func _build_relic_page() -> void:
	_relic_page = VBoxContainer.new()
	_relic_page.add_theme_constant_override("separation", 12)
	add_footer(_relic_page)

	_relic_page.add_child(_make_header("Relikte: BESITZ gilt für diesen Run, AKTIV: NEIN (keine Wirkung, kein Angebot) bleibt gespeichert"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = RELIC_LIST_HEIGHT
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_relic_page.add_child(scroll)
	_relic_rows = VBoxContainer.new()
	_relic_rows.add_theme_constant_override("separation", 8)
	_relic_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_relic_rows)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_make_button("ZURÜCK", _show_page.bind(_main)))
	row.add_child(_make_button("ALLE BEKOMMEN", _for_all_relics.bind(Relics.add_relic)))
	row.add_child(_make_button("ALLE ABGEBEN", _for_all_relics.bind(Relics.remove_relic)))
	row.add_child(_make_button("ALLE AN", _for_all_relics.bind(func(id: String): Relics.set_active(id, true))))
	row.add_child(_make_button("ALLE AUS", _for_all_relics.bind(func(id: String): Relics.set_active(id, false))))
	_relic_page.add_child(row)
	_refresh_relic_rows()

func _refresh_relic_rows() -> void:
	for child in _relic_rows.get_children():
		_relic_rows.remove_child(child)
		child.queue_free()
	for id in Relics.RELICS:
		_relic_rows.add_child(_make_relic_row(id))

func _make_relic_row(id: String) -> HBoxContainer:
	var relic: Dictionary = Relics.get_relic(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon := TextureRect.new()
	icon.texture = load(relic.icon)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = RELIC_ICON_SIZE
	row.add_child(icon)

	var relic_name := _make_header(tr(relic.name))
	relic_name.custom_minimum_size.x = RELIC_NAME_WIDTH
	relic_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	relic_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(relic_name)

	row.add_child(_make_relic_toggle("BESITZ", Relics.has_relic(id), func(on: bool):
		if on:
			Relics.add_relic(id)
		else:
			Relics.remove_relic(id)))
	row.add_child(_make_relic_toggle("AKTIV", Relics.is_active(id), func(on: bool): Relics.set_active(id, on)))

	var description := Label.new()
	description.text = tr(relic.description)
	description.custom_minimum_size.x = RELIC_DESC_WIDTH
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	row.add_child(description)
	return row

func _make_relic_toggle(label: String, on: bool, apply: Callable) -> Button:
	var button := _make_toggle_button(_relic_toggle_text(label, on))
	button.custom_minimum_size = BUTTON_SIZE
	button.button_pressed = on
	button.toggled.connect(func(now_on: bool):
		apply.call(now_on)
		button.text = _relic_toggle_text(label, now_on))
	return button

func _relic_toggle_text(label: String, on: bool) -> String:
	return "%s: %s" % [label, "JA" if on else "NEIN"]

func _for_all_relics(action: Callable) -> void:
	for id in Relics.RELICS:
		action.call(id)
	_refresh_relic_rows()

# ─────────────────────────
# Ei-Attacken

## Freischaltbare Ei-Attacken der Art, nach Herkunft: [[Überschrift, Skill-Namen], ...]
func _egg_skill_groups(mon_species: String) -> Array:
	var meta: Dictionary = Monmap.mon_metainfos_by_name(mon_species)
	return [
		["Fangen & Opfern", meta.get("unlockable_egg_skills", [])],
		["Meilensteine", meta.get("milestone_egg_skills", {}).values()],
		["Kopfgelder", meta.get("bounty_egg_skills", {}).values()],
	]

func _show_egg_skills(mon_species: String) -> void:
	_egg_species = mon_species
	for child in _egg_rows.get_children():
		_egg_rows.remove_child(child)
		child.queue_free()
	for group in _egg_skill_groups(mon_species):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := _make_header(group[0])
		label.custom_minimum_size.x = EGG_LABEL_WIDTH
		row.add_child(label)
		for skill_name in group[1]:
			row.add_child(_make_egg_skill_button(mon_species, skill_name))
		_egg_rows.add_child(row)

func _make_egg_skill_button(mon_species: String, skill_name: String) -> Button:
	var button := _make_toggle_button(tr(skill_name))
	button.custom_minimum_size = EGG_BUTTON_SIZE
	button.tooltip_text = Helper.skill_description(Skills.get_skill(skill_name))
	button.button_pressed = SaveManager.is_egg_skill_unlocked(mon_species, skill_name)
	button.toggled.connect(func(on: bool): _set_egg_skill(mon_species, skill_name, on))
	return button

func _set_egg_skill(mon_species: String, skill_name: String, unlocked: bool) -> void:
	if unlocked:
		SaveManager.unlock_egg_skill(mon_species, skill_name)
	else:
		SaveManager.lock_egg_skill(mon_species, skill_name)

func _set_species_unlocked(unlocked: bool) -> void:
	for group in _egg_skill_groups(_egg_species):
		for skill_name in group[1]:
			_set_egg_skill(_egg_species, skill_name, unlocked)
	_show_egg_skills(_egg_species)

func _unlock_all_species() -> void:
	for meta in Monmap.mons:
		for group in _egg_skill_groups(meta.name):
			for skill_name in group[1]:
				SaveManager.unlock_egg_skill(meta.name, skill_name)
	_show_egg_skills(_egg_species)
	Helper.show_unlock_message("Alle Ei-Attacken freigeschaltet")

# ─────────────────────────
# Judgement

func _start_judgement() -> void:
	var level: int = State.INITIAL_LEVEL
	for mon in State.mons:
		level = maxi(level, mon._level)
	for mon_species in _picked:
		# wie beim Fangen (catch_anim.gd)
		var mon := _wild_mon(mon_species, level)
		mon._initial_moves = Monster.BASE_MOVES
		State.catched_mons.append(mon)
		State.mark_mon_caught(mon_species)
	if _fallen_check.button_pressed:
		# ein neues Monster statt eines aus dem Team, das aktuelle Team bleibt unangetastet
		var fallen := _wild_mon(Monmap.mons.pick_random().name, level)
		fallen.add_gem("atk", FALLEN_GEM_BONUS)
		State.fainted_own_mons.append(fallen)
	_change_scene(JUDGEMENT_PATH)

## Wildes Monster einer bestimmten Art, immer mit Ei-Attacke (falls noch eine offen ist), damit Opfern möglich ist
func _wild_mon(mon_species: String, level: int) -> Monster:
	var meta: Dictionary = Monmap.mon_metainfos_by_name(mon_species)
	var mon := Monster.new(level, meta)
	mon._bounty = meta.get("bounty_target", "")
	Helper.add_biome_element(mon)
	Helper.roll_wild_skills(mon, meta)
	Helper.add_egg_skill(mon)
	mon.unlock_skills()
	return mon

# ─────────────────────────
# Spielstand löschen

## Sicherheitsabfrage: erst JA, LÖSCHEN setzt den Spielstand zurück
func _build_reset_page() -> void:
	_reset_page = VBoxContainer.new()
	_reset_page.add_theme_constant_override("separation", 12)
	add_footer(_reset_page)

	_reset_page.add_child(_make_header("Spielstand wirklich löschen?"))
	var info := Label.new()
	info.text = "Gefangene Monster, freigeschaltete Ei-Attacken, Meilensteine, Boss Tränen und der laufende Run sind danach weg.\nDas Spiel startet neu bei der Ei-Auswahl. Einstellungen bleiben erhalten."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 600
	info.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	_reset_page.add_child(info)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_make_button("ZURÜCK", _show_page.bind(_main)))
	var confirm := _make_button("JA, LÖSCHEN", _reset_save)
	confirm.add_theme_color_override("font_color", ACCENT)
	row.add_child(confirm)
	_reset_page.add_child(row)

func _reset_save() -> void:
	SaveManager.reset_game()
	State.reset()
	State.boss_shards = 0
	_change_scene(SELECTION_PATH)
