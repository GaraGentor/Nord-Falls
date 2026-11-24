class_name StatusPopup
extends PopupPanel

## Kleines Fenster über dem Status eines Monsters im Kampf (MonsterScene): listet, welche Werte gerade verstärkt
## oder geschwächt sind, um wie viel und wie lange, dazu Aufladungen und Statuseffekte.
## Schließt sich beim Klick daneben von selbst (PopupPanel).

const THEME := preload("res://script/ui/materials/pixel_font_theme.tres")
const FONT_SIZE := 24
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
	for kind in mon._boons:
		var stat: String = BOON_ICON_STATS.get(kind, "")
		if stat != "" and not stats.has(stat):
			stats.append(stat)
	for mod in mon._flat_mods.values():
		var stat: String = FLAT_ICON_STATS.get(mod.stat, mod.stat)
		if mod.value > 0.0 and not stats.has(stat):
			stats.append(stat)
	return stats

## Symbol (Stat-Key) pro Sonder-Verstärkung im Status unter dem Monster
const BOON_ICON_STATS := {"crit_next": "atk", "crit": "atk", "leech": "hp", "extra_moves": "speed", "taunt": "def",
	"double_hit": "atk", "extra_action": "speed"}
## Symbol für feste Boni ohne eigenen Wert (Schild-Bonus -> Verteidigung, Schadens-Bonus -> Angriff), Plage -> Initiative
const FLAT_ICON_STATS := {"shield": "def", "damage": "atk", "moves": "speed"}

## Werte mit Schwächung (mehrere Quellen auf denselben Wert zählen einmal)
static func debuffed_stats(mon: Monster) -> Array:
	var stats := []
	for debuff in mon._debuffs.values():
		var stat: String = FLAT_ICON_STATS.get(debuff.stat, debuff.stat) if debuff.stat == "moves" else debuff.stat
		if not stats.has(stat):
			stats.append(stat)
	for mod in mon._flat_mods.values():
		var stat: String = FLAT_ICON_STATS.get(mod.stat, mod.stat)
		if mod.value < 0.0 and not stats.has(stat):
			stats.append(stat)
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
	# feste Boni (Doppelter Schild, Kampfgeist, Rückenwind ...)
	for mod in mon._flat_mods.values():
		if mod.value > 0.0:
			lines.append([tr("STATUS_FLAT_BUFF_LINE").format({"value": roundi(mod.value), "stat": Skills.stat_label(mod.stat),
				"turns": _turns(mod.turns)}), BUFF_COLOR])
	for kind in mon._charges:
		lines.append([tr("STATUS_CHARGE_LINE_" + String(kind).to_upper()).format({"value": roundi(mon._charges[kind] * 100)}), BUFF_COLOR])
	# Sonder-Verstärkungen (kritische Treffer, Lebensraub, Aktionen, Aggro)
	for kind in mon._boons:
		var boon: Dictionary = mon._boons[kind]
		lines.append([tr("STATUS_BOON_" + String(kind).to_upper()).format({"value": roundi(boon.value), "turns": _turns(boon.turns)}), BUFF_COLOR])
	for debuff in mon._debuffs.values():
		# Plage: höchstens n Aktionen pro Zug
		if debuff.stat == "moves":
			lines.append([tr("STATUS_MOVES_CAP_LINE").format({"value": roundi(debuff.factor), "turns": _turns(debuff.turns)}),
				ElementEffects.DEBUFF_COLOR])
			continue
		lines.append([tr("STATUS_DEBUFF_LINE").format({"value": roundi(debuff.factor * 100), "stat": Skills.stat_label(debuff.stat),
			"turns": _turns(debuff.turns)}), ElementEffects.DEBUFF_COLOR])
	for mod in mon._flat_mods.values():
		if mod.value < 0.0:
			lines.append([tr("STATUS_FLAT_DEBUFF_LINE").format({"value": roundi(-mod.value), "stat": Skills.stat_label(mod.stat),
				"turns": _turns(mod.turns)}), ElementEffects.DEBUFF_COLOR])
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
