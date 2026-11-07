extends Control

var monster: Monster:
	set(mon):
		monster = mon
		if _detail_popup:
			_detail_popup.hide_popup()
		if mon:
			info_container.init_with_mon(mon)
			# is egg selection view
			if is_in_selection:
				switch_image(mon)
				element_chip._init_color(mon)
				init_new_grid()
				init_skills(mon)
				remove_panel()
			else:
				# switch_image(mon)
				element_chip._init_color(mon)
				init_new_grid()
				init_skills(mon)
			toggle_panels()


@export var info_container: Control
@export var is_in_selection: bool = true

@export var selection_monster_image_panel: VBoxContainer
@export var monster_switcher: Control

@export var monster_texture: TextureRect

@export var element_chip: Control

@export var name_label: Label

@export var grid_container: GridContainer

@export var initial_skill_label: Label
@export var play_button: Button
@export var learn_button: Button

@export var first_panel: Panel

@export var type_splash: TextureRect
@export var magic_splash: TextureRect

@export var skill_info_container: ScrollContainer

@export var is_watching = false
@export var is_learning = false

@export var info_panel: Panel
@export var info_label: Label

@export var skill_panel: Panel

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Events.skill_label_pressed.connect(skill_label_pressed)
	toggle_panels()
	if not is_in_selection:
		monster = State.mons[0]

func toggle_panels() -> void:
	if is_in_selection:
		selection_monster_image_panel.visible = true
		monster_switcher.visible = false
		first_panel.visible = true
	else:
		monster_switcher.visible = true
		selection_monster_image_panel.visible = false

func switch_image(mon: Monster) -> void:
	name_label.text = Helper.mon_battle_name(mon)
	Monmap.show_on(monster_texture, mon._name, Monmap.SMALL)
	pass

func init_skills(mon: Monster) -> void:
	var map = ["damage_type", "name", "cost", "cooldown", "value"]
	for skill in mon._skills:
		var new_play_button = play_button.duplicate(DuplicateFlags.DUPLICATE_USE_INSTANTIATION | DuplicateFlags.DUPLICATE_SCRIPTS | DuplicateFlags.DUPLICATE_SIGNALS)
		new_play_button.visible = true
		new_play_button.pressed.connect(func(): 
			Events.mouse_event.emit({"action":Enums.MOUSE_ACTION.PLAY_CARD, "skill": skill})
			Events.card_selected.emit(skill))
		var new_learn_button = learn_button.duplicate(DuplicateFlags.DUPLICATE_USE_INSTANTIATION | DuplicateFlags.DUPLICATE_SCRIPTS | DuplicateFlags.DUPLICATE_SIGNALS)
		new_learn_button.visible = true
		new_learn_button.pressed.connect(func(): 
			Events.learn_skill.emit(skill))
		# layout
		#grid_container.add_child(new_info_button)
		for st in map:
			var dupe = (DuplicateFlags.DUPLICATE_USE_INSTANTIATION | DuplicateFlags.DUPLICATE_SCRIPTS | DuplicateFlags.DUPLICATE_SIGNALS) if st == "name" else DuplicateFlags.DUPLICATE_USE_INSTANTIATION
			var name_label: Label = initial_skill_label.duplicate(dupe)
			name_label.visible = true
			name_label.text = display_skill_or_questionmark(skill, tr(skill[st]) if st == "name" else Helper.format_number(skill[st]))
			if st == "name":
				print(skill.nature)
				var new_ls = name_label.label_settings.duplicate(DuplicateFlags.DUPLICATE_USE_INSTANTIATION)
				new_ls.font_color = Helper.color_by_type(skill.nature)
				if Skills.is_unlockable_egg_skill(mon, skill):
					name_label.text = tr("EGG_SKILL_TAG").format({"skill": name_label.text})
					name_label.tooltip_text = tr("EGG_SKILL_HINT")
					new_ls.font_color = Color(0.858824, 0.717647, 0.45098, 1)
				name_label.label_settings = new_ls
				name_label.skill = skill
			if st == "damage_type":
				if skill[st] == Enums.SKILL_DAMAGE_TYPE.PHYSICAL:
					var y = type_splash.duplicate(DuplicateFlags.DUPLICATE_USE_INSTANTIATION)
					y.visible = true
					grid_container.add_child(y)
				else:
					var y = magic_splash.duplicate(DuplicateFlags.DUPLICATE_USE_INSTANTIATION)
					y.visible = true
					grid_container.add_child(y)
				continue
			grid_container.add_child(name_label)
		if not is_in_selection and not is_learning:
			grid_container.add_child(new_play_button)
		if is_in_selection and not is_learning:
			var name_label: Label = initial_skill_label.duplicate(DuplicateFlags.DUPLICATE_USE_INSTANTIATION)
			name_label.visible = true
			name_label.text = ""
			grid_container.add_child(name_label)
		if is_learning and is_in_selection:
			grid_container.add_child(new_learn_button)

func display_skill_or_questionmark(skill, str: String) -> String:
	var return_string = str if skill.scouted else "?"
	return return_string

func init_new_grid() -> void:
	for c in grid_container.get_children():
		c.queue_free()
	var map = ["", "SKILL_HEADER_SKILL", "SKILL_HEADER_COST", "SKILL_HEADER_CD", "SKILL_HEADER_POWER", ""]
	var header_settings: LabelSettings = initial_skill_label.label_settings.duplicate()
	header_settings.font_color = SkillDetailPopup.GOLD
	for st in map:
		var name_label: Label = initial_skill_label.duplicate()
		name_label.visible = true
		name_label.text = tr(st)
		name_label.label_settings = header_settings
		grid_container.add_child(name_label)

func remove_panel() -> void:
	if get_tree():
		get_tree().create_tween().tween_method(first_panel.set_size, first_panel.size, Vector2(first_panel.size.x,0), 1)

var _detail_popup: SkillDetailPopup

## Details im Popup neben dem Widget; das Signal ist global, daher reagiert nur das Widget, dem der Skill gehört
func skill_label_pressed(skill) -> void:
	if monster == null or not monster._skills.has(skill):
		# Skill eines anderen Widgets: dessen Popup ersetzt unseres
		if _detail_popup:
			_detail_popup.hide_popup()
		return
	if _detail_popup == null:
		_detail_popup = SkillDetailPopup.new()
		add_child(_detail_popup)
	var lock_hint := ["CONFIGURATOR_LOCKED", "EGG_SKILL_HINT"] if Skills.is_unlockable_egg_skill(monster, skill) else []
	_detail_popup.show_skill(skill, monster, self, lock_hint)

func select_watching_mon(mon: Monster) -> void:
	if is_in_selection:
		monster = mon

#func _on_learnbutton_pressed(skill) -> void:
#	learn_skill.emit(skill)
