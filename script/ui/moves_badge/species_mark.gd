class_name SpeciesMark
extends Control

## Gesprengte Kette hinter dem Seltenheits-Stern auf den Gegner-Karten am Zugrad (BattleMonCard):
## zeigt, wie weit man die Art beim Kerkermeister schon verbessert hat, damit man den Fang besser abwägen kann.
## Silbern = mindestens eine Kette gesprengt, golden (mit pulsierendem Glanz) = alle Ketten gesprengt.
## Keine Verbesserung (oder neue Art) = nichts zu sehen.
## Dazu der "NEU"-Aufkleber (make_new_tag) für Arten, die man noch nicht besitzt: liegt über der Karte bzw. dem
## Hypnose-Knopf und nimmt im Layout keinen Platz weg.

enum Tier { NONE, SILVER, GOLD }

## Form wie assets/ui/jailer/chain_broken.svg (96 x 56), auf MARK_HEIGHT verkleinert
const SOURCE_SIZE := Vector2(96, 56)
const MARK_HEIGHT := 30.0
const SHADOW_OFFSET := Vector2(2, 2)
const SHADOW_COLOR := Color(0, 0, 0, 0.55)
const OUTLINE_COLOR := Color(0.02, 0.03, 0.05)
## Strichstärken im SVG-Maß: Umriss, Metall, Glanzlinie
const OUTLINE_WIDTH := 13.0
const METAL_WIDTH := 7.0
## dünner Glanz oben auf dem Metall, halb durchsichtig, damit die Metallfarbe trägt
const SHINE_WIDTH := 2.0
const SHINE_ALPHA := 0.6
## Bruchstücke dicker als im SVG, sonst sieht man den Bruch bei Kartengröße nicht
const FRAGMENT_OUTLINE_WIDTH := 12.0
const FRAGMENT_WIDTH := 6.0
const ARC_POINTS := 8
## Metallfarben: Grundton und Glanz
const SILVER := Color(0.62, 0.66, 0.72)
const SILVER_SHINE := Color(0.92, 0.95, 1.0)
const GOLD := Color(0.858824, 0.717647, 0.45098)
const GOLD_SHINE := Color(1.0, 0.93, 0.62)
## Gold pulsiert zwischen Grundton und diesem hellen Gold (nicht über Orange)
const GOLD_BRIGHT := Color(1.0, 0.85, 0.42)
const PULSE_SPEED := 2.2
## "NEU"-Aufkleber: helles Gold, schräg, pulsiert sanft
const NEW_BRIGHT := Color(1.0, 0.95, 0.7)
const NEW_ROTATION := 0.2
const NEW_PULSE_SCALE := 1.12
const NEW_PULSE_TIME := 0.6

var _tier := Tier.NONE

## Art noch nicht im Besitz (Start-Monster und freigeschaltete Eier) und auch nicht schon im Team dieses Runs
static func is_new_species(mon_name: String) -> bool:
	return not Helper.get_all_owned_monster_names().has(mon_name) \
		and not State.mons.any(func(m: Monster): return m._name == mon_name)

## Beim Kerkermeister gesprengte Ketten der Art (gespeichert pro Art) und die höchstens möglichen
static func jailer_upgrades(mon_name: String) -> Vector2i:
	var level: int = SaveManager.save_data.monsters.get(mon_name, {}).get("upgrade", 0)
	return Vector2i(level, Monmap.mon_metainfos_by_name(mon_name).get("max_upgrades", 0))

static func tier_of(mon_name: String) -> Tier:
	var upgrades := jailer_upgrades(mon_name)
	if upgrades.x <= 0:
		return Tier.NONE
	return Tier.GOLD if upgrades.x >= upgrades.y else Tier.SILVER

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
	custom_minimum_size = SOURCE_SIZE * _scale() + SHADOW_OFFSET
	set_process(false)

## Kette für die Art von mon_name, bei Tier.NONE unsichtbar
func setup(mon_name: String) -> void:
	_tier = tier_of(mon_name)
	visible = _tier != Tier.NONE
	if visible:
		var upgrades := jailer_upgrades(mon_name)
		var key := "BATTLE_MON_CHAINS_MAX" if _tier == Tier.GOLD else "BATTLE_MON_CHAINS_SOME"
		tooltip_text = tr(key).format({"broken": upgrades.x, "max": upgrades.y})
	else:
		tooltip_text = ""
	# nur Gold glänzt pulsierend
	set_process(_tier == Tier.GOLD)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _scale() -> float:
	return MARK_HEIGHT / SOURCE_SIZE.y

## Offenes Glied wie im SVG: "M30 11 H18 Q8 11 8 21 V35 Q8 45 18 45 H30", side -1 = links, 1 = rechts (gespiegelt)
func _half_link(side: float, end_x: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2(end_x, 11)])
	# obere Ecke: von oben (-PI/2) nach links (-PI), untere Ecke: von links (PI) nach unten (PI/2)
	for i in ARC_POINTS + 1:
		var a := -PI / 2 - PI / 2 * i / ARC_POINTS
		points.append(Vector2(18, 21) + Vector2(cos(a), sin(a)) * 10)
	for i in ARC_POINTS + 1:
		var a := PI - PI / 2 * i / ARC_POINTS
		points.append(Vector2(18, 35) + Vector2(cos(a), sin(a)) * 10)
	points.append(Vector2(end_x, 45))
	if side > 0:
		for i in points.size():
			points[i].x = SOURCE_SIZE.x - points[i].x
	return points

func _transform(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var s := _scale()
	var origin := Vector2(0, (size.y - SHADOW_OFFSET.y - MARK_HEIGHT) / 2) + offset
	var result := PackedVector2Array()
	for p in points:
		result.append(origin + p * s)
	return result

func _draw() -> void:
	if _tier == Tier.NONE:
		return
	var s := _scale()
	var metal := SILVER
	var shine := SILVER_SHINE
	if _tier == Tier.GOLD:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * PULSE_SPEED)
		metal = GOLD.lerp(GOLD_BRIGHT, pulse)
		shine = GOLD_SHINE
	shine.a = SHINE_ALPHA
	var links := [_half_link(-1, 30), _half_link(1, 30)]
	# Bruchstücke des mittleren Glieds, länger als im SVG
	var fragments := [
		PackedVector2Array([Vector2(39, 28), Vector2(47, 17)]),
		PackedVector2Array([Vector2(49, 39), Vector2(57, 28)])]
	# Schatten, Umriss, Metall, Glanz
	for offset_color in [[SHADOW_OFFSET, SHADOW_COLOR], [Vector2.ZERO, OUTLINE_COLOR]]:
		for link in links:
			draw_polyline(_transform(link, offset_color[0]), offset_color[1], OUTLINE_WIDTH * s, true)
		for fragment in fragments:
			draw_polyline(_transform(fragment, offset_color[0]), offset_color[1], FRAGMENT_OUTLINE_WIDTH * s, true)
	for link in links:
		draw_polyline(_transform(link, Vector2.ZERO), metal, METAL_WIDTH * s, true)
		draw_polyline(_transform(link, Vector2(0, -1)), shine, SHINE_WIDTH * s, true)
	for fragment in fragments:
		draw_polyline(_transform(fragment, Vector2.ZERO), metal, FRAGMENT_WIDTH * s, true)
		draw_polyline(_transform(fragment, Vector2(0, -1)), shine, SHINE_WIDTH * s, true)
