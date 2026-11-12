class_name StatsGrid
extends GridContainer

@export var label: Label
@export var is_leveling: bool = false
## Alle Werte in einer Zeile: Name in Gold, direkt dahinter die Zahl
@export var horizontal: bool = false
## Eine Spalte pro Wert: oben der Name in Gold, darunter die Zahl (Kampf, Ei-Auswahl)
@export var stacked: bool = false
## Nur bei stacked (Map-Header-Dialog, Trophäen-Feld): hinter jeder Zahl der Trophäen-Anteil "(N)" und darunter
## die Trophäen dieses Werts (Symbol und Anzahl)
@export var show_trophies: bool = false

const GAIN_COLOR := Color(0.45, 0.85, 0.45)

## Symbol pro Wert (weiße Linien), auch oben rechts auf den Fähigkeiten (Skills.kind_icon):
## Faust = physischer Angriff, Funken = magischer Angriff, Schild = Verteidigung, Schild mit Funken = Sp. Verteidigung
const ICONS := {
	"hp": preload("res://assets/ui/icons/stat_heart.svg"),
	"atk": preload("res://assets/ui/icons/fist.svg"),
	"def": preload("res://assets/ui/icons/stat_shield.svg"),
	"s_atk": preload("res://assets/ui/icons/sparkle.svg"),
	"s_def": preload("res://assets/ui/icons/stat_s_shield.svg"),
	"speed": preload("res://assets/ui/icons/stat_pentagram.svg"),
	"bst": preload("res://assets/ui/icons/stat_arrow_up.svg"),
}
const ICON_ALPHA := 0.8
## Symbolgröße relativ zur Schriftgröße der Beschriftung
const ICON_SCALE := 1.15
const DEFAULT_FONT_SIZE := 16
## Trophäen-Bonus hinter der Zahl ("+6" in Grün), etwas kleiner als die Zahl
const TROPHY_BONUS_FONT_SCALE := 0.8
const TROPHY_ICON_SCALE := 1.1
const GEM_FIELD_PATH := "res://script/scenes/gems/gems.gd"

var plabels: Array[Label] = []
## nur bei stacked: Stat-Key -> Label mit der Zahl
var _value_labels := {}

## Werte-Tabelle ohne eigene Szene, mit stacked-Layout (trophies: Trophäen-Anteil und Trophäen unter den Werten)
static func stacked_for(monster: Monster, font_size := 15, trophies := false) -> StatsGrid:
	var grid := StatsGrid.new()
	grid.stacked = true
	grid.show_trophies = trophies
	grid.add_theme_constant_override("h_separation", 3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var template := Label.new()
	template.visible = false
	template.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	template.add_theme_font_size_override("font_size", font_size)
	grid.add_child(template)
	grid.label = template
	grid.init_with_mon(monster)
	return grid

var map = [
	{
		"key": "hp",
		"label": "STAT_HP",
		"value": func(monster:Monster): return monster.hp(),
	},
	{
		"key": "atk",
		"label": "STAT_ATK",
		"value": func(monster:Monster): return monster.attack(),
	},
	{
		"key": "def",
		"label": "STAT_DEF",
		"value": func(monster:Monster): return monster.defense(),
	},
	{
		"key": "s_atk",
		"label": "STAT_SPA",
		"value": func(monster:Monster): return monster.s_attack(),
	},
	{
		"key": "s_def",
		"label": "STAT_SPD",
		"value": func(monster:Monster): return monster.s_defense(),
	},
	{
		"key": "speed",
		"label": "STAT_SPE",
		"value": func(monster:Monster): return monster.speed(),
	},
	{
		"key": "bst",
		"label": "STAT_BST",
		"value": func(monster:Monster): return monster._best_points,
	}
]

func clear():
	var children = get_children()
	for child in children:
		if child and child.visible:
			remove_child(child)
			child.queue_free()

## hidden: Keys der Werte, die als "?" angezeigt werden (noch nicht aufgedeckte Werte von Gegnern)
func init_with_mon(monster, hidden: Array = []) -> void:
	if (is_leveling):
		columns = 3
		plabels = []
	clear()
	if stacked:
		_init_stacked(monster, hidden)
		return
	if horizontal:
		_init_horizontal(monster, hidden)
		return
	for i in range(map.size()):
		var obj = map[i]
		var tlabel = label.duplicate()
		tlabel.text = tr(obj.label)
		tlabel.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
		var vlabel = label.duplicate()
		vlabel.text = _value_text(obj, monster, hidden)
		vlabel.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)

		tlabel.visible = true
		vlabel.visible = true
		add_child(name_cell(self, obj.key, tlabel, false))
		add_child(_with_trophy_bonus(vlabel, obj.key, monster, hidden))

		if is_leveling:
			var plabel = label.duplicate()
			plabel.visible = true
			plabel.text = ""
			plabel.add_theme_color_override("font_color", GAIN_COLOR)
			plabels.append(plabel)
			add_child(plabel)

