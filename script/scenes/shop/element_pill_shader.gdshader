shader_type canvas_item;

// Bewusst ohne Bildschirm-Textur: Godot kopiert den Bildschirm nur einmal pro Frame, ab dem zweiten Trank
// läge darin noch der Wellen-Hintergrund statt der Karte und würde auf die Trankfarbe addiert.

uniform bool light_effect = false;
uniform bool border_exclusion_effect = false;
uniform bool wave_fix_on_border = false;

uniform vec4 water_color: source_color = vec4(1, 0, 0, 1);
uniform float water_wave_speed : hint_range(-100, 100, 0.01) = 2;
uniform float water_wave_ci: hint_range(0, 2, 0.01) = 0.05;
uniform float water_back_lightness: hint_range(0, 1, 0.01) = 0.8;
uniform vec4 ball_color: source_color = vec4(vec3(1), 1);
uniform float ball_border_ci : hint_range(0, 50, 1) = 5;
uniform float ball_light_speed : hint_range(-100, 100, 0.01) = 2;
uniform float wave_num : hint_range(0, 8, 1) = 2;

uniform float ini_Time = 0.;

uniform float height : hint_range(0, 1, 0.01) = 0.5;

uniform bool vibration_effect = false;
uniform float vibration_effect_timelength: hint_range(0, 10, 0.01) = 4;
uniform float vibration_speed : hint_range(-100, 100, 0.01) = 4;
uniform float vibration_magnitude : hint_range(0, 10, 0.01) = 0.25;
uniform float vibration_wave_ci: hint_range(0, 2, 0.01) = 0.05;

vec4 ontop(vec4 base, vec4 blend){
	return mix(base,blend,blend.a);
}

vec4 exclusion(vec4 base, vec4 blend){
	return base + blend - 2.0 * base * blend;
}

float easeOutExpo(float x){
	return x == 1. ? 1. : 1. - pow(2., -10. * x);
}//from https://easings.net/zh-cn#easeOutBounce

void fragment() {

	float NTIME = vibration_effect ? TIME - ini_Time : TIME;

	vec2 uv = (UV - 0.5)*2.;
	vec2 suv = UV*0.5 - 0.5;

	float a = wave_fix_on_border ? 2. : 1.;
	float b = wave_fix_on_border ? 1. : 0.5;

	if (height == 1. || height == 0.) {

		COLOR = vec4(water_color.rgb,height);
	} else {

		float plane_inclined_ratio = 0.1;
		float fix_x = sqrt(1.-pow(suv.y,2));
		float dH = sin(mod((UV.x*fix_x + TIME*water_wave_speed)*PI, TAU))*plane_inclined_ratio;
		float dHo = sin(mod((UV.x*fix_x + -TIME*water_wave_speed)*PI + PI, TAU))*plane_inclined_ratio;

		float t = easeOutExpo(min(NTIME, vibration_effect_timelength)/vibration_effect_timelength);
		float H = vibration_effect ? mix(height - uv.x*cos(NTIME*vibration_speed), height, t) : height;//*vibration_magnitude
		float CI = vibration_effect ? mix((water_wave_ci + vibration_wave_ci)*vibration_magnitude, water_wave_ci, t) : water_wave_ci;

		if (sin((cos(suv.x*PI*a) + NTIME*water_wave_speed)*wave_num)*CI + (1. - H) > UV.y + dHo) {

			COLOR = vec4(0.);
		} else {

			COLOR = vec4(water_color*water_back_lightness);
		}

		if (sin((cos(suv.x*PI*a + PI*b) + NTIME*water_wave_speed)*wave_num)*CI + (1. - H) < UV.y + dH) {

			COLOR = vec4(water_color);
		}
	}

	float L = 0.;

	if (light_effect) {L = cos(distance(UV, sin(suv*suv) + NTIME*ball_light_speed))*0.25;}

	float dist = distance(UV, vec2(0.5,0.5));
	COLOR = border_exclusion_effect ? exclusion(COLOR, vec4(vec3(1.),pow(dist*2.,ball_border_ci) + L)*ball_color) : ontop(COLOR, vec4(vec3(1.),pow(dist*2.,ball_border_ci) + L)*ball_color);
	// runder, geglätteter Rand
	COLOR.a *= 1. - smoothstep(0.5 - fwidth(dist), 0.5, dist);
}
