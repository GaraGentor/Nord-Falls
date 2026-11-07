extends TextureRect

var _mon

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Events.monster_faints.connect(_remove_mon)
	pass # Replace with function body.

func _remove_mon(mon) -> void:
	if _mon == mon:
		visible = false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
