class_name SkillCarousel
extends Control

## Fähigkeiten des ausgewählten Monsters im Infobereich des Kampfs (battle_info_panel.gd) als Karten nebeneinander,
## ohne Rahmen direkt auf dem Hintergrund. Die Karte in der Mitte ist am größten und gut lesbar, alle anderen sind eine
## Stufe kleiner (nicht weiter, sonst wären sie unlesbar). Es passen nicht alle hinein: zu Beginn steht die erste Karte
## in der Mitte, links davon ist Platz für die Silhouette des Monsters (battle_info_panel.gd).
##   Wischen / Ziehen oder Mausrad: die nächste Karte rückt in die Mitte (rastet danach ein)
##   Seitenkarte antippen: sie rückt in die Mitte. Mittlere Karte antippen: card_pressed (Details-Popup)
## Unbekannte Fähigkeiten der Gegner liegen verdeckt da und verraten nur Element (Farbe) und Stufe.

signal card_pressed(skill: Dictionary)

## Karten werden in dieser Größe gebaut und dann skaliert (passt zu EggSkillCard)
const CARD_SIZE := Vector2(172, 240)
## Größe der Karten je Abstand zur Mitte: Mitte 1, alle anderen MIN_SCALE (nur eine Stufe, dazwischen beim Wischen)
const FALLOFF := 0.22
const MIN_SCALE := 1.0 - FALLOFF
const GAP := 8.0
## Platz oben und unten: Kosten-Raute und Ei ragen über den Kartenrand hinaus
const PAD_Y := 20.0
## so viele Pixel Wischen schieben die Karten um eine Stelle weiter
const DRAG_PER_CARD := 90.0
const DRAG_THRESHOLD := 8.0
const SNAP_TIME := 0.22
const EGG_TEXTURE := preload("res://assets/ui/eggs/common_1.png")
const UNKNOWN_COLOR := Color(0.858824, 0.717647, 0.45098)

var _cards: Array[Control] = []
var _skills: Array = []
## Stelle, die gerade in der Mitte steht (Kommazahl beim Wischen und Einrasten)
var focus := 0.0:
	set(value):
		focus = value
		_layout()
var _mon: Monster
var _snap: Tween
var _pressing := false
var _dragging := false
var _press_x := 0.0
var _press_focus := 0.0

func _init() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_STOP

func _ready() -> void:
	resized.connect(_layout)

## Karten für die Skills von mon. known(skill) -> bool: offen oder verdeckt. Bleibt das Monster dasselbe
## (z. B. ein Skill wurde gerade aufgedeckt), bleibt die Karte in der Mitte stehen.
func show_skills(mon: Monster, skills: Array, known: Callable) -> void:
	var same_mon := mon == _mon and skills.size() == _skills.size()
	_mon = mon
	_skills = skills.duplicate()
	for card in _cards:
		remove_child(card)
		card.queue_free()
	_cards = []
	for skill in skills:
		var card := _known_card(skill, mon) if known.call(skill) else _unknown_card(skill)
		if Skills.is_unlockable_egg_skill(mon, skill):
			_add_egg_mark(card)
		SkillCardFace.ignore_mouse(card)
		card.size = CARD_SIZE
		add_child(card)
		_cards.append(card)
	if _snap:
		_snap.kill()
	# neues Monster: die erste Fähigkeit steht in der Mitte
	focus = clampf(roundf(focus), 0, maxf(skills.size() - 1, 0)) if same_mon else 0.0

func _known_card(skill: Dictionary, mon: Monster) -> Control:
	var card := EggSkillCard.create(skill, mon)
	card.custom_minimum_size = Vector2.ZERO
	return card

