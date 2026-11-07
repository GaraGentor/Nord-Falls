extends Control

## Nach dem Kampf: Links rotieren die neuen Fänge durch ein Karussell, rechts steht das aktuelle Team.
## Monster werden per Drag & Drop (oder Klick auf das Monster, dann Klick auf das Ziel) auf einen Team-Platz
## oder eine Ablage (Lehren, Opfern, Freilassen) gelegt. Die Teamaufstellung bleibt bis zum Bestätigen frei
## änderbar, Lehren, Opfern und Freilassen gelten sofort. Was beim Bestätigen noch im Karussell liegt, wird freigelassen.
## Ist im Kampf ein eigenes Monster gefallen, kann es zuerst einmalig durch einen neuen Fang wiederbelebt werden.
## Wird das übersprungen oder ist es nicht möglich, vererbt es eine Sache (Letzter Wille). Ohne übrige Fänge geht es danach direkt zur Karte.

const GOLD := SkillDetailPopup.GOLD
const MUTED := IronPlate.TEXT_COLOR
const EGG_ICON = preload("res://assets/ui/eggs/common_1.png")
const SKILL_LABEL_SCRIPT = preload("res://script/scenes/battle/monster_widget_skill_label.gd")
const MAX_TEAM := 2
const DRAG_THRESHOLD := 10.0
# Anteil der KP, mit dem ein wiederbelebtes Monster zurückkommt
const REVIVE_HP_SHARE := 0.3
# Anzeigenamen der Meilenstein-Zähler (siehe Skills.MILESTONES)
const MILESTONE_STAT_LABELS = {
	"biome_boss_kills": "MILESTONE_STAT_BIOME_BOSS_KILLS",
	"game_wins": "MILESTONE_STAT_GAME_WINS",
}

enum Zone { SLOT_1, SLOT_2, TEACH, SACRIFICE, RELEASE }
const ZONE_TITLES = {
	Zone.TEACH: "JUDGEMENT_ZONE_TEACH",
	Zone.SACRIFICE: "JUDGEMENT_ZONE_SACRIFICE",
	Zone.RELEASE: "JUDGEMENT_ZONE_RELEASE",
}

@export var mw1: Control
@export var mw2: Control
@export var mw3: Control
@export var catch_header: Label
@export var catch_badges: HBoxContainer
@export var catch_area: Control
@export var catch_empty: Label
@export var prev_button: Button
@export var next_button: Button
@export var dots: HBoxContainer
@export var slot_area_1: Control
@export var slot_area_2: Control
@export var slot_badges_1: HBoxContainer
@export var slot_badges_2: HBoxContainer
@export var slot_empty_1: Label
@export var slot_empty_2: Label
@export var hint_label: Label
@export var zone_row: HBoxContainer
@export var confirm_button: Button
@export var confirm_info: Label
@export var dialog: JudgementDialog

# Monster im Karussell: neue Fänge und aus dem Team getauschte Monster
var _pool: Array = []
# Fänge dieses Kampfes (nur die dürfen geopfert werden)
var _new_mons: Array = []
var _initial_team: Array = []
var _index := 0
# Ausgewähltes bzw. gerade gezogenes Monster
var _held: Monster = null
var _dragging := false
# Mausdruck auf einer Karte, aus dem ein Klick oder ein Drag wird
var _press := {}
var _zones := {}
var _zone_desc := {}
# Ablage -> ihre Eisenplatte (die Ablagen über den Team-Karten haben keine)
var _zone_plates := {}
# Kartenbereich -> goldener Auswahlrahmen
var _frames := {}

