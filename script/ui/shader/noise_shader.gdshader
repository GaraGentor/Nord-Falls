shader_type canvas_item;

uniform sampler2D noise_tex;
uniform float frequency : hint_range(0.1, 10.0) = 2.0;

void fragment() {
	vec4 noise_uv = texture(TEXTURE, UV + vec2(sin(TIME * 0.3), cos(TIME * 0.2)) * 0.7);
    COLOR = noise_uv;
}