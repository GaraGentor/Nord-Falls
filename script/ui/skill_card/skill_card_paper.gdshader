shader_type canvas_item;

// Skill-Karte im Stil des Kartenpapiers (map_paper.gdshader), aber dunkel und ruhig, damit heller Text lesbar bleibt.
// Bewegung gibt es nur am Rand (glühende Risse, pulsierender Rahmen) und ganz schwach in den Höhenlinien.
// Alles in Pixeln gerechnet (rect_size), damit nichts mit der Kartengröße mitgestreckt wird.

uniform vec4 paper_light : source_color = vec4(0.19, 0.15, 0.11, 1.0);
uniform vec4 paper_dark : source_color = vec4(0.09, 0.07, 0.055, 1.0);
uniform vec4 ink : source_color = vec4(0.72, 0.61, 0.44, 1.0);
// Farbe des Elements: Risse, Rahmen und der Lichtschein in den Höhenlinien
uniform vec4 accent : source_color = vec4(0.9, 0.6, 0.3, 1.0);
uniform vec4 frame_color : source_color = vec4(0.72, 0.61, 0.44, 1.0);
// 0 = normal, 1 = Rahmen leuchtet voll (Hover, Auswahl)
uniform float frame_glow : hint_range(0.0, 1.0) = 0.0;
// 0 = normal, 1 = grau und ohne Bewegung (gesperrte Karte)
uniform float muted : hint_range(0.0, 1.0) = 0.0;
uniform vec2 rect_size = vec2(150.0, 200.0);
uniform float seed = 0.0;
// Abstand der Papierkante zum Rand des Rechtecks, der Rest ist Platz für den Schlagschatten
uniform float margin = 3.0;

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
	vec2 p = UV * rect_size;
	// Offset klein halten, bei großen Werten verliert das Rauschen an Genauigkeit und zeigt Streifen
	vec2 sp = p + vec2(seed * 7.0, seed * 5.0);
	float alive = 1.0 - muted;

	// Leicht ausgefranster Rand, die Karte soll aber stabil wirken
	float border = min(min(p.x, rect_size.x - p.x), min(p.y, rect_size.y - p.y));
	float edge = border - margin + (fbm(sp / 18.0) - 0.5) * 3.0 + (noise(sp / 3.0) - 0.5) * 0.8;

	if (edge < 0.0) {
		// außerhalb des Papiers nur der Schatten
		COLOR = vec4(0.0, 0.0, 0.0, 0.45 * smoothstep(-3.0, 0.0, edge));
	} else {
		// Weiche Verfärbung
		float stain = noise(sp / 90.0) * 0.65 + noise(sp / 38.0 + 7.0) * 0.35;
		vec3 col = mix(paper_dark.rgb, paper_light.rgb, 0.3 + 0.7 * smoothstep(0.2, 0.8, stain));

		// Faltkanten: eine senkrechte und eine waagerechte, nicht schnurgerade und nie genau mittig
		vec2 fold_at = rect_size * (vec2(0.42, 0.56) + vec2(hash(vec2(seed, 1.0)), hash(vec2(seed, 2.0))) * 0.12);
		float fx = p.x - fold_at.x + (noise(sp.yy / 40.0) - 0.5) * 4.0;
		float fy = p.y - fold_at.y + (noise(sp.xx / 40.0) - 0.5) * 4.0;
		// die Felder kippen zum Licht, die Kante selbst ist eine feine Rille
		col *= 1.0 + sign(fx) * 0.035 + sign(fy) * 0.025;
		col *= 1.0 - (exp(-abs(fx) / 1.0) + exp(-abs(fy) / 1.0)) * 0.22;

		// Zur Mitte hin wird alles ruhiger, dort steht der Text
		float calm = smoothstep(4.0, 34.0, edge);

		// Höhenlinien wie auf der Karte, ab und zu läuft ein Lichtschein in Elementfarbe hindurch
		float height = fbm(sp / 62.0 + 5.0) * 9.0;
		float contour = fract(height);
		float contour_line = 1.0 - smoothstep(0.0, fwidth(height) * 1.1, min(contour, 1.0 - contour));
		float band = sin((p.x + p.y) * 0.012 - TIME * 0.7 + seed);
		band = smoothstep(0.75, 1.0, band) * alive;
		col = mix(col, ink.rgb, contour_line * mix(0.26, 0.09, calm));
		col = mix(col, accent.rgb, contour_line * band * mix(0.6, 0.14, calm));

		// Risse wie im Lava-Biom, glühen in Elementfarbe und nur am Rand
		float n = abs(fbm(sp / 34.0 + 11.0) - 0.5);
		float crack_mask = (1.0 - calm) * smoothstep(0.3, 0.55, noise(sp / 46.0 + 3.0)) * alive;
		float core = (1.0 - smoothstep(0.006, 0.02, n)) * crack_mask;
		float halo = (1.0 - smoothstep(0.0, 0.07, n)) * crack_mask;
		float pulse = 0.65 + 0.35 * sin(TIME * 1.4 + sp.x * 0.03 + sp.y * 0.02);
		col = mix(col, accent.rgb, halo * 0.3 * pulse);
		col = mix(col, accent.rgb, core * 0.9 * pulse);

		// Papierkörnung
		col *= 0.96 + noise(p / 1.6) * 0.08;

		// Der Rand ist dunkel und abgegriffen
		float worn = 1.0 - smoothstep(0.0, 16.0, edge);
		col = mix(col, paper_dark.rgb * 0.45, worn * worn * 0.8);

		// Handgezogener Doppelrahmen, folgt dem Papierrand und pulsiert leicht in Elementfarbe
		float frame = 1.0 - smoothstep(0.5, 1.4, abs(edge - 3.5));
		float frame_inner = (1.0 - smoothstep(0.2, 0.8, abs(edge - 6.5))) * 0.5;
		float frame_pulse = (0.5 + 0.5 * sin(TIME * 1.1 + seed)) * alive;
		vec3 frame_col = mix(frame_color.rgb, accent.rgb, 0.45 + 0.3 * frame_pulse);
		frame_col = mix(frame_col, frame_color.rgb * 1.25, frame_glow);
		col = mix(col, frame_col, max(frame, frame_inner) * mix(0.8, 1.0, frame_glow));
		// Schein des hervorgehobenen Rahmens nach innen
		col += frame_color.rgb * frame_glow * 0.16 * (1.0 - smoothstep(3.5, 15.0, edge));

		// Gesperrte Karten sind grau und dunkler
		float gray = dot(col, vec3(0.3, 0.59, 0.11));
		col = mix(col, vec3(gray) * 0.8, muted);

		COLOR = vec4(col, smoothstep(0.0, 1.0, edge));
	}
}
