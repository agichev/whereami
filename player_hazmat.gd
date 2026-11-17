extends CharacterBody3D

@export var speed: float = 3.2
@export var sprint_speed: float = 6.0
@export var rot_speed: float = 12.0
@export var mouse_sensitivity: float = 0.0025

@onready var visual_root: Node3D = $Visual
@onready var model_slot: Node3D = $Visual/ModelSlot
@onready var head_pivot: Node3D = $HeadPivot
@onready var camera: Camera3D = $HeadPivot/Camera3D
@onready var mannequin_mesh = find_child("Mannequin", true, false)

var anim_player: AnimationPlayer = null
var current_anim: String = ""

# Скелеты
var anim_skeleton: Skeleton3D = null
var char_skeleton: Skeleton3D = null

# Индексы костей головы и шеи
var neck_bone_idx: int = -1
var head_bone_idx: int = -1
var head_end_idx: int = -1

# Углы обзора камеры
var camera_pitch: float = 0.0 # Вверх/вниз
var player_yaw: float = 0.0    # Влево/вправо

# Реалистичное поведение ручной камеры (Handheld / Camcorder)
var mouse_input: Vector2 = Vector2.ZERO
var target_yaw: float = 0.0
var target_pitch: float = 0.0
var current_yaw: float = 0.0
var current_pitch: float = 0.0

var camera_noise_time: float = 0.0
var walk_bob_time: float = 0.0
var camera_roll: float = 0.0
var walk_weight: float = 0.0
var cur_head_pivot_pos: Vector3 = Vector3(0, 1.55, 0)

# Система зума и фокуса объектива (Found Footage Camcorder Zoom)
var base_fov: float = 70.0
var target_fov: float = 70.0
var current_fov: float = 70.0
const MIN_FOV: float = 24.0 # Максимальное приближение
const MAX_FOV: float = 70.0 # Стандартный обзор
var focus_blur_amount: float = 0.0
var is_zoomed: bool = false
var zoom_sound_timer: float = 0.0

var zoom_in_audio: AudioStreamPlayer = null
var zoom_out_audio: AudioStreamPlayer = null

# Скорость поворота мыши для Motion Blur
var mouse_angular_speed: Vector2 = Vector2.ZERO
var prev_player_yaw: float = 0.0
var prev_camera_pitch: float = 0.0

var head_shadow_mesh: MeshInstance3D = null
var is_active: bool = true
var is_in_cutscene: bool = false
var getup_audio_stream = preload("res://audio/player_getup.mp3")
var pause_menu_scene = preload("res://pause_menu.tscn")

# Звуковые эффекты шагов и дыхания (из Horror SFX)
var walk_step_sounds: Array = [
	preload("res://audio/step_walk_1.wav"),
	preload("res://audio/step_walk_2.wav"),
	preload("res://audio/step_walk_3.wav"),
	preload("res://audio/step_walk_4.wav"),
	preload("res://audio/step_walk_5.wav")
]

var run_step_sounds: Array = [
	preload("res://audio/step_run_1.wav"),
	preload("res://audio/step_run_2.wav"),
	preload("res://audio/step_run_3.wav"),
	preload("res://audio/step_run_4.wav"),
	preload("res://audio/step_run_5.wav"),
	preload("res://audio/step_run_6.wav"),
	preload("res://audio/step_run_7.wav")
]

var breath_slow_stream = preload("res://audio/breath_slow.wav")
var breath_fast_stream = preload("res://audio/breath_fast.wav")

var step_timer: float = 0.0
var step_interval_walk: float = 0.67
var step_interval_sprint: float = 0.33
var step_audio_player: AudioStreamPlayer3D = null
var breath_audio_player: AudioStreamPlayer = null
var heartbeat_audio_player: AudioStreamPlayer = null
var is_in_danger_chase: bool = false
var adrenaline_amount: float = 0.0 # 0.0 (покой) .. 1.0 (полный адреналин погони)

# Механика стамины (спринт короткий и конечный, скрытый от интерфейса)
const STAMINA_MAX: float = 4.0          # Длительность спринта до истощения: 4 секунды
const STAMINA_DRAIN: float = 1.0        # Расход в секунду при беге
const STAMINA_RECOVER_IDLE: float = 0.8 # Восстановление в покое (~5 сек до 100%)
const STAMINA_RECOVER_WALK: float = 0.4 # Восстановление при ходьбе в 2 раза медленнее (~10 сек)

var stamina: float = STAMINA_MAX
var is_exhausted: bool = false
var infinite_stamina: bool = false # Флаг бесконечной стамины (активируется после события с сущностью)

# Фонарик игрока и звук щелчка
var flashlight_stream = preload("res://audio/flashlight-on-off.mp3")
var flashlight_audio_player: AudioStreamPlayer = null
var flashlight_light: SpotLight3D = null      # Горячее пятно луча с тенями
var flashlight_spill: SpotLight3D = null      # Широкий тусклый ореол рассеянного света вокруг луча
var flashlight_mount: Node3D = null           # Крепление "в руке": фонарь смещен от объектива камеры
var flashlight_base_rot: Vector3 = Vector3.ZERO # Базовый прицел фонаря (луч сходится к центру взгляда)
var flashlight_sway: Vector2 = Vector2.ZERO   # Угловая инерция луча относительно головы (рад)
var flashlight_sway_vel: Vector2 = Vector2.ZERO
var flashlight_warmup: float = 0.0            # Разогрев лампы после щелчка, 0..1
var flashlight_flicker_t: float = 0.0
const FLASHLIGHT_ENERGY: float = 3.6
const FLASHLIGHT_SPILL_ENERGY: float = 0.35

