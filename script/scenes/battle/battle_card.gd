extends PanelContainer

## Skill-Karte auf der Hand: horizontal wischen scrollt die Hand,
## nach oben ziehen startet Drag & Drop auf ein Monster.

const DRAG_THRESHOLD := 12.0
## so weit nach oben gezogen wird aus einem Wischen doch noch Drag & Drop,
## damit ein seitliches Zucken am Anfang den Drag nicht verhindert
const SWIPE_TO_DRAG := 40.0
## Effekt um die Kosten-Raute: angetippt stärker, als Drag-Vorschau noch stärker
const PRESSED_INTENSITY := 1.6
const DRAG_INTENSITY := 1.9
## Drag-Vorschau: Raute etwas größer als auf der Karte, kurz über dem Finger, damit sie sichtbar bleibt
const DRAG_TOKEN_SCALE := 1.4
const DRAG_TOKEN_OFFSET := Vector2(0, -24)
## so lange fliegt die Raute von der Karte zum Finger
const TOKEN_FLY_TIME := 0.22
@export var name_label: Label
## Beschreibung mit gelb hervorgehobenen Werten (Helper.skill_description rich)
@export var description_label: RichTextLabel
## passt die Beschreibung nicht auf die Karte, scrollt sie von selbst runter und wieder hoch
@export var description_scroll: AutoScrollContainer

## Monster, dem die Karte gehört (show_state)
var mon: Monster

var skill: Dictionary:
	set(val):
		skill = val
		if is_node_ready():
			_init_card()

## CardHand, an die horizontale Wischbewegungen weitergegeben werden
var hand: ScrollContainer

var playable := true:
	set(val):
		playable = val
		modulate = Color(1, 1, 1) if playable else Color(0.5, 0.5, 0.5)

var _press_pos := Vector2.ZERO
var _pressed := false
var _swiping := false
## läuft gerade ein Drag & Drop dieser Karte
var _dragging := false
var _paper: SkillCardPaper
## oben die Kosten schräg auf der Ecke, unten Wert und Art-Symbol, Sterne (Stufe), Abklingzeit und Element (SkillCardFace)
var _top_row := SkillCardFace.TopRow.new()
var _bottom_row := SkillCardFace.BottomRow.new()

func _ready() -> void:
	var lines := name_label.get_parent()
	lines.add_child(_top_row)
	lines.move_child(_top_row, 0)
	_top_row.set_title(name_label)
	lines.add_child(_bottom_row)
	# RichTextLabel nutzt sonst nicht die Label-Schrift aus dem Theme
	description_label.add_theme_font_override("normal_font", name_label.get_theme_font("font"))
	SkillCardFace.style_text(description_label)
	# auf der ganzen Karte gedrückt halten hält den Text an
	description_scroll.hold_area = self
	_init_card()

func _init_card() -> void:
	if skill.is_empty():
		return
	if _paper == null:
		_paper = SkillCardPaper.attach(self, skill)
	else:
		_paper.set_skill(skill)
	name_label.text = tr(skill.name)
	SkillCardFace.style_title(name_label)
	name_label.self_modulate = SkillCardPaper.readable_color(Helper.color_by_type(skill.nature))
	# Kosten, wie das Monster sie zahlt (Bollwerkmeister verbilligt teure Schilde)
	_top_row.show_skill(skill, true, Skills.skill_cost(mon, skill) if mon != null else -1)
	_bottom_row.show_skill(skill, mon)
	# schlummert der Skill bei seinem Monster: abgeschwächte Werte, Element-Effekt durchgestrichen
	_set_description(Helper.skill_description(skill, true, mon), Color.WHITE)

## Neuer Text beginnt wieder oben, gleicher Text (z. B. erneutes show_state) scrollt einfach weiter
func _set_description(text: String, color: Color) -> void:
	description_label.self_modulate = color
	if description_label.text == text:
		return
	description_label.text = text
	description_scroll.restart()

