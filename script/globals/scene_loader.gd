extends Node

## Lädt beim Spielstart (Intro, intro.gd) alles Wichtige im Hintergrund vor und hält es fest, damit es im Cache bleibt:
## alle Szenen (samt ihrer Skripte) und Ressourcen und die kleinen Monsterbilder. Danach wechseln Szenen ohne Ladezeit, es gibt weder
## Lade-Bildschirm noch graues Bild.
##
## Benutzung: SceneLoader.change_scene("res://...tscn") statt get_tree().change_scene_to_file(...)
## (nimmt die vorgeladene Szene, sonst wird sie wie bisher direkt geladen).

## Gegen Deadlocks (das Spiel fror im Intro ganz ein, siehe loading_error.txt):
## - der Haupt-Thread wartet hier nie auf eine Datei (kein load() während des Vorladens, nur Status abfragen),
## - keine Sub-Threads (use_sub_threads = false),
## - Szenen und Ressourcen immer nur eine auf einmal: Kampf-Szenen binden sich gegenseitig per preload ein. Laden zwei
##   Threads je eine davon, wartet jeder auf die des anderen und beide werden nie fertig (battle.tscn, card_hand.tscn ...),
## - nur Bilder (hängen von nichts ab) laden parallel, erst nach allen Szenen (Reihenfolge der Warteschlange),
## - Skripte (.gd) werden nicht einzeln angefragt, sie kommen als Abhängigkeit der Szenen mit,
## - hängt eine Datei länger als STALL_SECONDS ohne Fortschritt, wird sie aufgegeben und gemeldet.

## so viele Bilder laden gleichzeitig
const IMAGE_PARALLEL := 4
## so lange darf das Vorladen ohne eine fertige Datei hängen, dann geht es ohne die hängenden weiter
const STALL_SECONDS := 8.0
## Ordner, deren Szenen und Ressourcen vorgeladen werden
const CODE_DIRS := ["res://script"]
const CODE_EXTENSIONS := ["tscn", "tres", "gdshader"]
## Monsterbilder: nur die kleinen Größen (Rad, Kampffeld, Karten). Die großen (1024 px) wären zu viel Grafikspeicher.
const MON_DIR := "res://assets/mons"
const MON_SUFFIXES := ["x64.png", "x256.png"]

## vorgeladen: Pfad -> Ressource
var loaded := {}
var _queue: Array[String] = []
var _running: Array[String] = []
var _total := 0
## Zeit seit der letzten fertigen Datei (STALL_SECONDS)
var _stalled := 0.0

## Protokoll jedes Ladeschritts nach user://scene_loader_debug.log (sofort geschrieben), falls es wieder hängt: auf true
const DEBUG_LOG := false
var _log_file: FileAccess
var _frame := 0

signal warm_up_finished

func _ready() -> void:
	if DEBUG_LOG:
		_log_file = FileAccess.open("user://scene_loader_debug.log", FileAccess.WRITE)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

## Startet das Vorladen von allem (CODE_DIRS, Monsterbilder)
func warm_up_everything() -> void:
	var paths: Array[String] = []
	for dir in CODE_DIRS:
		_collect(dir, CODE_EXTENSIONS, [], paths)
	_collect(MON_DIR, ["png"], MON_SUFFIXES, paths)
	warm_up(paths)

## Lädt paths im Hintergrund vor, ohne das Spiel anzuhalten
func warm_up(paths: Array) -> void:
	for path: String in paths:
		if not loaded.has(path) and not _queue.has(path) and not _running.has(path):
			_queue.append(path)
	_total = loaded.size() + _queue.size() + _running.size()
	_log("warm_up %d Dateien" % _queue.size())
	_stalled = 0.0
	set_process(true)

## Anteil 0..1 des Vorladens
func progress() -> float:
	return 1.0 if _total == 0 else float(loaded.size()) / _total

func is_done() -> bool:
	return _queue.is_empty() and _running.is_empty()

func change_scene(path: String) -> void:
	var scene: PackedScene = loaded.get(path)
	if scene == null:
		scene = load(path)
		loaded[path] = scene
	get_tree().change_scene_to_packed(scene)

func _process(delta: float) -> void:
	_frame += 1
	_log("frame %d running=%s" % [_frame, _running])
	_stalled += delta
	while not _queue.is_empty() and _running.size() < (IMAGE_PARALLEL if _queue[0].ends_with(".png") else 1):
		var path: String = _queue.pop_front()
		_log("next " + path)
		if ResourceLoader.has_cached(path):
			# schon im Cache (evtl. noch im Bau als Abhängigkeit einer anderen Datei): nur festhalten, nie darauf warten
			_log("cached " + path)
			loaded[path] = ResourceLoader.get_cached_ref(path)
		elif ResourceLoader.load_threaded_request(path, "", false) == OK:
			_running.append(path)
		else:
			push_warning("SceneLoader: konnte %s nicht anfragen" % path)
			loaded[path] = null
	for path in _running.duplicate():
		_log("status? " + path)
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_running.erase(path)
		_stalled = 0.0
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_log("get " + path)
			loaded[path] = ResourceLoader.load_threaded_get(path)
		else:
			# fehlerhafte oder nicht ladbare Datei: zählt als erledigt, wird später ganz normal geladen
			push_warning("SceneLoader: %s nicht geladen (Status %d)" % [path, status])
			loaded[path] = null
	if not _running.is_empty() and _stalled > STALL_SECONDS:
		# hängt: nicht weiter warten, das Spiel geht ohne diese Dateien weiter (werden später normal geladen)
		push_warning("SceneLoader: hängt seit %.0f s, gebe auf: %s" % [_stalled, ", ".join(_running)])
		for path in _running:
			loaded[path] = null
		_running.clear()
		_stalled = 0.0
	if is_done():
		set_process(false)
		warm_up_finished.emit()

## Sammelt Dateien rekursiv. Im exportierten Spiel heißen sie oft "x.png.import" / "x.tscn.remap", das wird abgeschnitten.
func _collect(dir_path: String, extensions: Array, suffixes: Array, into: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with(".") or sub == "addons":
			continue
		_collect(dir_path.path_join(sub), extensions, suffixes, into)
	for file in dir.get_files():
		var name := file.trim_suffix(".import").trim_suffix(".remap")
		if not extensions.has(name.get_extension()):
			continue
		if not suffixes.is_empty() and not suffixes.any(func(s): return name.ends_with(s)):
			continue
		var path := dir_path.path_join(name)
		if not into.has(path):
			into.append(path)

func _log(message: String) -> void:
	if _log_file:
		_log_file.store_line("%d %s" % [Time.get_ticks_msec(), message])
		_log_file.flush()
