shader_type canvas_item;

uniform vec4 bottom_color: source_color;
uniform vec4 top_color: source_color;

uniform float wave_amp: hint_range(0.0, 0.5);
uniform float wave_size: hint_range(1.0, 10.0);
uniform float wave_time_mul: hint_range(0.1, 2.0);

uniform int total_phases: hint_range(2, 600, 1);

// "Lebende Pixel" wie living_pixels.gdshader, aber auf die berechneten Wellen statt auf eine Textur
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


float rand(float n){return fract(sin(n) * 43758.5453123);}


float noise(float p){
	float fl = floor(p);
  float fc = fract(p);
	return mix(rand(fl), rand(fl + 1.0), fc);
}


float fmod(float x, float y) {
	return x - floor(x / y) * y;
}


vec4 lerp(vec4 a, vec4 b, float w) {
	return a + w * (b - a);
}


vec4 hash4(vec2 p) {
	vec4 p4 = fract(vec4(p.xyxy) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}


vec4 wave_color(vec2 uv, float time) {
	float t = float(total_phases);
	float effective_wave_amp = min(wave_amp, 0.5 / t);
	float d = fmod(uv.y, 1.0 / t);
	float i = floor(uv.y * t);
	float vi = floor(uv.y * t + t * effective_wave_amp);
	float s = effective_wave_amp * sin((uv.x + time * max(1.0 / t, noise(vi)) * wave_time_mul * vi / t) * 2.0 * PI * wave_size);

	if (d < s) i--;
	if (d > s + 1.0 / t) i++;
	i = clamp(i, 0.0, t - 1.0);

	return lerp(top_color, bottom_color, i / (t - 1.0));
}


void fragment() {
	if (!living_pixels) {
		COLOR = wave_color(UV, TIME);
	} else {
		vec2 px_per_uv = 1.0 / max(vec2(
			length(vec2(dFdx(UV.x), dFdy(UV.x))),
			length(vec2(dFdx(UV.y), dFdy(UV.y)))
		), vec2(1e-6));
		vec2 cells = max(round(px_per_uv / pixel_size), vec2(1.0));
		vec2 g = UV * cells;
		vec2 base = floor(g);

		float loop_pos = fract(TIME / loop_seconds);
		float t = loop_pos * TAU;

		// Fallback, falls kein Partikel das Pixel trifft
		vec4 best = wave_color((base + 0.5) / cells, TIME);
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
					vec4 col = wave_color((cell + 0.5) / cells, TIME);
					float bright = 1.0 + flicker * sin((k1 + 2.0) * t + h.y * TAU);
					best = vec4(col.rgb * bright, col.a);
				}
			}
		}

		vec2 dp = floor(FRAGCOORD.xy / dither_scale);
		// Muster verschiebt sich schrittweise -> animiertes Dithering
		vec4 ds = hash4(vec2(floor(loop_pos * max(1.0, floor(loop_seconds * dither_fps))), 3.7));
		dp += floor(ds.xy * 4.0);
		int bi = int(mod(dp.x, 4.0)) + int(mod(dp.y, 4.0)) * 4;
		float threshold = (BAYER[bi] + 0.5) / 16.0 - 0.5;
		vec3 rgb = floor(best.rgb * color_levels + 0.5 + threshold * dither_strength) / color_levels;
		COLOR = vec4(clamp(rgb, 0.0, 1.0), best.a);
	}
}
