class_name PartygoerEnemy
extends CharacterBody3D

# Partygoer Enemy (Монстр Уровня Fun)
# - Спавнится по лабиринту
# - При обычном свете: всегда играет песня "Daisy Bell" (3D Audio), бродит, при виде игрока преследует со скоростью 1.6 м/с
# - При блэкауте (свет выключен):
#     - Замолкает (собственная песня отключается)
#     - Замирает на месте (застывшая статуя)
#     - Активируется ТОЛЬКО если игрок посветит на него фонариком (конус света)
#     - Но при этом даже после активации от фонарика остаётся БЕЗЗВУЧНЫМ, пока не включится свет!

@export var move_speed: float = 1.6
@export var chase_speed: float = 1.6

var target_player: CharacterBody3D = null
var model_root: Node3D = null
var mesh_instance: MeshInstance3D = null
var shader_mat: ShaderMaterial = null
var daisy_audio: AudioStreamPlayer3D = null

var is_chasing: bool = false
var walk_cycle_time: float = 0.0

# Состояние блэкаута
var is_frozen_in_darkness: bool = false
var was_activated_by_flashlight: bool = false

# Патрулирование
var wander_dir: Vector3 = Vector3.FORWARD
var wander_timer: float = 0.0

func _ready():
	_setup_collision()
	_setup_model()
	_setup_audio()

func _setup_collision():
	collision_layer = 2 # Enemy layer
	collision_mask = 1  # Collide with world/walls
	
	var col = CollisionShape3D.new()
	var cap = CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 2.1
	col.shape = cap
	col.position.y = 1.05
	add_child(col)

	# Триггерная зона касания игрока (радиус 1.25м)
	var touch_area = Area3D.new()
	touch_area.name = "TouchPlayerArea"
	touch_area.collision_layer = 0
	touch_area.collision_mask = 1 # Проверяем игрока
	var area_col = CollisionShape3D.new()
	var area_cyl = CylinderShape3D.new()
	area_cyl.radius = 1.25
	area_cyl.height = 2.4
	area_col.shape = area_cyl
	area_col.position.y = 1.1
	touch_area.add_child(area_col)
	add_child(touch_area)

	touch_area.body_entered.connect(func(b):
		if b == target_player:
			_on_catch_player()
	)

func _setup_model():
	var p_scene = load("res://level_fun_assets/partygoer/source/unzipped/scene.gltf")
	if not p_scene:
		return
	var inst = p_scene.instantiate()
	model_root = Node3D.new()
	model_root.name = "ModelRoot"
	add_child(model_root)
	model_root.add_child(inst)

	inst.scale = Vector3(23.5, 23.5, 23.5)
	inst.position = Vector3(0.0, 0.86, 0.0)

	mesh_instance = inst.find_child("Object_2", true, false) as MeshInstance3D
	if mesh_instance:
		var albedo_tex = load("res://level_fun_assets/partygoer/source/unzipped/textures/PartygoerMaterial_baseColor.png")
		var normal_tex = load("res://level_fun_assets/partygoer/source/unzipped/textures/PartygoerMaterial_normal.png")
		var shader = load("res://partygoer_wobble.gdshader")
		shader_mat = ShaderMaterial.new()
		shader_mat.shader = shader
		shader_mat.set_shader_parameter("albedo_texture", albedo_tex)
		shader_mat.set_shader_parameter("normal_texture", normal_tex)
		shader_mat.set_shader_parameter("walk_speed", 3.2)
		shader_mat.set_shader_parameter("arm_swing_amount", 0.5)
		shader_mat.set_shader_parameter("is_walking", 1.0)
		mesh_instance.material_override = shader_mat

func _setup_audio():
	daisy_audio = AudioStreamPlayer3D.new()
	daisy_audio.name = "DaisyBellAudio"
	var song_stream = load("res://level_fun_assets/daisy_bell.mp3")
	if song_stream is AudioStreamMP3:
		song_stream.loop = true
	daisy_audio.stream = song_stream
	daisy_audio.unit_size = 18.0
	daisy_audio.max_distance = 45.0
	daisy_audio.volume_db = 1.0
	daisy_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	daisy_audio.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(daisy_audio)
	# Бесконечный повтор: если песня завершилась, запускаем заново, ТОЛЬКО если сейчас не блэкаут!
	daisy_audio.finished.connect(func():
		if daisy_audio and not is_frozen_in_darkness:
			daisy_audio.play()
	)
	# Во время блэкаута аудио НЕ включается при спавне
	if not is_frozen_in_darkness:
		daisy_audio.play()

# Управление блэкаутом со стороны генератора уровня
func on_blackout_start():
	is_frozen_in_darkness = true
	was_activated_by_flashlight = false
	# Замолкает
	if daisy_audio:
		daisy_audio.stop()
	# Останавливается
	velocity = Vector3.ZERO
	if shader_mat:
		shader_mat.set_shader_parameter("is_walking", 0.0)
	if model_root:
		model_root.rotation.z = 0.0

func on_blackout_end():
	is_frozen_in_darkness = false
	was_activated_by_flashlight = false
	# Включается песня снова
	if daisy_audio and not daisy_audio.playing:
		daisy_audio.play()

