shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(0.4, 0.9, 1.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 8.0) = 1.5;
uniform float glow_speed : hint_range(0.0, 10.0) = 2.0;

void fragment() {
	vec4 base = COLOR; // Vertex-Farbe, die das Script übergibt (color / color2)

	float along = UV.x;   // Position entlang der Linie: 0 = Start, 1 = Ende
	float across = UV.y;  // Position quer zur Linienbreite: 0 = Rand, 1 = Rand

	// Wandernder Licht-Puls, der entlang der Linie läuft
	float pulse = sin(along * 14.0 - TIME * glow_speed * 4.0) * 0.5 + 0.5;
	pulse = pow(pulse, 4.0); // scharfe, leuchtende Spitzen statt weichem Sinus

	// Glanz nimmt zur Mitte der Linienbreite hin zu (rundes Glühen statt harter Kante)
	float edge_fade = 1.0 - abs(across - 0.5) * 2.0;
	edge_fade = clamp(edge_fade, 0.0, 1.0);
	edge_fade = pow(edge_fade, 1.5);

	vec3 glow = glow_color.rgb * pulse * glow_intensity * edge_fade;

	COLOR = vec4(base.rgb + glow, base.a);
}
