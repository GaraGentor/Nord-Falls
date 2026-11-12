extends ChestRewardDialog

## Trophäen-Feld: drei Monster-Trophäen zur Wahl, die gewählte erhöht einen Wert eines eigenen
## Monsters um feste Punkte für den restlichen Run. Pro Biom-Tiefe werden die Trophäen stärker.
## Als Beute aus dem Kampf kommt nur eine einzelne Trophäe (gem_choices, siehe world_map.gd).
## Im Code heißen sie weiter "gem", gespeicherte Stat-Keys und Übersetzungs-Keys bleiben gleich.

const GEM_CHOICES := 3
const ACCENT := Color(0.2, 0.6, 0.65)

## Stat-Key (siehe Monster.gem_bonus) -> Anzeige
const STATS := {
	"hp": {"name": "GEM_HP", "desc": "GEM_HP_DESC", "stat": "STAT_HP", "icon": "res://assets/ui/trophies/lighthouse.svg"},
	"atk": {"name": "GEM_ATK", "desc": "GEM_ATK_DESC", "stat": "STAT_ATK", "icon": "res://assets/ui/trophies/branch_club.svg"},
	"def": {"name": "GEM_DEF", "desc": "GEM_DEF_DESC", "stat": "STAT_DEF", "icon": "res://assets/ui/trophies/crystal_hide.svg"},
	"s_atk": {"name": "GEM_S_ATK", "desc": "GEM_S_ATK_DESC", "stat": "STAT_SPA", "icon": "res://assets/ui/trophies/spark_tail.svg"},
	"s_def": {"name": "GEM_S_DEF", "desc": "GEM_S_DEF_DESC", "stat": "STAT_SPD", "icon": "res://assets/ui/trophies/mist_veil.svg"},
	"speed": {"name": "GEM_SPEED", "desc": "GEM_SPEED_DESC", "stat": "STAT_SPE", "icon": "res://assets/ui/trophies/storm_feather.svg"},
}

var gem_choices := GEM_CHOICES
var _bonus: int

func _ready() -> void:
	use_chest_layout(BAG_TEXTURE)
	set_accent(ACCENT)
	set_title(tr("GEM_CHOOSE"))
	set_drag_hint("GEM_HINT")
	show_fixed_targets(State.mons, false)
	show_gem_info(self)
	_bonus = DebugSettings.trophy_bonus(State.map_level)
	var stats = STATS.keys()
	stats.shuffle()
	for stat in stats.slice(0, gem_choices):
		# auf dem Teppich ist nur Platz für den Effekt, die Beschreibung steht im Tooltip
		add_gem_card(self, stat, _bonus, false).tooltip_text = tr(STATS[stat].desc)
	play_chest_intro()
	Tutorial.trigger("gems")

## Bild der Trophäe mit lebenden Pixeln
static func gem_icon(stat: String) -> Control:
	var icon := texture_icon(load(STATS[stat].icon))
	icon.material = Monmap.LIVING_MATERIAL
	return icon

## Monster-Ziele zeigen ihre gesammelten Trophäen und ihre Werte, beim Ziehen auch die Änderung durch die Trophäe
static func show_gem_info(dialog: RewardDialog) -> void:
	for target in dialog._fixed_targets:
		if target.mon == null:
			continue
		# wie im Map-Header: Trophäen-Anteil "(N)" hinter der Zahl, die Trophäen darunter (StatsGrid.show_trophies)
		target.stats = StatsGrid.stacked_for(target.mon, 15, true)
		target.box.add_child(target.stats)
		ignore_mouse_below(target)

## Trophäen-Karte, auch vom Shop genutzt: wird auf ein Monster gezogen.
## Die Änderung zeigen die Werte am Ziel (show_gem_info).
static func add_gem_card(dialog: RewardDialog, stat: String, bonus: int, with_desc := true) -> RewardDialog.RewardCard:
	var info: Dictionary = STATS[stat]
	var stat_name = dialog.tr(info.stat).trim_suffix(":")
	# Karte und Vorschau zeigen den Relikt-Bonus mit, gespeichert wird nur bonus (siehe Monster.gem_bonus)
	var shown_bonus: int = bonus + Relics.modify("trophy_bonus", 0)
	var text = dialog.tr("GEM_DESC").format({"stat": stat_name, "value": shown_bonus})
	if with_desc:
		text = dialog.tr(info.desc) + "\n" + text
	var give := func(mon: Monster):
		mon.add_gem(stat, bonus)
	return dialog.add_mon_card(dialog.tr(info.name), text, gem_icon(stat), dialog.tr("GEM_CHOOSE_MON"), State.mons, give, Callable(), {"stat": stat, "bonus": shown_bonus})