func _ready() -> void:
	_pool = State.catched_mons.duplicate()
	_new_mons = _pool.duplicate()
	_initial_team = State.mons.duplicate()
	if _pool.is_empty() and State.fainted_own_mons.is_empty():
		get_tree().change_scene_to_file.call_deferred("res://script/scenes/world_map/world_map.tscn")
		return
	# Die Karten sind hier flacher als im Kampf: dem Werte-Bereich mehr Höhe geben, die Attacken-Liste scrollt
	for widget in [mw1, mw2, mw3]:
		widget.get_node("MarginContainer/VBoxContainer/Panel").size_flags_stretch_ratio = 1.5
	# das aktuelle Team ist golden umrandet
	for plate: IronPlate in [$Margin/VBox/Top/TeamFrame/Border, $Margin/VBox/Top/TeamFrame/Legend/Plate]:
		plate.set_rim(GOLD)
	for zone in ZONE_TITLES:
		_zones[zone] = _make_zone(zone)
	for slot in MAX_TEAM:
		_zones[Zone.SLOT_1 + slot] = _make_slot_overlay(slot)
	for area in _card_areas():
		_frames[area] = _make_frame(area)
	_refresh()
	await _handle_fallen()
	if _pool.is_empty():
		get_tree().change_scene_to_file.call_deferred("res://script/scenes/world_map/world_map.tscn")
		return
	# Wiederbelebte gehören schon zur jetzigen Aufstellung
	_initial_team = State.mons.duplicate()
	_refresh()

func _process(_delta: float) -> void:
	if not _dragging:
		return
	for zone in _zones:
		_set_zone_glow(zone, Color(1.4, 1.4, 1.4) if _zones[zone].is_drag_hovered() else Color.WHITE)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _dragging:
		_dragging = false
		for zone in _zones:
			_set_zone_glow(zone, Color.WHITE)
		_set_held(null)

func _set_zone_glow(zone: int, color: Color) -> void:
	_zones[zone].self_modulate = color
	if _zone_plates.has(zone):
		_zone_plates[zone].modulate = color

# ─────────────────────────
# Eingabe

func _input(event: InputEvent) -> void:
	if dialog.visible:
		return
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_press = {}
			# Skill-Namen und das Detail-Popup öffnen bzw. schließen nur die Skill-Details
			if _is_skill_click():
				return
			var mon = _card_at(button.position)
			# Mit gehaltenem Monster sind die Team-Karten Ablageflächen, das übernimmt die Ablage selbst
			if mon == null or (_held != null and _slot_overlay_at(button.position)):
				return
			_press = {"mon": mon, "pos": button.position}
		elif not _press.is_empty():
			var mon: Monster = _press.mon
			_press = {}
			_set_held(null if _held == mon else mon)
		return
	var motion := event as InputEventMouseMotion
	if motion and not _press.is_empty() and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if motion.position.distance_to(_press.pos) > DRAG_THRESHOLD:
			var mon: Monster = _press.mon
			_press = {}
			_set_held(mon)
			_dragging = true
			force_drag({"judgement_mon": mon}, _drag_preview(mon))

func _is_skill_click() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	while hovered:
		if hovered is SkillDetailPopup or hovered.get_script() == SKILL_LABEL_SCRIPT:
			return true
		hovered = hovered.get_parent() as Control
	return false

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or dialog.visible or _zones.is_empty():
		return
	match key.keycode:
		KEY_ESCAPE:
			_set_held(null)
		KEY_LEFT, KEY_A:
			_step(-1)
		KEY_RIGHT, KEY_D:
			_step(1)
		KEY_ENTER, KEY_KP_ENTER:
			_on_confirm_pressed()
		_:
			return
	get_viewport().set_input_as_handled()

func _step(direction: int) -> void:
	if _pool.size() <= 1:
		return
	_index = posmod(_index + direction, _pool.size())
	if _pool.has(_held):
		_set_held(null)
	_refresh_catch()
	# kleine Slide-Animation in Blätterrichtung
	mw1.position.x = 40 * direction
	mw1.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(mw1, "position:x", 0.0, 0.15)
	tween.tween_property(mw1, "modulate:a", 1.0, 0.15)

