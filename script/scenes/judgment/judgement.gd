extends Control

## Nach dem Kampf. Links blättert man durch die neuen Fänge (und aus dem Team abgelegte Monster), darunter
## vergleicht ein Netzdiagramm das Wachstum des Fangs mit dem Team. Rechts steht das Team, in der Mitte die
## Fähigkeiten des ausgewählten Monsters (gelber Pfeil).
## - Monster ziehen: Fang auf ein Teammitglied tauscht, auf einen freien Platz nimmt ihn auf. Teammitglieder
##   nach links ziehen legt sie ab, auf das andere Teammitglied tauscht die Plätze.
## - Fähigkeit auf ein Teammitglied ziehen: es verleibt sich das Monster ein und lernt sie, das Monster geht.
## - Ei-Attacke eines neuen Fangs in die Tasche ziehen: dauerhaft freigeschaltet, das Monster geht.
##   Das geht nur im Judgement direkt nach dem Fang, später nicht mehr. Die Tasche fliegt nur herein, solange
##   das ausgewählte Monster eine solche Ei-Attacke trägt.
## Was beim Weiter links liegt, wird freigelassen. Ohne Teammitglied ist Weiter gesperrt.
## Ist im Kampf ein eigenes Monster gefallen, kann es zuerst einmalig durch einen neuen Fang wiederbelebt werden.
## Wird das übersprungen oder ist es nicht möglich, vererbt es eine Sache (Letzter Wille).

const GOLD := SkillDetailPopup.GOLD
const MUTED := IronPlate.TEXT_COLOR
const EGG_ICON = preload("res://assets/ui/eggs/common_1.png")
const RARITY_STAR = preload("res://assets/ui/icons/rarity_star.svg")
const LIVING_MATERIAL = preload("res://script/ui/shader/living_pixels_material.tres")
const ELEMENT_CHIP = preload("res://script/ui/element_chip/element_chip.tscn")
const INSET_BOX = preload("res://script/ui/materials/iron_inset_box.tres")
const MAP_SCENE := "res://script/scenes/world_map/world_map.tscn"
const MAX_TEAM := 2
const DRAG_THRESHOLD := 10.0
# Anteil der KP, mit dem ein wiederbelebtes Monster zurückkommt
const REVIVE_HP_SHARE := 0.3

## Farben der Werte-Rahmen, dieselben Farben im Netzdiagramm
const CATCH_COLOR := Color(0.36, 0.82, 0.4)
const SLOT_COLORS := [Color(0.7, 0.45, 0.96), Color(0.25, 0.85, 0.8)]
const STAT_KEYS := Growth.ATTRS
const STAT_LABELS := GrowthRadar.STAT_LABELS
## Breite einer Werte-Zelle (Symbol und Zahl): passen alle sechs nebeneinander, stehen sie in einer Zeile
const STAT_CELL_WIDTH := 46.0
## Höhe des Monsterbilds links (das Netzdiagramm braucht darunter Platz), im Team füllt das Bild den Platz
const CATCH_PICTURE_HEIGHT := 130.0
const TEAM_PICTURE_MIN_HEIGHT := 90.0
const SKILL_CARD_HEIGHT := 200.0
const COLUMN_GAP := 46.0
## Gelber Pfeil am ausgewählten Monster, wie im Kampf
const ARROW_COLOR := Color(1.0, 0.85, 0.25)
const ARROW_SIZE := 26.0
const ARROW_BOB := 6.0
## Goldener Rahmen um mögliche Ablagen beim Ziehen
const DROP_FRAME_WIDTH := 3
const BAG_SIZE := Vector2(200, 158)
const BAG_ITEM_SIZE := Vector2(34, 42)
const BAG_FLY_TIME := 0.35
## So weit liegt die Tasche versteckt unter ihrem Platz
const BAG_HIDDEN_OFFSET := 260.0

enum Zone { SLOT_1, SLOT_2, BENCH, BAG }

@export var dialog: JudgementDialog

# Monster links: neue Fänge und aus dem Team abgelegte Monster
var _pool: Array = []
# Fänge dieses Kampfes (nur deren Ei-Attacken lassen sich freischalten)
var _new_mons: Array = []
var _index := 0
# Monster, dessen Fähigkeiten in der Mitte stehen
var _selected: Monster = null
# in diesem Judgement freigeschaltete Ei-Attacken (Eier in der Tasche)
var _eggs_unlocked := 0
# Mausdruck auf einem Monster oder einer Fähigkeit, aus dem ein Klick oder ein Drag wird
var _press := {}
var _drag_data := {}
var _arrow_time := 0.0

# Zone -> JudgementDropZone
var _zones := {}
# Zone -> goldener Rahmen (Team-Plätze und Fang-Seite), sichtbar wenn die Ablage beim Ziehen möglich ist
var _zone_frames := {}
# Monster-Anzeige pro Ort, für Klicks, Drags und den Pfeil
var _catch_entry: Control
var _slot_entries := [null, null]
var _skill_cards: Array = []

