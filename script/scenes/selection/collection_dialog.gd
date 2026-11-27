class_name CollectionDialog
extends InfoDialog

## Startbildschirm: alle Monster-Arten, geöffnet über den Knopf "Sammlung".
## Gesehene Arten (SaveManager "seen_monsters" oder spielbar) mit Bild und Namen, die anderen als schwarze Silhouette.
## Jede zeigt ihre Seltenheit und ab welchem Biom sie häufig auftaucht (Map.usual_depth).
## Besessene Arten (Start-Monster, gefangen) haben ein abgedunkeltes Ei im Hintergrund der Kachel.
## Klick auf eine besessene Art zeigt alle ihre Ei-Attacken, freigeschaltete und gesperrte (SpeciesSkillsDialog).

const LIST_SIZE := Vector2(700, 470)
const COLUMNS := 4
const ENTRY_WIDTH := 150.0
const IMAGE_SIZE := Vector2(110, 110)
const NAME_FONT_SIZE := 24
const INFO_FONT_SIZE := 24
const SILHOUETTE := Color(0.04, 0.04, 0.05)
const UNKNOWN_COLOR := Color(0.5, 0.5, 0.48)
## Ei hinter besessenen Arten: füllt die Kachel bis auf den Rand, abgedunkelt, damit der Inhalt lesbar bleibt
const EGG_ICON := preload("res://assets/ui/eggs/common_1.png")
const OWNED_EGG_MARGIN := 6
const OWNED_EGG_TINT := Color(0.42, 0.42, 0.42, 0.75)
## so weit darf sich der Finger zwischen Drücken und Loslassen bewegen, damit es noch als Klick zählt
const CLICK_SLOP := 12.0

func _build(content: VBoxContainer) -> void:
	content.add_child(_title(tr("COLLECTION_TITLE"), SkillDetailPopup.GOLD))
	var species := Monmap.mons.filter(func(meta): return not meta.has("bounty_target"))
	species.sort_custom(func(a, b):
		var rarity_a: int = a.get("rarity", Enums.MON_RARITY.COMMON)
		var rarity_b: int = b.get("rarity", Enums.MON_RARITY.COMMON)
		return rarity_a < rarity_b if rarity_a != rarity_b else a.name.naturalnocasecmp_to(b.name) < 0)
	var seen := _seen_names()
	var owned := Helper.get_all_owned_monster_names()
	var known := species.filter(func(meta): return seen.has(meta.name)).size()
	content.add_child(_text(tr("COLLECTION_PROGRESS").format({"seen": known, "total": species.size()}),
		IronPlate.TEXT_COLOR, ROW_FONT_SIZE))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = LIST_SIZE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = SIZE_EXPAND | SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var clickable := {}
	for meta: Dictionary in species:
		var entry := _entry(meta, seen.has(meta.name), owned.has(meta.name))
		grid.add_child(entry)
		# die Ei-Attacken gibt es nur bei Arten, die man besitzt
		if owned.has(meta.name):
			clickable[entry] = meta.name
	# nur der ScrollContainer selbst nimmt Mausrad und Ziehen an, besessene Arten zusätzlich einen Klick
	RewardDialog.ignore_mouse_below(grid)
	for entry in clickable:
		_make_clickable(entry, clickable[entry])

## Gesehen sind Gegner und Start-Eier (seen_monsters) sowie alles, was schon als Start-Monster spielbar ist
func _seen_names() -> Array:
	var names: Array = SaveManager.save_data["seen_monsters"].duplicate()
	for mon_name in Helper.get_all_owned_monster_names():
		if not names.has(mon_name):
			names.append(mon_name)
	return names

## Besessene Art (Start-Monster oder schon gefangen): abgedunkeltes Ei in ihrer Seltenheitsfarbe über die ganze
## Kachel, zwischen Eisenplatte und Inhalt
func _add_owned_egg(panel: PanelContainer, rarity: int) -> void:
	var holder := MarginContainer.new()
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		holder.add_theme_constant_override("margin_" + side, OWNED_EGG_MARGIN)
	var egg := TextureRect.new()
	egg.texture = EGG_ICON
	egg.material = Monmap.egg_material(rarity)
	egg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	egg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	egg.modulate = OWNED_EGG_TINT
	egg.mouse_filter = MOUSE_FILTER_IGNORE
	holder.add_child(egg)
	panel.add_child(holder)
	# hinter den Inhalt, aber über die Eisenplatte (IronPlate.frame: Platte, dann Inhalt)
	panel.move_child(holder, 1)

