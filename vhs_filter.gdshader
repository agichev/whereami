shader_type canvas_item;

// Базовая оптика линзы
uniform float lens_distortion : hint_range(0.0, 0.2) = 0.045;
uniform float chromatic_aberration : hint_range(0.0, 0.01) = 0.002;
uniform float vignette_intensity : hint_range(0.0, 0.5) = 0.22;
uniform float noise_amount : hint_range(0.0, 0.1) = 0.022;

// Затемнение экрана (0.0 = нормальная картинка, 1.0 = полная чернота)
uniform float black_fade : hint_range(0.0, 1.0) = 0.0;

// Реалистичный размыв при резких движениях камеры (Motion Blur)
uniform vec2 motion_blur_dir = vec2(0.0, 0.0);

// Размытие фокуса при зуме камеры (Focus blur)
uniform float focus_blur : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Легкая оптическая кривизна линзы
vec2 distort_lens(vec2 uv, float strength) {
	vec2 coord = (uv - 0.5) * 2.0;
	float r2 = dot(coord, coord);
	float distortion = 1.0 + strength * r2;
	float max_corner = 1.0 + strength * 2.0;
	vec2 result = (coord * distortion) / max_corner;
	return (result * 0.5) + 0.5;
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Оптическая дисторсия
	vec2 distorted_uv = distort_lens(uv, lens_distortion);
	distorted_uv = clamp(distorted_uv, vec2(0.001), vec2(0.999));

	// Базовая хроматическая аберрация по краям
	vec2 center_offset = distorted_uv - 0.5;
	float dist = length(center_offset);
	vec2 base_ca = center_offset * (dist * chromatic_aberration * 2.0);

	// 1. Расчет размытия: Motion Blur (направленный) + Focus Blur (радиальный расфокус)
	vec2 m_blur = motion_blur_dir;
	float f_blur = focus_blur * 0.018;

	vec3 col = vec3(0.0);

	// Если есть моушен блюр или расфокус зума - делаем качественный мульти-сэмплинг
	if (length(m_blur) > 0.0005 || f_blur > 0.0005) {
		const int SAMPLES = 7;
		vec3 accum = vec3(0.0);
		for (int i = 0; i < SAMPLES; i++) {
			float step_ratio = (float(i) / float(SAMPLES - 1)) - 0.5;
			// Направленное смещение моушен блюра
			vec2 offset = m_blur * step_ratio;
			
			// Круговой размыв фокуса объектива
			float angle = float(i) * 2.39996; // Golden ratio angle
			vec2 f_offset = vec2(cos(angle), sin(angle)) * (f_blur * abs(step_ratio) * 2.0);

			vec2 s_uv = clamp(distorted_uv + offset + f_offset, vec2(0.001), vec2(0.999));

			float s_r = texture(screen_texture, clamp(s_uv + base_ca, vec2(0.0), vec2(1.0))).r;
			float s_g = texture(screen_texture, s_uv).g;
			float s_b = texture(screen_texture, clamp(s_uv - base_ca, vec2(0.0), vec2(1.0))).b;
			accum += vec3(s_r, s_g, s_b);
		}
		col = accum / float(SAMPLES);
	} else {
		float r = texture(screen_texture, clamp(distorted_uv + base_ca, vec2(0.0), vec2(1.0))).r;
		float g = texture(screen_texture, distorted_uv).g;
		float b = texture(screen_texture, clamp(distorted_uv - base_ca, vec2(0.0), vec2(1.0))).b;
		col = vec3(r, g, b);
	}

	// Тонкое аналоговое смешивание цветности
	vec2 bleed_offset = vec2(0.0012, 0.0);
	float r_bleed = texture(screen_texture, clamp(distorted_uv + base_ca + bleed_offset, vec2(0.0), vec2(1.0))).r;
	float b_bleed = texture(screen_texture, clamp(distorted_uv - base_ca - bleed_offset, vec2(0.0), vec2(1.0))).b;
	col.r = mix(col.r, r_bleed, 0.18);
	col.b = mix(col.b, b_bleed, 0.18);

	// Базовое мягкое зерно
	float grain = (hash(distorted_uv + vec2(TIME * 0.2, -TIME * 0.3)) - 0.5) * noise_amount;
	col += grain;

	// Мягкая виньетка по краям
	float vignette = smoothstep(0.85, 0.4, dist);
	col *= mix(1.0, vignette, vignette_intensity);

	// Плавный фейд из черноты
	col = mix(col, vec3(0.0), clamp(black_fade, 0.0, 1.0));

	COLOR = vec4(col, 1.0);
}
