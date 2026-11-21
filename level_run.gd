class_name LevelRun
extends Node3D

# Level "!" (Run for your life!)
# Бесконечный 5-километровый прямой больничный коридор, освещенный тревожным мигающим красным светом
# и знаками EXIT. Сзади гонятся сущности: Smiler, Bacteria, Hazmat NPC. В конце (5000м) — открытая дверь выхода.

const LEVEL_LENGTH_METERS: float = 5000.0
const CORRIDOR_WIDTH: float = 3.2
const CORRIDOR_HEIGHT: float = 3.0
const SEGMENT_LENGTH: float = 16.0
const START_OFFSET_METERS: float = 80.0 # Сегменты коридора начинаются с Z = +80.0, чтобы за спиной не было пустоты

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
var original_world_env: Environment = null
var run_world_env: Environment = null
var world_env_node: WorldEnvironment = null
var horde_darkness_wall: MeshInstance3D = null

signal player_reached_exit

func _ready():
	_setup_materials()
	_setup_alarms()

func _setup_materials():
	carpet_mat = StandardMaterial3D.new()
	carpet_mat.albedo_texture = load("res://level_run_assets/run_carpet.png")
	carpet_mat.uv1_scale = Vector3(1.0, 4.0, 1.0)
	carpet_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	carpet_mat.roughness = 0.88 # Мягкий ворс с глубокими красными бликами

	wall_mat = StandardMaterial3D.new()
	wall_mat.albedo_texture = load("res://level_run_assets/run_wall.png")
	wall_mat.uv1_scale = Vector3(4.0, 1.0, 1.0)
	wall_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	wall_mat.roughness = 0.55 # Реалистичная окрашенная больничная штукатурка
	wall_mat.specular = 0.45

	ceil_mat = StandardMaterial3D.new()
	ceil_mat.albedo_texture = load("res://level_run_assets/run_ceiling.png")
	ceil_mat.uv1_scale = Vector3(1.0, 4.0, 1.0)
	ceil_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ceil_mat.roughness = 0.75

	exit_sign_mat = StandardMaterial3D.new()
	exit_sign_mat.albedo_texture = load("res://level_run_assets/exit_sign.png")
	exit_sign_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	exit_sign_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # Яркий чистый неоновый знак
	exit_sign_mat.emission_enabled = false
	exit_sign_mat.cull_mode = BaseMaterial3D.CULL_DISABLED # Виден с любой стороны!

	exit_box_mat = StandardMaterial3D.new()
	exit_box_mat.albedo_color = Color(0.12, 0.02, 0.02)
	exit_box_mat.roughness = 0.4
	exit_box_mat.metallic = 0.2

	red_light_mat = StandardMaterial3D.new()
	red_light_mat.albedo_color = Color(1.0, 0.2, 0.2)
	red_light_mat.emission_enabled = true
	red_light_mat.emission = Color(1.0, 0.15, 0.15)
	red_light_mat.emission_energy_multiplier = 4.0

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

	# Настройка кинематографичного темного реалистичного окружения для Level !
	_setup_level_run_environment()

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

	# Создаем поглощающую стену тьмы строго позади орды монстров
	_build_horde_darkness_wall()

func _build_horde_darkness_wall():
	horde_darkness_wall = MeshInstance3D.new()
	horde_darkness_wall.name = "HordeDarknessWall"
	var q_mesh = QuadMesh.new()
	q_mesh.size = Vector2(CORRIDOR_WIDTH + 1.0, CORRIDOR_HEIGHT + 1.0)
	horde_darkness_wall.mesh = q_mesh

	var d_mat = StandardMaterial3D.new()
	d_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	d_mat.albedo_color = Color(0.005, 0.001, 0.001, 1.0) # Абсолютная черная бездна
	d_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	horde_darkness_wall.material_override = d_mat

	# Начальное положение: на 4 метра позади самого дальнего монстра (Hazmat)
	horde_darkness_wall.position = Vector3(0.0, CORRIDOR_HEIGHT * 0.5, 28.0)
	add_child(horde_darkness_wall)

