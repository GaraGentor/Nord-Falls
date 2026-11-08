shader_type canvas_item;

// Zug-Rune: pixeliger Eisen-Rhombus mit Goldrand und Schatten. Solange Züge übrig sind (charge = 1),
// glüht innen eine pulsierende Glut und ein Lichtglanz wandert über den Rand. Ohne Züge (charge = 0)
// ist sie kaltes Eisen mit dem Rand der Eisenplatten.

uniform vec2 rect_size = vec2(40.0);
uniform float pixel_size = 2.0;
uniform float rim_width = 2.0;
// Schatten nach rechts unten, in Pixeln
uniform vec2 shadow_offset = vec2(2.0, 2.0);
uniform vec4 iron_top : source_color = vec4(0.2, 0.235, 0.255, 1.0);
uniform vec4 iron_bottom : source_color = vec4(0.09, 0.105, 0.125, 1.0);
uniform vec4 gold_rim : source_color = vec4(0.858824, 0.717647, 0.45098, 1.0);
uniform vec4 cold_rim : source_color = vec4(0.31, 0.415, 0.424, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.5, 0.12, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.45);
uniform float charge = 1.0;
uniform float pulse_speed = 2.2;
// Sekunden zwischen zwei Lichtglänzen über den Rand
uniform float glint_period = 3.5;

float diamond(vec2 q, vec2 h) {
	return abs(q.x) / h.x + abs(q.y) / h.y;
}

void fragment() {
	vec2 cell = floor(UV * rect_size / pixel_size);
	vec2 p = (cell + 0.5) * pixel_size - rect_size * 0.5;
	// Rune nach links oben gerückt, damit der Schatten noch hineinpasst
	vec2 h = (rect_size - shadow_offset) * 0.5;
	vec2 q = p + shadow_offset * 0.5;
	float d = diamond(q, h);
	float d_shadow = diamond(q - shadow_offset, h);

	if (d > 1.0) {
		COLOR = d_shadow <= 1.0 ? shadow_color : vec4(0.0);
	} else {
		// Abstand zur Kante in Pixeln
		float edge = (1.0 - d) * h.x * h.y / length(h);
		vec3 rgb;
		if (edge < rim_width) {
			rgb = mix(cold_rim.rgb, gold_rim.rgb, charge);
			// Lichtglanz läuft diagonal über die Rune, nur auf dem Rand
			float t = fract(TIME / glint_period) * 3.0 - 1.5;
			float glint = 1.0 - smoothstep(0.0, 0.18, abs((q.x - q.y) / (h.x + h.y) - t));
			rgb = mix(rgb, vec3(1.0, 0.97, 0.85), glint * charge);
		} else {
			rgb = mix(iron_top.rgb, iron_bottom.rgb, UV.y);
			// obere linke Facette heller: wirkt wie geschliffen
			if (q.x + q.y < 0.0) {
				rgb *= 1.25;
			}
			float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);
			float core = pow(clamp(1.0 - d, 0.0, 1.0), 1.3);
			float glow = charge * core * mix(0.55, 1.0, pulse);
			rgb = mix(rgb, glow_color.rgb, clamp(glow * 1.4, 0.0, 1.0));
		}
		rgb = floor(rgb * 8.0 + 0.5) / 8.0;
		COLOR = vec4(rgb, 1.0);
	}
}
