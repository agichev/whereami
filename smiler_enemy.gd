class_name SmilerEnemy
extends CharacterBody3D

# Smiler (Nextbot) — 2D спрайт жуткой улыбки и глаз, преследующий игрока в темноте на Уровне 1
@export var speed: float = 4.2
@export var kill_distance: float = 1.3

var target_player: CharacterBody3D = null
var sprite: Sprite3D = null
var point_light: OmniLight3D = null
var is_dead: bool = false

# Таймер удержания луча фонарика на монстре (нужно 3 секунды)
var flashlight_focused_time: float = 0.0
const REQUIRED_FOCUS_TIME: float = 3.0

var dissolve_alpha: float = 1.0
var is_dissolving: bool = false
var dissolve_speed: float = 1.5

# Звуки
var hum_audio_player: AudioStreamPlayer3D = null
var death_triggered: bool = false

func _ready():
	add_to_group("smiler")
	_setup_visual()
	_setup_collision()
	_setup_audio()

func _setup_visual():
	# Билборд спрайт с текстурой smiler
	sprite = Sprite3D.new()
	sprite.name = "SmilerSprite"
	var tex = load("res://smiler_face_transparent.png")
	if not tex:
		tex = load("res://smiler_face.png")
	sprite.texture = tex
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.pixel_size = 0.0028 # Подходящий размер лица в рост человека (~1.4м ширина)
	sprite.shaded = false # Не зависит от внешнего освещения (unshaded)
	sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	sprite.no_depth_test = false
	sprite.position = Vector3(0, 1.3, 0) # На высоте глаз/груди
	add_child(sprite)

	# Свечение лица в темноте (жуткий слабый белый ореол вокруг зубов и глаз)
	point_light = OmniLight3D.new()
	point_light.name = "SmilerGlow"
	point_light.light_color = Color(0.9, 0.95, 1.0)
	point_light.light_energy = 0.9
	point_light.omni_range = 3.5
	point_light.omni_attenuation = 1.6
	point_light.shadow_enabled = false
	point_light.position = Vector3(0, 1.3, 0)
	add_child(point_light)

func _setup_collision():
	var col = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 0.55
	col.shape = sphere
	col.position = Vector3(0, 1.2, 0)
	add_child(col)

func _setup_audio():
	# Зловещее тихое жужжание/статический треск при приближении
	hum_audio_player = AudioStreamPlayer3D.new()
	hum_audio_player.name = "SmilerStaticHum"
	var s_res = load("res://audio/Creepy_ambience_3.wav")
	if s_res:
		hum_audio_player.stream = s_res
		hum_audio_player.volume_db = -4.0
		hum_audio_player.unit_size = 3.0
		hum_audio_player.max_distance = 18.0
		hum_audio_player.autoplay = true
		add_child(hum_audio_player)

func start_dissolve():
	is_dissolving = true
	is_dead = true

func _physics_process(delta: float):
	if is_dissolving:
		dissolve_alpha = max(0.0, dissolve_alpha - delta * dissolve_speed)
		if sprite:
			sprite.modulate.a = dissolve_alpha
		if point_light:
			point_light.light_energy = 0.9 * dissolve_alpha
		if dissolve_alpha <= 0.0:
			queue_free()
		return

	if not target_player or not is_instance_valid(target_player):
		return

	var cam = target_player.find_child("Camera3D", true, false)
	if not cam:
		return

	# Проверяем, видит ли игрок Смайлера (в поле зрения камеры + прямая видимость без стен)
	var is_visible_to_player = _check_player_sees_me(cam)

	# "Пока игрок не видит смайлера, тот не двигается, нападение из-за стены невозможно"
	if is_visible_to_player:
		# Двигаемся к игроку
		var to_player = target_player.global_position - global_position
		to_player.y = 0.0
		var dist = to_player.length()

		if dist > kill_distance:
			var dir = to_player.normalized()
			velocity.x = dir.x * speed
			velocity.z = dir.z * speed
			velocity.y = 0.0
			move_and_slide()
		else:
			# Коснулся игрока — смерть!
			_trigger_kill_player()
	else:
		# Стоит на месте в темноте, ожидая взгляда
		velocity = Vector3.ZERO
		move_and_slide()

	# Проверяем наведение фонарика на Смайлера:
	# "плавно рассеется если навестись на них фонариком и подержать 3 секунды"
	_check_flashlight_focus(cam, delta)

