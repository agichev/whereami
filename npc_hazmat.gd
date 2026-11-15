extends CharacterBody3D

@export var speed: float = 3.0
@export var sprint_speed: float = 5.2
@export var rot_speed: float = 8.0

@onready var visual_root: Node3D = $Visual
@onready var mannequin_mesh = find_child("Mannequin", true, false)
@onready var char_mesh: MeshInstance3D = find_child("Male_4", true, false)

var anim_player: AnimationPlayer = null
var current_anim: String = ""

# Скелеты
var anim_skeleton: Skeleton3D = null
var char_skeleton: Skeleton3D = null
var head_bone_idx: int = -1

# Маппинг всех костей: [ual_bone_a, ual_bone_b, haz_bone_a, haz_bone_b]
var limb_pairs: Array = [
	# Позвоночник
	["pelvis", "spine_01", "spine", "spine.001"],
	["spine_01", "spine_02", "spine.001", "spine.002"],
	["spine_02", "spine_03", "spine.002", "spine.003"],
	["spine_03", "neck_01", "spine.003", "spine.004"],
	
	# Ноги
	["thigh_l", "calf_l", "thigh.L", "shin.L"],
	["calf_l", "foot_l", "shin.L", "foot.L"],
	["foot_l", "ball_l", "foot.L", "toe.L"],
	
	["thigh_r", "calf_r", "thigh.R", "shin.R"],
	["calf_r", "foot_r", "shin.R", "foot.R"],
	["foot_r", "ball_r", "foot.R", "toe.R"],
	
	# Руки
	["upperarm_l", "lowerarm_l", "upper_arm.L", "forearm.L"],
	["lowerarm_l", "hand_l", "forearm.L", "hand.L"],
	
	["upperarm_r", "lowerarm_r", "upper_arm.R", "forearm.R"],
	["lowerarm_r", "hand_r", "forearm.R", "hand.R"]
]

var retarget_cache: Array = []

var target_player: CharacterBody3D = null
var stop_distance: float = 2.8      # Дистанция, на которой NPC останавливается
var start_follow_distance: float = 5.2 # Начинает идти ТОЛЬКО когда игрок отошел достаточно далеко
var is_following: bool = false       # Состояние следования с гистерезисом
var feeler_angles = [0.0, deg_to_rad(28.0), deg_to_rad(-28.0), deg_to_rad(55.0), deg_to_rad(-55.0), deg_to_rad(85.0), deg_to_rad(-85.0), deg_to_rad(115.0), deg_to_rad(-115.0)]

# Система умной сетки поиска путей AStar
var astar = AStar2D.new()
var astar_path: Array[Vector2] = []
var astar_timer: float = 0.0
var current_path_index: int = 0

# Механика "Bacteria scream": подойти супер близко (< 1.3м) и постоять 3 секунды
var close_time: float = 0.0
var is_screaming: bool = false
var is_mutated: bool = false # Флаг мутации (почернел, вытянулся)
var chase_duration: float = 0.0 # Время непрерывной погони (оторваться невозможно минимум 1.5 минуты = 90 сек)
const MIN_CHASE_DURATION: float = 90.0 # 1.5 минуты железной погони
var lost_target_timer: float = 0.0 # Таймер потери игрока из виду (нужно скрываться не менее 5 секунд)
var is_catching_player: bool = false # Флаг поимки игрока монстром
var fatigue_timer: float = 0.0 # Таймер цикла спринта и замедлений сущности
var is_slowing_down: bool = false # Фаза сбавления оборотов
var slow_down_duration: float = 0.0
var scream_head_blend: float = 0.0 # 0.0 (нормальное положение) до 1.0 (запрокинута голова вверх)
var hazmat_material: StandardMaterial3D = null
var bacteria_audio_stream = preload("res://audio/bacteria.mp3")
var bacteria_audio_player: AudioStreamPlayer3D = null
var blackout_audio_stream = preload("res://audio/soundreality-sub-down-222742.mp3")
var blackout_audio_player: AudioStreamPlayer = null

