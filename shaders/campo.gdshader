shader_type spatial;
// Suelo de los campos de Normandía (misión 2, el planeador): potreros de
// pasto entre los setos, cada uno de un tono un poco distinto (unos recién
// cortados, otros de heno alto), con manchas de tierra pisada y barro.
// Luz por píxel (sin vertex_lighting): así las bengalas y los fuegos iluminan
// el suelo en un círculo, no solo en las esquinas de la malla.
render_mode specular_disabled;

uniform sampler2D pasto : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D tierra : source_color, filter_nearest_mipmap, repeat_enable;
uniform float metros_por_textura = 2.2;
uniform vec2 potrero = vec2(34.0, 32.0);    // tamaño aproximado de cada campo

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
	vec3 p = texture(pasto, uv).rgb;
	vec3 t = texture(tierra, uv * 0.9).rgb * vec3(0.72, 0.6, 0.45);
	// Tono por potrero (verde más o menos amarillo)
	float campo = hash(floor(wpos.xz / potrero));
	p *= mix(vec3(0.82, 0.9, 0.7), vec3(1.0, 0.95, 0.72), campo);
	// Manchas de tierra pisada y barro
	float n = ruido(wpos.xz * 0.13) * 0.65 + ruido(wpos.xz * 0.5) * 0.35;
	float barro = smoothstep(0.66, 0.74, n);
	ALBEDO = mix(p, t, barro);
	ROUGHNESS = 1.0;
}