func _physics_process(delta: float):
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0

	# 1. Логика темноты (блэкаут)
	if is_frozen_in_darkness:
		# Во время блэкаута тусовщик двигается ТОЛЬКО пока на него светит фонарик игрока!
		# Как только игрок отводит луч фонарика или выключает его — тусовщик немедленно снова застывает на месте.
		var lit_by_flashlight = _is_lit_by_player_flashlight()
		if lit_by_flashlight:
			is_chasing = true
		else:
			# Фонарик не светит: тусовщик полностью замирает как статуя
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			if shader_mat:
				shader_mat.set_shader_parameter("is_walking", 0.0)
			if model_root:
				model_root.rotation.z = 0.0
			return
		
		# Если двигается под лучом фонарика в темноте: остается абсолютно беззвучным
		if daisy_audio and daisy_audio.playing:
			daisy_audio.stop()

	# 2. Логика обычной видимости игрока при свете
	var has_sight = _can_see_player()
	if has_sight:
		is_chasing = true
	
	var cur_speed = chase_speed if is_chasing else move_speed
	var target_vel_xz = Vector3.ZERO

	if target_player and is_instance_valid(target_player):
		var dist_to_player = global_position.distance_to(target_player.global_position)
		if dist_to_player < 1.35:
			_on_catch_player()
			return

	if is_chasing and target_player and is_instance_valid(target_player):
		var dir = (target_player.global_position - global_position)
		dir.y = 0.0
		var dist = dir.length()
		if dist > 0.4:
			dir = dir.normalized()
			target_vel_xz = dir * cur_speed
			var target_rot = atan2(dir.x, dir.z)
			rotation.y = lerp_angle(rotation.y, target_rot, 7.0 * delta)
		else:
			_on_catch_player()
	else:
		# Патрулирование
		wander_timer -= delta
		if wander_timer <= 0.0 or is_on_wall():
			wander_timer = randf_range(2.5, 5.0)
			var angle = randf_range(0.0, TAU)
			wander_dir = Vector3(sin(angle), 0.0, cos(angle)).normalized()
		
		target_vel_xz = wander_dir * cur_speed
		var target_rot = atan2(wander_dir.x, wander_dir.z)
		rotation.y = lerp_angle(rotation.y, target_rot, 4.0 * delta)

	velocity.x = lerp(velocity.x, target_vel_xz.x, 6.0 * delta)
	velocity.z = lerp(velocity.z, target_vel_xz.z, 6.0 * delta)

	move_and_slide()

	# Обновление анимации шага и покачивания рук в шейдере
	var horiz_vel = Vector2(velocity.x, velocity.z).length()
	var moving_ratio = clamp(horiz_vel / move_speed, 0.0, 1.5)
	if shader_mat:
		shader_mat.set_shader_parameter("is_walking", 1.0 if moving_ratio > 0.1 else 0.0)
		shader_mat.set_shader_parameter("walk_speed", 3.2 * moving_ratio)
		shader_mat.set_shader_parameter("arm_swing_amount", 0.5)

	# Плавное покачивание (wobble) туловища влево-вправо без подпрыгиваний вверх-вниз
	if model_root and moving_ratio > 0.1:
		walk_cycle_time += delta * 3.5 * moving_ratio
		model_root.rotation.z = sin(walk_cycle_time) * 0.035
		model_root.position.y = 0.0
	elif model_root:
		model_root.rotation.z = lerp(model_root.rotation.z, 0.0, 5.0 * delta)
		model_root.position.y = 0.0

# Проверка: светит ли фонарик игрока прямо на тусовщика
func _is_lit_by_player_flashlight() -> bool:
	if not target_player or not is_instance_valid(target_player):
		return false
	
	# Фонарик включен?
	var f_light = target_player.get("flashlight_light")
	if not f_light or not f_light.visible:
		return false

	var cam = target_player.find_child("Camera3D", true, false)
	if not cam:
		cam = get_viewport().get_camera_3d()
	if not cam:
		return false

	var cam_pos = cam.global_position
	var monster_chest = global_position + Vector3(0.0, 1.2, 0.0)
	var to_monster = monster_chest - cam_pos
	var dist = to_monster.length()

	# Радиус действия фонарика (до 26 метров)
	if dist > 26.0:
		return false

	var cam_forward = -cam.global_transform.basis.z.normalized()
	var angle = rad_to_deg(cam_forward.angle_to(to_monster.normalized()))

	# Угол луча фонарика ~26 градусов (половина угла конуса ~15-18 градусов с запасом)
	if angle > 18.0:
		return false

	# Проверяем, не перекрыт ли луч стеной
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return false

	var query = PhysicsRayQueryParameters3D.create(cam_pos, monster_chest)
	query.exclude = [target_player.get_rid() if target_player is CollisionObject3D else RID()]
	var result = space_state.intersect_ray(query)

	if result.is_empty():
		return true
	if result.collider == self:
		return true

	return false

# Проверка прямой видимости (Raycast без стен)
func _can_see_player() -> bool:
	if not target_player or not is_instance_valid(target_player):
		return false
	
	var dist = global_position.distance_to(target_player.global_position)
	if dist > 30.0:
		return false

	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return false

	var from = global_position + Vector3(0.0, 1.5, 0.0)
	var to = target_player.global_position + Vector3(0.0, 1.5, 0.0)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self.get_rid()]

	var result = space_state.intersect_ray(query)
	if result.is_empty() or result.collider == target_player:
		return true

	return false

func _on_catch_player():
	if not target_player or not target_player.get("is_active"):
		return
	if target_player.get("is_infected_by_partygoer"):
		return
	print("[PARTYGOER] Touched player! Starting infection and notifying level...")
	
	# Уведомляем генератор уровня о факте касания (чтобы отслеживать исчезновение монстров при выходе из поля зрения)
	var parent_chunk = get_parent()
	var level_fun = parent_chunk.get_parent() if parent_chunk else null
	if level_fun and "was_player_touched" in level_fun:
		level_fun.was_player_touched = true

	# Запускаем отложенную инфекцию (игрок ходит 15-40 сек под звуки сердца и звона, затем падает)
	if target_player.has_method("start_partygoer_infection"):
		target_player.start_partygoer_infection()
	elif target_player.has_method("play_partygoer_transformation_cutscene"):
		target_player.play_partygoer_transformation_cutscene()
