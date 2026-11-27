class_name ElementLoanPreview
extends Control

## Vorschau beim Ziehen einer Element-Kugel (ElementLoan.preview_element): über der ganzen oberen Bildschirmhälfte
## (verdeckt dabei kurz Zugrad und Gegner) stehen alle Fähigkeiten des Monsters am Zug als Karten, so wie sie mit
## dem neuen Element aussähen (Wert, Beschreibung, Effekt). Über jeder steht, zu welchem Element sie wird, oder dass
## sie sich nicht verändert (zweizeilig, damit auch "Wasser >> Aschesturm" passt). Unter dem Titel steht, was die
## neuen Elemente bewirken. Die Karten sind immer so breit wie bei sechs Fähigkeiten, auch wenn es weniger sind.
## So lässt sich vor dem Loslassen in Ruhe entscheiden. Nimmt keine Maus an: das Ablegen auf dem Monster geht durch.

const BACKGROUND := Color(0.03, 0.035, 0.04, 0.93)
const TITLE_SIZE := 30
const NAME_SIZE := 22
const EFFECT_SIZE := 20
const UNCHANGED_ALPHA := 0.45
const FADE_TIME := 0.12
const ARROW := " >> "
## Abstand zwischen den Karten
const CARD_GAP := 26
## Platz für so viele Karten, auch wenn das Monster weniger hat (alle Karten gleich groß)
const SLOTS := Skills.MAX_SKILLS
## Mindesthöhe der Karten, sie füllen den Rest der oberen Bildschirmhälfte
const CARD_MIN_HEIGHT := 150.0

var _shown_element := 0
var _content: VBoxContainer

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_TOP_WIDE)
	anchor_bottom = 0.5
	offset_left = 0
	offset_right = 0
	offset_top = 0
	offset_bottom = 0
	visible = false
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_content = VBoxContainer.new()
	_content.mouse_filter = MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override("separation", 10)
	margin.add_child(_content)
	# untere Kante: goldene Linie trennt die Vorschau vom Kampffeld
	var rim := ColorRect.new()
	rim.color = SkillCardPaper.GOLD
	rim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(rim)
	rim.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	rim.offset_top = -2
	Events.element_loans_changed.connect(_refresh)

func _refresh() -> void:
	var element := ElementLoan.preview_element
	var mon := ElementLoan.active
	# Tutorial (Feld 2, Leih-Schritt): die Vorschau bleibt weg
	if element == 0 or mon == null or Tutorial.hides("bat_loan_preview"):
		_shown_element = 0
		if visible:
			var tween := create_tween()
			tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
			tween.tween_callback(hide)
		return
	if element == _shown_element and visible:
		return
	_shown_element = element
	_build(mon, element)
	move_to_front()
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, FADE_TIME)

func _build(mon: Monster, element: int) -> void:
	for child in _content.get_children():
		child.queue_free()
	var combo := ColorMap.get_combo(element)
	var title := _label(tr("LOAN_PREVIEW_TITLE").format({
		"element": tr(combo.label), "mon": Helper.mon_battle_name(mon)}), TITLE_SIZE, Color(Helper.color_by_type(element)))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(title)
	var effects := _effect_text(mon)
	if effects != "":
		var subtitle := RichTextLabel.new()
		subtitle.bbcode_enabled = true
		subtitle.fit_content = true
		subtitle.scroll_active = false
		subtitle.mouse_filter = MOUSE_FILTER_IGNORE
		subtitle.theme = EggSkillCard.THEME
		subtitle.add_theme_font_size_override("normal_font_size", EFFECT_SIZE)
		subtitle.add_theme_color_override("default_color", IronPlate.TEXT_COLOR)
		subtitle.add_theme_constant_override("outline_size", 4)
		subtitle.add_theme_color_override("font_outline_color", Color.BLACK)
		subtitle.text = "[center]%s[/center]" % effects
		_content.add_child(subtitle)
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", CARD_GAP)
	_content.add_child(row)
	# leere Plätze links und rechts gleich verteilt: die Karten bleiben so breit wie bei SLOTS Fähigkeiten
	var spare := maxi(SLOTS - mon._skills.size(), 0) / 2.0
	if spare > 0:
		row.add_child(_spacer(spare))
	for skill in mon._skills:
		row.add_child(_column(mon, skill))
	if spare > 0:
		row.add_child(_spacer(spare))

