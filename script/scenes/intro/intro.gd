extends Control

## Intro beim Spielstart: weißer Schriftzug "To the North" auf Schwarz. Währenddessen lädt SceneLoader alles vor
## (Szenen, Skripte, kleine Monsterbilder), danach gibt es im Spiel keine Ladezeiten mehr. Ist alles da und der
## Schriftzug lange genug zu sehen gewesen, blendet er aus und es geht zur Ei-Auswahl.
## Dauert das Vorladen länger (langsame PCs, Handys), zeigt unten mittig eine Reihe Monster den Fortschritt:
## erst sieht man nichts, dann bauen sie sich nacheinander von unten nach oben auf.

const NEXT_SCENE := "res://script/scenes/selection/selection.tscn"
const TITLE := "To the North"
const PIXEL_FONT := preload("res://script/ui/fonts/m5x7/m5x7.ttf")
const FONT_SIZE := 108
const FADE_IN_SECONDS := 1.2
const FADE_OUT_SECONDS := 0.6
## so lange steht der Schriftzug nach dem Einblenden mindestens, auch wenn das Vorladen schneller fertig ist
const MIN_SECONDS := 1.0

## Ladeanzeige: so viele Monster, so groß, so weit über dem unteren Rand
const LOADER_MONS := 5
const LOADER_MON_SIZE := 72.0
const LOADER_GAP := 18.0
const LOADER_BOTTOM_MARGIN := 70.0
## erst wenn das Vorladen so lange dauert, erscheint die Anzeige (schnelle PCs sehen sie nie)
const LOADER_DELAY := 0.4
## so schnell holt die Anzeige den echten Fortschritt ein (pro Sekunde), damit sie nicht springt
const LOADER_CATCH_UP := 6.0

var _title: Label
## je Monster: {"clip": Control, "art": TextureRect}
var _loader_slots: Array[Dictionary] = []
var _loader: HBoxContainer
var _shown_progress := 0.0
var _loading := false

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
	_build_loader()
	set_process(false)
	_run()

func _run() -> void:
	var fade_in := create_tween()
	fade_in.tween_property(_title, "modulate:a", 1.0, FADE_IN_SECONDS).set_trans(Tween.TRANS_SINE)
	# erst laden, wenn der Schriftzug ganz da ist: das Laden bremst die Bilder, das Einblenden würde sonst ruckeln
	await fade_in.finished
	var started := Time.get_ticks_msec()
	SceneLoader.warm_up_everything()
	if not SceneLoader.is_done():
		_loading = true
		set_process(true)
		get_tree().create_timer(LOADER_DELAY).timeout.connect(_show_loader)
		await SceneLoader.warm_up_finished
		# die Anzeige läuft noch bis zum Ende voll, damit man das letzte Monster ganz sieht
		if _loader.visible:
			while _shown_progress < 0.999:
				await get_tree().process_frame
		_loading = false
	var waited := (Time.get_ticks_msec() - started) / 1000.0
	if waited < MIN_SECONDS:
		await get_tree().create_timer(MIN_SECONDS - waited).timeout
	var fade_out := create_tween().set_parallel()
	fade_out.tween_property(_title, "modulate:a", 0.0, FADE_OUT_SECONDS).set_trans(Tween.TRANS_SINE)
	if _loader.visible:
		fade_out.tween_property(_loader, "modulate:a", 0.0, FADE_OUT_SECONDS).set_trans(Tween.TRANS_SINE)
	await fade_out.finished
	SceneLoader.change_scene(NEXT_SCENE)

## Reihe aus zufälligen gewöhnlichen Monstern unten mittig, noch unsichtbar
func _build_loader() -> void:
	_loader = HBoxContainer.new()
	_loader.add_theme_constant_override("separation", int(LOADER_GAP))
	_loader.alignment = BoxContainer.ALIGNMENT_CENTER
	_loader.mouse_filter = MOUSE_FILTER_IGNORE
	_loader.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM, PRESET_MODE_MINSIZE)
	_loader.grow_horizontal = GROW_DIRECTION_BOTH
	_loader.grow_vertical = GROW_DIRECTION_BEGIN
	_loader.offset_bottom = -LOADER_BOTTOM_MARGIN
	_loader.visible = false
	add_child(_loader)
	var names: Array = Monmap.mons.filter(func(m): return m.rarity == Enums.MON_RARITY.COMMON).map(func(m): return m.name)
	names.shuffle()
	for mon_name: String in names.slice(0, LOADER_MONS):
		var slot := Control.new()
		slot.custom_minimum_size = Vector2.ONE * LOADER_MON_SIZE
		slot.mouse_filter = MOUSE_FILTER_IGNORE
		var clip := Control.new()
		clip.clip_contents = true
		clip.mouse_filter = MOUSE_FILTER_IGNORE
		slot.add_child(clip)
		var art := TextureRect.new()
		art.texture = Monmap.texture(mon_name, LOADER_MON_SIZE)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.material = Monmap.MONSTER_MATERIAL
		art.mouse_filter = MOUSE_FILTER_IGNORE
		art.size = Vector2.ONE * LOADER_MON_SIZE
		clip.add_child(art)
		_loader.add_child(slot)
		_loader_slots.append({"clip": clip, "art": art})
	_apply_progress(0.0)

func _show_loader() -> void:
	if not _loading:
		return
	_loader.visible = true

func _process(delta: float) -> void:
	_shown_progress = move_toward(_shown_progress, SceneLoader.progress(), delta * LOADER_CATCH_UP * maxf(SceneLoader.progress() - _shown_progress, 0.05))
	if SceneLoader.is_done():
		_shown_progress = move_toward(_shown_progress, 1.0, delta * 2.0)
	_apply_progress(_shown_progress)
	if not _loading:
		set_process(false)

## Monster nacheinander füllen: jedes zeigt von unten her so viel, wie sein Anteil am Fortschritt erreicht ist
func _apply_progress(progress: float) -> void:
	var count := _loader_slots.size()
	for i in count:
		var fill := clampf(progress * count - i, 0.0, 1.0)
		var visible_height := LOADER_MON_SIZE * fill
		var clip: Control = _loader_slots[i].clip
		var art: TextureRect = _loader_slots[i].art
		clip.position = Vector2(0, LOADER_MON_SIZE - visible_height)
		clip.size = Vector2(LOADER_MON_SIZE, visible_height)
		art.position = Vector2(0, -(LOADER_MON_SIZE - visible_height))
