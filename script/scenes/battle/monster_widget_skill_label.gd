extends Label

var skill

func _on_gui_input(event: InputEvent) -> void:
	print("click?")
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			print("Linke Maustaste losgelassen!")
			# Events.call_skill_card.emit({"action": selected_skill})
			Events.skill_label_pressed.emit(skill)
