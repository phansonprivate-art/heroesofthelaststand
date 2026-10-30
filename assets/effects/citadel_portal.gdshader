shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Wirbel im Portalbogen der Zitadellenkarte: drehende Spiralarme, heller Kern, weicher Rand.

uniform vec3 tint : source_color = vec3(0.65, 0.3, 1.0);
uniform float spin = 2.2;

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float a = atan(c.y, c.x);
	float arms = sin(a * 3.0 + r * 10.0 - TIME * spin) * 0.5 + 0.5;
	float fine = sin(a * 7.0 - r * 16.0 + TIME * spin * 1.6) * 0.5 + 0.5;
	float mask = 1.0 - smoothstep(0.82, 1.0, r);
	float core = 1.0 - smoothstep(0.0, 0.55, r);
	vec3 col = tint * (0.3 + 0.55 * arms + 0.2 * fine) + vec3(1.0, 0.85, 1.0) * core * 0.6;
	ALBEDO = col * mask;
	ALPHA = mask * (0.5 + 0.5 * arms);
}
