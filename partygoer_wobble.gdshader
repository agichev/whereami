shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform float walk_speed : hint_range(0.0, 15.0) = 3.0;
uniform float arm_swing_amount : hint_range(0.0, 2.0) = 0.6;
uniform float is_walking : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// В локальных координатах сетки Object_2 (до вращения Sketchfab_model):
	// X: ось плеч (лево-право) от -0.035 до +0.029
	// Y: ось груди / переда-спины
	// Z: вертикальная ось тела от -0.036 (низ подола) до +0.056 (голова)
	float x = VERTEX.x;
	float z = VERTEX.z;
	
	// Руки: находятся по бокам (|x| > 0.015) и свисают от плеч вниз (z между -0.025 и +0.025)
	float arm_weight = 0.0;
	if (abs(x) > 0.014 && z < 0.028 && z > -0.030) {
		float x_dist = clamp((abs(x) - 0.014) / 0.015, 0.0, 1.0);
		float z_dist = clamp((0.028 - z) / 0.045, 0.0, 1.0);
		arm_weight = x_dist * z_dist;
	}
	
	if (arm_weight > 0.0 && is_walking > 0.01) {
		float phase = TIME * walk_speed;
		float side_sign = sign(x);
		
		// Размахивание рук вперед-назад (по оси Y в локале сетки):
		// Левая и правая рука машут в противофазе: одна вперед, другая назад!
		float swing = sin(phase) * side_sign * arm_swing_amount * arm_weight;
		VERTEX.y += swing * 0.022 * is_walking;
		
		// Покачивание рук вправо-влево (от тела / к телу):
		VERTEX.x += sin(phase * 0.5) * side_sign * 0.003 * arm_weight * is_walking;
	}
}

void fragment() {
	vec4 col = texture(albedo_texture, UV);
	ALBEDO = col.rgb;
	ROUGHNESS = 0.85;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
}