## Platzhalter so breit wie slots Karten (samt Abstand, den die Reihe selbst noch einmal setzt)
func _spacer(slots: float) -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = slots
	return spacer

## Was die neuen Elemente bewirken, eine Zeile pro Element (z. B. Staub und Magma, wenn Luft- und Feuer-Skills
## Erde bekommen). Geliehen lösen die Effekte sicher aus. "" wenn keine Fähigkeit einen Effekt bekommt.
func _effect_text(mon: Monster) -> String:
	var lines: Array[String] = []
	var seen := {}
	for skill in mon._skills:
		var face := ElementLoan.display_skill(mon, skill)
		if face.is_empty() or seen.has(face.nature):
			continue
		seen[face.nature] = true
		var power := 1.0 / ElementEffects.VOLCANO_CHANCE if face.nature == ElementEffects.VOLCANO else 1.0
		var text := ElementEffects.element_effect_text(face.nature, power, INF)
		if text != "":
			lines.append(Helper.highlight(text, true))
	return "\n".join(lines)

## Eine Fähigkeit als richtige Karte, so wie sie mit dem neuen Element aussähe (Wert, Beschreibung samt
## Element-Effekt), damit man sieht, wie stark sie ist. Darüber: altes Element, Pfeil, neues Element.
## Unveränderte Karten stehen abgedunkelt mit Hinweis darüber.
func _column(mon: Monster, skill: Dictionary) -> Control:
	var face := ElementLoan.display_skill(mon, skill)
	var changed := not face.is_empty()
	var box := VBoxContainer.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.x = 1
	box.add_theme_constant_override("separation", 6)
	var head := VBoxContainer.new()
	head.mouse_filter = MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 0)
	box.add_child(head)
	# zweizeilig: oben das alte Element, darunter Pfeil und neues Element, so passen auch lange Namen
	var old_color := SkillCardPaper.readable_color(Helper.color_by_type(skill.nature))
	var old_line := _centered_line(head)
	var new_line := _centered_line(head)
	if changed:
		old_line.add_child(_label(tr(ColorMap.get_combo(skill.nature).label), NAME_SIZE, old_color))
		new_line.add_child(_label(ARROW.strip_edges() + " ", NAME_SIZE, SkillCardPaper.GOLD))
		new_line.add_child(_label(tr(ColorMap.get_combo(face.nature).label), NAME_SIZE,
			SkillCardPaper.readable_color(Helper.color_by_type(face.nature))))
	else:
		# gleiche Höhe wie die geänderten Spalten, damit die Karten auf einer Linie stehen
		var unchanged := _label(tr("LOAN_PREVIEW_UNCHANGED"), NAME_SIZE, IronPlate.TEXT_COLOR)
		unchanged.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		unchanged.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unchanged.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		old_line.add_child(unchanged)
		new_line.add_child(_label(" ", NAME_SIZE, IronPlate.TEXT_COLOR))
	var card := EggSkillCard.create(face if changed else skill, mon)
	# kleiner als sonst (EggSkillCard.HEIGHT): Titel, Effekt-Zeile und zweizeiliger Kopf brauchen Platz,
	# die Beschreibung scrollt von selbst
	card.custom_minimum_size = Vector2(1, CARD_MIN_HEIGHT)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(card)
	if not changed:
		card.modulate.a = UNCHANGED_ALPHA
	# die Vorschau nimmt keine Maus an, auch nicht die Karten darin: das Ablegen auf dem Monster geht durch
	_ignore_mouse(card)
	return box

func _centered_line(parent: Control) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.mouse_filter = MOUSE_FILTER_IGNORE
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 0)
	parent.add_child(line)
	return line

static func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.theme = EggSkillCard.THEME
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	return label