func _value_text(obj: Dictionary, monster, hidden: Array) -> String:
	return "?" if hidden.has(obj.key) else str(int(obj.value.call(monster)))

func _init_stacked(monster, hidden: Array) -> void:
	columns = map.size()
	_value_labels = {}
	# das Grid füllt zeilenweise: erst alle Namen, dann alle Zahlen
	for obj in map:
		var name_label = _horizontal_label(tr(obj.label).trim_suffix(":"), SkillDetailPopup.GOLD)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(name_cell(self, obj.key, name_label, true))
	for obj in map:
		var value_label = _horizontal_label(_value_text(obj, monster, hidden), IronPlate.TEXT_COLOR)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_with_trophy_bonus(value_label, obj.key, monster, hidden))
		_value_labels[obj.key] = value_label
	if show_trophies:
		for obj in map:
			add_child(_trophy_cell(obj.key, monster, hidden))

## Zeigt, wie ein Edelstein den Wert verändern würde (stat "" = nur der aktuelle Stand)
func show_gem_preview(monster: Monster, stat := "", bonus := 0) -> void:
	for obj in map:
		var value_label: Label = _value_labels[obj.key]
		var current := _value_text(obj, monster, [])
		var boosted: bool = obj.key == stat
		value_label.text = "%s > %d" % [current, int(current) + bonus] if boosted else current
		value_label.add_theme_color_override("font_color", SkillDetailPopup.GOLD if boosted else IronPlate.TEXT_COLOR)

func _init_horizontal(monster, hidden: Array = []) -> void:
	columns = map.size() * 2
	for obj in map:
		var tlabel = _horizontal_label(tr(obj.label).trim_suffix(":"), SkillDetailPopup.GOLD)
		tlabel.size_flags_horizontal = Control.SIZE_FILL
		add_child(name_cell(self, obj.key, tlabel, false))
		add_child(_with_trophy_bonus(_horizontal_label(_value_text(obj, monster, hidden), IronPlate.TEXT_COLOR), obj.key, monster, hidden))

func _horizontal_label(text: String, color: Color) -> Label:
	var new_label = label.duplicate()
	new_label.text = text
	new_label.add_theme_color_override("font_color", color)
	new_label.visible = true
	return new_label

func show_p_labels(texts: Array[String] = ["+1","+1","+1","+1","+1","+1","+1"]) -> void:
	for plabel in plabels:
		var index = plabels.find(plabel)
		plabel.text = texts[index]
		plabel.visible = true

func hide_p_labels() -> void:
	for plabel in plabels:
		plabel.text = ""

