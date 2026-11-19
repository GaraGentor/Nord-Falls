extends Control

## Intro beim Spielstart: weißer Schriftzug "To the North" auf Schwarz. Währenddessen lädt SceneLoader alles vor
## (Szenen, Skripte, kleine Monsterbilder), danach gibt es im Spiel keine Ladezeiten mehr. Ist alles da und der
## Schriftzug lange genug zu sehen gewesen, blendet er aus und es geht zur Ei-Auswahl.

const NEXT_SCENE := "res://script/scenes/selection/selection.tscn"
const TITLE := "To the North"
const PIXEL_FONT := preload("res://script/ui/fonts/pxelfont/PixelifySans-VariableFont_wght.ttf")
const FONT_SIZE := 72
const FADE_IN_SECONDS := 1.2
const FADE_OUT_SECONDS := 0.6
## so lange steht der Schriftzug nach dem Einblenden mindestens, auch wenn das Vorladen schneller fertig ist
const MIN_SECONDS := 1.0

var _title: Label

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)
	_title = Label.new()
	_title.text = TITLE
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", PIXEL_FONT)
	_title.add_theme_font_size_override("font_size", FONT_SIZE)
	_title.add_theme_color_override("font_color", Color.WHITE)
	_title.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_title.modulate.a = 0.0
	add_child(_title)
	_run()

func _run() -> void:
	var fade_in := create_tween()
	fade_in.tween_property(_title, "modulate:a", 1.0, FADE_IN_SECONDS).set_trans(Tween.TRANS_SINE)
	# erst laden, wenn der Schriftzug ganz da ist: das Laden bremst die Bilder, das Einblenden würde sonst ruckeln
	await fade_in.finished
	var started := Time.get_ticks_msec()
	SceneLoader.warm_up_everything()
	if not SceneLoader.is_done():
		await SceneLoader.warm_up_finished
	var waited := (Time.get_ticks_msec() - started) / 1000.0
	if waited < MIN_SECONDS:
		await get_tree().create_timer(MIN_SECONDS - waited).timeout
	var fade_out := create_tween()
	fade_out.tween_property(_title, "modulate:a", 0.0, FADE_OUT_SECONDS).set_trans(Tween.TRANS_SINE)
	await fade_out.finished
	SceneLoader.change_scene(NEXT_SCENE)
