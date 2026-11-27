extends Control

## Zwischenscreen im Judgement, wenn ein eigenes Monster gefallen ist (Letzter Wille und Wiederbelebung).
## In der Mitte des Schlachtfelds schwebt die Seele des Gefallenen und erklärt, was geht. Um sie herum liegt ihr
## Nachlass unter Knochenhaufen, darum stehen trauernd das Team und die neuen Fänge. Ihre Werte stehen oben in vier
## Spalten, dazwischen Titel und Sprechblase.
## - Knochenhaufen per Drag & Drop beiseitetragen: das eigene Hauptmonster eilt dazu und schiebt von hinten mit.
##   Liegt kein Haufen mehr auf einem Erbstück (eine Trophäen-Art, ein vergebenes Element oder eine Attacke),
##   kommt es zum Vorschein.
## - Erbstück antippen zeigt es oben groß. Erbstück auf ein Monster ziehen (oder antippen, dann das Monster antippen):
##   es erbt genau diese eine Sache, der Rest geht verloren. Die Werte der Monster zeigen, was sich ändern würde.
## - Neuen Fang zur Seele ziehen: er wird ihr neues Gefäß, das gefallene Monster lebt wieder (einmal pro Run).
## - Monster antippen (ohne ausgewähltes Erbstück): wie beim Trainer fährt die Bühne zur Seite und daneben
##   erscheinen seine Details mit allen Attacken (MonSkillsModal).
## run() liefert {"revive": Fang}, {"gift", "target", "replace"} oder {} (nichts hinterlassen).

signal _finished(result: Dictionary)

const BACKGROUND = preload("res://assets/sczene_backgrounds/letzter wille.jpg")
const BACKGROUND_MATERIAL = preload("res://script/ui/shader/background_living_material.tres")
const ELEMENT_CHIP = preload("res://script/ui/element_chip/element_chip.tscn")
const GemField = preload("res://script/scenes/gems/gems.gd")
## zur Laufzeit geladen: treasure.gd hängt über das Element-Overlay am Judgement-Dialog
const TREASURE_SCRIPT := "res://script/scenes/treasure/treasure.gd"
const GOLD := SkillDetailPopup.GOLD
const TEXT_COLOR := IronPlate.TEXT_COLOR
const STAT_KEYS := Growth.ATTRS

## Mitte der Seele (dort, wo im Hintergrundbild die Erdfläche liegt) und der Ellipse mit dem Nachlass
## (Anteile der Bildschirmgröße). Oben hinter der Seele bleibt auf der Ellipse eine Lücke.
const SOUL_CENTER := Vector2(0.5, 0.63)
const RING_CENTER := Vector2(0.5, 0.70)
const RING_RADIUS := Vector2(230, 78)
## ab so vielen Erbstücken wächst die Ellipse je weiterem Erbstück um RING_GROW
const RING_GROW_FROM := 6
const RING_GROW := Vector2(8, 9)
const RING_GAP_DEGREES := 30.0
const SOUL_SIZE := 140.0
const SOUL_TINT := Color(0.55, 0.85, 1.0, 0.62)
const SOUL_BOB := 6.0
## Oben in der Mitte zwischen den Werte-Platten: Titel, darunter Sprechblase bzw. das ausgewählte Erbstück
const BUBBLE_WIDTH := 400.0
const TOP_CONTENT_Y := 56.0
## Breite der Erklärung zu Trophäe oder Element (ihre Texte brechen darin um)
const DETAIL_WIDTH := 300.0
const SPOT_SIZE := Vector2(100, 60)
const GIFT_VIEW_SIZE := Vector2(140, 104)
const GIFT_ART_SIZE := 56.0
## Breite der Trefferfläche eines Erbstücks (Bild und die Mitte des Namens)
const ITEM_HIT_WIDTH := 76.0
## Erbstücke lassen sich nicht höher als hier ablegen (Anteil der Bildschirmhöhe; darüber ist Himmel)
const ITEM_MIN_Y := 0.5
## Mini-Attackenkarte auf dem Boden: Kartenpapier ohne Text, auf GIFT_ART_SIZE verkleinert
const MINI_CARD_SIZE := Vector2(150, 185)
## Knochen pro Haufen; ein Erbstück ist frei, wenn sein Haufen weiter als COVER_RADIUS weggetragen wurde
const BONES_PER_GIFT := Vector2i(3, 4)
const SKULL_CHANCE := 0.4
const COVER_RADIUS := 34.0
## Unterkante eines Haufens unter seiner Mitte (für die Tiefe)
const HEAP_FOOT := 14.0
## Bildschirmpixel pro Pixel der Knochen, etwa so grob wie die Pixel im Hintergrundbild
const ART_PIXEL := 3.0
## Plätze der Trauernden um die Seele (Bildmitte als Anteil der Bildschirmgröße) und die Spalte ihrer Werte-Platte
## oben (0 und 1 links, 2 und 3 rechts). Erst das Team, dann die Fänge; so stehen neue Fänge auf beiden Seiten.
const SLOTS := [
	{"pos": Vector2(0.12, 0.78), "side": -1, "column": 0},
	{"pos": Vector2(0.88, 0.78), "side": 1, "column": 3},
	{"pos": Vector2(0.22, 0.56), "side": -1, "column": 1},
	{"pos": Vector2(0.78, 0.56), "side": 1, "column": 2},
	{"pos": Vector2(0.06, 0.6), "side": -1, "column": 0},
	{"pos": Vector2(0.94, 0.6), "side": 1, "column": 3},
]
const HEIR_PICTURE := 160.0
const PLATE_WIDTH := 200.0
const PLATE_GAP := 10.0
const PLATE_TOP := 12.0
const MOURN_TINT := Color(0.82, 0.84, 0.95)
const MOURN_TILT := 4.0
const BLOCKED_ALPHA := 0.4
const DRAG_THRESHOLD := 8.0
## Aufräumer: seine Füße stehen so weit über der Unterkante des Haufens (dahinter, die Knochen verdecken sie),
## er holt sehr schnell auf
const HELPER_SINK := 8.0
const HELPER_SPEED := 30.0
## Monster-Details wie beim Trainer (MonSkillsModal): die Bühne fährt um diesen Anteil der Breite zur Seite,
## auf der frei werdenden Seite erscheint die Übersicht
const PAN_SHARE := 0.5
const PAN_SECONDS := 0.35
const MODAL_MARGIN := 16.0
const MODAL_TOP := 64.0
## Parallax: der Hintergrund fährt mit diesem Bruchteil der Bühne mit. Fast so weit wie die Bühne, sonst stehen
## Knochen und Monster plötzlich woanders auf dem Boden. Links und rechts liegt das Bild gespiegelt daneben.
const PARALLAX_PAN := 0.8
const TEAR_COLOR := Color(0.62, 0.82, 1.0, 0.9)
const WISP_COLOR := Color(0.55, 0.85, 1.0, 0.8)

var _fallen: Monster
var _dialog: JudgementDialog
var _hp_percent := 0
var _can_revive := false
var _can_inherit := false

## Alles, was beim Öffnen der Monster-Details zur Seite fährt (nur der Knopf bleibt stehen,
## der Hintergrund fährt langsamer mit)
var _stage: Control
var _background: Control
var _field: Control
## Monster, Seele, Erbstücke und Knochenhaufen: jedes Frame nach Fußhöhe sortiert (weiter unten = davor)
var _depth: Control
var _modal_holder: Control
var _open_heir := {}
var _pan_tween: Tween
var _soul: TextureRect
var _soul_time := 0.0
var _soul_floating := true
var _bubble: PanelContainer
var _bubble_label: Label
var _bubble_text := ""
## Erklärung zum ausgewählten Erbstück: Trophäe und Element auf einer Platte, Attacken nur als Karte
var _detail: PanelContainer
var _detail_box: VBoxContainer
var _detail_card: VBoxContainer
var _button: Button

