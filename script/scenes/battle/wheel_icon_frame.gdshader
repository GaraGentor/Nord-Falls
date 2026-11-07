shader_type canvas_item;

// Pixeliger Ring um ein Monster-Icon auf dem Initiativkreis. Wer am Zug ist, pulsiert deutlich.

uniform vec2 rect_size = vec2(50.0);
uniform float pixel_size = 2.0;
uniform float line_width = 4.0;
uniform vec4 frame_color : source_color = vec4(1.0);
uniform vec4 pulse_color : source_color = vec4(1.0);
// 0 = nicht am Zug, 1 = am Zug
uniform float active_amount = 0.0;
uniform float pulse_speed = 2.8;

void fragment() {
	vec2 cell = floor(UV * rect_size / pixel_size);
	vec2 p = (cell + 0.5) * pixel_size - rect_size * 0.5;
	float r = length(p);
	float outer = min(rect_size.x, rect_size.y) * 0.5;
	float dist = abs(r - (outer - line_width * 0.5));
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed + atan(p.y, p.x));
	float glow = active_amount * mix(0.35, 1.0, pulse);
	vec3 rgb = floor(mix(frame_color.rgb, pulse_color.rgb, glow) * 8.0 + 0.5) / 8.0;
	COLOR = vec4(rgb, step(dist, line_width * 0.5));
}