# Пул случайных персонажей (обычные гражданские люди)
const CHARACTER_POOL: Array = [
	{ "name": "Character_01", "fbx": "res://characters_pool/Character_01.fbx", "tex": "res://characters_pool/Character_01.png" },
	{ "name": "Character_05", "fbx": "res://characters_pool/Character_05.fbx", "tex": "res://characters_pool/Character_05.png" },
	{ "name": "Character_10", "fbx": "res://characters_pool/Character_10.fbx", "tex": "res://characters_pool/Character_10.png" },
	{ "name": "Character_14", "fbx": "res://characters_pool/Character_14.fbx", "tex": "res://characters_pool/Character_14.png" },
	{ "name": "Character_29_Female", "fbx": "res://characters_pool/Character_29_Female.fbx", "tex": "res://characters_pool/Character_29_Female.png" },
	{ "name": "Character_30_Female", "fbx": "res://characters_pool/Character_30_Female.fbx", "tex": "res://characters_pool/Character_30_Female.png" },
	{ "name": "Character_Female_02", "fbx": "res://characters_pool/Character_Female_02.fbx", "tex": "res://characters_pool/Character_Female_02.png" },
	{ "name": "Character_Female_04", "fbx": "res://characters_pool/Character_Female_04.fbx", "tex": "res://characters_pool/Character_Female_04.png" }
]

# Маппинг всех костей: [ual_bone_a, ual_bone_b, char_bone_a, char_bone_b]
var limb_pairs: Array = [
	# Позвоночник
	["pelvis", "spine_01", "mixamorig_Hips", "mixamorig_Spine"],
	["spine_01", "spine_02", "mixamorig_Spine", "mixamorig_Spine1"],
	["spine_02", "spine_03", "mixamorig_Spine1", "mixamorig_Spine2"],
	["spine_03", "neck_01", "mixamorig_Spine2", "mixamorig_Neck"],
	["neck_01", "Head", "mixamorig_Neck", "mixamorig_Head"],
	
	# Ноги
	["thigh_l", "calf_l", "mixamorig_LeftUpLeg", "mixamorig_LeftLeg"],
	["calf_l", "foot_l", "mixamorig_LeftLeg", "mixamorig_LeftFoot"],
	["foot_l", "ball_l", "mixamorig_LeftFoot", "mixamorig_LeftToeBase"],
	
	["thigh_r", "calf_r", "mixamorig_RightUpLeg", "mixamorig_RightLeg"],
	["calf_r", "foot_r", "mixamorig_RightLeg", "mixamorig_RightFoot"],
	["foot_r", "ball_r", "mixamorig_RightFoot", "mixamorig_RightToeBase"],
	
	# Руки
	["upperarm_l", "lowerarm_l", "mixamorig_LeftArm", "mixamorig_LeftForeArm"],
	["lowerarm_l", "hand_l", "mixamorig_LeftForeArm", "mixamorig_LeftHand"],
	
	["upperarm_r", "lowerarm_r", "mixamorig_RightArm", "mixamorig_RightForeArm"],
	["lowerarm_r", "hand_r", "mixamorig_RightForeArm", "mixamorig_RightHand"]
]

var retarget_cache: Array = []

func _ready():
	# Добавляем в группу player для триггеров и интерактивных дверей
	add_to_group("player")

	# Захват мыши для управления от 1 лица
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# 1. Скрываем манекен UAL1
	if mannequin_mesh:
		mannequin_mesh.visible = false

	# 2. Выбираем случайного обычного человека из пула
	randomize()
	var char_data = CHARACTER_POOL[randi() % CHARACTER_POOL.size()]
	spawn_random_character(char_data)

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

	if char_skeleton:
		neck_bone_idx = char_skeleton.find_bone("mixamorig_Neck")
		head_bone_idx = char_skeleton.find_bone("mixamorig_Head")
		head_end_idx = char_skeleton.find_bone("mixamorig_HeadTop_End")
		setup_head_shadow()

	# 4. Настраиваем ретаргетинг
	setup_retargeting()

	# 5. Инициализируем звуковые эффекты шагов и дыхания
	setup_audio_players()

	# 6. Стартовая анимация
	play_anim("Idle")

	# Инициализация углов камеры
	target_yaw = rotation.y
	current_yaw = rotation.y
	target_pitch = 0.0
	current_pitch = 0.0

	# 7. Настройка фонарика игрока (изначально выключен)
	setup_flashlight()
	
	# 8. Подключение глобальных настроек
	var gs = game_settings.instance
	if gs:
		gs.settings_changed.connect(_on_settings_changed)
		_on_settings_changed()

var game_settings = preload("res://game_settings.gd")

func _on_settings_changed():
	var gs = game_settings.instance
	if not gs:
		return
	mouse_sensitivity = gs.mouse_sensitivity
	base_fov = gs.fov
	if not is_zoomed:
		target_fov = base_fov
	if camera and not is_zoomed:
		camera.fov = gs.fov
	var vhs = get_tree().root.find_child("VHSOverlay", true, false)
	if vhs:
		vhs.visible = gs.vhs_enabled

func setup_audio_players():
	step_audio_player = AudioStreamPlayer3D.new()
	step_audio_player.name = "StepAudioPlayer"
	step_audio_player.unit_size = 3.0
	step_audio_player.max_distance = 15.0
	step_audio_player.volume_db = -4.0
	add_child(step_audio_player)

	breath_audio_player = AudioStreamPlayer.new()
	breath_audio_player.name = "BreathAudioPlayer"
	breath_audio_player.stream = breath_slow_stream
	breath_audio_player.volume_db = -12.0
	add_child(breath_audio_player)
	breath_audio_player.play()

	# Звук учащенного сердцебиения при адреналине / погоне
	heartbeat_audio_player = AudioStreamPlayer.new()
	heartbeat_audio_player.name = "HeartbeatAudioPlayer"
	var hb_stream = load("res://audio/heartbeat.mp3") as AudioStream
	if hb_stream:
		hb_stream.loop = true
		heartbeat_audio_player.stream = hb_stream
	heartbeat_audio_player.volume_db = -80.0
	add_child(heartbeat_audio_player)
	heartbeat_audio_player.play()

	# Инициализация звуков зума камеры
	zoom_in_audio = AudioStreamPlayer.new()
	zoom_in_audio.name = "ZoomInAudio"
	var z_in_stream = load("res://audio/zoom_in.mp3") as AudioStream
	if z_in_stream:
		zoom_in_audio.stream = z_in_stream
	zoom_in_audio.volume_db = -4.0
	add_child(zoom_in_audio)

	zoom_out_audio = AudioStreamPlayer.new()
	zoom_out_audio.name = "ZoomOutAudio"
	var z_out_stream = load("res://audio/zoom_out.mp3") as AudioStream
	if z_out_stream:
		zoom_out_audio.stream = z_out_stream
	zoom_out_audio.volume_db = -4.0
	add_child(zoom_out_audio)

