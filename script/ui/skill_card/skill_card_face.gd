class_name SkillCardFace
extends RefCounted

## Gemeinsame Teile aller Skill-Karten (Kampfkarte battle_card, Ei-Karte EggSkillCard, Trainer, Gericht):
##  [Kosten, auf der Ecke] [Sterne auf der oberen Kante]
##  Name
##  Beschreibung …
##  [Wert + Art-Symbol]          [Abklingzeit Uhr]
## Das Element steht um 90° gedreht außen am linken Rand, von unten nach oben lesbar (TopRow).
## Unten steht alles in einer Zeile (BottomRow), damit die Beschreibung möglichst viel Platz bekommt.
## Der Wert ist Skills.power_text: Schaden bzw. Schild mit den Werten des Monsters, ohne Monster die Formel.
## Passive, Buffs und Debuffs zeigen dort nur ihr Symbol, alles Weitere steht in der Beschreibung.
## Läuft im Kampf die Abklingzeit, stehen dort die restlichen Züge mit Uhr (BottomRow.show_cooldown).
##
## Alle Karten nutzen dieselben Schriftgrößen (TITLE_SIZE, TEXT_SIZE, VALUE_SIZE, INFO_SIZE),
## Titel über style_title, Beschreibung über style_text. Die einzelnen Ansichten setzen keine eigenen Größen.

const MOVES_BADGE := preload("res://script/ui/moves_badge/moves_badge.tscn")
const STAR_TEXTURE := preload("res://assets/ui/icons/rarity_star.svg")
const CLOCK_TEXTURE := preload("res://assets/ui/icons/clock.svg")
const PIXEL_FONT := preload("res://script/ui/fonts/m5x7/m5x7.ttf")
const STAR_COLOR := Color(0.858824, 0.717647, 0.45098, 1)
const TEXT_COLOR := Color(1.0, 0.95, 0.85)
## Hinweis in der Beschreibung der Kampfkarte, wenn Elemente fehlen oder die Abklingzeit läuft (battle_card).
## Wert, Symbole und Abklingzeit selbst stehen in der Elementfarbe.
const COOLDOWN_COLOR := Color(1, 0.45, 0.45)
## Hinweis auf fehlende Elemente unten auf der Karte (BottomRow.show_missing)
const MISSING_COLOR := Color(1, 0.45, 0.45)
## so stark scheinen Wert und Abklingzeit unter dem Hinweis durch (0 = unsichtbar, 1 = voll)
const MISSING_ROW_ALPHA := 0.3
const STAR_SIZE := 22.0
const ICON_SIZE := 24.0
## Schriftgrößen aller Skill-Karten (m5x7, Vielfache von 8)
## Name der Karte, auf allen Karten gleich groß. Nur wenn ein einzelnes Wort nicht in die Kartenbreite passt
## (z. B. "Trophäenscheiterhaufen" auf schmalen Karten), wird er bis MIN_TITLE_FONT_SIZE kleiner (fit_title)
const TITLE_SIZE := 24
## Beschreibung und Hinweise auf der Karte
const TEXT_SIZE := 24
## Wert unten links (Schaden / Schild)
const VALUE_SIZE := 32
## Formel statt Wert ("25+0.5x", ohne Monster): kleiner, damit sie neben Symbol und Abklingzeit passt
const FORMULA_SIZE := 24
## Abklingzeit und Element unten rechts
const INFO_SIZE := 24
## Art-Symbol neben dem Wert, als Vielfaches der Wert-Schriftgröße. Steht es allein (Passiv, Buff, Debuff),
## ist es genauso groß wie neben einem Wert (Stärke, Magie, Schild).
const VALUE_ICON_SCALE := 1.3
## Gewicht der variablen Pixelschrift für den fetten Wert (Achse wght, 400 normal bis 700 fett)
const BOLD_WEIGHT := 700

