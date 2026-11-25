class_name BiomePathDialog
extends InfoDialog

## Der ganze Biom-Pfad des Runs in groß, wie bei der Ei-Auswahl: geschaffte und aktuelles Biom hell,
## kommende abgedunkelt, der goldene Pixel hüpft bis zum aktuellen Biom. Klick auf ein Biom zeigt
## seine Stärken und Schwächen (BiomeInfoDialog öffnet sich darüber).

const BIOME_PATH := preload("res://script/scenes/selection/biome_path.gd")
const PATH_SIZE := Vector2(1150, 96)
## Platz über den Feldern für die Stufen-Punkte und den Hüpfer
const PATH_TOP_SPACE := 56

var _biomes: Array
var _current: int

## Öffnet den Pfad (biomes: Element-Masken aller Tiefen, current: aktuelle Tiefe ab 0) über host
static func open(host: Node, biomes: Array, current: int) -> InfoDialog:
	return InfoDialog.present(host, BiomePathDialog.new(biomes, current))

func _init(biomes: Array, current: int) -> void:
	super()
	_biomes = biomes
	_current = current

func _accent() -> Color:
	if _current >= 0 and _current < _biomes.size():
		return Color(ColorMap.get_combo(_biomes[_current]).color)
	return IronPlate.RIM

func _build(content: VBoxContainer) -> void:
	content.add_child(_title(tr("MAP_PATH_TITLE"), SkillDetailPopup.GOLD))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", PATH_TOP_SPACE)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(margin)
	var path: Control = BIOME_PATH.new()
	path.custom_minimum_size = PATH_SIZE
	path.node_height = PATH_SIZE.y
	margin.add_child(path)
	# bis einschließlich des aktuellen Bioms gilt als erreicht
	path.show_path(_biomes, _current + 1)

	content.add_child(_note(tr("BIOME_INFO_HINT"), IronPlate.TEXT_COLOR))