func _on_zone_dropped(data: Dictionary, zone: int) -> void:
	_apply(zone, data.judgement_mon)

func _on_zone_clicked(zone: int) -> void:
	if _held != null and _reason(zone, _held) == "":
		_apply(zone, _held)

func _on_confirm_pressed() -> void:
	if dialog.visible:
		return
	var starter = _pool.filter(_is_guarded_starter)
	if not starter.is_empty():
		var ok = await dialog.confirm(tr("JUDGEMENT_RELEASE_STARTER_TITLE"), _starter_warning(), tr("JUDGEMENT_RELEASE_CONFIRM"))
		if not ok:
			return
	# Neu ins Team aufgenommene Fänge starten mit vollen HP
	for mon in State.mons:
		if _new_mons.has(mon):
			mon._lost_hp = 0
	State.catched_mons.clear()
	get_tree().change_scene_to_file("res://script/scenes/world_map/world_map.tscn")

# ─────────────────────────
# Regeln & Aktionen

# "" wenn das Monster auf die Ablage darf, "-" wenn die Ablage hier keinen Sinn ergibt, sonst der Grund dagegen
func _reason(zone: int, mon: Monster) -> String:
	var in_team = State.mons.has(mon)
	var last = in_team and State.mons.size() <= 1
	var vars = {"mon": Helper.mon_battle_name(mon)}
	match zone:
		Zone.SLOT_1, Zone.SLOT_2:
			var slot = zone - Zone.SLOT_1
			if in_team and (slot >= State.mons.size() or State.mons[slot] == mon):
				return "-"
		Zone.TEACH:
			if last:
				return tr("JUDGEMENT_REASON_LAST")
			var targets = _teach_targets(mon)
			if not mon._skills.any(func(skill): return targets.any(func(member): return not Skills.knows_skill(member, skill.name))):
				return tr("JUDGEMENT_REASON_NOTHING_TO_TEACH").format(vars)
		Zone.SACRIFICE:
			if not _new_mons.has(mon):
				return tr("JUDGEMENT_REASON_OWN")
			if mon.get_unlockable_egg_skill().is_empty():
				return tr("JUDGEMENT_REASON_NO_EGG").format(vars)
			if last:
				return tr("JUDGEMENT_REASON_LAST")
		Zone.RELEASE:
			if last:
				return tr("JUDGEMENT_REASON_LAST")
	return ""

func _apply(zone: int, mon: Monster) -> void:
	_set_held(null)
	match zone:
		Zone.SLOT_1, Zone.SLOT_2:
			_place(mon, zone - Zone.SLOT_1)
		Zone.TEACH:
			await _teach(mon)
		Zone.SACRIFICE:
			_sacrifice(mon)
		Zone.RELEASE:
			await _release(mon)
	_refresh()

# Neuer Fang auf einen Team-Platz: tauscht mit dem bisherigen Monster, das dann im Karussell liegt.
# Team-Monster auf den anderen Platz: Plätze tauschen.
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

func _teach(teacher: Monster) -> void:
	var warning = _starter_warning() if _is_guarded_starter(teacher) else ""
	var result = await dialog.teach(teacher, _teach_targets(teacher), warning)
	if result.is_empty():
		return
	_learn(result.target, result.skill, result.replace)
	_remove(teacher)
	Helper.show_unlock_message(tr("JUDGEMENT_LEARNED").format({"mon": Helper.mon_battle_name(result.target), "skill": tr(result.skill.name)}))

func _learn(target: Monster, skill: Dictionary, replace: int) -> void:
	var learned = Skills.learnable_copy(skill)
	if replace == -1:
		target._skills.append(learned)
	else:
		target._skills[replace] = learned

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
			_learn(heir, result.gift.skill, result.replace)
	Helper.show_unlock_message(tr("LAST_WILL_INHERITED").format({"mon": Helper.mon_battle_name(heir), "gift": dialog.gift_name(result.gift)}))

