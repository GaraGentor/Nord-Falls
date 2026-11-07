extends ChestRewardDialog

## Skill-Auswahl aus dem Couvert der Bosse: das Couvert springt auf, darin liegen einzigartige Skills ohne Preis.
## Einer davon wird auf ein Monster gezogen, damit ist der Dialog vorbei. Man darf auch ohne Skill gehen.

const ACCENT := Color(0.8, 0.6, 0.3)
const CARD_MARGIN := 8
## Skill-Karten sind höher als andere Preise und liegen deshalb nebeneinander auf einem breiteren Teppich
const REWARD_STAGE_WIDTH := 600.0
const CARD_WIDTH := 160.0
const ROW_SPOTS: Array[Vector2] = [Vector2(0.18, 0.47), Vector2(0.5, 0.53), Vector2(0.82, 0.47)]
## Platz für die Elemente, die einem Monster fehlen, damit die Ziele beim Ziehen nicht springen
const MISSING_ROW_HEIGHT := 36.0

## Monster-Ziel -> Zeile mit den Elementen, die ihm für den gezogenen Skill fehlen
var _missing_rows := {}

func _ready() -> void:
	use_chest_layout(ENVELOPE_TEXTURE)
	_stage.custom_minimum_size.x = REWARD_STAGE_WIDTH
	set_accent(ACCENT)
	set_title(tr("SKILL_REWARD_CHOOSE"))
	set_drag_hint("SKILL_REWARD_HINT")
	show_fixed_targets(State.mons, false)
	for target in _fixed_targets:
		target.stats = StatsGrid.stacked_for(target.mon)
		target.box.add_child(target.stats)
		ignore_mouse_below(target)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.custom_minimum_size.y = MISSING_ROW_HEIGHT
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		target.box.add_child(row)
		_missing_rows[target] = row
	# die Ziele haben jetzt Werte und bleiben dadurch schon vor dem ersten Ziehen hell
	_lock_targets()
	for skill in Skills.reward_offers():
		add_skill_card(skill, _learn.bind(skill))
	_build_skip_button()
	play_chest_intro()

func _build_skip_button() -> void:
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	var skip := plate_button(tr("SKILL_REWARD_SKIP"))
	skip.pressed.connect(close)
	footer.add_child(skip)
	add_footer(footer)

## Papier bis zum Rand der Karte, der Text hält Abstand zum Rahmen
func _build_card(card: RewardCard, card_title: String, text: String) -> void:
	super(card, card_title, text)
	card.custom_minimum_size.x = CARD_WIDTH
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, CARD_MARGIN)
	card.remove_child(card.row)
	margin.add_child(card.row)
	card.add_child(margin)

func _loot_spots(count: int) -> Array:
	return ROW_SPOTS.duplicate() if count == ROW_SPOTS.size() else super(count)

func _learn(mon: Monster, skill: Dictionary) -> void:
	# über dem ganzen Dialog: auf dem Teppich hätten nicht alle Skills Platz
	if await learn_skill(skill, mon, self):
		State.taught_reward_skills.append(skill.name)
		close()

## Fertig ist der Dialog erst, wenn wirklich gelernt wurde (_learn)
func _taken(_card: RewardCard) -> void:
	pass

func _build_targets(card: RewardCard) -> void:
	super(card)
	_show_missing_elements(card.drag.skill)

func _hide_targets() -> void:
	super()
	_show_missing_elements({})

## Fehlende Elemente des gezogenen Skills unter den Monstern, die ihn noch nicht kennen
func _show_missing_elements(skill: Dictionary) -> void:
	for target: DropTarget in _missing_rows:
		var row: HBoxContainer = _missing_rows[target]
		for chip in row.get_children():
			row.remove_child(chip)
			chip.queue_free()
		if skill.is_empty() or Skills.knows_skill(target.mon, skill.name):
			continue
		for element: int in Skills.missing_elements(target.mon, skill):
			add_element_chip(row, element)
