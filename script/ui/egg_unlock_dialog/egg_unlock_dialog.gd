class_name EggUnlockDialog
extends InfoDialog

## Neu freigeschaltete Ei-Attacken (Opfern, Meilenstein, Kopfgeld): Dialog über allem, der weggeklickt werden muss,
## damit man die Freischaltung nicht verpasst (vorher nur ein kurz eingeblendeter Hinweis).
## Zeigt die Art, die Karten der Attacken und darunter, wodurch sie freigeschaltet wurden (Skills.get_egg_skill_source).
## Kommen mehrere Freischaltungen kurz hintereinander, erscheinen die Dialoge nacheinander (_queue).

## über den Info-Dialogen der Szenen, liegt direkt am Root und übersteht so auch Szenenwechsel
const UNLOCK_LAYER := 90
const CARD_SIZE := Vector2(220, 210)
const SOURCE_FONT_SIZE := 22
## So lange nach dem Erscheinen schließt ein Klick daneben noch nicht (Klicks, die eigentlich dem Kampf galten)
const CLOSE_GRACE_MSEC := 700

## Wartende Dialoge, solange einer offen ist
static var _queue: Array[EggUnlockDialog] = []
static var _open: EggUnlockDialog

var _title_key: String
var _mon_name: String
var _skill_names: Array
var _opened_at := 0

## title_key: Überschrift (z. B. "EGG_UNLOCK_TITLE"), mon_name: Art, die die Attacken bekommen hat
static func announce(tree: SceneTree, title_key: String, mon_name: String, skill_names: Array) -> void:
	if skill_names.is_empty():
		return
	var dialog := EggUnlockDialog.new(title_key, mon_name, skill_names)
	if _open != null and is_instance_valid(_open) and not _open.is_queued_for_deletion():
		_queue.append(dialog)
		return
	_show(tree, dialog)

static func _show(tree: SceneTree, dialog: EggUnlockDialog) -> void:
	var layer := CanvasLayer.new()
	layer.layer = UNLOCK_LAYER
	layer.add_child(dialog)
	tree.root.add_child(layer)
	_open = dialog

func _init(title_key: String, mon_name: String, skill_names: Array) -> void:
	super()
	_title_key = title_key
	_mon_name = mon_name
	_skill_names = skill_names.duplicate()
	# auch während einer pausierten Szene bedienbar
	process_mode = Node.PROCESS_MODE_ALWAYS

func _accent() -> Color:
	return Monmap.RARITY_COLORS[Monmap.rarity_of(_mon_name)]

func _build(content: VBoxContainer) -> void:
	_opened_at = Time.get_ticks_msec()
	content.add_child(_title(tr(_title_key), SkillDetailPopup.GOLD))

	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 12)
	content.add_child(head)
	var image := TextureRect.new()
	image.custom_minimum_size = Vector2(64, 64)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	Monmap.show_on(image, _mon_name, 64)
	head.add_child(image)
	head.add_child(_text(tr("EGG_UNLOCK_TEXT").format({"mon": Helper.mon_display_name(_mon_name)}),
		IronPlate.TEXT_COLOR, ROW_FONT_SIZE))

	# Werte auf den Karten wie bei einem frisch geschlüpften Monster der Art (wie in der Sammlung)
	var mon := Monster.new(State.INITIAL_LEVEL, Monmap.mon_metainfos_by_name(_mon_name))
	var margin := SkillCardPaper.flame_margin()
	margin.size_flags_horizontal = SIZE_SHRINK_CENTER
	content.add_child(margin)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	SkillCardPaper.make_room_for_flames(row)
	margin.add_child(row)
	for skill_name in _skill_names:
		var skill := Skills.carried_egg_skill(skill_name)
		if skill.is_empty():
			continue
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		row.add_child(box)
		var card := EggSkillCard.create(skill, mon)
		card.custom_minimum_size = CARD_SIZE
		card.size_flags_horizontal = SIZE_SHRINK_CENTER
		box.add_child(card)
		var source := Skills.get_egg_skill_source(_mon_name, skill_name)
		if not source.is_empty():
			var label := _text(tr(source[1]), IronPlate.TEXT_COLOR, SOURCE_FONT_SIZE)
			label.custom_minimum_size.x = CARD_SIZE.x
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.modulate.a = 0.85
			box.add_child(label)
	content.add_child(_note(tr("EGG_UNLOCK_NOTE"), IronPlate.TEXT_COLOR))

func _unhandled_input(event: InputEvent) -> void:
	# Leertaste/Enter schließen wie der Knopf, Esc wie gewohnt
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		close()
		return
	super(event)

func close() -> void:
	if Time.get_ticks_msec() - _opened_at < CLOSE_GRACE_MSEC:
		return
	if is_queued_for_deletion():
		return
	var tree := get_tree()
	super()
	if _open == self:
		_open = null
	if not _queue.is_empty():
		_show(tree, _queue.pop_front())
