shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;
// Billboard-Lebensbalken über Einheiten. Ein Material für alle; der Füllstand ist ein Instanz-Parameter.

instance uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(0.9, 0.25, 0.22, 1.0);
uniform vec4 back_color : source_color = vec4(0.05, 0.05, 0.07, 0.85);

void vertex() {
	// Zur Kamera ausrichten, Größe aus dem Mesh beibehalten
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV;
	float border = step(uv.x, 0.02) + step(0.98, uv.x) + step(uv.y, 0.12) + step(0.88, uv.y);
	vec4 c = uv.x < fill ? fill_color : back_color;
	c.rgb = mix(c.rgb, vec3(0.0), clamp(border, 0.0, 1.0) * 0.8);
	ALBEDO = c.rgb;
	ALPHA = max(c.a, clamp(border, 0.0, 1.0));
}
