shader_type spatial;
// Blockout-Boden: Steinplatten-Raster mit leichter Farbvariation, in Weltkoordinaten.

uniform vec3 base_color : source_color = vec3(0.30, 0.31, 0.34);
uniform vec3 line_color : source_color = vec3(0.17, 0.18, 0.20);
uniform float tile_size = 4.0;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = world_pos.xz / tile_size;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float line = 1.0 - smoothstep(0.0, 0.025, edge);
	vec3 c = base_color * (0.92 + hash(cell) * 0.16);
	ALBEDO = mix(c, line_color, line);
	ROUGHNESS = 0.92;
}
