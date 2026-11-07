shader_type canvas_item;

// Initiativkreis: Pentagramm in einem Ring aus zwei verflochtenen Linien, dahinter eine düstere Aura.
// Alles liegt auf einem groben Pixelraster und wird wie die "Lebenden Pixel" gedithert.
// Die Drehung kommt von wheel.gd und dreht sich mit dem Rad mit.

uniform vec2 rect_size = vec2(400.0);
uniform float radius = 80.0;
uniform float wheel_rotation = 0.0;
uniform float pixel_size : hint_range(1.0, 8.0, 0.5) = 3.0;
uniform float line_width = 3.5;
// Amplitude und Anzahl der Wellen der verflochtenen Linien
uniform float braid_amplitude = 5.0;
uniform float braid_waves = 12.0;
uniform vec4 line_color : source_color = vec4(0.42, 0.07, 0.09, 1.0);
uniform vec4 pulse_color : source_color = vec4(0.86, 0.2, 0.13, 1.0);
uniform vec4 star_color : source_color = vec4(0.5, 0.08, 0.1, 1.0);
uniform vec4 aura_color : source_color = vec4(0.28, 0.02, 0.07, 1.0);
uniform float pulse_speed = 1.1;
uniform float color_levels = 6.0;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

float pentagram_distance(vec2 p, float r) {
	float d = 1e6;
	for (int i = 0; i < 5; i++) {
		float a0 = -PI / 2.0 + TAU * float(i) / 5.0;
		float a1 = -PI / 2.0 + TAU * float(i + 2) / 5.0;
		d = min(d, segment_distance(p, vec2(cos(a0), sin(a0)) * r, vec2(cos(a1), sin(a1)) * r));
	}
	return d;
}

void fragment() {
	// erst aufs Pixelraster, dann um die Mitte drehen
	vec2 cell = floor(UV * rect_size / pixel_size);
	vec2 p = (cell + 0.5) * pixel_size - rect_size * 0.5;
	float c = cos(wheel_rotation);
	float s = sin(wheel_rotation);
	vec2 q = vec2(c * p.x + s * p.y, -s * p.x + c * p.y);
	float r = length(q);
	float theta = atan(q.y, q.x);

	float wave = sin(braid_waves * theta) * braid_amplitude;
	float braid = min(abs(r - radius - wave), abs(r - radius + wave));
	float star_radius = radius - braid_amplitude - line_width;
	float star = min(pentagram_distance(q, star_radius), abs(r - star_radius));

	// Glimmen läuft langsam um den Kreis
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed + sin(3.0 * theta) * 0.9);
	vec3 braid_rgb = mix(line_color.rgb, pulse_color.rgb, pulse * 0.6);
	vec3 star_rgb = mix(star_color.rgb, pulse_color.rgb, pulse * 0.35);

	float half_width = line_width * 0.5;
	float is_braid = step(braid, half_width);
	float is_star = step(star, half_width * 0.75);

	// Aura: dunkles Glühen um die Linien, im Inneren des Kreises am dichtesten
	float glow = exp(-min(braid, star) / 7.0) * (0.55 + 0.25 * pulse);
	float inner = smoothstep(radius * 1.25, radius * 0.5, r) * 0.55;
	float outer_fade = smoothstep(radius * 1.9, radius * 1.1, r);
	float aura = clamp(max(glow, inner) * outer_fade, 0.0, 0.85);

	// Dithering: die Aura zerfällt in einzelne Pixel statt weich auszulaufen
	int bi = int(mod(cell.x, 4.0)) + int(mod(cell.y, 4.0)) * 4;
	float threshold = (BAYER[bi] + 0.5) / 16.0 - 0.5;
	float aura_steps = clamp(floor(aura * color_levels + 0.5 + threshold) / color_levels, 0.0, 1.0);

	vec3 rgb = aura_color.rgb;
	float alpha = aura_steps;
	if (is_star > 0.5) {
		rgb = star_rgb;
		alpha = 1.0;
	}
	if (is_braid > 0.5) {
		rgb = braid_rgb;
		alpha = 1.0;
	}
	if (alpha > 0.0) {
		rgb = clamp(floor(rgb * color_levels * 2.0 + 0.5 + threshold) / (color_levels * 2.0), 0.0, 1.0);
	}
	COLOR = vec4(rgb, alpha);
}
