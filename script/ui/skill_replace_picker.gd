class_name SkillReplacePicker
extends VBoxContainer

## Auswahl, welcher Skill vergessen wird, wenn ein Monster keinen freien Slot mehr hat.
## picked liefert den Index des zu ersetzenden Skills oder -1 bei Abbruch, danach entfernt sich die Auswahl selbst.
signal picked(index: int)

func _init(mon: Monster) -> void:
	theme = preload("res://script/ui/materials/pixel_font_theme.tres")
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = tr("JUDGEMENT_REPLACE_TITLE").format({"max": Skills.MAX_SKILLS})
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title)
	for i in mon._skills.size():
		var button := Button.new()
		button.text = tr("JUDGEMENT_REPLACE").format({"skill": tr(mon._skills[i].name)})
		button.add_theme_color_override("font_color", Helper.color_by_type(mon._skills[i].nature))
		button.flat = true
		button.pressed.connect(picked.emit.bind(i))
		add_child(button)
	var cancel := Button.new()
	cancel.text = tr("COMMON_CANCEL")
	cancel.flat = true
	cancel.pressed.connect(picked.emit.bind(-1))
	add_child(cancel)
	picked.connect(func(_index): queue_free())