## Kosten-Plakette (Raute) auf der linken oberen Kartenecke. So groß ist sie wirklich: die Szene
## (moves_badge.tscn) setzt ihre Mindestgröße durch, alles Weitere (Lage, Effekt, Sterne) rechnet damit.
const BADGE_SIZE := Vector2(42, 39)
## so weit sitzt die Mitte der Raute links oberhalb der Kartenecke: 0 = genau mittig auf der Ecke
## (untere Spitze auf der linken Kante, rechte Spitze auf der oberen), größer = Spitzen weiter weg von den Kanten,
## negativ = Mitte etwas auf der Karte
const BADGE_OUTSET := -2.0
## Abstand der Sterne (links auf der oberen Kante) zur rechten Spitze der Raute
const STARS_GAP := 8.0
## Rand-Effekt um die Raute (Flammen, Wellen, Funken je nach Art der Karte, SkillCardPaper.flame_settings):
## so weit ragt er links, oben, rechts und unten über die Raute hinaus
const BADGE_FLAME_PAD := Vector4(18, 20, 18, 14)
## so schnell wird der Effekt um die Raute stärker bzw. wieder normal (TopRow.set_intensity)
const INTENSITY_TIME := 0.18
## Gezogene Kampfkarte (TopRow.lift_flames): Die Kosten-Raute samt Effekt löst sich von der Karte und wandert zur Maus.
## Ebene über allem, Geschwindigkeit (größer = folgt enger), ab welchem Abstand sie wieder an der Karte hängt,
## etwas größer als auf der Karte und kurz über dem Finger, damit sie sichtbar bleibt
const LIFTED_LAYER := 100
const LIFT_FOLLOW_SPEED := 18.0
const LIFT_HOME_DISTANCE := 1.0
const LIFT_SCALE := 1.4
const LIFT_OFFSET := Vector2(0, -24)
## Die Ziffern der Pixelschrift sitzen in ihrer Zeile nicht mittig (bei 24 px etwa 0,75 px zu weit links und
## 1,2 px zu tief): so weit wird die Zahl in der Raute verschoben, damit sie optisch mittig steht
const BADGE_TEXT_SHIFT := Vector2(1, -1)
## Abstand der Grundlinie des gedrehten Elementnamens zur Papierkante links (negativ: ins Papier hinein, bis kurz
## vor den sichtbaren Rahmen, der etwas innen liegt)
const ELEMENT_GAP := -2.0
## so weit über der Papierkante unten beginnt der erste Buchstabe des Elementnamens: bündig mit dem sichtbaren
## Rahmen (liegt im Papier-Shader etwas innen), samt Kontur der Schrift
const PAPER_FRAME_INSET := 5.0

static var _bold_font: FontVariation

## Pixelschrift in fett, einmal erzeugt und von allen Karten geteilt
static func bold_font() -> FontVariation:
	if _bold_font == null:
		_bold_font = FontVariation.new()
		_bold_font.base_font = PIXEL_FONT
		_bold_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): BOLD_WEIGHT}
	return _bold_font

