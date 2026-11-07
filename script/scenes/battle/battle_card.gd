extends PanelContainer

## Skill-Karte auf der Hand: horizontal wischen scrollt die Hand,
## nach oben ziehen startet Drag & Drop auf ein Monster.

const DRAG_THRESHOLD := 12.0
## so weit nach oben gezogen wird aus einem Wischen doch noch Drag & Drop,
## damit ein seitliches Zucken am Anfang den Drag nicht verhindert
const SWIPE_TO_DRAG := 40.0

@export var name_label: Label
@export var cost_label: Label
@export var value_label: Label
@export var type_icon: TextureRect
@export var description_label: Label

@export var physical_texture: Texture2D
@export var magic_texture: Texture2D

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
var _paper: SkillCardPaper

func _ready() -> void:
	_init_card()

func _init_card() -> void:
	if skill.is_empty():
		return
	if _paper == null:
		_paper = SkillCardPaper.attach(self, skill)
	else:
		_paper.set_skill(skill)
	name_label.text = tr(skill.name)
	name_label.self_modulate = SkillCardPaper.readable_color(Helper.color_by_type(skill.nature))
	cost_label.text = str(skill.cost)
	value_label.text = Helper.format_number(skill.get("value", skill.get("damage", "")))
	type_icon.texture = physical_texture if skill.damage_type == Enums.SKILL_DAMAGE_TYPE.PHYSICAL else magic_texture
	description_label.text = Helper.skill_description(skill)
	description_label.self_modulate = Color.WHITE

## Fehlen dem Monster Elemente für diesen Skill oder läuft die Abklingzeit noch,
## steht das statt der Beschreibung auf der Karte
func show_state(mon: Monster) -> void:
	var text = Skills.missing_elements_text(mon, skill)
	if text.is_empty() and not Skills.is_ready(skill):
		text = tr("BATTLE_CARD_COOLDOWN").format({"turns": Skills.cooldown_left(skill)})
	if text.is_empty():
		_init_card()
		return
	description_label.text = text
	description_label.self_modulate = Color(1, 0.45, 0.45)

## Ausgewählte Karte leuchtet am Rahmen (erst möglich, wenn die Karte im Baum ist)
func set_selected(selected: bool) -> void:
	_paper.set_glow(SkillCardPaper.SELECTED_GLOW if selected else 0.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_swiping = false
			_press_pos = event.global_position
		else:
			_pressed = false
			_swiping = false
		accept_event()
	elif event is InputEventMouseMotion and _pressed:
		var delta: Vector2 = event.global_position - _press_pos
		if _swiping:
			if -delta.y > SWIPE_TO_DRAG:
				_pressed = false
				_swiping = false
				_start_drag()
			else:
				hand.swipe_by(-event.relative.x)
		elif delta.length() > DRAG_THRESHOLD:
			# nur eindeutig seitliche Bewegungen scrollen, schräg nach oben ist ein Drag
			if absf(delta.x) > absf(delta.y) * 1.5:
				_swiping = true
				hand.swipe_by(-delta.x)
			else:
				_pressed = false
				_start_drag()
		accept_event()
	elif event is InputEventScreenDrag or event is InputEventScreenTouch:
		# Touch wird als Maus emuliert, sonst würde der ScrollContainer doppelt scrollen
		accept_event()

func _start_drag() -> void:
	if not playable:
		return
	var preview: Control = duplicate(0)
	preview.size = size
	preview.modulate.a = 0.85
	# Vorschau so verschieben, dass sie unter dem Finger hängt
	var holder := Control.new()
	holder.add_child(preview)
	preview.position = -size / 2
	force_drag({"type": "skill_card", "skill": skill}, holder)
	modulate.a = 0.3

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		modulate.a = 1.0