## Einträge {gift, spot, item, heap, revealed, possible}
var _piles: Array = []
## Knochenhaufen (je Erbstück einer), werden als Ganzes getragen
var _heaps: Array = []
## Einträge {mon, catch, side, picture, home, panel, plate, stats: {key: Label}, count, note, tear}
var _heirs: Array = []
var _heir_mons: Array = []
## Lebendes Hauptmonster, das beim Knochenräumen hinterherläuft ({} ohne Team)
var _helper := {}
var _helper_talk: PanelContainer
var _helper_following := false
var _helper_return: Tween

var _press := {}
var _drag := {}
var _selected := {}
var _hovered := {}
var _busy := true
var _wisp_time := 0.0

# ─────────────────────────
# Ablauf

## Gibt es etwas, das mindestens ein Erbe annehmen kann?
static func can_inherit(fallen: Monster, heirs: Array) -> bool:
	return gifts_of(fallen).any(func(gift): return heirs.any(func(heir): return gift_reason(gift, heir) == ""))

## Erbstücke: {"kind": "gems", "stat", "bonus" (gespeichert), "count", "shown" (mit Relikt-Bonus)},
## {"kind": "element", "element"} oder {"kind": "skill", "skill"}
static func gifts_of(fallen: Monster) -> Array:
	var gifts := []
	for stat in GemField.STATS:
		if fallen._gems.get(stat, 0) > 0:
			gifts.append({"kind": "gems", "stat": stat, "bonus": fallen._gems[stat],
				"count": maxi(fallen.gem_count(stat), 1), "shown": fallen.gem_bonus(stat)})
	for element in Enums.MON_TYPES.values():
		if fallen._gained_elements & element:
			gifts.append({"kind": "element", "element": element})
	for skill in fallen._skills:
		gifts.append({"kind": "skill", "skill": skill})
	return gifts

## "" wenn heir das Erbstück annehmen kann, sonst der Grund
static func gift_reason(gift: Dictionary, heir: Monster) -> String:
	match gift.kind:
		"element":
			if ColorMap.has_element(heir._type, gift.element):
				return _tr("LAST_WILL_HAS_ELEMENT")
			if not heir.can_gain_element(gift.element):
				return _tr("ELEMENT_LIMIT_REACHED")
		"skill":
			if Skills.knows_skill(heir, gift.skill.name):
				return _tr("JUDGEMENT_ALREADY_HAS_SKILL").format({"mon": Helper.mon_battle_name(heir), "skill": _tr(gift.skill.name)})
	return ""

static func gift_name(gift: Dictionary) -> String:
	match gift.kind:
		"gems":
			return _tr(GemField.STATS[gift.stat].name)
		"element":
			return _tr(ColorMap.get_combo(gift.element).label)
	return _tr(gift.skill.name)

static func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))

func run(fallen: Monster, team: Array, catches: Array, dialog: JudgementDialog, hp_share: float) -> Dictionary:
	_fallen = fallen
	_dialog = dialog
	_hp_percent = roundi(hp_share * 100)
	_can_revive = not fallen._revived and not catches.is_empty()
	var heirs := team.duplicate()
	heirs.append_array(catches)
	_can_inherit = can_inherit(fallen, heirs)
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_build(team, catches)
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.6)
	await tween.finished
	_say(_intro_text())
	_busy = false
	Tutorial.trigger("last_will")
	return await _finished

## Blendet den Screen aus und entfernt ihn
func close() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.45)
	await tween.finished
	queue_free()

func _intro_text() -> String:
	var lines := []
	lines.append(tr("LAST_WILL_SOUL_GIFT") if _can_inherit else tr("LAST_WILL_SOUL_NOTHING"))
	if _can_revive:
		lines.append(tr("LAST_WILL_SOUL_VESSEL").format({"hp": _hp_percent}))
	elif _fallen._revived and _heirs.any(func(heir): return heir.catch):
		lines.append(tr("LAST_WILL_SOUL_ONCE"))
	return "\n".join(PackedStringArray(lines))

func _finish(result: Dictionary) -> void:
	_busy = true
	# das Tutorial (Feld 8) wartet auf die Wiederbelebung
	if result.has("revive"):
		Events.last_will_revived.emit()
	_finished.emit(result)

# ─────────────────────────
# Eingabe

func _gui_input(event: InputEvent) -> void:
	if _busy:
		return
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_on_press(button.global_position)
		else:
			_on_release(button.global_position)
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_on_motion(motion.global_position)

func _on_press(pos: Vector2) -> void:
	# offene Details: ein anderes Monster wechselt die Übersicht, sonst fährt die Bühne zurück
	if not _open_heir.is_empty():
		_press = {"kind": "open", "ref": _heir_at(pos), "pos": pos}
		return
	_press = {"kind": "", "pos": pos}
	var heap := _heap_at(pos)
	if heap:
		_press = {"kind": "heap", "ref": heap, "pos": pos}
		return
	var entry := _item_at(pos)
	if not entry.is_empty():
		_press = {"kind": "gift", "ref": entry, "pos": pos}
		return
	var heir := _heir_at(pos)
	if not heir.is_empty():
		_press = {"kind": "heir", "ref": heir, "pos": pos}

func _on_motion(pos: Vector2) -> void:
	if not _drag.is_empty():
		if _drag.kind == "heap":
			_drag.ref.position = pos + _drag.offset - _field.global_position
		else:
			_drag.ghost.position = pos - _drag.ghost.size / 2
		_update_hover(pos)
		return
	if _press.is_empty() or _press.kind == "open" or pos.distance_to(_press.pos) <= DRAG_THRESHOLD:
		return
	match _press.kind:
		"heap":
			_start_heap_drag(_press.ref, _press.pos)
		"gift":
			_start_drag("gift", _press.ref, pos)
		"heir":
			if _press.ref.catch:
				_start_drag("catch", _press.ref, pos)
	_press = {}

func _on_release(pos: Vector2) -> void:
	if not _drag.is_empty():
		await _drop(pos)
		return
	if _press.is_empty():
		return
	var press := _press
	_press = {}
	# Antippen: Erbstück auswählen (oben groß), mit Auswahl ein Monster antippen vererbt,
	# ohne Auswahl zeigt es die Details des Monsters, sonst Auswahl aufheben
	match press.kind:
		"open":
			if press.ref.is_empty():
				_close_details()
			else:
				_toggle_details(press.ref)
		"gift":
			_select(press.ref if _selected != press.ref else {})
		"heir":
			if not _selected.is_empty():
				await _give(_selected, press.ref)
			else:
				_toggle_details(press.ref)
		_:
			_select({})

## Den ganzen Haufen tragen: obenauf und leicht angehoben, das Hauptmonster eilt dazu und schiebt von hinten
func _start_heap_drag(heap: BoneHeap, pos: Vector2) -> void:
	heap.scale = Vector2.ONE * 1.1
	_drag = {"kind": "heap", "ref": heap, "offset": heap.global_position - pos}
	_select({})
	if not _helper.is_empty():
		if _helper_return:
			_helper_return.kill()
		_helper_following = true
		_helper_talk.visible = true

