class_name MapBiomeTheme
extends RefCounted

## Aussehen der Karte pro Biom (Element-Maske aus ColorMap): Papier, Linien, Deko und Wetter.
##
## paper_light/paper_dark: Papierfarbe, ink: Rahmen, Höhenlinien und gesperrte Wege
## accent: Wege, die man gerade nehmen kann
## crack: [Farbe, Stärke, Pulsieren], contour: Stärke der Höhenlinien
## deco: [Icon, Färbung], Icons aus assets/ui/map/deco, siehe MapDecoLayer
## wind: Periode in Sekunden (Richtungswechsel) und bias (0 = pendelt hin und her, 1 = weht nur in eine Richtung)
## particles: Namen aus MapWeather.PARTICLES
## clouds, fog, lightning, flyers: optional, siehe MapWeather

const EARTH := Enums.MON_TYPES.EARTH
const FIRE := Enums.MON_TYPES.FIRE
const WATER := Enums.MON_TYPES.WATER
const AIR := Enums.MON_TYPES.AIR

const FALLBACK := {
	"paper_light": "#c9b28a", "paper_dark": "#9c835b", "ink": "#3a2a14", "accent": "#d1361f", "contour": 0.5,
	"deco": [["rock", "#a08a64"], ["bush", "#8c8a56"], ["tree", "#7f8250"]],
	"wind": {"period": 30.0, "bias": 0.5},
	"particles": ["dust"],
}