func _sacrifice(mon: Monster) -> void:
	var egg_skill = mon.get_unlockable_egg_skill()
	SaveManager.unlock_egg_skill(mon._name, egg_skill.name)
	Helper.show_unlock_message(tr("EGG_SKILL_UNLOCKED").format({"skill": tr(egg_skill.name), "mon": Helper.mon_display_name(mon._name)}))
	_remove(mon)

func _release(mon: Monster) -> void:
	if _is_guarded_starter(mon):
		var ok = await dialog.confirm(tr("JUDGEMENT_RELEASE_STARTER_TITLE"), _starter_warning(), tr("JUDGEMENT_RELEASE_CONFIRM"))
		if not ok:
			return
	_remove(mon)

func _remove(mon: Monster) -> void:
	State.mons.erase(mon)
	State.catched_mons.erase(mon)
	_pool.erase(mon)

func _teach_targets(teacher: Monster) -> Array:
	return State.mons.filter(func(member): return member != teacher)

func _is_guarded_starter(mon: Monster) -> bool:
	return mon == State.starter and not Skills.get_locked_milestones(State.starter_name).is_empty()

func _starter_warning() -> String:
	var lines = [tr("JUDGEMENT_STARTER_WARNING").format({"mon": Helper.mon_display_name(State.starter_name)})]
	for milestone in Skills.get_locked_milestones(State.starter_name):
		lines.append(tr("JUDGEMENT_STARTER_MILESTONE_LINE").format({
			"skill": tr(milestone.skill),
			"stat": tr(MILESTONE_STAT_LABELS.get(milestone.stat, milestone.stat)),
			"progress": SaveManager.get_milestone_progress(State.starter_name, milestone.stat),
			"count": milestone.count,
		}))
	return "\n".join(PackedStringArray(lines))

# ─────────────────────────
# Anzeige

func _refresh() -> void:
	_refresh_catch()
	_refresh_team()
	_refresh_zones()
	_refresh_confirm()

func _refresh_catch() -> void:
	var has_catch = not _pool.is_empty()
	_index = clampi(_index, 0, maxi(_pool.size() - 1, 0))
	mw1.visible = has_catch
	catch_empty.visible = not has_catch
	catch_header.text = tr("JUDGEMENT_NEW_CATCHES").format({"i": _index + 1 if has_catch else 0, "n": _pool.size()})
	prev_button.disabled = _pool.size() <= 1
	next_button.disabled = _pool.size() <= 1
	for child in dots.get_children():
		child.queue_free()
	for i in _pool.size():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = SIZE_SHRINK_CENTER
		var style := StyleBoxFlat.new()
		style.bg_color = GOLD if i == _index else Color(0.5, 0.5, 0.5)
		dot.add_theme_stylebox_override("panel", style)
		dots.add_child(dot)
	_fill_badges(catch_badges, _pool[_index] if has_catch else null)
	if has_catch:
		mw1.monster = _pool[_index]
	_refresh_frames()

func _refresh_team() -> void:
	var widgets = [mw2, mw3]
	var badges = [slot_badges_1, slot_badges_2]
	var empties = [slot_empty_1, slot_empty_2]
	for slot in MAX_TEAM:
		var has_mon = slot < State.mons.size()
		widgets[slot].visible = has_mon
		empties[slot].visible = not has_mon
		_fill_badges(badges[slot], State.mons[slot] if has_mon else null, slot)
		if has_mon:
			widgets[slot].monster = State.mons[slot]

