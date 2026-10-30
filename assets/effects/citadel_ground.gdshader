shader_type spatial;
// Boden der Zitadelle des Lichts nach dem Konzeptbild (Issue #4): Wiese und dunkler Waldboden (Waldraster aus dem
// Bild), gepflasterte Straßen mit Steinkante, Erdpfade, Flussufer, Abgrund mit Glutrissen und Lavabecken, Krater
// des Dschungelbosses, gefliester Zitadellenhof, Erd-Lichtungen. Alles analytisch aus dem Grundriss, gesetzt von
// scripts/maps/citadel_map.gd. Farbwerte sind LINEAR (aus den sRGB-Farben des Bildes umgerechnet: sRGB 0,37 ≈ linear 0,11).

const int MAX_SEGS = 128;
uniform vec4 segs[MAX_SEGS];               // Strecken: a.xy, b.xy (Welt-x/z)
uniform vec2 seg_info[MAX_SEGS];           // x = halbe Breite, y = Art (0 Pflaster, 1 Erdpfad)
uniform int seg_count = 0;
uniform vec2 river_points[24];
uniform int river_count = 0;
uniform float river_width = 5.0;
uniform vec2 plaza[8];                     // Zitadellenhof: konvexes Vieleck
uniform int plaza_count = 0;
uniform float abyss_x = -53.0;
uniform vec3 pit = vec3(0.0, 0.0, 7.5);    // Krater: Mitte x/z, Radius
uniform vec4 clearings[24];                // xy = Mitte, z = Radius
uniform int clearing_count = 0;
uniform vec3 lava[4];                      // xy = Mitte, z = Radius
uniform int lava_count = 0;
uniform sampler2D forest_map : filter_linear, repeat_disable;
uniform vec4 forest_rect = vec4(-83.6, -43.7, 154.9, 84.5);   // Weltbereich des Waldrasters: x, z, Breite, Tiefe

varying vec3 world_pos;

// Zufall ohne sin(): bleibt auch bei großen Koordinaten gleichmäßig (sin-Variante erzeugt eckige Flecken)
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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

// Voronoi: x = Abstand zur nächsten Zelle, y = Abstand zur Kante (für Fugen), z = Zellzufall
vec3 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 17.0)) * 0.8 + 0.1;
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; id = hash(i + g + 5.0); }
			else if (d < d2) { d2 = d; }
		}
	}
	return vec3(d1, d2 - d1, id);
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
	return length(a + ab * t - p);
}

float river_dist(vec2 p) {
	float d = 1e5;
	for (int i = 0; i < river_count - 1; i++) { d = min(d, seg_dist(p, river_points[i], river_points[i + 1])); }
	return d;
}

