class_name MoveChevrons
extends Control

## Pfeile hinter dem Seltenheits-Stern auf den Monsterkarten am Zugrad (BattleMonCard):
## ">" , ">>" oder ">>>": so viele Aktionen hat ein Gegner pro Zug. Im Stil der Zug-Rune (moves_rune.gdshader):
## Goldrand mit Schatten, innen glimmt eine pulsierende Glut.
## Dazu der "NEU"-Aufkleber (make_new_tag) für Arten, die man noch nicht besitzt: liegt über der Karte bzw. dem
## Hypnose-Knopf und nimmt im Layout keinen Platz weg.

## so viele Pfeile höchstens, mehr Aktionen stehen im Tooltip
const MAX_CHEVRONS := 3
const CHEVRON_SIZE := Vector2(12, 20)
## Dicke eines Pfeils (waagerecht gemessen)
const CHEVRON_THICKNESS := 6.0
const CHEVRON_GAP := 1.5
const SHADOW_OFFSET := Vector2(2, 2)
const SHADOW_COLOR := Color(0, 0, 0, 0.55)
const OUTLINE_COLOR := Color(0.02, 0.03, 0.05)
## Farben wie die Zug-Rune
const GOLD := Color(0.858824, 0.717647, 0.45098)
const GLOW := Color(1.0, 0.5, 0.12)
const GLOW_DARK := Color(0.55, 0.22, 0.05)
const PULSE_SPEED := 2.2
## "NEU"-Aufkleber: helles Gold, schräg, pulsiert sanft
const NEW_BRIGHT := Color(1.0, 0.95, 0.7)
const NEW_ROTATION := 0.2
const NEW_PULSE_SCALE := 1.12
const NEW_PULSE_TIME := 0.6

var _chevrons := 0

## Art noch nicht im Besitz (Start-Monster und freigeschaltete Eier) und auch nicht schon im Team dieses Runs
static func is_new_species(mon_name: String) -> bool:
	return not Helper.get_all_owned_monster_names().has(mon_name) \
		and not State.mons.any(func(m: Monster): return m._name == mon_name)

## Schräger, pulsierender Aufkleber (z. B. "NEU"), wird über ein anderes Control gelegt. Die Lage setzt der Aufrufer,
## das Pulsieren beginnt, sobald er im Baum ist.
static func make_new_tag(text: String, font_size: int) -> Label:
	var tag := Label.new()
	tag.text = text
	tag.add_theme_font_size_override("font_size", font_size)
	tag.add_theme_color_override("font_color", NEW_BRIGHT)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 8)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.tooltip_text = TranslationServer.translate("BATTLE_MON_NEW_HINT")
	tag.rotation = NEW_ROTATION
	tag.resized.connect(func(): tag.pivot_offset = tag.size / 2)
	tag.tree_entered.connect(func():
		var pulse := tag.create_tween().set_loops()
		pulse.tween_property(tag, "scale", Vector2.ONE * NEW_PULSE_SCALE, NEW_PULSE_TIME).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(tag, "scale", Vector2.ONE, NEW_PULSE_TIME).set_trans(Tween.TRANS_SINE), CONNECT_ONE_SHOT)
	return tag

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	set_process(false)

## chevrons: Aktionen pro Zug (0 = keine Pfeile)
func setup(chevrons: int) -> void:
	_chevrons = chevrons
	tooltip_text = tr("BATTLE_ENEMY_ACTIONS").format({"count": chevrons}) if chevrons > 0 else ""
	visible = chevrons > 0
	var shown := mini(chevrons, MAX_CHEVRONS)
	custom_minimum_size = Vector2(shown * CHEVRON_SIZE.x + maxi(shown - 1, 0) * CHEVRON_GAP + SHADOW_OFFSET.x,
		CHEVRON_SIZE.y + SHADOW_OFFSET.y)
	set_process(visible)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var height := size.y - SHADOW_OFFSET.y
	var x := 0.0
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * PULSE_SPEED)
	for i in mini(_chevrons, MAX_CHEVRONS):
		_draw_chevron(Vector2(x, (height - CHEVRON_SIZE.y) / 2), pulse)
		x += CHEVRON_SIZE.x + CHEVRON_GAP

func _chevron_points(origin: Vector2, w: float, h: float, t: float) -> PackedVector2Array:
	return PackedVector2Array([
		origin, origin + Vector2(t, 0), origin + Vector2(w, h / 2),
		origin + Vector2(t, h), origin + Vector2(0, h), origin + Vector2(w - t, h / 2)])

func _draw_chevron(origin: Vector2, pulse: float) -> void:
	var w := CHEVRON_SIZE.x
	var h := CHEVRON_SIZE.y
	var t := CHEVRON_THICKNESS
	draw_colored_polygon(_chevron_points(origin + SHADOW_OFFSET, w, h, t), SHADOW_COLOR)
	var outer := _chevron_points(origin, w, h, t)
	draw_colored_polygon(outer, GOLD)
	# Glut im Inneren: etwas kleinerer Pfeil, pulsiert wie die Rune
	var inner := _chevron_points(origin + Vector2(1.8, 3.0), w - 3.4, h - 6.0, t - 2.6)
	draw_colored_polygon(inner, GLOW_DARK.lerp(GLOW, lerpf(0.45, 1.0, pulse)))
	var outline := outer.duplicate()
	outline.append(outer[0])
	draw_polyline(outline, OUTLINE_COLOR, 1.5)
