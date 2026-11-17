extends CharacterBody3D

@onready var visual_root: Node3D = $Visual
@onready var anim_player: AnimationPlayer = $Visual/BacteriaModel/AnimationPlayer

var target_player: CharacterBody3D = null

# Состояния наблюдателя / преследователя
enum PeekerState {
	WATCHING,   # Стоит за углом и выглядывает
	RETREATING, # Быстро заходит за стену и исчезает
	CHASING,    # Агрится, орет и бежит за игроком
	DONE
}

var state: PeekerState = PeekerState.WATCHING
var state_timer: float = 0.0
var watch_duration: float = 1.0
var retreat_direction: Vector3 = Vector3.ZERO
var retreat_speed: float = 3.8

# Звуки
var voice_player: AudioStreamPlayer3D = null
var voice_stream = preload("res://audio/u_gvmdx2u3qx-hey-come-here-363952.mp3")
var help_me_stream: AudioStream = null

# 4 крика преследования
var chase_screams: Array = [
	preload("res://audio/distancingmyselffromthis-wavering-alien-growl-223563.mp3"),
	preload("res://audio/distancingmyselffromthis-creature-wail-223555.mp3"),
	preload("res://audio/distancingmyselffromthis-angry-holler-223562.mp3"),
	preload("res://audio/distancingmyselffromthis-static-loud-holler-223559.mp3")
]
var scream_audio_player: AudioStreamPlayer3D = null
var scream_timer: float = 0.0
var last_scream_idx: int = -1

# Аудиоанализатор децибел (громче орет -> быстрее бежит)
var spectrum_analyzer_instance: AudioEffectSpectrumAnalyzerInstance = null
var current_smooth_db: float = -60.0

# Навигация (A* сетка Backrooms)
var astar: AStar2D = AStar2D.new()
var astar_path: PackedVector2Array = PackedVector2Array()
var current_path_index: int = 0
var astar_timer: float = 0.0

# Длительность погони и возможность оторваться
var chase_duration: float = 0.0
var lost_player_timer: float = 0.0
var has_caught_player: bool = false

# Углы рейкастов обхода углов
var feeler_angles = [
	0.0,
	deg_to_rad(25), deg_to_rad(-25),
	deg_to_rad(50), deg_to_rad(-50),
	deg_to_rad(75), deg_to_rad(-75)
]

func _ready():
	# Удаляем камеры и свет из GLB
	var root_node = find_child("RootNode", true, false)
	if root_node:
		for child in root_node.get_children():
			if child is Camera3D or child is Light3D:
				child.queue_free()

	# Матовый черный цвет
	var black_mat = StandardMaterial3D.new()
	black_mat.albedo_color = Color(0.04, 0.04, 0.04)
	black_mat.roughness = 0.95
	for m in find_children("*", "MeshInstance3D"):
		var mi = m as MeshInstance3D
		mi.material_override = black_mat

	# Начинаем с позы наблюдения
	play_anim("Armature_001|stalkingpose", true)

	# 1. 3D шепот человека ("hey come here" или "help me...")
	voice_player = AudioStreamPlayer3D.new()
	help_me_stream = load("res://audio/help_me.mp3") as AudioStream
	if help_me_stream and randf() < 0.5:
		voice_player.stream = help_me_stream
		voice_player.volume_db = 4.0
		watch_duration = 4.8
	else:
		voice_player.stream = voice_stream
		voice_player.volume_db = 2.0
		watch_duration = 3.8

	voice_player.unit_size = 3.5
	voice_player.max_distance = 32.0
	voice_player.bus = "Master"
	add_child(voice_player)
	voice_player.play()

	# 2. Настройка аудиошины для спектрального анализа криков
	var bus_name = "BacteriaScreamBus"
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx == -1:
		bus_idx = AudioServer.bus_count
		AudioServer.add_bus(bus_idx)
		AudioServer.set_bus_name(bus_idx, bus_name)
		var spectrum_effect = AudioEffectSpectrumAnalyzer.new()
		spectrum_effect.buffer_length = 0.15
		AudioServer.add_bus_effect(bus_idx, spectrum_effect, 0)
	spectrum_analyzer_instance = AudioServer.get_bus_effect_instance(bus_idx, 0)

	# Игрок криков погони
	scream_audio_player = AudioStreamPlayer3D.new()
	scream_audio_player.name = "BacteriaScreamPlayer"
	scream_audio_player.bus = bus_name
	scream_audio_player.unit_size = 10.0
	scream_audio_player.max_distance = 45.0
	add_child(scream_audio_player)

