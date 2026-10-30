shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// Wolkenfeld unter der Klippe der Zitadellenkarte: weiche Ballen aus Rauschen, oben hell, Ränder blau verschattet,
// treibt langsam.

uniform float seed = 0.0;

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

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	vec2 q = UV * 4.0 + vec2(seed, seed * 1.7) + vec2(TIME * 0.02, 0.0);
	float puff = noise(q) * 0.55 + noise(q * 2.1) * 0.3 + noise(q * 4.3) * 0.15;
	float fall = 1.0 - smoothstep(0.35, 1.0, length(c));
	float a = smoothstep(0.35, 0.65, puff * fall + fall * 0.35);
	ALBEDO = mix(vec3(0.62, 0.72, 0.85), vec3(0.97, 0.98, 1.0), smoothstep(0.4, 0.8, puff));
	ALPHA = a * 0.9;
}
