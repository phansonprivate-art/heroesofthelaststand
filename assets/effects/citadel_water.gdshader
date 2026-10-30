shader_type spatial;
render_mode cull_disabled;
// Fluss der Zitadellenkarte: Band entlang des Flusslaufs (UV.x quer 0..1, UV.y längs in Metern).
// Strömung, Wellenglanz und helle Uferkanten.

uniform vec3 deep_color : source_color = vec3(0.05, 0.22, 0.30);
uniform vec3 shallow_color : source_color = vec3(0.12, 0.40, 0.46);
uniform float flow_speed = 0.6;

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
	float across = abs(UV.x - 0.5) * 2.0;                 // 0 Mitte, 1 Ufer
	vec2 q = vec2(UV.x * 3.0, UV.y * 0.35 - TIME * flow_speed);
	float w = noise(q * 2.0) * 0.6 + noise(q * 5.0 + 3.1) * 0.4;
	vec3 col = mix(deep_color, shallow_color, smoothstep(0.35, 1.0, across) * 0.8 + w * 0.25);
	float sparkle = smoothstep(0.9, 0.98, noise(vec2(UV.x * 9.0, UV.y * 1.3 - TIME * flow_speed * 1.6)));
	float foam = smoothstep(0.9, 1.0, across + w * 0.08);
	ALBEDO = mix(col, vec3(0.85, 0.93, 0.95), foam * 0.7);
	EMISSION = vec3(0.6, 0.85, 1.0) * sparkle * 0.12;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