var _left_zone: Control
var _catch_box: VBoxContainer
var _page_label: Label
var _prev_button: Button
var _next_button: Button
var _radar: GrowthRadar
var _legend: HFlowContainer
var _team_frame: Control
var _slot_boxes: Array = []
var _skill_grid: GridContainer
var _bag: OpenBag
var _bag_zone: JudgementDropZone
var _bag_shown := false
var _bag_tween: Tween
var _confirm_button: Button
var _arrow: Control

func _ready() -> void:
	_pool = State.catched_mons.duplicate()
	_new_mons = _pool.duplicate()
	if _pool.is_empty() and State.fainted_own_mons.is_empty():
		get_tree().change_scene_to_file.call_deferred(MAP_SCENE)
		return
	_build()
	_refresh()
	await _handle_fallen()
	if _pool.is_empty():
		get_tree().change_scene_to_file.call_deferred(MAP_SCENE)
		return
	_refresh()
	Tutorial.trigger("judgement")

func _process(delta: float) -> void:
	if _arrow:
		_arrow_time += delta
		_arrow.queue_redraw()
	if _drag_data.is_empty():
		return
	for zone in _zones:
		var allowed := _reason(zone, _drag_data) == ""
		_highlight(zone, allowed, allowed and _zones[zone].is_drag_hovered())

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and not _drag_data.is_empty():
		_drag_data = {}
		for zone in _zones:
			_highlight(zone, false, false)

func _highlight(zone: int, allowed: bool, hovered: bool) -> void:
	_zones[zone].modulate = Color(1.25, 1.25, 1.2) if hovered else Color.WHITE
	if zone == Zone.BAG:
		_bag.set_gold(allowed)
	else:
		_zone_frames[zone].visible = allowed

# ─────────────────────────
# Eingabe

func _input(event: InputEvent) -> void:
	if dialog.visible or _zones.is_empty():
		return
	# Monster und Karten werden hier vor der GUI ausgewertet, das Tutorial-Overlay würde sie sonst nicht abfangen
	var mouse := event as InputEventMouse
	if mouse and Tutorial.blocks_input(mouse.position):
		return
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_press = {}
			var mon := _mon_at(button.position)
			if mon:
				_press = {"data": {"judgement_mon": mon}, "pos": button.position}
				return
			var card := _skill_card_at(button.position)
			if card:
				_press = {"data": {"judgement_skill": card.get_meta("skill"), "owner": _selected}, "pos": button.position}
		elif not _press.is_empty():
			var data: Dictionary = _press.data
			_press = {}
			if data.has("judgement_mon"):
				_select(data.judgement_mon)
		return
	var motion := event as InputEventMouseMotion
	if motion and not _press.is_empty() and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if motion.position.distance_to(_press.pos) > DRAG_THRESHOLD:
			_drag_data = _press.data
			_press = {}
			if _drag_data.has("judgement_mon"):
				_select(_drag_data.judgement_mon)
			force_drag(_drag_data, _drag_preview(_drag_data))

func _mon_at(pos: Vector2) -> Monster:
	if _catch_entry and _catch_entry.get_global_rect().has_point(pos):
		return _pool[_index]
	for slot in MAX_TEAM:
		var entry: Control = _slot_entries[slot]
		if entry and entry.get_global_rect().has_point(pos):
			return State.mons[slot]
	return null

func _skill_card_at(pos: Vector2) -> Control:
	for card in _skill_cards:
		if card.get_global_rect().has_point(pos):
			return card
	return null

func _step(direction: int) -> void:
	if _pool.size() <= 1:
		return
	var was_selected := _pool.has(_selected)
	_index = posmod(_index + direction, _pool.size())
	if was_selected:
		_selected = _pool[_index]
	_refresh()
	# kurz einblenden, damit der Wechsel auffällt
	_catch_box.modulate.a = 0.0
	create_tween().tween_property(_catch_box, "modulate:a", 1.0, 0.15)

func _select(mon: Monster) -> void:
	if mon == _selected:
		return
	_selected = mon
	_refresh()

func _on_dropped(data: Dictionary, zone: int) -> void:
	if _reason(zone, data) != "":
		return
	if data.has("judgement_mon"):
		var mon: Monster = data.judgement_mon
		match zone:
			Zone.SLOT_1, Zone.SLOT_2:
				_place(mon, zone - Zone.SLOT_1)
			Zone.BENCH:
				_bench(mon)
	else:
		match zone:
			Zone.SLOT_1, Zone.SLOT_2:
				await _absorb(data.owner, data.judgement_skill, State.mons[zone - Zone.SLOT_1])
			Zone.BAG:
				await _sacrifice(data.owner)
	_refresh()

func _on_confirm_pressed() -> void:
	if dialog.visible or State.mons.is_empty():
		return
	if _pool.any(_is_guarded_starter):
		var ok = await dialog.confirm(tr("JUDGEMENT_RELEASE_STARTER_TITLE"), _starter_warning(), tr("JUDGEMENT_RELEASE_CONFIRM"))
		if not ok:
			return
	# Neu ins Team aufgenommene Fänge starten mit vollen HP
	for mon in State.mons:
		if _new_mons.has(mon):
			mon._lost_hp = 0
	State.catched_mons.clear()
	get_tree().change_scene_to_file(MAP_SCENE)

# ─────────────────────────
# Regeln & Aktionen

