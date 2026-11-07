extends ChestRewardDialog

## Relic-Auswahl nach einem Boss-Sieg (Boss-Feld oder Biom-Boss): bis zu RELIC_CHOICES
## noch nicht gesammelte Relics, eins davon darf genommen werden.

const RELIC_CHOICES := 3
const ACCENT := Color(0.55, 0.32, 0.75)

func _ready() -> void:
	use_chest_layout(BOX_TEXTURE)
	set_accent(ACCENT)
	set_title(tr("RELIC_REWARD_CHOOSE"))
	set_drag_hint("RELIC_REWARD_HINT")
	show_fixed_targets([], true)
	var offered = Relics.get_unowned()
	offered.shuffle()
	for id in offered.slice(0, RELIC_CHOICES):
		add_relic_card(self, id)
	play_chest_intro()

## Relic-Karte, auch von Schatz und Shop genutzt: wird in die Tasche gezogen
static func add_relic_card(dialog: RewardDialog, id: String) -> RewardDialog.RewardCard:
	var relic = Relics.get_relic(id)
	var take := func():
		Relics.add_relic(id)
	return dialog.add_bag_card(dialog.tr(relic.name), dialog.tr(relic.description), texture_icon(load(relic.icon)), take)
