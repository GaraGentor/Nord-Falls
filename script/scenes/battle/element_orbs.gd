class_name ElementOrbs
extends Control

## Schwebende Element-Kugeln neben einem eigenen Monster im Kampf (Element-Leihgabe, ElementLoan).
##   > eigene Elemente: auf den Partner ziehen, wenn er am Zug ist. Beim Ziehen zeigen seine Karten schon die Wirkung.
##   > verliehenes eigenes Element: nur als leerer Ring, solange der Partner es hat
##   > geliehene Elemente des Partners: mit weißem Ring, anklicken gibt sie zurück (Aktion kommt zurück)
##   > "-N": so viele Aktionen fehlen diesem Monster im nächsten Zug

const ORB_SIZE := 34.0
## Höhe einer Kugel im Verhältnis zur Breite (Platz für den Schweif)
const ORB_HEIGHT := 1.75
## Radius des Körpers im Verhältnis zur Breite
const BODY_SHARE := 0.28
## Länge des Schweifs in Körper-Radien, Anzahl der Kreise, aus denen er besteht
const TAIL_LENGTH := 2.9
const TAIL_STEPS := 18
const ORB_GAP := 4.0
const DEBT_COLOR := Color(1.0, 0.45, 0.4)
## Aktions-Raute mit "-1" (MovesBadge), etwas kleiner als an den Bildern im Infobereich
const DEBT_BADGE_SIZE := Vector2(36, 33)

var _scene: Control
## Reihe der Kugeln über dem Kopf des Monsters
var _column: HBoxContainer
var _debt_badge: MovesBadge

func _init(scene: Control) -> void:
	_scene = scene
	mouse_filter = MOUSE_FILTER_IGNORE
	_column = HBoxContainer.new()
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.mouse_filter = MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override("separation", int(ORB_GAP))
	add_child(_column)

func _ready() -> void:
	Events.element_loans_changed.connect(_rebuild)
	Events.monster_status_changed.connect(func(_mon): _rebuild())
	_rebuild()

func _mon() -> Monster:
	return _scene.mon

## Nur neu aufbauen, wenn sich etwas Sichtbares geändert hat: sonst verschwände die gerade gezogene Kugel
## (die Vorschau beim Ziehen meldet sich auch über element_loans_changed)
var _shown := ""

func _rebuild() -> void:
	if not is_inside_tree():
		return
	var mon := _mon()
	var signature := ""
	if mon != null and mon.is_alive():
		signature = "%d|%s|%s|%d" % [mon._type, _lent_elements(mon), mon._loans.map(func(loan): return loan.element),
			mon._loan_debt]
	if signature == _shown:
		return
	_shown = signature
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	_debt_badge = null
	if signature == "":
		return
	var lent := _lent_elements(mon)
	for element in ElementGlyph.elements_of(mon._type):
		var orb := Orb.new(element, mon)
		orb.ghost = lent.has(element)
		_column.add_child(orb)
	for loan in mon._loans:
		var orb := Orb.new(loan.element, mon)
		orb.borrowed = true
		_column.add_child(orb)
	if mon._loan_debt > 0:
		# "-1" auf der Aktions-Raute (wie die Züge auf der Karte im Infobereich), damit klar ist: es fehlen Aktionen
		_debt_badge = load(MovesBadge.SCENE_PATH).instantiate()
		_debt_badge.custom_minimum_size = DEBT_BADGE_SIZE
		_debt_badge.size_flags_vertical = Control.SIZE_SHRINK_END
		_column.add_child(_debt_badge)
		_debt_badge.show_number(-mon._loan_debt, true)
		_debt_badge.label.add_theme_color_override("font_color", DEBT_COLOR)
		_debt_badge.tooltip_text = tr("LOAN_DEBT_TOOLTIP").format({"count": mon._loan_debt})

## Elemente dieses Monsters, die gerade ein Partner geliehen hat
func _lent_elements(mon: Monster) -> Array:
	var lent := []
	for other: Monster in State.mons + State.enemy_mons:
		for loan in other._loans:
			if loan.from == mon:
				lent.append(loan.element)
	return lent

