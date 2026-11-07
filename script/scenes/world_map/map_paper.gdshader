shader_type canvas_item;

// Altes Kartenpapier: Faltkanten, Dellen, ausgefranster Rand, Höhenlinien und (je nach Biom) Risse.
// Alles in Pixeln gerechnet (rect_size), damit nichts mit der Kartenhöhe mitgestreckt wird.

uniform vec4 paper_light : source_color = vec4(0.79, 0.70, 0.54, 1.0);
uniform vec4 paper_dark : source_color = vec4(0.61, 0.51, 0.36, 1.0);
uniform vec4 ink : source_color = vec4(0.23, 0.16, 0.08, 1.0);
uniform vec4 crack_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float crack_amount : hint_range(0.0, 1.0) = 0.0;
// 0 = ruhig, 1 = Risse glühen und pulsieren
uniform float crack_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float contour_amount : hint_range(0.0, 1.0) = 0.5;
uniform vec2 rect_size = vec2(1200.0, 2400.0);
uniform float seed = 0.0;
uniform vec2 fold_spacing = vec2(300.0, 560.0);
// Abstand der Papierkante zum Rand des Rechtecks, der Rest ist Platz für den Schlagschatten
uniform float margin = 22.0;

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

// Abstand zur nächsten Faltkante (mit Vorzeichen), .y ist die Nummer des Feldes
vec2 fold(float x, float spacing) {
	float cell = x / spacing;
	return vec2((fract(cell + 0.5) - 0.5) * spacing, floor(cell + 0.5));
}

void fragment() {
	vec2 p = UV * rect_size;
	// Offset klein halten, bei großen Werten verliert das Rauschen an Genauigkeit und zeigt Streifen
	vec2 sp = p + vec2(seed * 37.0, seed * 23.0);

	// Faltkanten laufen nicht schnurgerade
	vec2 fx = fold(p.x + (noise(sp.yy / 90.0) - 0.5) * 8.0, fold_spacing.x);
	vec2 fy = fold(p.y + (noise(sp.xx / 90.0) - 0.5) * 8.0, fold_spacing.y);

	// Ausgefranster Rand, an den Faltkanten eingerissen
	float border = min(min(p.x, rect_size.x - p.x), min(p.y, rect_size.y - p.y));
	float notch = exp(-abs(fx.x) / 12.0) + exp(-abs(fy.x) / 12.0);
	float edge = border - margin + (fbm(sp / 70.0) - 0.5) * 26.0 + (noise(sp / 7.0) - 0.5) * 5.0 - notch * 11.0;

	if (edge < 0.0) {
		// außerhalb des Papiers nur der Schatten
		COLOR = vec4(0.0, 0.0, 0.0, 0.5 * smoothstep(-20.0, 0.0, edge));
	} else {
		// Großflächige, weiche Verfärbung, das Papier bleibt überwiegend hell
		float stain = noise(sp / 420.0) * 0.65 + noise(sp / 170.0 + 7.0) * 0.35;
		vec3 col = mix(paper_dark.rgb, paper_light.rgb, 0.45 + 0.55 * smoothstep(0.2, 0.8, stain));

		// Dellen: nur grobes Rauschen, von schräg oben beleuchtet
		float h = noise(sp / 130.0);
		float dent = (noise((sp + vec2(8.0, 0.0)) / 130.0) - h) + (noise((sp + vec2(0.0, 8.0)) / 130.0) - h);
		col *= 1.0 + clamp(dent * 3.5, -0.09, 0.09);

		// Gefaltete Felder kippen abwechselnd zum Licht
		float flip_x = mod(fx.y, 2.0) * 2.0 - 1.0;
		float flip_y = mod(fy.y, 2.0) * 2.0 - 1.0;
		col *= 1.0 + flip_x * fx.x / fold_spacing.x * 0.12 + flip_y * fy.x / fold_spacing.y * 0.08;
		// Die Kante selbst: dunkle Rille mit heller Seite
		float crease = exp(-abs(fx.x) / 2.2) * (fx.x > 0.0 ? 1.0 : -1.0) * flip_x + exp(-abs(fy.x) / 2.2) * (fy.x > 0.0 ? 1.0 : -1.0) * flip_y;
		col *= 1.0 + crease * 0.2;
		col *= 1.0 - (exp(-abs(fx.x) / 1.2) + exp(-abs(fy.x) / 1.2)) * 0.14;

		// Höhenlinien wie auf einer gedruckten Karte
		float height = fbm(sp / 270.0 + 5.0) * 15.0;
		float width = fwidth(height) * 1.1;
		float contour = fract(height);
		float contour_line = 1.0 - smoothstep(0.0, width, min(contour, 1.0 - contour));
		col = mix(col, ink.rgb, contour_line * contour_amount * 0.3);

		// Risse: Lava, Eis, Trockenrisse oder der Riss im Chaos
		if (crack_amount > 0.0) {
			float n = abs(fbm(sp / 170.0 + 11.0) - 0.5);
			float mask = smoothstep(0.42, 0.6, noise(sp / 330.0 + 3.0));
			float core = (1.0 - smoothstep(0.004, 0.012, n)) * mask;
			float halo = (1.0 - smoothstep(0.0, 0.05, n)) * mask;
			float pulse = mix(1.0, 0.65 + 0.35 * sin(TIME * 1.4 + sp.x * 0.008 + sp.y * 0.005), crack_pulse);
			col = mix(col, crack_color.rgb, halo * crack_amount * crack_pulse * 0.35 * pulse);
			col = mix(col, crack_color.rgb, core * crack_amount * pulse);
		}

		// Papierkörnung
		col *= 0.97 + noise(p / 2.3) * 0.06;

		// Der Rand ist vom Anfassen dunkel und abgegriffen
		float worn = 1.0 - smoothstep(0.0, 85.0, edge);
		col = mix(col, paper_dark.rgb * 0.5, worn * worn * 0.75);

		// Handgezogener Doppelrahmen, folgt dem Papierrand
		float frame = 1.0 - smoothstep(0.8, 2.0, abs(edge - 22.0));
		frame = max(frame, (1.0 - smoothstep(0.3, 1.0, abs(edge - 30.0))) * 0.6);
		col = mix(col, ink.rgb, frame * 0.5);

		COLOR = vec4(col, smoothstep(0.0, 1.5, edge));
	}
}