func _input(event: InputEvent):
	if not is_active:
		return
	
	# При клике ЛКМ в окно игры захватываем мышь, если она была освобождена
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
		# Зум объектива колесиком мыши (Wheel Up = Zoom In, Wheel Down = Zoom Out)
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not is_in_cutscene:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_step(true)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_step(false)

	# Вращение мыши (накапливаем для плавной ручной камеры с инерцией)
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			target_yaw -= event.relative.x * mouse_sensitivity
			target_pitch -= event.relative.y * mouse_sensitivity
			target_pitch = clamp(target_pitch, -deg_to_rad(85), deg_to_rad(85))

	# Меню паузы по Esc
	if event.is_action_pressed("pause"):
		open_pause_menu()

	# Свободное переключение фонарика по клавише F (латинская F / русская А)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F or event.physical_keycode == KEY_F or (event.unicode > 0 and (char(event.unicode).to_lower() == "f" or char(event.unicode).to_lower() == "а")):
			if not is_in_cutscene:
				toggle_flashlight()

		# Взаимодействие с дверью по клавише E (латинская E / русская У)
		if event.keycode == KEY_E or event.physical_keycode == KEY_E or (event.unicode > 0 and (char(event.unicode).to_lower() == "e" or char(event.unicode).to_lower() == "у")):
			if not is_in_cutscene:
				interact_with_door()

func zoom_step(zoom_in: bool):
	if zoom_in:
		if target_fov > MIN_FOV + 1.0:
			target_fov = max(MIN_FOV, target_fov - 13.0)
			is_zoomed = true
			focus_blur_amount = min(1.0, focus_blur_amount + 0.55) # Расфокус при резкой перестройке линзы
			
			# Если звук приближения уже играет, не прерываем его заново на каждом щелчке колесика!
			# А если играл звук отдаления, плавно переключаем на zoom_in
			if zoom_out_audio and zoom_out_audio.playing:
				zoom_out_audio.stop()
			if zoom_in_audio and not zoom_in_audio.playing:
				zoom_in_audio.play()
	else:
		if target_fov < base_fov - 1.0:
			target_fov = min(base_fov, target_fov + 13.0)
			if target_fov >= base_fov - 1.0:
				target_fov = base_fov
				is_zoomed = false
			focus_blur_amount = min(1.0, focus_blur_amount + 0.40)
			
			# Аналогично для отдаления: не перезапускаем трещащий звук поверх самого себя
			if zoom_in_audio and zoom_in_audio.playing:
				zoom_in_audio.stop()
			if zoom_out_audio and not zoom_out_audio.playing:
				zoom_out_audio.play()