func _check_player_sees_me(cam: Camera3D) -> bool:
	# 1. Проверяем расстояние (до 30 метров)
	var eye_pos = cam.global_position
	var my_eye = global_position + Vector3(0, 1.3, 0)
	var to_smiler = my_eye - eye_pos
	var dist = to_smiler.length()
	if dist > 32.0:
		return false

	# 2. Проверяем угол конуса зрения игрока (FOV ~75-80 градусов)
	var cam_fwd = -cam.global_transform.basis.z.normalized()
	var dir_to_smiler = to_smiler.normalized()
	var dot = cam_fwd.dot(dir_to_smiler)
	# cos(50 градусов) ~ 0.64 (в пределах экрана)
	if dot < 0.60:
		return false

	# 3. Raycast: проверяем, что между камерой и смайлером нет стены
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(eye_pos, my_eye)
	query.exclude = [target_player, self]
	var hit = space_state.intersect_ray(query)
	if not hit.is_empty():
		# Луч уперся в стену/препятствие
		return false

	return true

func _check_flashlight_focus(cam: Camera3D, delta: float):
	if not target_player:
		return

	# Проверяем, включен ли фонарик у игрока
	var fl = target_player.get("flashlight_light")
	if not fl or not fl.visible:
		flashlight_focused_time = max(0.0, flashlight_focused_time - delta * 1.5)
		return

	# Проверяем, направлен ли центр луча фонарика на монстра
	var eye_pos = cam.global_position
	var my_eye = global_position + Vector3(0, 1.3, 0)
	var to_smiler = my_eye - eye_pos
	var dist = to_smiler.length()
	if dist > fl.spot_range:
		flashlight_focused_time = max(0.0, flashlight_focused_time - delta * 1.5)
		return

	var cam_fwd = -cam.global_transform.basis.z.normalized()
	var dir = to_smiler.normalized()
	var dot = cam_fwd.dot(dir)

	# Угол фонарика spot_angle = 36 градусов, половина угла 18 градусов -> cos(18) ~ 0.95
	# Если луч фонарика наведен на монстра и нет преград:
	if dot > 0.94:
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(eye_pos, my_eye)
		query.exclude = [target_player, self]
		var hit = space_state.intersect_ray(query)
		if hit.is_empty():
			flashlight_focused_time += delta
			# Легкое мерцание / реакция на свет
			var flicker = randf_range(0.7, 1.2)
			sprite.modulate = Color(flicker, flicker, flicker, 1.0 - (flashlight_focused_time / REQUIRED_FOCUS_TIME) * 0.4)

			if flashlight_focused_time >= REQUIRED_FOCUS_TIME:
				start_dissolve()
			return

	flashlight_focused_time = max(0.0, flashlight_focused_time - delta * 1.2)
	sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _trigger_kill_player():
	if death_triggered or is_dead:
		return
	death_triggered = true

	# Блокируем игрока
	target_player.is_active = false
	target_player.velocity = Vector3.ZERO

	# Проигрываем jumpscare видео и возвращаем в Главное Меню
	var ui = get_tree().root.find_child("UI", true, false)
	if not ui:
		get_tree().reload_current_scene()
		return

	var vp = VideoStreamPlayer.new()
	vp.name = "SmilerDeathJumpscare"
	vp.expand = true
	vp.anchor_right = 1.0
	vp.anchor_bottom = 1.0
	vp.stream = load("res://death_jumpscare.ogv")
	vp.volume_db = 8.0
	vp.z_index = 100
	ui.add_child(vp)

	vp.finished.connect(func():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().reload_current_scene()
	)
	vp.play()
