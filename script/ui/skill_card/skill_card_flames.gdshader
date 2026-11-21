shader_type canvas_item;

// Pixel-Effekt rund um eine Skill-Karte. Die Bewegung zeigt die Art der Karte, die Farbe (SkillCardPaper.KIND_COLORS)
// unterscheidet innerhalb der Art (physisch / magisch):
//   0 Angriff: lodernde Flammenzungen, die nach oben steigen
//   1 Schild:  ruhige Wasserwellen mit Schaumkrone, die von unten Mitte beidseitig nach oben fließen (Magie-Schild mit Lichtfunken)
//   2 Buff:    Funken steigen nach oben
//   3 Debuff:  Tropfen sinken nach unten
// Passive haben keinen Effekt (SkillCardPaper blendet ihn aus).
// Das Rechteck ragt um pad (links, oben, rechts, unten) über das Papier hinaus. Alles beginnt ein Stück auf dem
// Papierrand (overlap), damit keine Lücke zur Karte bleibt, und ist auf ein grobes Pixelraster gerastert.

uniform int mode = 0;
// 0 = physisch, 1 = magisch (Schild: Lichtfunken im Wasser)
uniform int variant = 0;
uniform vec4 flame_color : source_color = vec4(1.0, 0.3, 0.1, 1.0);
uniform vec2 rect_size = vec2(200.0, 260.0);
// Überstand des Rechtecks über das Papier: links, oben, rechts, unten (Pixel)
uniform vec4 pad = vec4(20.0, 24.0, 20.0, 24.0);
// so weit beginnt der Effekt auf dem Papier (Papierrand liegt 3 Pixel innen, siehe margin im Papier-Shader)
uniform float overlap = 4.0;
// Größe eines Effekt-Pixels
uniform float pixel = 2.0;
uniform float speed = 1.0;
uniform float seed = 0.0;

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
	return noise(p) * 0.6 + noise(p * 2.03 + 13.0) * 0.28 + noise(p * 4.1 + 37.0) * 0.12;
}

// Reichweite je nach Richtung vom Papier weg: nach oben, zur Seite, nach unten (dir_y < 0 = nach oben)
float reach(float dir_y, float top, float side, float bottom) {
	return side + max(-dir_y, 0.0) * (top - side) + max(dir_y, 0.0) * (bottom - side);
}

vec4 flames(vec2 sp, float e, float dir_y, float t) {
	// etwa so hoch wie die Wellen beim Schild
	float fall = e / reach(dir_y, 16.0, 8.0, 4.0);
	// senkrecht gestrecktes Rauschen, das nach oben wandert: lange, ruhige Zungen
	float body = fbm(vec2(sp.x / 7.0, sp.y / 18.0 + t * 1.1));
	float detail = noise(vec2(sp.x / 3.5, sp.y / 7.0 + t * 2.2));
	// Höhe der einzelnen Zungen schwankt langsam entlang des Randes
	float sway = noise(vec2(sp.x / 13.0 + sp.y / 13.0, t * 0.35));
	// kein geschlossener Saum: schon am Rand nur einzelne Zungen, die nach außen ausdünnen
	float heat = 0.5 - fall * (0.8 - sway * 0.45) + (body - 0.5) * 1.7 + (detail - 0.5) * 0.3;
	// drei harte Stufen wie in Pixel-Art: heller Kern (nur im Inneren der Zungen), Farbe, dunkle Spitzen
	if (heat > 0.9 && fall > 0.08) {
		return vec4(mix(flame_color.rgb, vec3(1.0), 0.4), 1.0);
	} else if (heat > 0.5) {
		return vec4(flame_color.rgb, 1.0);
	} else if (heat > 0.3) {
		return vec4(flame_color.rgb * 0.6, 0.9);
	}
	return vec4(0.0);
}

// Weg entlang eines abgerundeten Rechtecks um das Papier (Ecken als Viertelkreise mit Radius r):
// liefert die Strecke vom oberen linken Ende der Oberkante im Uhrzeigersinn
float perimeter_pos(vec2 q, vec2 off, vec2 inner_min, vec2 inner_max, float r) {
	float w = inner_max.x - inner_min.x;
	float h = inner_max.y - inner_min.y;
	float quarter = r * 1.5707963;
	if (off.y < 0.0 && off.x == 0.0) {
		return q.x - inner_min.x;
	} else if (off.x > 0.0 && off.y < 0.0) {
		return w + r * atan(off.x, -off.y);
	} else if (off.x > 0.0 && off.y == 0.0) {
		return w + quarter + q.y - inner_min.y;
	} else if (off.x > 0.0 && off.y > 0.0) {
		return w + h + quarter + r * atan(off.y, off.x);
	} else if (off.y > 0.0 && off.x == 0.0) {
		return w + h + 2.0 * quarter + inner_max.x - q.x;
	} else if (off.x < 0.0 && off.y > 0.0) {
		return 2.0 * w + h + 2.0 * quarter + r * atan(-off.x, off.y);
	} else if (off.x < 0.0 && off.y == 0.0) {
		return 2.0 * w + h + 3.0 * quarter + inner_max.y - q.y;
	}
	return 2.0 * w + 2.0 * h + 3.0 * quarter + r * atan(-off.y, -off.x);
}