func open_pause_menu():
	var ui = get_tree().root.find_child("UI", true, false)
	if not ui:
		return
	var existing = ui.find_child("PauseMenu", true, false)
	if existing:
		return
	var pause_menu = pause_menu_scene.instantiate()
	ui.add_child(pause_menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

func setup_head_shadow():
	# Создаем теневой меш напрямую в корне игрока с масштабом 1:1,
	# чтобы избежать масштабирования костей FBX-моделей
	head_shadow_mesh = MeshInstance3D.new()
	head_shadow_mesh.name = "HeadShadowProxy"
	var cap = CapsuleMesh.new()
	# Реалистичные анатомические пропорции человеческой головы (ширина ~17см, высота ~22см)
	cap.radius = 0.085
	cap.height = 0.22
	head_shadow_mesh.mesh = cap
	head_shadow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(head_shadow_mesh)

func spawn_random_character(char_data: Dictionary):
	var model_res = load(char_data["fbx"])
	if not model_res:
		return
	var char_inst = model_res.instantiate()
	model_slot.add_child(char_inst)

	# Находим меш и назначаем PSX текстуру с nearest фильтрацией и двусторонним рендерингом (cull_disabled)
	var tex = load(char_data["tex"])
	var mat = StandardMaterial3D.new()
	if tex:
		mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED # Внутренние стороны одежды теперь непрозрачные и закрашенные
	mat.roughness = 0.85

	for m in char_inst.find_children("*", "MeshInstance3D", true, false):
		m.material_override = mat

func setup_retargeting():
	if not anim_skeleton or not char_skeleton:
		return
	retarget_cache.clear()

	# Трансформация скелета относительно Visual/ModelSlot
	var skel_to_model = char_skeleton.transform
	var cur_node: Node = char_skeleton.get_parent()
	while cur_node and cur_node != model_slot:
		if cur_node is Node3D:
			skel_to_model = cur_node.transform * skel_to_model
		cur_node = cur_node.get_parent()
	var model_to_skel_basis = skel_to_model.basis.inverse()

	for item in limb_pairs:
		var u_a = anim_skeleton.find_bone(item[0])
		var u_b = anim_skeleton.find_bone(item[1])
		var c_a = char_skeleton.find_bone(item[2])
		var c_b = char_skeleton.find_bone(item[3])
		if u_a != -1 and u_b != -1 and c_a != -1 and c_b != -1:
			var c_p_idx = char_skeleton.get_bone_parent(c_a)
			var c_rest_dir = (char_skeleton.get_bone_global_rest(c_b).origin - char_skeleton.get_bone_global_rest(c_a).origin).normalized()
			var c_rest_basis = char_skeleton.get_bone_global_rest(c_a).basis
			retarget_cache.append([u_a, u_b, c_a, c_p_idx, c_rest_dir, c_rest_basis, model_to_skel_basis])

func _process(dt: float):
	if is_active and not is_in_cutscene:
		# Плавная интерполяция вращения (вес и инерция реальной ручной камеры)
		var yaw_weight = 1.0 - exp(-22.0 * dt)
		var pitch_weight = 1.0 - exp(-24.0 * dt)
		current_yaw = lerp_angle(current_yaw, target_yaw, yaw_weight)
		current_pitch = lerp_angle(current_pitch, target_pitch, pitch_weight)
		
		player_yaw = current_yaw
		camera_pitch = current_pitch
		rotation.y = player_yaw

		# Скорость движения персонажа
		var horiz_vel = Vector2(velocity.x, velocity.z).length()
		var move_factor = clamp(horiz_vel / sprint_speed, 0.0, 1.0)
		var is_moving = horiz_vel > 0.1 and is_on_floor()

		# Плавный вес перехода стойка <-> ходьба (walk_weight):
		# Никаких мгновенных скачков при начале или остановке шага
		var target_walk_weight = 1.0 if is_moving else 0.0
		var walk_trans_speed = 4.5 if is_moving else 3.5
		walk_weight = lerp(walk_weight, target_walk_weight, 1.0 - exp(-walk_trans_speed * dt))

		# Коэффициент приближения зума (1.0 = обычный обзор, 2.5+ = сильное приближение)
		var zoom_factor = base_fov / max(1.0, current_fov)
		# При приближении эффект шагов и тряски оптически усиливается
		var zoom_shake_mult = clamp(zoom_factor, 1.0, 3.2)

		# 1. Естественное медленное дыхание и живое покачивание ручной камеры в руках (как в Kane Pixels)
		camera_noise_time += dt * 1.2
		var idle_sway_pitch = (sin(camera_noise_time * 1.1) * 0.003 + sin(camera_noise_time * 2.3) * 0.0015) * zoom_shake_mult
		var idle_sway_yaw = (cos(camera_noise_time * 0.9) * 0.003) * zoom_shake_mult
		var idle_pos_y = sin(camera_noise_time * 1.0) * 0.005

		# 2. Мягкий инерционный крен при повороте (минимальный, горизонт ровный)
		var yaw_delta = (target_yaw - current_yaw)
		var target_roll = clamp(yaw_delta * 0.08, -deg_to_rad(1.2), deg_to_rad(1.2))
		
		# 3. Реалистичные шаги ручной камеры
		if is_moving:
			var bob_freq = 7.2 if (horiz_vel > 4.0) else 4.6
			walk_bob_time += dt * bob_freq
		else:
			walk_bob_time = fmod(walk_bob_time, TAU)

		# Плавная траектория шагов, взвешенная через walk_weight
		var raw_bob_x = sin(walk_bob_time * 0.5) * (0.015 + 0.015 * move_factor)
		var raw_bob_y = sin(walk_bob_time) * (0.012 + 0.018 * move_factor)
		var raw_walk_roll = sin(walk_bob_time * 0.5) * (deg_to_rad(0.5) + deg_to_rad(0.5) * move_factor) * zoom_shake_mult
		var raw_walk_pitch = cos(walk_bob_time) * (deg_to_rad(0.3) + deg_to_rad(0.4) * move_factor) * zoom_shake_mult

		var bob_offset_x = raw_bob_x * walk_weight
		var bob_offset_y = idle_pos_y * (1.0 - walk_weight) + raw_bob_y * walk_weight
		var walk_roll = raw_walk_roll * walk_weight
		var walk_pitch = raw_walk_pitch * walk_weight

		# Плавное сведение крена (горизонт стабилен)
		camera_roll = lerp_angle(camera_roll, target_roll + walk_roll, 1.0 - exp(-10.0 * dt))

		# Назначаем углы камере
		head_pivot.rotation.x = camera_pitch + idle_sway_pitch + walk_pitch
		head_pivot.rotation.y = idle_sway_yaw
		head_pivot.rotation.z = camera_roll
		
		# Смещение позиции камеры для шагов (мягкая интерполяция без рывков)
		if camera:
			camera.position.x = lerp(camera.position.x, bob_offset_x, 1.0 - exp(-10.0 * dt))
			camera.position.y = lerp(camera.position.y, bob_offset_y, 1.0 - exp(-10.0 * dt))

		# 4. Обновление FOV зума и расфокуса
		current_fov = lerp(current_fov, target_fov, 1.0 - exp(-8.0 * dt))
		if camera:
			camera.fov = current_fov

		# Плавная фокусировка объектива (focus blur затухает, пока линза наводится на резкость)
		focus_blur_amount = lerp(focus_blur_amount, 0.0, 1.0 - exp(-4.5 * dt))

		# 5. Расчет скорости вращения камеры для реалистичного Motion Blur
		var yaw_vel = (current_yaw - prev_player_yaw) / max(0.0001, dt)
		var pitch_vel = (current_pitch - prev_camera_pitch) / max(0.0001, dt)
		prev_player_yaw = current_yaw
		prev_camera_pitch = current_pitch

		# Вектор размытия (горизонтальное и вертикальное смещение пикселей)
		var target_mb = Vector2(-yaw_vel * 0.0028, pitch_vel * 0.0028)
		# Ограничиваем максимальную длину размытия
		if target_mb.length() > 0.04:
			target_mb = target_mb.normalized() * 0.04
		mouse_angular_speed = lerp(mouse_angular_speed, target_mb, 1.0 - exp(-25.0 * dt))

		# Передаем Motion Blur и Focus Blur в шейдер VHSOverlay
		var vhs_node = get_tree().root.find_child("VHSOverlay", true, false)
		if vhs_node and vhs_node.material is ShaderMaterial:
			vhs_node.material.set_shader_parameter("motion_blur_dir", mouse_angular_speed)
			vhs_node.material.set_shader_parameter("focus_blur", focus_blur_amount)

		# 6. Реалистичная работа фонарика: инерция луча, разогрев лампы, дрожь рук
		_update_flashlight(dt, yaw_vel, pitch_vel)

	if anim_skeleton and char_skeleton:
		for item in retarget_cache:
			var u_a: int = item[0]
			var u_b: int = item[1]
			var c_a: int = item[2]
			var c_p_idx: int = item[3]
			var c_rest_dir: Vector3 = item[4]
			var c_rest_basis: Basis = item[5]
			var model_to_skel_basis: Basis = item[6]

			# Направление кости в пространстве аниматора UAL1
			var u_cur_dir = (anim_skeleton.get_bone_global_pose(u_b).origin - anim_skeleton.get_bone_global_pose(u_a).origin).normalized()
			
			# Переводим в систему координат скелета персонажа
			var target_skel_dir = (model_to_skel_basis * u_cur_dir).normalized()

			# Поворот от начального направления кости модели к целевому направлению
			var q_align = Quaternion(c_rest_dir, target_skel_dir)
			var target_c_g = Basis(q_align) * c_rest_basis

			var parent_c_g = Basis()
			if c_p_idx != -1:
				parent_c_g = char_skeleton.get_bone_global_pose(c_p_idx).basis

			var local_target = parent_c_g.inverse() * target_c_g
			char_skeleton.set_bone_pose_rotation(c_a, local_target.get_rotation_quaternion())

		# Скрываем только голову, сохраняя шею нормальной
		if head_bone_idx != -1:
			char_skeleton.set_bone_pose_scale(head_bone_idx, Vector3(0.001, 0.001, 0.001))
			if head_end_idx != -1:
				char_skeleton.set_bone_pose_scale(head_end_idx, Vector3(0.001, 0.001, 0.001))

		# Позиционирование камеры от первого лица:
		if not is_in_cutscene and neck_bone_idx != -1:
			var neck_bone_g = char_skeleton.get_bone_global_pose(neck_bone_idx)
			var local_neck_pos = visual_root.transform * model_slot.transform * char_skeleton.transform * neck_bone_g.origin
			
			# Позиционируем теневой меш головы строго над шеей персонажа
			if head_shadow_mesh:
				head_shadow_mesh.position = Vector3(local_neck_pos.x, local_neck_pos.y + 0.11, local_neck_pos.z - 0.02)
			
			# При наклоне головы вниз выдвигаем камеру еще немного вперед по естественной дуге шеи
			var pitch_factor = clamp(-camera_pitch / deg_to_rad(85), 0.0, 1.0)
			
			# local_neck_pos.z — реальная текущая координата Z шеи в локальном пространстве игрока.
			# Смещаем камеру всегда строго перед шеей (на 0.12м впереди шеи + дополнительный вынос при взгляде вниз).
			var forward_z = local_neck_pos.z - 0.12 - (0.10 * pitch_factor)
			var up_y = local_neck_pos.y + 0.12 - (0.04 * pitch_factor)
			
			var target_head_pos = Vector3(0, up_y, forward_z)
			# Мягкое сглаживание положения опорной точки головы между анимациями стойки и шагов
			cur_head_pivot_pos = cur_head_pivot_pos.lerp(target_head_pos, 1.0 - exp(-14.0 * get_process_delta_time()))
			head_pivot.position = cur_head_pivot_pos

func play_getup_cutscene():
	is_in_cutscene = true
	is_active = false
	# Гарантируем, что курсор мыши скрыт во время всей анимации подъема
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Скрываем модельку персонажа и теневой меш на время падения/подъема
	visual_root.visible = false
	if head_shadow_mesh:
		head_shadow_mesh.visible = false
	
	# Синхронизируем player_yaw с текущим физическим rotation.y игрока
	player_yaw = rotation.y
	target_yaw = rotation.y
	current_yaw = rotation.y
	
	# Начальное состояние: человек лежит лицом вниз на мокром ковре
	# Камера у самого пола (Y=0.15м), смотрит прямо в пол (pitch=-80 град) с легким перекосом на бок (roll=25 град)
	head_pivot.position = Vector3(0, 0.15, 0)
	head_pivot.rotation.x = deg_to_rad(-80)
	head_pivot.rotation.y = 0.0
	head_pivot.rotation.z = deg_to_rad(25)
	camera_pitch = deg_to_rad(-80)
	target_pitch = deg_to_rad(-80)
	current_pitch = deg_to_rad(-80)
	
	# Сразу делаем экран абсолютно черным при старте подъема
	var vhs_mat: ShaderMaterial = null
	var vhs_node = get_tree().root.find_child("VHSOverlay", true, false)
	if vhs_node and vhs_node.material is ShaderMaterial:
		vhs_mat = vhs_node.material
		vhs_mat.set_shader_parameter("black_fade", 1.0)

	# Воспроизводим звук вздохов/подъема человека
	var audio = AudioStreamPlayer.new()
	audio.name = "GetUpAudio"
	audio.stream = getup_audio_stream
	audio.volume_db = 0.0
	add_child(audio)
	audio.play()
	
	# Фаза 1: 0.0с - 1.4с: Человек только пришел в сознание в темноте, начинает тяжело дышать.
	# Через короткую паузу (0.3с) глаза начинают открываться — экран плавно выходит из черноты на протяжении 2.0с!
	if vhs_mat:
		var tw_fade = create_tween()
		tw_fade.tween_interval(0.3)
		tw_fade.tween_method(func(val): vhs_mat.set_shader_parameter("black_fade", val), 1.0, 0.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(1.4).timeout
	
	# Фаза 2: 1.4с - 3.0с: Приподнимается на локтях / руках, оглядывает пол и стены
	var tw1 = create_tween().set_parallel(true)
	tw1.tween_property(head_pivot, "position:y", 0.65, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw1.tween_property(head_pivot, "rotation:x", deg_to_rad(-45), 1.6).set_trans(Tween.TRANS_SINE)
	tw1.tween_property(head_pivot, "rotation:z", deg_to_rad(-10), 1.6).set_trans(Tween.TRANS_SINE)
	await tw1.finished
	
	# Фаза 3: 3.0с - 4.8с: Резкий толчок и подъем на ноги в полный рост, выравнивание горизонта
	var tw2 = create_tween().set_parallel(true)
	tw2.tween_property(head_pivot, "position:y", 1.60, 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.tween_property(head_pivot, "rotation:x", deg_to_rad(0), 1.6).set_trans(Tween.TRANS_CUBIC)
	tw2.tween_property(head_pivot, "rotation:z", deg_to_rad(0), 1.6).set_trans(Tween.TRANS_SINE)
	await tw2.finished
	
	camera_pitch = 0.0
	head_pivot.position = Vector3(0, 1.55, 0)
	head_pivot.rotation = Vector3.ZERO
	target_pitch = 0.0
	current_pitch = 0.0

	# Фаза 4: Человек встал на ноги и огляделся. Теперь привязываем камеру к скелету ПЕРЕД показом меша
	if neck_bone_idx != -1 and char_skeleton:
		var neck_bone_g = char_skeleton.get_bone_global_pose(neck_bone_idx)
		var local_neck_pos = visual_root.transform * model_slot.transform * char_skeleton.transform * neck_bone_g.origin
		head_pivot.position = Vector3(0, local_neck_pos.y + 0.12, local_neck_pos.z - 0.12)
		if head_shadow_mesh:
			head_shadow_mesh.position = Vector3(local_neck_pos.x, local_neck_pos.y + 0.11, local_neck_pos.z - 0.02)

	# Скрываем голову в меше
	if head_bone_idx != -1 and char_skeleton:
		char_skeleton.set_bone_pose_scale(head_bone_idx, Vector3(0.001, 0.001, 0.001))
		if head_end_idx != -1:
			char_skeleton.set_bone_pose_scale(head_end_idx, Vector3(0.001, 0.001, 0.001))

	# Пропускаем один кадр для гарантии применения позы скелета перед включением видимости
	await get_tree().process_frame

	visual_root.visible = true
	if head_shadow_mesh:
		head_shadow_mesh.visible = true
	
	is_in_cutscene = false
	is_active = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(dt: float):
	if not is_active:
		velocity = Vector3.ZERO
		return
	
	if not is_on_floor():
		velocity.y -= 9.8 * dt

	var input_vec = Vector2.ZERO
	if Input.is_action_pressed("move_forward"): input_vec.y -= 1
	if Input.is_action_pressed("move_backward"): input_vec.y += 1
	if Input.is_action_pressed("move_left"): input_vec.x -= 1
	if Input.is_action_pressed("move_right"): input_vec.x += 1
	input_vec = input_vec.normalized()

	var wants_sprint = Input.is_action_pressed("sprint")
	var is_moving = input_vec.length() > 0.1
	
	# Обновление выносливости персонажа
	var can_sprint = false
	var is_sprinting = false

	if infinite_stamina:
		# Режим бесконечной стамины
		stamina = STAMINA_MAX
		is_exhausted = false
		can_sprint = wants_sprint and is_moving
		is_sprinting = can_sprint
	else:
		if is_exhausted:
			# Пока персонаж не отдышится хотя бы до 30%, спринтовать снова нельзя
			if stamina >= STAMINA_MAX * 0.35:
				is_exhausted = false
		
		can_sprint = wants_sprint and is_moving and not is_exhausted and stamina > 0.0
		is_sprinting = can_sprint
		
		if is_sprinting:
			stamina = max(0.0, stamina - STAMINA_DRAIN * dt)
			if stamina <= 0.0:
				is_exhausted = true
				is_sprinting = false
		else:
			if is_moving:
				# Восстановление при ходьбе в 2 раза медленнее, чем на месте
				stamina = min(STAMINA_MAX, stamina + STAMINA_RECOVER_WALK * dt)
			else:
				# Восстановление стоя на месте
				stamina = min(STAMINA_MAX, stamina + STAMINA_RECOVER_IDLE * dt)

	var cur_speed = sprint_speed if is_sprinting else speed
	# Если игрок приблизил камеру (зум), он движется в 2 раза медленнее
	if is_zoomed:
		cur_speed *= 0.5

	# Движение в направлении взгляда персонажа (global transform basis)
	var move_dir = (transform.basis * Vector3(input_vec.x, 0, input_vec.y)).normalized()

	if move_dir.length() > 0.1:
		velocity.x = move_dir.x * cur_speed
		velocity.z = move_dir.z * cur_speed

		# Авто-подъем на небольшие ступени и выступы бордюров (до 0.38м)
		_snap_up_stairs_check(move_dir, cur_speed, dt)

		if is_sprinting:
			play_anim("Sprint")
		else:
			play_anim("Walk")
	else:
		velocity.x = move_toward(velocity.x, 0, cur_speed)
		velocity.z = move_toward(velocity.z, 0, cur_speed)
		play_anim("Idle")

	move_and_slide()

	# Обработка звуков шагов и динамического дыхания
	handle_audio_fx(dt, is_sprinting)

# Плавный подъем на легкие выступы, порожки и тротуарные бордюры (высотой до 0.38м)
const MAX_STEP_HEIGHT: float = 0.38
func _snap_up_stairs_check(move_dir: Vector3, cur_speed: float, dt: float):
	if not is_on_floor():
		return

	# Проверяем, есть ли перед ногами препятствие высотой до 0.38м
	var space_state = get_world_3d().direct_space_state
	var my_foot = global_position + Vector3(0, 0.06, 0)
	var check_forward = move_dir.normalized() * 0.45

	# Луч 1: низкий луч у самой земли (втыкается в бордюр)
	var low_query = PhysicsRayQueryParameters3D.create(my_foot, my_foot + check_forward)
	low_query.exclude = [self.get_rid()]
	var low_hit = space_state.intersect_ray(low_query)

	if not low_hit.is_empty():
		# Луч 2: высокий луч на высоте допустимой ступени (пролетает над бордюром)
		var high_pos = my_foot + Vector3(0, MAX_STEP_HEIGHT, 0)
		var high_query = PhysicsRayQueryParameters3D.create(high_pos, high_pos + check_forward)
		high_query.exclude = [self.get_rid()]
		var high_hit = space_state.intersect_ray(high_query)

		# Если на уровне ног есть препятствие, а вверху свободно — перед нами выступ/бордюр!
		if high_hit.is_empty():
			# Пускаем вертикальный луч вниз, чтобы узнать точную высоту верха бордюра
			var down_start = high_pos + check_forward
			var down_end = my_foot + check_forward
			var down_query = PhysicsRayQueryParameters3D.create(down_start, down_end)
			down_query.exclude = [self.get_rid()]
			var down_hit = space_state.intersect_ray(down_query)

			if not down_hit.is_empty():
				var step_h = down_hit.position.y - global_position.y
				if step_h > 0.02 and step_h <= MAX_STEP_HEIGHT + 0.05:
					# Мягко приподнимаем персонажа на высоту выступа
					global_position.y = lerp(global_position.y, down_hit.position.y + 0.04, 20.0 * dt)
					velocity.y = 0.0

var last_walk_idx: int = -1
var last_run_idx: int = -1

func handle_audio_fx(dt: float, is_sprinting: bool):
	if not is_active or is_in_cutscene:
		if breath_audio_player and breath_audio_player.playing:
			breath_audio_player.stop()
		if heartbeat_audio_player and heartbeat_audio_player.playing:
			heartbeat_audio_player.stop()
		return

	# 0. Адреналин и отчетливое сердцебиение при опасности / погоне
	var target_adrenaline = 1.0 if is_in_danger_chase else 0.0
	var adren_speed = 3.0 if is_in_danger_chase else 0.8
	adrenaline_amount = lerp(adrenaline_amount, target_adrenaline, 1.0 - exp(-adren_speed * dt))

	if heartbeat_audio_player:
		if not heartbeat_audio_player.playing:
			heartbeat_audio_player.play()
		if adrenaline_amount > 0.02:
			# Отчетливое, тревожное глухое биение сердца (от -24dB до -4dB)
			var hb_vol = lerp(-32.0, -4.0, adrenaline_amount)
			heartbeat_audio_player.volume_db = hb_vol
			heartbeat_audio_player.pitch_scale = lerp(0.95, 1.25, adrenaline_amount) # Ускорение пульса от страха
		else:
			heartbeat_audio_player.volume_db = -80.0

	# 1. Шаги
	var horiz_vel = Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horiz_vel > 0.5:
		step_timer += dt
		var interval = step_interval_sprint if is_sprinting else step_interval_walk
		if step_timer >= interval:
			step_timer = 0.0
			play_footstep(is_sprinting)
	else:
		step_timer = step_interval_walk * 0.85 # Быстрый шаг при возобновлении движения

	# 2. Дыхание согласовано с уровнем стамины
	if breath_audio_player:
		if not breath_audio_player.playing:
			breath_audio_player.play()
		
		# Если стамина опустилась ниже 40% или персонаж полностью выдохся — тяжелое/учащенное дыхание
		if stamina < STAMINA_MAX * 0.45 or is_exhausted:
			if breath_audio_player.stream != breath_fast_stream:
				breath_audio_player.stream = breath_fast_stream
				breath_audio_player.volume_db = -8.0
				breath_audio_player.play()
		else:
			if breath_audio_player.stream != breath_slow_stream:
				breath_audio_player.stream = breath_slow_stream
				breath_audio_player.volume_db = -13.0
				breath_audio_player.play()

func play_footstep(is_sprinting: bool):
	if not step_audio_player:
		return
	var sound_pool = run_step_sounds if is_sprinting else walk_step_sounds
	if sound_pool.is_empty():
		return
	
	var idx = randi() % sound_pool.size()
	if is_sprinting:
		if idx == last_run_idx and sound_pool.size() > 1:
			idx = (idx + 1) % sound_pool.size()
		last_run_idx = idx
	else:
		if idx == last_walk_idx and sound_pool.size() > 1:
			idx = (idx + 1) % sound_pool.size()
		last_walk_idx = idx

	step_audio_player.stream = sound_pool[idx]
	step_audio_player.pitch_scale = randf_range(0.92, 1.06) if is_sprinting else randf_range(0.85, 0.95)
	step_audio_player.volume_db = -3.0 if is_sprinting else -5.0
	step_audio_player.play()

func play_anim(anim_name: String):
	if current_anim == anim_name:
		return
	if anim_player and anim_player.has_animation(anim_name):
		current_anim = anim_name
		anim_player.play(anim_name, 0.2)

func setup_flashlight():
	# Звук включения/выключения фонарика
	flashlight_audio_player = AudioStreamPlayer.new()
	flashlight_audio_player.name = "FlashlightAudio"
	flashlight_audio_player.stream = flashlight_stream
	flashlight_audio_player.volume_db = 2.0
	add_child(flashlight_audio_player)

	# Фонарь держат в правой руке, а смотрит игрок глазами:
	# источник света смещен от объектива камеры, поэтому пятно никогда не совпадает
	# с геометрическим центром кадра (как у настоящего ручного фонаря).
	flashlight_mount = Node3D.new()
	flashlight_mount.name = "FlashlightMount"
	flashlight_mount.position = Vector3(0.17, -0.14, -0.05)
	# Доворачиваем фонарь на точку в ~7 м впереди, чтобы луч сходился к центру взгляда
	flashlight_base_rot = Vector3(atan2(0.14, 7.0), atan2(0.17, 7.0), 0.0)
	flashlight_mount.rotation = flashlight_base_rot
	camera.add_child(flashlight_mount)

	# 1. Основной луч: теплое пятно (вольфрам/теплый LED) с мягким краем и полутенью
	flashlight_light = SpotLight3D.new()
	flashlight_light.name = "Flashlight"
	flashlight_light.light_color = Color(1.0, 0.94, 0.82)
	flashlight_light.light_energy = 0.0 # Реальная яркость выставляется при разогреве лампы
	flashlight_light.light_specular = 0.7 # Блик на мокром полу и металле остается, но не "пластиковый"
	flashlight_light.spot_range = 26.0
	flashlight_light.spot_angle = 26.0
	flashlight_light.spot_attenuation = 1.3
	flashlight_light.spot_angle_attenuation = 1.8 # Плавный край пятна вместо резкой границы конуса
	flashlight_light.shadow_enabled = true
	flashlight_light.shadow_bias = 0.02 # Меньше отрыва теней от предметов
	flashlight_light.shadow_normal_bias = 1.2
	flashlight_light.shadow_blur = 1.6
	flashlight_light.light_angular_distance = 2.5 # Полутень от реального размера отражателя
	flashlight_light.visible = false # Изначально выключен
	flashlight_mount.add_child(flashlight_light)

	# 2. Ореол: широкий тусклый свет, который настоящий фонарь рассеивает вокруг пятна
	flashlight_spill = SpotLight3D.new()
	flashlight_spill.name = "FlashlightSpill"
	flashlight_spill.light_color = Color(0.92, 0.93, 1.0) # Холоднее: рассеяние на пыли и парах
	flashlight_spill.light_energy = 0.0
	flashlight_spill.light_specular = 0.0
	flashlight_spill.spot_range = 14.0
	flashlight_spill.spot_angle = 62.0
	flashlight_spill.spot_attenuation = 1.9
	flashlight_spill.spot_angle_attenuation = 1.2
	flashlight_spill.shadow_enabled = false
	flashlight_spill.visible = false
	flashlight_mount.add_child(flashlight_spill)

# Ежекадровое поведение фонарика: инерция луча, разогрев, дрожь уставшей руки
func _update_flashlight(dt: float, yaw_vel: float, pitch_vel: float):
	if not flashlight_mount or not flashlight_light:
		return

	var is_on = flashlight_light.visible

	# 1. Разогрев: щелчок не дает мгновенную яркость (нить лампы / драйвер LED)
	flashlight_warmup = move_toward(flashlight_warmup, 1.0 if is_on else 0.0, dt * (8.0 if is_on else 14.0))
	if flashlight_spill:
		flashlight_spill.visible = is_on and flashlight_warmup > 0.01

	# 2. Инерция: фонарь в руке отстает от поворота головы, луч "плывет" за взглядом
	var inertia_target = Vector2(
		clampf(-yaw_vel * 0.05, -0.06, 0.06),
		clampf(-pitch_vel * 0.05, -0.06, 0.06)
	)
	var spring_accel = (inertia_target - flashlight_sway) * 90.0 - flashlight_sway_vel * 18.0
	flashlight_sway_vel += spring_accel * dt
	flashlight_sway += flashlight_sway_vel * dt

	# 3. Дрожь рук: слабая в покое, сильнее при усталости и во время погони
	var fatigue = clampf(1.0 - stamina / STAMINA_MAX, 0.0, 1.0)
	var wobble = 1.0 + fatigue * 2.0 + adrenaline_amount * 0.8
	var idle_yaw = sin(camera_noise_time * 1.15) * 0.006 + sin(camera_noise_time * 2.7) * 0.0022
	var idle_pitch = cos(camera_noise_time * 0.95) * 0.005 + sin(camera_noise_time * 3.1) * 0.0018
	var breath = sin(camera_noise_time * 1.9) * 0.0018 * (1.0 + adrenaline_amount)
	var droop = deg_to_rad(4.0) * fatigue # Уставшая рука опускает ствол фонаря вниз

	flashlight_mount.rotation = flashlight_base_rot + Vector3(
		(idle_pitch + breath) * wobble + flashlight_sway.y - droop,
		idle_yaw * wobble + flashlight_sway.x,
		flashlight_sway.x * 0.35 # Легкий крен при повороте кисти
	)

	# 4. Нестабильность питания и нагрева: легкое живое мерцание, без хоррор-стробоскопа
	flashlight_flicker_t += dt
	var flicker = 1.0 + sin(flashlight_flicker_t * 31.0) * 0.010 + sin(flashlight_flicker_t * 7.7) * 0.018
	var ramp = smoothstep(0.0, 1.0, flashlight_warmup)
	flashlight_light.light_energy = FLASHLIGHT_ENERGY * ramp * flicker
	if flashlight_spill:
		flashlight_spill.light_energy = FLASHLIGHT_SPILL_ENERGY * ramp * flicker

func interact_with_door():
	if not camera:
		return
	var space_state = get_world_3d().direct_space_state
	var from = camera.global_position
	var to = from - camera.global_transform.basis.z * 3.2 # Дистанция 3.2м вперед
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		if collider:
			var door_p = collider.get_meta("door_parent", null)
			if door_p and is_instance_valid(door_p) and door_p.has_method("toggle"):
				door_p.toggle()
				return
			# Также проверяем родителей если метаданные были на дочернем объекте
			var parent_node = collider.get_parent()
			while parent_node:
				if parent_node.has_method("toggle"):
					parent_node.toggle()
					return
				parent_node = parent_node.get_parent()

# Единая точка включения/выключения фонаря (звук щелчка только при реальном переключении)
func _set_flashlight_enabled(on: bool):
	if not flashlight_light:
		return
	if flashlight_light.visible == on:
		return
	flashlight_light.visible = on
	if flashlight_audio_player:
		flashlight_audio_player.play()

func toggle_flashlight():
	if not flashlight_light:
		return
	_set_flashlight_enabled(not flashlight_light.visible)

func enable_flashlight_and_infinite_stamina():
	infinite_stamina = true
	is_in_danger_chase = true
	_set_flashlight_enabled(true)

func enable_infinite_stamina_only():
	infinite_stamina = true
	is_in_danger_chase = true

func disable_infinite_stamina_only():
	infinite_stamina = false
	is_in_danger_chase = false

func disable_flashlight_and_reset_stamina():
	infinite_stamina = false
	is_in_danger_chase = false
	_set_flashlight_enabled(false)
