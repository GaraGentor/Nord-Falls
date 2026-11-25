class_name ElementOrbs
extends Control

## Schwebende Element-Kugeln über einem eigenen Monster im Kampf (Element-Leihgabe, ElementLoan), als Dreieck
## um die "-N"-Raute. Ist ein eigenes Monster am Zug, fliegen die Elemente seines Partners von dessen Seite ein;
## die eigenen Elemente des Monsters am Zug bleiben solange versteckt.
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
const DEBT_COLOR := Color(1.0, 0.45, 0.4)
## Aktions-Raute mit "-1" (MovesBadge), etwas kleiner als an den Bildern im Infobereich
const DEBT_BADGE_SIZE := Vector2(36, 33)

## Abstand der Kugeln von der Mitte des Dreiecks (dort steht die "-N"-Raute)
const CLUSTER_RADIUS := 40.0
## Mitte des Dreiecks auf dem Monster: Anteil der Bildhöhe von oben (die Kugeln landen auf dem Rücken,
## darüber bleibt Platz)
const CLUSTER_HEIGHT := 0.32
## Ein- und Ausflug zur Seite des Monsters: Strecke, Dauer, Versatz zwischen den Kugeln
const FLY_DISTANCE := 420.0
const FLY_TIME := 0.45
const FLY_OUT_TIME := 0.35
const FLY_STAGGER := 0.07

var _scene: Control
## Kugeln und Raute, mittig im Dreieck (Position = Mitte des Dreiecks)
var _cluster: Control
var _debt_badge: MovesBadge

func _init(scene: Control) -> void:
	_scene = scene
	mouse_filter = MOUSE_FILTER_IGNORE

func _ready() -> void:
	Events.element_loans_changed.connect(_rebuild)
	Events.monster_status_changed.connect(func(_mon): _rebuild())
	_rebuild()

func _mon() -> Monster:
	return _scene.mon

## Was über diesem Monster gerade zu sehen ist:
##   "partner": ein anderes eigenes Monster ist am Zug: die Elemente, die es sich von hier leihen kann
##   "active": dieses Monster ist am Zug: eigene Elemente versteckt, nur die geliehenen (anklicken gibt sie zurück)
##   "": sonst (Gegner am Zug, K.O.): nur die "-N"-Raute, falls Aktionen fehlen
func _role(mon: Monster) -> String:
	var active := ElementLoan.active
	if mon == null or not mon.is_alive() or active == null or not State.mons.has(active):
		return ""
	return "active" if active == mon else "partner"

## Nur neu aufbauen, wenn sich etwas Sichtbares geändert hat: sonst verschwände die gerade gezogene Kugel
## (die Vorschau beim Ziehen meldet sich auch über element_loans_changed)
var _shown := ""
var _shown_role := ""

func _rebuild() -> void:
	if not is_inside_tree():
		return
	var mon := _mon()
	var role := _role(mon)
	var signature := ""
	if mon != null and mon.is_alive():
		signature = "%s|%d|%s|%s|%d" % [role, mon._type, _lent_elements(mon), mon._loans.map(func(loan): return loan.element),
			mon._loan_debt]
	if signature == _shown:
		return
	var role_changed := role != _shown_role
	_shown = signature
	_shown_role = role
	# Monster links fliegen nach links ein und aus, Monster rechts nach rechts
	var side := -1.0 if _scene.mon_slot == 0 else 1.0
	var old := _cluster
	_cluster = null
	_debt_badge = null
	if old != null:
		if role_changed:
			_fly_out(old, side)
		else:
			old.queue_free()
	if signature == "":
		return
	_cluster = Control.new()
	_cluster.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_cluster)
	var orbs: Array[Orb] = []
	if role == "partner":
		var lent := _lent_elements(mon)
		for element in ElementGlyph.elements_of(mon._type):
			var orb := Orb.new(element, mon)
			# das Tutorial (Feld 2) hebt die Kugeln des Partners hervor
			orb.add_to_group("tut_bat_orbs")
			orb.ghost = lent.has(element)
			orbs.append(orb)
	elif role == "active":
		for loan in mon._loans:
			var orb := Orb.new(loan.element, mon)
			orb.borrowed = true
			orbs.append(orb)
	if mon._loan_debt > 0:
		# "-1" auf der Aktions-Raute (wie die Züge auf der Karte im Infobereich), damit klar ist: es fehlen Aktionen
		_debt_badge = load(MovesBadge.SCENE_PATH).instantiate()
		_debt_badge.custom_minimum_size = DEBT_BADGE_SIZE
		_debt_badge.size = DEBT_BADGE_SIZE
		_debt_badge.position = -DEBT_BADGE_SIZE / 2
		_cluster.add_child(_debt_badge)
		_debt_badge.show_number(-mon._loan_debt, true)
		_debt_badge.label.add_theme_color_override("font_color", DEBT_COLOR)
		_debt_badge.tooltip_text = tr("LOAN_DEBT_TOOLTIP").format({"count": mon._loan_debt})
	var spots := _spots(orbs.size(), _debt_badge != null)
	# Einflug nur, wenn die Elemente neu dazukommen (Partner wechselt), sonst stehen sie gleich an ihrem Platz
	var fly := role_changed and role == "partner"
	for i in orbs.size():
		var orb := orbs[i]
		_cluster.add_child(orb)
		orb.size = orb.custom_minimum_size
		var target := spots[i] - orb.body_offset()
		if not fly:
			orb.position = target
			continue
		orb.position = target + Vector2(FLY_DISTANCE * side, 0)
		orb.modulate.a = 0.0
		var tween := orb.create_tween().set_parallel()
		tween.tween_property(orb, "position", target, FLY_TIME).set_delay(i * FLY_STAGGER) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(orb, "modulate:a", 1.0, FLY_TIME * 0.5).set_delay(i * FLY_STAGGER)

