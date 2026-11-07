shader_type canvas_item;

// Bild als "Vorstellung": der Rand löst sich in eine ziehende Wolke auf, statt hart abzuschneiden.
// Eine Welle läuft am Rand entlang und zieht dort ein paar Pixel nach außen.
// Das Bild selbst besteht wie bei living_pixels aus zitternden Pixel-Partikeln mit Dithering.

// Größe des Nodes in Pixeln, kommt per Skript. UV hilft hier nicht, weil
// "Keep Aspect Covered" nur einen Ausschnitt der Textur zeichnet.
uniform vec2 rect_size = vec2(600.0, 700.0);
uniform float pixel_size : hint_range(1.0, 12.0, 0.5) = 4.0;
// Partikel: Bewegung in Partikelgrößen, max. 0.5 damit die 3x3-Nachbarsuche reicht
uniform float amplitude : hint_range(0.0, 0.5) = 0.22;
uniform float twitch : hint_range(0.0, 0.5) = 0.18;
uniform float twitch_chance : hint_range(0.0, 1.0) = 0.12;
uniform float loop_seconds : hint_range(1.0, 30.0) = 6.0;
// Größe pulsiert zwischen min und max (1.0 = volle Zelle)
uniform float particle_min_size : hint_range(0.3, 1.0) = 0.8;
uniform float particle_max_size : hint_range(0.3, 1.2) = 1.1;
// Lücken zwischen den Partikeln zeigen das abgedunkelte Bild statt des hellen Hintergrunds
uniform float gap_brightness : hint_range(0.0, 1.0) = 0.55;
uniform float flicker : hint_range(0.0, 1.0) = 0.22;
uniform float corner_radius : hint_range(0.0, 200.0) = 70.0;
// wie weit die Wolke ins Bild reicht, in Pixeln
uniform float cloud_depth : hint_range(0.0, 200.0) = 84.0;
// Breite des Übergangs von Wolke zu Bild, in Pixeln
uniform float cloud_softness : hint_range(1.0, 100.0) = 30.0;
// Größe der Wolkenbäusche, in Pixeln
uniform float cloud_scale : hint_range(10.0, 300.0) = 62.0;
uniform float cloud_speed : hint_range(0.0, 2.0) = 0.16;
// Dunst, der die Wolke am Rand einfärbt, Alpha = Stärke
uniform vec4 mist_color : source_color = vec4(0.78, 0.88, 0.95, 0.85);
// Randwelle: Verzerrung in Pixeln, Breite der Zone und Wellen pro Umlauf
uniform float stretch_pixels : hint_range(0.0, 40.0) = 12.0;
uniform float stretch_width : hint_range(1.0, 200.0) = 80.0;
uniform float wave_count : hint_range(1.0, 32.0, 1.0) = 9.0;
uniform float wave_speed : hint_range(0.0, 6.0) = 1.1;
uniform float color_levels : hint_range(2.0, 32.0, 1.0) = 8.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 1.0;
uniform float dither_scale : hint_range(1.0, 8.0, 1.0) = 2.0;
// Wechsel des Dither-Musters pro Sekunde
uniform float dither_fps : hint_range(0.0, 30.0) = 10.0;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

vec4 hash4(vec2 p) {
	vec4 p4 = fract(vec4(p.xyxy) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.55;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amp;
		p = p * 2.03 + vec2(17.1, 9.3);
		amp *= 0.5;
	}
	return sum;
}

// Abstand zum abgerundeten Rand, innen positiv
float inner_distance(vec2 p) {
	vec2 q = abs(p - rect_size * 0.5) - rect_size * 0.5 + corner_radius;
	return -(length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - corner_radius);
}

float bayer(vec2 dp) {
	int bi = int(mod(dp.x, 4.0)) + int(mod(dp.y, 4.0)) * 4;
	return (BAYER[bi] + 0.5) / 16.0;
}

void fragment() {
	vec2 uv_per_px = vec2(dFdx(UV.x), dFdy(UV.y));
	vec2 g = local_pos / pixel_size;
	vec2 base = floor(g);
	vec2 p = (base + 0.5) * pixel_size;
	float dist = inner_distance(p);

	// Welle läuft einmal rundherum, Winkel statt Bogenlänge reicht bei dem Rahmen
	vec2 from_center = p - rect_size * 0.5;
	float angle = atan(from_center.y, from_center.x);
	float wave = sin(angle * wave_count - TIME * wave_speed) * 0.65
		+ sin(angle * (wave_count * 2.0 + 1.0) + TIME * wave_speed * 0.7) * 0.35;
	float rim = 1.0 - smoothstep(0.0, stretch_width, dist);
	vec2 inward = -normalize(from_center + vec2(0.001));
	vec2 stretch = inward * wave * rim * rim * stretch_pixels;

	// Partikel wie in living_pixels, ganzzahlige Frequenzen -> nahtlose Schleife
	float loop_pos = fract(TIME / loop_seconds);
	float t = loop_pos * TAU;
	float twitch_step = floor(loop_pos * max(1.0, floor(loop_seconds * 4.0)));
	vec3 particle = vec3(0.0);
	float best_prio = -1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = base + vec2(float(x), float(y));
			vec4 h = hash4(cell);
			vec4 h2 = hash4(cell + 71.37);

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
				vec2 cell_center = (cell + 0.5) * pixel_size + stretch;
				vec3 col = textureLod(TEXTURE, UV + (cell_center - local_pos) * uv_per_px, 0.0).rgb;
				particle = col * (1.0 + flicker * (sin((k1 + 2.0) * t + h.y * TAU) * 0.6 + (j.w - 0.5) * 0.8));
			}
		}
	}
	if (best_prio < 0.0) {
		particle = textureLod(TEXTURE, UV + (p + stretch - local_pos) * uv_per_px, 0.0).rgb * gap_brightness;
	}

	// Wolkenrand: Rauschen schiebt die Kante, zwei Lagen ziehen gegeneinander
	vec2 drift = vec2(TIME * cloud_speed, -TIME * cloud_speed * 0.6);
	float cloud = fbm(p / cloud_scale + drift);
	cloud = mix(cloud, fbm(p / (cloud_scale * 0.55) - drift * 1.4 + 31.7), 0.35);
	// fbm liegt meist um die Mitte, gespreizt entstehen erst richtige Bäusche
	cloud = smoothstep(0.28, 0.62, cloud);
	float edge = dist - cloud * cloud_depth;
	float alpha = smoothstep(0.0, cloud_softness, edge);

	vec2 dp = floor(FRAGCOORD.xy / dither_scale);
	vec3 rgb = mix(particle, mist_color.rgb, mist_color.a * (1.0 - smoothstep(0.0, cloud_softness * 1.8, edge)));
	// Muster verschiebt sich schrittweise -> animiertes Dithering
	vec4 ds = hash4(vec2(floor(loop_pos * max(1.0, floor(loop_seconds * dither_fps))), 3.7));
	float threshold = bayer(dp + floor(ds.xy * 4.0)) - 0.5;
	rgb = floor(rgb * color_levels + 0.5 + threshold * dither_strength) / color_levels;

	// Auflösen in Dither-Pixel statt weichem Alpha, das Muster steht still, damit die Kante nicht flimmert
	COLOR = vec4(clamp(rgb, 0.0, 1.0), step(bayer(dp), alpha)) * COLOR;
}
