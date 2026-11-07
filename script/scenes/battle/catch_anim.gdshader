shader_type canvas_item;

uniform vec2 center = vec2(0.5);
uniform int stripes = 24;
uniform float speed : hint_range(0.0, 5.0, 0.1) = 0.2;
uniform int direction : hint_range(-1, 1, 2) = 1;
uniform vec4 stripe_colors[8];
uniform int color_count : hint_range(1, 8) = 2;

// "Lebende Pixel" wie map_background.gdshader, aber auf die berechnete Spirale
uniform bool living_pixels = true;
// Partikelgröße in Bildschirmpixeln
uniform float pixel_size : hint_range(1.0, 12.0, 0.5) = 4.0;
// Grundbewegung in Partikelgrößen, max. 0.5 damit die 3x3-Nachbarsuche reicht
uniform float amplitude : hint_range(0.0, 0.5) = 0.0;
uniform float loop_seconds : hint_range(1.0, 30.0) = 19.365;
// Partikelgröße pulsiert zwischen min und max, unter 1.0 entstehen Lücken
uniform float particle_min_size : hint_range(0.3, 1.0) = 1.0;
uniform float particle_max_size : hint_range(0.3, 1.2) = 1.2;
// Helligkeits-Flackern pro Partikel
uniform float flicker : hint_range(0.0, 1.0) = 0.15;
// Farbstufen pro Kanal für das Dithering
uniform float color_levels : hint_range(2.0, 32.0, 1.0) = 8.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 1.0;
// Bildschirmpixel pro Dither-Pixel
uniform float dither_scale : hint_range(1.0, 8.0, 1.0) = 2.0;
// Wechsel des Dither-Musters pro Sekunde
uniform float dither_fps : hint_range(0.0, 30.0) = 10.0;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);


vec4 hash4(vec2 p) {
	vec4 p4 = fract(vec4(p.xyxy) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}


// aspect_ratio = Breite / Höhe in Bildschirmpixeln, damit die Spirale rund bleibt
vec3 spiral_color(vec2 uv, float aspect_ratio, float time) {
	vec2 corrected_uv = uv * vec2(aspect_ratio, 1.0);
	vec2 corrected_center = center * vec2(aspect_ratio, 1.0);

	vec2 dir = corrected_center - corrected_uv;
	float angle = atan(dir.y, dir.x) - (time * speed * float(direction));

	int stripe_index = int(floor(angle / (TAU / float(stripes)))) % stripes;
	int color_index = stripe_index % color_count;
	color_index = clamp(color_index, 0, color_count - 1);
	return stripe_colors[color_index].rgb;
}


void fragment() {
	vec2 px_per_uv = 1.0 / max(vec2(
		length(vec2(dFdx(UV.x), dFdy(UV.x))),
		length(vec2(dFdx(UV.y), dFdy(UV.y)))
	), vec2(1e-6));
	float aspect_ratio = px_per_uv.x / px_per_uv.y;

	if (!living_pixels) {
		COLOR.rgb = spiral_color(UV, aspect_ratio, TIME);
	} else {
		vec2 cells = max(round(px_per_uv / pixel_size), vec2(1.0));
		vec2 g = UV * cells;
		vec2 base = floor(g);

		float loop_pos = fract(TIME / loop_seconds);
		float t = loop_pos * TAU;

		// Fallback, falls kein Partikel das Pixel trifft
		vec3 best = spiral_color((base + 0.5) / cells, aspect_ratio, TIME);
		float best_prio = -1.0;

		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 cell = base + vec2(float(x), float(y));
				vec4 h = hash4(cell);
				vec4 h2 = hash4(cell + 71.37);

				float amp = amplitude * (0.25 + 0.75 * h.x * h.x);
				float k1 = 1.0 + floor(h.y * 3.0);
				float k2 = 1.0 + floor(h.z * 3.0);
				float k3 = 3.0 + floor(h2.x * 5.0);
				vec2 off = vec2(
					sin(k1 * t + h.w * TAU) * 0.75 + sin(k3 * t + h2.y * TAU) * 0.25,
					cos(k2 * t + h2.z * TAU) * 0.75 + sin((k3 + 1.0) * t + h.z * TAU) * 0.25
				) * amp;
				off = clamp(off, -0.5, 0.5);

				float pulse = 0.5 + 0.5 * sin((k2 + 1.0) * t + h2.x * TAU);
				float half_size = mix(particle_min_size, particle_max_size, pulse) * 0.5;

				vec2 d = abs(g - (cell + 0.5 + off));
				if (max(d.x, d.y) < half_size && h2.w > best_prio) {
					best_prio = h2.w;
					vec3 col = spiral_color((cell + 0.5) / cells, aspect_ratio, TIME);
					float bright = 1.0 + flicker * sin((k1 + 2.0) * t + h.y * TAU);
					best = col * bright;
				}
			}
		}

		vec2 dp = floor(FRAGCOORD.xy / dither_scale);
		// Muster verschiebt sich schrittweise -> animiertes Dithering
		vec4 ds = hash4(vec2(floor(loop_pos * max(1.0, floor(loop_seconds * dither_fps))), 3.7));
		dp += floor(ds.xy * 4.0);
		int bi = int(mod(dp.x, 4.0)) + int(mod(dp.y, 4.0)) * 4;
		float threshold = (BAYER[bi] + 0.5) / 16.0 - 0.5;
		COLOR.rgb = clamp(floor(best * color_levels + 0.5 + threshold * dither_strength) / color_levels, 0.0, 1.0);
	}
}