# 4 крика монстра во время преследования игрока
var chase_screams: Array = [
	preload("res://audio/distancingmyselffromthis-wavering-alien-growl-223563.mp3"),
	preload("res://audio/distancingmyselffromthis-creature-wail-223555.mp3"),
	preload("res://audio/distancingmyselffromthis-angry-holler-223562.mp3"),
	preload("res://audio/distancingmyselffromthis-static-loud-holler-223559.mp3")
]
var chase_audio_player: AudioStreamPlayer3D = null
var chase_scream_timer: float = 0.0
var last_chase_scream_idx: int = -1

# Анализатор реальной акустической громкости звука в реальном времени
var spectrum_analyzer_instance: AudioEffectSpectrumAnalyzerInstance = null
var current_smooth_db: float = -60.0

func _ready():
	# 1. Скрываем манекен UAL1
	if mannequin_mesh:
		mannequin_mesh.visible = false

	# 2. Настраиваем ретро-текстуру химзащиты
	if char_mesh:
		var tex = load("res://character/Hazmet_Tex.png")
		if tex:
			hazmat_material = StandardMaterial3D.new()
			hazmat_material.albedo_texture = tex
			hazmat_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
			hazmat_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			hazmat_material.roughness = 0.8
			char_mesh.material_override = hazmat_material

	# 3. Находим скелеты и анимации
	for ap in find_children("*", "AnimationPlayer", true, false):
		if ap.has_animation("Walk") or ap.has_animation("Idle"):
			anim_player = ap
			break

	for s in find_children("*", "Skeleton3D", true, false):
		if s.get_bone_count() > 40:
			anim_skeleton = s
		else:
			char_skeleton = s

	# 4. Кэшируем параметры для векторного ретаргетинга
	if anim_skeleton and char_skeleton:
		head_bone_idx = char_skeleton.find_bone("spine.004")
		var skel_to_model = char_skeleton.transform
		var cur_node: Node = char_skeleton.get_parent()
		while cur_node and cur_node != find_child("Model", true, false):
			if cur_node is Node3D:
				skel_to_model = cur_node.transform * skel_to_model
			cur_node = cur_node.get_parent()
		var model_to_skel_basis = skel_to_model.basis.inverse()

		for item in limb_pairs:
			var u_a = anim_skeleton.find_bone(item[0])
			var u_b = anim_skeleton.find_bone(item[1])
			var h_a = char_skeleton.find_bone(item[2])
			var h_b = char_skeleton.find_bone(item[3])
			if u_a != -1 and u_b != -1 and h_a != -1 and h_b != -1:
				var h_p_idx = char_skeleton.get_bone_parent(h_a)
				var h_rest_dir = (char_skeleton.get_bone_global_rest(h_b).origin - char_skeleton.get_bone_global_rest(h_a).origin).normalized()
				var h_rest_basis = char_skeleton.get_bone_global_rest(h_a).basis
				retarget_cache.append([u_a, u_b, h_a, h_p_idx, h_rest_dir, h_rest_basis, model_to_skel_basis])

	# 5. Инициализация звуков: Bacteria и громкого звука отключения света (soundreality-sub-down)
	bacteria_audio_player = AudioStreamPlayer3D.new()
	bacteria_audio_player.name = "BacteriaPlayer"
	bacteria_audio_player.stream = bacteria_audio_stream
	bacteria_audio_player.unit_size = 4.0
	bacteria_audio_player.max_distance = 30.0
	bacteria_audio_player.volume_db = 4.0
	add_child(bacteria_audio_player)

	blackout_audio_player = AudioStreamPlayer.new()
	blackout_audio_player.name = "BlackoutSoundPlayer"
	blackout_audio_player.stream = blackout_audio_stream
	blackout_audio_player.volume_db = 14.0 # Очень громкий звук отключения света, как просил пользователь
	add_child(blackout_audio_player)

	# Настройка выделенной аудиошины с AudioEffectSpectrumAnalyzer для измерения реальных децибел
	var bus_name = "CreatureScreamBus"
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx == -1:
		bus_idx = AudioServer.bus_count
		AudioServer.add_bus(bus_idx)
		AudioServer.set_bus_name(bus_idx, bus_name)
		var spectrum_effect = AudioEffectSpectrumAnalyzer.new()
		spectrum_effect.buffer_length = 0.15
		AudioServer.add_bus_effect(bus_idx, spectrum_effect, 0)

	spectrum_analyzer_instance = AudioServer.get_bus_effect_instance(bus_idx, 0)

	chase_audio_player = AudioStreamPlayer3D.new()
	chase_audio_player.name = "ChaseScreamPlayer"
	chase_audio_player.bus = bus_name
	chase_audio_player.unit_size = 10.0 # Очень громкий и мощный вблизи
	chase_audio_player.max_distance = 120.0 # Слышно даже если игрок убежал далеко через коридоры
	chase_audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	chase_audio_player.volume_db = 12.0
	add_child(chase_audio_player)

	# Ищем игрока если цель еще не задана
	if not target_player:
		target_player = get_tree().root.find_child("HazmatPlayer", true, false)

	play_anim("Idle")

