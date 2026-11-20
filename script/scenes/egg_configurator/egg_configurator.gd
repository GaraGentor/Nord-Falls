extends Control

## Konfigurator nach "Reise beginnen": wähle 3 Ei-Attacken, die dein Monster in den Run mitnimmt.
## Zur Wahl stehen die Standard-Ei-Attacken der Art und alle freigeschalteten, dahinter die gesperrten.
##
## Ein Kellerraum (ei_attacken.jpg): das Monster steht hinter dem Tisch (eigene Ebene ei_attacken_tisch.png),
## die Attacken schweben als Karten in einem Bogen von der linken Truhe über den Tisch zur rechten.
## Höchstens VISIBLE schweben gleichzeitig. Scrollen (Mausrad, Wischen) schiebt sie weiter: die einen
## verschwinden in der einen Truhe, aus der anderen kommen neue.
## Mitgenommen wird, was auf dem Tisch liegt: Karte auf einen Platz ziehen (eine dort liegende fliegt zurück in
## den Bogen bzw. tauscht bei Tisch-zu-Tisch den Platz) oder antippen. Vom Tisch gezogen und irgendwo losgelassen
## oder angetippt fliegt sie zurück in den Bogen.
## Gesperrte Attacken lassen sich nicht nehmen: das Monster sagt in einer Sprechblase, wie man sie freischaltet.
##
## Alle Positionen stehen in Pixeln des Hintergrundbilds, das den Bildschirm füllt (wie stretch "cover").
## Jede Karte hat ein Ziel (Bogen, Tisch, Truhe, Finger) und gleitet in _process dorthin.

const SKILLS_TO_PICK := 3
## so viele Karten schweben gleichzeitig im Bogen
const VISIBLE := 6
## Hintergrund ohne Tisch (ei_attacken.jpg, die Stelle mit der Umgebung aufgefüllt)
const BACKGROUND := preload("res://assets/sczene_backgrounds/ei_attacken_ohne_tisch.jpg")
## nur der Tisch aus ei_attacken.jpg, liegt vergrößert vor dem Monster
const TABLE := preload("res://assets/sczene_backgrounds/ei_attacken_tisch.png")
## Tisch um TABLE_ZOOM vergrößert, TABLE_PIVOT (Mitte unten zwischen den Beinen) bleibt stehen
const TABLE_ZOOM := 1.20
const TABLE_PIVOT := Vector2(686, 312)
const BACKGROUND_MATERIAL := preload("res://script/ui/shader/background_living_material.tres")
const IMAGE_SIZE := Vector2(1376, 768)
const GO_ICON := preload("res://assets/ui/icons/check_go.svg")
const TEXT_COLOR := IronPlate.TEXT_COLOR
const GOLD := SkillCardPaper.GOLD

## Bogen als quadratische Bézierkurve von Truhe zu Truhe (Bildpixel)
const ARC_START := Vector2(222, 488)
const ARC_CONTROL := Vector2(688, -290)
const ARC_END := Vector2(1154, 488)
## Anteil der Kurvenneigung, um den sich die Karten im Bogen drehen
const ARC_TILT := 0.25
## Kartengröße ohne Skalierung (Bildpixel), skaliert je nach Ort
const CARD_SIZE := Vector2(180, 210)
const ARC_SCALE := 0.85
const TABLE_SCALE := 0.88
## Karten auf dem Tisch liegen: in der Tiefe gestaucht, darunter ein Schatten
const LYING_SQUASH := 1.0
const SHADOW_OFFSET := Vector2(5, 7)
const SHADOW_COLOR := Color(0, 0, 0, 0.45)
## vergrößert und aufgerichtet zum Lesen (Maus darüber bzw. Finger gedrückt halten)
const HOVER_SCALE := 1.25
const DRAG_SCALE := 0.9
## Plätze auf der Tischplatte (Mitte der Karte) und ihre leichte Schräglage
const SLOT_CENTERS: Array[Vector2] = [Vector2(514, 552), Vector2(686, 552), Vector2(858, 552)]
const SLOT_TILT: Array[float] = [-0.04, 0.015, 0.05]
## auf der Tischplatte losgelassen landet die Karte auf dem nächsten Platz
## (Tischplatte bei TABLE_ZOOM 1.2 um TABLE_PIVOT samt den Karten darauf)
const TABLE_RECT := Rect2(395, 455, 586, 200)
## Das Monster steht hinter dem Tisch auf dem Boden: die sichtbaren Füße (unterer Rand des nicht
## durchsichtigen Bildteils) stehen auf MON_FEET, an der Wand hinter dem Tisch.
## Der sichtbare Teil wird MON_HEIGHT hoch, breite Monster höchstens MON_MAX_WIDTH breit.
const MON_FEET := Vector2(688, 648)
const MON_HEIGHT := 420.0
const MON_MAX_WIDTH := 660.0
## Sprechblase rechts neben dem Kopf, Zipfel zeigt nach links zum Monster
const BUBBLE_AT := Vector2(820, 225)
const BUBBLE_WIDTH := 380.0
## Mitte der Zeile mit Zähler und Aufbruch-Knopf unter dem Tisch
const BOTTOM_ROW_Y := 736.0
## Bereich des Bogens für die Tutorial-Hervorhebung
const ARC_AREA := Rect2(120, 30, 1136, 460)
## Mitte der Zähler auf der Vorderseite der Truhen (Bildpixel): so viele Karten liegen noch darin
const CHEST_COUNT_LEFT := Vector2(222, 600)
const CHEST_COUNT_RIGHT := Vector2(1154, 600)
const CHEST_COUNT_FONT_SIZE := 22
## leere Truhe: Zähler gedimmt
const CHEST_EMPTY_ALPHA := 0.45