# "" wenn data hier abgelegt werden darf, sonst "-"
func _reason(zone: int, data: Dictionary) -> String:
	if data.has("judgement_mon"):
		var mon: Monster = data.judgement_mon
		var in_team := State.mons.has(mon)
		match zone:
			Zone.SLOT_1, Zone.SLOT_2:
				var slot := zone - Zone.SLOT_1
				if not in_team:
					return ""
				# Teammitglied auf das andere: Plätze tauschen
				return "" if State.mons.size() == MAX_TEAM and State.mons[slot] != mon else "-"
			Zone.BENCH:
				return "" if in_team else "-"
		return "-"
	var skill: Dictionary = data.judgement_skill
	var owner: Monster = data.owner
	match zone:
		Zone.SLOT_1, Zone.SLOT_2:
			var slot := zone - Zone.SLOT_1
			if slot >= State.mons.size() or State.mons[slot] == owner or Skills.knows_skill(State.mons[slot], skill.name):
				return "-"
			return ""
		Zone.BAG:
			return "" if _is_unlockable_egg(owner, skill) else "-"
	return "-"

func _is_unlockable_egg(mon: Monster, skill: Dictionary) -> bool:
	return _new_mons.has(mon) and Skills.is_unlockable_egg_skill(mon, skill)

# Fang auf einen Team-Platz: tauscht mit dem bisherigen Monster, das dann links liegt.
# Teammitglied auf das andere: Plätze tauschen.
func _place(mon: Monster, slot: int) -> void:
	if State.mons.has(mon):
		var from = State.mons.find(mon)
		State.mons[from] = State.mons[slot]
		State.mons[slot] = mon
		return
	var pool_index = _pool.find(mon)
	if slot < State.mons.size():
		_pool[pool_index] = State.mons[slot]
		State.mons[slot] = mon
		_index = pool_index
	else:
		State.mons.append(mon)
		_pool.remove_at(pool_index)

# Teammitglied nach links ablegen: es liegt danach vorne im Blätterstapel
func _bench(mon: Monster) -> void:
	State.mons.erase(mon)
	_pool.append(mon)
	_index = _pool.size() - 1

# target verleibt sich owner ein und lernt skill, owner geht
func _absorb(owner: Monster, skill: Dictionary, target: Monster) -> void:
	if not await _may_lose(owner):
		return
	var replace := -1
	if target._skills.size() >= Skills.MAX_SKILLS:
		replace = await dialog.pick_replace(target, skill)
		if replace == -1:
			return
	var learned = Skills.learnable_copy(skill)
	if replace == -1:
		target._skills.append(learned)
	else:
		target._skills[replace] = learned
	_remove(owner)
	Helper.show_unlock_message(tr("JUDGEMENT_ABSORBED").format({
		"target": Helper.mon_battle_name(target), "mon": Helper.mon_battle_name(owner), "skill": tr(skill.name)}))

func _sacrifice(mon: Monster) -> void:
	if not await _may_lose(mon):
		return
	var egg_skill = mon.get_unlockable_egg_skill()
	SaveManager.unlock_egg_skill(mon._name, egg_skill.name)
	_eggs_unlocked += 1
	Helper.show_unlock_message(tr("EGG_SKILL_UNLOCKED").format({"skill": tr(egg_skill.name), "mon": Helper.mon_display_name(mon._name)}))
	_remove(mon)

# Das Start-Monster mit offenen Meilensteinen geht nur nach Rückfrage
func _may_lose(mon: Monster) -> bool:
	if not _is_guarded_starter(mon):
		return true
	return await dialog.confirm(tr("JUDGEMENT_LOSE_STARTER_TITLE"), _starter_warning(), tr("JUDGEMENT_LOSE_STARTER_CONFIRM"))

func _remove(mon: Monster) -> void:
	State.mons.erase(mon)
	State.catched_mons.erase(mon)
	_pool.erase(mon)

func _is_guarded_starter(mon: Monster) -> bool:
	return mon == State.starter and not Skills.get_locked_milestones(State.starter_name).is_empty()

func _starter_warning() -> String:
	var lines = [tr("JUDGEMENT_STARTER_WARNING").format({"mon": Helper.mon_display_name(State.starter_name)})]
	for milestone in Skills.get_locked_milestones(State.starter_name):
		lines.append(tr("JUDGEMENT_STARTER_MILESTONE_LINE").format({
			"skill": tr(milestone.skill),
			"stat": tr("MILESTONE_STAT_" + milestone.stat.to_upper()),
			"progress": mini(Skills.milestone_progress(milestone.stat), milestone.count),
			"count": milestone.count,
		}))
	return "\n".join(PackedStringArray(lines))

# ─────────────────────────
# Gefallene Monster: Wiederbelebung, sonst Letzter Wille

func _handle_fallen() -> void:
	var fallen_mons = State.fainted_own_mons.duplicate()
	State.fainted_own_mons.clear()
	for fallen in fallen_mons:
		if not await _offer_revive(fallen):
			await _last_will(fallen)

