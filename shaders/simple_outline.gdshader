shader_type spatial;

render_mode unshaded, cull_front;

uniform float weight = 0.025;

uniform vec3 outline_color = vec3(0.0);

void vertex() {
	VERTEX += NORMAL * weight * COLOR.r;
}

void fragment() {
	ALBEDO = outline_color;
}