func _setup_level_run_environment():
	world_env_node = get_tree().root.find_child("WorldEnvironment", true, false)
	if world_env_node and world_env_node.environment:
		original_world_env = world_env_node.environment
		run_world_env = original_world_env.duplicate()
		
		# Черный глубокий фон без сторонней подсветки
		run_world_env.background_mode = Environment.BG_COLOR
		run_world_env.background_color = Color(0.005, 0.001, 0.001, 1.0)
		run_world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		run_world_env.ambient_light_color = Color(0.005, 0.001, 0.001, 1.0)
		run_world_env.ambient_light_energy = 0.05
		
		# Красный туман ТОЛЬКО вдали (начинается с 35-40 метров, вблизи тумана НЕТ)
		run_world_env.fog_enabled = true
		run_world_env.fog_mode = Environment.FOG_MODE_DEPTH
		run_world_env.fog_light_color = Color(0.9, 0.02, 0.02, 1.0) # Ярко-кровавый цвет горизонта вдали
		run_world_env.fog_light_energy = 1.0
		run_world_env.fog_depth_begin = 35.0  # Ближе 35 метров воздух абсолютно чистый!
		run_world_env.fog_depth_end = 120.0   # На 120м коридор полностью уходит в раскаленную красноту
		run_world_env.fog_density = 0.001     # Отключаем экспоненциальный туман вблизи
		
		# Мягкий аккуратный Bloom для надписей EXIT
		run_world_env.glow_enabled = true
		run_world_env.glow_intensity = 0.4
		run_world_env.glow_bloom = 0.2
		run_world_env.glow_hdr_threshold = 0.85
		run_world_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		
		# Тональный маппинг Filmic
		run_world_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		run_world_env.tonemap_exposure = 1.0
		
		# Глубокие тени SSAO в углах
		run_world_env.ssao_enabled = true
		run_world_env.ssao_radius = 1.5
		run_world_env.ssao_intensity = 2.5
		
		world_env_node.environment = run_world_env

func _exit_tree():
	if alarm1_player:
		alarm1_player.stop()
	if alarm2_player:
		alarm2_player.stop()
	if world_env_node and original_world_env:
		world_env_node.environment = original_world_env

func _process(delta: float):
	if not player or is_completed:
		return

	var pz = player.global_position.z
	_update_streaming(pz)

	# Логика орды сущностей: они постоянно держатся позади игрока на расстоянии 12-16 метров,
	# ускоряются, если игрок пытается остановиться, и ловят при замедлении.
	_process_horde(delta, pz)

	# Проверка достижения выхода (Z <= -LEVEL_LENGTH_METERS + 2.0)
	if pz <= -LEVEL_LENGTH_METERS + 2.5 and not is_completed:
		is_completed = true
		player_reached_exit.emit()

func _update_streaming(player_z: float):
	var current_seg = int(floor((-player_z + START_OFFSET_METERS) / SEGMENT_LENGTH))
	var min_seg = max(0, current_seg - 5)
	var total_segs = int((LEVEL_LENGTH_METERS + START_OFFSET_METERS) / SEGMENT_LENGTH) + 1
	var max_seg = min(total_segs, current_seg + 8)

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
	var start_z = START_OFFSET_METERS - float(seg_idx) * SEGMENT_LENGTH
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
		_add_locked_door(root, Vector3(-CORRIDOR_WIDTH * 0.5 + 0.04, 0.0, door_z), PI * 0.5)
		_add_locked_door(root, Vector3(CORRIDOR_WIDTH * 0.5 - 0.04, 0.0, door_z), -PI * 0.5)

	# 6. Подвесные красные знаки EXIT и тревожные красные лампы на потолке
	for l_step in [4.0, 12.0]:
		var light_z = start_z - l_step
		_add_ceiling_exit_fixture(root, Vector3(0.0, CORRIDOR_HEIGHT, light_z))

	# Стена позади на самом дальнем сегменте сзади (Z = +START_OFFSET_METERS)
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
		back_wall.position = Vector3(0.0, CORRIDOR_HEIGHT * 0.5, START_OFFSET_METERS + 0.15)
		root.add_child(back_wall)

	return root

