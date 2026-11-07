extends Node

func get_combo(mask: int) -> Dictionary:
	match mask:
		# ─────────────────────────
		# Single elements
		Enums.MON_TYPES.AIR:
			return { "color": "#CFEFFF", "label": "ELEMENT_AIR" }
		Enums.MON_TYPES.WATER:
			return { "color": "#1E90FF", "label": "ELEMENT_WATER" }
		Enums.MON_TYPES.FIRE:
			return { "color": "#E25822", "label": "ELEMENT_FIRE" }
		Enums.MON_TYPES.EARTH:
			return { "color": "#6B4F2A", "label": "ELEMENT_EARTH" }

		# ─────────────────────────
		# 2-element combinations
		Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER:
			return { "color": "#9AD9FF", "label": "ELEMENT_ICE" }
		Enums.MON_TYPES.WATER | Enums.MON_TYPES.FIRE:
			return { "color": "#B0C4C8", "label": "ELEMENT_STEAM" }
		Enums.MON_TYPES.FIRE | Enums.MON_TYPES.AIR:
			return { "color": "#FFD700", "label": "ELEMENT_LIGHTNING" }
		Enums.MON_TYPES.EARTH | Enums.MON_TYPES.FIRE:
			return { "color": "#8B2E1A", "label": "ELEMENT_MAGMA" }
		Enums.MON_TYPES.EARTH | Enums.MON_TYPES.WATER:
			return { "color": "#5A4A3F", "label": "ELEMENT_MUD" }
		Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR:
			return { "color": "#C2B280", "label": "ELEMENT_DUST" }

		# ─────────────────────────
		# 3-element combinations
		Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER | Enums.MON_TYPES.FIRE:
			return { "color": "#A9C9FF", "label": "ELEMENT_THUNDERSTORM" }
		Enums.MON_TYPES.EARTH | Enums.MON_TYPES.WATER | Enums.MON_TYPES.FIRE:
			return { "color": "#7A3E2B", "label": "ELEMENT_VOLCANO" }
		Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR | Enums.MON_TYPES.FIRE:
			return { "color": "#6E6259", "label": "ELEMENT_ASH_STORM" }
		Enums.MON_TYPES.EARTH | Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER:
			return { "color": "#4F6F52", "label": "ELEMENT_SWAMP" }

		# ─────────────────────────
		# All four elements
		Enums.MON_TYPES.AIR | Enums.MON_TYPES.WATER | Enums.MON_TYPES.FIRE | Enums.MON_TYPES.EARTH:
			return { "color": "#7B3FE4", "label": "ELEMENT_CHAOS" }

		# ─────────────────────────
		# Empty / fallback
		0:
			return { "color": "#000000", "label": "ELEMENT_EMPTY" }
		_:
			return { "color": "#555555", "label": "ELEMENT_UNKNOWN" }

func has_element(type, has):
	return type & has

func remove_element(type, element):
	type &= ~element

func add_element(type, element):
	return type | element