## wie schnell Karten ihrem Ziel folgen (exponentiell, pro Sekunde)
const FOLLOW_SPEED := 12.0
const SCROLL_SPEED := 10.0
## Wackeln einer gesperrten Karte, die man nehmen wollte
const SHAKE_PIXELS := 6.0
const SHAKE_DECAY := 3.0
## Mit dem Finger beginnt das Ziehen einer Karte erst nach so langem Drücken, vorher scrollt Wischen den Bogen
const LONG_PRESS_USEC := 300_000
## So weit darf sich der Finger bzw. die Maus bewegen, damit es noch als Antippen zählt
const TAP_DISTANCE := DragScroll.DEADZONE

## Eine Attacke samt Karte und deren aktueller Darstellung (Mitte in Bildschirmpixeln)
class Entry:
	var name: String
	var card: EggSkillCard
	## "" = wählbar, sonst Überschrift und Hinweis, wie man sie freischaltet
	var locked_label := ""
	var hint := ""
	## Platz auf dem Tisch, -1 = schwebt im Bogen
	var slot := -1
	var center := Vector2.ZERO
	var scale := 0.0
	## Höhe im Verhältnis zur Breite: 1 = aufrecht, LYING_SQUASH = liegt auf dem Tisch
	var squash := 1.0
	var rotation := 0.0
	var alpha := 0.0
	var shake := 0.0

	func locked() -> bool:
		return locked_label != ""

var _mon: Monster
var _entries: Array[Entry] = []
## Karte pro Tischplatz, null = leer
var _slots: Array = []
## Position im Bogen: Index der ersten sichtbaren schwebenden Karte (gleitet zu _scroll_target)
var _scroll := 0.0
var _scroll_target := 0.0

var _background: TextureRect
var _table: TextureRect
var _monster: TextureRect
## ganzes Monsterbild in Bildpixeln des Hintergrunds, so gelegt, dass die Füße auf MON_FEET stehen
var _mon_rect: Rect2
var _slot_marks: Control
var _card_layer: Control
var _bubble: SpeechBubble
var _bottom_row: HBoxContainer
var _counter_label: Label
var _go_button: Button
## Zähler auf den Truhen: [Panel, Label] links und rechts
var _chest_left: Array = []
var _chest_right: Array = []
## unsichtbare Flächen für die Tutorial-Hervorhebung
var _table_area: Control
var _arc_area: Control
var _mon_area: Control
## sichtbarer Teil des Monsters in Bildpixeln des Hintergrunds
var _mon_visible: Rect2

