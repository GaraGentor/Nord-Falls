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

## Wie weit die Partikel fliegen (1 = wie im Material), ihre Größe bleibt gleich
func set_range(factor: float) -> void:
	if is_equal_approx(factor, 1.0):
		return
	var mat := particles.process_material.duplicate() as ParticleProcessMaterial
	mat.emission_sphere_radius *= factor
	mat.initial_velocity_min *= factor
	mat.initial_velocity_max *= factor
	mat.gravity *= factor
	particles.process_material = mat

func restart() -> void:
	particles.restart()
