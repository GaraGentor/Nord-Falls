class_name TutorialOverlay
extends CanvasLayer

## Spielt eine Tutorial-Sequenz ab (siehe Tutorial.SEQUENCES): dunkelt alles ab bis auf die Ziele.
## Gesprochen wird in einer Sprechblase, entweder von einem NPC unten in der Ecke (Tutorial.SPEAKERS)
## oder, mit speaker "npc", vom NPC der Szene selbst (Gruppe "tut_npc"): er bleibt hell, die Blase steht an seinem Kopf.
## Klicks gehen nur durch die Löcher, und auch nur, wenn der Schritt das erlaubt (Aktion des Spielers, "free" oder "open").

signal finished
signal skipped

const SPOTLIGHT = preload("res://script/ui/tutorial/tutorial_spotlight.gdshader")
const FONT_THEME = preload("res://script/ui/materials/pixel_font_theme.tres")
const GOLD := SkillDetailPopup.GOLD
const LAYER := 100
## so viele Zielgruppen hebt der Shader einzeln hervor, weitere werden mit der letzten zusammengefasst
const MAX_HOLES := 6
const SPEAKER_SIZE := Vector2(240, 360)
const SPEAKER_PIXEL_SCALE := 0.5
## NPC der Szene als Sprecher: die Blase steht auf dieser Höhe seines Bildes
const NPC_MOUTH := 0.2
const BUBBLE_WIDTH := 380.0
## Abstand der Blase zum NPC und Höhe über dessen Oberkante
const BUBBLE_GAP := 8.0
const BUBBLE_DROP := 40.0
## Aufschlag pro Ausweichstelle der Blase, in verdeckter Fläche (Pixel²): etwa ein 40 Pixel hoher Streifen
const CANDIDATE_PENALTY := BUBBLE_WIDTH * 40.0
## Aufschlag pro Ausweichstelle des Porträts (unten, Mitte, oben; bevorzugte Seite zuerst)
const SPEAKER_PENALTY := SPEAKER_SIZE.x * 20.0
## Gewicht verdeckter Fläche: Ziele und übrige Knöpfe der Szene (der Hintergrund zählt 0).
## Ziele zählen so viel, dass jede Stelle ohne Überdeckung gewinnt, wenn es eine gibt: das Tutorial bleibt frei.
const HOLE_WEIGHT := 200.0
const BUTTON_WEIGHT := 4.0
## Ausweichstellen der Blase in den Ecken und Randmitten, wenn neben dem Sprecher kein Platz ist: Aufschlag
const FALLBACK_PENALTY := CANDIDATE_PENALTY * 4.0
## Laufende Neuberechnung (Knöpfe bewegen sich, z. B. beim Scrollen der Karte): Porträt und Blase bleiben stehen,
## solange eine andere Stelle nicht deutlich weniger verdeckt. Sonst springen sie hin und her.
const STICKY_PENALTY := BUBBLE_WIDTH * 120.0
## so oft wird nachgesehen, ob Knöpfe der Szene erschienen oder verschwunden sind
const BUTTONS_REFRESH_SECONDS := 0.25
## so viel größer als das Ziel ist das Loch
const HOLE_PADDING := 8.0
const FADE_SECONDS := 0.25
const DIM := Color(0, 0, 0, 0.65)
## bei offenen Schritten muss der Rest gut sichtbar bleiben
const OPEN_DIM := Color(0, 0, 0, 0.25)
const SKIP_FONT_SIZE := 24
const NEXT_FONT_SIZE := 32

## Fläche über allem, schluckt Klicks außerhalb der Löcher
class Blocker extends Control:
	var holes: Array[Rect2] = []
	## der sprechende NPC der Szene: oft selbst ein Ziel zum Ablegen (Essenz ins Feuer, Träne zum Kerkermeister)
	var npc_rect := Rect2()
	var hole_clickable := false
	## alles bleibt bedienbar, die Löcher zeigen nur, worauf es ankommt
	var open := false

	func lets_through(point: Vector2) -> bool:
		return open or (hole_clickable and (npc_rect.has_point(point)
			or holes.any(func(hole: Rect2): return hole.has_point(point))))

	func _has_point(point: Vector2) -> bool:
		return not lets_through(point)

