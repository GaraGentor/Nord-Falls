class_name MovesParticlesView
extends TextureRect

## Züge-Partikel mit dem "Lebende Pixel"-Shader der Monsterbilder: Der Shader braucht ein zusammenhängendes
## Bild, deshalb laufen die Partikel in einem eigenen SubViewport und dieses Rect zeigt dessen Textur.

@export var viewport: SubViewport
@export var particles: GPUParticles2D

var emitting: bool:
	get:
		return particles.emitting
	set(value):
		particles.emitting = value

func _ready() -> void:
	texture = viewport.get_texture()

## Partikel auf diesen Punkt im Eltern-Control zentrieren
func center_on(point: Vector2) -> void:
	position = point - size / 2

func restart() -> void:
	particles.restart()