func _add_locked_door(parent: Node3D, pos: Vector3, rot_y: float):
	var door_node = Node3D.new()
	door_node.position = pos
	door_node.rotation.y = rot_y

	# Наличник двери
	var trim_mat = StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.18, 0.18, 0.19)
	trim_mat.roughness = 0.5
	trim_mat.metallic = 0.4

	# Дверное полотно
	var d_mat = StandardMaterial3D.new()
	d_mat.albedo_color = Color(0.24, 0.06, 0.06) # Темно-бордовая больничная краска
	d_mat.roughness = 0.7

	# Внешняя рама/наличник
	var frame_left = _create_box_mesh(Vector3(0.06, 2.15, 0.08), Vector3(-0.48, 1.075, 0.0), trim_mat)
	var frame_right = _create_box_mesh(Vector3(0.06, 2.15, 0.08), Vector3(0.48, 1.075, 0.0), trim_mat)
	var frame_top = _create_box_mesh(Vector3(1.02, 0.06, 0.08), Vector3(0.0, 2.12, 0.0), trim_mat)
	door_node.add_child(frame_left)
	door_node.add_child(frame_right)
	door_node.add_child(frame_top)

	# Дверная створка (утоплена в раму)
	var leaf = _create_box_mesh(Vector3(0.90, 2.08, 0.04), Vector3(0.0, 1.04, 0.0), d_mat)
	door_node.add_child(leaf)

	# Металлическая ручка двери
	var handle_mat = StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.75, 0.75, 0.77)
	handle_mat.metallic = 0.85
	handle_mat.roughness = 0.25
	var handle = _create_box_mesh(Vector3(0.12, 0.03, 0.05), Vector3(0.35, 1.0, 0.035), handle_mat)
	door_node.add_child(handle)

	parent.add_child(door_node)

