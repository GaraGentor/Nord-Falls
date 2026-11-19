extends Node

## Lädt beim Spielstart (Intro, intro.gd) alles Wichtige im Hintergrund vor und hält es fest, damit es im Cache bleibt:
## alle Szenen und Skripte und die kleinen Monsterbilder. Danach wechseln Szenen ohne Ladezeit, es gibt weder
## Lade-Bildschirm noch graues Bild.
##
## Benutzung: SceneLoader.change_scene("res://...tscn") statt get_tree().change_scene_to_file(...)
## (nimmt die vorgeladene Szene, sonst wird sie wie bisher direkt geladen).

## so viele Dateien laden gleichzeitig
const PARALLEL := 8
## Ordner, deren Szenen und Skripte vorgeladen werden
const CODE_DIRS := ["res://script"]
const CODE_EXTENSIONS := ["tscn", "gd", "tres", "gdshader"]
## Monsterbilder: nur die kleinen Größen (Rad, Kampffeld, Karten). Die großen (1024 px) wären zu viel Grafikspeicher.
const MON_DIR := "res://assets/mons"
const MON_SUFFIXES := ["x64.png", "x256.png"]

## vorgeladen: Pfad -> Ressource
var loaded := {}
var _queue: Array[String] = []
var _running: Array[String] = []
var _total := 0

signal warm_up_finished

func _ready() -> void:
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

func _process(_delta: float) -> void:
	while _running.size() < PARALLEL and not _queue.is_empty():
		var path: String = _queue.pop_front()
		if ResourceLoader.has_cached(path):
			loaded[path] = load(path)
		elif ResourceLoader.load_threaded_request(path, "", true) == OK:
			_running.append(path)
	for path in _running.duplicate():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_running.erase(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			loaded[path] = ResourceLoader.load_threaded_get(path)
		else:
			# fehlerhafte oder nicht ladbare Datei: zählt als erledigt, wird später ganz normal geladen
			loaded[path] = null
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