## gedrückt: Karte (oder null = Hintergrund), wo und wann, mit dem Finger?
var _pressing := false
var _press_entry: Entry
var _press_pos := Vector2.ZERO
var _press_usec := 0
var _press_touch := false
## "" = noch unklar (Antippen), "drag" = Karte ziehen, "swipe" = Bogen scrollen, "blocked" = gesperrte Karte
var _mode := ""
var _swipe_start_scroll := 0.0
## Tischplatz unter der gezogenen Karte, -1 = keiner
var _drop_slot := -1
var _hovered: Entry
## zuletzt angeklickte gesperrte Karte, leuchtet am Rahmen
var _selected_locked: Entry
## Zeitpunkt, seit dem ein Finger liegt (0 = kein Finger, z. B. Maus)
var _touch_down_usec := 0
var _time := 0.0
## letzte Position von Maus bzw. Finger (lokal), aus den Eingabe-Events statt vom System-Cursor
var _pointer := Vector2.ZERO

func _ready() -> void:
	_mon = State.mons[0]
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_slots.resize(SKILLS_TO_PICK)
	_slots.fill(null)
	_build()
	_place_preselected()
	resized.connect(_layout)
	_layout()
	_refresh()
	Tutorial.trigger("egg_configurator")

# ─────────────────────────
# Aufbau

func _build() -> void:
	_background = _image_layer(BACKGROUND, BACKGROUND_MATERIAL)
	add_child(_background)

	_monster = TextureRect.new()
	Monmap.show_on(_monster, _mon._name, Monmap.MEDIUM)
	_monster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_monster.stretch_mode = TextureRect.STRETCH_SCALE
	_mon_rect = _monster_rect(_monster.texture)
	_monster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_monster)

	# Tisch vor dem Monster; transparente Stellen dürfen keine Partikel werfen
	var table_material: ShaderMaterial = BACKGROUND_MATERIAL.duplicate()
	table_material.set_shader_parameter("alpha_cutoff", 0.5)
	_table = _image_layer(TABLE, table_material)
	add_child(_table)

	_slot_marks = Control.new()
	_slot_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_marks.draw.connect(_draw_slots)
	add_child(_slot_marks)

	# das Monsterbild hat durchsichtige Ränder: hervorgehoben wird nur der sichtbare Körper
	_mon_area = _tutorial_area("tut_cfg_mon")
	_table_area = _tutorial_area("tut_cfg_slots")
	_arc_area = _tutorial_area("tut_cfg_grid")

	# hinter den Karten: die aus der Truhe kommenden Karten fliegen darüber
	_chest_left = _chest_counter()
	_chest_right = _chest_counter()

	_card_layer = Control.new()
	_card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_card_layer)
	for skill_name in Skills.get_available_egg_skills(_mon._name):
		var entry := _add_entry(Skills.get_skill(skill_name), "", "")
		# wie die Attacke freigeschaltet wurde
		var source := Skills.get_egg_skill_source(_mon._name, skill_name)
		if not source.is_empty():
			entry.card.tooltip_text = tr(source[0]) + "\n" + tr(source[1])
	for skill_name in Skills.get_locked_egg_skills(_mon._name):
		_add_entry(Skills.get_skill(skill_name), "CONFIGURATOR_LOCKED", "EGG_SKILL_HINT")
	for milestone in Skills.get_locked_milestones(_mon._name):
		_add_entry(Skills.get_skill(milestone.skill), "CONFIGURATOR_LOCKED_MILESTONE", milestone.hint)
	for bounty in Skills.get_locked_bounties(_mon._name):
		_add_entry(Skills.get_skill(bounty.skill), "CONFIGURATOR_LOCKED_BOUNTY", bounty.hint)

	_bottom_row = HBoxContainer.new()
	_bottom_row.add_theme_constant_override("separation", 16)
	_counter_label = _label("", 22, TEXT_COLOR)
	var counter_panel := PanelContainer.new()
	counter_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	IronPlate.frame(counter_panel, _counter_label, 16, 10)
	# das Tutorial stellt Trainer und Sprechblase nicht darüber
	counter_panel.add_to_group("tut_keep_clear")
	_bottom_row.add_child(counter_panel)
	_go_button = RewardDialog.icon_button(GO_ICON)
	_go_button.tooltip_text = tr("CONFIGURATOR_GO")
	_go_button.focus_mode = Control.FOCUS_NONE
	_go_button.pressed.connect(_on_go_pressed)
	_go_button.add_to_group("tut_cfg_go")
	_bottom_row.add_child(_go_button)
	add_child(_bottom_row)

	_bubble = SpeechBubble.new(BUBBLE_WIDTH, false, true)
	add_child(_bubble)