func _refresh_zones() -> void:
	for zone in _zones:
		var reason = "-" if _held == null else _reason(zone, _held)
		var drop_zone: JudgementDropZone = _zones[zone]
		if zone in [Zone.SLOT_1, Zone.SLOT_2]:
			drop_zone.visible = _held != null and reason == ""
			if drop_zone.visible:
				drop_zone.get_meta("label").text = _slot_text(zone - Zone.SLOT_1, _held)
			continue
		var desc: Label = _zone_desc[zone]
		var vars = {"mon": Helper.mon_battle_name(_held) if _held else ""}
		if _held == null:
			desc.text = tr(ZONE_TITLES[zone] + "_IDLE")
		elif reason != "":
			desc.text = reason
		elif zone == Zone.SACRIFICE:
			desc.text = tr("JUDGEMENT_ZONE_SACRIFICE_EFFECT").format({"mon": vars.mon, "skill": tr(_held.get_unlockable_egg_skill().name)})
		else:
			desc.text = tr(ZONE_TITLES[zone] + "_EFFECT").format(vars)
		var allowed = _held != null and reason == ""
		_zone_plates[zone].set_rim(GOLD if allowed else IronPlate.RIM)
		drop_zone.modulate.a = 0.45 if _held != null and not allowed else 1.0
	hint_label.text = tr("JUDGEMENT_HINT_IDLE") if _held == null else tr("JUDGEMENT_HINT_HELD").format({"mon": Helper.mon_battle_name(_held)})
	hint_label.add_theme_color_override("font_color", MUTED if _held == null else GOLD)
	_refresh_frames()

func _refresh_confirm() -> void:
	var changed = State.mons != _initial_team
	confirm_button.text = tr("JUDGEMENT_CONFIRM_CHANGED" if changed else "JUDGEMENT_CONFIRM_KEEP")
	if _pool.is_empty():
		confirm_info.text = tr("JUDGEMENT_CONFIRM_NOTHING_LEFT")
	else:
		var names = _pool.map(func(mon): return Helper.mon_battle_name(mon))
		confirm_info.text = tr("JUDGEMENT_CONFIRM_RELEASES").format({"mons": ", ".join(PackedStringArray(names))})

func _refresh_frames() -> void:
	for area in _frames:
		_frames[area].visible = _held != null and _card_mon(area) == _held

func _set_held(mon: Monster) -> void:
	_held = mon
	_refresh_zones()

func _slot_text(slot: int, mon: Monster) -> String:
	var vars = {"mon": Helper.mon_battle_name(mon)}
	if State.mons.has(mon):
		return tr("JUDGEMENT_DROP_REORDER")
	if slot < State.mons.size():
		vars.old = Helper.mon_battle_name(State.mons[slot])
		return tr("JUDGEMENT_DROP_SWAP").format(vars)
	return tr("JUDGEMENT_DROP_FILL").format(vars)

# Kennzeichnungen über der Karte: Team-Platz, neu, Ei-Attacke, Start-Monster, aus dem Team getauscht
func _fill_badges(row: HBoxContainer, mon: Monster, slot: int = -1) -> void:
	for child in row.get_children():
		child.queue_free()
	if slot != -1:
		row.add_child(_badge(tr("JUDGEMENT_BADGE_SLOT").format({"slot": slot + 1}), Color(0.0934, 0.0873, 0.0837), GOLD))
	if mon == null:
		return
	if _new_mons.has(mon):
		row.add_child(_badge(tr("JUDGEMENT_BADGE_NEW"), GOLD, Color.BLACK))
		var egg_skill = mon.get_unlockable_egg_skill()
		if not egg_skill.is_empty():
			var egg = _badge(tr(egg_skill.name), Color(0.15, 0.13, 0.1), GOLD, EGG_ICON, Monmap.egg_material(Monmap.rarity_of(mon._name)))
			egg.tooltip_text = tr("EGG_SKILL_HINT")
			row.add_child(egg)
	elif not State.mons.has(mon):
		row.add_child(_badge(tr("JUDGEMENT_BADGE_BENCHED"), Color(0.3, 0.3, 0.3), IronPlate.TEXT_COLOR))
	if mon == State.starter:
		row.add_child(_badge(tr("JUDGEMENT_BADGE_STARTER"), Color(0.3, 0.3, 0.3), IronPlate.TEXT_COLOR))