## Fehlen dem Monster Elemente für diesen Skill, liegt der Hinweis unten über Wert und Abklingzeit,
## die Beschreibung bleibt stehen. Läuft sonst die Abklingzeit noch, steht das statt der Beschreibung auf der Karte
## und das Wertfeld zeigt die restlichen Züge.
func show_state(owner_mon: Monster) -> void:
	mon = owner_mon
	_init_card()
	var missing := Skills.missing_elements_text(mon, skill)
	if not missing.is_empty():
		_bottom_row.show_missing(missing)
		return
	if not Skills.is_ready(skill):
		_set_description(cooldown_text(Skills.cooldown_left(skill)), SkillCardFace.COOLDOWN_COLOR)
		_bottom_row.show_cooldown(Skills.cooldown_left(skill))

## Abklingzeit in eigenen Zügen (Skills.cooldown_left zählt den laufenden Zug mit):
## Direkt nach dem Einsatz eines Skills mit Abklingzeit 1 steht 2 da, also "nächsten Zug gesperrt, danach bereit".
func cooldown_text(turns: int) -> String:
	match turns:
		1: return tr("BATTLE_CARD_COOLDOWN_NEXT")
		2: return tr("BATTLE_CARD_COOLDOWN_AFTER_NEXT")
	return tr("BATTLE_CARD_COOLDOWN").format({"turns": turns})

## Ausgewählte Karte leuchtet am Rahmen (erst möglich, wenn die Karte im Baum ist)
func set_selected(selected: bool) -> void:
	_paper.set_glow(SkillCardPaper.SELECTED_GLOW if selected else 0.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_swiping = false
			_press_pos = event.global_position
			hand.stop_fling()
			# angetippt: der Effekt um die Kosten-Raute lodert stärker
			if _can_drag():
				_top_row.set_intensity(PRESSED_INTENSITY)
		else:
			if _swiping:
				hand.end_swipe()
			_pressed = false
			_swiping = false
			if not _dragging:
				_top_row.set_intensity(1.0)
		accept_event()
	elif event is InputEventMouseMotion and _pressed:
		var delta: Vector2 = event.global_position - _press_pos
		if _swiping:
			if -delta.y > SWIPE_TO_DRAG and _can_drag():
				_pressed = false
				_swiping = false
				hand.stop_fling()
				_start_drag()
			else:
				hand.swipe_by(-event.relative.x)
		elif delta.length() > DRAG_THRESHOLD:
			# nur eindeutig seitliche Bewegungen scrollen, schräg nach oben ist ein Drag.
			# Lässt sich die Karte gerade nicht spielen, scrollt jede Bewegung die Hand.
			if absf(delta.x) > absf(delta.y) * 1.5 or not _can_drag():
				_swiping = true
				_top_row.set_intensity(1.0)
				hand.swipe_by(-delta.x)
			else:
				_pressed = false
				_start_drag()
		accept_event()
	elif event is InputEventScreenDrag or event is InputEventScreenTouch:
		# Touch wird als Maus emuliert, sonst würde der ScrollContainer doppelt scrollen
		accept_event()

## spielbar und die Hand ist nicht gesperrt (Gegner am Zug)
func _can_drag() -> bool:
	return playable and (hand == null or hand.can_play.call())

## Statt der ganzen Karte (die alles verdecken würde) hängt nur die Kosten-Raute mit ihrem Effekt am Finger.
## Sie fliegt von ihrem Platz auf der Karte zum Finger.
func _start_drag() -> void:
	if not _can_drag():
		_top_row.set_intensity(1.0)
		return
	var token := _top_row.make_token(DRAG_INTENSITY)
	token.scale = Vector2.ONE * DRAG_TOKEN_SCALE
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(token)
	# die Vorschau folgt dem Finger, die Raute startet aber dort, wo sie auf der Karte sitzt
	token.position = _top_row.badge_center() - get_global_mouse_position()
	force_drag({"type": "skill_card", "skill": skill, "mon": mon}, holder)
	_dragging = true
	modulate.a = 0.3
	# die Vorschau ist hier evtl. noch nicht im Baum: Tween am SceneTree, an die Raute gebunden
	var tween := get_tree().create_tween().bind_node(token)
	tween.set_ignore_time_scale(true)
	tween.tween_property(token, "position", DRAG_TOKEN_OFFSET, TOKEN_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		modulate.a = 1.0
		if _dragging:
			_dragging = false
			_top_row.set_intensity(1.0)
