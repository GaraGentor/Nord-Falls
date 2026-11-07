extends RewardDialog

## Rastlager: letztes Feld jedes Pfads vor dem Boss (Map.PATH_TYPE.HUB). Bietet drei Stationen,
## jede einmal nutzbar: Ausruhen (Lager), Laden und Trainer. Während eine Station offen ist,
## ist das Rastlager ausgeblendet und kommt danach wieder, bis man mit "Weiter" aufbricht.

const HEAL_CAMP_SCENE = preload("res://script/scenes/heal_camp/heal_camp.tscn")
const SHOP_SCENE = preload("res://script/scenes/shop/shop.tscn")
const TRAINER_SCENE = preload("res://script/scenes/trainer/trainer.tscn")

const ACCENT := Color(0.35, 0.65, 0.3)
const STATION_ICON_SIZE := 220
const STATION_FONT_SIZE := 22
const DONE_MODULATE := Color(0.5, 0.5, 0.5)

func _ready() -> void:
	use_map_layout()
	set_accent(ACCENT)
	set_title(tr("HUB_TITLE"))
	set_drag_hint("HUB_DESC")
	# keine Preise und Ziele, nur die Stationen
	_columns.visible = false

	var stations := HBoxContainer.new()
	stations.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stations.add_theme_constant_override("separation", 20)
	stations.theme = LABEL_THEME
	stations.add_child(_station("HUB_REST", Map.ICONS[Map.PATH_TYPE.CAMP], HEAL_CAMP_SCENE))
	stations.add_child(_station(Map.type_label(Map.PATH_TYPE.SHOP), Map.ICONS[Map.PATH_TYPE.SHOP], SHOP_SCENE))
	stations.add_child(_station(Map.type_label(Map.PATH_TYPE.TRAINER), Map.ICONS[Map.PATH_TYPE.TRAINER], TRAINER_SCENE))
	add_footer(stations)

	var continue_button := plate_button(tr("HUB_CONTINUE"))
	continue_button.custom_minimum_size = Vector2(220, 50)
	continue_button.add_theme_font_size_override("font_size", STATION_FONT_SIZE)
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_button.pressed.connect(close)
	add_footer(continue_button)

func _station(label: String, icon: Texture2D, scene: PackedScene) -> Button:
	var button := plate_button(tr(label))
	button.icon = icon
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_constant_override("icon_max_width", STATION_ICON_SIZE)
	button.add_theme_font_size_override("font_size", STATION_FONT_SIZE)
	button.pressed.connect(_open_station.bind(button, scene))
	return button

## Station öffnen, danach ist sie verbraucht (der Laden würfelt sonst bei jedem Öffnen neue Ware)
func _open_station(button: Button, scene: PackedScene) -> void:
	button.disabled = true
	button.text = tr("HUB_DONE").format({"station": button.text})
	button.modulate = DONE_MODULATE
	var station := scene.instantiate()
	visible = false
	station.tree_exited.connect(func(): visible = true)
	get_parent().add_child(station)
	station.visible = true
