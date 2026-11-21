class_name LevelRun
extends Node3D

# Level "!" (Run for your life!)
# Бесконечный 5-километровый прямой больничный коридор, освещенный тревожным мигающим красным светом
# и знаками EXIT. Сзади гонятся сущности: Smiler, Bacteria, Hazmat NPC. В конце (5000м) — открытая дверь выхода.

const LEVEL_LENGTH_METERS: float = 5000.0
const CORRIDOR_WIDTH: float = 3.2
const CORRIDOR_HEIGHT: float = 3.0
const SEGMENT_LENGTH: float = 16.0
const DOOR_SPACING: float = 8.0 # Двери по бокам каждые 8 метров

var carpet_mat: StandardMaterial3D
var wall_mat: StandardMaterial3D
var ceil_mat: StandardMaterial3D
var exit_sign_mat: StandardMaterial3D
var exit_box_mat: StandardMaterial3D
var red_light_mat: StandardMaterial3D

var active_segments: Dictionary = {}
var player: CharacterBody3D = null

# Сущности в погоне
var pack_bacteria: CharacterBody3D = null
var pack_hazmat: CharacterBody3D = null
var pack_smiler: CharacterBody3D = null

# Звуки
var alarm1_player: AudioStreamPlayer = null
var alarm2_player: AudioStreamPlayer = null

# Дверь выхода в конце коридора
var exit_door: InteractiveDoor = null
var is_completed: bool = false

signal player_reached_exit

func _ready():
	_setup_materials()
	_setup_alarms()

func _setup_materials():
	carpet_mat = StandardMaterial3D.new()
	carpet_mat.albedo_texture = load("res://level_run_assets/run_carpet.png")
	carpet_mat.uv1_scale = Vector3(1.0, 4.0, 1.0)
	carpet_mat.roughness = 0.95

	wall_mat = StandardMaterial3D.new()
	wall_mat.albedo_texture = load("res://level_run_assets/run_wall.png")
	wall_mat.uv1_scale = Vector3(4.0, 1.0, 1.0)
	wall_mat.roughness = 0.85

	ceil_mat = StandardMaterial3D.new()
	ceil_mat.albedo_texture = load("res://level_run_assets/run_ceiling.png")
	ceil_mat.uv1_scale = Vector3(1.0, 4.0, 1.0)
	ceil_mat.roughness = 0.9

	exit_sign_mat = StandardMaterial3D.new()
	exit_sign_mat.albedo_texture = load("res://level_run_assets/exit_sign.png")
	exit_sign_mat.emission_enabled = true
	exit_sign_mat.emission = Color(1.0, 0.1, 0.1)
	exit_sign_mat.emission_energy_multiplier = 4.0

	exit_box_mat = StandardMaterial3D.new()
	exit_box_mat.albedo_color = Color(0.1, 0.02, 0.02)
	exit_box_mat.roughness = 0.5

	red_light_mat = StandardMaterial3D.new()
	red_light_mat.albedo_color = Color(0.9, 0.1, 0.1)
	red_light_mat.emission_enabled = true
	red_light_mat.emission = Color(1.0, 0.15, 0.15)
	red_light_mat.emission_energy_multiplier = 3.5

func _setup_alarms():
	alarm1_player = AudioStreamPlayer.new()
	alarm1_player.name = "DeafeningAlarm"
	alarm1_player.stream = load("res://audio/deafening_alarm.mp3")
	alarm1_player.volume_db = 2.0
	alarm1_player.finished.connect(func(): if is_instance_valid(alarm1_player): alarm1_player.play())
	add_child(alarm1_player)

	alarm2_player = AudioStreamPlayer.new()
	alarm2_player.name = "NavalAlarm"
	alarm2_player.stream = load("res://audio/naval_alarm.mp3")
	alarm2_player.volume_db = -1.0
	alarm2_player.finished.connect(func(): if is_instance_valid(alarm2_player): alarm2_player.play())
	add_child(alarm2_player)

func start_level(target_player: CharacterBody3D):
	player = target_player
	is_completed = false

	# Запуск сирен
	if alarm1_player:
		alarm1_player.play()
	if alarm2_player:
		alarm2_player.play()

	# Стартовая генерация сегментов вокруг начала (Z = 0)
	_update_streaming(0.0)

	# Спавн сущностей сзади игрока
	_spawn_chasing_horde()

	# Финишный тупик на отметке -5000м с открытой дверью выхода
	_build_exit_barrier()

