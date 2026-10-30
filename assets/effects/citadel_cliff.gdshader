shader_type spatial;
// Felswand unter dem Plateau der Zitadellenkarte (schwebende Insel wie im Konzeptbild): waagerechte Gesteinsbänder,
// Risse, nach unten dunkler; oben ein grüner Grasüberhang.

varying vec3 world_pos;

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float along = world_pos.x * 0.7 + world_pos.z * 0.7;
	float y = world_pos.y;
	float band = noise(vec2(along * 0.15, y * 0.9)) * 0.6 + noise(vec2(along * 0.6, y * 2.5)) * 0.4;
	float crack = smoothstep(0.82, 0.9, noise(vec2(along * 1.4, y * 0.35)));
	vec3 col = mix(vec3(0.11, 0.105, 0.1), vec3(0.24, 0.23, 0.21), band) * (1.0 - crack * 0.6);
	col *= mix(0.45, 1.0, smoothstep(-30.0, -2.0, y));                          // nach unten dunkler
	float grass = smoothstep(-1.6, -0.3, y + (noise(vec2(along * 0.8, 0.0)) - 0.5) * 1.2);
	col = mix(col, vec3(0.08, 0.15, 0.04), grass);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