## Bild so groß und so gelegt, dass sein sichtbarer Teil MON_HEIGHT hoch ist und unten mittig auf MON_FEET steht
func _monster_rect(texture: Texture2D) -> Rect2:
	var texture_size := texture.get_size() if texture else Vector2.ONE
	var used := Rect2(Vector2.ZERO, texture_size)
	var source := texture.get_image() if texture else null
	if source and not source.is_empty():
		if source.is_compressed():
			source = source.duplicate()
			source.decompress()
		var used_px := source.get_used_rect()
		if used_px.size != Vector2i.ZERO:
			# Bild kann in anderer Auflösung vorliegen als die Textur
			var k := texture_size / Vector2(source.get_size())
			used = Rect2(Vector2(used_px.position) * k, Vector2(used_px.size) * k)
	var fit := minf(MON_HEIGHT / used.size.y, MON_MAX_WIDTH / used.size.x)
	var feet := used.position + Vector2(used.size.x / 2.0, used.size.y)
	_mon_visible = Rect2(MON_FEET - Vector2(used.size.x / 2.0, used.size.y) * fit, used.size * fit)
	return Rect2(MON_FEET - feet * fit, texture_size * fit)

func _image_layer(texture: Texture2D, material_: Material) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.material = material_
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## Kleines Eisenschild auf einer Truhe: wie viele Karten noch darin liegen
func _chest_counter() -> Array:
	# leer, damit der erste Stand in _set_chest_count auf jeden Fall gesetzt wird
	var label := _label("", CHEST_COUNT_FONT_SIZE, TEXT_COLOR)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	IronPlate.frame(panel, label, 10, 4)
	RewardDialog.ignore_mouse_below(panel)
	add_child(panel)
	return [panel, label]

## Karten links bzw. rechts außerhalb des Bogens, je nach aktueller Scroll-Position
func _update_chest_counts(floating_count: int) -> void:
	var left := clampi(roundi(_scroll), 0, floating_count)
	var right := maxi(floating_count - left - VISIBLE, 0)
	_set_chest_count(_chest_left, left)
	_set_chest_count(_chest_right, right)

func _set_chest_count(counter: Array, count: int) -> void:
	var label: Label = counter[1]
	var text := "+%d" % count if count > 0 else "0"
	if label.text == text:
		return
	label.text = text
	var panel: PanelContainer = counter[0]
	panel.modulate.a = 1.0 if count > 0 else CHEST_EMPTY_ALPHA
	_place_chest_counter(counter, CHEST_COUNT_LEFT if counter == _chest_left else CHEST_COUNT_RIGHT)

func _place_chest_counter(counter: Array, at: Vector2) -> void:
	var panel: PanelContainer = counter[0]
	panel.reset_size()
	panel.position = _to_screen(at) - panel.size / 2.0

func _tutorial_area(group: String) -> Control:
	var area := Control.new()
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_to_group(group)
	add_child(area)
	return area

func _add_entry(skill: Dictionary, locked_label: String, hint: String) -> Entry:
	var entry := Entry.new()
	entry.name = skill.get("name", "")
	entry.locked_label = locked_label
	entry.hint = hint
	entry.card = EggSkillCard.create(skill, _mon, locked_label, hint)
	entry.card.set_title_size(15)
	entry.card.custom_minimum_size = CARD_SIZE
	entry.card.size = CARD_SIZE
	entry.card.pivot_offset = CARD_SIZE / 2
	entry.card.visible = false
	entry.card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	entry.card.gui_input.connect(_on_card_input.bind(entry))
	entry.card.mouse_entered.connect(func(): _hovered = entry)
	entry.card.mouse_exited.connect(func():
		if _hovered == entry:
			_hovered = null)
	_card_layer.add_child(entry.card)
	_entries.append(entry)
	return entry

