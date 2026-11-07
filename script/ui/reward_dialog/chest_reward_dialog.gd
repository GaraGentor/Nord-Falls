class_name ChestRewardDialog
extends RewardDialog

## Belohnungs-Dialog mit Behälter (Edelstein-Feld: Beutel, Schatz: Truhe, Relic-Auswahl: Kiste, Skill-Auswahl: Couvert): statt der
## Kartenspalte springt links der Behälter auf, die Preise fliegen heraus, er verschwindet, ein Teppich kommt
## von unten und die Preise fallen darauf. Von dort werden sie wie gewohnt auf die Ziele gezogen.
## Ablauf im _ready() der Unterklasse: erst use_chest_layout(), zuletzt play_chest_intro().

const CHEST_TEXTURE = preload("res://assets/ui/rewards/reward_chest.png")
const BAG_TEXTURE = preload("res://assets/ui/rewards/bag.png")
const BOX_TEXTURE = preload("res://assets/ui/rewards/box.png")
const ENVELOPE_TEXTURE = preload("res://assets/ui/rewards/envelop.png")
const RUG_TEXTURE = preload("res://assets/ui/rewards/rug.png")
## eigenes Material für Behälter und Teppich, unabhängig von Monmap.LIVING_MATERIAL
const STAGE_MATERIAL = preload("res://script/ui/reward_dialog/reward_stage_material.tres")
## abgedunkelt, damit der goldene Text darauf lesbar bleibt
const RUG_TINT := Color(0.55, 0.55, 0.55)
const STAGE_WIDTH := 400.0
const LOOT_WIDTH := 140.0
const LOOT_ICON_SIZE := Vector2(64, 64)
const LOOT_TITLE_FONT_SIZE := 16
const LOOT_TEXT_FONT_SIZE := 13
## Anzahl Preise -> Liegeplätze auf dem Teppich, Mitte des Preises als Anteil der Bühne
const LOOT_SPOTS := {
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.3, 0.38), Vector2(0.7, 0.62)],
	3: [Vector2(0.3, 0.3), Vector2(0.7, 0.33), Vector2(0.5, 0.72)],
	4: [Vector2(0.28, 0.28), Vector2(0.72, 0.28), Vector2(0.28, 0.72), Vector2(0.72, 0.72)],
}
## so weit weicht ein Preis zufällig von seinem Platz ab, ohne die anderen zu berühren
const LOOT_JITTER := 0.025
## Preise schweben kurz über der Truhe, solange der Teppich kommt
const LOOT_HOVER_SPACING := 0.3
const LOOT_HOVER_Y := 0.2
const CHEST_MOUTH_Y := 0.52
const CHEST_HEIGHT := 0.62

## Fläche links: erst die Truhe, dann der Teppich mit den Preisen
var _stage: Control
var _chest: TextureRect
var _rug: TextureRect
var _loot: Array[RewardCard] = []

func use_chest_layout(container_texture: Texture2D = CHEST_TEXTURE) -> void:
	use_map_layout()
	_stage = Control.new()
	_stage.custom_minimum_size.x = STAGE_WIDTH
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# der Teppich kommt von unten herein und ist vorher nicht zu sehen
	_stage.clip_contents = true
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	use_card_stage(_stage)
	_rug = _stage_image(RUG_TEXTURE)
	_rug.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_rug.visible = false
	_rug.modulate = RUG_TINT
	_chest = _stage_image(container_texture)

func _stage_image(texture: Texture2D) -> TextureRect:
	var image := texture_icon(texture) as TextureRect
	image.material = STAGE_MATERIAL
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(image)
	return image

## Preis ohne Platte: nur Bild und Text, der Teppich ist der Hintergrund
func _build_card(card: RewardCard, card_title: String, text: String) -> void:
	build_loot_card(card, card_title, text)

## Auch vom Void-Ereignis genutzt, dort liegt das neue Relikt auf dem Teppich
static func build_loot_card(card: RewardCard, card_title: String, text: String) -> void:
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	card.custom_minimum_size.x = LOOT_WIDTH
	card.row = VBoxContainer.new()
	card.row.add_theme_constant_override("separation", 2)
	card.add_child(card.row)
	card.icon.custom_minimum_size = LOOT_ICON_SIZE
	card.row.add_child(card.icon)
	card.info = VBoxContainer.new()
	card.info.add_theme_constant_override("separation", 0)
	card.row.add_child(card.info)
	card.info.add_child(_loot_label(card_title, LOOT_TITLE_FONT_SIZE, SkillDetailPopup.GOLD))
	card.info.add_child(_loot_label(text, LOOT_TEXT_FONT_SIZE, Color.WHITE))