const LOOKS := {
	# ── Einzelelemente ─────────────────────
	AIR: {
		"paper_light": "#e4eef4", "paper_dark": "#a9c4d4", "ink": "#2f4a5e", "accent": "#e8590c", "contour": 0.45,
		"deco": [["cloud_small", "#ffffff"], ["swirl", "#8fb6cc"], ["feather", "#f4f8fa"], ["mountain", "#b6cbd8"], ["bird", "#6f93a8"]],
		"wind": {"period": 26.0, "bias": 0.25},
		"particles": ["wind", "feather_fall"],
		"clouds": {"count": 8, "color": "#ffffff", "alpha": 0.62, "speed": 26.0, "size": [190.0, 420.0]},
		"flyers": {"icon": "bird", "color": "#3e5a6c", "count": 4, "speed": 70.0, "size": 34.0},
	},
	WATER: {
		"paper_light": "#2f7ba3", "paper_dark": "#17486d", "ink": "#bfe6f5", "accent": "#ffe066", "contour": 0.75,
		"deco": [["wave", "#7fd0ea"], ["fish", "#ffb36b"], ["lily", "#6fd39a"], ["wave", "#a8e4f4"], ["iceberg", "#d8f2fb"]],
		"wind": {"period": 18.0, "bias": 0.0},
		"particles": ["bubble", "drizzle"],
		"clouds": {"count": 3, "color": "#d9eef7", "alpha": 0.3, "speed": 14.0, "size": [240.0, 460.0]},
		"fog": {"color": "#9fdcf0", "amount": 0.14, "scale": 260.0, "speed": 0.03},
	},
	FIRE: {
		"paper_light": "#7a2f18", "paper_dark": "#3a130d", "ink": "#f0b27a", "accent": "#ffd23f", "contour": 0.3,
		"crack": ["#ff7a1a", 0.75, 1.0],
		"deco": [["flame", "#ff8a2a"], ["flame", "#ffc23d"], ["dead_tree", "#5c2a1a"], ["bone", "#e6c9a0"], ["rock", "#6b2c1c"]],
		"wind": {"period": 20.0, "bias": 0.1},
		"particles": ["ember", "ember_big", "smoke_fine"],
		"clouds": {"count": 4, "color": "#1d0d0a", "alpha": 0.4, "speed": 16.0, "size": [240.0, 480.0]},
		"fog": {"color": "#ff6a1f", "amount": 0.12, "scale": 300.0, "speed": 0.05},
	},
	EARTH: {
		"paper_light": "#9a7849", "paper_dark": "#5d4426", "ink": "#2b1c0d", "accent": "#ffe27a", "contour": 0.75,
		"crack": ["#2b1c0d", 0.35, 0.0],
		"deco": [["pine", "#4f6b3a"], ["tree", "#5e7d3e"], ["mountain", "#7c6444"], ["rock", "#857356"], ["mushroom", "#c6764a"], ["bush", "#5a7a3f"]],
		"wind": {"period": 28.0, "bias": 0.3},
		"particles": ["leaf", "dust"],
		"clouds": {"count": 3, "color": "#fff1d4", "alpha": 0.28, "speed": 10.0, "size": [220.0, 420.0]},
		"flyers": {"icon": "bird", "color": "#2b1c0d", "count": 2, "speed": 55.0, "size": 28.0},
	},
	# ── Zwei Elemente ──────────────────────
	AIR | WATER: {
		"paper_light": "#c9e2f0", "paper_dark": "#94c0da", "ink": "#2c4e6b", "accent": "#1458c8", "contour": 0.4,
		"crack": ["#7fb6d6", 0.6, 0.0],
		"deco": [["snowflake", "#ffffff"], ["ice_spike", "#bfe6f7"], ["iceberg", "#d8f1fb"], ["crystal", "#9fd8f2"], ["pine", "#7ea6ba"]],
		"wind": {"period": 16.0, "bias": 0.1},
		"particles": ["snow", "snow_big", "glint"],
		"clouds": {"count": 4, "color": "#ffffff", "alpha": 0.55, "speed": 20.0, "size": [220.0, 460.0]},
		"fog": {"color": "#ffffff", "amount": 0.16, "scale": 280.0, "speed": 0.05},
	},
	WATER | FIRE: {
		"paper_light": "#bccacb", "paper_dark": "#8a9ca0", "ink": "#2f3d40", "accent": "#e8541a", "contour": 0.5,
		"deco": [["geyser", "#e8f0f0"], ["geyser", "#c6d6d8"], ["rock", "#7d8b8e"], ["wave", "#93b4bb"], ["flame", "#e88a4a"]],
		"wind": {"period": 15.0, "bias": 0.0},
		"particles": ["steam", "steam_fine"],
		"clouds": {"count": 6, "color": "#f2f6f6", "alpha": 0.45, "speed": 12.0, "size": [260.0, 520.0]},
		"fog": {"color": "#ffffff", "amount": 0.34, "scale": 240.0, "speed": 0.07},
	},
	FIRE | AIR: {
		"paper_light": "#3e3e66", "paper_dark": "#1e1e38", "ink": "#c7c9ee", "accent": "#ffe23f", "contour": 0.4,
		"crack": ["#ffe23f", 0.4, 1.0],
		"deco": [["bolt", "#ffe23f"], ["bolt", "#fff4a8"], ["dead_tree", "#55557f"], ["rock", "#4a4a72"], ["crystal", "#b9bcff"]],
		"wind": {"period": 12.0, "bias": 0.0},
		"particles": ["spark", "wind"],
		"clouds": {"count": 6, "color": "#14142a", "alpha": 0.55, "speed": 34.0, "size": [260.0, 520.0]},
		"lightning": {"color": "#fff4a8", "min": 2.5, "max": 7.0},
	},
	EARTH | FIRE: {
		"paper_light": "#541d15", "paper_dark": "#1f0c0a", "ink": "#e08a4a", "accent": "#ffe14d", "contour": 0.2,
		"crack": ["#ff8a1f", 1.0, 1.0],
		"deco": [["volcano", "#5a241a"], ["rock", "#3e1a14"], ["flame", "#ff7a1a"], ["crystal", "#ff9d2e"], ["bone", "#c9a27c"]],
		"wind": {"period": 22.0, "bias": 0.0},
		"particles": ["ember", "ember_big", "ash"],
		"clouds": {"count": 3, "color": "#120706", "alpha": 0.45, "speed": 12.0, "size": [260.0, 500.0]},
		"fog": {"color": "#ff5a14", "amount": 0.16, "scale": 240.0, "speed": 0.04},
	},
	EARTH | WATER: {
		"paper_light": "#75604a", "paper_dark": "#42342a", "ink": "#d6c4a8", "accent": "#b7f26a", "contour": 0.6,
		"deco": [["reed", "#8a8f55"], ["mushroom", "#b0875a"], ["lily", "#6f8c4f"], ["rock", "#5a4a3a"], ["dead_tree", "#3f3226"]],
		"wind": {"period": 20.0, "bias": 0.2},
		"particles": ["rain", "bubble"],
		"clouds": {"count": 5, "color": "#2e2720", "alpha": 0.42, "speed": 15.0, "size": [240.0, 480.0]},
		"fog": {"color": "#8f7c62", "amount": 0.14, "scale": 260.0, "speed": 0.03},
	},
	EARTH | AIR: {
		"paper_light": "#e0cea0", "paper_dark": "#ad9566", "ink": "#4a3a1e", "accent": "#d1361f", "contour": 0.7,
		"deco": [["dune", "#d8bd82"], ["cactus", "#7f9455"], ["bone", "#f4ead2"], ["rock", "#a88d5e"], ["ruin", "#c2a572"], ["swirl", "#c2a572"]],
		"wind": {"period": 11.0, "bias": 0.0},
		"particles": ["sand", "sand_fine"],
		"clouds": {"count": 3, "color": "#d9c289", "alpha": 0.4, "speed": 44.0, "size": [320.0, 600.0]},
		"fog": {"color": "#d9bd80", "amount": 0.3, "scale": 200.0, "speed": 0.2},
	},
	# ── Drei Elemente ──────────────────────
	AIR | WATER | FIRE: {
		"paper_light": "#4f6690", "paper_dark": "#25324f", "ink": "#cfe0ff", "accent": "#ffe23f", "contour": 0.5,
		"deco": [["wave", "#8fb4e6"], ["bolt", "#ffe23f"], ["dead_tree", "#32435f"], ["swirl", "#9fbdea"], ["rock", "#3f5275"]],
		"wind": {"period": 10.0, "bias": 0.0},
		"particles": ["rain_heavy", "rain"],
		"clouds": {"count": 8, "color": "#161f33", "alpha": 0.58, "speed": 42.0, "size": [280.0, 600.0]},
		"lightning": {"color": "#dfe9ff", "min": 2.0, "max": 6.0},
	},
	EARTH | WATER | FIRE: {
		"paper_light": "#633226", "paper_dark": "#27110c", "ink": "#dca27a", "accent": "#ffb13a", "contour": 0.3,
		"crack": ["#ff6a1a", 0.85, 1.0],
		"deco": [["volcano", "#6d3324"], ["volcano", "#512418"], ["geyser", "#cfa892"], ["flame", "#ff7a1a"], ["rock", "#44201a"]],
		"wind": {"period": 18.0, "bias": 0.15},
		"particles": ["ash", "ash_fine", "ember", "ember_big"],
		"clouds": {"count": 7, "color": "#0e0605", "alpha": 0.52, "speed": 20.0, "size": [280.0, 560.0]},
		"fog": {"color": "#3a1a12", "amount": 0.2, "scale": 280.0, "speed": 0.05},
	},
	EARTH | AIR | FIRE: {
		"paper_light": "#766a60", "paper_dark": "#39322d", "ink": "#d7cfc6", "accent": "#ff7a2e", "contour": 0.3,
		"crack": ["#ff7a2e", 0.3, 1.0],
		"deco": [["dead_tree", "#322c28"], ["ruin", "#5a5047"], ["bone", "#cfc6ba"], ["rock", "#4d4540"], ["flame", "#ff7a2e"]],
		"wind": {"period": 9.0, "bias": 0.0},
		"particles": ["ash_storm", "ash_storm_big", "ember"],
		"clouds": {"count": 7, "color": "#1b1714", "alpha": 0.4, "speed": 62.0, "size": [300.0, 640.0]},
		"fog": {"color": "#26211d", "amount": 0.2, "scale": 210.0, "speed": 0.24},
	},
	EARTH | AIR | WATER: {
		"paper_light": "#567a58", "paper_dark": "#2b3f2e", "ink": "#d1e3bb", "accent": "#e3f25a", "contour": 0.55,
		"deco": [["reed", "#8ca85c"], ["lily", "#79b86a"], ["mushroom", "#c9a35a"], ["dead_tree", "#26352a"], ["tentacle", "#3f6650"]],
		"wind": {"period": 24.0, "bias": 0.0},
		"particles": ["firefly", "bubble", "spore"],
		"clouds": {"count": 3, "color": "#c9dcc0", "alpha": 0.22, "speed": 9.0, "size": [260.0, 500.0]},
		"fog": {"color": "#bcd8ac", "amount": 0.24, "scale": 260.0, "speed": 0.03},
	},
	# ── Alle vier ──────────────────────────
	AIR | WATER | FIRE | EARTH: {
		"paper_light": "#46257f", "paper_dark": "#180b33", "ink": "#d1b8ff", "accent": "#5cf2d6", "contour": 0.45,
		"crack": ["#ff4fd8", 0.9, 1.0],
		"deco": [["eye", "#c9a2ff"], ["tentacle", "#7b3fe4"], ["crystal", "#5cf2d6"], ["star", "#ffb3f0"], ["flame", "#ff4fd8"], ["snowflake", "#9fe4ff"]],
		"wind": {"period": 7.0, "bias": 0.0},
		"particles": ["rift", "rift_rise", "ember", "snow"],
		"clouds": {"count": 6, "color": "#0c0420", "alpha": 0.5, "speed": 48.0, "size": [260.0, 560.0]},
		"fog": {"color": "#b04fff", "amount": 0.18, "scale": 220.0, "speed": 0.12},
		"lightning": {"color": "#5cf2d6", "min": 3.0, "max": 8.0},
	},
}

## Reihenfolge für die Vorschau mit Taste B
const PREVIEW_ORDER: Array[int] = [
	EARTH, WATER, FIRE, AIR,
	AIR | WATER, WATER | FIRE, FIRE | AIR, EARTH | FIRE, EARTH | WATER, EARTH | AIR,
	AIR | WATER | FIRE, EARTH | WATER | FIRE, EARTH | AIR | FIRE, EARTH | AIR | WATER,
	AIR | WATER | FIRE | EARTH,
]

static func get_look(mask: int) -> Dictionary:
	return LOOKS.get(mask, FALLBACK)
