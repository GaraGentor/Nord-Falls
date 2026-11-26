class_name ElementLoan

## Element-Leihgabe (element_leihgabe_idee.txt): Das Monster am Zug zieht ein Element seines Partners auf sich.
## Seine Fähigkeiten bekommen dieses Element für den Element-EFFEKT dazu (ElementEffects, löst dann sicher aus).
## Schaden, Element-Faktor, Kosten und Abklingzeit bleiben, wie sie sind.
##
## Regeln:
##   > Nur das eigene Monster am Zug leiht, nur vom lebenden Partner im eigenen Team.
##   > Pro geliehenem Element verliert der Partner 1 Aktion in seinem nächsten Zug (Monster._loan_debt),
##     höchstens so viele, wie er Aktionen pro Zug hat.
##   > Die Leihgabe gilt für die nächste Fähigkeit, die sie verändert. Danach (oder am Zugende) geht das Element zurück,
##     die Aktion des Partners bleibt verbraucht. Vorher zurückgeben (Kugel anklicken) erstattet die Aktion.
##   > Eine Fähigkeit verändert sich nur, wenn das Ergebnis ein Kombi-Element mit Effekt ist: kein Element, das sie
##     schon hat, höchstens Monster.MAX_ELEMENTS Elemente (Chaos bleibt dem Endboss), schlummernde Skills nie.
##     Treffer-Effekte nur bei Schadens-Skills, Vulkan (doppelte Wirkung) bei jeder Fähigkeit.

## Eigenes Monster, das gerade am Zug ist und leihen darf (setzt battle.gd, sonst null)
static var active: Monster
## Vorschau beim Ziehen einer Kugel: dieses Element käme zu den Leihgaben von active dazu (0 = keine Vorschau)
static var preview_element := 0

## Elemente, die mon gerade geliehen hat, als Maske
static func loaned_mask(mon: Monster) -> int:
	var mask := 0
	if mon == null:
		return mask
	for loan in mon._loans:
		mask |= loan.element
	return mask

## Leihgaben plus Vorschau (für die Anzeige der Karten)
static func shown_mask(mon: Monster) -> int:
	var mask := loaned_mask(mon)
	if mon != null and mon == active:
		mask |= preview_element
	return mask

## Aktionen, die mon in einem Zug bekommt (wie Monster.reset_to_new_round, ohne Schulden)
## Gegner haben keine Kerkermeister-Verbesserungen (wie battle.gd _plan_intent)
static func moves_per_turn(mon: Monster) -> int:
	var base: int = mon._initial_moves if State.enemy_mons.has(mon) else mon._initial_moves + mon._upgrades
	return mon.cap_moves(Relics.modify("moves", base, mon) + roundi(mon.boon_value("extra_moves")))

## Kann lender noch eine Aktion verleihen?
static func can_lend_more(lender: Monster) -> bool:
	return lender != null and lender.is_alive() and lender._loan_debt < moves_per_turn(lender)

## Element, das sich die Kombi aus nature und extra ergibt, wenn der Skill dadurch einen Effekt bekommt, sonst 0.
## extra < 0: die aktuellen Leihgaben von mon.
static func loan_nature(mon: Monster, skill: Dictionary, extra := -1) -> int:
	if extra < 0:
		extra = loaned_mask(mon)
	if extra == 0 or skill.is_empty() or Skills.is_passive(skill) or skill.get("_dormant", false) or Skills.is_dormant(mon, skill):
		return 0
	var nature: int = skill.get("nature", 0)
	var combined := nature | extra
	if combined == nature or Map.count_elements(combined) > Monster.MAX_ELEMENTS:
		return 0
	return combined if gives_effect(skill, combined) else 0

## Hat dieses Kombi-Element bei dieser Art Fähigkeit einen Effekt?
static func gives_effect(skill: Dictionary, mask: int) -> bool:
	if not ElementEffects.EFFECT_KEYS.has(mask) or mask == ElementEffects.CHAOS:
		return false
	if mask == ElementEffects.VOLCANO:
		return true
	return Skills.is_damage_skill(skill)

