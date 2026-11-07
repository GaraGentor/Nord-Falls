class_name ShopDialog
extends RewardDialog

## Grundlage für Shop und Trainer: jede Karte hat einen Preis in ME, dazu Geld und Fertig-Button
## als Fußzeile (Shop) oder Tasche und Button oben (Trainer). Ist das Geld zu knapp, wird der Preis rot und die Ware lässt sich nicht ziehen.
## Rabatt-Gutscheine liegen neben der Tasche und werden auf die Kasse bzw. den Trainer gezogen. Damit ist der Gutschein weg,
## bis zum nächsten Kauf stehen alle Preise golden und reduziert da. Wer ohne Kauf geht, hat Pech gehabt.

## Gutscheine neben der Tasche, der Stapel lässt sich auf den Verkäufer ziehen
class CouponStack extends VBoxContainer:
	const ART_SIZE := Vector2(64, 64)
	const FONT_SIZE := 18

	var dialog: ShopDialog
	var _art: Control
	var _count: Label

	func _init(owner_dialog: ShopDialog) -> void:
		dialog = owner_dialog
		alignment = BoxContainer.ALIGNMENT_END
		# das Bild hat viel Rand, die Zahl rückt ans Ticket heran
		add_theme_constant_override("separation", -12)
		tooltip_text = tr("COUPON_DESC")
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_art = RewardDialog.texture_icon(COUPON_ICON)
		_art.material = OpenBag.PROPS_MATERIAL
		_art.custom_minimum_size = ART_SIZE
		add_child(_art)
		_count = Label.new()
		_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_count.add_theme_font_override("font", OpenBag.PIXEL_FONT)
		_count.add_theme_font_size_override("font_size", FONT_SIZE)
		_count.add_theme_color_override("font_color", SkillDetailPopup.GOLD)
		_count.add_theme_color_override("font_outline_color", Color.BLACK)
		_count.add_theme_constant_override("outline_size", 4)
		add_child(_count)
		RewardDialog.ignore_mouse_below(self)

	func show_count(count: int) -> void:
		_count.text = "x%d" % count
		visible = count > 0

	func _get_drag_data(_at_position: Vector2):
		if dialog._coupon_active:
			dialog._show_blocked(tr("COUPON_ALREADY_ACTIVE"))
			return null
		var art: Control = _art.duplicate(0)
		art.size = ART_SIZE
		art.position = -ART_SIZE / 2
		var holder := Control.new()
		holder.add_child(art)
		set_drag_preview(holder)
		dialog._set_coupon_dragged(true)
		return self

## Fläche über dem Verkäufer, nimmt nur während des Ziehens eines Gutscheins die Maus an
class CouponTarget extends Control:
	var dialog: ShopDialog

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is CouponStack

	func _drop_data(_at_position: Vector2, _data: Variant) -> void:
		dialog._apply_coupon()

const TOO_EXPENSIVE_COLOR := Color(0.9, 0.3, 0.3)
const COUPON_DISCOUNT := 0.25
const COUPON_ICON = preload("res://assets/ui/icons/coupon.svg")
const ESSENCE_ICON = preload("res://assets/ui/icons/monster_essence.svg")
const EXIT_ICON = preload("res://assets/ui/jailer/icon_exit.svg")

var _money_label: Label
## steht hinter dem Betrag, entfällt neben dem Essenz-Icon
var _money_suffix := " ME"
## Karte -> Preis-Label, wird rot, wenn das Geld nicht reicht
var _price_labels := {}
## ein Gutschein wurde abgegeben, der nächste Kauf bei diesem Besuch ist reduziert
var _coupon_active := false
var _coupon_stack: CouponStack
var _coupon_target: CouponTarget
## Bild des Verkäufers, leuchtet beim Ziehen eines Gutscheins golden
var _coupon_seller: TextureRect

## Preis unter den Titel der Karte hängen. repeatable: bleibt nach dem Kauf im Angebot
func set_price(card: RewardCard, price: int, repeatable := false) -> void:
	card.drag.price = price
	card.drag.repeatable = repeatable
	var label := Label.new()
	label.theme = LABEL_THEME
	label.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.insert_detail(label)
	_price_labels[card] = label
	_show_price(card)