func start_peeker_sequence(hide_dir: Vector3):
	retreat_direction = hide_dir.normalized()
	state = PeekerState.WATCHING
	state_timer = 0.0

	if target_player:
		look_at_target(target_player.global_position)

func play_anim(anim_name: String, loop: bool = true):
	if not anim_player or not anim_player.has_animation(anim_name):
		return
	var anim = anim_player.get_animation(anim_name)
	if loop:
		anim.loop_mode = Animation.LOOP_LINEAR
	else:
		anim.loop_mode = Animation.LOOP_NONE
	if anim_player.current_animation != anim_name:
		anim_player.play(anim_name, 0.2)

func _physics_process(delta: float):
	state_timer += delta

	match state:
		PeekerState.WATCHING:
			velocity = Vector3.ZERO
			if target_player:
				look_at_target(target_player.global_position)
			play_anim("Armature_001|stalkingpose", true)

			var dist = 999.0
			if target_player:
				dist = global_position.distance_to(target_player.global_position)

			# По окончании времени наблюдения: с шансом 18% агрится на игрока, иначе спокойно уходит
			if state_timer >= watch_duration or dist < 7.0:
				state_timer = 0.0
				# Маленький шанс (18%) триггера погони
				if randf() < 0.18:
					trigger_aggro_chase()
				else:
					state = PeekerState.RETREATING

		PeekerState.RETREATING:
			play_anim("Armature_001|bendingOverScene", true)

			if retreat_direction.length_squared() > 0.01:
				var target_rot_y = atan2(-retreat_direction.x, -retreat_direction.z)
				rotation.y = lerp_angle(rotation.y, target_rot_y, 14.0 * delta)

			velocity.x = retreat_direction.x * retreat_speed
			velocity.z = retreat_direction.z * retreat_speed

			# Удаляем сущность ТОЛЬКО когда она полностью скрылась из прямой видимости игрока за стену
			if target_player:
				var cam_p = target_player.global_position + Vector3(0, 1.5, 0)
				var my_center = global_position + Vector3(0, 1.5, 0)
				var my_head = global_position + Vector3(0, 2.2, 0)
				var space_st = get_world_3d().direct_space_state

				var q_c = PhysicsRayQueryParameters3D.create(cam_p, my_center)
				q_c.exclude = [self.get_rid(), target_player.get_rid()]
				var hit_c = space_st.intersect_ray(q_c)

				var q_h = PhysicsRayQueryParameters3D.create(cam_p, my_head)
				q_h.exclude = [self.get_rid(), target_player.get_rid()]
				var hit_h = space_st.intersect_ray(q_h)

				# Если стена полностью перекрыла и центр тела, и голову:
				var fully_hidden = (not hit_c.is_empty()) and (not hit_h.is_empty())

				# Удаляем ТОЛЬКО если скрылся за стену
				if fully_hidden and state_timer >= 0.4:
					state = PeekerState.DONE
					queue_free()
			else:
				if state_timer >= 1.5:
					state = PeekerState.DONE
					queue_free()

		PeekerState.CHASING:
			_process_chase(delta)

		PeekerState.DONE:
			queue_free()

	# Гравитация
	if not is_on_floor():
		velocity.y -= 15.0 * delta
	else:
		velocity.y = 0.0

	move_and_slide()

