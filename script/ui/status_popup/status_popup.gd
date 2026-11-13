class_name StatusPopup
extends PopupPanel

## Kleines Fenster über dem Status eines Monsters im Kampf (MonsterScene): listet, welche Werte gerade verstärkt
## oder geschwächt sind, um wie viel und wie lange, dazu Aufladungen und Statuseffekte.
## Schließt sich beim Klick daneben von selbst (PopupPanel).

const THEME := preload("res://script/ui/materials/pixel_font_theme.tres")
const FONT_SIZE := 18
const BUFF_COLOR := Color(0.55, 1.0, 0.55)
const TEXT_COLOR := Color(0.92, 0.9, 0.85)
const BACKGROUND := Color(0.08, 0.07, 0.1, 0.94)
const BORDER := Color(0.858824, 0.717647, 0.45098)

## Werte mit Verstärkung oder Aufladung (Aufladungen zählen als Angriff bzw. Sp. Angriff)
static func buffed_stats(mon: Monster) -> Array:
	var stats: Array = mon._buffs.keys()
	for kind in mon._charges:
		var stat: String = "atk" if kind == "physical" else "s_atk"
		if not stats.has(stat):
			stats.append(stat)
	return stats

## Werte mit Schwächung (mehrere Quellen auf denselben Wert zählen einmal)
static func debuffed_stats(mon: Monster) -> Array:
	var stats := []
	for debuff in mon._debuffs.values():
		if not stats.has(debuff.stat):
			stats.append(debuff.stat)
	return stats

## Öffnet das Fenster unter anchor
static func open(anchor: Control, mon: Monster) -> void:
	if mon == null:
		return
	var popup := StatusPopup.new()
	anchor.get_tree().root.add_child(popup)
	popup._fill(mon)
	popup.popup_hide.connect(popup.queue_free)
	var rect := anchor.get_global_rect()
	popup.popup(Rect2i(Vector2i(rect.position + Vector2(0, rect.size.y + 4)), Vector2i.ZERO))

func _fill(mon: Monster) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.theme = THEME
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var lines := _lines(mon)
	if lines.is_empty():
		lines.append([tr("STATUS_POPUP_NONE"), TEXT_COLOR])
	for line in lines:
		var label := Label.new()
		label.text = line[0]
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_color", line[1])
		box.add_child(label)

## [Text, Farbe] pro Zeile
func _lines(mon: Monster) -> Array:
	var lines := []
	for stat in mon._buffs:
		var buff: Dictionary = mon._buffs[stat]
		lines.append([tr("STATUS_BUFF_LINE").format({"value": roundi(buff.factor * 100), "stat": Skills.stat_label(stat),
			"turns": _turns(buff.turns)}), BUFF_COLOR])
	for kind in mon._charges:
		lines.append([tr("STATUS_CHARGE_LINE_" + String(kind).to_upper()).format({"value": roundi(mon._charges[kind] * 100)}), BUFF_COLOR])
	for debuff in mon._debuffs.values():
		lines.append([tr("STATUS_DEBUFF_LINE").format({"value": roundi(debuff.factor * 100), "stat": Skills.stat_label(debuff.stat),
			"turns": _turns(debuff.turns)}), ElementEffects.DEBUFF_COLOR])
	for status in mon._statuses:
		var text := tr(ElementEffects.STATUS_LABELS[status])
		if status == ElementEffects.POISON:
			text += " x%d" % mon.status_stacks(status)
		lines.append([text + " (" + tr("STATUS_UNTIL_END") + ")", ElementEffects.STATUS_COLORS[status]])
	return lines

## Verbleibende eigene Züge: gespeichert wird +1, weil zu Beginn jedes Zuges heruntergezählt wird
func _turns(turns: int) -> String:
	if turns < 0:
		return tr("STATUS_UNTIL_END")
	return tr("STATUS_TURNS").format({"turns": maxi(turns - 1, 1)})
