class_name CollectionDialog
extends InfoDialog

## Startbildschirm: alle Monster-Arten, geöffnet über den Knopf "Sammlung".
## Gesehene Arten (SaveManager "seen_monsters" oder spielbar) mit Bild und Namen, die anderen als schwarze Silhouette.
## Jede zeigt ihre Seltenheit und ab welchem Biom sie häufig auftaucht (Map.usual_depth).

const LIST_SIZE := Vector2(700, 470)
const COLUMNS := 4
const ENTRY_WIDTH := 150.0
const IMAGE_SIZE := Vector2(110, 110)
const NAME_FONT_SIZE := 17
const INFO_FONT_SIZE := 14
const SILHOUETTE := Color(0.04, 0.04, 0.05)
const UNKNOWN_COLOR := Color(0.5, 0.5, 0.48)

func _build(content: VBoxContainer) -> void:
	content.add_child(_title(tr("COLLECTION_TITLE"), SkillDetailPopup.GOLD))
	var species := Monmap.mons.filter(func(meta): return not meta.has("bounty_target"))
	species.sort_custom(func(a, b):
		var rarity_a: int = a.get("rarity", Enums.MON_RARITY.COMMON)
		var rarity_b: int = b.get("rarity", Enums.MON_RARITY.COMMON)
		return rarity_a < rarity_b if rarity_a != rarity_b else a.name.naturalnocasecmp_to(b.name) < 0)
	var seen := _seen_names()
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
	for meta: Dictionary in species:
		grid.add_child(_entry(meta, seen.has(meta.name)))
	# nur der ScrollContainer selbst nimmt Mausrad und Ziehen an
	RewardDialog.ignore_mouse_below(grid)

## Gesehen sind Gegner und Start-Eier (seen_monsters) sowie alles, was schon als Start-Monster spielbar ist
func _seen_names() -> Array:
	var names: Array = SaveManager.save_data["seen_monsters"].duplicate()
	for mon_name in Helper.get_all_owned_monster_names():
		if not names.has(mon_name):
			names.append(mon_name)
	return names

func _entry(meta: Dictionary, seen: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = ENTRY_WIDTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	IronPlate.frame(panel, column, 8, 8)

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
	var where := tr("COLLECTION_BOSS_ONLY") if rarity == Enums.MON_RARITY.MYTHIC \
		else tr("COLLECTION_FROM_BIOME").format({"biome": Map.usual_depth(rarity) + 1})
	column.add_child(_text(where, IronPlate.TEXT_COLOR, INFO_FONT_SIZE))
	return panel