# Переход в режим ярости / погони
func trigger_aggro_chase():
	state = PeekerState.CHASING
	chase_duration = 0.0
	lost_player_timer = 0.0
	has_caught_player = false

	# Останавливаем шепот
	if voice_player and voice_player.is_playing():
		voice_player.stop()

	# Стартовый яростный крик начала погони
	play_scream_sound(16.0)

	# Активируем бесконечный бег у игрока (БЕЗ фонарика, фонарик при бактерии не нужен)
	if target_player and target_player.has_method("enable_infinite_stamina_only"):
		target_player.enable_infinite_stamina_only()

func _process_chase(dt: float):
	if not target_player:
		queue_free()
		return

	chase_duration += dt

	var my_pos = global_position
	var player_pos = target_player.global_position
	var dist_to_player = my_pos.distance_to(player_pos)

	# 1. Если настиг игрока (< 1.35м) -> переход на уровень 89!
	if dist_to_player < 1.35 and not has_caught_player:
		has_caught_player = true
		catch_player_and_send_to_level89()
		return

	# 2. Воспроизведение периодических криков преследования
	_update_chase_screams(dt)

	# 3. Возможность оторваться:
	# Если игрок вне зоны видимости лучом
	var space_state = get_world_3d().direct_space_state
	var los_query = PhysicsRayQueryParameters3D.create(my_pos + Vector3(0, 1.5, 0), player_pos + Vector3(0, 1.5, 0))
	los_query.exclude = [self.get_rid(), target_player.get_rid()]
	var los_hit = space_state.intersect_ray(los_query)
	var has_los = los_hit.is_empty()

	if not has_los:
		lost_player_timer += dt
	else:
		lost_player_timer = 0.0

	# Игрок оторвался, если:
	# - Убежал дальше 45 метров
	# - Или скрылся за углами и держит дистанцию > 28м дольше 4.5 секунд
	if dist_to_player > 45.0 or (dist_to_player > 28.0 and lost_player_timer > 4.5):
		escape_and_disappear()
		return

	# 4. Навигация к игроку (A* + обход углов)
	var move_dir = compute_smart_nav_dir(dt)

	# 5. Механика: ЧЕМ ГРОМЧЕ ОРЕТ — ТЕМ БЫСТРЕЕ БЕЖИТ
	var measured_db = -60.0
	if scream_audio_player and scream_audio_player.is_playing() and spectrum_analyzer_instance:
		var mag = spectrum_analyzer_instance.get_magnitude_for_frequency_range(20.0, 18000.0)
		var linear_energy = max(mag.x, mag.y)
		if linear_energy > 0.00001:
			measured_db = linear_to_db(linear_energy)

	# Плавное сглаживание децибел
	var smooth_speed = 8.0 if measured_db > current_smooth_db else 3.5
	current_smooth_db = move_toward(current_smooth_db, measured_db, dt * smooth_speed * 10.0)

	# Нормализуем уровень: от тишины (-45 dB) до самого громкого пика (-8 dB)
	var vol_factor = clamp(inverse_lerp(-45.0, -8.0, current_smooth_db), 0.0, 1.0)

	# Скорость: от 3.1 м/с (чуть медленнее игрока, можно оторваться на поворотах)
	# до 6.3 м/с на пике крика (быстрее спринта игрока 6.0 м/с!)
	var cur_speed = lerp(3.1, 6.35, vol_factor)

	velocity.x = move_dir.x * cur_speed
	velocity.z = move_dir.z * cur_speed

	# Поворот в сторону движения
	if move_dir.length_squared() > 0.01:
		var target_rot_y = atan2(-move_dir.x, -move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_rot_y, 10.0 * dt)

	play_anim("Armature_001|bendingOverScene", true)

func _update_chase_screams(dt: float):
	if chase_screams.is_empty() or not scream_audio_player:
		return
	if scream_audio_player.is_playing():
		return

	scream_timer -= dt
	if scream_timer <= 0.0:
		play_scream_sound(14.0)
		scream_timer = randf_range(1.0, 2.2)

