extends SceneTree
## Bereitet neue Monsterbilder auf: Für jeden Ordner unter assets/mons/<nr>/ ohne <nr>_front.png wird das
## Rohbild (jpg/png, z. B. aus einem Bildgenerator) freigestellt, quadratisch zugeschnitten und in allen Größen
## gespeichert, die Monmap.texture() erwartet (FRONT_SIZES / BACK_SIZES). Die Rückansicht ist vorerst das Frontbild.
##
## Aufruf aus dem Projektordner:
##   godot --headless --path . --script res://tools/mon_images.gd            (nur Ordner ohne Frontbild)
##   godot --headless --path . --script res://tools/mon_images.gd -- --force 17 18   (diese Ordner neu erzeugen)
##
## Freistellen: Vom Bildrand aus wird jeder fast weiße, ungesättigte Pixel transparent (Flood-Fill). Umrandete
## weiße Flächen im Monster (Dampf, Augenglanz) bleiben so erhalten. Pixel am Rand werden je nach Helligkeit
## halbtransparent, damit keine weißen Säume bleiben.

const MONS_DIR := "res://assets/mons"
const FRONT_SIZES := [64, 128, 256, 512, 1024]
const BACK_SIZES := [256, 512, 1024]
## So hell (kleinster Farbkanal) und so wenig gesättigt muss ein Pixel sein, um als Hintergrund zu gelten
const BG_MIN_CHANNEL := 0.86
const BG_MAX_SATURATION := 0.10
## Freiraum um das Monster, Anteil der Bildgröße
const MARGIN := 0.03

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var force := args.has("--force")
	var only := Array(args).filter(func(a): return a != "--force")
	var dirs := DirAccess.get_directories_at(MONS_DIR)
	var done := 0
	for name in dirs:
		if not only.is_empty() and not only.has(name):
			continue
		var folder := "%s/%s" % [MONS_DIR, name]
		if FileAccess.file_exists("%s/%s_front.png" % [folder, name]) and not force:
			continue
		var source := _find_source(folder, name)
		if source == "":
			print("%s: kein Rohbild gefunden" % name)
			continue
		_prepare(folder, name, source)
		done += 1
	print("fertig, %d Monster aufbereitet" % done)
	quit()

## Erstes jpg/png im Ordner, das nicht selbst ein erzeugtes <nr>_front/back-Bild ist
func _find_source(folder: String, name: String) -> String:
	for file in DirAccess.get_files_at(folder):
		var ext := file.get_extension().to_lower()
		if (ext == "jpg" or ext == "jpeg" or ext == "png") and not file.begins_with(name + "_"):
			return "%s/%s" % [folder, file]
	return ""

func _prepare(folder: String, name: String, source: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(source))
	img.convert(Image.FORMAT_RGBA8)
	_remove_background(img)
	var used := img.get_used_rect()
	var side := int(maxi(used.size.x, used.size.y) * (1.0 + 2.0 * MARGIN))
	var square := Image.create(side, side, false, Image.FORMAT_RGBA8)
	square.blit_rect(img, used, Vector2i((side - used.size.x) / 2, (side - used.size.y) / 2))
	# Farbe transparenter Pixel an die Nachbarn angleichen, sonst bluten beim Verkleinern weiße Säume ein
	square.fix_alpha_edges()
	for size in FRONT_SIZES:
		_save_scaled(square, size, "%s/%s_front%s.png" % [folder, name, _suffix(size)])
	for size in BACK_SIZES:
		_save_scaled(square, size, "%s/%s_back%s.png" % [folder, name, _suffix(size)])
	print("%s: aus %s, %dx%d -> %d" % [name, source.get_file(), img.get_width(), img.get_height(), FRONT_SIZES.back()])

func _suffix(size: int) -> String:
	return "" if size == FRONT_SIZES.back() else "x%d" % size

func _save_scaled(square: Image, size: int, path: String) -> void:
	var scaled := square.duplicate() as Image
	scaled.resize(size, size, Image.INTERPOLATE_LANCZOS)
	scaled.save_png(ProjectSettings.globalize_path(path))

func _is_background(data: PackedByteArray, i: int) -> bool:
	var r := data[i * 4]
	var g := data[i * 4 + 1]
	var b := data[i * 4 + 2]
	var lo := mini(r, mini(g, b))
	var hi := maxi(r, maxi(g, b))
	return lo >= BG_MIN_CHANNEL * 255.0 and hi - lo <= BG_MAX_SATURATION * 255.0

func _remove_background(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var bg := PackedByteArray()
	bg.resize(w * h)
	var stack := PackedInt32Array()
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if bg[i] or not _is_background(data, i):
			continue
		bg[i] = 1
		var x := i % w
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if i >= w: stack.append(i - w)
		if i < (h - 1) * w: stack.append(i + w)
	for i in w * h:
		if bg[i]:
			data[i * 4 + 3] = 0
			continue
		# Randpixel neben dem Hintergrund: je heller, desto durchsichtiger (Kantenglättung gegen weiße Säume)
		var x := i % w
		var edge := (x > 0 and bg[i - 1]) or (x < w - 1 and bg[i + 1]) or (i >= w and bg[i - w]) or (i < (h - 1) * w and bg[i + w])
		if edge:
			var lo := mini(data[i * 4], mini(data[i * 4 + 1], data[i * 4 + 2])) / 255.0
			data[i * 4 + 3] = int(clampf((1.0 - lo) / (1.0 - BG_MIN_CHANNEL), 0.0, 1.0) * 255.0)
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)
