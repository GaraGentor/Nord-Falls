class_name EggSkillCard
extends PanelContainer

## Große Karte einer Ei-Attacke für die Ei-Auswahl, aufgebaut wie die Spielkarte im Kampf.
## Kosten schräg auf der Ecke, der Name und unten Wert mit Art-Symbol, Sterne, Abklingzeit und Element stehen fest (SkillCardFace). Nur die Beschreibung darunter scrollt:
## von selbst, wenn sie nicht passt, und per Mausrad / Leiste auch von Hand. Nach eigenem Scrollen
## setzt das automatische Scrollen erst nach einer Weile Ruhe wieder ein.
## Gesperrte Attacken liegen unter zwei gekreuzten Ketten, mittig steht, wie man sie freischaltet.

const HEIGHT := 210.0
const THEME := preload("res://script/ui/materials/battle_labels.tres")
const TEXT_COLOR := IronPlate.TEXT_COLOR
const MISSING_COLOR := Color(1, 0.45, 0.45)
const LOCKED_TINT := Color(0.5, 0.5, 0.5)
const GOLD := SkillCardPaper.GOLD

var _scroll: AutoScrollContainer
var _paper: SkillCardPaper
var _bottom_row: SkillCardFace.BottomRow
var _name_label: Label
## Gesperrte Karte: Inhalt (abgedunkelt) und Ketten mit Hinweis, set_revealed blendet die Ketten weg
var _margin: MarginContainer
var _lock: ChainOverlay
## Plakette mit dem Freischalt-Hinweis (fährt beim Aufdecken nach oben raus)
var _lock_text: Control
var _reveal_tween: Tween

## Aufdecken: Hinweis raus, dann die Ketten, die zweite etwas versetzt
const REVEAL_TEXT_TIME := 0.22
const REVEAL_CHAIN_TIME := 0.38
const REVEAL_CHAIN_STAGGER := 0.07

## locked_label/locked_hint: gesperrte Attacke, Texte mittig auf den Ketten (leer = nicht gesperrt)
static func create(skill: Dictionary, mon: Monster, locked_label := "", locked_hint := "") -> EggSkillCard:
	var card := EggSkillCard.new()
	card._build(skill, mon, locked_label, locked_hint)
	return card

func _build(skill: Dictionary, mon: Monster, locked_label: String, locked_hint: String) -> void:
	var locked := locked_label != ""
	theme = THEME
	custom_minimum_size = Vector2(0, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_paper = SkillCardPaper.attach(self, skill, locked)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 11)
	margin.add_theme_constant_override("margin_bottom", 11)
	if locked:
		margin.modulate = LOCKED_TINT
	add_child(margin)
	_margin = margin
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 4)
	margin.add_child(lines)

	# oben: Kosten schräg auf der Ecke, der Name daneben
	var top_row := SkillCardFace.TopRow.new()
	lines.add_child(top_row)
	top_row.show_skill(skill)

	var name_label := _label(tr(skill.name), 24, SkillCardPaper.readable_color(Helper.color_by_type(skill.nature)))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top_row.set_title(name_label)
	lines.add_child(name_label)
	# höchstens zwei Zeilen, lange Namen werden kleiner
	SkillCardFace.fit_title(name_label, 18)
	_name_label = name_label

	# Mitte: nur die Beschreibung scrollt
	_scroll = AutoScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# auf der ganzen Karte gedrückt halten hält den Text an
	_scroll.hold_area = self
	# PASS: Klick und Ziehen gehen weiter an die Karte (Drag & Drop), das Mausrad scrollt den Text
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	lines.add_child(_scroll)
	# wichtige Stellen gelb (Helper.highlight), daher RichTextLabel mit der Schrift der übrigen Labels
	var description := RichTextLabel.new()
	description.bbcode_enabled = true
	description.fit_content = true
	description.scroll_active = false
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.add_theme_font_override("normal_font", THEME.get_font("font", "Label"))
	description.add_theme_font_size_override("normal_font_size", 24)
	description.add_theme_color_override("default_color", TEXT_COLOR)
	# schlummernd: abgeschwächte Werte, Element-Effekt durchgestrichen, darunter was die Attacke weckt
	description.text = Helper.skill_description(skill, true, null if locked else mon)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 1
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(description)

	if not locked and not Skills.can_use(mon, skill):
		# wählbar, aber erst spielbar, wenn das Monster die fehlenden Elemente bekommt (z. B. im Shop)
		var missing := _label(Skills.missing_elements_text(mon, skill), 16, MISSING_COLOR)
		missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		missing.custom_minimum_size.x = 1
		lines.add_child(missing)

	# unten: Wert und Art-Symbol (fett, etwas größer als der Name), Sterne (Stufe), Abklingzeit und Element
	var bottom_row := SkillCardFace.BottomRow.new()
	lines.add_child(bottom_row)
	bottom_row.set_value_size(18)
	bottom_row.show_skill(skill, mon)
	_bottom_row = bottom_row

	if locked:
		_scroll.set_process(false)
		_lock = _build_lock(locked_label, locked_hint)
		add_child(_lock)