static func _loot_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label

## Die Preise sind erst nach dem Intro ziehbar
func _place_card(card: RewardCard) -> void:
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.modulate.a = 0.0
	_stage.add_child(card)
	_loot.append(card)

func _takeable_cards() -> Array:
	return _loot

func play_chest_intro() -> void:
	# der umbrochene Text kennt seine Höhe erst nach dem Layout, davon hängt die Größe der Preise ab
	await get_tree().process_frame
	await get_tree().process_frame
	var stage_size := _stage.size
	for card in _loot:
		card.reset_size()
		card.pivot_offset = card.size / 2
		card.scale = Vector2(0.3, 0.3)
		card.info.modulate.a = 0.0
		card.position = stage_size * Vector2(0.5, CHEST_MOUTH_Y) - card.size / 2
	await _pop_chest(stage_size)
	await _wait_before_burst()
	await _burst_loot(stage_size)
	await _swap_chest_for_rug(stage_size)
	await _drop_loot(stage_size)
	for card in _loot:
		card.mouse_filter = Control.MOUSE_FILTER_STOP

## Der Behälter steht schon da, die Preise bleiben noch drin (Schatz: bis der Schlüssel benutzt wurde)
func _wait_before_burst() -> void:
	pass

func _pop_chest(stage_size: Vector2) -> void:
	var chest_size := Vector2.ONE * stage_size.y * CHEST_HEIGHT
	_chest.size = chest_size
	_chest.position = Vector2((stage_size.x - chest_size.x) / 2, stage_size.y - chest_size.y)
	await pop_container(_chest).finished

## Behälter springt von unten auf und wackelt, bevor er aufplatzt
static func pop_container(image: Control) -> Tween:
	image.pivot_offset = Vector2(image.size.x / 2, image.size.y)
	image.scale = Vector2.ZERO
	var tween := image.create_tween()
	tween.tween_property(image, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for angle in [-3.0, 3.0, -2.0, 0.0]:
		tween.tween_property(image, "rotation_degrees", angle, 0.07)
	return tween

func _burst_loot(stage_size: Vector2) -> void:
	var tween := create_tween().set_parallel()
	for i in _loot.size():
		var card := _loot[i]
		var delay := i * 0.1
		var hover_x := 0.5 + (i - (_loot.size() - 1) / 2.0) * LOOT_HOVER_SPACING
		var target := stage_size * Vector2(hover_x, LOOT_HOVER_Y) - card.size / 2
		tween.tween_property(card, "modulate:a", 1.0, 0.1).set_delay(delay)
		tween.tween_property(card, "scale", Vector2.ONE, 0.4).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "position", target, 0.4).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished

func _swap_chest_for_rug(stage_size: Vector2) -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(_chest, "modulate:a", 0.0, 0.3)
	tween.tween_property(_chest, "scale", Vector2(0.8, 0.8), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	_chest.queue_free()
	_rug.position.y = stage_size.y
	_rug.visible = true
	tween = create_tween()
	tween.tween_property(_rug, "position:y", 0.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished

## Liegeplätze der Preise, Unterklassen mit größeren Preisen können eigene wählen
func _loot_spots(count: int) -> Array:
	return LOOT_SPOTS[count].duplicate()

func _drop_loot(stage_size: Vector2) -> void:
	var spots := _loot_spots(_loot.size())
	spots.shuffle()
	var tween := create_tween().set_parallel()
	for i in _loot.size():
		var card := _loot[i]
		var delay := i * 0.08
		spots[i] += Vector2(randf_range(-LOOT_JITTER, LOOT_JITTER), randf_range(-LOOT_JITTER, LOOT_JITTER))
		var target: Vector2 = spots[i] * stage_size - card.size / 2
		tween.tween_property(card, "position:x", target.x, 0.45).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "position:y", target.y, 0.45).set_delay(delay).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tween.tween_property(card.info, "modulate:a", 1.0, 0.25).set_delay(delay + 0.3)
	await tween.finished
	# Anteil statt Pixel: bleibt passend, wenn sich die Fläche ändert
	for i in _loot.size():
		var card := _loot[i]
		card.grow_horizontal = GROW_DIRECTION_BOTH
		card.grow_vertical = GROW_DIRECTION_BOTH
		for side in [SIDE_LEFT, SIDE_RIGHT]:
			card.set_anchor_and_offset(side, spots[i].x, 0.0, true)
		for side in [SIDE_TOP, SIDE_BOTTOM]:
			card.set_anchor_and_offset(side, spots[i].y, 0.0, true)
