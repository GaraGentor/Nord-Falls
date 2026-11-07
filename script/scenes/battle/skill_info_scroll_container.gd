extends Control

@export var skill_name: Label
@export var skill_description: Label

var skill

func _init_with_skill(_skill) -> void:
	skill = _skill
	skill_description.text = Helper.skill_description(skill)
	skill_name.text = tr(skill.name)

func _on_close_info_button_pressed() -> void:
	visible = false
	