## Was die Karte gerade kostet, mit abgegebenem Gutschein reduziert
func price_of(card: RewardCard) -> int:
	var price: int = card.drag.price
	return ceili(price * (1.0 - COUPON_DISCOUNT)) if _coupon_active else price

func _show_price(card: RewardCard) -> void:
	var label: Label = _price_labels[card]
	label.text = Helper.me_text(price_of(card))
	label.add_theme_color_override("font_color", SkillDetailPopup.GOLD if _coupon_active else IronPlate.TEXT_COLOR)

## Gutschein-Stapel und Ablagefläche anlegen. Die Fläche kommt ganz nach oben, damit nichts den Drop abfängt,
## also erst aufrufen, wenn der Verkäufer und alles um ihn herum steht. Das Geld muss schon angezeigt werden (_watch_money).
func add_coupons(stack_parent: Control, seller: TextureRect) -> void:
	_coupon_seller = seller
	_coupon_stack = CouponStack.new(self)
	stack_parent.add_child(_coupon_stack)
	_coupon_target = CouponTarget.new()
	_coupon_target.dialog = self
	_coupon_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seller.get_parent().add_child(_coupon_target)
	State.coupons_changed.connect(_coupons_changed)
	_coupons_changed(State.coupons)

func _coupons_changed(_new_val) -> void:
	_coupon_stack.show_count(State.coupons)
	_money_changed(State.ep)

func _set_coupon_dragged(dragged: bool) -> void:
	_coupon_target.mouse_filter = Control.MOUSE_FILTER_STOP if dragged else Control.MOUSE_FILTER_IGNORE
	_coupon_seller.material.set_shader_parameter("outline_color", SkillDetailPopup.GOLD if dragged else OpenBag.NO_OUTLINE)
	_coupon_stack.modulate.a = 0.4 if dragged else 1.0

func _apply_coupon() -> void:
	_coupon_active = true
	State.coupons -= 1
	_coupon_applied()

## Reaktion des Verkäufers auf den abgegebenen Gutschein
func _coupon_applied() -> void:
	pass

func _hide_targets() -> void:
	super()
	if _coupon_target:
		_set_coupon_dragged(false)

## Geld links, Fertig-Button rechts; erst aufrufen, wenn alle Karten einen Preis haben
func add_money_footer(finish_key: String) -> void:
	var footer := HBoxContainer.new()
	_money_label = Label.new()
	_money_label.theme = LABEL_THEME
	_money_label.add_theme_color_override("font_color", IronPlate.TEXT_COLOR)
	_money_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_money_label)
	var finish := plate_button(tr(finish_key))
	finish.pressed.connect(close)
	footer.add_child(finish)
	add_footer(footer)
	_watch_money()

func _watch_money() -> void:
	State.ep_changed.connect(_money_changed)
	_money_changed(State.ep)

func _exit_tree() -> void:
	if State.ep_changed.is_connected(_money_changed):
		State.ep_changed.disconnect(_money_changed)
	if State.coupons_changed.is_connected(_coupons_changed):
		State.coupons_changed.disconnect(_coupons_changed)

## Bezahlen, Einzelstücke ausgrauen, der Dialog bleibt offen
func pay(card: RewardCard) -> void:
	if not card.drag.repeatable:
		mark_sold(card)
	var price := price_of(card)
	if price > 0:
		_coupon_active = false
	State.ep -= price
	set_drag_hint(tr("SHOP_BOUGHT").format({"item": card.drag.title}))

func _drag_blocked(card: RewardCard) -> String:
	if State.ep < price_of(card):
		return tr("SHOP_NOT_ENOUGH_MONEY")
	return ""

func _money_changed(_new_val) -> void:
	_money_label.text = str(State.ep) + _money_suffix
	for card: RewardCard in _price_labels:
		_show_price(card)
		var too_expensive: bool = not card.sold and State.ep < price_of(card)
		_price_labels[card].modulate = TOO_EXPENSIVE_COLOR if too_expensive else Color.WHITE