# Liefert true, wenn das Monster wiederbelebt wurde.
func _offer_revive(fallen: Monster) -> bool:
	if fallen._revived or _pool.is_empty():
		return false
	var hp_percent = roundi(REVIVE_HP_SHARE * 100)
	var catch: Monster = await dialog.revive(fallen, _pool, hp_percent)
	if catch == null:
		return false
	_remove(catch)
	State.mons.append(fallen)
	fallen.revive(REVIVE_HP_SHARE)
	_refresh()
	Helper.show_unlock_message(tr("REVIVE_DONE").format({"mon": Helper.mon_battle_name(fallen), "hp": hp_percent}))
	return true

# Erben können das Team und die neuen Fänge. Abgelehnt wird nur nach Rückfrage, das Erbe ist danach weg.
func _last_will(fallen: Monster) -> void:
	var heirs: Array = State.mons.duplicate()
	heirs.append_array(_pool)
	if not dialog.can_inherit(fallen, heirs):
		return
	while true:
		var result: Dictionary = await dialog.last_will(fallen, heirs)
		if not result.is_empty():
			_inherit(fallen, result)
			_refresh()
			return
		var text = tr("LAST_WILL_DECLINE_TEXT").format({"mon": Helper.mon_battle_name(fallen)})
		if await dialog.confirm(tr("LAST_WILL_DECLINE_TITLE"), text, tr("LAST_WILL_DECLINE")):
			return

func _inherit(fallen: Monster, result: Dictionary) -> void:
	var heir: Monster = result.target
	match result.gift.kind:
		"gems":
			for stat in fallen._gems:
				heir.add_gem(stat, fallen._gems[stat], fallen.gem_count(stat))
		"element":
			heir.gain_element(result.gift.element)
		"skill":
			var learned = Skills.learnable_copy(result.gift.skill)
			if result.replace == -1:
				heir._skills.append(learned)
			else:
				heir._skills[result.replace] = learned
	Helper.show_unlock_message(tr("LAST_WILL_INHERITED").format({"mon": Helper.mon_battle_name(heir), "gift": dialog.gift_name(result.gift)}))

# ─────────────────────────
# Anzeige

func _refresh() -> void:
	_index = clampi(_index, 0, maxi(_pool.size() - 1, 0))
	# links ist immer nur der gerade gezeigte Fang auswählbar
	if _pool.has(_selected) and _pool[_index] != _selected:
		_selected = _pool[_index]
	if not _pool.has(_selected) and not State.mons.has(_selected):
		_selected = _pool[_index] if not _pool.is_empty() else (State.mons[0] if not State.mons.is_empty() else null)
	_refresh_catch()
	_refresh_team()
	_refresh_skills()
	_refresh_radar()
	_bag.show_items(_eggs_unlocked)
	_show_bag(_selected != null and not _selected.get_unlockable_egg_skill().is_empty() and _new_mons.has(_selected))
	_confirm_button.disabled = State.mons.is_empty()
	_confirm_button.modulate.a = 0.45 if _confirm_button.disabled else 1.0
	_confirm_button.tooltip_text = tr("JUDGEMENT_REASON_LAST") if _confirm_button.disabled else ""

func _refresh_catch() -> void:
	_clear(_catch_box)
	_catch_entry = null
	var has_catch := not _pool.is_empty()
	_page_label.text = tr("JUDGEMENT_PAGE").format({"i": _index + 1 if has_catch else 0, "n": _pool.size()})
	_prev_button.disabled = _pool.size() <= 1
	_next_button.disabled = _pool.size() <= 1
	if not has_catch:
		var empty := _label(16, MUTED)
		empty.text = tr("JUDGEMENT_NO_CATCHES_LEFT")
		_outline(empty)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.custom_minimum_size.y = CATCH_PICTURE_HEIGHT
		_catch_box.add_child(empty)
		return
	_catch_entry = _mon_entry(_pool[_index], CATCH_COLOR, false)
	_catch_box.add_child(_catch_entry)

func _refresh_team() -> void:
	for slot in MAX_TEAM:
		var box: VBoxContainer = _slot_boxes[slot]
		_clear(box)
		_slot_entries[slot] = null
		if slot < State.mons.size():
			_slot_entries[slot] = _mon_entry(State.mons[slot], SLOT_COLORS[slot], true)
			box.add_child(_slot_entries[slot])
		else:
			var missing := _label(17, MUTED)
			missing.text = tr("JUDGEMENT_MISSING_MEMBER")
			missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			missing.size_flags_vertical = SIZE_EXPAND_FILL
			box.add_child(missing)

func _refresh_skills() -> void:
	_clear(_skill_grid)
	_skill_cards.clear()
	for i in Skills.MAX_SKILLS:
		if _selected and i < _selected._skills.size():
			var skill: Dictionary = _selected._skills[i]
			var card := EggSkillCard.create(skill, _selected)
			card.custom_minimum_size.y = SKILL_CARD_HEIGHT
			card.size_flags_vertical = SIZE_EXPAND_FILL
			card.set_meta("skill", skill)
			card.mouse_default_cursor_shape = CURSOR_DRAG
			if _is_unlockable_egg(_selected, skill):
				_add_egg(card)
				card.tooltip_text = tr("JUDGEMENT_EGG_CARD_HINT")
			_skill_grid.add_child(card)
			_skill_cards.append(card)
		else:
			var empty := Panel.new()
			empty.add_theme_stylebox_override("panel", INSET_BOX)
			empty.modulate.a = 0.4
			empty.custom_minimum_size.y = SKILL_CARD_HEIGHT
			empty.size_flags_horizontal = SIZE_EXPAND_FILL
			empty.size_flags_vertical = SIZE_EXPAND_FILL
			empty.mouse_filter = MOUSE_FILTER_IGNORE
			_skill_grid.add_child(empty)

