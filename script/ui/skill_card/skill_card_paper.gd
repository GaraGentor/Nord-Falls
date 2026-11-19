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

## TEST: großes Art-Symbol (Skills.kind_icon) als Wasserzeichen über die ganze Karte, eingefärbt nach Element,
## damit man auf einen Blick sieht, was die Karte macht. Unbekannte Gegner-Skills (attach mit known = false) zeigen keins.
const KIND_WATERMARK_ALPHA := 0.38
## Rand um das Symbol als Anteil der Kartengröße
const KIND_WATERMARK_MARGIN := 0.1
const KIND_COLORS := {
	"physical": Color(1.0, 0.1, 0.1),
	"magic": Color(0.6, 0.25, 1.0),
	"shield": Color(0.3, 0.8, 1.0),
	"buff": Color(0.2, 1.0, 0.2),
	"debuff": Color(1.0, 0.55, 0.0),
	"passive": Color(0.0, 0.55, 0.15),
}

## Pixel-Effekt rund um die Karte: die Bewegung zeigt die Art (Angriff Flammen, Schild Wasserwellen, Buff steigende
## Funken, Debuff sinkende Tropfen, Passiv nichts), die Farbe physisch/magisch. Platz über das Papier hinaus
## (links, oben, rechts, unten, Pixel); die Reichweiten selbst stehen im Shader.
const FLAMES_SHADER := preload("res://script/ui/skill_card/skill_card_flames.gdshader")
const FLAME_PAD := Vector4(20.0, 24.0, 20.0, 24.0)
## Abstand zwischen Karten nebeneinander, damit der Rand-Effekt nicht unter der Nachbarkarte verschwindet (FLAME_PAD.x + .z)
const FLAME_GAP_X := 40
## Abstand zwischen Kartenreihen untereinander (die Flammen oben ragen am weitesten hinaus)
const FLAME_GAP_Y := 64

## Abstände eines Containers voller Karten auf FLAME_GAP_X / FLAME_GAP_Y anheben (Grid, Flow, H-/VBox), null wird ignoriert
static func make_room_for_flames(container: Node) -> void:
	if container is GridContainer or container is FlowContainer:
		container.add_theme_constant_override("h_separation", maxi(container.get_theme_constant("h_separation"), FLAME_GAP_X))
		container.add_theme_constant_override("v_separation", maxi(container.get_theme_constant("v_separation"), FLAME_GAP_Y))
	elif container is HBoxContainer:
		container.add_theme_constant_override("separation", maxi(container.get_theme_constant("separation"), FLAME_GAP_X))
	elif container is VBoxContainer:
		container.add_theme_constant_override("separation", maxi(container.get_theme_constant("separation"), FLAME_GAP_Y))
## Effekt im Shader (mode) je Art
const KIND_EFFECTS := {
	"physical": 0,
	"magic": 0,
	"shield": 1,
	"buff": 2,
	"debuff": 3,
	# Passive bleiben ohne Effekt
	"passive": -1,
}

var _shader_material: ShaderMaterial
var _button: BaseButton
var _watermark: TextureRect
var _flames: ColorRect
var _flames_material: ShaderMaterial
## Karte hätte einen Rand-Effekt (bekannt, nicht gesperrt, nicht passiv); sichtbar nur mit GameSettings.card_effects
var _flames_wanted := false

static func kind_key(skill: Dictionary) -> String:
	if Skills.is_passive(skill):
		return "passive"
	if Skills.is_buff_skill(skill):
		return "buff"
	if Skills.is_debuff_skill(skill):
		return "debuff"
	if Skills.is_damage_skill(skill):
		return "physical" if Skills.is_physical(skill) else "magic"
	return "shield"

## Farbe der Art (voll deckend), auch für die kleinen Symbole in Tabellen und Listen
static func kind_color(skill: Dictionary) -> Color:
	return KIND_COLORS[kind_key(skill)]