## Im Tutorial bleibt der Tisch leer, der Spieler legt die Attacken selbst hin.
## Sonst die zuletzt für diese Art gewählten Attacken, Lücken füllen die beim Ei gewürfelten.
func _place_preselected() -> void:
	if Tutorial.should_show("egg_configurator"):
		return
	var preselect: Array = SaveManager.get_egg_loadout(_mon._name).duplicate()
	preselect.append_array(_mon._skills.map(func(skill): return skill.get("name", "")))
	var filled := 0
	for skill_name in preselect:
		if filled >= SKILLS_TO_PICK:
			break
		var entry := _find(skill_name)
		if entry == null or entry.locked() or entry.slot >= 0:
			continue
		entry.slot = filled
		_slots[filled] = entry
		filled += 1

func _find(skill_name: String) -> Entry:
	for entry in _entries:
		if entry.name == skill_name and not entry.locked():
			return entry
	return null

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

# ─────────────────────────
# Bildpixel -> Bildschirm

func _image_scale() -> float:
	return maxf(size.x / IMAGE_SIZE.x, size.y / IMAGE_SIZE.y)

func _to_screen(point: Vector2) -> Vector2:
	var s := _image_scale()
	return (size - IMAGE_SIZE * s) / 2.0 + point * s

func _rect_to_screen(rect: Rect2) -> Rect2:
	return Rect2(_to_screen(rect.position), rect.size * _image_scale())

func _layout() -> void:
	var image_rect := _rect_to_screen(Rect2(Vector2.ZERO, IMAGE_SIZE))
	_background.position = image_rect.position
	_background.size = image_rect.size
	var table_image := _rect_to_screen(Rect2(TABLE_PIVOT * (1.0 - TABLE_ZOOM), IMAGE_SIZE * TABLE_ZOOM))
	_table.position = table_image.position
	_table.size = table_image.size
	var mon_rect := _rect_to_screen(_mon_rect)
	_monster.position = mon_rect.position
	_monster.size = mon_rect.size
	var mon_area := _rect_to_screen(_mon_visible)
	_mon_area.position = mon_area.position
	_mon_area.size = mon_area.size
	# Tutorial-Loch um die drei Tischplätze, folgt SLOT_CENTERS von selbst
	var table_rect := _slot_rect(0)
	for i in range(1, SKILLS_TO_PICK):
		table_rect = table_rect.merge(_slot_rect(i))
	table_rect = table_rect.grow(6.0)
	_table_area.position = table_rect.position
	_table_area.size = table_rect.size
	var arc_rect := _rect_to_screen(ARC_AREA)
	_arc_area.position = arc_rect.position
	_arc_area.size = arc_rect.size
	_bubble.position = _to_screen(BUBBLE_AT)
	_place_chest_counter(_chest_left, CHEST_COUNT_LEFT)
	_place_chest_counter(_chest_right, CHEST_COUNT_RIGHT)
	_bottom_row.reset_size()
	var row_center := _to_screen(Vector2(IMAGE_SIZE.x / 2.0, BOTTOM_ROW_Y))
	_bottom_row.position = Vector2(row_center.x - _bottom_row.size.x / 2.0, minf(row_center.y - _bottom_row.size.y / 2.0, size.y - _bottom_row.size.y - 8.0))

func _slot_rect(index: int) -> Rect2:
	var card_size := CARD_SIZE * Vector2(1.0, LYING_SQUASH) * TABLE_SCALE * _image_scale()
	return Rect2(_to_screen(SLOT_CENTERS[index]) - card_size / 2.0, card_size)

# ─────────────────────────
# Bewegung

func _floating() -> Array[Entry]:
	var floating: Array[Entry] = []
	for entry in _entries:
		if entry.slot < 0:
			floating.append(entry)
	return floating

func _max_scroll() -> float:
	return maxf(_floating().size() - VISIBLE, 0)