func _exit_tree():
	if alarm1_player:
		alarm1_player.stop()
	if alarm2_player:
		alarm2_player.stop()

func _process(_delta: float):
	if not player or is_completed:
		return

	var pz = player.global_position.z
	_update_streaming(pz)

	# Логика орды сущностей: они постоянно держатся позади игрока на расстоянии 8-16 метров,
	# ускоряются, если игрок пытается остановиться, и ловят при замедлении.
	_process_horde(pz)

	# Проверка достижения выхода (Z <= -LEVEL_LENGTH_METERS + 2.0)
	if pz <= -LEVEL_LENGTH_METERS + 2.5 and not is_completed:
		is_completed = true
		player_reached_exit.emit()

func _update_streaming(player_z: float):
	var current_seg = int(floor(-player_z / SEGMENT_LENGTH))
	var min_seg = max(0, current_seg - 3)
	var max_seg = min(int(LEVEL_LENGTH_METERS / SEGMENT_LENGTH) + 1, current_seg + 8)

	# Удаляем далекие сегменты
	var to_remove = []
	for s_idx in active_segments.keys():
		if s_idx < min_seg or s_idx > max_seg:
			to_remove.append(s_idx)

	for s_idx in to_remove:
		var node = active_segments[s_idx]
		if is_instance_valid(node):
			node.queue_free()
		active_segments.erase(s_idx)

	# Строим новые
	for s_idx in range(min_seg, max_seg + 1):
		if not active_segments.has(s_idx):
			var seg_node = _build_segment(s_idx)
			add_child(seg_node)
			active_segments[s_idx] = seg_node

func _build_segment(seg_idx: int) -> Node3D:
	var root = Node3D.new()
	root.name = "Segment_%d" % seg_idx
	var start_z = -float(seg_idx) * SEGMENT_LENGTH
	var center_z = start_z - SEGMENT_LENGTH * 0.5

	# 1. Пол
	var floor_body = StaticBody3D.new()
	var f_mesh = MeshInstance3D.new()
	var f_box = BoxMesh.new()
	f_box.size = Vector3(CORRIDOR_WIDTH, 0.2, SEGMENT_LENGTH)
	f_mesh.mesh = f_box
	f_mesh.material_override = carpet_mat
	floor_body.add_child(f_mesh)
	var f_col = CollisionShape3D.new()
	var f_shape = BoxShape3D.new()
	f_shape.size = f_box.size
	f_col.shape = f_shape
	floor_body.add_child(f_col)
	floor_body.position = Vector3(0.0, -0.1, center_z)
	root.add_child(floor_body)

	# 2. Потолок
	var ceil_body = StaticBody3D.new()
	var c_mesh = MeshInstance3D.new()
	var c_box = BoxMesh.new()
	c_box.size = Vector3(CORRIDOR_WIDTH, 0.2, SEGMENT_LENGTH)
	c_mesh.mesh = c_box
	c_mesh.material_override = ceil_mat
	ceil_body.add_child(c_mesh)
	var c_col = CollisionShape3D.new()
	var c_shape = BoxShape3D.new()
	c_shape.size = c_box.size
	c_col.shape = c_shape
	ceil_body.add_child(c_col)
	ceil_body.position = Vector3(0.0, CORRIDOR_HEIGHT + 0.1, center_z)
	root.add_child(ceil_body)

	# 3. Левая стена (X = -CORRIDOR_WIDTH/2)
	var left_body = StaticBody3D.new()
	var l_mesh = MeshInstance3D.new()
	var l_box = BoxMesh.new()
	l_box.size = Vector3(0.2, CORRIDOR_HEIGHT, SEGMENT_LENGTH)
	l_mesh.mesh = l_box
	l_mesh.material_override = wall_mat
	left_body.add_child(l_mesh)
	var l_col = CollisionShape3D.new()
	var l_shape = BoxShape3D.new()
	l_shape.size = l_box.size
	l_col.shape = l_shape
	left_body.add_child(l_col)
	left_body.position = Vector3(-CORRIDOR_WIDTH * 0.5 - 0.1, CORRIDOR_HEIGHT * 0.5, center_z)
	root.add_child(left_body)

	# 4. Правая стена (X = +CORRIDOR_WIDTH/2)
	var right_body = StaticBody3D.new()
	var r_mesh = MeshInstance3D.new()
	var r_box = BoxMesh.new()
	r_box.size = Vector3(0.2, CORRIDOR_HEIGHT, SEGMENT_LENGTH)
	r_mesh.mesh = r_box
	r_mesh.material_override = wall_mat
	right_body.add_child(r_mesh)
	var r_col = CollisionShape3D.new()
	var r_shape = BoxShape3D.new()
	r_shape.size = r_box.size
	r_col.shape = r_shape
	right_body.add_child(r_col)
	right_body.position = Vector3(CORRIDOR_WIDTH * 0.5 + 0.1, CORRIDOR_HEIGHT * 0.5, center_z)
	root.add_child(right_body)

	# 5. Двери по бокам (не открывающиеся, запертые двери больничных палат)
	for d_step in [4.0, 12.0]:
		var door_z = start_z - d_step
		_add_locked_door(root, Vector3(-CORRIDOR_WIDTH * 0.5, 0.0, door_z), PI * 0.5)
		_add_locked_door(root, Vector3(CORRIDOR_WIDTH * 0.5, 0.0, door_z), -PI * 0.5)

	# 6. Подвесные красные знаки EXIT и тревожные красные лампы на потолке
	for l_step in [4.0, 12.0]:
		var light_z = start_z - l_step
		_add_ceiling_exit_fixture(root, Vector3(0.0, CORRIDOR_HEIGHT, light_z))

	# Стена позади на самом старте (Z = 0), чтобы нельзя было побежать назад
	if seg_idx == 0:
		var back_wall = StaticBody3D.new()
		var bw_mesh = MeshInstance3D.new()
		var bw_box = BoxMesh.new()
		bw_box.size = Vector3(CORRIDOR_WIDTH + 0.4, CORRIDOR_HEIGHT, 0.3)
		bw_mesh.mesh = bw_box
		bw_mesh.material_override = wall_mat
		back_wall.add_child(bw_mesh)
		var bw_col = CollisionShape3D.new()
		var bw_shape = BoxShape3D.new()
		bw_shape.size = bw_box.size
		bw_col.shape = bw_shape
		back_wall.add_child(bw_col)
		back_wall.position = Vector3(0.0, CORRIDOR_HEIGHT * 0.5, 0.15)
		root.add_child(back_wall)

	return root