## Reihe mittig über dem Status (Schild, Buffs) im sonst leeren Streifen, wo bei Gegnern die Absicht steht.
## Unterkante der Reihe = Oberkante des Status, die Schweife ragen nach oben.
func _process(_delta: float) -> void:
	# neues Monster auf dem Platz (Endboss-Relikt Buddy) oder K.O.: baut nur neu, wenn sich etwas geändert hat
	_rebuild()
	var texture_rect: TextureRect = _scene.texture_rect
	if texture_rect == null or texture_rect.texture == null:
		return
	var rect_size := texture_rect.size
	var tex_size := texture_rect.texture.get_size()
	var scale_factor := minf(rect_size.x / tex_size.x, rect_size.y / tex_size.y)
	var drawn := tex_size * scale_factor
	var origin: Vector2 = _scene._texture_offset() + (rect_size - drawn) / 2
	_column.size = _column.get_combined_minimum_size()
	var status: Control = _scene.status_box
	var status_top: float = status.global_position.y - _scene.global_position.y
	position = Vector2(origin.x + (drawn.x - _column.size.x) / 2, status_top - _column.size.y - 2.0)


## Eine Kugel: Grundelement in seiner Farbe mit kleiner Flamme, schwebt leicht auf und ab
class Orb extends Control:
	var element: int
	## Monster, bei dem die Kugel gerade schwebt
	var owner_mon: Monster
	## eigenes Element, das gerade verliehen ist: nur ein leerer Ring
	var ghost := false
	## vom Partner geliehen: weißer Ring, anklicken gibt es zurück
	var borrowed := false
	var _time := 0.0
	var _seed := 0.0
	var _color: Color

	func _init(orb_element: int, mon: Monster) -> void:
		element = orb_element
		owner_mon = mon
		custom_minimum_size = Vector2(ElementOrbs.ORB_SIZE, ElementOrbs.ORB_SIZE * ElementOrbs.ORB_HEIGHT)
		_seed = randf() * TAU
		_time = _seed
		_color = Color(Helper.color_by_type(element))

	func _ready() -> void:
		var label := tr(ColorMap.get_combo(element).label)
		if not State.mons.has(owner_mon):
			# Gegner: nur zum Anschauen
			tooltip_text = tr("LOAN_LENT_TOOLTIP").format({"element": label}) if ghost else label
			mouse_filter = MOUSE_FILTER_PASS
		elif ghost:
			tooltip_text = tr("LOAN_LENT_TOOLTIP").format({"element": label})
			mouse_filter = MOUSE_FILTER_PASS
		elif borrowed:
			tooltip_text = tr("LOAN_BORROWED_TOOLTIP").format({"element": label})
			mouse_filter = MOUSE_FILTER_STOP
			mouse_default_cursor_shape = CURSOR_POINTING_HAND
		else:
			tooltip_text = tr("LOAN_ORB_TOOLTIP").format({"element": label})
			mouse_filter = MOUSE_FILTER_STOP

	## Darf diese Kugel gerade auf das Monster am Zug gezogen werden?
	func can_lend() -> bool:
		return not ghost and not borrowed and ElementLoan.can_borrow(ElementLoan.active, owner_mon, element)

	func _process(delta: float) -> void:
		_time += delta
		mouse_default_cursor_shape = CURSOR_DRAG if can_lend() else CURSOR_ARROW
		if borrowed:
			mouse_default_cursor_shape = CURSOR_POINTING_HAND
		queue_redraw()

	func _draw() -> void:
		var radius := size.x * ElementOrbs.BODY_SHARE
		var center := Vector2(size.x / 2, size.y - radius - 3.0 + sin(_time * 2.2) * 2.0)
		draw_orb(self, center, radius, _color, _time, ghost, borrowed, can_lend())

	## Irrlicht (Entwurf "Unbenannt (27)"): runder Körper mit Glanzpunkt unten links, darüber ein S-förmiger Schweif,
	## der zur Spitze hin dünner wird und im Wind weht. Auch für die Drag-Vorschau und die Absicht der Gegner.
	## center = Mitte des Körpers. Der Schweif ist aus vielen kleinen Kreisen gebaut: kein Polygon, das sich in der
	## Kurve selbst schneiden könnte.
	## ghost: verliehen, nur Umriss; ring: weißer statt dunkler Umriss (geliehen); pulse: leuchtet (ziehbar)
	static func draw_orb(canvas: CanvasItem, center: Vector2, radius: float, color: Color, time: float, ghost := false,
			ring := false, pulse := false) -> void:
		var spine := _tail(center, radius, time)
		var outline := Color.WHITE if ring else Color(0, 0, 0, 0.85)
		var edge := 1.8 if ring else 1.3
		if ghost:
			# Umriss in der Elementfarbe, innen dunkel: das Element ist gerade weg
			_silhouette(canvas, center, radius, spine, edge, Color(color, 0.7))
			_silhouette(canvas, center, radius, spine, 0.0, Color(0, 0, 0, 0.55))
			return
		var glow := 0.07 + (0.05 * (1.0 + sin(time * 5.0)) if pulse else 0.0)
		for i in 4:
			canvas.draw_circle(center, radius * (1.0 + 0.25 * (4 - i)), Color(color, glow * (i + 1)))
		_silhouette(canvas, center, radius, spine, edge, outline)
		# Schweif zur Spitze hin heller, Körper in voller Farbe
		for point in spine:
			canvas.draw_circle(point.pos, point.width, color.lerp(color.lightened(0.45), point.t))
		canvas.draw_circle(center, radius, color)
		# Glanzpunkt unten links wie im Entwurf
		canvas.draw_circle(center + Vector2(-radius * 0.42, radius * 0.38), radius * 0.22, Color(1, 1, 1, 0.65))

	## Punkte entlang des Schweifs vom Körper bis zur Spitze: {"pos", "width", "t"}.
	## S-Kurve, die Welle läuft nach oben und schwingt an der Spitze am stärksten.
	static func _tail(center: Vector2, radius: float, time: float) -> Array:
		var points := []
		var height := radius * ElementOrbs.TAIL_LENGTH
		for i in ElementOrbs.TAIL_STEPS:
			var t := float(i + 1) / ElementOrbs.TAIL_STEPS
			var sway := sin(PI * 1.8 * t - time * 3.0) * radius * 0.95 * pow(t, 0.6)
			points.append({
				"pos": center + Vector2(sway, -radius * 0.3 - height * t),
				"width": maxf(radius * 0.72 * pow(1.0 - t, 1.2), 0.6),
				"t": t,
			})
		return points

	## Ganze Form (Körper + Schweif), um grow größer, in einer Farbe: als Umriss unter die eigentliche Füllung
	static func _silhouette(canvas: CanvasItem, center: Vector2, radius: float, spine: Array, grow: float, color: Color) -> void:
		canvas.draw_circle(center, radius + grow, color)
		for point in spine:
			canvas.draw_circle(point.pos, point.width + grow, color)

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if not can_lend():
			return null
		var preview := DragPreview.new(_color)
		set_drag_preview(preview)
		ElementLoan.set_preview(element)
		return {"type": "element_orb", "element": element, "lender": owner_mon}

	func _gui_input(event: InputEvent) -> void:
		if borrowed and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			accept_event()
			if owner_mon == ElementLoan.active:
				ElementLoan.cancel(owner_mon, element)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			ElementLoan.set_preview(0)


## Kleine Kugel als Symbol, z. B. in der Absicht eines Gegners (geplante Leihgabe), side = Kantenlänge
static func badge(element: int, side: float) -> Control:
	var preview := DragPreview.new(Color(Helper.color_by_type(element)))
	preview.custom_minimum_size = Vector2(side * 0.8, side)
	preview.centered = true
	return preview


## Kugel unter der Maus beim Ziehen (oder mit centered als Symbol in einer Zeile)
class DragPreview extends Control:
	var centered := false
	var _color: Color
	var _time := 0.0

	func _init(color: Color) -> void:
		_color = color
		mouse_filter = MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		if centered:
			# Körper unten, der Schweif füllt den Rest nach oben
			# Gesamthöhe: Körper unten (1 Radius) + Ansatz (0,3) + Schweif + etwas Luft
			var radius := size.y / (1.3 + ElementOrbs.TAIL_LENGTH + 0.4)
			Orb.draw_orb(self, Vector2(size.x / 2, size.y - radius - 1.0), radius, _color, _time)
			return
		Orb.draw_orb(self, Vector2.ZERO, ElementOrbs.ORB_SIZE * 0.34, _color, _time, false, true, true)
