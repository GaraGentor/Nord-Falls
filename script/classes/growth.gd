class_name Growth
extends RefCounted

var hp: float
var atk: float
var def: float
var s_atk: float
var s_def: float
var speed: float

const ATTRS := ["hp", "atk", "def", "s_atk", "s_def", "speed"]
# Wie stark jeder Anteil pro Run vom Profil der Art abweichen darf (0.15 = ±15 %)
const MAX_DEVIATION := 0.15

# preferred: bevorzugte Anteile der Art in Prozent (Monmap "preferred_stats"), Summe 100
func _init(preferred: Dictionary) -> void:
	# Schritt 1: jeden Anteil zufällig um bis zu ±MAX_DEVIATION verschieben
	var sum := 0.0
	for a in ATTRS:
		self[a] = preferred[a] * (1.0 + randf_range(-MAX_DEVIATION, MAX_DEVIATION))
		sum += self[a]

	# Schritt 2: wieder auf Summe 1 bringen, damit die Basiswerte-Summe (best_points) erhalten bleibt
	for a in ATTRS:
		self[a] /= sum