func _start_drag(kind: String, ref: Dictionary, pos: Vector2) -> void:
	var ghost := Control.new()
	ghost.mouse_filter = MOUSE_FILTER_IGNORE
	if kind == "gift":
		ghost.size = Vector2.ONE * GIFT_ART_SIZE * 1.2
		var art := _gift_art(ref.gift)
		art.scale = Vector2.ONE * 1.2
		ghost.add_child(art)
		ref.item.modulate.a = 0.35
		_select(ref)
	else:
		ghost.size = Vector2.ONE * HEIR_PICTURE
		var picture := TextureRect.new()
		Monmap.show_on(picture, ref.mon._name, Monmap.ICON)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.size = ghost.size
		ghost.add_child(picture)
		ref.picture.modulate.a = 0.35
		_select({})
		if _can_revive:
			_say(tr("LAST_WILL_SOUL_DRAG_VESSEL") + "\n" + tr("LAST_WILL_REVIVE_DROP").format({"hp": _hp_percent}))
	add_child(ghost)
	ghost.position = pos - ghost.size / 2
	_drag = {"kind": kind, "ref": ref, "ghost": ghost}
	_update_hover(pos)

func _drop(pos: Vector2) -> void:
	var drag := _drag
	_drag = {}
	_set_hovered({})
	if _soul_floating:
		_soul.material = Monmap.MONSTER_MATERIAL
	match drag.kind:
		"heap":
			drag.ref.scale = Vector2.ONE
			_check_uncovered()
			_helper_stop()
		"gift":
			var heir := _heir_at(pos)
			drag.ref.item.modulate.a = 1.0 if drag.ref.possible else 0.5
			drag.ghost.queue_free()
			if not heir.is_empty():
				await _give(drag.ref, heir)
			else:
				# irgendwo aufs Feld: das Erbstück bleibt dort liegen, so lässt es sich zurechtlegen
				# der Name unter dem Bild muss noch auf den Bildschirm passen
				var below := GIFT_VIEW_SIZE.y - 6 - GIFT_ART_SIZE / 2
				var spot := pos.clamp(Vector2(GIFT_VIEW_SIZE.x / 2, size.y * ITEM_MIN_Y), size - Vector2(GIFT_VIEW_SIZE.x / 2, below))
				drag.ref.item.global_position = spot - (_art_center(drag.ref) - drag.ref.item.global_position)
		"catch":
			drag.ref.picture.modulate = MOURN_TINT
			if _soul_rect().has_point(pos):
				if _can_revive:
					await _revive(drag.ref, drag.ghost)
					return
				_say(tr("LAST_WILL_SOUL_ONCE"))
			elif _can_revive:
				_say(_intro_text())
			drag.ghost.queue_free()

func _update_hover(pos: Vector2) -> void:
	match _drag.kind:
		"gift":
			_set_hovered(_heir_at(pos))
		"catch":
			var over := _soul_rect().has_point(pos) and _can_revive
			_soul.material = Monmap.monster_selected_material if over else Monmap.MONSTER_MATERIAL

## Knochenhaufen unter pos; liegen mehrere übereinander, gewinnt der, dessen Mitte am nächsten ist
func _heap_at(pos: Vector2) -> BoneHeap:
	var best: BoneHeap = null
	for heap: BoneHeap in _heaps:
		if heap.hit(pos) and (best == null or heap.global_position.distance_to(pos) < best.global_position.distance_to(pos)):
			best = heap
	return best

## Aufgedecktes Erbstück unter pos: nur Bild und Name zählen (nicht die ganze, breite Ansicht), bei Überschneidung
## gewinnt das Erbstück, dessen Bild am nächsten ist
func _item_at(pos: Vector2) -> Dictionary:
	var best := {}
	var best_distance := INF
	for entry in _piles:
		if not entry.revealed:
			continue
		var item: Control = entry.item
		var hit_area := Rect2(item.global_position + Vector2((GIFT_VIEW_SIZE.x - ITEM_HIT_WIDTH) / 2, 0), Vector2(ITEM_HIT_WIDTH, GIFT_VIEW_SIZE.y))
		var distance := _art_center(entry).distance_to(pos)
		if hit_area.has_point(pos) and distance < best_distance:
			best = entry
			best_distance = distance
	return best

## Mitte des Bilds eines Erbstücks (global)
func _art_center(entry: Dictionary) -> Vector2:
	return entry.item.global_position + Vector2(GIFT_VIEW_SIZE.x / 2, 6 + GIFT_ART_SIZE / 2)

func _heir_at(pos: Vector2) -> Dictionary:
	# Monster oder seine Werte-Platte oben
	for heir in _heirs:
		if heir.picture.get_global_rect().has_point(pos) or heir.panel.get_global_rect().has_point(pos):
			return heir
	return {}

func _soul_rect() -> Rect2:
	return _soul.get_global_rect().grow(24)

# ─────────────────────────
# Aktionen

