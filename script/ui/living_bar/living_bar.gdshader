shader_type canvas_item;

// Füllung der LivingBar im Stil der lebenden Pixel: grobe Pixel mit Verlauf (oben hell, unten dunkel),
// jedes Pixel flimmert mit eigener Phase, aufsteigende helle Funken und Bayer-Dithering wie living_pixels.gdshader.
// Farbe kommt über COLOR (ColorRect.color), damit Tweens und modulate weiter wirken.

global uniform float pixel_scale;

uniform float pixel_size : hint_range(1.0, 12.0, 0.5) = 3.0;
// Verlauf: so viel heller oben bzw. dunkler unten
uniform float top_light : hint_range(0.0, 1.0) = 0.35;
uniform float bottom_shade : hint_range(0.0, 1.0) = 0.45;
uniform float flicker : hint_range(0.0, 1.0) = 0.18;
// Funken: Anteil der Pixel, die gerade aufleuchten, und wie schnell sie nach oben wandern
uniform float spark_density : hint_range(0.0, 0.3) = 0.06;
uniform float spark_speed : hint_range(0.0, 20.0) = 6.0;
uniform float spark_strength : hint_range(0.0, 2.0) = 0.8;
uniform float color_levels : hint_range(2.0, 32.0, 1.0) = 8.0;
uniform float dither_fps : hint_range(0.0, 30.0) = 8.0;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float scale = max(pixel_scale, 1.0);
	vec2 cell = floor(FRAGCOORD.xy / (pixel_size * scale));
	vec2 local = UV;
	vec3 base = COLOR.rgb;

	// Verlauf von oben nach unten, in Pixelstufen
	float v = floor(local.y * 6.0) / 5.0;
	vec3 col = mix(base * (1.0 + top_light), base * (1.0 - bottom_shade), v);

	// Flimmern pro Pixel
	float phase = hash(cell) * 6.2831;
	float speed = 1.0 + hash(cell + 7.0) * 2.0;
	col *= 1.0 + sin(TIME * speed + phase) * flicker;

	// aufsteigende Funken: eine Spalte hat ab und zu ein helles Pixel, das nach oben wandert
	float column = hash(vec2(cell.x, 3.0));
	float rise = fract(TIME * spark_speed * 0.05 * (0.5 + column) + column * 13.0);
	float spark_row = floor((1.0 - rise) * 8.0);
	float row = floor(local.y * 8.0);
	if (column < spark_density * 8.0 && abs(row - spark_row) < 0.5) {
		col += vec3(spark_strength) * (1.0 - rise);
	}

	// Ordered Dithering mit wechselndem Muster
	vec2 d = mod(cell + floor(TIME * dither_fps), 4.0);
	float threshold = (BAYER[int(d.y) * 4 + int(d.x)] + 0.5) / 16.0 - 0.5;
	col = floor(col * color_levels + threshold + 0.5) / color_levels;

	COLOR = vec4(clamp(col, 0.0, 1.5), COLOR.a);
}