## Kosten-Plakette als Raute auf der linken oberen Kartenecke, die Sterne (Stufe) daneben links auf der oberen Kante,
## das Element um 90° gedreht außen am linken Rand: beginnt unten links und läuft nach oben Richtung Plakette.
## Die Zeile selbst ist 0 hoch: Plakette, Sterne und Element ragen über Ecke bzw. Kanten.
## Alle richten sich nach dem Kartenpapier (SkillCardPaper), nicht nach dem Innenabstand der jeweiligen Karte,
## und sitzen so auf allen Karten gleich. Sterne und Element sind auch bei unbekannten Skills sichtbar.
class TopRow extends Control:
	var cost_badge: Control
	var _stars: HBoxContainer
	var _star_count := 0
	var _element: Label
	var _paper: SkillCardPaper
	var _place_queued := false
	## Rand-Effekt hinter der Raute
	var _flames: ColorRect
	var _flames_material: ShaderMaterial
	## Stärke des Effekts um die Raute (set_intensity)
	var _intensity := 1.0
	var _intensity_tween: Tween
	## Raute und Effekt hängen gerade in einer Ebene über allem (lift_flames), solange nicht an der Karte
	var _lift_layer: CanvasLayer
	## wandern zur Maus (sonst zurück auf die Karte)
	var _following := false
	## Platz der Raute auf der Karte (_place), gilt auch, solange sie wandert
	var _badge_home := Vector2.ZERO
	## Maßstab der Karte auf dem Bildschirm beim Abheben (die Hand kann skaliert sein)
	var _home_scale := Vector2.ONE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flames_material = ShaderMaterial.new()
		_flames_material.shader = SkillCardPaper.FLAMES_SHADER
		_flames_material.set_shader_parameter("diamond", true)
		_flames_material.set_shader_parameter("pad", SkillCardFace.BADGE_FLAME_PAD)
		_flames_material.set_shader_parameter("overlap", 2.0)
		_flames = ColorRect.new()
		_flames.material = _flames_material
		_flames.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flames.size = SkillCardFace.BADGE_SIZE + Vector2(SkillCardFace.BADGE_FLAME_PAD.x + SkillCardFace.BADGE_FLAME_PAD.z,
			SkillCardFace.BADGE_FLAME_PAD.y + SkillCardFace.BADGE_FLAME_PAD.w)
		_flames_material.set_shader_parameter("rect_size", _flames.size)
		_flames.visible = false
		add_child(_flames)
		cost_badge = SkillCardFace.MOVES_BADGE.instantiate()
		cost_badge.custom_minimum_size = SkillCardFace.BADGE_SIZE
		cost_badge.size = SkillCardFace.BADGE_SIZE
		cost_badge.label.add_theme_font_size_override("font_size", SkillCardFace.INFO_SIZE)
		cost_badge.label.add_theme_constant_override("outline_size", 4)
		# Zahl optisch mittig in der Raute (statt der alten Verschiebung aus moves_badge.tscn)
		var number: Label = cost_badge.label
		number.offset_left = SkillCardFace.BADGE_TEXT_SHIFT.x
		number.offset_right = SkillCardFace.BADGE_TEXT_SHIFT.x
		number.offset_top = SkillCardFace.BADGE_TEXT_SHIFT.y
		number.offset_bottom = SkillCardFace.BADGE_TEXT_SHIFT.y
		SkillCardFace.ignore_mouse(cost_badge)
		add_child(cost_badge)
		_stars = HBoxContainer.new()
		_stars.add_theme_constant_override("separation", 0)
		_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_stars)
		# von unten nach oben lesbar: Textanfang unten, Oberkante zeigt von der Karte weg
		_element = SkillCardFace.label(SkillCardFace.INFO_SIZE, SkillCardFace.TEXT_COLOR)
		_element.rotation = -PI / 2
		_element.resized.connect(_queue_place)
		add_child(_element)
		item_rect_changed.connect(_queue_place)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_ENTER_TREE:
			# das Papier hängt manche Karte erst nach der Kopfzeile an (battle_card)
			_queue_place()
		elif what == NOTIFICATION_EXIT_TREE:
			# Karte verlässt den Baum (gespielt, Hand neu aufgebaut): Effekt sofort zurück
			_following = false
			_attach_flames.call_deferred()
		elif what == NOTIFICATION_PREDELETE:
			if _lift_layer != null and is_instance_valid(_lift_layer):
				_lift_layer.queue_free()

	func _queue_place() -> void:
		if _place_queued:
			return
		_place_queued = true
		_place.call_deferred()

	## Raute auf die Ecke, Sterne linksbündig (gleich rechts neben der Raute) auf die obere Kante des Kartenpapiers
	func _place() -> void:
		_place_queued = false
		if not is_inside_tree():
			return
		if _paper == null or not is_instance_valid(_paper):
			_paper = _find_paper()
			if _paper == null:
				return
			_paper.item_rect_changed.connect(_queue_place)
			_paper.flames_changed.connect(_sync_flames)
			_sync_flames()
		var to_local := get_global_transform().affine_inverse() * _paper.get_global_transform()
		var corner: Vector2 = to_local * Vector2.ZERO
		_badge_home = corner - SkillCardFace.BADGE_SIZE / 2 - Vector2.ONE * SkillCardFace.BADGE_OUTSET
		var pad := SkillCardFace.BADGE_FLAME_PAD * _intensity
		if _lift_layer == null:
			cost_badge.position = _badge_home
			_flames.position = _badge_home - Vector2(pad.x, pad.y)
		var badge_right := _badge_home.x + SkillCardFace.BADGE_SIZE.x
		_stars.position = Vector2(badge_right + SkillCardFace.STARS_GAP, corner.y - SkillCardFace.STAR_SIZE / 2)
		# gedreht liegt die Höhe des Labels waagerecht, die Grundlinie (Ascent) zeigt zur Karte:
		# sie endet ELEMENT_GAP vor der linken Kante; der erste Buchstabe beginnt unten am sichtbaren Rahmen
		var bottom_left: Vector2 = to_local * Vector2(0, _paper.size.y)
		_element.size = _element.get_combined_minimum_size()
		var font := _element.get_theme_font("font")
		var ascent := font.get_ascent(_element.get_theme_font_size("font_size")) if font != null else _element.size.y
		_element.position = Vector2(bottom_left.x - ascent - SkillCardFace.ELEMENT_GAP, bottom_left.y - SkillCardFace.PAPER_FRAME_INSET)

	## Effekt um die Raute stärker (1 = normal), z. B. solange eine Kampfkarte gedrückt ist.
	## Der Überstand wächst mit, damit der größere Effekt nicht abgeschnitten wird.
	func set_intensity(value: float, animate := true) -> void:
		if _intensity_tween:
			_intensity_tween.kill()
		if not animate or not is_inside_tree():
			_apply_intensity(value)
			return
		_intensity_tween = create_tween()
		_intensity_tween.set_ignore_time_scale(true)
		_intensity_tween.tween_method(_apply_intensity, _intensity, value, SkillCardFace.INTENSITY_TIME)

	func _apply_intensity(value: float) -> void:
		_intensity = value
		var pad := SkillCardFace.BADGE_FLAME_PAD * value
		_flames.size = SkillCardFace.BADGE_SIZE + Vector2(pad.x + pad.z, pad.y + pad.w)
		if _lift_layer == null:
			_flames.position = _badge_home - Vector2(pad.x, pad.y)
		_flames_material.set_shader_parameter("pad", pad)
		_flames_material.set_shader_parameter("rect_size", _flames.size)
		_flames_material.set_shader_parameter("intensity", value)

	## Gezogene Kampfkarte: Kosten-Raute samt Effekt lösen sich von der Karte und wandern zur Maus, etwas größer
	## (LIFT_SCALE) und kurz über dem Finger (LIFT_OFFSET). Es sind dieselben Nodes, keine Kopie: Sie hängen solange
	## in einer eigenen Ebene über allem. drop_flames schickt sie zurück, angekommen hängen sie wieder an der Karte.
	func lift_flames() -> void:
		_following = true
		if _lift_layer != null:
			return
		var on_screen := get_global_transform_with_canvas()
		_home_scale = on_screen.get_scale()
		# In der eigenen Ebene fehlt das Theme der Szene: die Schrift der Zahl vorher festhalten, sonst käme die
		# Standardschrift
		var number: Label = cost_badge.label
		number.add_theme_font_override("font", number.get_theme_font("font"))
		_lift_layer = CanvasLayer.new()
		_lift_layer.layer = SkillCardFace.LIFTED_LAYER
		get_tree().root.add_child(_lift_layer)
		for node: Control in [_flames, cost_badge]:
			var screen_pos: Vector2 = on_screen * node.position
			remove_child(node)
			_lift_layer.add_child(node)
			node.position = screen_pos
			node.scale = _home_scale
		set_process(true)

	func drop_flames() -> void:
		_following = false

	func _process(delta: float) -> void:
		if _lift_layer == null:
			set_process(false)
			return
		var weight := 1.0 - exp(-SkillCardFace.LIFT_FOLLOW_SPEED * delta)
		var goal_scale := _home_scale * (SkillCardFace.LIFT_SCALE if _following else 1.0)
		var scale_now := cost_badge.scale.lerp(goal_scale, weight)
		var target: Vector2
		if _following:
			# Mitte der Raute knapp über der Maus
			target = get_viewport().get_mouse_position() + SkillCardFace.LIFT_OFFSET - SkillCardFace.BADGE_SIZE / 2 * scale_now
		else:
			target = get_global_transform_with_canvas() * _badge_home
		var badge_pos := cost_badge.position.lerp(target, weight)
		var pad := SkillCardFace.BADGE_FLAME_PAD * _intensity
		cost_badge.scale = scale_now
		cost_badge.position = badge_pos
		_flames.scale = scale_now
		_flames.position = badge_pos - Vector2(pad.x, pad.y) * scale_now
		if not _following and badge_pos.distance_to(target) < SkillCardFace.LIFT_HOME_DISTANCE:
			_attach_flames()

	## Raute und Effekt wieder auf die Karte (Effekt ganz hinten, Raute gleich darüber)
	func _attach_flames() -> void:
		if _lift_layer == null:
			return
		for node: Control in [_flames, cost_badge]:
			_lift_layer.remove_child(node)
			add_child(node)
			node.scale = Vector2.ONE
		move_child(_flames, 0)
		move_child(cost_badge, 1)
		_lift_layer.queue_free()
		_lift_layer = null
		cost_badge.position = _badge_home
		var pad := SkillCardFace.BADGE_FLAME_PAD * _intensity
		_flames.position = _badge_home - Vector2(pad.x, pad.y)
		set_process(false)

	## Effekt um die Raute in Art und Farbe der Karte, wie ihn das Papier vorgibt
	func _sync_flames() -> void:
		if _paper == null or not is_instance_valid(_paper):
			return
		var settings: Dictionary = _paper.flame_settings()
		for key in ["mode", "variant", "flame_color", "seed"]:
			_flames_material.set_shader_parameter(key, settings[key])
		_flames.visible = settings.visible and cost_badge.modulate.a > 0.0

	## Das Papier liegt als Kind auf der Karte, irgendwo über der Kopfzeile
	func _find_paper() -> SkillCardPaper:
		var node := get_parent()
		while node != null:
			for child in node.get_children():
				if child is SkillCardPaper:
					return child
			node = node.get_parent()
		return null

	## Name der Karte linksbündig (Plakette und Sterne sitzen über der Kante), in der einheitlichen Titelgröße
	func set_title(title: Label) -> void:
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		SkillCardFace.style_title(title)

	## known = false: unbekannter Skill eines Gegners, die Kosten bleiben verborgen.
	## cost >= 0: tatsächliche Kosten für das Monster (Skills.skill_cost), sonst die Grundkosten der Karte
	func show_skill(skill: Dictionary, known := true, cost := -1) -> void:
		cost_badge.show_number(cost if cost >= 0 else skill.cost, false)
		cost_badge.modulate.a = 1.0 if known else 0.0
		for star in _stars.get_children():
			_stars.remove_child(star)
			star.queue_free()
		_star_count = skill.get("tier", 1)
		for i in _star_count:
			var star := SkillCardFace.icon(SkillCardFace.STAR_TEXTURE, SkillCardFace.STAR_SIZE)
			star.self_modulate = SkillCardFace.STAR_COLOR
			_stars.add_child(star)
		_element.text = tr(ColorMap.get_combo(skill.nature).label)
		_element.add_theme_color_override("font_color", SkillCardPaper.readable_color(Helper.color_by_type(skill.nature)))
		_sync_flames()
		_queue_place()

