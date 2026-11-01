shader_type spatial;
// Mar del Canal: dos capas de la textura de agua moviéndose en distinto
// sentido, y una franja de espuma en la orilla que va y viene.
render_mode vertex_lighting, specular_disabled;

uniform sampler2D agua : source_color, filter_nearest_mipmap, repeat_enable;
uniform float metros_por_textura = 6.0;
uniform float z_orilla = 10.0;
uniform vec4 espuma : source_color = vec4(0.82, 0.84, 0.8, 1.0);

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
	vec3 a = texture(agua, uv + vec2(TIME * 0.010, -TIME * 0.025)).rgb;
	vec3 b = texture(agua, uv * 0.7 + vec2(-TIME * 0.015, -TIME * 0.012) + 0.5).rgb;
	vec3 c = mix(a, b, 0.5);
	// Espuma de la orilla: ancho que respira con las olas
	float ola = 0.5 + 0.4 * sin(TIME * 0.9 + wpos.x * 0.07) + ruido(vec2(wpos.x * 0.4, TIME * 0.3)) * 0.6;
	float d = wpos.z - z_orilla;
	float f = 1.0 - smoothstep(ola - 0.3, ola, d);
	f *= smoothstep(0.3, 0.55, ruido(wpos.xz * 2.0 + vec2(0.0, TIME * 0.5)));
	// segunda línea de espuma más afuera, más tenue
	float f2 = (1.0 - smoothstep(0.0, 0.5, abs(d - ola - 2.5))) * smoothstep(0.5, 0.75, ruido(wpos.xz * 1.3 - vec2(TIME * 0.2, 0.0)));
	c = mix(c, espuma.rgb, max(f * 0.75, f2 * 0.4));
	// Aclarar el agua poco profunda cerca de la playa
	c = mix(c * 1.25, c, smoothstep(0.0, 12.0, d));
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
