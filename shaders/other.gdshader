shader_type spatial;

render_mode blend_mix, depth_draw_opaque, cull_back;

uniform float shader_lerp : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float light_mode : hint_range(-1.0, 1.0, 0.01) = 0.0;
/* Shader 1 */
uniform sampler2D ax;
uniform vec2 uv_scale = vec2(4.0);

/* Shader 2 */
uniform vec4 albedo : source_color;

uniform float smstep : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float stepv : hint_range(0.0, 1.0, 0.01) = 0.25;

uniform float max_l : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float normal_multiplier : hint_range(0.0, 1.0, 0.01);
uniform sampler2D normal : hint_normal;

uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset;


void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}


void fragment() {

	// Resultado shader 1
	vec2 screen_uv = SCREEN_UV - 0.5;
	screen_uv.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	screen_uv *= uv_scale;
	screen_uv += 0.5;

	vec3 shader1_color = texture(ax, screen_uv).rgb;


	// Resultado shader 2
	vec3 shader2_color = albedo.rgb;


	// Mezcla de colores
	ALBEDO = mix(shader2_color * clamp(light_mode + 1.0,0.1,1.0), shader1_color, shader_lerp);


	// Mezcla de normales
	vec3 shader1_normal = vec3(0.5, 0.5, 1.0);
	vec3 shader2_normal = texture(normal, UV).rgb;

	NORMAL_MAP = mix(shader2_normal , shader1_normal, shader_lerp);
	NORMAL_MAP_DEPTH = normal_multiplier;
}
void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);

	float l = min(
		max_l,
		smoothstep(stepv - smstep, stepv + smstep, ndotl)
	);

	vec3 shaded = vec3(l) * ALBEDO * LIGHT_COLOR * ATTENUATION;

	float shade_amount = clamp(-light_mode + 1.0, -1.0, 1.0);

	DIFFUSE_LIGHT = mix(ALBEDO, shaded, shade_amount);
}










//hehe