## Unterer Teil in einer Zeile: links groß Wert und Art-Symbol, rechts die Abklingzeit.
## Fehlen dem Monster Elemente (show_missing), liegt der Hinweis an derselben Stelle über Wert und Abklingzeit,
## die Beschreibung darüber behält ihren Platz.
## Das Element steht gedreht außen am linken Kartenrand (TopRow).
class BottomRow extends MarginContainer:
	var _row: HBoxContainer
	var _power: HBoxContainer
	var _value: Label
	var _kind: TextureRect
	var _cooldown: HBoxContainer
	var _cooldown_label: Label
	var _cooldown_icon: TextureRect
	var _missing: Label
	## Elementfarbe der Karte, auf dem dunklen Papier lesbar: Wert, Symbole und Abklingzeit
	var _nature_color := SkillCardFace.TEXT_COLOR
	## nur das Symbol, ohne Wert (Passiv, Buff, Debuff)
	var _icon_only := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row = HBoxContainer.new()
		_row.add_theme_constant_override("separation", 6)
		_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_row)
		_power = HBoxContainer.new()
		_power.add_theme_constant_override("separation", 4)
		_power.size_flags_vertical = Control.SIZE_SHRINK_END
		_power.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.add_child(_power)
		_value = SkillCardFace.label(SkillCardFace.VALUE_SIZE, SkillCardFace.TEXT_COLOR)
		_value.add_theme_font_override("font", SkillCardFace.bold_font())
		_power.add_child(_value)
		_kind = SkillCardFace.icon(null, SkillCardFace.ICON_SIZE)
		_power.add_child(_kind)

		# unten rechts, auf Höhe des Werts
		_cooldown = HBoxContainer.new()
		_cooldown.alignment = BoxContainer.ALIGNMENT_END
		_cooldown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cooldown.size_flags_vertical = Control.SIZE_SHRINK_END
		_cooldown.add_theme_constant_override("separation", 3)
		_cooldown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.add_child(_cooldown)
		_cooldown_label = SkillCardFace.label(SkillCardFace.INFO_SIZE, SkillCardFace.TEXT_COLOR)
		_cooldown.add_child(_cooldown_label)
		_cooldown_icon = SkillCardFace.icon(SkillCardFace.CLOCK_TEXTURE, SkillCardFace.ICON_SIZE)
		_cooldown.add_child(_cooldown_icon)

		# fehlende Elemente: liegt über Wert und Abklingzeit (MarginContainer stapelt seine Kinder)
		_missing = SkillCardFace.label(SkillCardFace.TEXT_SIZE, SkillCardFace.MISSING_COLOR)
		_missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_missing.size_flags_vertical = Control.SIZE_FILL
		_missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_missing.custom_minimum_size.x = 1
		_missing.visible = false
		add_child(_missing)

	## Hinweis statt Wert und Abklingzeit, z. B. "Benötigt: Erde, Feuer" (Skills.missing_elements_text).
	## Leerer Text zeigt wieder Wert und Abklingzeit. show_skill setzt ihn zurück.
	func show_missing(text: String) -> void:
		_missing.text = text
		_missing.visible = text != ""
		# Wert und Abklingzeit scheinen unter dem Hinweis durch
		_row.modulate.a = SkillCardFace.MISSING_ROW_ALPHA if text != "" else 1.0

	## mon: Besitzer für den Wert (null = Formel).
	## known = false: unbekannter Skill eines Gegners, Wert, Symbol und Abklingzeit bleiben verborgen.
	func show_skill(skill: Dictionary, mon: Monster = null, known := true) -> void:
		show_missing("")
		_nature_color = SkillCardPaper.readable_color(Helper.color_by_type(skill.nature))
		# Passive wirken dauerhaft, eine Abklingzeit gibt es dort nicht; ohne Abklingzeit bleibt die Uhr ebenfalls weg
		_cooldown.modulate.a = 0.0 if Skills.is_passive(skill) or not known or int(skill.get("cooldown", 0)) <= 0 else 1.0
		_cooldown_label.text = str(skill.get("cooldown", 0))
		_cooldown_label.add_theme_color_override("font_color", _nature_color)
		_cooldown_icon.modulate = _nature_color
		# unsichtbar statt ausgeblendet, damit unbekannte Karten gleich hoch bleiben
		_power.modulate.a = 1.0 if known else 0.0
		_icon_only = Skills.shows_only_icon(skill)
		_value.visible = not _icon_only
		_value.text = "" if _icon_only else Skills.power_text(skill, mon)
		_value.add_theme_font_size_override("font_size", SkillCardFace.FORMULA_SIZE if "+" in _value.text else SkillCardFace.VALUE_SIZE)
		_value.add_theme_color_override("font_color", _nature_color)
		_kind.texture = Skills.kind_icon(skill)
		_kind.modulate = _nature_color
		_apply_power_size()

	## Im Kampf bei laufender Abklingzeit: statt Wert und Art die restlichen Züge mit Uhr.
	## Zurück zum Wert mit show_skill.
	func show_cooldown(turns: int) -> void:
		_icon_only = false
		_value.visible = true
		_value.text = str(turns)
		_value.add_theme_font_size_override("font_size", SkillCardFace.VALUE_SIZE)
		_value.add_theme_color_override("font_color", _nature_color)
		_kind.texture = SkillCardFace.CLOCK_TEXTURE
		_kind.modulate = _nature_color
		_apply_power_size()

	func _apply_power_size() -> void:
		var scale := SkillCardFace.VALUE_ICON_SCALE
		var icon_size := roundf(SkillCardFace.VALUE_SIZE * scale)
		_kind.custom_minimum_size = Vector2(icon_size, icon_size)