func _refresh_radar() -> void:
	var entries := []
	if not _pool.is_empty():
		entries.append({"mon": _pool[_index], "color": CATCH_COLOR})
	for slot in State.mons.size():
		entries.append({"mon": State.mons[slot], "color": SLOT_COLORS[slot]})
	_radar.show_mons(entries)
	_clear(_legend)
	for entry in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = MOUSE_FILTER_IGNORE
		var dot := ColorRect.new()
		dot.color = entry.color
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = SIZE_SHRINK_CENTER
		dot.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(dot)
		var name_label := _label(13, MUTED)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.text = Helper.mon_battle_name(entry.mon)
		row.add_child(name_label)
		_legend.add_child(row)

# Tasche fliegt von unten herein bzw. wieder hinaus
func _show_bag(wanted: bool) -> void:
	if wanted == _bag_shown:
		return
	_bag_shown = wanted
	if _bag_tween:
		_bag_tween.kill()
	_bag_tween = create_tween()
	if wanted:
		_bag_zone.visible = true
		_bag_tween.tween_property(_bag_zone, "position:y", 0.0, BAG_FLY_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_bag_tween.tween_property(_bag_zone, "position:y", BAG_HIDDEN_OFFSET, BAG_FLY_TIME * 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		_bag_tween.tween_callback(_bag_zone.hide)

# Monster wie auf einer Karte: oben Name und Stufe, darunter Kennzeichnungen und Seltenheit, groß das Bild mit dem
# Element unten rechts darüber, unten die Werte in einem Rahmen in der Farbe des Monsters im Netzdiagramm.
# fill: das Bild nimmt sich den übrigen Platz (Team), sonst feste Höhe (links)
func _mon_entry(mon: Monster, color: Color, fill: bool) -> VBoxContainer:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 5)
	entry.mouse_filter = MOUSE_FILTER_IGNORE
	entry.size_flags_vertical = SIZE_EXPAND_FILL if fill else SIZE_FILL
	var header := HBoxContainer.new()
	header.mouse_filter = MOUSE_FILTER_IGNORE
	entry.add_child(header)
	var name_label := _label(20, Helper.color_by_mon(mon))
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.text = Helper.mon_battle_name(mon)
	_outline(name_label)
	header.add_child(name_label)
	var level := _label(20, MUTED)
	level.autowrap_mode = TextServer.AUTOWRAP_OFF
	level.text = tr("BATTLE_MON_LEVEL") + " " + str(mon._level)
	_outline(level)
	header.add_child(level)

	# zu viele Kennzeichnungen brechen in eine zweite Zeile um
	var badges := HFlowContainer.new()
	badges.add_theme_constant_override("h_separation", 6)
	badges.add_theme_constant_override("v_separation", 4)
	badges.mouse_filter = MOUSE_FILTER_IGNORE
	entry.add_child(badges)
	var tag := _tag(mon)
	if tag:
		badges.add_child(tag)
	badges.add_child(_rarity_badge(mon))
	if _new_mons.has(mon) and not mon.get_unlockable_egg_skill().is_empty():
		badges.add_child(_egg_badge(mon))

	# Bild mit dem Element-Chip unten rechts darüber (kein Container: der Chip darf ins Bild ragen)
	var picture_area := Control.new()
	picture_area.mouse_filter = MOUSE_FILTER_IGNORE
	picture_area.custom_minimum_size.y = TEAM_PICTURE_MIN_HEIGHT if fill else CATCH_PICTURE_HEIGHT
	picture_area.size_flags_vertical = SIZE_EXPAND_FILL if fill else SIZE_FILL
	entry.add_child(picture_area)
	var picture := TextureRect.new()
	Monmap.show_on(picture, mon._name, Monmap.ICON)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = MOUSE_FILTER_IGNORE
	picture_area.add_child(picture)
	picture.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var chip: Control = ELEMENT_CHIP.instantiate()
	chip.mouse_filter = MOUSE_FILTER_PASS
	picture_area.add_child(chip)
	chip.set_element(mon._type)
	chip.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT, PRESET_MODE_MINSIZE)
	chip.grow_horizontal = GROW_DIRECTION_BEGIN
	chip.grow_vertical = GROW_DIRECTION_BEGIN

	entry.add_child(_stats_box(mon, color))
	return entry

# Kennzeichnung oben links: Start-Monster, neu gefangen oder aus dem Team abgelegt
func _tag(mon: Monster) -> Control:
	if mon == State.starter:
		return _badge(tr("JUDGEMENT_BADGE_STARTER"), Color(0.3, 0.3, 0.3), MUTED)
	if _new_mons.has(mon):
		return _badge(tr("JUDGEMENT_BADGE_NEW"), GOLD, Color.BLACK)
	if not State.mons.has(mon):
		return _badge(tr("JUDGEMENT_BADGE_BENCHED"), Color(0.3, 0.3, 0.3), MUTED)
	return null

