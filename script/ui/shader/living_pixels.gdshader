shader_type canvas_item;

// "Lebende Pixel": das Bild wird in grobe Pixel-Partikel zerlegt, jedes Partikel
// zittert mit eigener Phase, Frequenz und Amplitude um seinen Platz.
// Danach animiertes Ordered Dithering (Bayer 4x4) für den flimmernden Retro-Look.
// Alle Bewegungen nutzen ganzzahlige Frequenzen über loop_seconds -> nahtlose Schleife.

// Partikelgröße in Bildschirmpixeln, damit kleine Icons und große Bilder gleich grob wirken
uniform float pixel_size : hint_range(1.0, 12.0, 0.5) = 3.0;
// Mindestanzahl Partikel über die Bildbreite, sonst werden winzige Icons unkenntlich
uniform float min_cells : hint_range(8.0, 128.0, 1.0) = 32.0;
// Grundbewegung in Partikelgrößen, max. 0.5 damit die 3x3-Nachbarsuche reicht
uniform float amplitude : hint_range(0.0, 0.5) = 0.22;
// kurze ruckartige Sprünge einzelner Partikel
uniform float twitch : hint_range(0.0, 0.5) = 0.18;
uniform float twitch_chance : hint_range(0.0, 1.0) = 0.12;
uniform float loop_seconds : hint_range(1.0, 30.0) = 6.0;
// Partikelgröße pulsiert zwischen min und max (1.0 = volle Zelle)
uniform float particle_min_size : hint_range(0.3, 1.0) = 0.7;
uniform float particle_max_size : hint_range(0.3, 1.2) = 1.0;
// Helligkeits-Flackern pro Partikel
uniform float flicker : hint_range(0.0, 1.0) = 0.22;
// Farbstufen pro Kanal für das Dithering
uniform float color_levels : hint_range(2.0, 32.0, 1.0) = 6.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 1.0;
// Bildschirmpixel pro Dither-Pixel
uniform float dither_scale : hint_range(1.0, 8.0, 1.0) = 2.0;
// Wechsel des Dither-Musters pro Sekunde
uniform float dither_fps : hint_range(0.0, 30.0) = 10.0;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.35;
// 0 = unsichtbar, 1 = alle Partikel da (zum Einblenden per Tween)
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
// Umriss um die Silhouette (z. B. ausgewähltes Monster im Kampf), Alpha 0 = aus
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 0.0, 0.0);
// Umrissbreite in Bildschirmpixeln
uniform float outline_thickness : hint_range(0.0, 16.0) = 4.0;
// Einfärbung nach Helligkeit (z. B. Eier nach Seltenheit), Alpha = Stärke, 0 = aus
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);

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

void fragment() {
	// Bildschirmpixel pro UV-Einheit, auch bei Skalierung und Drehung
	vec2 px_per_uv = 1.0 / max(vec2(
		length(vec2(dFdx(UV.x), dFdy(UV.x))),
		length(vec2(dFdx(UV.y), dFdy(UV.y)))
	), vec2(1e-6));
	float cells_x = max(round(px_per_uv.x / pixel_size), min_cells);
	vec2 cells = vec2(cells_x, max(1.0, round(cells_x * px_per_uv.y / px_per_uv.x)));
	vec2 g = UV * cells;
	vec2 base = floor(g);

	float loop_pos = fract(TIME / loop_seconds);
	float t = loop_pos * TAU;
	// Sprung-Zeitschritte, ganzzahlig pro Schleife
	float twitch_step = floor(loop_pos * max(1.0, floor(loop_seconds * 4.0)));

	vec4 best = vec4(0.0);
	float best_prio = -1.0;

	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = base + vec2(float(x), float(y));
			if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= cells.x || cell.y >= cells.y) {
				continue;
			}
			vec4 col = textureLod(TEXTURE, (cell + 0.5) / cells, 0.0);
			if (col.a < alpha_cutoff) {
				continue;
			}
			if (tint_color.a > 0.0) {
				float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
				col.rgb = mix(col.rgb, tint_color.rgb * lum * 1.3, tint_color.a);
			}
			vec4 h = hash4(cell);
			vec4 h2 = hash4(cell + 71.37);
			if (h2.w > reveal) {
				continue;
			}

			// die meisten Partikel bewegen sich wenig, einige deutlich mehr
			float amp = amplitude * (0.25 + 0.75 * h.x * h.x);
			float k1 = 1.0 + floor(h.y * 3.0);
			float k2 = 1.0 + floor(h.z * 3.0);
			float k3 = 3.0 + floor(h2.x * 5.0);
			vec2 off = vec2(
				sin(k1 * t + h.w * TAU) * 0.75 + sin(k3 * t + h2.y * TAU) * 0.25,
				cos(k2 * t + h2.z * TAU) * 0.75 + sin((k3 + 1.0) * t + h.z * TAU) * 0.25
			) * amp;

			vec4 j = hash4(cell + twitch_step * 17.13);
			off += (j.xy - 0.5) * 2.0 * twitch * step(1.0 - twitch_chance, j.z);
			off = clamp(off, -0.5, 0.5);

			float pulse = 0.5 + 0.5 * sin((k2 + 1.0) * t + h2.x * TAU);
			float half_size = mix(particle_min_size, particle_max_size, pulse) * 0.5;

			vec2 d = abs(g - (cell + 0.5 + off));
			if (max(d.x, d.y) < half_size && h2.w > best_prio) {
				best_prio = h2.w;
				float bright = 1.0 + flicker * (sin((k1 + 2.0) * t + h.y * TAU) * 0.6 + (j.w - 0.5) * 0.8);
				best = vec4(col.rgb * bright, 1.0);
			}
		}
	}

	if (best_prio < 0.0) {
		COLOR = vec4(0.0);
		// Umriss außerhalb der ursprünglichen Silhouette
		if (outline_color.a > 0.0 && textureLod(TEXTURE, UV, 0.0).a < alpha_cutoff) {
			vec2 r = outline_thickness / px_per_uv;
			float hit = 0.0;
			for (int i = 0; i < 12; i++) {
				float a = float(i) * TAU / 12.0;
				vec2 p = UV + vec2(cos(a), sin(a)) * r;
				if (p.x >= 0.0 && p.y >= 0.0 && p.x <= 1.0 && p.y <= 1.0) {
					hit = max(hit, step(alpha_cutoff, textureLod(TEXTURE, p, 0.0).a));
				}
			}
			COLOR = vec4(outline_color.rgb, outline_color.a * hit) * vertex_color;
		}
	} else {
		vec2 dp = floor(FRAGCOORD.xy / dither_scale);
		// Muster verschiebt sich schrittweise -> animiertes Dithering
		vec4 ds = hash4(vec2(floor(loop_pos * max(1.0, floor(loop_seconds * dither_fps))), 3.7));
		dp += floor(ds.xy * 4.0);
		int bi = int(mod(dp.x, 4.0)) + int(mod(dp.y, 4.0)) * 4;
		float threshold = (BAYER[bi] + 0.5) / 16.0 - 0.5;
		vec3 rgb = floor(best.rgb * color_levels + 0.5 + threshold * dither_strength) / color_levels;
		COLOR = vec4(clamp(rgb, 0.0, 1.0), 1.0) * vertex_color;
	}
}
