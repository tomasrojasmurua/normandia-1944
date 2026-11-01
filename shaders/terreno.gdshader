shader_type spatial;
// Suelo de la playa: mezcla arena mojada (cerca del mar), arena seca,
// una franja de guijarros y pasto de duna detrás del búnker. Los bordes
// entre zonas son irregulares (ruido) para que no se vean líneas rectas.
// El mar está hacia +Z; el búnker hacia -Z.
render_mode vertex_lighting, specular_disabled;

uniform sampler2D arena_mojada : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D arena_seca : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D guijarros : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D pasto : source_color, filter_nearest_mipmap, repeat_enable;
uniform float metros_por_textura = 2.0;   // 64 px cada 2 m = 32 px por metro
uniform float z_orilla = 10.0;            // donde empieza el agua
uniform float z_mojada = 1.0;             // de aquí hacia el mar, arena mojada
uniform vec2 franja_guijarros = vec2(-31.0, -26.0);
uniform float z_pasto = -47.0;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float ruido(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz / metros_por_textura;
	float n = ruido(wpos.xz * 0.25) * 0.65 + ruido(wpos.xz * 1.1) * 0.35;   // 0..1
	float z = wpos.z + (n - 0.5) * 5.0;
	vec3 mojada = texture(arena_mojada, uv).rgb;
	vec3 seca = texture(arena_seca, uv * 0.9 + 0.37).rgb;
	vec3 piedras = texture(guijarros, uv).rgb;
	vec3 hierba = texture(pasto, uv * 0.8).rgb;
	vec3 c = seca;
	c = mix(c, mojada, smoothstep(z_mojada - 1.0, z_mojada + 2.0, z));
	// Más oscuro justo en la orilla (arena empapada)
	c *= 1.0 - 0.25 * smoothstep(z_orilla - 4.0, z_orilla, wpos.z + (n - 0.5) * 2.0);
	float g = smoothstep(franja_guijarros.x - 1.0, franja_guijarros.x + 1.0, z)
		* (1.0 - smoothstep(franja_guijarros.y - 1.0, franja_guijarros.y + 1.0, z));
	c = mix(c, piedras, g);
	c = mix(c, hierba, 1.0 - smoothstep(z_pasto - 2.0, z_pasto + 2.0, z));
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
