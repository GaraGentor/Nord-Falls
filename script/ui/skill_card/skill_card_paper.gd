class_name SkillCardPaper
extends ColorRect

## Hintergrund aller Skill-Karten: dunkles Kartenpapier mit Rissen und Rahmen in der Elementfarbe.
## attach() legt es hinter den Inhalt einer Karte und entfernt deren alten Rahmen.
## Buttons zeigen Hover und Auswahl über den Papierrahmen.

const SHADER := preload("res://script/ui/skill_card/skill_card_paper.gdshader")
const INK := Color(0.72, 0.61, 0.44)
const GOLD := Color(0.858824, 0.717647, 0.45098, 1)
## Rahmenglühen je nach Button-Zustand
const HOVER_GLOW := 0.45
const SELECTED_GLOW := 1.0
## dunklere Elementfarben (Erde, Magma ...) werden bis zu dieser Helligkeit aufgehellt
const MIN_TEXT_LIGHTNESS := 0.72
const MIN_ACCENT_LIGHTNESS := 0.55

var _shader_material: ShaderMaterial
var _button: BaseButton

## Legt das Papier hinter den Inhalt von card. Skill später wechseln: set_skill()
static func attach(card: Control, skill: Dictionary, muted := false) -> SkillCardPaper:
	var paper := SkillCardPaper.new()
	paper.set_skill(skill)
	# das Papier ersetzt eine Eisenplatte der Karte
	for child in card.get_children():
		if child is IronPlate:
			child.visible = false
	paper._shader_material.set_shader_parameter("muted", 1.0 if muted else 0.0)
	card.add_child(paper)
	card.move_child(paper, 0)
	if card is PanelContainer:
		card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if card is BaseButton:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			card.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		paper._button = card
		# jeder Zustandswechsel zeichnet den Button neu, auch set_pressed_no_signal
		card.draw.connect(paper._sync_button)
	return paper

## Elementfarbe, die auf dem dunklen Papier gut lesbar ist
static func readable_color(color: Color) -> Color:
	return _with_min_lightness(color, MIN_TEXT_LIGHTNESS)

static func _with_min_lightness(color: Color, lightness: float) -> Color:
	if color.get_luminance() >= lightness:
		return color
	# erst den Farbton voll aufdrehen, reicht das nicht, Richtung Weiß mischen
	var bright := Color.from_hsv(color.h, color.s, 1.0)
	var missing := lightness - bright.get_luminance()
	return bright.lerp(Color.WHITE, missing / (1.0 - bright.get_luminance())) if missing > 0.0 else bright

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = SHADER
	material = _shader_material
	resized.connect(func(): _shader_material.set_shader_parameter("rect_size", size))

func set_skill(skill: Dictionary) -> void:
	var color := Helper.color_by_type(skill.nature)
	_shader_material.set_shader_parameter("accent", _with_min_lightness(color, MIN_ACCENT_LIGHTNESS))
	# gleiche Karte, gleiches Muster. Shader-Rauschen rechnet mit kleinen Zahlen genauer
	_shader_material.set_shader_parameter("seed", float(hash(skill.name) % 100))

func _sync_button() -> void:
	var glow := 0.0
	match _button.get_draw_mode():
		BaseButton.DRAW_HOVER:
			glow = HOVER_GLOW
		BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED:
			glow = SELECTED_GLOW
	set_glow(glow)

## Rahmen golden leuchten lassen, 0 = normaler Rahmen
func set_glow(glow: float) -> void:
	_shader_material.set_shader_parameter("frame_glow", glow)
	_shader_material.set_shader_parameter("frame_color", GOLD if glow > 0.0 else INK)