func _process(dt: float):
	# Векторный ретаргетинг анимаций UAL1 на кости химзащиты
	if anim_skeleton and char_skeleton:
		for item in retarget_cache:
			var u_a: int = item[0]
			var u_b: int = item[1]
			var h_a: int = item[2]
			var h_p_idx: int = item[3]
			var h_rest_dir: Vector3 = item[4]
			var h_rest_basis: Basis = item[5]
			var model_to_skel_basis: Basis = item[6]

			var u_cur_dir = (anim_skeleton.get_bone_global_pose(u_b).origin - anim_skeleton.get_bone_global_pose(u_a).origin).normalized()
			var target_skel_dir = (model_to_skel_basis * u_cur_dir).normalized()

			var q_align = Quaternion(h_rest_dir, target_skel_dir)
			var target_h_g = Basis(q_align) * h_rest_basis

			var parent_h_g = Basis()
			if h_p_idx != -1:
				parent_h_g = char_skeleton.get_bone_global_pose(h_p_idx).basis

			var local_target = parent_h_g.inverse() * target_h_g
			char_skeleton.set_bone_pose_rotation(h_a, local_target.get_rotation_quaternion())

		# Анимация запрокидывания головы вверх при крике
		if head_bone_idx != -1:
			var base_head_q = char_skeleton.get_bone_pose_rotation(head_bone_idx)
			if scream_head_blend > 0.001:
				# Поворот головы назад/вверх (угол ~75 градусов)
				var tilt_up_q = Quaternion(Vector3.RIGHT, deg_to_rad(-75.0))
				var final_q = base_head_q.slerp(base_head_q * tilt_up_q, scream_head_blend)
				char_skeleton.set_bone_pose_rotation(head_bone_idx, final_q)
			else:
				# Гарантированное возвращение головы на место
				char_skeleton.set_bone_pose_rotation(head_bone_idx, base_head_q)

