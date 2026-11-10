extends Control

## Heilungs-Camp: in der Mitte das Lagerfeuer, links und rechts davon die eigenen Monster.
## Geheilt wird nur über das Feuer: Essenz aus der Tasche in die Flammen ziehen, jederzeit und ohne Obergrenze
## (sind die Monster voll, ist die Essenz einfach weg). Die Lebensanzeigen steigen sofort,
## während kleine Herzen in einem großen Bogen aus dem Feuer auf die Monster fliegen.

## Stapel Essenz neben der Tasche, lässt sich ins Feuer ziehen
class GoldStack extends VBoxContainer:
	const ART_SIZE := Vector2(64, 64)
	const COIN_SIZE := Vector2(40, 40)
	const FONT_SIZE := 20

	var camp: Node
	var amount: int
	var _art: Control

	func _init(owner_camp: Node, gold: int, coins: int) -> void:
		camp = owner_camp
		amount = gold
		alignment = BoxContainer.ALIGNMENT_END
		add_theme_constant_override("separation", 0)
		_art = Control.new()
		_art.custom_minimum_size = ART_SIZE
		for i in coins:
			var coin := RewardDialog.texture_icon(ESSENCE_ICON)
			coin.material = PROPS_MATERIAL
			coin.size = COIN_SIZE
			# Münzen türmen sich von unten nach oben auf
			coin.position = Vector2((ART_SIZE.x - COIN_SIZE.x) / 2 + (i % 2) * 6.0 - 3.0, ART_SIZE.y - COIN_SIZE.y - i * 6.0)
			_art.add_child(coin)
		add_child(_art)
		var label := Label.new()
		label.text = Helper.me_text(gold)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 6)
		add_child(label)
		RewardDialog.ignore_mouse_below(self)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _get_drag_data(_at_position: Vector2):
		if not camp.can_feed(amount):
			camp.fire_says(tr("CAMP_FEED_POOR"))
			return null
		var art: Control = _art.duplicate()
		art.position = -ART_SIZE / 2
		var holder := Control.new()
		holder.add_child(art)
		set_drag_preview(holder)
		return self

## Relikt "Endloses Feuer" anstelle von Tasche und Essenz: kostet nichts und bleibt nach jedem Wurf liegen
class EndlessFireRelic extends VBoxContainer:
	const ART_SIZE := Vector2(96, 96)
	const FONT_SIZE := 20

	var _art: Control

	func _init() -> void:
		alignment = BoxContainer.ALIGNMENT_END
		add_theme_constant_override("separation", 4)
		var relic: Dictionary = Relics.get_relic(ENDLESS_FIRE)
		_art = RewardDialog.texture_icon(load(relic.icon))
		_art.material = PROPS_MATERIAL
		_art.custom_minimum_size = ART_SIZE
		add_child(_art)
		var label := Label.new()
		label.text = tr(relic.name)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 6)
		add_child(label)
		tooltip_text = tr(relic.description)
		RewardDialog.ignore_mouse_below(self)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG

	func _get_drag_data(_at_position: Vector2):
		var art: Control = _art.duplicate()
		art.position = -ART_SIZE / 2
		var holder := Control.new()
		holder.add_child(art)
		set_drag_preview(holder)
		return self

## Fläche über dem Feuer, Ablegeziel für Essenz und das Relikt
class FeedTarget extends Control:
	var camp: Node

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is GoldStack or data is EndlessFireRelic

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if data is GoldStack:
			camp.feed(data.amount)
		else:
			camp.feed_relic()

const CAMP_MONSTER = preload("res://script/scenes/heal_camp/camp_monster.tscn")
const HEART_TEXTURE = preload("res://assets/ui/icons/heart.svg")
const PROPS_MATERIAL = preload("res://script/scenes/jailer/jailer_props_material.tres")
const ESSENCE_ICON = preload("res://assets/ui/icons/monster_essence.svg")
## Lebenspunkte pro Monster, die eine Essenz im Feuer bringt
const HP_PER_GOLD := 5
const ENDLESS_FIRE := "endless_fire"
## Lebenspunkte pro Monster, die ein Wurf des Relikts bringt: so viel wie der größte Essenz-Stapel
const ENDLESS_FIRE_HP := 50
## Größe der Stapel neben der Tasche -> so viele Münzen zeigt der Stapel
const GOLD_STACKS := {1: 1, 5: 3, 10: 5}
const BAG_SIZE := Vector2(150, 142)
const BAG_ITEM_SIZE := Vector2(40, 40)
const BAG_FONT_SIZE := 22
## so viel Essenz steht für ein sichtbares Stück in der Tasche
const ESSENCE_PER_ITEM := 25
const BUBBLE_WIDTH := 320.0
const BUBBLE_MIN_TOP := 8.0
## Unterkante der Sprechblase, von der Oberkante des Feuers aus: knapp über den Flammen
const BUBBLE_BOTTOM := 96.0
## so lange bleibt eine Antwort des Feuers stehen, dann bittet es wieder um Essenz
const FIRE_TALK_SECONDS := 2.5
const HEAL_SECONDS := 0.8
const BUTTON_MARGIN := 24
const HEART_SIZE := Vector2(26, 26)
const HEARTS_PER_FEED := 6
const HEART_INTERVAL := 0.1
const HEART_FLIGHT_SECONDS := 1.1
## so hoch steigen die Herzen über den höheren der beiden Endpunkte
const HEART_ARC_HEIGHT := Vector2(170.0, 260.0)
## Austrittspunkt im Feuer, Anteile seiner Fläche
const FIRE_MOUTH := Vector2(0.5, 0.72)

