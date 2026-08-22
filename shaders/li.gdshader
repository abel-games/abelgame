
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float smstep : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float stepv : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform vec4 albedo : source_color;

uniform float max_l : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float normal_multiplier : hint_range(0.0, 1.0, 0.01);
uniform sampler2D normal : hint_normal;

uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset;
void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	ALBEDO = albedo.rgb;
	NORMAL_MAP = texture(normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_multiplier;
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float l = min(max_l, smoothstep(stepv - smstep, stepv + smstep, ndotl));
	DIFFUSE_LIGHT = vec3(l) * ALBEDO * LIGHT_COLOR * ATTENUATION;
	
}













//hehe