## Rollenwechsel: die alten Kugeln heben kurz ab und fliegen zur Seite hinaus, die Raute verblasst.
## Danach verschwindet die ganze alte Gruppe.
func _fly_out(old: Control, side: float) -> void:
	var i := 0
	for child in old.get_children():
		if child is Orb:
			child.fading = true
			var tween := child.create_tween().set_parallel()
			tween.tween_property(child, "position:x", child.position.x + FLY_DISTANCE * side, FLY_OUT_TIME) \
				.set_delay(i * FLY_STAGGER).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tween.tween_property(child, "modulate:a", 0.0, FLY_OUT_TIME * 0.4) \
				.set_delay(i * FLY_STAGGER + FLY_OUT_TIME * 0.6)
			i += 1
		elif child is Control:
			child.mouse_filter = MOUSE_FILTER_IGNORE
			child.create_tween().tween_property(child, "modulate:a", 0.0, FLY_OUT_TIME)
	var done := old.create_tween()
	done.tween_interval(FLY_OUT_TIME + i * FLY_STAGGER)
	done.tween_callback(old.queue_free)

## Plätze der Kugelkörper rund um die Mitte: eine Kugel oben (ohne Raute mittig), zwei links und rechts,
## drei als Dreieck (oben, unten links, unten rechts), mehr im Kreis
func _spots(count: int, has_badge: bool) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	if count == 1:
		spots.append(Vector2(0, -CLUSTER_RADIUS) if has_badge else Vector2.ZERO)
		return spots
	if count == 2:
		spots.append(Vector2(-CLUSTER_RADIUS, 0))
		spots.append(Vector2(CLUSTER_RADIUS, 0))
		return spots
	for i in count:
		var angle := -PI / 2 - TAU * i / count
		spots.append(Vector2(cos(angle), sin(angle)) * CLUSTER_RADIUS)
	return spots

## Elemente dieses Monsters, die gerade ein Partner geliehen hat
func _lent_elements(mon: Monster) -> Array:
	var lent := []
	for other: Monster in State.mons + State.enemy_mons:
		for loan in other._loans:
			if loan.from == mon:
				lent.append(loan.element)
	return lent

## Dreieck mittig auf dem Monster (oberes Drittel des Bilds), darüber bleibt Platz für Status und Effekte.
## Liegt auf der Ebene über dem Kampffeld (battle.gd), deshalb in globalen Koordinaten.
func _process(_delta: float) -> void:
	# neues Monster auf dem Platz (Endboss-Relikt Buddy), K.O. oder Zugwechsel: baut nur neu, wenn sich etwas ändert
	_rebuild()
	visible = _scene.is_visible_in_tree()
	var image: Rect2 = _scene.drawn_image_rect()
	if image.size == Vector2.ZERO:
		return
	global_position = _scene.global_position + image.position + image.size * Vector2(0.5, CLUSTER_HEIGHT)


## Eine Kugel: Grundelement in seiner Farbe mit kleiner Flamme, schwebt leicht auf und ab
class Orb extends Control:
	var element: int
	## Monster, bei dem die Kugel gerade schwebt
	var owner_mon: Monster
	## eigenes Element, das gerade verliehen ist: nur ein leerer Ring
	var ghost := false
	## vom Partner geliehen: weißer Ring, anklicken gibt es zurück
	var borrowed := false
	## wird gerade ausgeblendet (Zugwechsel)
	var fading := false
	var _time := 0.0
	var _seed := 0.0
	var _color: Color
	## Maus-Verhalten laut Art der Kugel (aus _ready), beim Ziehen und Ausblenden vorübergehend IGNORE
	var _active_filter := MOUSE_FILTER_PASS

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
		_active_filter = mouse_filter

	## Darf diese Kugel gerade auf das Monster am Zug gezogen werden?
	func can_lend() -> bool:
		return not ghost and not borrowed and ElementLoan.can_borrow(ElementLoan.active, owner_mon, element)

	## Mitte des Körpers (ohne Wippen) relativ zur Kugel, siehe _draw
	func body_offset() -> Vector2:
		var orb_size := custom_minimum_size
		return Vector2(orb_size.x / 2, orb_size.y - orb_size.x * ElementOrbs.BODY_SHARE - 3.0)

	func _process(delta: float) -> void:
		_time += delta
		# beim Ziehen einer Karte (oder Kugel) liegen die Kugeln nicht im Weg: das Ziel darunter nimmt sie an
		# beim Ausblenden (Zugwechsel) nimmt sie nichts mehr an
		mouse_filter = MOUSE_FILTER_IGNORE if fading or get_viewport().gui_is_dragging() else _active_filter
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
