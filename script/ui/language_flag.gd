class_name LanguageFlag
extends RefCounted

## Kleine Flaggen für die Sprachwahl in den Einstellungen, Pixel für Pixel erzeugt (keine Bilddateien nötig):
## "de" Deutschland, "en" Vereinigtes Königreich. Mit dunklem Rand, damit sie auf der Eisenplatte stehen.

const SIZE := Vector2i(40, 24)
const BORDER := Color(0.1, 0.09, 0.08)
const DE_BLACK := Color(0.08, 0.08, 0.08)
const DE_RED := Color(0.86, 0.0, 0.0)
const DE_GOLD := Color(1.0, 0.8, 0.0)
const UK_BLUE := Color(0.0, 0.14, 0.49)
const UK_RED := Color(0.78, 0.06, 0.18)
const UK_WHITE := Color(1, 1, 1)

static var _cache := {}

static func texture(locale: String) -> Texture2D:
	if not _cache.has(locale):
		_cache[locale] = ImageTexture.create_from_image(_image(locale))
	return _cache[locale]

static func _image(locale: String) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	# innen ohne Rand
	var w := SIZE.x - 2
	var h := SIZE.y - 2
	for y in SIZE.y:
		for x in SIZE.x:
			var inner := x > 0 and y > 0 and x < SIZE.x - 1 and y < SIZE.y - 1
			var color := BORDER
			if inner:
				color = _uk(x - 1, y - 1, w, h) if locale == "en" else _de(y - 1, h)
			image.set_pixel(x, y, color)
	return image

static func _de(y: int, h: int) -> Color:
	var third := float(y) / h * 3.0
	return DE_BLACK if third < 1.0 else DE_RED if third < 2.0 else DE_GOLD

## Union Jack vereinfacht: blau, weiße und rote Diagonalen, darüber das weiße Kreuz mit rotem Kreuz darin
static func _uk(x: int, y: int, w: int, h: int) -> Color:
	var px := x + 0.5
	var py := y + 0.5
	var length := sqrt(float(w * w + h * h))
	var diagonal := minf(absf(px * h - py * w), absf(px * h - (h - py) * w)) / length
	var cross := minf(absf(px - w / 2.0), absf(py - h / 2.0))
	if cross < h * 0.1:
		return UK_RED
	if cross < h / 6.0:
		return UK_WHITE
	if diagonal < h * 0.05:
		return UK_RED
	if diagonal < h * 0.12:
		return UK_WHITE
	return UK_BLUE
