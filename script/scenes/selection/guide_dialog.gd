class_name GuideDialog
extends InfoDialog

## Startbildschirm: die Anleitung (TutorialPanel) als scrollbares Fenster, geöffnet über den Knopf "Anleitung".

const LIST_SIZE := Vector2(640, 480)

func _build(content: VBoxContainer) -> void:
	var guide := TutorialPanel.new()
	guide.custom_minimum_size = LIST_SIZE
	content.add_child(guide)