func _physics_process(dt: float):
	if not is_on_floor():
		velocity.y -= 9.8 * dt

	if not target_player:
		target_player = get_tree().root.find_child("HazmatPlayer", true, false)
		move_and_slide()
		return

	# Вектор к игроку в мировой плоскости XZ
	var to_player = target_player.global_position - global_position
	to_player.y = 0.0
	var dist_to_player = to_player.length()

	# Проверка супер близкого расстояния (< 1.35 м) для триггера крика Bacteria
	if dist_to_player < 1.35 and not is_screaming:
		close_time += dt
		if close_time >= 3.0:
			trigger_bacteria_scream()
	elif not is_screaming:
		close_time = max(0.0, close_time - dt * 2.0)

	# Плавная интерполяция запрокидывания головы
	if is_screaming:
		scream_head_blend = move_toward(scream_head_blend, 1.0, dt * 2.5)
	else:
		scream_head_blend = move_toward(scream_head_blend, 0.0, dt * 2.0)

	# Во время крика NPC замирает на месте и смотрит вверх/на игрока
	if is_screaming:
		velocity.x = move_toward(velocity.x, 0, speed * 3.0 * dt)
		velocity.z = move_toward(velocity.z, 0, speed * 3.0 * dt)
		play_anim("Idle")
		move_and_slide()
		return

	# Умное поведение ожидания (гистерезис):
	if not is_following:
		if dist_to_player > start_follow_distance:
			is_following = true
	else:
		if dist_to_player <= stop_distance:
			is_following = false

	# Проверка: оторвался ли игрок от сущности (когда монстр был мутирован/черен)
	if is_mutated:
		# Во время мутации монстр преследует игрока упорно и не останавливается из-за гистерезиса
		is_following = true
		chase_duration += dt

		# Проверка поимки игрока: если монстр подошел вплотную (< 1.15м)
		if not is_catching_player and dist_to_player < 1.15:
			is_catching_player = true
			trigger_jumpscare_and_game_over()
			return

		var space_state = get_world_3d().direct_space_state
		var has_los = has_direct_line_of_sight(space_state)

		# Если сущность видит игрока — таймер потери сбрасывается моментально
		if has_los:
			lost_target_timer = 0.0
		else:
			lost_target_timer += dt

		# Оторваться ФИЗИЧЕСКИ НЕВОЗМОЖНО минимум 1.5 минуты (90 секунд)!
		if chase_duration >= MIN_CHASE_DURATION:
			# Только по истечении 1.5 минут игрок может оторваться, если далеко убежал
			if dist_to_player > 50.0:
				reset_from_mutated_state()
			elif dist_to_player > 32.0 and lost_target_timer > 6.0:
				reset_from_mutated_state()

	if is_following:
		# Воспроизведение случайных криков преследования с интервалом в 1-2 секунды
		_update_chase_screams(dt)

		# Умная навигация: A* + локальный обход углов
		var move_dir = compute_smart_nav_dir(dt)

		# Если игрок убежал совсем далеко — ускоряемся на спринт
		var is_sprinting = dist_to_player > 7.5
		var cur_speed = sprint_speed if is_sprinting else speed

		# В черном/мутированном состоянии скорость сущности прямо зависит от реальной физической громкости (dB):
		if is_mutated:
			var measured_db = -60.0
			if chase_audio_player and chase_audio_player.is_playing() and spectrum_analyzer_instance:
				# Замеряем амплитуду всего слышимого спектра (20 Гц - 18000 Гц)
				var mag = spectrum_analyzer_instance.get_magnitude_for_frequency_range(20.0, 18000.0)
				var linear_energy = max(mag.x, mag.y)
				if linear_energy > 0.00001:
					measured_db = linear_to_db(linear_energy)

			# Плавное сглаживание децибел (быстрая атака на нарастание громкости, плавный спад при затихании)
			var smooth_speed = 8.0 if measured_db > current_smooth_db else 3.5
			current_smooth_db = move_toward(current_smooth_db, measured_db, dt * smooth_speed * 10.0)

			# Нормализуем уровень: от тишины (-45 dB) до самого громкого пика (-5 dB и выше)
			var vol_factor = clamp(inverse_lerp(-45.0, -8.0, current_smooth_db), 0.0, 1.0)

			# Когда тихо / молчит: 2.85 м/с (чуть медленнее шага игрока 3.2, дает передышку)
			# На пике громкости (максимальные децибелы): 6.45 м/с (быстрее спринта игрока 6.0!)
			cur_speed = lerp(2.85, 6.45, vol_factor)
			is_sprinting = vol_factor > 0.35

		velocity.x = move_dir.x * cur_speed
		velocity.z = move_dir.z * cur_speed

		# При ходьбе тело направлено в сторону движения + с легким смещением взгляда в сторону игрока
		var desired_dir = to_player.normalized()
		var walk_facing = (move_dir * 0.75 + desired_dir * 0.25).normalized()
		var local_walk_dir = global_transform.basis.inverse() * walk_facing
		var target_rot = atan2(-local_walk_dir.x, -local_walk_dir.z)
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_rot, rot_speed * dt)

		if is_sprinting:
			play_anim("Sprint")
		else:
			play_anim("Walk")
	else:
		# Стоит на месте, плавно гасит скорость и смотрит на игрока
		velocity.x = move_toward(velocity.x, 0, speed * 2.5 * dt)
		velocity.z = move_toward(velocity.z, 0, speed * 2.5 * dt)

		if dist_to_player > 0.4:
			var look_dir = to_player.normalized()
			var local_look = global_transform.basis.inverse() * look_dir
			var target_rot = atan2(-local_look.x, -local_look.z)
			visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_rot, rot_speed * 0.6 * dt)

		play_anim("Idle")

	move_and_slide()

