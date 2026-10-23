shader_type canvas_item;

uniform vec4 fog_color : source_color = vec4(0.03, 0.03, 0.05, 1.0);
uniform float inner_radius : hint_range(0.0, 1.0) = 0.20;
uniform float outer_radius : hint_range(0.0, 1.5) = 0.58;
uniform float max_density : hint_range(0.0, 1.0) = 0.98;
uniform float fog_scale : hint_range(0.5, 10.0) = 3.5;
uniform float noise_strength : hint_range(0.0, 0.5) = 0.16;
uniform float drift_speed : hint_range(0.0, 0.2) = 0.04;

vec2 hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(dot(hash(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
			dot(hash(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
		mix(dot(hash(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
			dot(hash(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	for (int i = 0; i < 3; i++) {
		v += a * noise(p);
		p = rot * p * 2.0;
		a *= 0.5;
	}
	return v * 0.5 + 0.5;
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 uv = UV - vec2(0.5);
	uv.x *= aspect;
	float dist = length(uv);

	vec2 motion1 = vec2(TIME * drift_speed, TIME * (drift_speed * 0.5));
	vec2 motion2 = vec2(-TIME * (drift_speed * 0.7), TIME * (drift_speed * 0.8));

	float n1 = fbm(uv * fog_scale + motion1);
	float n2 = fbm(uv * (fog_scale * 1.6) + motion2);
	float combined_noise = mix(n1, n2, 0.4);

	float noisy_dist = dist + (combined_noise - 0.5) * noise_strength;
	float base_mask = smoothstep(inner_radius, outer_radius, noisy_dist);

	float mist_density = mix(0.85, 1.0, combined_noise);
	float alpha = clamp(base_mask * mist_density * max_density, 0.0, max_density);

	COLOR = vec4(fog_color.rgb, alpha);
}