## Verdeckt: Papier in der Elementfarbe, mittig ein großes Fragezeichen und die Stufe
func _unknown_card(skill: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme = EggSkillCard.THEME
	SkillCardPaper.attach(card, skill, false, false)
	var lines := VBoxContainer.new()
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(lines)
	var mark := SkillCardFace.label(96, SkillCardPaper.readable_color(Helper.color_by_type(skill.nature)))
	mark.text = "?"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(mark)
	var text := SkillCardFace.label(22, UNKNOWN_COLOR)
	text.text = tr("BATTLE_UNKNOWN_SKILL").format({"tier": skill.get("tier", 1)})
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = CARD_SIZE.x - 24
	lines.add_child(text)
	card.tooltip_text = tr("BATTLE_UNKNOWN_SKILL_HINT")
	return card

## Ei-Attacken, die durch Fangen und Opfern freigeschaltet werden können: Ei schräg oben rechts hinter der Karte
## (wie im Judgement, judgement.gd _add_egg)
func _add_egg_mark(card: Control) -> void:
	# die Karte ist ein Container und würde das Ei auf ihre Größe ziehen: daher ein Halter über die ganze Karte
	var holder := Control.new()
	holder.show_behind_parent = true
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(holder)
	var egg := TextureRect.new()
	egg.texture = EGG_TEXTURE
	egg.material = Monmap.egg_material(Monmap.rarity_of(_mon._name))
	egg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	egg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	egg.mouse_filter = MOUSE_FILTER_IGNORE
	egg.anchor_left = 1.0
	egg.anchor_right = 1.0
	egg.offset_left = -20
	egg.offset_right = 24
	egg.offset_top = -16
	egg.offset_bottom = 36
	egg.pivot_offset = Vector2(22, 26)
	egg.rotation_degrees = 18
	holder.add_child(egg)

## Größe und Platz jeder Karte aus ihrem Abstand zur Mitte
func _layout() -> void:
	if _cards.is_empty() or size.y <= 0:
		return
	var fit := maxf(size.y - PAD_Y * 2, 1.0) / CARD_SIZE.y
	var scales: Array[float] = []
	var centers: Array[float] = []
	var x := 0.0
	for i in _cards.size():
		var s := maxf(1.0 - absf(i - focus) * FALLOFF, MIN_SCALE) * fit
		var width := CARD_SIZE.x * s
		if i > 0:
			x += CARD_SIZE.x * scales[i - 1] / 2 + GAP + width / 2
		scales.append(s)
		centers.append(x)
	# die Stelle "focus" (auch zwischen zwei Karten) liegt genau in der Mitte
	var low := clampi(floori(focus), 0, _cards.size() - 1)
	var high := clampi(low + 1, 0, _cards.size() - 1)
	var focus_x := lerpf(centers[low], centers[high], focus - low)
	var shift := size.x / 2 - focus_x
	for i in _cards.size():
		var card := _cards[i]
		var s := scales[i]
		card.scale = Vector2.ONE * s
		card.position = Vector2(centers[i] + shift - CARD_SIZE.x * s / 2, (size.y - CARD_SIZE.y * s) / 2)

	# die Mitte liegt obenauf, falls sich Karten berühren (Reihenfolge statt z_index: sonst lägen die Karten auch
	# über Fenstern, die später kommen, z. B. der Vorschau beim Leihen)
	var order := range(_cards.size())
	order.sort_custom(func(a, b): return absf(a - focus) > absf(b - focus))
	for i in order.size():
		move_child(_cards[order[i]], i)

func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button:
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT]:
			snap_to(roundf(focus) - 1)
			accept_event()
		elif button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT]:
			snap_to(roundf(focus) + 1)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if button.pressed:
				_pressing = true
				_dragging = false
				_press_x = button.position.x
				_press_focus = focus
				if _snap:
					_snap.kill()
			elif _pressing:
				_pressing = false
				if _dragging:
					snap_to(roundf(focus))
				else:
					_tap(button.position)
		return
	var motion := event as InputEventMouseMotion
	if motion and _pressing:
		var dx := motion.position.x - _press_x
		if not _dragging and absf(dx) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			focus = clampf(_press_focus - dx / DRAG_PER_CARD, -0.4, _cards.size() - 0.6)
			accept_event()

func _tap(pos: Vector2) -> void:
	var index := _card_at(pos)
	if index < 0:
		return
	if index == roundi(focus):
		card_pressed.emit(_skills[index])
	else:
		snap_to(index)

## Karte unter pos, bei Überschneidung die, die näher an der Mitte liegt
func _card_at(pos: Vector2) -> int:
	var best := -1
	for i in _cards.size():
		var card := _cards[i]
		if Rect2(card.position, CARD_SIZE * card.scale).has_point(pos):
			if best < 0 or absf(i - focus) < absf(best - focus):
				best = i
	return best

## Gleitet zur Stelle index und rastet dort ein
func snap_to(index: float) -> void:
	index = clampf(index, 0, maxf(_cards.size() - 1, 0))
	if _snap:
		_snap.kill()
	_snap = create_tween()
	_snap.tween_property(self, "focus", index, SNAP_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
