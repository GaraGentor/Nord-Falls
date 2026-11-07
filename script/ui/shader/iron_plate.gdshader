shader_type canvas_item;

// Dunkle Eisenplatte für Textflächen in beliebiger Größe (auf einem ColorRect):
// gleiche groben Pixel, gleiches Flackern und Dithering wie living_pixels.gdshader,
// die Platte wird aber berechnet, damit sie sich beim Skalieren nicht verzerrt.

uniform vec4 fill_top : source_color = vec4(0.09, 0.125, 0.145, 1.0);
uniform vec4 fill_bottom : source_color = vec4(0.05, 0.07, 0.085, 1.0);
uniform vec4 outline_color : source_color = vec4(0.024, 0.031, 0.047, 1.0);
// innerer Rand, wird beim Hervorheben umgefärbt
uniform vec4 rim_color : source_color = vec4(0.31, 0.415, 0.424, 1.0);
// Partikelgröße in Bildschirmpixeln
uniform float pixel_size : hint_range(1.0, 12.0, 0.5) = 3.0;
// abgeschrägte Ecken, in Partikeln
uniform float corner_cells : hint_range(0.0, 8.0, 1.0) = 2.0;
// Flecken und Kratzer im Metall
uniform float mottle : hint_range(0.0, 1.0) = 0.45;
uniform float loop_seconds : hint_range(1.0, 30.0) = 19.365;
uniform float flicker : hint_range(0.0, 1.0) = 0.15;
uniform float color_levels : hint_range(2.0, 32.0, 1.0) = 12.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 1.0;
uniform float dither_scale : hint_range(1.0, 8.0, 1.0) = 2.0;
uniform float dither_fps : hint_range(0.0, 30.0) = 10.0;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

// Modulate des Nodes, da COLOR im Fragment überschrieben wird
varying vec4 vertex_color;

void vertex() {
	vertex_color = COLOR;
}

vec4 hash4(vec2 p) {
	vec4 p4 = fract(vec4(p.xyxy) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

// weiche Flecken über mehrere Partikel
float blotch(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash4(i).x;
	float b = hash4(i + vec2(1.0, 0.0)).x;
	float c = hash4(i + vec2(0.0, 1.0)).x;
	float d = hash4(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 px_per_uv = 1.0 / max(vec2(
		length(vec2(dFdx(UV.x), dFdy(UV.x))),
		length(vec2(dFdx(UV.y), dFdy(UV.y)))
	), vec2(1e-6));
	vec2 cells = max(round(px_per_uv / pixel_size), vec2(1.0));
	vec2 cell = floor(UV * cells);
	vec2 from_start = cell;
	vec2 from_end = cells - 1.0 - cell;
	vec2 edge2 = min(from_start, from_end);
	// Abstand zum Rand, die Ecken zählen als Schräge
	float edge = min(min(edge2.x, edge2.y), edge2.x + edge2.y - corner_cells);

	if (edge < 0.0) {
		COLOR = vec4(0.0);
	} else {
		float loop_pos = fract(TIME / loop_seconds);
		float t = loop_pos * TAU;
		vec4 h = hash4(cell);
		vec3 rgb;
		if (edge < 1.0) {
			rgb = outline_color.rgb;
		} else if (edge < 2.0) {
			// oben links fällt Licht auf den Rand, unten rechts liegt er im Schatten
			float lit = from_start.x < 2.0 || from_start.y < 2.0 ? 1.0 : 0.55;
			rgb = rim_color.rgb * lit;
		} else {
			rgb = mix(fill_top.rgb, fill_bottom.rgb, UV.y);
			float stain = blotch(cell / 9.0) * 0.7 + blotch(cell / 3.0) * 0.3;
			rgb *= 1.0 + mottle * (stain - 0.5) * 1.4 + mottle * (h.y - 0.5) * 0.5;
			// Schatten direkt am Rand
			rgb *= mix(0.6, 1.0, clamp((edge - 2.0) / 3.0, 0.0, 1.0));
		}
		float k = 1.0 + floor(h.z * 3.0);
		rgb *= 1.0 + flicker * sin((k + 2.0) * t + h.w * TAU);

		vec2 dp = floor(FRAGCOORD.xy / dither_scale);
		// Muster verschiebt sich schrittweise -> animiertes Dithering
		vec4 ds = hash4(vec2(floor(loop_pos * max(1.0, floor(loop_seconds * dither_fps))), 3.7));
		dp += floor(ds.xy * 4.0);
		int bi = int(mod(dp.x, 4.0)) + int(mod(dp.y, 4.0)) * 4;
		float threshold = (BAYER[bi] + 0.5) / 16.0 - 0.5;
		rgb = floor(rgb * color_levels + 0.5 + threshold * dither_strength) / color_levels;
		COLOR = vec4(clamp(rgb, 0.0, 1.0), 1.0) * vertex_color;
	}
}
