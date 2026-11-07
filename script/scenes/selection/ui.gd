extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Events.select_initial_mon.connect(refresh_ui)

func refresh_ui(index: int) -> void:
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