func _rarity_badge(mon: Monster) -> Control:
	var rarity := Monmap.rarity_of(mon._name)
	var badge := _badge(tr(Monmap.RARITY_LABELS[rarity]), Color(0.0934, 0.0873, 0.0837), Monmap.RARITY_COLORS[rarity])
	var star := TextureRect.new()
	star.texture = RARITY_STAR
	star.material = LIVING_MATERIAL
	star.self_modulate = Monmap.RARITY_COLORS[rarity]
	star.custom_minimum_size = Vector2(14, 14)
	star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	star.size_flags_vertical = SIZE_SHRINK_CENTER
	star.mouse_filter = MOUSE_FILTER_IGNORE
	var row: HBoxContainer = badge.get_meta("row")
	row.add_child(star)
	row.move_child(star, 0)
	return badge

# Neuer Fang mit Ei-Attacke, die sich jetzt in der Tasche freischalten lässt
func _egg_badge(mon: Monster) -> Control:
	var badge := _badge(tr("JUDGEMENT_BADGE_EGG"), Color(0.15, 0.13, 0.1), GOLD)
	badge.tooltip_text = tr("JUDGEMENT_EGG_CARD_HINT")
	var egg := TextureRect.new()
	egg.texture = EGG_ICON
	egg.material = Monmap.egg_material(Monmap.rarity_of(mon._name))
	egg.custom_minimum_size = Vector2(14, 17)
	egg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	egg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	egg.size_flags_vertical = SIZE_SHRINK_CENTER
	egg.mouse_filter = MOUSE_FILTER_IGNORE
	var row: HBoxContainer = badge.get_meta("row")
	row.add_child(egg)
	row.move_child(egg, 0)
	return badge

func _badge(text: String, background: Color, color: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	# PASS: Ablegen auf den Team-Platz darunter klappt weiter
	badge.mouse_filter = MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	IronPlate.frame(badge, row, 8, 3).tint(background)
	var label := _label(14, color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text = text
	row.add_child(label)
	badge.set_meta("row", row)
	return badge

# Werte in einem Rahmen in der Farbe des Monsters im Netzdiagramm: eine Zeile, wenn Platz ist, sonst zwei
func _stats_box(mon: Monster, color: Color) -> PanelContainer:
	var box := PanelContainer.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.065, 0.06, 0.85)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	box.add_theme_stylebox_override("panel", style)
	var grid := GridContainer.new()
	grid.columns = STAT_KEYS.size()
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 3)
	grid.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(grid)
	var values := {"hp": mon.hp(), "atk": mon.attack(), "def": mon.defense(), "s_atk": mon.s_attack(), "s_def": mon.s_defense(), "speed": mon.speed()}
	for key in STAT_KEYS:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		cell.size_flags_horizontal = SIZE_EXPAND_FILL
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.mouse_filter = MOUSE_FILTER_PASS
		cell.tooltip_text = tr(STAT_LABELS[key]).trim_suffix(":")
		cell.add_child(StatsGrid.stat_icon(key, 16))
		var value := _label(14, MUTED)
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		value.text = str(int(values[key]))
		cell.add_child(value)
		grid.add_child(cell)
	box.resized.connect(func():
		var width := box.size.x - style.content_margin_left - style.content_margin_right
		grid.columns = STAT_KEYS.size() if width >= STAT_KEYS.size() * STAT_CELL_WIDTH else 3)
	return box

# Ei hinter der Karte oben rechts: diese Ei-Attacke lässt sich jetzt in der Tasche freischalten
func _add_egg(card: Control) -> void:
	# die Karte ist ein Container und würde das Ei auf ihre Größe ziehen: daher ein Halter über die ganze Karte
	var holder := Control.new()
	holder.show_behind_parent = true
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(holder)
	var egg := TextureRect.new()
	egg.texture = EGG_ICON
	egg.material = Monmap.egg_material(Monmap.rarity_of(_selected._name))
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

func _drag_preview(data: Dictionary) -> Control:
	var holder := Control.new()
	if data.has("judgement_mon"):
		var picture := TextureRect.new()
		Monmap.show_on(picture, data.judgement_mon._name, Monmap.ICON)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.size = Vector2(120, 120)
		picture.position = -picture.size / 2
		picture.modulate.a = 0.85
		holder.add_child(picture)
	else:
		var card := EggSkillCard.create(data.judgement_skill, data.owner)
		card.custom_minimum_size = Vector2(170, SKILL_CARD_HEIGHT)
		card.size = card.custom_minimum_size
		card.position = -card.size / 2
		card.modulate.a = 0.9
		holder.add_child(card)
	return holder