func play_scream_sound(vol: float = 14.0):
	if chase_screams.is_empty() or not scream_audio_player:
		return
	var next_idx = randi() % chase_screams.size()
	if next_idx == last_scream_idx and chase_screams.size() > 1:
		next_idx = (next_idx + 1) % chase_screams.size()
	last_scream_idx = next_idx

	scream_audio_player.stream = chase_screams[next_idx]
	scream_audio_player.volume_db = vol
	scream_audio_player.pitch_scale = randf_range(0.92, 1.08)
	scream_audio_player.play()

# Поимка игрока: отправка на Level 89
func catch_player_and_send_to_level89():
	state = PeekerState.DONE
	velocity = Vector3.ZERO

	if scream_audio_player:
		scream_audio_player.stop()

	var builder = get_tree().root.find_child("Main", true, false)
	if builder and builder.has_method("_transition_to_level_89"):
		builder._transition_to_level_89()

	queue_free()

# Игрок оторвался — монстр растворяется
func escape_and_disappear():
	state = PeekerState.DONE
	velocity = Vector3.ZERO

	if scream_audio_player:
		scream_audio_player.stop()

	# Возвращаем игрока в нормальное состояние (сброс стамины)
	if target_player and target_player.has_method("disable_infinite_stamina_only"):
		target_player.disable_infinite_stamina_only()
	elif target_player and target_player.has_method("disable_flashlight_and_reset_stamina"):
		target_player.disable_flashlight_and_reset_stamina()

	# Помечаем в билдере успешный побег (дает шанс 1% на спавн noclip дыры)
	var builder = get_tree().root.find_child("Main", true, false)
	if builder:
		builder.has_escaped_monster_once = true

	queue_free()

# Высокопроизводительная навигация к игроку
func compute_smart_nav_dir(dt: float) -> Vector3:
	var my_pos = global_position
	var player_pos = target_player.global_position
	var space_state = get_world_3d().direct_space_state

	# Луч прямой видимости
	var ray_query = PhysicsRayQueryParameters3D.create(my_pos + Vector3(0, 0.7, 0), player_pos + Vector3(0, 0.7, 0))
	ray_query.exclude = [self.get_rid(), target_player.get_rid()]
	var hit = space_state.intersect_ray(ray_query)

	var target_sub_goal = player_pos
	if hit.is_empty():
		target_sub_goal = player_pos
		astar_path.clear()
	else:
		astar_timer -= dt
		if astar_timer <= 0.0 or astar_path.is_empty():
			astar_timer = 0.4
			_rebuild_astar_path(my_pos, player_pos)

		if not astar_path.is_empty():
			while current_path_index < astar_path.size():
				var wp_2d = astar_path[current_path_index]
				var wp_3d = Vector3(wp_2d.x, my_pos.y, wp_2d.y)
				if my_pos.distance_to(wp_3d) < 1.0 and current_path_index < astar_path.size() - 1:
					current_path_index += 1
				else:
					target_sub_goal = wp_3d
					break

	var desired_dir = (target_sub_goal - my_pos).normalized()
	desired_dir.y = 0.0
	desired_dir = desired_dir.normalized()

	return compute_obstacle_avoidance_dir(desired_dir)