// Schild: Wasser, das in ruhigen Wellen um die Karte fließt. Die Wellen entspringen unten in der Mitte, laufen auf
// beiden Seiten gespiegelt nach oben und treffen sich oben in der Mitte. Oben auf jeder Welle heller Schaum,
// darunter ruhiges Wasser mit einem feinen Strömungsstreifen.
// magic: dazu einzelne Lichtfunken im Wasser (Magie-Schild)
vec4 waves(vec2 sp, vec2 q, vec2 off, float d, float e, vec2 inner_min, vec2 inner_max, float t, bool magic) {
	// fester Eckradius für die Weglänge, damit die Wellen in den Ecken nicht mit dem Abstand verzerren
	const float corner_r = 8.0;
	float w = inner_max.x - inner_min.x;
	float h = inner_max.y - inner_min.y;
	float quarter = corner_r * 1.5707963;
	float total = 2.0 * (w + h) + 4.0 * quarter;
	float s = perimeter_pos(q, off, inner_min, inner_max, corner_r);
	// Strecke von der Mitte der Unterkante aus, auf beiden Seiten gleich (0 unten Mitte, total / 2 oben Mitte)
	float bottom_mid = w + h + 2.0 * quarter + w * 0.5;
	float u = abs(s - bottom_mid);
	u = min(u, total - u);
	// gleichmäßige, flache Wellenbögen (Wellenlänge 36 Pixel), die langsam nach oben wandern; eine lange,
	// sanfte Dünung hebt und senkt sie kaum merklich
	float phase = fract(u / 36.0 - t * 0.35 + seed * 0.1);
	float arc = sin(phase * 3.1415927);
	float swell = sin(u * 0.03 - t * 0.4 + seed);
	float height = 3.5 + arc * arc * 3.5 + swell * 0.6;
	if (e > height) {
		return vec4(0.0);
	}
	vec3 water = flame_color.rgb;
	vec3 deep = flame_color.rgb * 0.5;
	vec3 foam = mix(flame_color.rgb, vec3(1.0), 0.7);
	// Schaumkrone: die oberste Pixelreihe jeder Welle, auf den Kämmen etwas dicker
	if (e > height - 1.5 - arc * 0.8) {
		return vec4(foam, 1.0);
	}
	// zur Karte hin dunkler, dazu ein heller Streifen im Wellenkörper
	vec3 col = mix(water, deep, clamp(1.0 - e / height, 0.0, 1.0) * 0.6);
	if (abs(e - height * 0.55) < 1.0 && arc > 0.5) {
		col = mix(water, foam, 0.4);
	}
	if (magic && hash(vec2(floor(sp.x / 2.0) + floor(sp.y / 2.0) * 37.0, floor(t * 1.5))) > 0.98) {
		col = vec3(1.0);
	}
	return vec4(col, 0.9);
}

// Teilchen, die sich senkrecht bewegen (Buff: nach oben, Debuff: nach unten), ohne Saum am Papier
vec4 drift(vec2 sp, float e, float dir_y, float t, bool up) {
	// Buff und Debuff etwa so groß wie die Wellen beim Schild
	float len = up ? reach(dir_y, 16.0, 9.0, 4.0) : reach(dir_y, 4.0, 9.0, 16.0);
	float fall = e / len;
	if (fall >= 1.0) {
		return vec4(0.0);
	}
	float n;
	if (up) {
		// kleine, runde Funken, die zügig aufsteigen
		n = noise(vec2(sp.x / 4.0, sp.y / 4.5 + t * 2.6));
	} else {
		// längliche Tropfen, die langsamer herabsinken
		n = noise(vec2(sp.x / 4.0, sp.y / 9.0 - t * 1.5));
	}
	// am Papier dichter, nach außen werden es weniger
	float threshold = 0.72 + fall * 0.2;
	if (n > threshold + 0.08) {
		return vec4(mix(flame_color.rgb, vec3(1.0), up ? 0.45 : 0.15), 1.0);
	} else if (n > threshold) {
		return vec4(flame_color.rgb * (up ? 1.0 : 0.7), 0.9);
	}
	return vec4(0.0);
}

void fragment() {
	vec2 p = (floor(UV * rect_size / pixel) + 0.5) * pixel;
	vec2 inner_min = pad.xy + vec2(overlap);
	vec2 inner_max = rect_size - pad.zw - vec2(overlap);
	vec2 q = clamp(p, inner_min, inner_max);
	vec2 off = p - q;
	float d = length(off);
	if (d <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		float dir_y = off.y / d;
		// Abstand zur Papierkante, der Überlapp gehört noch zum Rand
		float e = max(d - overlap, 0.0);
		float t = TIME * speed;
		vec2 sp = p + vec2(seed * 3.0, seed * 5.0);
		if (mode == 1) {
			COLOR = waves(sp, q, off, d, e, inner_min, inner_max, t, variant == 1);
		} else if (mode == 2) {
			COLOR = drift(sp, e, dir_y, t, true);
		} else if (mode == 3) {
			COLOR = drift(sp, e, dir_y, t, false);
		} else {
			COLOR = flames(sp, e, dir_y, t);
		}
	}
}