# ─────────────────────────
# Aufbau

func _card_areas() -> Array:
	return [catch_area, slot_area_1, slot_area_2]

func _card_mon(area: Control) -> Monster:
	if area == catch_area:
		return _pool[_index] if not _pool.is_empty() else null
	var slot = 0 if area == slot_area_1 else 1
	return State.mons[slot] if slot < State.mons.size() else null

func _card_at(pos: Vector2) -> Monster:
	for area in _card_areas():
		if area.get_global_rect().has_point(pos):
			return _card_mon(area)
	return null

func _slot_overlay_at(pos: Vector2) -> bool:
	for zone in [Zone.SLOT_1, Zone.SLOT_2]:
		if _zones[zone].visible and _zones[zone].get_global_rect().has_point(pos):
			return true
	return false

func _make_zone(zone: int) -> JudgementDropZone:
	var drop_zone := JudgementDropZone.new()
	drop_zone.size_flags_horizontal = SIZE_EXPAND_FILL
	_connect_zone(drop_zone, zone)
	var box := VBoxContainer.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	_zone_plates[zone] = IronPlate.frame(drop_zone, box, 12, 10)
	var title := _label(19, GOLD)
	title.text = tr(ZONE_TITLES[zone])
	box.add_child(title)
	var desc := _label(13, MUTED)
	desc.size_flags_vertical = SIZE_EXPAND_FILL
	box.add_child(desc)
	_zone_desc[zone] = desc
	zone_row.add_child(drop_zone)
	return drop_zone

# Ablage über einer Team-Karte, nur sichtbar solange ein Monster gehalten wird
func _make_slot_overlay(slot: int) -> JudgementDropZone:
	var overlay := JudgementDropZone.new()
	overlay.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.35)
	style.draw_center = true
	style.set_border_width_all(4)
	style.border_color = GOLD
	overlay.add_theme_stylebox_override("panel", style)
	_connect_zone(overlay, Zone.SLOT_1 + slot)
	var center := CenterContainer.new()
	center.mouse_filter = MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var banner := PanelContainer.new()
	banner.mouse_filter = MOUSE_FILTER_IGNORE
	center.add_child(banner)
	var label := _label(17, GOLD)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(240, 0)
	IronPlate.frame(banner, label, 12, 10).set_rim(GOLD)
	overlay.set_meta("label", label)
	var area = slot_area_1 if slot == 0 else slot_area_2
	area.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	return overlay

func _connect_zone(drop_zone: JudgementDropZone, zone: int) -> void:
	drop_zone.check = func(data): return _reason(zone, data.judgement_mon)
	drop_zone.dropped.connect(_on_zone_dropped.bind(zone))
	drop_zone.clicked.connect(_on_zone_clicked.bind(zone))

func _make_frame(area: Control) -> Panel:
	var frame := Panel.new()
	frame.visible = false
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(4)
	style.border_color = GOLD
	frame.add_theme_stylebox_override("panel", style)
	area.add_child(frame)
	frame.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	return frame

func _drag_preview(mon: Monster) -> Control:
	var holder := Control.new()
	var picture := TextureRect.new()
	Monmap.show_on(picture, mon._name, Monmap.ICON)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size = Vector2(120, 120)
	picture.position = -picture.size / 2
	picture.modulate.a = 0.85
	holder.add_child(picture)
	return holder

func _badge(text: String, background: Color, color: Color, icon: Texture2D = null, icon_material: Material = null) -> PanelContainer:
	var badge := PanelContainer.new()
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	IronPlate.frame(badge, row, 8, 3).tint(background)
	if icon:
		var picture := TextureRect.new()
		picture.texture = icon
		picture.material = icon_material
		picture.custom_minimum_size = Vector2(18, 18)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(picture)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	row.add_child(label)
	return badge

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = MOUSE_FILTER_IGNORE
	return label