## Kleinste Schrift für den Skill-Namen, falls er selbst so nicht in TITLE_MAX_LINES Zeilen passt
const MIN_TITLE_FONT_SIZE := 16
const TITLE_MAX_LINES := 2

## Name einer Skill-Karte: einheitliche Größe, lange Namen werden kleiner (fit_title)
static func style_title(title: Label) -> void:
	title.add_theme_font_size_override("font_size", TITLE_SIZE)
	fit_title(title, TITLE_SIZE)

## Beschreibung oder Hinweis auf einer Skill-Karte (Label oder RichTextLabel) in der einheitlichen Textgröße
static func style_text(text: Control) -> void:
	if text is RichTextLabel:
		for key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
			text.add_theme_font_size_override(key, TEXT_SIZE)
	else:
		text.add_theme_font_size_override("font_size", TEXT_SIZE)

## Skill-Name höchstens TITLE_MAX_LINES Zeilen: passt er bei base_size nicht, wird die Schrift kleiner.
## Rechnet bei jeder Größenänderung neu, die Breite steht erst nach dem Layout fest.
static func fit_title(title: Label, base_size: int) -> void:
	title.set_meta("title_base_size", base_size)
	title.max_lines_visible = TITLE_MAX_LINES
	if not title.has_meta("title_fitting"):
		title.set_meta("title_fitting", true)
		title.resized.connect(func(): _refit_title(title))
	_refit_title(title)

