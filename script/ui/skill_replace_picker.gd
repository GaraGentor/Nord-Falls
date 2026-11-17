class_name SkillReplacePicker
extends JudgementDialog

## Auswahl, welcher Skill vergessen wird, wenn ein Monster keinen freien Slot mehr hat.
## Zeigt die Skills als Karten wie beim Lehren im Judgement (JudgementDialog.pick_replace) und liegt
## auf einer eigenen CanvasLayer über allem, egal wo sie geöffnet wird (Skill-Belohnung, Trainer, neues Element).
## picked liefert den Index des zu ersetzenden Skills oder -1 bei Abbruch, danach entfernt sich die Auswahl selbst.
signal picked(index: int)

const LAYER := 110
const FONT_THEME = preload("res://script/ui/materials/pixel_font_theme.tres")

var _mon: Monster
var _skill: Dictionary

## Öffnet die Auswahl für mon, der skill lernen soll. parent ist nur der Platz im Baum.
static func open(parent: Node, mon: Monster, skill: Dictionary) -> SkillReplacePicker:
	var layer := CanvasLayer.new()
	layer.layer = LAYER
	# aus einer anderen Ebene heraus (z. B. ElementGainOverlay) eine Ebene darüber
	var node: Node = parent
	while node:
		if node is CanvasLayer:
			layer.layer = maxi(LAYER, node.layer + 1)
			break
		node = node.get_parent()
	var picker := SkillReplacePicker.new()
	picker._mon = mon
	picker._skill = skill
	picker.theme = FONT_THEME
	layer.add_child(picker)
	picker.picked.connect(func(_index): layer.queue_free())
	parent.add_child(layer)
	return picker

func _ready() -> void:
	super()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_run.call_deferred()

func _run() -> void:
	var index: int = await pick_replace(_mon, _skill)
	picked.emit(index)