## kleines Art-Symbol in der Art-Farbe, für Listen und Tabellen
static func kind_icon_rect(skill: Dictionary, icon_size: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = Skills.kind_icon(skill)
	icon.modulate = kind_color(skill)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

## Legt das Papier hinter den Inhalt von card. Skill später wechseln: set_skill()
static func attach(card: Control, skill: Dictionary, muted := false, known := true) -> SkillCardPaper:
	var paper := SkillCardPaper.new()
	paper.set_skill(skill, known)
	# das Papier ersetzt eine Eisenplatte der Karte
	for child in card.get_children():
		if child is IronPlate:
			child.visible = false
	paper._shader_material.set_shader_parameter("muted", 1.0 if muted else 0.0)
	# gesperrte Karten brennen nicht
	if muted:
		paper._flames_wanted = false
		paper._apply_settings()
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

## Rand um Karten in einem Container, der abschneidet (ScrollContainer, clip_contents): so viel Platz, wie die
## Rand-Effekte über die Karten hinausragen (FLAME_PAD). Die Karten kommen als Kind in den MarginContainer.
static func flame_margin() -> MarginContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", int(FLAME_PAD.x))
	margin.add_theme_constant_override("margin_top", int(FLAME_PAD.y))
	margin.add_theme_constant_override("margin_right", int(FLAME_PAD.z))
	margin.add_theme_constant_override("margin_bottom", int(FLAME_PAD.w))
	return margin

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
	# Kind des Papiers: liegt über dem Papier, aber hinter dem Inhalt der Karte (das Papier ist ihr erstes Kind)
	_watermark = TextureRect.new()
	_watermark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_watermark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_watermark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_watermark.anchor_left = KIND_WATERMARK_MARGIN
	_watermark.anchor_top = KIND_WATERMARK_MARGIN
	_watermark.anchor_right = 1.0 - KIND_WATERMARK_MARGIN
	_watermark.anchor_bottom = 1.0 - KIND_WATERMARK_MARGIN
	add_child(_watermark)
	# Flammen ragen FLAME_PAD über das Papier hinaus, in der Mitte bleiben sie durchsichtig (skill_card_flames.gdshader)
	_flames = ColorRect.new()
	_flames.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flames_material = ShaderMaterial.new()
	_flames_material.shader = FLAMES_SHADER
	_flames_material.set_shader_parameter("pad", FLAME_PAD)
	_flames.material = _flames_material
	_flames.anchor_right = 1.0
	_flames.anchor_bottom = 1.0
	_flames.offset_left = -FLAME_PAD.x
	_flames.offset_top = -FLAME_PAD.y
	_flames.offset_right = FLAME_PAD.z
	_flames.offset_bottom = FLAME_PAD.w
	_flames.resized.connect(func(): _flames_material.set_shader_parameter("rect_size", _flames.size))
	add_child(_flames)
	# Einstellung live übernehmen; Godot trennt die Verbindung, wenn das Papier freigegeben wird
	GameSettings.changed.connect(_apply_settings)

func _apply_settings() -> void:
	_flames.visible = _flames_wanted and GameSettings.card_effects
	_watermark.visible = GameSettings.card_watermark

## known = false: unbekannter Skill eines Gegners, kein Wasserzeichen und keine Flammen (das "scouted" der
## Skill-Vorlagen ist meist false und taugt dafür nicht, die Stelle mit der Karte weiß, ob der Skill bekannt ist)
func set_skill(skill: Dictionary, known := true) -> void:
	_watermark.texture = Skills.kind_icon(skill) if known else null
	var kind := kind_key(skill)
	var kind_color: Color = KIND_COLORS[kind]
	_flames_material.set_shader_parameter("mode", KIND_EFFECTS[kind])
	# physisch / magisch, beim Schild eckige Runen bzw. runde Glyphen
	_flames_material.set_shader_parameter("variant", 1 if kind == "magic" else 0)
	_flames_material.set_shader_parameter("flame_color", kind_color)
	_flames_material.set_shader_parameter("seed", float(hash(skill.name) % 100))
	_flames_wanted = known and KIND_EFFECTS[kind] >= 0
	_apply_settings()
	var color := Helper.color_by_type(skill.nature)
	var accent := _with_min_lightness(color, MIN_ACCENT_LIGHTNESS)
	_shader_material.set_shader_parameter("accent", accent)
	# Wasserzeichen in der Elementfarbe (wie der Rahmen), die Art zeigt schon das Symbol selbst
	accent.a = KIND_WATERMARK_ALPHA
	_watermark.modulate = accent
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