var _steps: Array = []
var _index := -1
var _scene: Node
var _blocker: Blocker
var _spotlight: ShaderMaterial
## Porträt in der Ecke, bei speaker "npc" unsichtbar
var _speaker: TextureRect
var _npc_speaks := false
var _box: VBoxContainer
var _bubble: SpeechBubble
var _next_button: Button
## Sprecher steht rechts (sonst links), die Blase steht auf seiner anderen Seite
var _speaker_right := true
## alle Löcher zusammen, für die Wahl der Seite
var _bounds := Rect2()
## Verbindungen, auf die der aktuelle Schritt wartet: [[Signal, Callable], ...]
var _waiting: Array = []
var _presses_left := 0
## sichtbare Knöpfe der Szene beim Beginn des Schritts: Porträt und Blase sollen sie nicht verdecken
var _scene_buttons: Array = []
var _buttons_timer := 0.0
## Porträt würde überall ein Ziel verdecken und bleibt deshalb weg (_place_speaker)
var _speaker_hidden := false

func _init() -> void:
	layer = LAYER

func start(sequence: Dictionary, scene: Node) -> void:
	_steps = sequence.steps
	_scene = scene
	_npc_speaks = sequence.speaker == "npc"
	_build(Tutorial.SPEAKERS.get(sequence.speaker, {}))
	get_viewport().size_changed.connect(_layout)
	_blocker.modulate.a = 0.0
	create_tween().tween_property(_blocker, "modulate:a", 1.0, FADE_SECONDS)
	_show_step(0)

## Lässt ein Klick an dieser Stelle durch? Für Szenen, die Mausklicks selbst in _input auswerten.
func lets_through(point: Vector2) -> bool:
	return _blocker.lets_through(point)