# Срабатывание отключения света и крика Bacteria
func trigger_bacteria_scream():
	is_screaming = true
	close_time = 0.0
	is_following = false

	# 1. Перед тем как он начнет чернеть: вырубаем весь свет на карте с ОЧЕНЬ громким звуком soundreality-sub-down
	if blackout_audio_player:
		blackout_audio_player.play()

	var builder = get_tree().root.find_child("Main", true, false)
	if builder and builder.has_method("trigger_global_blackout"):
		builder.trigger_global_blackout()

	# Небольшая драматическая пауза (0.5 сек) перед криком и почернением
	await get_tree().create_timer(0.5).timeout

	# 2. Крик Bacteria и подъем головы
	if bacteria_audio_player:
		bacteria_audio_player.play()

	# Запрокидываем голову вверх
	var head_up_tw = create_tween()
	head_up_tw.tween_property(self, "scream_head_blend", 1.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# 3. Моделька начинает чернеть
	is_mutated = true
	if hazmat_material:
		var tw = create_tween()
		tw.tween_property(hazmat_material, "albedo_color", Color(0.04, 0.04, 0.04, 1.0), 3.0).set_trans(Tween.TRANS_SINE)

	# Вытягивание модельки в 1.5 раза по вертикали (Y-ось: 1.0 -> 1.5), именно вытянуться в высоту
	if visual_root:
		var stretch_tw = create_tween()
		stretch_tw.tween_property(visual_root, "scale:y", 1.5, 4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Через 2 секунды после начала почернения у игрока включается фонарик и стамина становится бесконечной
	_delayed_trigger_player_flashlight()

	# Ждем длительность крика звука bacteria.mp3 (около 5 секунд)
	var scream_duration = 5.0
	if bacteria_audio_player and bacteria_audio_player.stream:
		scream_duration = bacteria_audio_player.stream.get_length()

	await get_tree().create_timer(scream_duration).timeout
	is_screaming = false
	
	# Плавно и гарантированно возвращаем голову на место
	var return_tw = create_tween()
	return_tw.tween_property(self, "scream_head_blend", 0.0, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _delayed_trigger_player_flashlight():
	await get_tree().create_timer(2.0).timeout
	if not target_player:
		target_player = get_tree().root.find_child("HazmatPlayer", true, false)
	if target_player and target_player.has_method("enable_flashlight_and_infinite_stamina"):
		target_player.enable_flashlight_and_infinite_stamina()

func has_direct_line_of_sight(space_state: PhysicsDirectSpaceState3D) -> bool:
	if not target_player:
		return false
	var origin = global_position + Vector3(0, 0.7, 0)
	var p_target = target_player.global_position + Vector3(0, 0.7, 0)
	var query = PhysicsRayQueryParameters3D.create(origin, p_target)
	query.exclude = [self.get_rid(), target_player.get_rid()]
	var res = space_state.intersect_ray(query)
	return res.is_empty()

# Сброс мутации и возвращение мира и сущности в нормальное состояние
func reset_from_mutated_state():
	if not is_mutated:
		return
	is_mutated = false

	# 1. Включаем свет на карте, возвращаем туман и гул ламп
	var builder = get_tree().root.find_child("Main", true, false)
	if builder:
		builder.has_escaped_monster_once = true # Активируем шанс 1% спавна noclip чанка
		if builder.has_method("restore_global_lighting"):
			builder.restore_global_lighting()

	# 2. Выключаем фонарик у игрока и сбрасываем стамину к нормальной
	if target_player and target_player.has_method("disable_flashlight_and_reset_stamina"):
		target_player.disable_flashlight_and_reset_stamina()

	# 3. Останавливаем крики монстра
	if chase_audio_player and chase_audio_player.is_playing():
		chase_audio_player.stop()

	# 4. Возвращаем желтый цвет костюма
	if hazmat_material:
		var tw_mat = create_tween()
		tw_mat.tween_property(hazmat_material, "albedo_color", Color(1.0, 1.0, 1.0, 1.0), 1.5).set_trans(Tween.TRANS_SINE)

	# 5. Возвращаем пропорции модельки назад в норму (scale:y -> 1.0)
	if visual_root:
		var tw_scale = create_tween()
		tw_scale.tween_property(visual_root, "scale:y", 1.0, 1.5).set_trans(Tween.TRANS_SINE)

# Скример при поимке игрока: видео jumpscare и возврат в Main Menu
func trigger_jumpscare_and_game_over():
	# Блокируем управление игрока
	if target_player:
		target_player.is_active = false
		target_player.velocity = Vector3.ZERO

	# Останавливаем звуки шагов и криков
	if chase_audio_player:
		chase_audio_player.stop()

	var ui = get_tree().root.find_child("UI", true, false)
	if not ui:
		get_tree().reload_current_scene()
		return

	# Поверх всего экрана на весь CanvasLayer создаем VideoStreamPlayer
	var vp = VideoStreamPlayer.new()
	vp.name = "DeathJumpscarePlayer"
	vp.expand = true
	vp.anchor_right = 1.0
	vp.anchor_bottom = 1.0
	vp.stream = load("res://death_jumpscare.ogv")
	vp.volume_db = 8.0 # Громкий пугающий звук скримера
	vp.z_index = 100
	ui.add_child(vp)

	vp.finished.connect(func():
		# По окончании скримера перезагружаем сцену и открываем главное меню
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().reload_current_scene()
	)
	vp.play()

func _update_chase_screams(dt: float):
	# КРИЧАТЬ ТОЛЬКО КОГДА СТАЛ ЧЕРНЫМ (is_mutated)
	if not is_mutated:
		return

	if chase_screams.is_empty() or not chase_audio_player:
		return

	# Если прямо сейчас воспроизводится звук, ждем пока он доиграет
	if chase_audio_player.is_playing():
		return

	chase_scream_timer -= dt
	if chase_scream_timer <= 0.0:
		# Выбираем случайный звук из 4 криков (без повтора предыдущего)
		var next_idx = randi() % chase_screams.size()
		if next_idx == last_chase_scream_idx and chase_screams.size() > 1:
			next_idx = (next_idx + 1) % chase_screams.size()
		last_chase_scream_idx = next_idx

		var scream_stream = chase_screams[next_idx]
		chase_audio_player.stream = scream_stream
		chase_audio_player.volume_db = 14.0
		chase_audio_player.pitch_scale = randf_range(0.93, 1.07)
		chase_audio_player.play()

		# Интервал в 1-2 секунды до следующего крика после завершения текущего
		chase_scream_timer = randf_range(1.0, 2.0)

# Умная высокопроизводительная навигация по сетке Backrooms (CELL_SIZE = 2.0m)
func compute_smart_nav_dir(dt: float) -> Vector3:
	if not target_player:
		return Vector3.ZERO

	var my_pos = global_position
	var player_pos = target_player.global_position
	var space_state = get_world_3d().direct_space_state

	# Проверяем прямую видимость до игрока лучом (с небольшим запасом по высоте)
	var ray_query = PhysicsRayQueryParameters3D.create(my_pos + Vector3(0, 0.7, 0), player_pos + Vector3(0, 0.7, 0))
	ray_query.exclude = [self.get_rid(), target_player.get_rid()]
	var hit = space_state.intersect_ray(ray_query)

	var target_sub_goal = player_pos
	if hit.is_empty():
		# Игрок в прямой видимости!
		target_sub_goal = player_pos
		astar_path.clear()
	else:
		# Игрок скрылся за стеной/углом
		astar_timer -= dt
		if astar_timer <= 0.0 or astar_path.is_empty():
			astar_timer = 0.5 # Пересчет всего 2 раза в секунду
			_rebuild_astar_path(my_pos, player_pos)
		
		# Продвигаемся по точкам пути
		if not astar_path.is_empty():
			while current_path_index < astar_path.size():
				var wp_2d = astar_path[current_path_index]
				var wp_3d = Vector3(wp_2d.x, my_pos.y, wp_2d.y)
				# Достигли текущей контрольной точки коридора
				if my_pos.distance_to(wp_3d) < 1.0 and current_path_index < astar_path.size() - 1:
					current_path_index += 1
				else:
					target_sub_goal = wp_3d
					break

	var desired_dir = (target_sub_goal - my_pos).normalized()
	desired_dir.y = 0.0
	desired_dir = desired_dir.normalized()

	# Огибание углов через быстрый Context Steering с физическим отталкиванием
	return compute_obstacle_avoidance_dir(desired_dir)

func _rebuild_astar_path(from_pos: Vector3, to_pos: Vector3):
	var builder = get_tree().root.find_child("Main", true, false)
	if not builder or not builder.has_method("get_chunk_grid"):
		return

	astar.clear()
	# Используем точный размер клеток генератора лабиринта: CELL_SIZE = 2.0 метра!
	const CELL_SIZE = 2.0
	const CHUNK_SIZE = 16.0
	const BLOCK_CELLS = 8

	var my_cell_x = int(floor(from_pos.x / CELL_SIZE))
	var my_cell_z = int(floor(from_pos.z / CELL_SIZE))
	var target_cell_x = int(floor(to_pos.x / CELL_SIZE))
	var target_cell_z = int(floor(to_pos.z / CELL_SIZE))

	# Ограничиваем область поиска небольшим окном вокруг сущности и игрока (максимум +-7 клеток)
	var min_gx = min(my_cell_x, target_cell_x) - 3
	var max_gx = max(my_cell_x, target_cell_x) + 3
	var min_gz = min(my_cell_z, target_cell_z) - 3
	var max_gz = max(my_cell_z, target_cell_z) + 3

	# Не более 18х18 клеток = максимум ~300 операций без единого рейкаста!
	min_gx = max(min_gx, my_cell_x - 8)
	max_gx = min(max_gx, my_cell_x + 8)
	min_gz = max(min_gz, my_cell_z - 8)
	max_gz = min(max_gz, my_cell_z + 8)

	var coord_to_id = {}
	var point_id = 0

	for gx in range(min_gx, max_gx + 1):
		for gz in range(min_gz, max_gz + 1):
			# Координаты центра клетки в мировом пространстве
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

	# Связываем соседние клетки
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

# Рейкаст-алгоритм обхода препятствий (Context Steering / Whiskers)
func compute_obstacle_avoidance_dir(desired_dir: Vector3) -> Vector3:
	var space_state = get_world_3d().direct_space_state
	var origin = global_position + Vector3(0, 0.7, 0)
	var best_dir = desired_dir
	var best_score = -999999.0

	# 1. Проверяем наличие препятствия прямо перед собой (короткий бамперный луч 0.8м)
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

		# Сильный штраф, если смотрим в стену ближе 0.6м
		var score = alignment * 2.0 + clearance * 3.5
		if free_dist < 0.6:
			score -= 10.0
		if not bumper_hit.is_empty() and hit_normal != Vector3.ZERO:
			# Даем преимущество касательному скольжению вдоль нормали стены
			var slide_dir = (desired_dir - hit_normal * desired_dir.dot(hit_normal)).normalized()
			score += dir_candidate.dot(slide_dir) * 2.5

		if score > best_score:
			best_score = score
			best_dir = dir_candidate

	return best_dir

func play_anim(anim_name: String):
	if current_anim == anim_name:
		return
	if anim_player and anim_player.has_animation(anim_name):
		current_anim = anim_name
		anim_player.play(anim_name, 0.25)
