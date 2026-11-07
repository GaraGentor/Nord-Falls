extends Control

var enemy_mon: Monster

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	enemy_mon = Mons.generate_mons({"count": 1, "level": 1})[0]
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_pressed() -> void:
	enemy_mon.upgrade_by_level(1)
	var p_per_level = Helper.points_per_level(500)
	print("__________________")
	print("monlevel:", enemy_mon._level)
	print("monbst:", enemy_mon._best_points)
	print("monhp:", (enemy_mon._level * enemy_mon._growth.hp) * p_per_level)
	print("monatk:", enemy_mon._level * enemy_mon._growth.atk * p_per_level)
	print("mondef:", enemy_mon._level * enemy_mon._growth.def * p_per_level)
	print("monap:", enemy_mon._level * enemy_mon._growth.s_atk * p_per_level)
	print("monad:", enemy_mon._level * enemy_mon._growth.s_def * p_per_level)
	pass # Replace with function body.