func _add_locked_door(parent: Node3D, pos: Vector3, rot_y: float):
	var door_node = Node3D.new()
	door_node.position = pos
	door_node.rotation.y = rot_y

	# Коробка и полотно двери
	var frame = MeshInstance3D.new()
	var f_box = BoxMesh.new()
	f_box.size = Vector3(1.0, 2.2, 0.1)
	frame.mesh = f_box

	var d_mat = StandardMaterial3D.new()
	d_mat.albedo_color = Color(0.28, 0.08, 0.08) # Больничная темно-красная дверь
	d_mat.roughness = 0.6
	frame.material_override = d_mat
	frame.position = Vector3(0.0, 1.1, 0.0)

	door_node.add_child(frame)
	parent.add_child(door_node)

func _add_ceiling_exit_fixture(parent: Node3D, pos: Vector3):
	var fix_root = Node3D.new()
	fix_root.position = pos

	# Корпус знака EXIT (подвесной)
	var box_mesh = MeshInstance3D.new()
	var b_box = BoxMesh.new()
	b_box.size = Vector3(0.7, 0.35, 0.12)
	box_mesh.mesh = b_box
	box_mesh.material_override = exit_box_mat
	box_mesh.position = Vector3(0.0, -0.22, 0.0)
	fix_root.add_child(box_mesh)

	# Лицевая светящаяся табличка EXIT с надписью
	var sign_front = MeshInstance3D.new()
	var sf_quad = QuadMesh.new()
	sf_quad.size = Vector2(0.66, 0.33)
	sign_front.mesh = sf_quad
	sign_front.material_override = exit_sign_mat
	# Смотрит в сторону бегущего игрока (+Z)
	sign_front.position = Vector3(0.0, -0.22, 0.062)
	fix_root.add_child(sign_front)

	# Красный свет тревоги
	var red_light = OmniLight3D.new()
	red_light.light_color = Color(1.0, 0.08, 0.08)
	red_light.light_energy = 2.8
	red_light.omni_range = 11.0
	red_light.omni_attenuation = 1.6
	red_light.position = Vector3(0.0, -0.35, 0.0)
	fix_root.add_child(red_light)

	parent.add_child(fix_root)