# Pfeil zwischen der Mitte und dem ausgewählten Monster, die Spitze zeigt auf das Monster und wippt leicht
func _draw_arrow() -> void:
	if _selected == null:
		return
	var entry: Control = null
	# dir: -1 = Pfeil rechts vom Fang, zeigt nach links; 1 = Pfeil links vom Team, zeigt nach rechts
	var dir := 1.0
	var edge := _team_frame.get_global_rect().position.x
	if _catch_entry and _pool[_index] == _selected:
		entry = _catch_entry
		dir = -1.0
		edge = _left_zone.get_global_rect().end.x
	else:
		for slot in MAX_TEAM:
			if _slot_entries[slot] and State.mons[slot] == _selected:
				entry = _slot_entries[slot]
	if entry == null:
		return
	var bob := (1.0 + sin(_arrow_time * 5.0)) * ARROW_BOB / 2
	var tip := Vector2(edge - dir * (4 + bob), entry.get_global_rect().get_center().y) - _arrow.get_global_rect().position
	var s := ARROW_SIZE
	var shape := [Vector2(0, 0), Vector2(s * 0.6, -s * 0.5), Vector2(s * 0.6, -s * 0.22),
		Vector2(s * 1.2, -s * 0.22), Vector2(s * 1.2, s * 0.22), Vector2(s * 0.6, s * 0.22), Vector2(s * 0.6, s * 0.5)]
	var points := PackedVector2Array()
	for point in shape:
		points.append(tip + Vector2(-dir * point.x, point.y))
	_arrow.draw_colored_polygon(points, ARROW_COLOR)
	var outline := points.duplicate()
	outline.append(points[0])
	_arrow.draw_polyline(outline, Color.BLACK, 3.0, true)

# ─────────────────────────
# Aufbau

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	move_child(margin, dialog.get_index())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", COLUMN_GAP)
	columns.mouse_filter = MOUSE_FILTER_IGNORE
	margin.add_child(columns)
	columns.add_child(_build_left())
	columns.add_child(_build_middle())
	columns.add_child(_build_team())
	# Pfeil über allem außer dem Dialog
	_arrow = Control.new()
	_arrow.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_arrow.mouse_filter = MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)
	move_child(_arrow, dialog.get_index())

# Links: Blättern und der aktuelle Fang, darunter das Netzdiagramm in einer eigenen Platte.
# Die ganze Spalte ist die Ablage für Teammitglieder.
func _build_left() -> Control:
	var zone := _make_zone(Zone.BENCH)
	zone.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	zone.size_flags_horizontal = SIZE_EXPAND_FILL
	zone.custom_minimum_size.x = 280
	zone.add_to_group("tut_jud_catches")
	_left_zone = zone
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = MOUSE_FILTER_IGNORE
	zone.add_child(box)
	_zone_frames[Zone.BENCH] = _drop_frame(zone)
	var nav := HBoxContainer.new()
	nav.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(nav)
	_prev_button = _nav_button("<", -1)
	nav.add_child(_prev_button)
	var page_panel := PanelContainer.new()
	page_panel.mouse_filter = MOUSE_FILTER_IGNORE
	page_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	_page_label = _label(20, GOLD)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	IronPlate.frame(page_panel, _page_label, 10, 4)
	nav.add_child(page_panel)
	_next_button = _nav_button(">", 1)
	nav.add_child(_next_button)
	_catch_box = VBoxContainer.new()
	_catch_box.add_theme_constant_override("separation", 4)
	_catch_box.mouse_filter = MOUSE_FILTER_IGNORE
	# eigene Platte nur für den Fang (PASS: Ablegen auf die Spalte darunter klappt weiter)
	var catch_panel := PanelContainer.new()
	catch_panel.mouse_filter = MOUSE_FILTER_PASS
	IronPlate.frame(catch_panel, _catch_box, 10, 8)
	box.add_child(catch_panel)
	var radar_panel := PanelContainer.new()
	radar_panel.mouse_filter = MOUSE_FILTER_PASS
	radar_panel.size_flags_vertical = SIZE_EXPAND_FILL
	var radar_box := VBoxContainer.new()
	radar_box.add_theme_constant_override("separation", 4)
	radar_box.mouse_filter = MOUSE_FILTER_IGNORE
	IronPlate.frame(radar_panel, radar_box, 10, 8)
	box.add_child(radar_panel)
	var heading := _label(17, GOLD)
	heading.text = tr("JUDGEMENT_GROWTH")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	radar_box.add_child(heading)
	_radar = GrowthRadar.new()
	_radar.size_flags_vertical = SIZE_EXPAND_FILL
	_radar.custom_minimum_size.y = 150
	radar_box.add_child(_radar)
	_legend = HFlowContainer.new()
	_legend.alignment = FlowContainer.ALIGNMENT_CENTER
	_legend.add_theme_constant_override("h_separation", 12)
	_legend.mouse_filter = MOUSE_FILTER_IGNORE
	radar_box.add_child(_legend)
	return zone

