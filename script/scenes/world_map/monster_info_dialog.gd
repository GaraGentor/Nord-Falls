class_name MonsterInfoDialog
extends Control

## Details eines eigenen Monsters über der ganzen Kartenfläche (der Header der Karte bleibt sichtbar):
## oben links Name und Bild (unten links am Bild die Züge als Rune), daneben die Werte wie im Kampf (mit Trophäen)
## und darunter Element- und Seltenheits-Chip, rechts das Wachstum pro Stufe als Netzdiagramm und der Zurück-Knopf.
## Darunter alle Attacken als große Karten wie im Kampf in einer waagerechten Scrollview (reine Anzeige, ohne Klick).

const BATTLE_CARD := preload("res://script/scenes/battle/battle_card.tscn")
const ELEMENT_CHIP := preload("res://script/ui/element_chip/element_chip.tscn")
const PORTRAIT_SIZE := Vector2(160, 160)
const NAME_FONT_SIZE := 26
const CHIP_HEIGHT := 32.0
## Werte wie im Kampf: Schriftgröße und Breite der Platte im BattleInfoPanel (580 breit, je 12 Rand)
const STATS_FONT_SIZE := 15
const STATS_WIDTH := 556.0
const RADAR_MIN_SIZE := Vector2(190, 150)
## Höhe so, dass die Karten samt Rand-Effekten (SkillCardPaper.FLAME_PAD) unter dem Map-Header auf den Bildschirm passen
const SKILL_CARD_SIZE := Vector2(210, 184)
const BACK_ICON := preload("res://assets/ui/icons/icon_back.svg")

var _mon: Monster

func _init(mon: Monster) -> void:
	_mon = mon
	theme = RewardDialog.FONT_THEME
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	# Klicks gehen nicht auf die Karte darunter durch
	mouse_filter = MOUSE_FILTER_STOP

func _ready() -> void:
	offset_top = RewardDialog.MAP_HEADER_HEIGHT
	var panel := PanelContainer.new()
	RewardDialog.fit_to_map_area(panel)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	IronPlate.frame(panel, box, 24, 20)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	box.add_child(top)
	top.add_child(_portrait_side())
	top.add_child(_facts())
	top.add_child(_radar())
	var back := RewardDialog.icon_button(BACK_ICON)
	back.tooltip_text = tr("MONSTER_INFO_BACK")
	back.size_flags_vertical = SIZE_SHRINK_BEGIN
	back.pressed.connect(queue_free)
	top.add_child(back)
	box.add_child(_skill_cards())

## Name über dem Bild, unten links am Bild die Züge
func _portrait_side() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var name_label := Label.new()
	name_label.text = Helper.mon_battle_name(_mon)
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	name_label.add_theme_color_override("font_color", SkillCardPaper.readable_color(Helper.color_by_mon(_mon)))
	box.add_child(name_label)
	var portrait := RewardDialog.mon_icon(_mon)
	portrait.custom_minimum_size = PORTRAIT_SIZE
	box.add_child(MovesBadge.attach_to_portrait(portrait, _mon))
	return box

## Element und Seltenheit, darunter die Werte wie im Kampf; Trophäen stehen direkt unter ihrem Wert,
## ihr Anteil grün hinter der Zahl (wie im Trophäen-Feld)
func _facts() -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 12)
	chips.custom_minimum_size.y = CHIP_HEIGHT
	box.add_child(chips)
	var element_chip: Control = ELEMENT_CHIP.instantiate()
	element_chip.size_flags_horizontal = SIZE_SHRINK_BEGIN
	element_chip.size_flags_vertical = SIZE_FILL
	chips.add_child(element_chip)
	element_chip.set_element(_mon._type)
	var rarity := Monmap.rarity_of(_mon._name)
	var rarity_chip: Control = ELEMENT_CHIP.instantiate()
	rarity_chip.size_flags_horizontal = SIZE_SHRINK_BEGIN
	rarity_chip.size_flags_vertical = SIZE_FILL
	chips.add_child(rarity_chip)
	rarity_chip._init_with_element({"label": Monmap.RARITY_LABELS[rarity], "color": Monmap.RARITY_COLORS[rarity]})
	var stats_panel := PanelContainer.new()
	stats_panel.custom_minimum_size.x = STATS_WIDTH
	IronPlate.frame(stats_panel, StatsGrid.stacked_for(_mon, STATS_FONT_SIZE, true), 10, 8)
	box.add_child(stats_panel)
	# Werte oben, Element und Seltenheit darunter
	box.move_child(stats_panel, 0)
	return box

## Wachstum pro Stufe als Netzdiagramm (wie im Judgement) in der Farbe des Monsters
func _radar() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.mouse_filter = MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = MOUSE_FILTER_IGNORE
	IronPlate.frame(panel, box, 10, 8)
	var heading := Label.new()
	heading.text = tr("JUDGEMENT_GROWTH")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 17)
	heading.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
	box.add_child(heading)
	var radar := GrowthRadar.new()
	radar.custom_minimum_size = RADAR_MIN_SIZE
	radar.size_flags_vertical = SIZE_EXPAND_FILL
	box.add_child(radar)
	radar.show_mons([{"mon": _mon, "color": Helper.color_by_mon(_mon)}])
	return panel

## Alle Attacken als Kampfkarten nebeneinander. Die Karten nehmen keine Eingabe an,
## so landen Mausrad und Wischen direkt bei der Scrollview und ein Klick bewirkt nichts.
func _skill_cards() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Platz für die Rand-Effekte der Karten, sonst schneidet die Scrollview sie ab
	var margin := SkillCardPaper.flame_margin()
	scroll.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SkillCardPaper.FLAME_GAP_X)
	margin.add_child(row)
	for skill in _mon._skills:
		var card := BATTLE_CARD.instantiate()
		card.mon = _mon
		card.skill = skill
		card.custom_minimum_size = SKILL_CARD_SIZE
		card.size_flags_vertical = SIZE_SHRINK_BEGIN
		card.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(card)
	return scroll