func _build_exit_barrier():
	var end_z = -LEVEL_LENGTH_METERS

	# Финишный тупик
	var end_wall = StaticBody3D.new()
	var w_mesh = MeshInstance3D.new()
	var w_box = BoxMesh.new()
	w_box.size = Vector3(CORRIDOR_WIDTH + 0.4, CORRIDOR_HEIGHT, 0.3)
	w_mesh.mesh = w_box
	w_mesh.material_override = wall_mat
	end_wall.add_child(w_mesh)
	var w_col = CollisionShape3D.new()
	var w_shape = BoxShape3D.new()
	w_shape.size = w_box.size
	w_col.shape = w_shape
	end_wall.add_child(w_col)
	end_wall.position = Vector3(0.0, CORRIDOR_HEIGHT * 0.5, end_z - 0.15)
	add_child(end_wall)

	# Открытая дверь выхода
	exit_door = InteractiveDoor.new()
	exit_door.name = "LevelRunExitDoor"
	exit_door.level_type = 1
	exit_door.player_entered_black_void.connect(func(_d): player_reached_exit.emit())
	add_child(exit_door)
	exit_door.global_position = Vector3(0.0, 0.0, end_z + 0.5)
	exit_door.rotation.y = 0.0
	# Сразу распахиваем её
	exit_door.call_deferred("toggle")

func _spawn_chasing_horde():
	# 1. Bacteria
	var bacteria_scene = preload("res://npc_bacteria.tscn")
	pack_bacteria = bacteria_scene.instantiate()
	add_child(pack_bacteria)
	pack_bacteria.global_position = Vector3(-0.7, 0.0, 10.0)
	pack_bacteria.target_player = player
	pack_bacteria.start_peeker_sequence(Vector3(0, 0, -1))
	pack_bacteria.trigger_aggro_chase()

	# 2. Hazmat NPC
	var hazmat_scene = preload("res://npc_hazmat.tscn")
	pack_hazmat = hazmat_scene.instantiate()
	add_child(pack_hazmat)
	pack_hazmat.global_position = Vector3(0.7, 0.0, 14.0)
	pack_hazmat.target_player = player
	pack_hazmat.trigger_aggro_chase()

	# 3. Smiler
	var smiler_script = preload("res://smiler_enemy.gd")
	pack_smiler = smiler_script.new()
	add_child(pack_smiler)
	pack_smiler.global_position = Vector3(0.0, 1.4, 7.0)
	pack_smiler.target_player = player

func _process_horde(player_z: float):
	# Держим орду на динамической дистанции сзади игрока:
	# Если игрок бежит на полной скорости (спринт ~6 м/с), сущности держатся на дистанции 8-15 метров сзади.
	# Если игрок останавливается или бежит назад — сущности настигают и убивают его!
	var desired_z = player_z + 9.0

	if pack_smiler and is_instance_valid(pack_smiler):
		pack_smiler.global_position.x = 0.0
		# Не даем отдалиться больше чем на 16м назад
		if pack_smiler.global_position.z > player_z + 16.0:
			pack_smiler.global_position.z = player_z + 16.0
		# Если игрок повернул назад и подошел ближе 1.5м — смерть
		if pack_smiler.global_position.distance_to(player.global_position) < 1.4:
			pack_smiler._trigger_kill_player()

	if pack_bacteria and is_instance_valid(pack_bacteria):
		pack_bacteria.global_position.x = -0.7
		if pack_bacteria.global_position.z > player_z + 17.0:
			pack_bacteria.global_position.z = player_z + 17.0
		if pack_bacteria.global_position.distance_to(player.global_position) < 1.4:
			pack_bacteria.catch_player_and_send_to_level89()

	if pack_hazmat and is_instance_valid(pack_hazmat):
		pack_hazmat.global_position.x = 0.7
		if pack_hazmat.global_position.z > player_z + 18.0:
			pack_hazmat.global_position.z = player_z + 18.0
		if pack_hazmat.global_position.distance_to(player.global_position) < 1.4:
			pack_hazmat.catch_player_and_send_to_level89()