@export var left_slot: Control
@export var right_slot: Control
## Lagerfeuer, aus ihm kommen die Herzen
@export var fire: Control
## Reihe vor dem Feuer: Tasche und Essenz-Stapel
@export var feed_row: Control

var debug = false
var _camp_monsters: Array[Control] = []
var _bag: OpenBag
var _stacks: Array[GoldStack] = []
var _bubble: SpeechBubble
var _fire_talk: Tween
## Monster -> verlorene KP nach allen bisherigen Bissen; die Anzeige läuft diesem Stand hinterher
var _lost_hp_after := {}
var _heal: Tween

func _enter_tree() -> void:
	if debug:
		var mon1:Monster = Helper.generate_mons({"count": 1, "level": randi_range(10,30)})[0]
		mon1._lost_hp = mon1.hp() / 1.5
		State.mons.append(mon1)
		#var mon2:Monster = Helper.generate_mons({"count": 1, "level": randi_range(10,30)})[0]
		#mon2._lost_hp = mon2.hp() / 1.5
		#State.mons.append(mon2)

func _ready() -> void:
	var button := RewardDialog.icon_button(ShopDialog.EXIT_ICON)
	button.tooltip_text = tr("COMMON_OK")
	button.pressed.connect(_leave)
	add_child(button)
	button.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT, PRESET_MODE_KEEP_SIZE, BUTTON_MARGIN)
	for mon: Monster in State.mons:
		_lost_hp_after[mon] = mon._lost_hp
	# das Team hat höchstens zwei Monster (judgement.gd MAX_TEAM)
	var slots: Array[Control] = [left_slot, right_slot]
	for i in State.mons.size():
		var camp_monster := CAMP_MONSTER.instantiate()
		camp_monster.mon = State.mons[i]
		slots[i % slots.size()].add_child(camp_monster)
		_camp_monsters.append(camp_monster)
	_build_feeding()

## Tasche und Stapel vor dem Feuer, darüber seine Sprechblase; das Feuer selbst nimmt die Essenz an
func _build_feeding() -> void:
	var target := FeedTarget.new()
	target.camp = self
	target.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	fire.add_child(target)
	# gleich breite Seiten links und rechts halten die Tasche mittig vor dem Feuer
	var left_side := Control.new()
	left_side.size_flags_horizontal = SIZE_EXPAND_FILL
	left_side.mouse_filter = MOUSE_FILTER_IGNORE
	feed_row.add_child(left_side)
	var endless := Relics.works(ENDLESS_FIRE)
	if endless:
		feed_row.add_child(EndlessFireRelic.new())
	else:
		_bag = OpenBag.new(BAG_SIZE, ESSENCE_ICON, BAG_ITEM_SIZE, BAG_FONT_SIZE)
		feed_row.add_child(_bag)
	var right_side := HBoxContainer.new()
	right_side.size_flags_horizontal = SIZE_EXPAND_FILL
	right_side.add_theme_constant_override("separation", 12)
	feed_row.add_child(right_side)
	if not endless:
		for amount: int in GOLD_STACKS:
			var stack := GoldStack.new(self, amount, GOLD_STACKS[amount])
			_stacks.append(stack)
			right_side.add_child(stack)

	_bubble = SpeechBubble.new(BUBBLE_WIDTH, true, false, true)
	add_child(_bubble)
	# beim ersten Besuch erklärt das Feuer im Tutorial, danach bittet es wie immer um Essenz
	fire.add_to_group("tut_npc")
	feed_row.add_to_group("tut_camp_feed")
	# links und rechts vom Feuer: je eine eigene Gruppe, sonst läge das Feuer im selben Loch
	for i in _camp_monsters.size():
		_camp_monsters[i].add_to_group("tut_camp_mon_%d" % i)
	if not Tutorial.trigger("camp", _ask_for_food):
		_ask_for_food()

	if not endless:
		State.ep_changed.connect(_show_money)
		_show_money(State.ep)

## Die Blase steigt mit den wachsenden Flammen, bleibt aber im Bild
func _place_bubble() -> void:
	var fire_top_left := fire.global_position - global_position
	var lift: float = fire.flame_lift()
	var top := fire_top_left.y + BUBBLE_BOTTOM - lift - _bubble.size.y
	_bubble.position = Vector2(fire_top_left.x + (fire.size.x - _bubble.size.x) / 2, maxf(top, BUBBLE_MIN_TOP))