## Verändert eine Leihgabe von element mindestens eine Fähigkeit von mon? (zusätzlich zu den bisherigen Leihgaben)
static func changes_any(mon: Monster, extra: int) -> bool:
	for skill in mon._skills:
		if loan_nature(mon, skill, extra) != 0:
			return true
	return false

## Darf borrower sich element von lender leihen?
static func can_borrow(borrower: Monster, lender: Monster, element: int) -> bool:
	if borrower == null or lender == null or borrower == lender or borrower != active:
		return false
	if not borrower.is_alive() or not State.mons.has(borrower) or not State.mons.has(lender):
		return false
	if not lender._type & element or loaned_mask(borrower) & element:
		return false
	return can_lend_more(lender) and changes_any(borrower, loaned_mask(borrower) | element)

static func borrow(borrower: Monster, lender: Monster, element: int) -> void:
	if not can_borrow(borrower, lender, element):
		return
	lend(borrower, lender, element)

## Leihgabe ohne die Prüfungen für den Spieler (Gegner-KI, battle.gd _take_loan prüft selbst)
static func lend(borrower: Monster, lender: Monster, element: int) -> void:
	borrower._loans.append({"element": element, "from": lender})
	lender._loan_debt += 1
	_changed(borrower, lender)
	Events.element_borrowed.emit()

## Kugel zurückgeben, bevor eine Fähigkeit sie verbraucht hat: der Partner bekommt seine Aktion zurück
static func cancel(borrower: Monster, element: int) -> void:
	for loan in borrower._loans:
		if loan.element == element:
			borrower._loans.erase(loan)
			var lender: Monster = loan.from
			lender._loan_debt = maxi(lender._loan_debt - 1, 0)
			_changed(borrower, lender)
			return

## Alle Elemente zurück an ihre Besitzer, die Aktionen bleiben verbraucht (nach der Fähigkeit oder am Zugende)
static func return_all(borrower: Monster) -> void:
	if borrower == null or borrower._loans.is_empty():
		return
	var lenders: Array = borrower._loans.map(func(loan): return loan.from)
	borrower._loans.clear()
	_changed(borrower, null)
	for lender in lenders:
		Events.monster_status_changed.emit(lender)

## Der Skill so, wie er mit den Leihgaben wirkt: Kopie mit "effect_nature" (ElementEffects) und "_loaned"
## (Effekt löst sicher aus). Ohne passende Leihgabe der Skill selbst.
static func apply(mon: Monster, skill: Dictionary) -> Dictionary:
	var mask := loan_nature(mon, skill)
	if mask == 0:
		return skill
	var copy := skill.duplicate()
	copy.effect_nature = mask
	copy._loaned = true
	return copy

## Für die Karten-Anzeige: Kopie, die wie das Kombi-Element aussieht (Farbe, Element, Effekt-Text), mit Vorschau.
## Leer, wenn sich die Karte nicht verändert.
static func display_skill(mon: Monster, skill: Dictionary) -> Dictionary:
	var mask := loan_nature(mon, skill, shown_mask(mon))
	if mask == 0:
		return {}
	var copy := skill.duplicate()
	copy.nature = mask
	copy.effect_nature = mask
	copy._loaned = true
	# nicht noch einmal als schlummernd behandeln (Skills.effective_skill)
	copy._effective = true
	return copy

## Wird mon bei der aktuellen Vorschau gar nicht verändert? (Karte ausgrauen, solange eine Kugel gezogen wird)
static func preview_dims(mon: Monster, skill: Dictionary) -> bool:
	return preview_element != 0 and mon == active and loan_nature(mon, skill, shown_mask(mon)) == 0

static func set_preview(element: int) -> void:
	if preview_element == element:
		return
	preview_element = element
	Events.element_loans_changed.emit()

static func _changed(borrower: Monster, lender: Monster) -> void:
	Events.monster_status_changed.emit(borrower)
	if lender != null:
		Events.monster_status_changed.emit(lender)
	Events.element_loans_changed.emit()