// Abstand zum konvexen Hof (negativ innen). Die Punkte kommen so sortiert, dass (e.y, -e.x) nach außen zeigt.
float plaza_dist(vec2 p) {
	float d = -1e5;
	for (int i = 0; i < plaza_count; i++) {
		vec2 a = plaza[i];
		vec2 e = normalize(plaza[(i + 1) % plaza_count] - a);
		d = max(d, dot(p - a, vec2(e.y, -e.x)));
	}
	return d;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n = fbm(p * 0.08);
	float fine = noise(p * 1.7);
	// Wiese, unter dem Wald dunkler Waldboden (Raster aus dem Konzeptbild, Ränder verwackelt)
	vec2 fuv = (p - forest_rect.xy) / forest_rect.zw + (vec2(noise(p * 0.35), noise(p * 0.35 + 7.0)) - 0.5) * 0.012;
	float forest = texture(forest_map, fuv).r;
	vec3 grass = mix(vec3(0.11, 0.19, 0.05), vec3(0.2, 0.25, 0.08), smoothstep(0.3, 0.75, n));
	grass *= 0.85 + 0.25 * fine;
	vec3 floor_col = mix(vec3(0.03, 0.06, 0.025), vec3(0.07, 0.1, 0.04), n) * (0.8 + 0.35 * fine);
	vec3 ground = mix(grass, floor_col, smoothstep(0.2, 0.7, forest));
	// Abgrund: dunkles Vulkangestein, glühende Risse
	float abyss = smoothstep(abyss_x + 5.0, abyss_x - 5.0, p.x + (n - 0.5) * 12.0);
	vec3 crack_cells = cells(p * 0.22);
	float crack = (1.0 - smoothstep(0.0, 0.025, crack_cells.y)) * smoothstep(0.52, 0.68, noise(p * 0.15));
	vec3 rock = mix(vec3(0.03, 0.012, 0.012), vec3(0.09, 0.025, 0.022), fbm(p * 0.6)) * (0.8 + 0.3 * fine);
	ground = mix(ground, rock, abyss);
	vec3 emit = vec3(1.0, 0.3, 0.07) * crack * abyss * (0.6 + 0.4 * noise(p * 0.3 + TIME * 0.1)) * smoothstep(0.35, 0.7, n + 0.2);
	// Lavabecken mit dunkler, langsam treibender Kruste
	float lv = 0.0;
	for (int i = 0; i < lava_count; i++) {
		lv = max(lv, 1.0 - smoothstep(lava[i].z * 0.55, lava[i].z, length(p - lava[i].xy) + (n - 0.5) * 3.0));
	}
	vec3 molten = mix(vec3(1.0, 0.12, 0.02), vec3(1.0, 0.3, 0.04), noise(p * 0.6 + TIME * 0.15));
	float crust = smoothstep(0.42, 0.6, noise(p * 0.9 + vec2(TIME * 0.05, 0.0)));
	ground = mix(ground, mix(vec3(0.35, 0.05, 0.01), vec3(0.08, 0.035, 0.03), crust), lv);   // Farbe kommt aus dem Leuchten
	emit += molten * lv * (1.0 - crust) * 0.6;
	// Erd-Lichtungen (Lager, Ruinen, Bauten)
	float dirt = 0.0;
	for (int i = 0; i < clearing_count; i++) {
		dirt = max(dirt, 1.0 - smoothstep(clearings[i].z * 0.6, clearings[i].z, length(p - clearings[i].xy) + (n - 0.5) * 3.0));
	}
	ground = mix(ground, mix(vec3(0.13, 0.09, 0.05), vec3(0.09, 0.065, 0.04), fine) * (1.0 - 0.4 * abyss), dirt * 0.85);
	// Krater des Dschungelbosses: dunkler Grund, Gesteinsschichten zum Rand hin, heller Felsrand
	float pr = length(p - pit.xy) / pit.z + (n - 0.5) * 0.08;
	float ang = atan(p.y - pit.y, p.x - pit.x);
	float strata = noise(vec2(ang * 6.0, pr * 9.0));
	vec3 pit_col = mix(vec3(0.008, 0.006, 0.01), vec3(0.08, 0.065, 0.06) * (0.6 + 0.5 * strata), smoothstep(0.6, 0.99, pr));
	pit_col = mix(pit_col, vec3(0.16, 0.14, 0.12) * (0.8 + 0.3 * fine), smoothstep(0.9, 1.0, pr) * (1.0 - smoothstep(1.05, 1.18, pr)));
	ground = mix(ground, pit_col, 1.0 - smoothstep(1.12, 1.25, pr));
	// Flussufer: feuchte dunkle Erde
	float rd = river_dist(p);
	float bank = 1.0 - smoothstep(river_width * 0.5, river_width * 0.5 + 2.0, rd + (n - 0.5) * 1.5);
	ground = mix(ground, vec3(0.07, 0.055, 0.035) * (0.85 + 0.3 * fine), bank * 0.9);
	// Straßen und Pfade
	float stone_edge = 1e5;
	float trail_edge = 1e5;
	for (int i = 0; i < seg_count; i++) {
		float d = seg_dist(p, segs[i].xy, segs[i].zw) - seg_info[i].x;
		if (seg_info[i].y < 0.5) { stone_edge = min(stone_edge, d); } else { trail_edge = min(trail_edge, d); }
	}
	float fray = (n - 0.5) * 1.2 + (fine - 0.5) * 0.4;
	float trail = 1.0 - smoothstep(-0.4, 0.3, trail_edge + fray);
	ground = mix(ground, mix(vec3(0.14, 0.095, 0.05), vec3(0.1, 0.07, 0.04), fine), trail * 0.9);
	float road = 1.0 - smoothstep(-0.15, 0.1, stone_edge + fray * 0.35);
	float shoulder = (1.0 - smoothstep(0.0, 1.4, stone_edge + fray)) * (1.0 - road);
	ground = mix(ground, vec3(0.12, 0.09, 0.055) * (0.8 + 0.3 * fine), shoulder * 0.7);
	vec3 flag = cells(p * 1.15);
	float joint = smoothstep(0.02, 0.09, flag.y);
	vec3 stone = mix(vec3(0.09, 0.088, 0.083), vec3(0.17, 0.165, 0.155), flag.z) * mix(0.45, 1.0, joint) * (0.9 + 0.15 * fine);
	float curb = smoothstep(-0.9, -0.5, stone_edge) * (1.0 - smoothstep(-0.25, 0.0, stone_edge));
	stone = mix(stone, vec3(0.24, 0.235, 0.22) * (0.85 + 0.2 * fine), curb * 0.6);   // helle Steinkante
	stone = mix(stone, stone * vec3(0.55, 0.45, 0.55), abyss);
	ground = mix(ground, stone, road);
	emit *= 1.0 - max(road, trail);
	// Zitadellenhof: helle Steinfliesen im Raster
	float od = plaza_count > 2 ? plaza_dist(p) : 1e5;
	float plaza_mask = 1.0 - smoothstep(-0.4, 0.2, od);
	vec2 tile = abs(fract(p * 0.5) - 0.5);
	float tile_joint = smoothstep(0.44, 0.48, max(tile.x, tile.y));
	vec3 tiles = mix(vec3(0.13, 0.135, 0.13), vec3(0.2, 0.205, 0.195), hash(floor(p * 0.5))) * (1.0 - 0.45 * tile_joint);
	ground = mix(ground, tiles, plaza_mask);
	ALBEDO = ground;
	ROUGHNESS = mix(0.95, 0.75, road);
	EMISSION = emit * 1.5;
}