func _entry(meta: Dictionary, seen: bool, owned: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = ENTRY_WIDTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	IronPlate.frame(panel, column, 8, 8)
	if owned:
		_add_owned_egg(panel, meta.get("rarity", Enums.MON_RARITY.COMMON))

	var image := TextureRect.new()
	image.custom_minimum_size = IMAGE_SIZE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_horizontal = SIZE_SHRINK_CENTER
	Monmap.show_on(image, meta.name, IMAGE_SIZE.x)
	if not seen:
		# das Monster-Material übernimmt modulate, so bleibt nur der Umriss
		image.modulate = SILHOUETTE
	column.add_child(image)

	var title := _text(Helper.mon_display_name(meta.name) if seen else "???",
		SkillDetailPopup.GOLD if seen else UNKNOWN_COLOR, NAME_FONT_SIZE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = ENTRY_WIDTH - 16
	column.add_child(title)
	var rarity: int = meta.get("rarity", Enums.MON_RARITY.COMMON)
	column.add_child(_text(tr(Monmap.RARITY_LABELS[rarity]), Monmap.RARITY_COLORS[rarity], INFO_FONT_SIZE))
	var where := tr("COLLECTION_BOSS_ONLY").format({"biome": Map.rarity_min_depth(rarity) + 1}) if rarity == Enums.MON_RARITY.MYTHIC \
		else tr("COLLECTION_FROM_BIOME").format({"biome": Map.usual_depth(rarity) + 1})
	column.add_child(_text(where, IronPlate.TEXT_COLOR, INFO_FONT_SIZE))
	var requirement := _requirement_text(rarity)
	if requirement != "":
		var label := _text(requirement, UNKNOWN_COLOR, INFO_FONT_SIZE)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = ENTRY_WIDTH - 16
		column.add_child(label)
	return panel

## Noch fehlender Besitz, damit die Seltenheit auftauchen darf (Map.RARITY_UNLOCKS), leer wenn erfüllt
func _requirement_text(rarity: int) -> String:
	var needed: Dictionary = Map.RARITY_UNLOCKS.get(rarity, {}).get("owned", {})
	var owned := Map.owned_rarity_counts()
	var missing := []
	for needed_rarity in needed:
		if owned.get(needed_rarity, 0) < needed[needed_rarity]:
			missing.append("%d× %s" % [needed[needed_rarity], tr(Monmap.RARITY_LABELS[needed_rarity])])
	if missing.is_empty():
		return ""
	return tr("COLLECTION_REQUIRES").format({"list": ", ".join(missing)})

## Klick (ohne Wischen) auf eine besessene Art öffnet ihre Ei-Attacken (SpeciesSkillsDialog)
func _make_clickable(panel: Control, mon_name: String) -> void:
	panel.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	panel.tooltip_text = tr("COLLECTION_SKILLS_OPEN")
	on_click(panel, func(): InfoDialog.present(self, SpeciesSkillsDialog.new(mon_name)))

## Klick ohne Wischen auf control (Wischen scrollt weiter die Liste darunter)
static func on_click(control: Control, action: Callable) -> void:
	control.mouse_filter = MOUSE_FILTER_PASS
	var press := {"pos": Vector2.INF}
	control.gui_input.connect(func(event: InputEvent):
		if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
			return
		if event.pressed:
			press.pos = event.global_position
		elif press.pos != Vector2.INF and event.global_position.distance_to(press.pos) < CLICK_SLOP:
			press.pos = Vector2.INF
			action.call())

## Alle Ei-Attacken einer Art: oben die freigeschalteten (darunter, woher sie kommen),
## darunter die gesperrten unter Ketten mit dem Hinweis, wie man sie freischaltet (wie im Konfigurator).
## Klick auf eine gesperrte Karte nimmt Ketten und Hinweis weg, bis man woanders hinklickt (_reveal).
## Klick auf eine freigeschaltete Karte zeigt darunter, wodurch genau sie freigeschaltet wurde (_show_source).
class SpeciesSkillsDialog extends InfoDialog:
	const LIST_SIZE := Vector2(760, 420)
	const COLUMNS := 3
	const CARD_SIZE := Vector2(200, 210)
	const SOURCE_FONT_SIZE := 24

	var _mon_name: String
	var _locked_cards: Array[EggSkillCard] = []
	## Gerade aufgedeckte gesperrte Karte (null = keine)
	var _revealed: EggSkillCard
	## Freigeschaltete Karten -> Label mit der genauen Herkunft (Skills.get_egg_skill_source), erst nach Klick sichtbar
	var _source_details := {}
	## Freigeschaltete Karte, deren Herkunft gerade offen ist (null = keine)
	var _source_shown: EggSkillCard

	func _init(mon_name: String) -> void:
		super()
		_mon_name = mon_name

	func _accent() -> Color:
		return Monmap.RARITY_COLORS[Monmap.rarity_of(_mon_name)]

	func _build(content: VBoxContainer) -> void:
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
		head.add_child(_title(Helper.mon_display_name(_mon_name), SkillDetailPopup.GOLD))

		var egg_skills := Skills.get_all_egg_skills(_mon_name)
		var unlocked: int = egg_skills.available.size()
		var total: int = unlocked + egg_skills.locked.size()
		content.add_child(_text(tr("SELECTION_EGG_MOVES_HINT").format(
			{"unlocked": unlocked, "total": total, "missing": total - unlocked}), IronPlate.TEXT_COLOR, ROW_FONT_SIZE))

		# Werte auf den Karten wie bei einem frisch geschlüpften Monster der Art
		var mon := Monster.new(State.INITIAL_LEVEL, Monmap.mon_metainfos_by_name(_mon_name))
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = LIST_SIZE
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		content.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 8)
		scroll.add_child(list)

		if unlocked > 0:
			list.add_child(_section(tr("COLLECTION_SKILLS_UNLOCKED")))
			var grid := _grid(list)
			for skill_name in egg_skills.available:
				var skill := Skills.carried_egg_skill(skill_name)
				if skill.is_empty():
					continue
				var source := Skills.get_egg_skill_source(_mon_name, skill_name)
				var card := EggSkillCard.create(skill, mon)
				var box := _add_card(grid, card, tr(source[0]) if not source.is_empty() else "")
				if not source.is_empty():
					var detail := _text(tr(source[1]), SkillDetailPopup.GOLD, SOURCE_FONT_SIZE)
					detail.custom_minimum_size.x = CARD_SIZE.x
					detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					detail.visible = false
					box.add_child(detail)
					_source_details[card] = detail
		if not egg_skills.locked.is_empty():
			var heading := _section(tr("COLLECTION_SKILLS_LOCKED"))
			heading.add_theme_color_override("font_color", UNKNOWN_COLOR)
			list.add_child(heading)
			var grid := _grid(list)
			for skill_name in egg_skills.locked:
				var skill := Skills.get_skill(skill_name)
				if skill.is_empty():
					continue
				var hint: Array = egg_skills.hints[skill_name]
				var card := EggSkillCard.create(skill, mon, hint[0], hint[1])
				_add_card(grid, card, "")
				_locked_cards.append(card)
		# nur die Scrollview nimmt Mausrad und Ziehen an, die Beschreibungen scrollen von selbst
		RewardDialog.ignore_mouse_below(list)
		# gesperrte Karten zusätzlich einen Klick: aufdecken
		for card in _locked_cards:
			card.mouse_default_cursor_shape = CURSOR_POINTING_HAND
			CollectionDialog.on_click(card, _reveal.bind(card))
		# freigeschaltete Karten: Klick zeigt die Herkunft
		for card: EggSkillCard in _source_details:
			card.mouse_default_cursor_shape = CURSOR_POINTING_HAND
			card.tooltip_text = tr("COLLECTION_SOURCE_CLICK")
			CollectionDialog.on_click(card, _show_source.bind(card))

	## Zeigt unter der freigeschalteten Karte, wodurch sie freigeschaltet wurde; nochmal klicken blendet es aus
	func _show_source(card: EggSkillCard) -> void:
		var previous := _source_shown
		_hide_source()
		if previous == card:
			return
		_source_shown = card
		_source_details[card].visible = true
		card.set_selected(true)

	func _hide_source() -> void:
		if _source_shown == null:
			return
		_source_details[_source_shown].visible = false
		_source_shown.set_selected(false)
		_source_shown = null

	## Deckt die gesperrte Karte auf, eine vorher aufgedeckte geht wieder unter die Ketten
	func _reveal(card: EggSkillCard) -> void:
		if _revealed == card:
			return
		if _revealed != null:
			_revealed.set_revealed(false)
		_revealed = card
		card.set_revealed(true)

	## Klick neben die aufgedeckte Karte: Ketten und Hinweis kommen zurück
	func _input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			return
		# Klick neben die Karte mit offener Herkunft: wieder zu
		if _source_shown != null and not _source_shown.get_global_rect().has_point(event.global_position):
			_hide_source()
		if _revealed == null:
			return
		if not _revealed.get_global_rect().has_point(event.global_position):
			_revealed.set_revealed(false)
			_revealed = null

	## Karten-Raster mit Platz für die Rand-Effekte der Karten
	func _grid(list: VBoxContainer) -> GridContainer:
		var margin := SkillCardPaper.flame_margin()
		margin.size_flags_horizontal = SIZE_SHRINK_CENTER
		list.add_child(margin)
		var grid := GridContainer.new()
		grid.columns = COLUMNS
		SkillCardPaper.make_room_for_flames(grid)
		margin.add_child(grid)
		return grid

	func _add_card(grid: GridContainer, card: EggSkillCard, note: String) -> VBoxContainer:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		grid.add_child(box)
		card.custom_minimum_size = CARD_SIZE
		card.size_flags_horizontal = SIZE_SHRINK_CENTER
		box.add_child(card)
		if note != "":
			var label := _text(note, IronPlate.TEXT_COLOR, SOURCE_FONT_SIZE)
			label.custom_minimum_size.x = CARD_SIZE.x
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.modulate.a = 0.8
			box.add_child(label)
		return box
