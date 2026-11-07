shader_type canvas_item;

// Legt den "Lebende Pixel"-Look aus Kampf und Start (living_pixels.gdshader) über alles, was
// vorher auf den Bildschirm gezeichnet wurde: grobe Pixel, Flackern, wenige Farbstufen, Dithering.
// Dazu wird das Bild abgedunkelt und entsättigt, damit die Karte düster wirkt.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest, repeat_disable;

// Partikelgröße in Bildschirmpixeln
uniform float pixel_size : hint_range(1.0, 12.0, 0.5) = 4.0;
uniform float loop_seconds : hint_range(1.0, 30.0) = 30.0;
// Helligkeits-Flackern pro Partikel
uniform float flicker : hint_range(0.0, 1.0) = 0.2;
// Farbstufen pro Kanal für das Dithering
uniform float color_levels : hint_range(2.0, 32.0, 1.0) = 4.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 1.0;
// Bildschirmpixel pro Dither-Pixel
uniform float dither_scale : hint_range(1.0, 8.0, 1.0) = 1.0;
// Wechsel des Dither-Musters pro Sekunde
uniform float dither_fps : hint_range(0.0, 30.0) = 10.0;
// Sättigung vor dem Dithering, Helligkeit erst danach: so bleiben die Farbtöne erhalten (wie modulate im Kampf)
uniform float saturation : hint_range(0.0, 1.5) = 0.7;
// Helle Stellen werden stärker abgedunkelt als dunkle: Papier wird düster, Glut und Lava glimmen weiter
uniform float highlight_brightness : hint_range(0.0, 1.5) = 0.55;
uniform float shadow_brightness : hint_range(0.0, 1.5) = 1.0;
// wie stark die Ränder im Dunkeln versinken
uniform float vignette : hint_range(0.0, 1.0) = 0.4;

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

void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / pixel_size);
	// Mittel aus vier Punkten, sonst fallen dünne Linien zwischen die Partikel
	vec3 col = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		vec2 sub = (vec2(float(i & 1), float(i >> 1)) + 0.5) * 0.5;
		col += textureLod(screen_texture, (cell + sub) * pixel_size * SCREEN_PIXEL_SIZE, 0.0).rgb;
	}
	col *= 0.25;

	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, saturation);

	float loop_pos = fract(TIME / loop_seconds);
	float t = loop_pos * TAU;
	vec4 h = hash4(cell);
	vec4 j = hash4(cell + floor(loop_pos * max(1.0, floor(loop_seconds * 4.0))) * 17.13);
	float k = 1.0 + floor(h.y * 3.0);
	col *= 1.0 + flicker * (sin((k + 2.0) * t + h.x * TAU) * 0.6 + (j.w - 0.5) * 0.8);

	vec2 dp = floor(FRAGCOORD.xy / dither_scale);
	// Muster verschiebt sich schrittweise -> animiertes Dithering
	vec4 ds = hash4(vec2(floor(loop_pos * max(1.0, floor(loop_seconds * dither_fps))), 3.7));
	dp += floor(ds.xy * 4.0);
	int bi = int(mod(dp.x, 4.0)) + int(mod(dp.y, 4.0)) * 4;
	float threshold = (BAYER[bi] + 0.5) / 16.0 - 0.5;
	vec3 rgb = floor(col * color_levels + 0.5 + threshold * dither_strength) / color_levels;
	vec2 centered = UV * 2.0 - 1.0;
	rgb = clamp(rgb, 0.0, 1.0);
	float brightness = mix(shadow_brightness, highlight_brightness, dot(rgb, vec3(0.299, 0.587, 0.114)));
	float dark = brightness * (1.0 - vignette * smoothstep(0.35, 1.25, length(centered)));
	COLOR = vec4(rgb * dark, 1.0);
}
