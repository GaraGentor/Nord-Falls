shader_type canvas_item;

// Der Void: schwarzes Loch mit leuchtendem Rand, darum eine Scheibe aus Spiralarmen, die nach innen laufen.
// Grobe Pixel und wenige Farbstufen passen zum Retro-Look des Spiels.

// Pixel pro Seite
uniform float cells = 120.0;
// läuft von außen hoch (void_event.gd), damit das Tempo sich ohne Sprung ändern kann
uniform float phase = 0.0;
// 0 = ruhig, 1 = saugt gerade: heller Rand und kräftigere Arme
uniform float pull = 0.0;
uniform vec3 deep_color = vec3(0.07, 0.02, 0.16);
uniform vec3 arm_color = vec3(0.42, 0.13, 0.72);
uniform vec3 rim_color = vec3(0.95, 0.45, 1.0);

const float HOLE_RADIUS = 0.27;
const float COLOR_LEVELS = 7.0;

void fragment() {
	vec2 p = (floor(UV * cells) + 0.5) / cells * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y, p.x);

	// nur ganzzahlige Vielfache vom Winkel, sonst entsteht eine Naht
	float wide = 0.5 + 0.5 * sin(3.0 * angle + 7.0 * log(max(r, 0.01)) + phase * 2.0);
	float fine = 0.5 + 0.5 * sin(7.0 * angle + 13.0 * log(max(r, 0.01)) + phase * 3.1);
	float arms = wide * 0.7 + fine * 0.3;

	float disc = 1.0 - smoothstep(HOLE_RADIUS, 1.0, r);
	vec3 color = mix(deep_color, arm_color, arms * disc * (1.1 + 0.5 * pull));
	color += rim_color * pow(arms, 4.0) * disc * 0.45;

	float rim_distance = (r - HOLE_RADIUS) / 0.05;
	color += rim_color * exp(-rim_distance * rim_distance) * (0.75 + 0.5 * pull);
	color *= smoothstep(HOLE_RADIUS - 0.03, HOLE_RADIUS + 0.01, r);
	color = floor(color * COLOR_LEVELS + 0.5) / COLOR_LEVELS;

	// außen löst sich die Scheibe entlang der Arme auf
	float edge = 1.0 - smoothstep(0.55, 1.0, r);
	float alpha = clamp(edge * (0.55 + arms), 0.0, 1.0);
	if (r < 0.7) {
		alpha = max(alpha, 1.0 - smoothstep(0.45, 0.7, r));
	}
	COLOR = vec4(color, step(0.12, alpha) * alpha);
}