## Beschriftung mit Symbol: icon_above = Symbol darüber (stacked), sonst davor. Ein Klick erklärt alle Werte.
static func name_cell(host: Node, key: String, name_label: Label, icon_above: bool) -> Control:
	var cell: BoxContainer = VBoxContainer.new() if icon_above else HBoxContainer.new()
	cell.add_theme_constant_override("separation", 1 if icon_above else 4)
	cell.size_flags_horizontal = name_label.size_flags_horizontal
	var font_size := name_label.get_theme_font_size("font_size")
	if font_size <= 0:
		font_size = DEFAULT_FONT_SIZE
	cell.add_child(stat_icon(key, roundf(font_size * ICON_SCALE)))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if icon_above else Control.SIZE_FILL
	cell.add_child(name_label)
	make_clickable(cell, host, key)
	return cell

## Symbol eines Werts (weiße Linien, leicht durchsichtig)
static func stat_icon(key: String, icon_size: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = ICONS.get(key)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2.ONE * icon_size
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.modulate.a = ICON_ALPHA
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

## Klick auf control öffnet die Erklärung der Werte (StatInfoDialog) mit key hervorgehoben
static func make_clickable(control: Control, host: Node, key: String) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.tooltip_text = TranslationServer.translate("STAT_INFO_HINT")
	control.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			control.accept_event()
			StatInfoDialog.open(host, key))

# ─────────────────────────
# Trophäen

## Punkte, die Trophäen zu diesem Wert beitragen (0 = keine oder verdeckt). Bei Gegnern erst, wenn der Wert aufgedeckt ist.
static func trophy_bonus(monster, key: String, hidden: Array = []) -> int:
	if not monster is Monster or hidden.has(key) or not ICONS.has(key) or key == "bst":
		return 0
	return monster.gem_bonus(key)

## Mit show_trophies: Zahl mit grünem "(N)" dahinter, wenn Trophäen auf dem Wert liegen (N ist schon in der Zahl enthalten)
func _with_trophy_bonus(value_label: Label, key: String, monster, hidden: Array) -> Control:
	var bonus := trophy_bonus(monster, key, hidden)
	if not show_trophies or bonus <= 0:
		return value_label
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 3)
	cell.alignment = BoxContainer.ALIGNMENT_CENTER if stacked else BoxContainer.ALIGNMENT_BEGIN
	cell.size_flags_horizontal = value_label.size_flags_horizontal
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cell.add_child(value_label)
	var bonus_label := value_label.duplicate() as Label
	bonus_label.text = "(%d)" % bonus
	bonus_label.add_theme_color_override("font_color", GAIN_COLOR)
	var font_size := value_label.get_theme_font_size("font_size")
	bonus_label.add_theme_font_size_override("font_size", roundi((font_size if font_size > 0 else DEFAULT_FONT_SIZE) * TROPHY_BONUS_FONT_SCALE))
	bonus_label.tooltip_text = tr("STAT_TROPHY_BONUS_HINT").format({"bonus": bonus})
	bonus_label.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.add_child(bonus_label)
	return cell

## Unter der Zahl: Trophäen dieses Werts als Bild mit Anzahl, leer ohne Trophäen (bzw. solange der Wert verdeckt ist)
func _trophy_cell(key: String, monster, hidden: Array) -> Control:
	var cell := HBoxContainer.new()
	cell.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_theme_constant_override("separation", 2)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if trophy_bonus(monster, key, hidden) <= 0:
		return cell
	var count: int = monster.gem_count(key)
	var font_size := label.get_theme_font_size("font_size")
	if font_size <= 0:
		font_size = DEFAULT_FONT_SIZE
	var gem_field = load(GEM_FIELD_PATH)
	var icon: Control = gem_field.gem_icon(key)
	icon.custom_minimum_size = Vector2.ONE * roundf(font_size * TROPHY_ICON_SCALE)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)
	var count_label := _horizontal_label("%dx" % count, GAIN_COLOR)
	count_label.add_theme_font_size_override("font_size", roundi(font_size * TROPHY_BONUS_FONT_SCALE))
	count_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cell.add_child(count_label)
	cell.tooltip_text = TranslationServer.translate(gem_field.STATS[key].name)
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	return cell
