extends Node3D

# Наблюдатель Уровня 89 (The Shadow Observer)
# Полностью черная моделька человека/hazmat, стоящая неподвижно вдалеке в тумане.
# Если игрок начинает идти в ее сторону или подходит ближе определенной дистанции — растворяется в тумане и исчезает.

var player: Node3D = null
var spawn_pos: Vector3 = Vector3.ZERO
var initial_dist_to_player: float = 0.0
var min_observed_distance: float = 999.0
var is_fading: bool = false
var black_mat: StandardMaterial3D = null
var meshes: Array[MeshInstance3D] = []

func _ready():
	# Создаем абсолютно черный матовый материал силуэта
	black_mat = StandardMaterial3D.new()
	black_mat.albedo_color = Color(0.01, 0.01, 0.01, 1.0)
	black_mat.roughness = 1.0
	black_mat.metallic = 0.0
	black_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Применяем черный материал ко всем мешам модельки
	for child in find_children("*", "MeshInstance3D"):
		var mi = child as MeshInstance3D
		mi.material_override = black_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		meshes.append(mi)

	# Запускаем анимацию дыхания / покоя (Idle)
	for child in find_children("*", "AnimationPlayer"):
		var ap = child as AnimationPlayer
		if ap.has_animation("Idle"):
			ap.play("Idle")
			break

	# Ищем игрока в сцене
	player = get_tree().root.find_child("HazmatPlayer", true, false)
	if player:
		spawn_pos = global_position
		initial_dist_to_player = global_position.distance_to(player.global_position)
		min_observed_distance = initial_dist_to_player
		look_at_player_yaw()

func look_at_player_yaw():
	if not player:
		return
	var dir = player.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		rotation.y = atan2(dir.x, dir.z)

func _process(delta: float):
	if is_fading or not player:
		return

	# Всегда смотрит прямо на игрока
	look_at_player_yaw()

	var cur_dist = global_position.distance_to(player.global_position)

	# Проверяем движение игрока в сторону наблюдателя:
	# Если игрок приблизился на 3.5 метра от дистанции спавна или подошел ближе чем на 22 метра — исчезаем
	if cur_dist < min_observed_distance:
		min_observed_distance = cur_dist

	var moved_towards_dist = initial_dist_to_player - cur_dist
	if moved_towards_dist > 3.0 or cur_dist < 22.0:
		fade_out_and_destroy()

func fade_out_and_destroy():
	if is_fading:
		return
	is_fading = true

	# Плавное растворение в тумане за 0.8 сек
	var tw = create_tween()
	tw.tween_property(black_mat, "albedo_color:a", 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func():
		queue_free()
	)