# Mitte: Fähigkeiten des ausgewählten Monsters, unten rechts fliegt bei Ei-Attacken die Tasche herein
func _build_middle() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	# Luft nach oben: das Ei an den Karten ragt über den Rand
	var top_space := Control.new()
	top_space.custom_minimum_size.y = 14
	top_space.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(top_space)
	box.size_flags_stretch_ratio = 2.1
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = MOUSE_FILTER_IGNORE
	_skill_grid = GridContainer.new()
	_skill_grid.columns = 3
	_skill_grid.size_flags_vertical = SIZE_EXPAND_FILL
	_skill_grid.add_theme_constant_override("h_separation", 14)
	_skill_grid.add_theme_constant_override("v_separation", 18)
	_skill_grid.mouse_filter = MOUSE_FILTER_IGNORE
	_skill_grid.add_to_group("tut_jud_skills")
	box.add_child(_skill_grid)
	# fester Platz unten, die Tasche selbst ist frei beweglich darin
	var bag_row := Control.new()
	bag_row.custom_minimum_size.y = BAG_SIZE.y
	bag_row.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(bag_row)
	var bag_slot := Control.new()
	bag_slot.mouse_filter = MOUSE_FILTER_IGNORE
	bag_row.add_child(bag_slot)
	bag_slot.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	bag_slot.offset_left = -BAG_SIZE.x
	bag_slot.offset_top = -BAG_SIZE.y
	bag_slot.offset_right = 0
	bag_slot.offset_bottom = 0
	_bag_zone = _make_zone(Zone.BAG)
	_bag_zone.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_bag_zone.size = BAG_SIZE
	_bag_zone.position.y = BAG_HIDDEN_OFFSET
	_bag_zone.visible = false
	_bag_zone.add_to_group("tut_jud_bag")
	_bag = OpenBag.new(BAG_SIZE, EGG_ICON, BAG_ITEM_SIZE, 16)
	_bag_zone.add_child(_bag)
	bag_slot.add_child(_bag_zone)
	return box

# Rechts: Team-Rahmen mit der Überschrift oben und dem Weiter-Button unten, beide mittig über dem Rand
func _build_team() -> Control:
	_team_frame = Control.new()
	_team_frame.size_flags_horizontal = SIZE_EXPAND_FILL
	_team_frame.custom_minimum_size.x = 280
	_team_frame.mouse_filter = MOUSE_FILTER_IGNORE
	_team_frame.add_to_group("tut_jud_team")
	var border := IronPlate.new()
	border.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	border.offset_top = 16
	border.offset_bottom = -26
	_team_frame.add_child(border)
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	content.offset_left = 14
	content.offset_right = -14
	content.offset_top = 46
	content.offset_bottom = -60
	content.add_theme_constant_override("separation", 22)
	content.mouse_filter = MOUSE_FILTER_IGNORE
	_team_frame.add_child(content)
	for slot in MAX_TEAM:
		var zone := _make_zone(Zone.SLOT_1 + slot)
		zone.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		zone.size_flags_vertical = SIZE_EXPAND_FILL
		var box := VBoxContainer.new()
		box.mouse_filter = MOUSE_FILTER_IGNORE
		zone.add_child(box)
		_zone_frames[Zone.SLOT_1 + slot] = _drop_frame(zone)
		content.add_child(zone)
		_slot_boxes.append(box)
	var legend := PanelContainer.new()
	legend.mouse_filter = MOUSE_FILTER_IGNORE
	var title := _label(20, GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text = tr("JUDGEMENT_TEAM")
	IronPlate.frame(legend, title, 22, 5).set_rim(GOLD)
	_team_frame.add_child(legend)
	legend.set_anchors_and_offsets_preset(PRESET_CENTER_TOP, PRESET_MODE_MINSIZE)
	legend.grow_horizontal = GROW_DIRECTION_BOTH
	_confirm_button = RewardDialog.plate_button("JUDGEMENT_CONTINUE")
	_confirm_button.custom_minimum_size = Vector2(190, 52)
	_confirm_button.add_theme_color_override("font_color", GOLD)
	_confirm_button.add_theme_color_override("font_hover_color", Color(1, 0.9, 0.65))
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_confirm_button.add_to_group("tut_jud_confirm")
	_team_frame.add_child(_confirm_button)
	_confirm_button.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM, PRESET_MODE_MINSIZE)
	_confirm_button.grow_horizontal = GROW_DIRECTION_BOTH
	_confirm_button.grow_vertical = GROW_DIRECTION_BEGIN
	return _team_frame

func _make_zone(zone: int) -> JudgementDropZone:
	var drop_zone := JudgementDropZone.new()
	drop_zone.check = func(data): return _reason(zone, data)
	drop_zone.dropped.connect(_on_dropped.bind(zone))
	_zones[zone] = drop_zone
	return drop_zone

# Goldener Rahmen über einer Ablage, nur beim Ziehen sichtbar (die Ablage ist ein PanelContainer, er füllt sie)
func _drop_frame(zone: Control) -> Panel:
	var frame := Panel.new()
	frame.visible = false
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(DROP_FRAME_WIDTH)
	style.set_corner_radius_all(4)
	style.border_color = GOLD
	style.expand_margin_left = 6
	style.expand_margin_right = 6
	style.expand_margin_top = 6
	style.expand_margin_bottom = 6
	frame.add_theme_stylebox_override("panel", style)
	zone.add_child(frame)
	return frame

func _nav_button(text: String, direction: int) -> Button:
	var button := RewardDialog.plate_button(text)
	button.custom_minimum_size = Vector2(48, 36)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(_step.bind(direction))
	return button

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = MOUSE_FILTER_IGNORE
	return label

# Dunkle Kontur: Texte ohne Platte bleiben auf dem hellen Hintergrund lesbar
func _outline(label: Label) -> void:
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.04))
	label.add_theme_constant_override("outline_size", 6)