static func _refit_title(title: Label) -> void:
	var base: int = title.get_meta("title_base_size")
	var font := title.get_theme_font("font")
	# Platz für den Text: ohne den Einzug neben der Kosten-Plakette (TopRow.set_title)
	var width := title.size.x
	var style := title.get_theme_stylebox("normal")
	if style != null:
		width -= style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT)
	var font_size := base
	if font != null and width > 1.0:
		# kleiner, solange der Name zu viele Zeilen braucht oder ein Wort mitten drin umbrechen müsste
		while font_size > MIN_TITLE_FONT_SIZE and (_line_count(title.text, font, font_size, width) > TITLE_MAX_LINES \
				or _widest_word(title.text, font, font_size) > width):
			font_size -= 8
	if title.get_theme_font_size("font_size") != font_size:
		title.add_theme_font_size_override("font_size", font_size)

static func _widest_word(text: String, font: Font, font_size: int) -> float:
	var widest := 0.0
	for word in text.split(" ", false):
		widest = maxf(widest, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return widest

static func _line_count(text: String, font: Font, font_size: int, width: float) -> int:
	var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var text_size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1, flags)
	return roundi(text_size.y / font.get_height(font_size))

static func label(font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_constant_override("outline_size", 4)
	result.add_theme_color_override("font_outline_color", Color.BLACK)
	return result

static func icon(texture: Texture2D, icon_size: float) -> TextureRect:
	var result := TextureRect.new()
	result.texture = texture
	result.custom_minimum_size = Vector2(icon_size, icon_size)
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		ignore_mouse(child)
