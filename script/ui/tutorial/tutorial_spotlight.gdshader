shader_type canvas_item;

// Abdunkelung fürs Tutorial: alles dunkel bis auf die Ziele (holes, mit pulsierendem goldenem Rahmen)
// und den sprechenden NPC der Szene (npc_hole, ohne Rahmen).
// Rechtecke = x, y, Breite, Höhe in Pixeln der Fläche; Breite 0 = nicht benutzt.

const int MAX_HOLES = 6;

uniform vec4 holes[MAX_HOLES];
uniform int hole_count = 0;
uniform vec4 npc_hole = vec4(0.0);
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform vec4 dim_color : source_color = vec4(0.0, 0.0, 0.0, 0.65);
uniform vec4 border_color : source_color = vec4(0.858824, 0.717647, 0.45098, 1.0);
uniform float radius = 10.0;
uniform float softness = 4.0;
uniform float border = 3.0;

// Abstand zum abgerundeten Rechteck, negativ innen; ohne Rechteck sehr weit weg
float rect_distance(vec2 p, vec4 rect) {
	if (rect.z < 1.0) {
		return 1e6;
	}
	vec2 half_size = rect.zw * 0.5;
	vec2 q = abs(p - (rect.xy + half_size)) - half_size + radius;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	vec2 p = UV * rect_size;
	// Abstand zur Vereinigung aller Ziele: überlappende Ziele bekommen einen gemeinsamen Rahmen ohne Linien im Inneren
	float holes_d = 1e6;
	for (int i = 0; i < MAX_HOLES; i++) {
		if (i >= hole_count) {
			break;
		}
		holes_d = min(holes_d, rect_distance(p, holes[i]));
	}
	float ring = 1.0 - smoothstep(0.0, 1.5, abs(holes_d - border * 0.5) - border * 0.5);
	float d = min(rect_distance(p, npc_hole), holes_d);
	vec4 color = dim_color;
	color.a *= smoothstep(0.0, softness, d);
	float pulse = 0.65 + 0.35 * sin(TIME * 3.0);
	COLOR = mix(color, vec4(border_color.rgb, 1.0), ring * pulse);
}