func _build(speaker: Dictionary) -> void:
	_blocker = Blocker.new()
	_blocker.theme = FONT_THEME
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_blocker)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spotlight = ShaderMaterial.new()
	_spotlight.shader = SPOTLIGHT
	_spotlight.set_shader_parameter("border_color", GOLD)
	dim.material = _spotlight
	_blocker.add_child(dim)

	_speaker = TextureRect.new()
	_speaker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_speaker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_speaker.size = SPEAKER_SIZE
	_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speaker.visible = not _npc_speaks
	if not _npc_speaks:
		_speaker.texture = load(speaker.texture)
		# eigene Kopie: die NPC-Szene schaltet am selben Material den goldenen Umriss.
		# Der NPC ist hier etwa halb so groß wie in seiner Szene, mit halben Pixeln wirkt er gleich grob.
		var material: ShaderMaterial = load(speaker.material).duplicate()
		material.set_shader_parameter("pixel_size", material.get_shader_parameter("pixel_size") * SPEAKER_PIXEL_SCALE)
		_speaker.material = material
	_blocker.add_child(_speaker)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_blocker.add_child(_box)
	# die Höhe steht erst fest, wenn der Text umgebrochen ist
	_box.minimum_size_changed.connect(_layout)
	# zwei eigene Knöpfe unter der Blase: Überspringen links, Weiter rechts
	var buttons := HBoxContainer.new()
	_box.add_child(buttons)
	var skip_button := _button(tr("TUTORIAL_SKIP"), SKIP_FONT_SIZE, IronPlate.TEXT_COLOR)
	skip_button.pressed.connect(_on_skip_pressed)
	buttons.add_child(skip_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.add_child(spacer)
	_next_button = _button(tr("TUTORIAL_NEXT"), NEXT_FONT_SIZE, GOLD)
	_next_button.pressed.connect(_next)
	buttons.add_child(_next_button)

## Text-Knopf auf eigener Eisenplatte, damit er auch über einem hellen Ziel lesbar bleibt
func _button(text: String, font_size: int, color: Color) -> Button:
	var button := RewardDialog.plate_button(text)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", color)
	return button

func _show_step(index: int) -> void:
	_stop_waiting()
	_index = index
	var step: Dictionary = _steps[index]
	if step.get("if_present", false) and _find_all(_first_target(step)).is_empty():
		_next()
		return
	var wait: String = step.get("wait", "next")
	# "dismiss": der Schritt wartet auf eine Aktion, Weiter beendet die Sequenz aber auch und blendet den Trainer aus
	_next_button.visible = wait == "next" or step.get("dismiss", false)
	_blocker.hole_clickable = wait != "next" or step.get("free", false)
	_blocker.open = step.get("open", false)
	_spotlight.set_shader_parameter("dim_color", OPEN_DIM if _blocker.open else DIM)
	if wait.begins_with("pressed:"):
		_presses_left = step.get("count", 1)
		_wait_for_buttons(wait.trim_prefix("pressed:"), index)
	elif wait.begins_with("signal:"):
		_wait_for_signal(wait.trim_prefix("signal:"))
	_update_holes()
	_scene_buttons = _visible_buttons()
	if _npc_speaks:
		_speaker_right = _choose_speaker_side()
	else:
		_place_speaker(false)
	# die Blase wird pro Schritt neu gebaut, ihr Zipfel zeigt immer zum Sprecher
	if _bubble:
		_bubble.queue_free()
	_bubble = SpeechBubble.new(BUBBLE_WIDTH, true, not _speaker_right)
	_box.add_child(_bubble)
	_box.move_child(_bubble, 0)
	# offene Schritte: der Spieler braucht den ganzen Bildschirm, das Porträt tritt zurück und die Blase steht am Ziel
	_speaker.visible = _speaker_shown()
	_bubble.say(tr(step.text).format(Tutorial.text_values()))
	_layout()

## Der NPC der Szene steht, wo er steht: die Blase kommt auf die Seite zur Bildmitte
func _choose_speaker_side() -> bool:
	var npc := _npc()
	return npc == null or _rect_of(npc).get_center().x >= _blocker.size.x / 2

## Porträt an den Rand stellen, wo es am wenigsten Ziele und Knöpfe verdeckt: bevorzugt unten auf der Seite
## ohne Ziel, sonst auf der anderen Seite, sonst in der Mitte oder oben am Rand.
## Verdeckt es auch dort ein Ziel, tritt das Porträt zurück und nur die Blase bleibt.
## keep_side: Seite bleibt (z. B. bei Größenänderung, der Zipfel der Blase zeigt schon dorthin)
## sticky: die jetzige Stelle bleibt, solange keine andere deutlich besser ist
func _place_speaker(keep_side: bool, sticky := false) -> void:
	var screen := _blocker.size
	var preferred := _speaker_right if keep_side else (_bounds.size.x <= 0.0 or _bounds.get_center().x < screen.x / 2)
	var forced := _forced_side()
	if forced != "":
		preferred = forced == "right"
	var sides: Array[bool] = [preferred]
	if not keep_side and forced == "":
		sides.append(not preferred)
	var current := _speaker.position
	var best_cost := INF
	var index := 0
	for y in [screen.y - SPEAKER_SIZE.y, (screen.y - SPEAKER_SIZE.y) / 2.0, 0.0]:
		for right in sides:
			var position := Vector2(screen.x - SPEAKER_SIZE.x if right else 0.0, y)
			var cost := _covered_area(Rect2(position, SPEAKER_SIZE), false) + index * SPEAKER_PENALTY
			if sticky and not position.is_equal_approx(current):
				cost += STICKY_PENALTY
			index += 1
			if cost < best_cost:
				best_cost = cost
				_speaker.position = position
				_speaker_right = right
	_speaker_hidden = _covers_hole(_speaker.get_rect())
	_speaker.visible = _speaker_shown()

## Porträt in der Ecke: nicht bei sprechendem NPC der Szene, bei offenen Schritten und wenn es ein Ziel verdecken würde
func _speaker_shown() -> bool:
	return not _npc_speaks and not _blocker.open and not _speaker_hidden

func _covers_hole(rect: Rect2) -> bool:
	return _blocker.holes.any(func(hole: Rect2): return rect.intersects(hole))

## Knöpfe der Szene und alles, was sie in die Gruppe "tut_keep_clear" legt (z. B. Anzeigen neben Knöpfen)
func _visible_buttons() -> Array:
	if _scene == null:
		return []
	var nodes := _scene.find_children("*", "BaseButton", true, false)
	nodes.append_array(get_tree().get_nodes_in_group("tut_keep_clear"))
	return nodes.filter(func(node): return node is Control and node.is_visible_in_tree())

## Wartet auf alle sichtbaren Knöpfe der Gruppe (z. B. jedes Startfeld der Karte).
## Entstehen sie erst später (Szene baut sich noch auf), wird beim nächsten Frame erneut gesucht.
func _wait_for_buttons(group: String, index: int) -> void:
	var buttons := _find_all(group).filter(func(node): return node is BaseButton)
	if buttons.is_empty():
		await get_tree().process_frame
		if is_inside_tree() and _index == index:
			_wait_for_buttons(group, index)
		return
	for button: BaseButton in buttons:
		_connect(button.pressed, _on_target_pressed)

func _wait_for_signal(signal_name: String) -> void:
	var arg_count := 0
	for info: Dictionary in Events.get_signal_list():
		if info.name == signal_name:
			arg_count = info.args.size()
	_connect(Signal(Events, signal_name), _next.unbind(arg_count) if arg_count > 0 else _next)

func _connect(sig: Signal, callable: Callable) -> void:
	sig.connect(callable)
	_waiting.append([sig, callable])

func _stop_waiting() -> void:
	for connection: Array in _waiting:
		var sig: Signal = connection[0]
		if not sig.is_null() and sig.is_connected(connection[1]):
			sig.disconnect(connection[1])
	_waiting = []

func _on_target_pressed() -> void:
	_presses_left -= 1
	if _presses_left <= 0:
		_next()

func _next() -> void:
	if _index + 1 < _steps.size():
		_show_step(_index + 1)
	else:
		_close()
		finished.emit()

## Tutorial.ask_skip fragt nach; bleibt man, läuft die Sequenz an derselben Stelle weiter
func _on_skip_pressed() -> void:
	skipped.emit()

## Dialoge aus dem Tutorial (Rückfrage beim Überspringen) liegen eine Ebene über dem Overlay
func dialog_host() -> Node:
	return _blocker

func _close() -> void:
	_stop_waiting()
	queue_free()

## Gehört die Sequenz zu einer Szene, die schon verlassen wurde?
func is_stale() -> bool:
	# gestartet aus _ready einer Szene, die beim Szenenwechsel noch nicht current_scene war: sie gehört dazu
	if _scene == null:
		_scene = get_tree().current_scene
		return false
	return get_tree().current_scene != _scene and get_tree().current_scene != null

func _process(delta: float) -> void:
	# Szene wurde verlassen, bevor die Sequenz fertig war: abbrechen, sie kommt beim nächsten Mal wieder
	if is_stale():
		_close()
		return
	# Ziele können sich bewegen (fallende Eier, Scrollen), daher jedes Frame neu
	_update_holes()
	if _npc_speaks:
		_layout()
		return
	# Knöpfe können während des Schritts erscheinen (z. B. "Reise beginnen" nach dem Ausbrüten): Porträt weicht aus
	_buttons_timer -= delta
	if _buttons_timer <= 0.0:
		_buttons_timer = BUTTONS_REFRESH_SECONDS
		_scene_buttons = _visible_buttons()
		_layout(true)

func _update_holes() -> void:
	if _index < 0:
		return
	var targets = _steps[_index].get("target", [])
	if targets is String:
		targets = [targets]
	# ein Loch pro Gruppe um alle ihre Mitglieder (z. B. Regalbrett samt Ware)
	var holes: Array[Rect2] = []
	for group: String in targets:
		var members := _find_all(group)
		if members.is_empty():
			continue
		var rect := _rect_of(members[0])
		for member in members.slice(1):
			rect = rect.merge(_rect_of(member))
		rect = rect.grow(HOLE_PADDING)
		if holes.size() < MAX_HOLES:
			holes.append(rect)
		else:
			holes[-1] = holes[-1].merge(rect)
	_blocker.holes = holes
	_bounds = Rect2()
	var packed := PackedVector4Array()
	packed.resize(MAX_HOLES)
	for i in holes.size():
		_bounds = holes[i] if i == 0 else _bounds.merge(holes[i])
		packed[i] = Vector4(holes[i].position.x, holes[i].position.y, holes[i].size.x, holes[i].size.y)
	_spotlight.set_shader_parameter("holes", packed)
	_spotlight.set_shader_parameter("hole_count", holes.size())
	var npc := _npc() if _npc_speaks else null
	var npc_rect := _rect_of(npc) if npc else Rect2()
	_blocker.npc_rect = npc_rect
	_spotlight.set_shader_parameter("npc_hole", Vector4(npc_rect.position.x, npc_rect.position.y, npc_rect.size.x, npc_rect.size.y))
	_spotlight.set_shader_parameter("rect_size", _blocker.size)

## sticky: laufende Neuberechnung, Porträt und Blase bleiben stehen, solange keine andere Stelle deutlich besser ist
func _layout(sticky := false) -> void:
	var screen := _blocker.size
	_box.reset_size()
	_box.size.x = BUBBLE_WIDTH
	var anchor: Rect2
	var top: float
	if _npc_speaks:
		var npc := _npc()
		anchor = _rect_of(npc) if npc else Rect2(screen.x, screen.y / 2, 0, 0)
		top = anchor.position.y + anchor.size.y * NPC_MOUTH
	else:
		_place_speaker(true, sticky)
		anchor = _speaker.get_rect()
		top = anchor.position.y + BUBBLE_DROP
	# der Zipfel zeigt zum Sprecher, ohne Porträt hat er nichts zu zeigen
	if _bubble:
		for child in _bubble.get_children():
			if child is Node2D:
				child.visible = _npc_speaks or _speaker.visible
	var x := anchor.position.x - BUBBLE_WIDTH - BUBBLE_GAP if _speaker_right else anchor.end.x + BUBBLE_GAP
	var above_x := anchor.end.x - BUBBLE_WIDTH if _speaker_right else anchor.position.x
	var max_x := screen.x - BUBBLE_WIDTH - BUBBLE_GAP
	var max_y := screen.y - _box.size.y - BUBBLE_GAP
	if _blocker.open and not _npc_speaks and _bounds.size.x > 0.0:
		_box.position = Vector2(clampf(_bounds.end.x - BUBBLE_WIDTH, BUBBLE_GAP, max_x),
			clampf(_bounds.position.y - _box.size.y - BUBBLE_GAP, BUBBLE_GAP, max_y))
		return
	# neben dem Sprecher auf Mundhöhe, knapp über den Knöpfen darunter, ganz oben, ganz unten oder über ihm:
	# die Stelle, die am wenigsten Ziele und Knöpfe verdeckt
	var candidates: Array[Vector2] = [
		Vector2(x, top),
		Vector2(x, _above_buttons(x, top) - _box.size.y - BUBBLE_GAP),
		Vector2(x, BUBBLE_GAP),
		Vector2(x, max_y),
		Vector2(above_x, anchor.position.y - _box.size.y),
	]
	var near := candidates.size()
	# kein Platz beim Sprecher: Ecken und Randmitten des Bildschirms, damit die Blase nie ein Ziel verdeckt
	var middle_x := (screen.x - BUBBLE_WIDTH) / 2.0
	var middle_y := (screen.y - _box.size.y) / 2.0
	for spot: Vector2 in [Vector2(BUBBLE_GAP, BUBBLE_GAP), Vector2(max_x, BUBBLE_GAP), Vector2(middle_x, BUBBLE_GAP),
			Vector2(BUBBLE_GAP, max_y), Vector2(max_x, max_y), Vector2(middle_x, max_y),
			Vector2(BUBBLE_GAP, middle_y), Vector2(max_x, middle_y)]:
		candidates.append(spot)
	for i in candidates.size():
		candidates[i] = candidates[i].clamp(Vector2(BUBBLE_GAP, BUBBLE_GAP), Vector2(max_x, max_y))
	# Schritt mit fester Seite ("bubble"): nur Stellen auf dieser Bildschirmhälfte
	var forced := _forced_side()
	if forced != "":
		var on_side := func(spot: Vector2) -> bool:
			var center_x := spot.x + BUBBLE_WIDTH / 2.0
			return center_x >= screen.x / 2.0 if forced == "right" else center_x < screen.x / 2.0
		var kept := candidates.filter(on_side)
		if not kept.is_empty():
			near = candidates.slice(0, near).filter(on_side).size()
			candidates.assign(kept)
	var current := _box.position
	var best := candidates[0]
	var best_cover := INF
	for i in candidates.size():
		var candidate := candidates[i]
		# frühere Stellen sind näher am Sprecher und gewinnen, solange sie nicht deutlich mehr verdecken
		var penalty := i * CANDIDATE_PENALTY if i < near else near * CANDIDATE_PENALTY + FALLBACK_PENALTY
		var cover := _covered_area(Rect2(candidate, _box.size), true) + penalty
		if sticky and not candidate.is_equal_approx(current):
			cover += STICKY_PENALTY
		if cover < best_cover:
			best = candidate
			best_cover = cover
	_box.position = best

## Oberkante des obersten Knopfs unterhalb von from_y, der in der Spalte der Blase (ab x) liegt; sonst der Bildschirmrand
func _above_buttons(x: float, from_y: float) -> float:
	var limit := _blocker.size.y
	# ohne festen Typ: ein inzwischen gelöschter Knopf (z. B. aus dem geschlossenen Debug-Menü) würde sonst schon
	# bei der Zuweisung abstürzen, bevor is_instance_valid greift
	for button in _scene_buttons:
		if not is_instance_valid(button):
			continue
		var rect := _rect_of(button)
		if rect.position.y > from_y and rect.end.x > x and rect.position.x < x + BUBBLE_WIDTH:
			limit = minf(limit, rect.position.y)
	return limit

## Wie viel das Rechteck verdeckt: Ziele zählen HOLE_WEIGHT-fach, übrige Knöpfe der Szene BUTTON_WEIGHT-fach.
## with_speaker: das Porträt zählt wie ein Ziel (für die Blase)
func _covered_area(rect: Rect2, with_speaker: bool) -> float:
	var area := 0.0
	for hole in _blocker.holes:
		area += rect.intersection(hole).get_area() * HOLE_WEIGHT
	for button in _scene_buttons:
		if is_instance_valid(button):
			area += rect.intersection(_rect_of(button)).get_area() * BUTTON_WEIGHT
	if with_speaker and _speaker.visible:
		area += rect.intersection(_speaker.get_rect()).get_area() * HOLE_WEIGHT
	return area

## Gibt der aktuelle Schritt das Ziel frei (es ist ein Ziel und der Schritt wartet auf eine Aktion, "free" oder "open")?
func step_allows(group: String) -> bool:
	if _index < 0 or _index >= _steps.size():
		return false
	if _blocker.open:
		return true
	var targets = _steps[_index].get("target", [])
	if targets is String:
		targets = [targets]
	return _blocker.hole_clickable and targets.has(group)

## Soll die Szene "tut_<group>" während des aktuellen Schritts ausblenden ("hide" des Schritts)?
func step_hides(group: String) -> bool:
	if _index < 0 or _index >= _steps.size():
		return false
	var hidden = _steps[_index].get("hide", [])
	if hidden is String:
		hidden = [hidden]
	return hidden.has(group)

## "bubble" des aktuellen Schritts: "right" / "left" hält Trainer und Blase auf dieser Seite, sonst leer
func _forced_side() -> String:
	if _index < 0 or _index >= _steps.size():
		return ""
	return _steps[_index].get("bubble", "")

func _first_target(step: Dictionary) -> String:
	var targets = step.get("target", "")
	if targets is Array:
		return targets[0] if not targets.is_empty() else ""
	return targets

func _npc() -> Control:
	var npcs := _find_all("npc")
	return npcs[0] if not npcs.is_empty() else null

## Alle sichtbaren Controls der Gruppe "tut_<group>"
func _find_all(group: String) -> Array:
	return get_tree().get_nodes_in_group("tut_" + group).filter(
		func(node): return node is Control and node.is_visible_in_tree())

## Bildschirm-Rechteck eines Controls, auch wenn es auf einer eigenen CanvasLayer liegt
func _rect_of(control: Control) -> Rect2:
	var xf := control.get_global_transform_with_canvas()
	return Rect2(xf.origin, control.size * xf.get_scale())