## Erbstücke, auf denen kein Haufen mehr liegt, kommen zum Vorschein
func _check_uncovered() -> void:
	for entry in _piles:
		if entry.revealed:
			continue
		var center: Vector2 = entry.item.global_position + Vector2(GIFT_VIEW_SIZE.x / 2, 6 + GIFT_ART_SIZE / 2)
		if _heaps.any(func(heap): return heap.global_position.distance_to(center) < COVER_RADIUS):
			continue
		entry.revealed = true
		var item: Control = entry.item
		item.visible = true
		item.scale = Vector2.ONE * 0.3
		item.modulate.a = 1.0 if entry.possible else 0.5
		item.create_tween().tween_property(item, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _select(entry: Dictionary) -> void:
	if entry == _selected:
		return
	if not _selected.is_empty() and is_instance_valid(_selected.item):
		_selected.item.create_tween().tween_property(_selected.item, "scale", Vector2.ONE, 0.12)
	_selected = entry
	if not entry.is_empty():
		entry.item.create_tween().tween_property(entry.item, "scale", Vector2.ONE * 1.12, 0.12)
	_show_detail(entry.gift if not entry.is_empty() else {})
	_refresh_previews()

## Tutorial (Feld 8): erst wiederbeleben, Vererben oder Ablehnen würden die Wiederbelebung überspringen
func _revive_required() -> bool:
	if Tutorial.run_active and _can_revive:
		_say(tr("LAST_WILL_TUT_REVIVE_FIRST"))
		return true
	return false

func _give(entry: Dictionary, heir: Dictionary) -> void:
	if _revive_required():
		return
	var reason := gift_reason(entry.gift, heir.mon)
	if reason != "":
		Helper.show_unlock_message(reason)
		return
	var replace := -1
	if entry.gift.kind == "skill" and heir.mon._skills.size() >= Skills.MAX_SKILLS:
		_busy = true
		replace = await _dialog.pick_replace(heir.mon, entry.gift.skill)
		_busy = false
		if replace == -1:
			return
	_busy = true
	_set_hovered({})
	_selected = {}
	_show_detail({})
	_refresh_previews()
	_say(tr("LAST_WILL_SOUL_THANKS"))
	# das Erbstück fliegt zum Erben, alles andere verblasst
	var item: Control = entry.item
	var target: Vector2 = heir.picture.get_global_rect().get_center() - item.size / 2
	var tween := create_tween().set_parallel()
	tween.tween_property(item, "global_position", target, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(item, "scale", Vector2.ONE * 0.4, 0.55)
	tween.chain().tween_property(item, "modulate:a", 0.0, 0.2)
	for other in _piles:
		if other != entry:
			create_tween().tween_property(other.spot, "modulate:a", 0.25, 0.8)
	await tween.finished
	var flash := create_tween()
	flash.tween_property(heir.picture, "modulate", Color(1.7, 1.6, 1.2), 0.12)
	flash.tween_property(heir.picture, "modulate", MOURN_TINT, 0.4)
	await _soul_leave()
	_finish({"gift": entry.gift, "target": heir.mon, "replace": replace})

## Der Fang wird zum neuen Gefäß: er fliegt in die Seele, die Seele wird wieder zum lebenden Monster
func _revive(heir: Dictionary, ghost: Control) -> void:
	_busy = true
	_select({})
	_say(tr("LAST_WILL_SOUL_REVIVED"))
	_soul_floating = false
	var center := _soul.get_global_rect().get_center()
	ghost.pivot_offset = ghost.size / 2
	var tween := create_tween().set_parallel()
	tween.tween_property(ghost, "position", center - ghost.size / 2, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(ghost, "rotation", TAU, 0.4)
	tween.tween_property(ghost, "scale", Vector2.ONE * 0.3, 0.4)
	tween.tween_property(heir.picture, "modulate:a", 0.0, 0.4)
	tween.tween_property(heir.panel, "modulate:a", 0.0, 0.4)
	tween.chain().tween_property(ghost, "modulate:a", 0.0, 0.15)
	await tween.finished
	ghost.queue_free()
	# der Nachlass gehört wieder ihm: aufgedeckte Erbstücke fliegen zu ihm zurück
	for entry in _piles:
		if not entry.revealed:
			continue
		var item: Control = entry.item
		var fly := create_tween().set_parallel()
		fly.tween_property(item, "global_position", center - item.size / 2, 0.5)
		fly.tween_property(item, "modulate:a", 0.0, 0.5)
	# aufleuchten, Farbe und Körper zurück, ein Hüpfer
	_soul.pivot_offset = _soul.size / 2
	var rise := create_tween()
	rise.tween_property(_soul, "modulate", Color(2, 2, 2, 1), 0.18)
	rise.set_parallel()
	rise.tween_property(_soul, "self_modulate", Color.WHITE, 0.45).set_delay(0.18)
	rise.tween_property(_soul, "modulate", Color.WHITE, 0.45).set_delay(0.18)
	rise.tween_property(_soul, "scale", Vector2.ONE * 1.25, 0.22).set_delay(0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rise.tween_property(_soul, "position:y", _soul.position.y - 30, 0.22).set_delay(0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rise.chain().tween_property(_soul, "scale", Vector2.ONE * 1.1, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rise.tween_property(_soul, "position:y", _soul.position.y, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await rise.finished
	# die anderen trauern nicht mehr
	for other in _heirs:
		other.picture.modulate = Color.WHITE
		other.picture.rotation_degrees = 0.0
	await get_tree().create_timer(0.8).timeout
	_finish({"revive": heir.mon})

func _on_button_pressed() -> void:
	if _busy or _revive_required():
		return
	if _can_inherit:
		_busy = true
		var text := tr("LAST_WILL_DECLINE_TEXT").format({"mon": Helper.mon_battle_name(_fallen)})
		var ok := await _dialog.confirm(tr("LAST_WILL_DECLINE_TITLE"), text, tr("LAST_WILL_DECLINE"))
		_busy = false
		if not ok:
			return
	_busy = true
	_select({})
	_say(tr("LAST_WILL_SOUL_FAREWELL"))
	for entry in _piles:
		create_tween().tween_property(entry.spot, "modulate:a", 0.0, 0.8)
	await _soul_leave()
	_finish({})

## Die Seele steigt auf und verblasst
func _soul_leave() -> void:
	await get_tree().create_timer(0.9).timeout
	_soul_floating = false
	var tween := create_tween().set_parallel()
	tween.tween_property(_soul, "position:y", _soul.position.y - 90, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(_soul, "modulate:a", 0.0, 1.1)
	tween.tween_property(_bubble, "modulate:a", 0.0, 0.6)
	await tween.finished

# ─────────────────────────
# Monster-Details

## Wie beim Trainer: Monster links fahren mit der Bühne nach rechts, links daneben erscheint die Übersicht
## (MonSkillsModal); Monster rechts umgekehrt. Dasselbe Monster nochmal oder ein Klick daneben fährt zurück.
func _toggle_details(heir: Dictionary) -> void:
	if heir == _open_heir:
		_close_details()
		return
	_select({})
	if not _open_heir.is_empty():
		_open_heir.picture.material = Monmap.MONSTER_MATERIAL
	_clear(_modal_holder)
	_open_heir = heir
	heir.picture.material = Monmap.monster_selected_material
	var pan := size.x * PAN_SHARE
	var side: int = heir.side
	_modal_holder.size = Vector2(pan - 2 * MODAL_MARGIN, size.y - MODAL_TOP - MODAL_MARGIN)
	_modal_holder.position = Vector2(-pan + MODAL_MARGIN if side < 0 else size.x + MODAL_MARGIN, MODAL_TOP)
	_modal_holder.add_child(MonSkillsModal.new(heir.mon))
	_button.visible = false
	_pan_to(pan * -side)

func _close_details() -> void:
	if _open_heir.is_empty():
		return
	_open_heir.picture.material = Monmap.MONSTER_MATERIAL
	_open_heir = {}
	_button.visible = true
	_pan_to(0.0)

func _pan_to(target: float) -> void:
	if _pan_tween:
		_pan_tween.kill()
	_pan_tween = create_tween()
	_pan_tween.tween_method(_set_pan, _stage.position.x, target, PAN_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if target == 0.0:
		_pan_tween.tween_callback(_clear.bind(_modal_holder))

func _set_pan(value: float) -> void:
	_stage.position.x = value
	_update_parallax()

## Der Hintergrund ist links und rechts um den größten Ausschlag breiter, so bleibt nie ein Rand frei
func _update_parallax() -> void:
	_background.position.x = (_stage.position.x if _stage else 0.0) * PARALLAX_PAN

# ─────────────────────────
# Aufräumer

## Steht genau hinter dem getragenen Haufen: die sichtbare Figur mittig über der Haufenmitte, ihre Füße knapp
## dahinter, so verdecken die Knochen den unteren Teil. Gerade aufgerichtet, nicht gespiegelt, holt schnell auf.
func _helper_follow(delta: float) -> void:
	var picture: TextureRect = _helper.picture
	var heap: BoneHeap = _drag.ref
	picture.rotation = 0.0
	var feet := Vector2(picture.get_meta("mid_x"), picture.get_meta("foot"))
	var target := heap.global_position + Vector2(0, HEAP_FOOT - HELPER_SINK) - feet
	picture.global_position = picture.global_position.lerp(target, 1.0 - exp(-HELPER_SPEED * delta))

## Kurz stehen bleiben, dann zurück an den eigenen Platz
func _helper_stop() -> void:
	if _helper.is_empty() or not _helper_following:
		return
	_helper_following = false
	var picture: TextureRect = _helper.picture
	_helper_return = create_tween()
	_helper_return.tween_interval(0.7)
	_helper_return.tween_callback(func(): _helper_talk.visible = false)
	_helper_return.tween_property(picture, "position", _helper.home, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# zurück am Platz trauert er wieder leicht geneigt
	_helper_return.tween_property(picture, "rotation_degrees", MOURN_TILT * -_helper.side, 0.2)

func _place_helper_talk() -> void:
	var picture: TextureRect = _helper.picture
	_helper_talk.reset_size()
	_helper_talk.global_position = picture.global_position + Vector2((picture.size.x - _helper_talk.size.x) / 2, -_helper_talk.size.y - 4)

# ─────────────────────────
# Anzeige

func _process(delta: float) -> void:
	if _soul == null:
		return
	_soul_time += delta
	_sort_depth()
	if _helper_following and _drag.get("kind", "") == "heap":
		_helper_follow(delta)
	if _helper_talk and _helper_talk.visible:
		_place_helper_talk()
	# Höhe der Blase steht erst nach dem Umbruch fest: neu ausrichten, solange sie sichtbar ist
	if _bubble.visible:
		_place_bubble()
	# ebenso die Erklärung zum Erbstück: schrumpft auf ihre tatsächliche Größe, falls sie zu groß gemessen wurde
	for shown in [_detail, _detail_card]:
		if shown.visible:
			_place_detail(shown)
	if _soul_floating:
		_soul.position.y = _soul_home_y() + sin(_soul_time * 1.6) * SOUL_BOB
		_soul.modulate.a = SOUL_TINT.a + sin(_soul_time * 2.3) * 0.08
		_wisp_time -= delta
		if _wisp_time <= 0:
			_wisp_time = randf_range(0.25, 0.6)
			_spawn_drop(_soul.position + Vector2(randf_range(0.25, 0.75) * SOUL_SIZE, SOUL_SIZE * 0.6), WISP_COLOR, -40.0, 1.3)
	# Tränen der Trauernden
	for heir in _heirs:
		heir.tear -= delta
		if heir.tear <= 0 and heir.picture.modulate.a > 0.5 and _soul_floating:
			heir.tear = randf_range(1.6, 3.6)
			var picture: TextureRect = heir.picture
			var spot := picture.global_position - _field.global_position + Vector2(picture.size.x * randf_range(0.4, 0.6), picture.size.y * 0.35)
			_spawn_drop(spot, TEAR_COLOR, 34.0, 0.9)

## Sichtbare Figur in einem Monsterbild (ohne durchsichtigen Rand), lokal im Bild: "foot" = Unterkante der Figur,
## "mid_x" = ihre Mitte. Gebraucht für die Tiefe und damit der Aufräumer genau hinter dem Haufen steht.
func _measure_figure(picture: TextureRect) -> void:
	var image := picture.texture.get_image() if picture.texture else null
	if image == null:
		picture.set_meta("foot", picture.size.y)
		picture.set_meta("mid_x", picture.size.x / 2)
		return
	if image.is_compressed():
		image.decompress()
	var used := image.get_used_rect()
	# wie STRETCH_KEEP_ASPECT_CENTERED
	var fit := minf(picture.size.x / image.get_width(), picture.size.y / image.get_height())
	var offset := (picture.size - Vector2(image.get_size()) * fit) / 2
	picture.set_meta("foot", offset.y + used.end.y * fit)
	picture.set_meta("mid_x", offset.x + (used.position.x + used.size.x / 2.0) * fit)

## Was weiter unten auf dem Boden steht, liegt davor: Monster und Knochen verdecken sich je nach Höhe gegenseitig
func _sort_depth() -> void:
	var nodes := _depth.get_children()
	nodes.sort_custom(func(a, b): return _foot_y(a) < _foot_y(b))
	for i in nodes.size():
		if nodes[i].get_index() != i:
			_depth.move_child(nodes[i], i)

## Höhe, auf der etwas auf dem Boden steht (lokal in _depth)
func _foot_y(node: Control) -> float:
	if node is BoneHeap:
		return node.position.y + HEAP_FOOT
	if node is BloodSpot:
		# das Erbstück liegt im Fleck; seine Unterkante ist das Bild, nicht der Name
		var item: Control = node.get_child(0)
		return node.position.y + item.position.y + 6 + GIFT_ART_SIZE
	# Monster und Seele: die Füße der sichtbaren Figur, nicht der Bildrand (die Bilder haben durchsichtige Ränder)
	return node.position.y + node.get_meta("foot", node.size.y)

func _soul_home_y() -> float:
	return size.y * SOUL_CENTER.y - SOUL_SIZE / 2

func _spawn_drop(pos: Vector2, color: Color, distance: float, time: float) -> void:
	var drop := Drop.new()
	drop.color = color
	drop.rising = distance < 0
	drop.position = pos
	_field.add_child(drop)
	var tween := drop.create_tween().set_parallel()
	tween.tween_property(drop, "position:y", pos.y + distance, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(drop, "modulate:a", 0.0, time).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(drop.queue_free)

## Sprechblase der Seele, Text läuft wie geschrieben ein
func _say(text: String) -> void:
	if text == _bubble_text and _bubble.visible:
		return
	_bubble_text = text
	_bubble_label.text = text
	_bubble_label.visible_ratio = 0.0
	_bubble.visible = _selected.is_empty()
	_bubble.modulate.a = 1.0
	create_tween().tween_property(_bubble_label, "visible_ratio", 1.0, clampf(text.length() * 0.018, 0.3, 1.6))

func _place_bubble() -> void:
	_bubble.reset_size()
	_bubble.position = Vector2((size.x - _bubble.size.x) / 2, TOP_CONTENT_Y)

## Ausgewähltes Erbstück oben groß an der Stelle der Sprechblase ({} = Sprechblase wieder zeigen)
func _show_detail(gift: Dictionary) -> void:
	_detail.visible = false
	_detail_card.visible = false
	_bubble.visible = gift.is_empty() and _bubble_text != ""
	if gift.is_empty():
		return
	var possible := _heirs.any(func(heir): return gift_reason(gift, heir.mon) == "")
	var box: VBoxContainer = _detail_card if gift.kind == "skill" else _detail_box
	_clear(box)
	if gift.kind == "skill":
		var card := EggSkillCard.create(gift.skill, _fallen)
		card.custom_minimum_size = Vector2(270, EggSkillCard.HEIGHT)
		_ignore_mouse(card)
		box.add_child(card)
	else:
		var title := _label(32, GOLD if gift.kind == "gems" else Helper.color_by_type(gift.element))
		title.text = gift_name(gift)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(title)
		var art_row := CenterContainer.new()
		art_row.custom_minimum_size.y = GIFT_ART_SIZE
		art_row.mouse_filter = MOUSE_FILTER_IGNORE
		var art_holder := Control.new()
		art_holder.custom_minimum_size = Vector2.ONE * GIFT_ART_SIZE
		art_holder.mouse_filter = MOUSE_FILTER_IGNORE
		art_holder.add_child(_gift_art(gift))
		art_row.add_child(art_holder)
		box.add_child(art_row)
		var desc := _label(24, TEXT_COLOR)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if gift.kind == "gems":
			var info: Dictionary = GemField.STATS[gift.stat]
			desc.text = tr(info.desc) + "\n" + tr("GEM_DESC").format({"stat": _stat_name(gift.stat), "value": gift.shown})
		else:
			desc.text = tr("LAST_WILL_ELEMENT_DESC")
		box.add_child(desc)
	if not possible:
		var note := _label(24, GOLD)
		_outline(note)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.text = tr("LAST_WILL_ALL_HAVE_ELEMENT") if gift.kind == "element" else tr("JUDGEMENT_TEACH_KNOWN_ALL")
		box.add_child(note)
	# umbrechende Texte brauchen ihre Breite von Anfang an, sonst misst Godot sie mit einem Wort pro Zeile und
	# die Platte wird viel zu hoch
	for child in box.get_children():
		if child is Label:
			child.custom_minimum_size.x = DETAIL_WIDTH
	var shown: Control = _detail_card if gift.kind == "skill" else _detail
	shown.visible = true
	_place_detail(shown)

func _place_detail(shown: Control) -> void:
	shown.reset_size()
	shown.position = Vector2((size.x - shown.size.x) / 2, TOP_CONTENT_Y)

## Werte und Hinweise der Erben passend zum ausgewählten Erbstück
func _refresh_previews() -> void:
	var gift: Dictionary = _selected.gift if not _selected.is_empty() else {}
	for heir in _heirs:
		var mon: Monster = heir.mon
		var values := _stat_values(mon)
		for key in STAT_KEYS:
			var label: Label = heir.stats[key]
			var boosted: bool = not gift.is_empty() and gift.kind == "gems" and gift.stat == key
			label.text = "%d>%d" % [values[key], values[key] + gift.shown] if boosted else str(values[key])
			label.add_theme_color_override("font_color", GOLD if boosted else TEXT_COLOR)
		var full := mon._skills.size() >= Skills.MAX_SKILLS
		heir.count.add_theme_color_override("font_color", GOLD if not gift.is_empty() and gift.kind == "skill" and full else TEXT_COLOR)
		var lines := []
		var reason := "" if gift.is_empty() else gift_reason(gift, mon)
		if reason != "":
			lines.append(reason if gift.kind == "element" else tr("JUDGEMENT_LEARN_KNOWN_LONG"))
		elif not gift.is_empty():
			match gift.kind:
				"element":
					lines.append("%s %s" % [tr("SHOP_CHANGES_TO"), tr(ColorMap.get_combo(ColorMap.add_element(mon._type, gift.element)).label)])
				"skill":
					var missing := Skills.missing_elements_text(mon, gift.skill)
					if missing != "":
						lines.append(missing)
					if full:
						lines.append(tr("LAST_WILL_REPLACES"))
			if heir.catch:
				lines.append(tr("LAST_WILL_HEIR_CATCH"))
		heir.note.text = "\n".join(PackedStringArray(lines))
		heir.note.visible = not lines.is_empty()
		var alpha := BLOCKED_ALPHA if reason != "" else 1.0
		heir.picture.modulate.a = alpha
		heir.panel.modulate.a = alpha

func _set_hovered(heir: Dictionary) -> void:
	if heir == _hovered:
		return
	if not _hovered.is_empty():
		_hovered.plate.set_rim(IronPlate.RIM)
	_hovered = heir
	if not heir.is_empty() and gift_reason(_drag.ref.gift, heir.mon) == "":
		heir.plate.set_rim(GOLD)

func _stat_values(mon: Monster) -> Dictionary:
	return {"hp": int(mon.hp()), "atk": int(mon.attack()), "def": int(mon.defense()), "s_atk": int(mon.s_attack()), "speed": int(mon.speed())}

func _stat_name(stat: String) -> String:
	return tr(GemField.STATS[stat].stat).trim_suffix(":")

# ─────────────────────────
# Aufbau

func _build(team: Array, catches: Array) -> void:
	# Hintergrund füllt den Bildschirm (wie KEEP_ASPECT_COVERED), links und rechts liegt er gespiegelt daneben,
	# damit beim Parallax nie ein Rand frei wird
	_background = Control.new()
	_background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_background)
	var image_size := BACKGROUND.get_size()
	var cover := maxf(size.x / image_size.x, size.y / image_size.y)
	var tile := image_size * cover
	var origin := (size - tile) / 2
	for i in [-1, 0, 1]:
		var part := TextureRect.new()
		part.texture = BACKGROUND
		part.material = BACKGROUND_MATERIAL
		part.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		part.stretch_mode = TextureRect.STRETCH_SCALE
		part.flip_h = i != 0
		part.mouse_filter = MOUSE_FILTER_IGNORE
		part.size = tile
		part.position = origin + Vector2(i * tile.x, 0)
		_background.add_child(part)
	_update_parallax()
	_stage = Control.new()
	_stage.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_stage)
	_stage.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_field = Control.new()
	_field.mouse_filter = MOUSE_FILTER_IGNORE
	_stage.add_child(_field)
	_field.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_depth = Control.new()
	_depth.mouse_filter = MOUSE_FILTER_IGNORE
	_field.add_child(_depth)
	_depth.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var title := _label(32, GOLD)
	_outline(title)
	title.text = tr("LAST_WILL_TITLE").format({"mon": Helper.mon_battle_name(_fallen)})
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# fährt mit den Werte-Platten mit, sonst liefe er beim Öffnen der Details in sie hinein
	_stage.add_child(title)
	title.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	title.offset_top = 14

	# erst die Erben: die Erbstücke prüfen, ob jemand sie annehmen kann
	var slot := 0
	for mon in team:
		_add_heir(mon, false, slot)
		slot += 1
	for mon in catches:
		_add_heir(mon, true, slot)
		slot += 1
	_build_soul()
	_build_piles()
	_build_helper(team)

	_detail = PanelContainer.new()
	_detail.mouse_filter = MOUSE_FILTER_IGNORE
	_detail.visible = false
	_detail_box = VBoxContainer.new()
	_detail_box.custom_minimum_size.x = DETAIL_WIDTH
	_detail_box.add_theme_constant_override("separation", 6)
	_detail_box.mouse_filter = MOUSE_FILTER_IGNORE
	IronPlate.frame(_detail, _detail_box, 14, 10).set_rim(GOLD)
	_stage.add_child(_detail)
	_detail_card = VBoxContainer.new()
	_detail_card.mouse_filter = MOUSE_FILTER_IGNORE
	_detail_card.visible = false
	_detail_card.add_theme_constant_override("separation", 6)
	_stage.add_child(_detail_card)
	_modal_holder = Control.new()
	_modal_holder.mouse_filter = MOUSE_FILTER_IGNORE
	_stage.add_child(_modal_holder)

	_button = RewardDialog.plate_button("LAST_WILL_DECLINE" if _can_inherit else "JUDGEMENT_CONTINUE")
	_button.custom_minimum_size = Vector2(220, 48)
	_button.add_theme_font_size_override("font_size", 24)
	_button.pressed.connect(_on_button_pressed)
	add_child(_button)
	_button.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM, PRESET_MODE_MINSIZE)
	_button.grow_horizontal = GROW_DIRECTION_BOTH
	_button.grow_vertical = GROW_DIRECTION_BEGIN
	_button.position.y -= 14

## Die Seele schwebt dort, wo das Monster gefallen ist: halb durchsichtig, bläulich, atmet wie ein lebendes Monster
func _build_soul() -> void:
	_soul = TextureRect.new()
	_soul.texture = Monmap.texture(_fallen._name, SOUL_SIZE)
	_soul.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_soul.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_soul.mouse_filter = MOUSE_FILTER_IGNORE
	_soul.material = Monmap.MONSTER_MATERIAL
	_soul.self_modulate = Color(SOUL_TINT, 1.0)
	_soul.modulate.a = SOUL_TINT.a
	_soul.size = Vector2.ONE * SOUL_SIZE
	_soul.position = Vector2(size.x * SOUL_CENTER.x - SOUL_SIZE / 2, _soul_home_y())
	_soul.add_to_group("tut_will_soul")
	_depth.add_child(_soul)
	_measure_figure(_soul)

	_bubble = PanelContainer.new()
	_bubble.mouse_filter = MOUSE_FILTER_IGNORE
	_bubble.visible = false
	_bubble_label = _label(24, TEXT_COLOR)
	_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble_label.custom_minimum_size.x = BUBBLE_WIDTH - 32
	IronPlate.frame(_bubble, _bubble_label, 16, 10).set_rim(WISP_COLOR)
	_stage.add_child(_bubble)

## Erbstücke auf einer Ellipse um die Seele, in zufälliger Reihenfolge und jedes unter ein paar Knochen
func _build_piles() -> void:
	var gifts := gifts_of(_fallen)
	gifts.shuffle()
	var center := Vector2(size.x * RING_CENTER.x, size.y * RING_CENTER.y)
	var span := 360.0 - 2 * RING_GAP_DEGREES
	# viele Erbstücke: die Ellipse wächst, damit sie sich nicht gegenseitig verdecken
	var extra := maxi(gifts.size() - RING_GROW_FROM, 0)
	var radius := RING_RADIUS + RING_GROW * extra
	for i in gifts.size():
		var angle := deg_to_rad(-90.0 + RING_GAP_DEGREES + span * (i + 0.5) / gifts.size())
		var spot_center := center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
		var spot := BloodSpot.new()
		spot.size = SPOT_SIZE
		spot.position = spot_center - SPOT_SIZE / 2
		spot.mouse_filter = MOUSE_FILTER_IGNORE
		spot.splash()
		var item := _gift_view(gifts[i])
		item.visible = false
		item.position = (SPOT_SIZE - GIFT_VIEW_SIZE) / 2 + Vector2(0, -16)
		spot.add_child(item)
		spot.add_to_group("tut_will_piles")
		_piles.append({"gift": gifts[i], "spot": spot, "item": item, "heap": null, "revealed": false,
			"possible": _heir_mons.any(func(mon): return gift_reason(gifts[i], mon) == "")})
	for entry in _piles:
		_depth.add_child(entry.spot)
	# je Erbstück ein Haufen aus ein paar Knochen und manchmal einem Schädel obenauf, getragen wird er als Ganzes
	for entry in _piles:
		var heap := BoneHeap.new()
		heap.position = entry.spot.position + entry.item.position + Vector2(GIFT_VIEW_SIZE.x / 2, 6 + GIFT_ART_SIZE / 2)
		for i in randi_range(BONES_PER_GIFT.x, BONES_PER_GIFT.y):
			var bone := Bone.new(PixelArt.bone(randi_range(12, 15)), ART_PIXEL, Monmap.LIVING_MATERIAL)
			bone.position = Vector2(randf_range(-12, 12), randf_range(-9, 9))
			bone.rotation = randf_range(-PI, PI)
			heap.add_child(bone)
		if randf() < SKULL_CHANCE:
			var skull := Bone.new(PixelArt.skull(), ART_PIXEL, Monmap.LIVING_MATERIAL)
			skull.position = Vector2(randf_range(-6, 6), randf_range(-8, -2))
			skull.rotation = randf_range(-0.4, 0.4)
			heap.add_child(skull)
		_depth.add_child(heap)
		_heaps.append(heap)
		entry.heap = heap
	_sort_depth()

## Das lebende Hauptmonster (Start-Monster, sonst das erste im Team) räumt mit
func _build_helper(team: Array) -> void:
	if team.is_empty():
		return
	var mon: Monster = State.starter if team.has(State.starter) else team[0]
	for heir in _heirs:
		if heir.mon == mon:
			_helper = heir
	_helper_talk = PanelContainer.new()
	_helper_talk.mouse_filter = MOUSE_FILTER_IGNORE
	_helper_talk.visible = false
	var label := _label(24, TEXT_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text = tr("LAST_WILL_TIDY")
	IronPlate.frame(_helper_talk, label, 10, 4)
	_stage.add_child(_helper_talk)

## Trauerndes Monster an seinem Platz um die Seele; seine Werte-Platte steht oben in seiner Spalte
## (zwei links, zwei rechts, dazwischen Titel und Sprechblase)
func _add_heir(mon: Monster, is_catch: bool, slot_index: int) -> void:
	var slot: Dictionary = SLOTS[mini(slot_index, SLOTS.size() - 1)]
	var side: int = slot.side
	var picture_center := Vector2(size.x * slot.pos.x, size.y * slot.pos.y)

	var picture := TextureRect.new()
	Monmap.show_on(picture, mon._name, Monmap.SMALL)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = MOUSE_FILTER_IGNORE
	picture.size = Vector2.ONE * HEIR_PICTURE
	picture.position = picture_center - picture.size / 2
	picture.pivot_offset = Vector2(HEIR_PICTURE / 2, HEIR_PICTURE)
	picture.rotation_degrees = MOURN_TILT * -side
	picture.modulate = MOURN_TINT
	# das Tutorial (Feld 8) zeigt auf den neuen Fang
	if is_catch:
		picture.add_to_group("tut_will_catch")
	_depth.add_child(picture)
	_measure_figure(picture)
	# leises Schluchzen
	var sob := picture.create_tween().set_loops()
	sob.tween_property(picture, "scale", Vector2(1.0, 0.96), 1.1).set_trans(Tween.TRANS_SINE)
	sob.tween_property(picture, "scale", Vector2.ONE, 1.1).set_trans(Tween.TRANS_SINE)

	var column: int = slot.column
	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.custom_minimum_size.x = PLATE_WIDTH
	var column_x := MODAL_MARGIN + column * (PLATE_WIDTH + PLATE_GAP) if column < 2 \
		else size.x - MODAL_MARGIN - (4 - column) * PLATE_WIDTH - (3 - column) * PLATE_GAP
	# mehr als vier Erben (nur im Debug möglich): zweite Reihe
	panel.position = Vector2(column_x, PLATE_TOP + (slot_index / 4) * 240.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = MOUSE_FILTER_IGNORE
	var plate := IronPlate.frame(panel, box, 8, 6)
	_field.add_child(panel)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(header)
	# kleines Bild, damit man die Platte dem Monster auf dem Feld zuordnen kann
	var face := TextureRect.new()
	Monmap.show_on(face, mon._name, Monmap.TINY)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.custom_minimum_size = Vector2(28, 28)
	header.add_child(face)
	var name_label := _label(24, Helper.color_by_mon(mon))
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text = Helper.mon_battle_name(mon)
	header.add_child(name_label)
	var level := _label(24, TEXT_COLOR)
	level.autowrap_mode = TextServer.AUTOWRAP_OFF
	level.text = "%s %d" % [tr("BATTLE_MON_LEVEL"), mon._level]
	header.add_child(level)

	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(info)
	if is_catch:
		var badge := _label(24, GOLD)
		badge.autowrap_mode = TextServer.AUTOWRAP_OFF
		badge.text = tr("JUDGEMENT_BADGE_NEW")
		info.add_child(badge)
	var chip: Control = ELEMENT_CHIP.instantiate()
	chip.mouse_filter = MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = SIZE_SHRINK_CENTER
	info.add_child(chip)
	chip.set_element(mon._type)
	var skill_count := _label(24, TEXT_COLOR)
	skill_count.autowrap_mode = TextServer.AUTOWRAP_OFF
	skill_count.size_flags_horizontal = SIZE_EXPAND_FILL
	skill_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	skill_count.text = "%d/%d" % [mon._skills.size(), Skills.MAX_SKILLS]
	info.add_child(skill_count)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 0)
	grid.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(grid)
	var stats := {}
	for key in STAT_KEYS:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		cell.mouse_filter = MOUSE_FILTER_IGNORE
		cell.add_child(StatsGrid.stat_icon(key, 16))
		var value := _label(24, TEXT_COLOR)
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		cell.add_child(value)
		grid.add_child(cell)
		stats[key] = value
	var note := _label(24, GOLD)
	note.visible = false
	box.add_child(note)
	_ignore_mouse(panel)

	_heir_mons.append(mon)
	_heirs.append({"mon": mon, "catch": is_catch, "side": side, "picture": picture, "home": picture.position,
		"panel": panel, "plate": plate, "stats": stats, "count": skill_count, "note": note, "tear": randf_range(0.5, 2.5)})
	_refresh_previews()

## Erbstück auf dem Boden: Bild und kurzer Name darunter
func _gift_view(gift: Dictionary) -> Control:
	var holder := Control.new()
	holder.size = GIFT_VIEW_SIZE
	holder.pivot_offset = GIFT_VIEW_SIZE / 2
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	var art := _gift_art(gift)
	art.position = Vector2((GIFT_VIEW_SIZE.x - GIFT_ART_SIZE) / 2, 6)
	holder.add_child(art)
	var label := _label(24, GOLD)
	_outline(label)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.max_lines_visible = 2
	label.position = Vector2(0, GIFT_ART_SIZE + 8)
	label.size = Vector2(GIFT_VIEW_SIZE.x, 40)
	match gift.kind:
		"gems":
			label.text = "+%d %s" % [gift.shown, _stat_name(gift.stat)]
		"element":
			label.text = gift_name(gift)
			label.add_theme_color_override("font_color", Helper.color_by_type(gift.element))
		"skill":
			label.text = gift_name(gift)
			label.add_theme_color_override("font_color", SkillCardPaper.readable_color(Helper.color_by_type(gift.skill.nature)))
	holder.add_child(label)
	return holder

## Bild eines Erbstücks in GIFT_ART_SIZE: Trophäe, Trank oder Schriftrolle in der Elementfarbe (Attacke)
func _gift_art(gift: Dictionary) -> Control:
	var art: Control
	match gift.kind:
		"gems":
			art = GemField.gem_icon(gift.stat)
		"element":
			art = load(TREASURE_SCRIPT).potion_art(gift.element)
		_:
			# Attacke: dasselbe Kartenpapier wie die Attackenkarten (Elementfarbe, Art-Symbol), nur ohne Text
			var holder := Control.new()
			var card := Control.new()
			card.size = MINI_CARD_SIZE
			var card_scale := GIFT_ART_SIZE / MINI_CARD_SIZE.y
			card.scale = Vector2.ONE * card_scale
			card.position.x = (GIFT_ART_SIZE - MINI_CARD_SIZE.x * card_scale) / 2
			SkillCardPaper.attach(card, gift.skill)
			holder.add_child(card)
			art = holder
	art.custom_minimum_size = Vector2.ONE * GIFT_ART_SIZE
	art.size = art.custom_minimum_size
	_ignore_mouse(art)
	return art

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

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

func _outline(label: Label) -> void:
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.04))
	label.add_theme_constant_override("outline_size", 6)

# ─────────────────────────
# Gezeichnete Kleinteile

## Blutspritzer unter einem Erbstück
class BloodSpot extends Control:
	const BLOOD := Color(0.36, 0.05, 0.05, 0.85)
	var _specks: Array = []

	func splash() -> void:
		for i in 5:
			_specks.append([Vector2(randf_range(0.15, 0.85) * size.x, randf_range(0.55, 0.9) * size.y), randf_range(1.5, 3.5)])

	func _draw() -> void:
		for speck in _specks:
			draw_circle(speck[0], speck[1], BLOOD)

## Kleine Pixel-Art-Texturen (Knochen, Schädel) für den Living-Pixel-Shader (der braucht eine Textur).
## Knochen in den Farben der Knochen im Hintergrundbild. Schattierung von selbst: oben Licht, unten Schatten,
## außen ein dunkler Umriss.
class PixelArt:
	const BONE_LIGHT := Color8(185, 180, 172)
	const BONE_MID := Color8(160, 155, 148)
	const BONE_SHADE := Color8(124, 117, 107)
	const DARK := Color8(40, 34, 30)
	const OUTLINE := Color8(52, 44, 38)
	## "#" gefüllt, "x" dunkles Detail (Augen, Nase, Zahnlücken)
	const SKULL := [
		"..#####..",
		".#######.",
		"#########",
		"#xx###xx#",
		"#xx###xx#",
		".###x###.",
		"..#####..",
		"..#x#x#..",
		"..#####..",
	]

	static func bone(length: int) -> ImageTexture:
		var inside := func(x: int, y: int) -> bool:
			if x < 0 or y < 0 or x >= length or y >= 6:
				return false
			# Gelenkköpfe an beiden Enden (je zwei Höcker), dazwischen der Schaft
			var end := mini(x, length - 1 - x)
			match end:
				0:
					return y in [0, 1, 4, 5]
				1:
					return true
				2:
					return y >= 1 and y <= 4
			return y >= 2 and y <= 3
		return _paint(length, 6, inside, func(x, y): return _lit(inside, x, y, BONE_LIGHT, BONE_MID, BONE_SHADE))

	static func skull() -> ImageTexture:
		var inside := func(x: int, y: int) -> bool:
			return x >= 0 and y >= 0 and y < SKULL.size() and x < SKULL[y].length() and SKULL[y][x] != "."
		var color := func(x: int, y: int) -> Color:
			return DARK if SKULL[y][x] == "x" else _lit(inside, x, y, BONE_LIGHT, BONE_MID, BONE_SHADE)
		return _paint(SKULL[0].length(), SKULL.size(), inside, color)

	static func _lit(inside: Callable, x: int, y: int, light: Color, mid: Color, shade: Color) -> Color:
		if not inside.call(x, y - 1):
			return light
		if not inside.call(x, y + 1):
			return shade
		return mid

	static func _paint(w: int, h: int, inside: Callable, color_of: Callable) -> ImageTexture:
		var image := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				if inside.call(x, y):
					image.set_pixel(x + 1, y + 1, color_of.call(x, y))
		var outline := []
		for y in h + 2:
			for x in w + 2:
				if image.get_pixel(x, y).a > 0.0:
					continue
				for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
					var n: Vector2i = Vector2i(x, y) + d
					if n.x >= 0 and n.y >= 0 and n.x < w + 2 and n.y < h + 2 and image.get_pixelv(n).a > 0.0:
						outline.append(Vector2i(x, y))
						break
		for p in outline:
			image.set_pixelv(p, OUTLINE)
		return ImageTexture.create_from_image(image)

## Haufen aus Knochen über einem Erbstück; position ist seine Mitte, getragen wird er als Ganzes
class BoneHeap extends Control:
	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func hit(pos: Vector2) -> bool:
		return get_children().any(func(bone): return bone.hit(pos))

## Knochen oder Schädel als Pixel-Art mit Living-Pixel-Shader; position ist die Mitte
## (hit rechnet in Richtung des gedrehten Knochens)
class Bone extends Control:
	const GRAB_MARGIN := 6.0
	var sprite: TextureRect

	func _init(texture: Texture2D, pixel: float, living: Material) -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		sprite = TextureRect.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.material = living
		sprite.mouse_filter = MOUSE_FILTER_IGNORE
		sprite.size = texture.get_size() * pixel
		sprite.position = -sprite.size / 2
		add_child(sprite)

	func hit(pos: Vector2) -> bool:
		var local := get_global_transform().affine_inverse() * pos
		return Rect2(sprite.position, sprite.size).grow(GRAB_MARGIN).has_point(local)

## Träne (fällt) oder Lichtfunke der Seele (steigt)
class Drop extends Control:
	var color := Color.WHITE
	var rising := false

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if rising:
			draw_circle(Vector2.ZERO, 2.5, color)
			return
		draw_circle(Vector2(0, 2), 3.0, color)
		draw_colored_polygon(PackedVector2Array([Vector2(-2.6, 1), Vector2(2.6, 1), Vector2(0, -5)]), color)