func is_locked() -> bool:
	return _lock != null

## Gesperrte Karte aufdecken (Ketten und Hinweis weg, Karte in voller Farbe) oder wieder verschließen.
## Die Sammlung deckt so eine angeklickte Ei-Attacke auf, bis man woanders hinklickt.
func set_revealed(revealed: bool) -> void:
	if _lock == null:
		return
	if _reveal_tween != null:
		_reveal_tween.kill()
	_scroll.set_process(revealed)
	set_selected(revealed)
	var tween := create_tween().set_parallel()
	_reveal_tween = tween
	var out_y := -size.y
	if revealed:
		# erst fährt der Hinweis nach oben raus, dann ziehen sich die Ketten nacheinander nach oben weg
		tween.tween_property(_lock_text, "position:y", out_y, REVEAL_TEXT_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(_lock_text, "modulate:a", 0.0, REVEAL_TEXT_TIME).set_delay(REVEAL_TEXT_TIME * 0.5)
		tween.tween_property(_lock, "retract_right", 1.0, REVEAL_CHAIN_TIME).set_delay(REVEAL_TEXT_TIME * 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(_lock, "retract_left", 1.0, REVEAL_CHAIN_TIME).set_delay(REVEAL_TEXT_TIME * 0.6 + REVEAL_CHAIN_STAGGER) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(_margin, "modulate", Color.WHITE, REVEAL_CHAIN_TIME).set_delay(REVEAL_TEXT_TIME)
		tween.tween_method(_paper.set_muted, 1.0, 0.0, REVEAL_CHAIN_TIME).set_delay(REVEAL_TEXT_TIME)
	else:
		# umgekehrt: die Ketten rasseln zurück (federn nach), danach fällt der Hinweis wieder von oben herein
		tween.tween_property(_lock, "retract_left", 0.0, REVEAL_CHAIN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(_lock, "retract_right", 0.0, REVEAL_CHAIN_TIME).set_delay(REVEAL_CHAIN_STAGGER) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(_margin, "modulate", LOCKED_TINT, REVEAL_CHAIN_TIME)
		tween.tween_method(_paper.set_muted, 0.0, 1.0, REVEAL_CHAIN_TIME)
		var text_delay := REVEAL_CHAIN_TIME * 0.6
		tween.tween_property(_lock_text, "position:y", 0.0, REVEAL_TEXT_TIME * 1.4).from(out_y).set_delay(text_delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(_lock_text, "modulate:a", 1.0, REVEAL_TEXT_TIME).set_delay(text_delay)

## Zwei gekreuzte Ketten über der Karte, mittig eine Plakette mit dem Freischalt-Hinweis
func _build_lock(locked_label: String, locked_hint: String) -> ChainOverlay:
	var chains := ChainOverlay.new()
	chains.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := MarginContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		center.add_theme_constant_override("margin_" + side, 14)
	chains.add_child(center)
	_lock_text = center
	var plate := PanelContainer.new()
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.92)
	style.border_color = ChainOverlay.METAL
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	plate.add_theme_stylebox_override("panel", style)
	center.add_child(plate)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_theme_constant_override("separation", 4)
	plate.add_child(texts)
	var title := _label(tr(locked_label), 24, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 1
	texts.add_child(title)
	var hint := _label(tr(locked_hint), 16, TEXT_COLOR)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 1
	texts.add_child(hint)
	return chains

## Kleinerer Name für schmale Karten (z. B. Ei-Auswahl), lange Namen werden weiterhin noch kleiner
func set_title_size(font_size: int) -> void:
	SkillCardFace.fit_title(_name_label, font_size)
	_bottom_row.set_value_size(font_size)

## Angeklickte Karte leuchtet am Rahmen
func set_selected(selected: bool) -> void:
	_paper.set_glow(SkillCardPaper.SELECTED_GLOW if selected else 0.0)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

## Ketten von oben rechts nach unten links und von oben links nach unten rechts.
## Glieder wechseln sich ab: flach liegend (Ring) und hochkant (Strich).
class ChainOverlay extends Control:
	const METAL := Color(0.62, 0.6, 0.57)
	const SHINE := Color(0.88, 0.86, 0.82)
	const SHADOW := Color(0.05, 0.04, 0.04, 0.9)
	const LINK_LENGTH := 26.0
	const LINK_STEP := 19.0
	const SEGMENTS := 16

	## 0 = Kette liegt über der Karte, 1 = ganz nach oben rechts bzw. oben links aus der Karte gezogen
	var retract_right := 0.0:
		set(value):
			retract_right = value
			queue_redraw()
	var retract_left := 0.0:
		set(value):
			retract_left = value
			queue_redraw()

	func _ready() -> void:
		clip_contents = true
		resized.connect(queue_redraw)

	func _draw() -> void:
		_draw_retracted(Vector2(size.x, 0), Vector2(0, size.y), retract_right)
		_draw_retracted(Vector2.ZERO, size, retract_left)

	## Die Kette rutscht entlang ihrer eigenen Richtung zu ihrem oberen Ende hinaus
	func _draw_retracted(from: Vector2, to: Vector2, retract: float) -> void:
		var shift := (from - to) * retract * 1.15
		_draw_chain(from + shift, to + shift)

	func _draw_chain(from: Vector2, to: Vector2) -> void:
		var length := from.distance_to(to)
		if length < 1.0:
			return
		var dir := (to - from) / length
		var perp := Vector2(-dir.y, dir.x)
		var count := maxi(roundi(length / LINK_STEP), 1)
		var step := length / count
		var half := LINK_LENGTH / 2.0
		# erst die flachen Ringe, darüber die hochkant stehenden Glieder, die sie verbinden
		for flat in [true, false]:
			for i in range(0, count + 1):
				if (i % 2 == 0) != flat:
					continue
				var center := from + dir * (i * step)
				if flat:
					var points := PackedVector2Array()
					for s in SEGMENTS + 1:
						var t := TAU * s / SEGMENTS
						points.append(center + dir * cos(t) * half + perp * sin(t) * half * 0.55)
					draw_polyline(points, SHADOW, 6.0, true)
					draw_polyline(points, METAL, 3.0, true)
					# Glanzlicht auf der oberen Hälfte
					draw_polyline(points.slice(SEGMENTS / 2, SEGMENTS + 1), SHINE, 1.0, true)
				else:
					var a := center - dir * half
					var b := center + dir * half
					draw_line(a, b, SHADOW, 7.0, true)
					draw_line(a, b, METAL, 4.0, true)
					draw_line(a + perp, b + perp, SHINE, 1.0, true)
