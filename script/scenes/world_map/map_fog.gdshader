shader_type canvas_item;

// Bildschirmpixel pro Spielpixel (1280x720), setzt GameSettings: bei scharfer Darstellung (canvas_items) auf großen
// Bildschirmen bleiben Partikel und Dithering so grob wie in der Grundauflösung
global uniform float pixel_scale;

// Treibender Nebel/Staub über der Karte, grob gerastert passend zum Pixel-Look. Blitze hellen ihn auf.

uniform vec4 fog_color : source_color = vec4(1.0);
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.2;
uniform float scale = 320.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// wird vom Skript mit dem Wind weitergezählt, damit der Nebel beim Richtungswechsel nicht springt
uniform vec2 drift = vec2(0.0);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.1 + 17.0) * 0.3 + noise(p * 4.3 + 41.0) * 0.15;
}

void fragment() {
	float fog_cell = 3.0 * max(pixel_scale, 0.01);
	vec2 p = floor(FRAGCOORD.xy / fog_cell) * fog_cell;
	float a = fbm(p / scale + drift);
	float b = fbm(p / (scale * 0.55) - drift * 1.6 + 9.0);
	float density = smoothstep(0.42, 0.78, a) * 0.75 + smoothstep(0.5, 0.8, b) * 0.35;
	float alpha = floor(density * 7.0) / 7.0 * amount;
	COLOR = vec4(mix(fog_color.rgb, flash_color.rgb, flash), max(alpha, flash * 0.28));
}