func _arc_point(t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * ARC_START + 2.0 * u * t * ARC_CONTROL + t * t * ARC_END

func _arc_angle(t: float) -> float:
	var tangent := 2.0 * (1.0 - t) * (ARC_CONTROL - ARC_START) + 2.0 * t * (ARC_END - ARC_CONTROL)
	return tangent.angle() * ARC_TILT

func _process(delta: float) -> void:
	_time += delta
	if _mode != "swipe":
		_scroll = lerpf(_scroll, _scroll_target, 1.0 - exp(-SCROLL_SPEED * delta))
	var follow := 1.0 - exp(-FOLLOW_SPEED * delta)
	var s := _image_scale()
	var mouse := _pointer
	var floating := _floating()
	for entry in _entries:
		var target_center: Vector2
		var target_scale: float
		var target_rotation := 0.0
		var target_alpha := 1.0
		var target_squash := 1.0
		# zum Lesen groß: Maus darüber, oder Finger liegt still lange genug darauf
		var hovered := entry == _hovered and _mode == "" and not _pressing
		if _reading() and entry == _press_entry:
			hovered = true
		if _mode == "drag" and entry == _press_entry:
			target_center = mouse
			target_scale = DRAG_SCALE * s
			# beim Ziehen folgt die Karte dem Finger ohne Verzögerung
			entry.center = mouse
		elif entry.slot >= 0:
			target_center = _to_screen(SLOT_CENTERS[entry.slot])
			target_scale = (HOVER_SCALE if hovered else TABLE_SCALE) * s
			target_rotation = 0.0 if hovered else SLOT_TILT[entry.slot]
			# liegt auf dem Tisch, zum Lesen richtet sie sich auf
			target_squash = 1.0 if hovered else LYING_SQUASH
		else:
			# Platz im Bogen: 0 = in der linken Truhe, 1 = in der rechten
			var u := (floating.find(entry) - _scroll + 0.5) / VISIBLE
			var t := clampf(u, 0.0, 1.0)
			# an den Rändern schrumpft die Karte in die Truhe
			var edge := clampf(minf(u, 1.0 - u) * VISIBLE * 2.0, 0.0, 1.0)
			target_center = _to_screen(_arc_point(t))
			target_scale = (HOVER_SCALE if hovered and edge >= 1.0 else ARC_SCALE) * s * edge
			target_rotation = 0.0 if hovered else _arc_angle(t)
			target_alpha = edge
			if entry.alpha < 0.01 and edge > 0.0:
				# kommt aus der Truhe, auf deren Seite sie steht
				entry.center = _to_screen(ARC_START if u < 0.5 else ARC_END)
				entry.scale = 0.0
		if hovered:
			# vergrößert ganz im Bild bleiben
			var half := CARD_SIZE * target_scale / 2.0
			target_center = target_center.clamp(half, (size - half).max(half))
		entry.center = entry.center.lerp(target_center, follow)
		entry.scale = lerpf(entry.scale, target_scale, follow)
		entry.squash = lerpf(entry.squash, target_squash, follow)
		entry.rotation = lerp_angle(entry.rotation, target_rotation, follow)
		entry.alpha = lerpf(entry.alpha, target_alpha, follow) if target_alpha > 0.0 else move_toward(entry.alpha, 0.0, delta * 6.0)
		entry.shake = move_toward(entry.shake, 0.0, delta * SHAKE_DECAY)
		_apply(entry)
	_raise_on_top()
	_update_chest_counts(floating.size())
	_slot_marks.queue_redraw()

func _apply(entry: Entry) -> void:
	var card := entry.card
	var shake := Vector2(sin(_time * 50.0) * SHAKE_PIXELS * entry.shake, 0.0)
	card.position = entry.center - CARD_SIZE / 2.0 + shake
	card.scale = Vector2(1.0, entry.squash) * maxf(entry.scale, 0.001)
	card.rotation = entry.rotation
	card.modulate.a = clampf(entry.alpha, 0.0, 1.0)
	card.visible = entry.alpha > 0.01 and entry.scale > 0.02
	# halb in der Truhe lässt sich nichts greifen
	card.mouse_filter = Control.MOUSE_FILTER_STOP if entry.alpha > 0.6 else Control.MOUSE_FILTER_IGNORE

## Gezogene bzw. vergrößerte Karte liegt über den anderen
func _raise_on_top() -> void:
	var top: Entry = _press_entry if _mode == "drag" else _hovered
	if top and top.card.get_index() != _card_layer.get_child_count() - 1:
		_card_layer.move_child(top.card, -1)

## Schatten der liegenden Karten auf der Tischplatte, darüber die Umrisse freier Plätze
func _draw_slots() -> void:
	for entry: Entry in _slots:
		if entry == null or (_mode == "drag" and entry == _press_entry):
			continue
		var shadow_scale := Vector2(1.0, entry.squash) * entry.scale
		_slot_marks.draw_set_transform(entry.center + SHADOW_OFFSET * _image_scale(), entry.rotation, shadow_scale)
		_slot_marks.draw_rect(Rect2(-CARD_SIZE / 2.0, CARD_SIZE), Color(SHADOW_COLOR, SHADOW_COLOR.a * entry.alpha))
	_slot_marks.draw_set_transform(Vector2.ZERO)
	for i in SKILLS_TO_PICK:
		var highlighted := _mode == "drag" and _drop_slot == i
		if _slots[i] != null and not highlighted:
			continue
		var rect := _slot_rect(i)
		var alpha := 0.9 if highlighted else 0.35
		_slot_marks.draw_rect(rect, Color(GOLD, alpha * 0.25), true)
		_slot_marks.draw_rect(rect, Color(GOLD, alpha), false, 2.0)

# ─────────────────────────
# Eingabe

func _on_card_input(event: InputEvent, entry: Entry) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_start_press(entry, event.global_position)
		entry.card.accept_event()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_start_press(null, event.global_position)
		accept_event()

## Finger liegt still auf einer Karte, länger als für ein Antippen: Karte wird zum Lesen groß
func _reading() -> bool:
	return _pressing and _press_touch and _mode == "" and _press_entry != null \
			and Time.get_ticks_usec() - _press_usec >= LONG_PRESS_USEC

func _start_press(entry: Entry, at: Vector2) -> void:
	if _pressing:
		return
	_bubble.dismiss()
	_pressing = true
	_press_entry = entry
	_press_pos = at
	_press_usec = Time.get_ticks_usec()
	_press_touch = _touch_down_usec > 0
	_mode = ""

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.index == 0:
		_touch_down_usec = Time.get_ticks_usec() if event.pressed else 0
	if event is InputEventMouse:
		_pointer = get_global_transform().affine_inverse() * event.global_position
	if event is InputEventMouseButton and event.pressed and not _pressing \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_bubble.dismiss()
		_scroll_by(1.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0)
		get_viewport().set_input_as_handled()
		return
	if not _pressing:
		return
	if event is InputEventMouseMotion:
		_on_press_motion(event.global_position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_on_release()

func _on_press_motion(at: Vector2) -> void:
	var moved := at - _press_pos
	if _mode == "" and moved.length() > TAP_DISTANCE:
		var long_press := Time.get_ticks_usec() - _press_usec >= LONG_PRESS_USEC
		var entry := _press_entry
		if entry and entry.slot < 0 and _press_touch and not long_press:
			# Finger kurz aufgelegt und gleich gewischt: das scrollt den Bogen
			_start_swipe()
		elif entry and entry.locked():
			_mode = "blocked"
			_say_locked(entry)
		elif entry:
			_mode = "drag"
			_hovered = null
		else:
			_start_swipe()
	if _mode == "swipe":
		var spacing := (ARC_END.x - ARC_START.x) / VISIBLE * _image_scale()
		_scroll_target = clampf(_swipe_start_scroll - moved.x / spacing, 0.0, _max_scroll())
		_scroll = _scroll_target
	elif _mode == "drag":
		_drop_slot = _slot_at(_pointer)

func _start_swipe() -> void:
	_mode = "swipe"
	_swipe_start_scroll = _scroll_target

func _on_release() -> void:
	match _mode:
		"drag":
			_drop(_press_entry)
		"swipe":
			_scroll_target = clampf(roundf(_scroll_target), 0.0, _max_scroll())
		"":
			# nach langem Draufhalten (Lesen) zählt Loslassen nicht als Antippen
			if _press_entry and not _reading():
				_tap(_press_entry)
	_pressing = false
	_press_entry = null
	_mode = ""
	_drop_slot = -1

func _scroll_by(steps: float) -> void:
	_scroll_target = clampf(roundf(_scroll_target + steps), 0.0, _max_scroll())

## Tischplatz unter dem Punkt; irgendwo auf der Tischplatte zählt der nächstgelegene
func _slot_at(point: Vector2) -> int:
	for i in SKILLS_TO_PICK:
		if _slot_rect(i).grow(8.0).has_point(point):
			return i
	if not _rect_to_screen(TABLE_RECT).has_point(point):
		return -1
	var best := 0
	for i in SKILLS_TO_PICK:
		if absf(_to_screen(SLOT_CENTERS[i]).x - point.x) < absf(_to_screen(SLOT_CENTERS[best]).x - point.x):
			best = i
	return best

## Antippen: aus dem Bogen auf den ersten freien Platz, vom Tisch zurück in den Bogen
func _tap(entry: Entry) -> void:
	if entry.locked():
		_say_locked(entry)
		return
	if entry.slot >= 0:
		_take_off_table(entry)
	else:
		var free := _slots.find(null)
		if free < 0:
			return
		_put_on_table(entry, free)
	_refresh()

## Abgelegt auf einem Platz: die Karte kommt dorthin. Lag dort schon eine, fliegt sie zurück in den Bogen
## oder, kam die gezogene von einem anderen Platz, auf diesen (Tausch). Daneben losgelassen: vom Tisch
## gezogene fliegt zurück in den Bogen, aus dem Bogen gezogene an ihren Platz dort.
func _drop(entry: Entry) -> void:
	if _drop_slot < 0:
		if entry.slot >= 0:
			_take_off_table(entry)
	elif entry.slot != _drop_slot:
		var old: Entry = _slots[_drop_slot]
		var from := entry.slot
		if from >= 0:
			_slots[from] = null
		# die alte Karte zuerst vom Platz nehmen: _take_off_table leert ihren Platz, und der gehört danach der neuen
		if old and from < 0:
			_take_off_table(old)
		_put_on_table(entry, _drop_slot)
		if old and from >= 0:
			_put_on_table(old, from)
	_refresh()

func _put_on_table(entry: Entry, slot: int) -> void:
	var index := _floating().find(entry)
	entry.slot = slot
	_slots[slot] = entry
	# der Bogen rückt nach, ohne dass die Karten dahinter springen
	if index >= 0 and index < _scroll_target:
		_scroll_target -= 1.0
		_scroll -= 1.0
	_scroll_target = clampf(_scroll_target, 0.0, _max_scroll())

## Zurück in den Bogen, der dorthin scrollt, wo sie in der Reihenfolge hingehört
func _take_off_table(entry: Entry) -> void:
	_slots[entry.slot] = null
	entry.slot = -1
	var index := _floating().find(entry)
	if index < _scroll_target:
		_scroll_target = index
	elif index > _scroll_target + VISIBLE - 1:
		_scroll_target = index - VISIBLE + 1
	_scroll_target = clampf(_scroll_target, 0.0, _max_scroll())

## Gesperrte Attacke angeklickt oder gezogen: das Monster sagt, wie man sie freischaltet
func _say_locked(entry: Entry) -> void:
	if _selected_locked:
		_selected_locked.card.set_selected(false)
	_selected_locked = entry
	entry.card.set_selected(true)
	entry.shake = 1.0
	_bubble.say(tr(entry.locked_label) + "\n" + tr(entry.hint))

# ─────────────────────────
# Aufbruch

func _selected() -> Array[String]:
	var names: Array[String] = []
	for entry in _slots:
		if entry != null:
			names.append(entry.name)
	return names

func _refresh() -> void:
	var selected := _selected()
	# mindestens eine Attacke muss mit dem Start-Element spielbar sein
	var has_usable = selected.any(func(skill_name): return Skills.can_use_name(_mon, skill_name))
	_counter_label.text = tr("CONFIGURATOR_COUNTER").format({"count": selected.size(), "max": SKILLS_TO_PICK})
	if selected.size() == SKILLS_TO_PICK and not has_usable:
		_counter_label.text = tr("CONFIGURATOR_NEED_USABLE")
	_go_button.disabled = selected.size() != SKILLS_TO_PICK or not has_usable
	if is_node_ready():
		_layout.call_deferred()
	if selected.size() == SKILLS_TO_PICK:
		Events.egg_loadout_complete.emit()

func _on_go_pressed() -> void:
	SaveManager.set_egg_loadout(_mon._name, _selected())
	_mon._skills = []
	for skill_name in _selected():
		var skill = Skills.get_skill(skill_name)
		if skill.is_empty():
			continue
		skill.scouted = true
		_mon._skills.append(skill)
	# mit Tutorial erst der Übungskampf, er führt danach zur Karte
	if Tutorial.wants_practice():
		Tutorial.start_practice()
		return
	# die Karte braucht beim ersten Mal etwas: solange füllen sich die Wellen als Lade-Anzeige
	SceneLoader.change_scene("res://script/scenes/world_map/world_map.tscn")