func _create_box_mesh(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var b = BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	return mi

func _add_ceiling_exit_fixture(parent: Node3D, pos: Vector3):
	var fix_root = Node3D.new()
	fix_root.position = pos

	# Подвесные металлические стержни от потолка к знаку
	var rod_mat = StandardMaterial3D.new()
	rod_mat.albedo_color = Color(0.2, 0.2, 0.22)
	rod_mat.metallic = 0.8
	var rod_l = _create_box_mesh(Vector3(0.02, 0.22, 0.02), Vector3(-0.25, -0.11, 0.0), rod_mat)
	var rod_r = _create_box_mesh(Vector3(0.02, 0.22, 0.02), Vector3(0.25, -0.11, 0.0), rod_mat)
	fix_root.add_child(rod_l)
	fix_root.add_child(rod_r)

	# Корпус подвесного знака EXIT
	var box_mesh = MeshInstance3D.new()
	var b_box = BoxMesh.new()
	b_box.size = Vector3(0.72, 0.36, 0.12)
	box_mesh.mesh = b_box
	box_mesh.material_override = exit_box_mat
	box_mesh.position = Vector3(0.0, -0.32, 0.0)
	fix_root.add_child(box_mesh)

	# Лицевая светящаяся табличка EXIT с надписью (лицом к бегущему игроку, смотрящему в -Z)
	var sign_front = MeshInstance3D.new()
	var sf_quad = QuadMesh.new()
	sf_quad.size = Vector2(0.68, 0.34)
	sign_front.mesh = sf_quad
	sign_front.material_override = exit_sign_mat
	# Смещаем чуть вперед от корпуса, без поворота (QuadMesh смотрит в +Z)
	sign_front.position = Vector3(0.0, -0.32, 0.063)
	sign_front.rotation_degrees = Vector3(0, 0, 0)
	fix_root.add_child(sign_front)

	# Задняя светящаяся табличка EXIT
	var sign_back = MeshInstance3D.new()
	sign_back.mesh = sf_quad
	sign_back.material_override = exit_sign_mat
	sign_back.position = Vector3(0.0, -0.32, -0.063)
	sign_back.rotation_degrees = Vector3(0, 180, 0)
	fix_root.add_child(sign_back)

	# Источник света — САМ ЗНАК EXIT (расположен прямо внутри коробки знака, освещает коридор под собой и вокруг)
	var exit_light = OmniLight3D.new()
	exit_light.light_color = Color(1.0, 0.08, 0.08) # Чистый неоновый красный
	exit_light.light_energy = 2.4 # Мягкий локальный свет от таблички
	exit_light.omni_range = 7.5   # Локальный радиус освещения
	exit_light.omni_attenuation = 1.6
	exit_light.position = Vector3(0.0, -0.32, 0.0)
	fix_root.add_child(exit_light)

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

func _kill_player_by_horde():
	if is_completed:
		return
	is_completed = true
	if player:
		player.is_active = false
		player.velocity = Vector3.ZERO
	
	# Показываем скример смерти и перезагружаем в меню
	var ui = get_tree().root.find_child("UI", true, false)
	if not ui:
		get_tree().reload_current_scene()
		return

	var vp = VideoStreamPlayer.new()
	vp.name = "LevelRunDeathJumpscare"
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

func _spawn_chasing_horde():
	# 1. Bacteria
	var bacteria_scene = preload("res://npc_bacteria.tscn")
	pack_bacteria = bacteria_scene.instantiate()
	add_child(pack_bacteria)
	pack_bacteria.global_position = Vector3(-0.7, 0.0, 21.0)
	pack_bacteria.target_player = player
	pack_bacteria.set_physics_process(false)
	pack_bacteria.trigger_aggro_chase()
	pack_bacteria.play_anim("Armature_001|bendingOverScene", true)

	# 2. Hazmat NPC
	var hazmat_scene = preload("res://npc_hazmat.tscn")
	pack_hazmat = hazmat_scene.instantiate()
	add_child(pack_hazmat)
	pack_hazmat.global_position = Vector3(0.7, 0.0, 23.5)
	pack_hazmat.target_player = player
	pack_hazmat.trigger_aggro_chase()
	pack_hazmat.set_physics_process(false)
	pack_hazmat.play_anim("Sprint")

	# 3. Smiler
	var smiler_script = preload("res://smiler_enemy.gd")
	pack_smiler = smiler_script.new()
	add_child(pack_smiler)
	# Smiler летает на уровне груди/глаз человека (Y = 0.1, т.к. внутри спрайт на Y = 1.3)
	pack_smiler.global_position = Vector3(0.0, 0.1, 18.0)
	pack_smiler.target_player = player
	pack_smiler.set_physics_process(false)

func _process_horde(delta: float, player_z: float):
	if is_completed or not player:
		return

	# Во время интро-катсцены орда не нападает, а ждет на безопасной дистанции 18-24 метров сзади
	var in_cutscene = player.get("is_in_cutscene") == true or player.get("is_active") == false
	if in_cutscene:
		if pack_smiler and is_instance_valid(pack_smiler):
			pack_smiler.global_position = Vector3(0.0, 0.1, player_z + 18.0)
		if pack_bacteria and is_instance_valid(pack_bacteria):
			pack_bacteria.global_position = Vector3(-0.7, 0.0, player_z + 21.0)
		if pack_hazmat and is_instance_valid(pack_hazmat):
			pack_hazmat.global_position = Vector3(0.7, 0.0, player_z + 23.5)
		if horde_darkness_wall and is_instance_valid(horde_darkness_wall):
			horde_darkness_wall.position.z = player_z + 28.0
		return

	# Логика орды:
	# Монстры поддерживают постоянное напряжение и держат дистанцию преследования.
	# У игрока всегда есть фора:
	# 1) На полном спринте (скорость 6.0 м/с) игрок плавно отрывается вперед до комфортных 16-18 метров.
	# 2) При оглядке назад на бегу, зуме камеры (скорость ~3.0 м/с) или обычной ходьбе монстры плавно сокращают дистанцию,
	#    но НЕ убивают мгновенно — у игрока остается дистанция тревоги 5-8 метров.
	# 3) Только если игрок буквально встал на месте (или пошел назад), монстры быстро настигают его и убивают.
	# 4) Монстры никогда не замирают намертво — они всегда агрессивно бегут за игроком.

	var player_fwd_speed = -player.velocity.z # скорость движения вперед по -Z
	
	# Расчет скорости монстров
	# Базовая целевая дистанция преследования: 15 метров
	var target_gap = 15.0
	
	# Обновляем позицию Smiler (авангард орды, летает по центру)
	if pack_smiler and is_instance_valid(pack_smiler):
		pack_smiler.global_position.x = 0.0
		var current_gap = pack_smiler.global_position.z - player_z
		var smiler_speed = 0.0
		
		if player_fwd_speed <= 0.8:
			# Игрок встал на месте или идет назад: монстры стремительно нападают
			smiler_speed = 6.2
		elif player_fwd_speed < 4.0:
			# Игрок замедлился (зум, оглядывается назад, идет пешком):
			# Монстры приближаются, сжимая кольцо до опасных 6 метров, но не напрыгивают намертво
			if current_gap > 6.5:
				smiler_speed = player_fwd_speed + 1.2
			else:
				smiler_speed = max(1.5, player_fwd_speed * 0.95)
		else:
			# Игрок бежит на полной скорости (спринт ~6.0 м/с):
			# Монстры держат динамичную дистанцию ~14-16м, создавая ощущение погони хвост в хвост
			if current_gap < target_gap:
				smiler_speed = player_fwd_speed - 0.7 # Игрок понемногу отрывается
			elif current_gap > target_gap + 2.0:
				smiler_speed = player_fwd_speed + 0.6 # Монстры подтягиваются
			else:
				smiler_speed = player_fwd_speed

		# Монстры никогда не бегут назад и не стоят на месте
		smiler_speed = max(2.5, smiler_speed)
		pack_smiler.global_position.z -= smiler_speed * delta

		if pack_smiler.global_position.distance_to(player.global_position) < 1.4:
			_kill_player_by_horde()
			return

	# Обновляем позицию Bacteria (слева, чуть позади смайлера)
	if pack_bacteria and is_instance_valid(pack_bacteria):
		pack_bacteria.global_position.x = -0.7
		# Анимация бега и крики бактерии при преследовании
		pack_bacteria.play_anim("Armature_001|bendingOverScene", true)
		pack_bacteria._update_chase_screams(delta)

		var current_gap_b = pack_bacteria.global_position.z - player_z
		var b_target_gap = target_gap + 2.5
		var b_speed = 0.0
		
		if player_fwd_speed <= 0.8:
			b_speed = 6.5
		elif player_fwd_speed < 4.0:
			if current_gap_b > 8.0:
				b_speed = player_fwd_speed + 1.3
			else:
				b_speed = max(1.5, player_fwd_speed * 0.95)
		else:
			if current_gap_b < b_target_gap:
				b_speed = player_fwd_speed - 0.6
			elif current_gap_b > b_target_gap + 2.0:
				b_speed = player_fwd_speed + 0.7
			else:
				b_speed = player_fwd_speed

		b_speed = max(2.5, b_speed)
		pack_bacteria.global_position.z -= b_speed * delta

		if pack_bacteria.global_position.distance_to(player.global_position) < 1.4:
			_kill_player_by_horde()
			return

	# Обновляем позицию Hazmat (справа, замыкающий)
	if pack_hazmat and is_instance_valid(pack_hazmat):
		pack_hazmat.global_position.x = 0.7
		# Анимация бега и крики преследователя
		pack_hazmat.play_anim("Sprint")
		pack_hazmat._update_chase_screams(delta)

		var current_gap_h = pack_hazmat.global_position.z - player_z
		var h_target_gap = target_gap + 4.5
		var h_speed = 0.0

		if player_fwd_speed <= 0.8:
			h_speed = 6.6
		elif player_fwd_speed < 4.0:
			if current_gap_h > 10.0:
				h_speed = player_fwd_speed + 1.4
			else:
				h_speed = max(1.5, player_fwd_speed * 0.95)
		else:
			if current_gap_h < h_target_gap:
				h_speed = player_fwd_speed - 0.5
			elif current_gap_h > h_target_gap + 2.0:
				h_speed = player_fwd_speed + 0.8
			else:
				h_speed = player_fwd_speed

		h_speed = max(2.5, h_speed)
		pack_hazmat.global_position.z -= h_speed * delta

		if pack_hazmat.global_position.distance_to(player.global_position) < 1.4:
			_kill_player_by_horde()
			return

	# Позиция поглощающей стены черноты: следует строго позади орды монстров на дистанции 4-5 метров
	if horde_darkness_wall and is_instance_valid(horde_darkness_wall):
		var furthest_monster_z = player_z + 24.0
		if pack_hazmat and is_instance_valid(pack_hazmat):
			furthest_monster_z = max(furthest_monster_z, pack_hazmat.global_position.z)
		if pack_bacteria and is_instance_valid(pack_bacteria):
			furthest_monster_z = max(furthest_monster_z, pack_bacteria.global_position.z)
		horde_darkness_wall.position.z = furthest_monster_z + 4.5