func _ask_for_food() -> void:
	if Relics.works(ENDLESS_FIRE):
		_bubble.say(tr("CAMP_FIRE_ASK_ENDLESS").format({"hp": ENDLESS_FIRE_HP}))
	else:
		_bubble.say(tr("CAMP_FIRE_ASK").format({"hp": HP_PER_GOLD}))

## Kurze Antwort des Feuers, danach bittet es wieder um Essenz
func fire_says(text: String) -> void:
	_bubble.say(text)
	if _fire_talk:
		_fire_talk.kill()
	_fire_talk = create_tween()
	_fire_talk.tween_interval(FIRE_TALK_SECONDS)
	_fire_talk.tween_callback(_ask_for_food)

func can_feed(amount: int) -> bool:
	return State.ep >= amount

func feed(amount: int) -> void:
	State.ep -= amount
	_burn(amount * HP_PER_GOLD)

func feed_relic() -> void:
	_burn(ENDLESS_FIRE_HP)

func _burn(hp: int) -> void:
	_heal_team(hp)
	fire_says(tr("CAMP_FIRE_EATING"))
	fire.eat()

func _show_money(ep: int) -> void:
	_bag.label.text = str(ep)
	_bag.show_items(ceili(ep / float(ESSENCE_PER_ITEM)))
	# Stapel, die gerade nicht ins Feuer dürfen, sind ausgegraut
	for stack in _stacks:
		var blocked := not can_feed(stack.amount)
		stack.modulate = RewardDialog.LOCKED_COLOR if blocked else Color.WHITE
		stack.mouse_default_cursor_shape = CURSOR_ARROW if blocked else CURSOR_DRAG

## Das Feuer bekommt den goldenen Umriss, solange die Essenz darüber schwebt
func _process(_delta: float) -> void:
	_place_bubble()
	var over := get_viewport().gui_is_dragging() and fire.get_global_rect().has_point(get_global_mouse_position())
	fire.set_gold(over)

## Ein neuer Bissen übernimmt die laufende Anzeige, damit schnelles Füttern nichts verschluckt
func _heal_team(hp: int) -> void:
	if _camp_monsters.is_empty():
		return
	if _heal:
		_heal.kill()
	_heal = create_tween().set_parallel()
	for mon: Monster in _lost_hp_after:
		_lost_hp_after[mon] = clampf(_lost_hp_after[mon] - hp, 0, mon.hp())
		_heal.tween_property(mon, "_lost_hp", _lost_hp_after[mon], HEAL_SECONDS)
	_send_hearts()

## Mit dem Lager endet auch die laufende Anzeige, die Heilung muss trotzdem ankommen
func _leave() -> void:
	if _heal:
		_heal.kill()
	for mon: Monster in _lost_hp_after:
		mon._lost_hp = _lost_hp_after[mon]
	queue_free()

## Abwechselnd ein Herz zu jedem Monster
func _send_hearts() -> void:
	var hearts := create_tween()
	for i in HEARTS_PER_FEED:
		hearts.tween_callback(_fly_heart.bind(_camp_monsters[i % _camp_monsters.size()]))
		hearts.tween_interval(HEART_INTERVAL)

func _fly_heart(camp_monster: Control) -> void:
	var heart := TextureRect.new()
	heart.texture = HEART_TEXTURE
	heart.material = PROPS_MATERIAL
	heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heart.mouse_filter = MOUSE_FILTER_IGNORE
	heart.size = HEART_SIZE
	heart.pivot_offset = HEART_SIZE / 2
	heart.z_index = 5
	add_child(heart)
	var start := fire.get_global_rect().position + fire.size * FIRE_MOUTH - global_position - HEART_SIZE / 2
	var texture_rect: Control = camp_monster.texture_rect
	var end := texture_rect.get_global_rect().get_center() - global_position - HEART_SIZE / 2
	end += Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0))
	var peak := Vector2((start.x + end.x) / 2, minf(start.y, end.y) - randf_range(HEART_ARC_HEIGHT.x, HEART_ARC_HEIGHT.y))
	# Bézierkurve mit drei Punkten: steil aus dem Feuer heraus, in großem Bogen zum Monster
	var along_arc := func(t: float) -> void:
		heart.position = start.lerp(peak, t).lerp(peak.lerp(end, t), t)
	heart.position = start
	heart.scale = Vector2.ONE * 0.4
	var tween := heart.create_tween().set_parallel()
	tween.tween_method(along_arc, 0.0, 1.0, HEART_FLIGHT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(heart, "scale", Vector2.ONE, HEART_FLIGHT_SECONDS * 0.4)
	tween.tween_property(heart, "modulate:a", 0.0, 0.2).set_delay(HEART_FLIGHT_SECONDS - 0.2)
	tween.chain().tween_callback(heart.queue_free)