func _rebuild_astar_path(from_pos: Vector3, to_pos: Vector3):
	var builder = get_tree().root.find_child("Main", true, false)
	if not builder or not builder.has_method("get_chunk_grid"):
		return

	astar.clear()
	const CELL_SIZE = 2.0
	const CHUNK_SIZE = 16.0
	const BLOCK_CELLS = 8

	var my_cell_x = int(floor(from_pos.x / CELL_SIZE))
	var my_cell_z = int(floor(from_pos.z / CELL_SIZE))
	var target_cell_x = int(floor(to_pos.x / CELL_SIZE))
	var target_cell_z = int(floor(to_pos.z / CELL_SIZE))

	var min_gx = min(my_cell_x, target_cell_x) - 3
	var max_gx = max(my_cell_x, target_cell_x) + 3
	var min_gz = min(my_cell_z, target_cell_z) - 3
	var max_gz = max(my_cell_z, target_cell_z) + 3

	min_gx = max(min_gx, my_cell_x - 8)
	max_gx = min(max_gx, my_cell_x + 8)
	min_gz = max(min_gz, my_cell_z - 8)
	max_gz = min(max_gz, my_cell_z + 8)

	var coord_to_id = {}
	var point_id = 0

	for gx in range(min_gx, max_gx + 1):
		for gz in range(min_gz, max_gz + 1):
			var world_x = (float(gx) + 0.5) * CELL_SIZE
			var world_z = (float(gz) + 0.5) * CELL_SIZE

			var cx = int(floor(world_x / CHUNK_SIZE))
			var cz = int(floor(world_z / CHUNK_SIZE))
			var lx = world_x - cx * CHUNK_SIZE
			var lz = world_z - cz * CHUNK_SIZE
			var col = clamp(int(floor(lx / CELL_SIZE)), 0, BLOCK_CELLS - 1)
			var r = clamp(int(floor(lz / CELL_SIZE)), 0, BLOCK_CELLS - 1)

			var grid = builder.get_chunk_grid(Vector2i(cx, cz))
			if not grid.is_empty() and grid[r][col] == 1:
				var key = Vector2i(gx, gz)
				coord_to_id[key] = point_id
				astar.add_point(point_id, Vector2(world_x, world_z))
				point_id += 1

	var neighbors = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for key in coord_to_id.keys():
		var id1 = coord_to_id[key]
		for n in neighbors:
			var n_key = key + n
			if coord_to_id.has(n_key):
				var id2 = coord_to_id[n_key]
				if not astar.are_points_connected(id1, id2):
					astar.connect_points(id1, id2)

	var start_2d = Vector2(from_pos.x, from_pos.z)
	var target_2d = Vector2(to_pos.x, to_pos.z)
	var start_id = astar.get_closest_point(start_2d)
	var end_id = astar.get_closest_point(target_2d)

	if start_id != -1 and end_id != -1:
		var path = astar.get_point_path(start_id, end_id)
		astar_path = path
		current_path_index = 0
		if astar_path.size() > 1 and start_2d.distance_to(astar_path[0]) < 0.8:
			current_path_index = 1

func compute_obstacle_avoidance_dir(desired_dir: Vector3) -> Vector3:
	var space_state = get_world_3d().direct_space_state
	var origin = global_position + Vector3(0, 0.7, 0)
	var best_dir = desired_dir
	var best_score = -999999.0

	var bumper_query = PhysicsRayQueryParameters3D.create(origin, origin + desired_dir * 0.9)
	bumper_query.exclude = [self.get_rid()]
	if target_player:
		bumper_query.exclude.append(target_player.get_rid())
	var bumper_hit = space_state.intersect_ray(bumper_query)

	var check_dist = 2.0
	for angle in feeler_angles:
		var dir_candidate = desired_dir.rotated(Vector3.UP, angle).normalized()
		var ray_target = origin + dir_candidate * check_dist

		var query = PhysicsRayQueryParameters3D.create(origin, ray_target)
		query.exclude = [self.get_rid()]
		if target_player:
			query.exclude.append(target_player.get_rid())

		var result = space_state.intersect_ray(query)
		var free_dist = check_dist
		var hit_normal = Vector3.ZERO
		if not result.is_empty():
			free_dist = origin.distance_to(result.position)
			hit_normal = result.normal

		var alignment = dir_candidate.dot(desired_dir)
		var clearance = free_dist / check_dist

		var score = alignment * 2.0 + clearance * 3.5
		if free_dist < 0.6:
			score -= 10.0
		if not bumper_hit.is_empty() and hit_normal != Vector3.ZERO:
			var slide_dir = (desired_dir - hit_normal * desired_dir.dot(hit_normal)).normalized()
			score += dir_candidate.dot(slide_dir) * 2.5

		if score > best_score:
			best_score = score
			best_dir = dir_candidate

	return best_dir

func look_at_target(target_pos: Vector3):
	var to_t = (target_pos - global_position)
	to_t.y = 0.0
	if to_t.length_squared() > 0.01:
		rotation.y = atan2(-to_t.x, -to_t.z)
