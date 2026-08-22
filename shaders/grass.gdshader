shader_type spatial;

uniform vec3 grass_color : source_color = vec3(0.0,0.5,0.0);
uniform sampler2D grass_normal : hint_normal;
uniform vec2 uv_scale = vec2(1.0,1.0);

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	ALBEDO = grass_color;
	NORMAL_MAP = texture(grass_normal, UV * uv_scale).rgb;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
