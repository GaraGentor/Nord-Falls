extends Node

signal finish_catching(catched, mon)

# signal map_event_pressed(node)
signal card_selected(card)
signal call_skill_card(skill)
signal select_mon(mon)
signal select_enemy_mon(mon)
signal select_mon_skill(skill)

signal select_widget_monster(mon)

signal refresh_ui_for_monster()

signal select_initial_mon(index)

signal mouse_event(props)

signal monster_faints(mon)

signal mon_is_catched(mon)

# battle
signal deal_damage_to_monster(mon)
# Treffer mit Schaden und Element-Faktor (für die schwebende Anzeige "Sehr effektiv!"), blocked = vom Schild abgefangen
signal monster_hit_with_element(mon, damage, multiplier, blocked)
# Schild, Buff oder Abklingzeit eines Monsters hat sich geändert
signal monster_status_changed(mon)
# geplante Züge der Gegner (Monster._intent) oder ihre Ziele haben sich geändert
signal intents_changed()

# monster widget
signal skill_label_pressed(skill)

# learn skill from judgement
signal learn_skill(skill)

# test anim
signal damage_animation_done(mon)

# hit anim
signal monster_hit_monster(from, to)

# upgrade status to make them upgraded on the run
signal mon_upgraded(mon_name)
