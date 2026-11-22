class_name LevelFun
extends Node3D

# Level "Fun" (Веселье)
# Непредсказуемый лабиринт: комнаты разных размеров, извилистые коридоры, тупики, разветвления.
# Потолок: 3.6м, плиточный.
# Пол: ковер-дорога Road Rug (без швов).
# Стены: яркие цветные стены со строгим черным плинтусом.
# Колонны: белые с черным обрамлением.
# Декорации: праздничные столы FNaF и шарики rainbow balloons.

const L_FUN_HEIGHT: float = 3.6
const CELL_SIZE: float = 4.0 # Базовая сетка лабиринта: 4x4 метра

var player: CharacterBody3D = null

# Материалы
var floor_mat: StandardMaterial3D = null
var ceil_mat: StandardMaterial3D = null
var baseboard_mat: StandardMaterial3D = null
var pillar_mat: StandardMaterial3D = null
var wall_materials: Array[StandardMaterial3D] = []

# Ресурсы моделей
var table_scene: PackedScene = null
var balloon_scene: PackedScene = null
var partygoer_enemy_script = preload("res://partygoer_enemy.gd")
var spawned_partygoers: Array[CharacterBody3D] = []

# Чанки стриминга (по 10x10 клеток сетки = 40x40 метров)
const CHUNK_CELLS: int = 10
const CHUNK_SIZE_M: float = float(CHUNK_CELLS) * CELL_SIZE # 40.0м

var active_chunks: Dictionary = {} # Vector2i -> Node3D
var active_lights: Array[OmniLight3D] = []
var active_lamp_meshes: Array[MeshInstance3D] = []
var lamp_material: StandardMaterial3D = null

# Механика блэкаута на Уровне Fun
var blackout_active: bool = false
var blackout_disabled_permanently: bool = false
var next_blackout_time: float = 75.0 # Первый блэкаут через ~1-1.5 мин (затем 90-180 сек)
var blackout_duration: float = 0.0
var music_scheduled: bool = false
var music_timer: float = 0.0
var blackout_sound_stream = preload("res://audio/soundreality-sub-down-222742.mp3")
var daisy_bell_stream = preload("res://level_fun_assets/daisy_bell.mp3")
var echo_speakers: Array[AudioStreamPlayer3D] = []

# Событие касания: игрок был коснут тусовщиком
var was_player_touched: bool = false

# Типы клеток сетки (мировые координаты сетки gx, gz):
# 0 = WALL (стена)
# 1 = FLOOR (проходимый пол: комната или коридор)
# 2 = PILLAR (колонна)

func _init():
	_init_materials()
	table_scene = load("res://level_fun_assets/table/source/unzipped/FNAF Table/FNaF Table.fbx")
	balloon_scene = load("res://level_fun_assets/balloons/source/rainbow balloons.glb")

func _init_materials():
	# Пол - ковер с дорогами Road Rug (бесшовный зеркальный тайлинг)
	floor_mat = StandardMaterial3D.new()
	var rug_tex = load("res://level_fun_assets/road_rug_seamless.jpg")
	floor_mat.albedo_texture = rug_tex
	floor_mat.uv1_triplanar = true
	floor_mat.uv1_scale = Vector3(0.08, 0.08, 0.08)
	floor_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	floor_mat.roughness = 0.9

	# Потолок - плиточный
	ceil_mat = StandardMaterial3D.new()
	var c_tex = load("res://kane_ceiling.png")
	ceil_mat.albedo_texture = c_tex
	ceil_mat.uv1_triplanar = true
	ceil_mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	ceil_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ceil_mat.roughness = 0.9

	# Плинтус черный
	baseboard_mat = StandardMaterial3D.new()
	baseboard_mat.albedo_color = Color(0.08, 0.08, 0.08)
	baseboard_mat.roughness = 0.7

	# Колонны - белые
	pillar_mat = StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.95, 0.95, 0.92)
	pillar_mat.roughness = 0.85

	# Цвета стен
	var colors = [
		Color(0.95, 0.25, 0.60), # Розовый
		Color(0.20, 0.85, 0.25), # Ярко-зеленый
		Color(0.95, 0.20, 0.15), # Ярко-красный
		Color(0.95, 0.55, 0.15), # Оранжевый
		Color(0.98, 0.80, 0.15), # Желтый
		Color(0.20, 0.65, 0.95), # Голубой
		Color(0.65, 0.25, 0.90)  # Фиолетовый
	]
	for c in colors:
		var m = StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		wall_materials.append(m)

	# Материал плафонов ламп
	lamp_material = StandardMaterial3D.new()
	lamp_material.albedo_color = Color(1.0, 0.98, 0.92)
	lamp_material.emission_enabled = true
	lamp_material.emission = Color(1.0, 0.96, 0.88)
	lamp_material.emission_energy_multiplier = 3.0

func setup(p: CharacterBody3D):
	player = p
	if player:
		# Выбираем случайный чанк для спавна (от -20 до 20)
		var rand_cx = randi_range(-20, 20)
		var rand_cz = randi_range(-20, 20)
		var start_chunk = Vector2i(rand_cx, rand_cz)
		var start_grid = _generate_chunk_grid(start_chunk)

		# Находим проходимую свободную клетку внутри выбранного чанка
		var open_pts: Array[Vector3] = []
		for gx in range(1, CHUNK_CELLS - 1):
			for gz in range(1, CHUNK_CELLS - 1):
				if start_grid[gx][gz] == 1:
					open_pts.append(Vector3(
						float(rand_cx) * CHUNK_SIZE_M + gx * CELL_SIZE + CELL_SIZE * 0.5,
						0.2,
						float(rand_cz) * CHUNK_SIZE_M + gz * CELL_SIZE + CELL_SIZE * 0.5
					))

		if not open_pts.is_empty():
			player.global_position = open_pts[randi() % open_pts.size()]
		else:
			player.global_position = Vector3(
				float(rand_cx) * CHUNK_SIZE_M + 20.0,
				0.2,
				float(rand_cz) * CHUNK_SIZE_M + 20.0
			)

		player.velocity = Vector3.ZERO
		var init_yaw = randf_range(0.0, TAU)
		player.rotation.y = init_yaw
		if "player_yaw" in player:
			player.player_yaw = init_yaw

	_update_chunks()

func _process(delta: float):
	if not player:
		return
	_update_chunks()
	_process_blackout(delta)
	_process_touched_disappearance(delta)

# Если игрок был коснут, ждем пока ВСЕ тусовщики пропадут из поля зрения игрока
func _process_touched_disappearance(delta: float):
	if not was_player_touched or spawned_partygoers.is_empty():
		return
	
	# Проверяем, видит ли игрок хоть одного тусовщика
	var any_visible = false
	var cam = player.find_child("Camera3D", true, false)
	if not cam:
		cam = get_viewport().get_camera_3d()
	
	if cam:
		var cam_pos = cam.global_position
		var cam_forward = -cam.global_transform.basis.z.normalized()
		var space_state = get_world_3d().direct_space_state
		
		for p in spawned_partygoers:
			if not is_instance_valid(p):
				continue
			var p_pos = p.global_position + Vector3(0.0, 1.2, 0.0)
			var to_p = p_pos - cam_pos
			var dist = to_p.length()
			
			# Если тусовщик близко (< 40м) и в конусе зрения камеры (угловой обзор ~85 градусов)
			if dist < 45.0:
				var angle = rad_to_deg(cam_forward.angle_to(to_p.normalized()))
				if angle < 75.0:
					# Проверяем луч видимости (нет ли стены между камерой и тусовщиком)
					if space_state:
						var query = PhysicsRayQueryParameters3D.create(cam_pos, p_pos)
						query.exclude = [player.get_rid() if player is CollisionObject3D else RID()]
						var res = space_state.intersect_ray(query)
						if res.is_empty() or res.collider == p:
							any_visible = true
							break
					else:
						any_visible = true
						break

	# Как только ВСЕ тусовщики вышли из поля зрения игрока:
	# они разом все исчезают, а блэкаут навсегда отключается!
	if not any_visible:
		print("[LEVEL FUN] Player escaped line of sight after touch! All partygoers vanish, blackout disabled forever.")
		for p in spawned_partygoers:
			if is_instance_valid(p):
				p.queue_free()
		spawned_partygoers.clear()
		was_player_touched = false
		blackout_disabled_permanently = true
		if blackout_active:
			_end_blackout_event()

func _update_chunks():
	if not player:
		return
	var px = player.global_position.x
	var pz = player.global_position.z
	var cur_cx = int(floor(px / CHUNK_SIZE_M))
	var cur_cz = int(floor(pz / CHUNK_SIZE_M))

	var needed: Dictionary = {}
	var view_radius = 2 # 5x5 чанков вокруг игрока

	for dz in range(-view_radius, view_radius + 1):
		for dx in range(-view_radius, view_radius + 1):
			var c = Vector2i(cur_cx + dx, cur_cz + dz)
			needed[c] = true

	# Удаление далеких чанков
	var to_remove = []
	for c in active_chunks.keys():
		if not needed.has(c):
			to_remove.append(c)

	for c in to_remove:
		var node = active_chunks[c]
		if is_instance_valid(node):
			node.queue_free()
		active_chunks.erase(c)

	# Очищаем невалидные ссылки на свет и тусовщиков
	active_lights = active_lights.filter(func(l): return is_instance_valid(l))
	active_lamp_meshes = active_lamp_meshes.filter(func(m): return is_instance_valid(m))
	spawned_partygoers = spawned_partygoers.filter(func(p): return is_instance_valid(p))

	# Создание новых чанков
	for c in needed.keys():
		if not active_chunks.has(c):
			_build_chunk(c)

func _hash_2i(x: int, z: int, salt: int = 1337) -> int:
	var h = (x * 73856093) ^ (z * 19349663) ^ (salt * 83492791)
	return abs(h)

# Процедурная генерация плана чанка: лабиринт с комнатами, поворотами и тупиками
func _generate_chunk_grid(c: Vector2i) -> Array:
	var grid = []
	for x in range(CHUNK_CELLS):
		var row = []
		for z in range(CHUNK_CELLS):
			row.append(0) # По умолчанию стена
		grid.append(row)

	var h = _hash_2i(c.x, c.y, 42)
	var rng = RandomNumberGenerator.new()
	rng.seed = h

	# 1. Размещаем 1-2 комнаты случайного размера (от 3x3 до 6x6 клеток = 12x12 до 24x24 метра)
	var room_count = rng.randi_range(1, 2)
	var room_rects: Array[Rect2i] = []

	for _r in range(room_count):
		var rw = rng.randi_range(3, 5)
		var rh = rng.randi_range(3, 5)
		var rx = rng.randi_range(1, CHUNK_CELLS - rw - 1)
		var rz = rng.randi_range(1, CHUNK_CELLS - rh - 1)
		var rect = Rect2i(rx, rz, rw, rh)
		room_rects.append(rect)

		for gx in range(rx, rx + rw):
			for gz in range(rz, rz + rh):
				grid[gx][gz] = 1 # Пол

	# 2. Главные межчанковые коридоры (гарантируют связность мира между чанками)
	# Точки входа на границах чанка определяются детерминированно из хэша сопредельных сторон
	var north_x = (abs(_hash_2i(c.x, c.y, 11)) % (CHUNK_CELLS - 4)) + 2
	var south_x = (abs(_hash_2i(c.x, c.y + 1, 11)) % (CHUNK_CELLS - 4)) + 2
	var west_z = (abs(_hash_2i(c.x, c.y, 22)) % (CHUNK_CELLS - 4)) + 2
	var east_z = (abs(_hash_2i(c.x + 1, c.y, 22)) % (CHUNK_CELLS - 4)) + 2

	# Входы на границах
	grid[north_x][0] = 1
	grid[south_x][CHUNK_CELLS - 1] = 1
	grid[0][west_z] = 1
	grid[CHUNK_CELLS - 1][east_z] = 1

	# Соединяем входы с центром / комнатами извилистыми путями (с поворотами)
	_carve_corridor(grid, north_x, 0, south_x, CHUNK_CELLS - 1, rng)
	_carve_corridor(grid, 0, west_z, CHUNK_CELLS - 1, east_z, rng)

	# 3. Добавляем 1-3 случайных тупиковых ответвления (dead ends) для лабиринта
	var branch_count = rng.randi_range(1, 3)
	for _b in range(branch_count):
		var start_x = rng.randi_range(1, CHUNK_CELLS - 2)
		var start_z = rng.randi_range(1, CHUNK_CELLS - 2)
		if grid[start_x][start_z] == 1:
			var branch_len = rng.randi_range(2, 4)
			var dirs = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			var b_dir = dirs[rng.randi() % dirs.size()]
			var bx = start_x
			var bz = start_z
			for _step in range(branch_len):
				bx = clamp(bx + b_dir.x, 1, CHUNK_CELLS - 2)
				bz = clamp(bz + b_dir.y, 1, CHUNK_CELLS - 2)
				grid[bx][bz] = 1

	return grid

func _carve_corridor(grid: Array, x1: int, z1: int, x2: int, z2: int, rng: RandomNumberGenerator):
	var cx = x1
	var cz = z1
	# Двигаемся с промежуточным поворотом, создающим изгибы
	var turn_at_z = rng.randi_range(min(z1, z2), max(z1, z2))
	while cz != turn_at_z:
		cz += 1 if turn_at_z > cz else -1
		grid[cx][cz] = 1
	while cx != x2:
		cx += 1 if x2 > cx else -1
		grid[cx][cz] = 1
	while cz != z2:
		cz += 1 if z2 > cz else -1
		grid[cx][cz] = 1

func _build_chunk(c: Vector2i):
	var chunk_node = Node3D.new()
	chunk_node.name = "Chunk_%d_%d" % [c.x, c.y]
	add_child(chunk_node)
	active_chunks[c] = chunk_node

	var x0 = c.x * CHUNK_SIZE_M
	var z0 = c.y * CHUNK_SIZE_M

	var grid = _generate_chunk_grid(c)

	# Выбираем цвет стен для этого чанка
	var color_idx = _hash_2i(c.x, c.y, 77) % wall_materials.size()
	var wall_mat = wall_materials[color_idx]

	var h = _hash_2i(c.x, c.y, 99)
	var rng = RandomNumberGenerator.new()
	rng.seed = h

	# Координаты выходов на сопредельные чанки
	var north_x = (abs(_hash_2i(c.x, c.y, 11)) % (CHUNK_CELLS - 4)) + 2
	var south_x = (abs(_hash_2i(c.x, c.y + 1, 11)) % (CHUNK_CELLS - 4)) + 2
	var west_z = (abs(_hash_2i(c.x, c.y, 22)) % (CHUNK_CELLS - 4)) + 2
	var east_z = (abs(_hash_2i(c.x + 1, c.y, 22)) % (CHUNK_CELLS - 4)) + 2

	# 1. Построение пола и потолка только там, где есть пол (grid == 1)
	# Объединяем пол и потолок чанка
	for gx in range(CHUNK_CELLS):
		for gz in range(CHUNK_CELLS):
			if grid[gx][gz] == 1:
				var cell_world_x = x0 + gx * CELL_SIZE + CELL_SIZE * 0.5
				var cell_world_z = z0 + gz * CELL_SIZE + CELL_SIZE * 0.5
				_spawn_cell_floor_and_ceil(chunk_node, cell_world_x, cell_world_z)

				# Проверяем 4 соседа клетки: строим стену только если сосед внутри чанка стена (0),
				# а на внешней границе чанка строим стену только если эта клетка НЕ является выходом/проходом к соседу
				# Север (gz - 1)
				if (gz > 0 and grid[gx][gz - 1] == 0) or (gz == 0 and gx != north_x):
					_spawn_wall_segment(chunk_node,
						Vector3(cell_world_x, 0.0, cell_world_z - CELL_SIZE * 0.5),
						Vector3(CELL_SIZE, L_FUN_HEIGHT, 0.4), wall_mat)
				# Юг (gz + 1)
				if (gz < CHUNK_CELLS - 1 and grid[gx][gz + 1] == 0) or (gz == CHUNK_CELLS - 1 and gx != south_x):
					_spawn_wall_segment(chunk_node,
						Vector3(cell_world_x, 0.0, cell_world_z + CELL_SIZE * 0.5),
						Vector3(CELL_SIZE, L_FUN_HEIGHT, 0.4), wall_mat)
				# Запад (gx - 1)
				if (gx > 0 and grid[gx - 1][gz] == 0) or (gx == 0 and gz != west_z):
					_spawn_wall_segment(chunk_node,
						Vector3(cell_world_x - CELL_SIZE * 0.5, 0.0, cell_world_z),
						Vector3(0.4, L_FUN_HEIGHT, CELL_SIZE), wall_mat)
				# Восток (gx + 1)
				if (gx < CHUNK_CELLS - 1 and grid[gx + 1][gz] == 0) or (gx == CHUNK_CELLS - 1 and gz != east_z):
					_spawn_wall_segment(chunk_node,
						Vector3(cell_world_x + CELL_SIZE * 0.5, 0.0, cell_world_z),
						Vector3(0.4, L_FUN_HEIGHT, CELL_SIZE), wall_mat)

	# 2. Размещение колонн, столов и шаров
	# Ищем свободные открытые зоны (где у клетки все 4 соседа тоже пол — открытая комната)
	var open_cells: Array[Vector2i] = []
	for gx in range(1, CHUNK_CELLS - 1):
		for gz in range(1, CHUNK_CELLS - 1):
			if grid[gx][gz] == 1 and grid[gx-1][gz] == 1 and grid[gx+1][gz] == 1 and grid[gx][gz-1] == 1 and grid[gx][gz+1] == 1:
				open_cells.append(Vector2i(gx, gz))

	# Колонны в центрах комнат
	if not open_cells.is_empty() and rng.randf() < 0.6:
		var p_idx = rng.randi() % open_cells.size()
		var p_cell = open_cells[p_idx]
		var p_pos = Vector3(x0 + p_cell.x * CELL_SIZE + CELL_SIZE * 0.5, 0.0, z0 + p_cell.y * CELL_SIZE + CELL_SIZE * 0.5)
		_spawn_fun_pillar(chunk_node, p_pos)
		open_cells.remove_at(p_idx)

	# Столы в открытых комнатах
	if not open_cells.is_empty() and rng.randf() < 0.8:
		var t_idx = rng.randi() % open_cells.size()
		var t_cell = open_cells[t_idx]
		var t_pos = Vector3(x0 + t_cell.x * CELL_SIZE + CELL_SIZE * 0.5, 0.0, z0 + t_cell.y * CELL_SIZE + CELL_SIZE * 0.5)
		_spawn_fun_table(chunk_node, t_pos)
		open_cells.remove_at(t_idx)

	# Шарики (разбросаны по углам и у стен)
	var balloon_count = rng.randi_range(2, 5)
	for _i in range(balloon_count):
		var rx = rng.randi_range(1, CHUNK_CELLS - 2)
		var rz = rng.randi_range(1, CHUNK_CELLS - 2)
		if grid[rx][rz] == 1:
			var b_pos = Vector3(x0 + rx * CELL_SIZE + rng.randf_range(1.0, 3.0), 0.0, z0 + rz * CELL_SIZE + rng.randf_range(1.0, 3.0))
			_spawn_fun_balloons(chunk_node, b_pos)

	# Спавн Partygoer монстров (в 65% чанков, по 1-2 тусовщика, но не прямо на стартовом чанке игрока)
	# Если блэкаут навсегда отключен после касания — тусовщики больше не спавнятся вообще!
	var player_chunk = Vector2i(int(floor(player.global_position.x / CHUNK_SIZE_M)), int(floor(player.global_position.z / CHUNK_SIZE_M))) if player else Vector2i(9999, 9999)
	if not blackout_disabled_permanently and c != player_chunk and rng.randf() < 0.65:
		var spawnable_cells: Array[Vector2i] = []
		for gx in range(1, CHUNK_CELLS - 1):
			for gz in range(1, CHUNK_CELLS - 1):
				if grid[gx][gz] == 1:
					spawnable_cells.append(Vector2i(gx, gz))
		if not spawnable_cells.is_empty():
			var count = 2 if rng.randf() < 0.40 and spawnable_cells.size() >= 4 else 1
			for _p in range(count):
				var idx = rng.randi() % spawnable_cells.size()
				var s_cell = spawnable_cells[idx]
				spawnable_cells.remove_at(idx)
				var m_pos = Vector3(x0 + s_cell.x * CELL_SIZE + CELL_SIZE * 0.5, 0.2, z0 + s_cell.y * CELL_SIZE + CELL_SIZE * 0.5)
				_spawn_partygoer(chunk_node, m_pos)

	# Освещение: частые потолочные светильники по всем комнатам и коридорам
	# Лампы в шахматном порядке каждые 2 клетки сетки (каждые 8 метров),
	# чтобы свет был повсюду в каждом помещении и проходе
	for lx in range(CHUNK_CELLS):
		for lz in range(CHUNK_CELLS):
			if grid[lx][lz] == 1 and ((lx + lz) % 2 == 0):
				var l_pos = Vector3(x0 + lx * CELL_SIZE + CELL_SIZE * 0.5, L_FUN_HEIGHT - 0.2, z0 + lz * CELL_SIZE + CELL_SIZE * 0.5)
				_spawn_light(chunk_node, l_pos, 10.0, 2.2)

func _spawn_cell_floor_and_ceil(parent: Node3D, cx: float, cz: float):
	# Пол (с небольшим нахлестом 0.02м, чтобы не было микрощелей)
	var floor_body = StaticBody3D.new()
	floor_body.position = Vector3(cx, 0.0, cz)

	var f_mesh = MeshInstance3D.new()
	var f_box = BoxMesh.new()
	f_box.size = Vector3(CELL_SIZE + 0.02, 0.1, CELL_SIZE + 0.02)
	f_mesh.mesh = f_box
	f_mesh.material_override = floor_mat
	f_mesh.position.y = -0.05
	floor_body.add_child(f_mesh)

	var f_col = CollisionShape3D.new()
	var b_col = BoxShape3D.new()
	b_col.size = Vector3(CELL_SIZE + 0.02, 0.2, CELL_SIZE + 0.02)
	f_col.shape = b_col
	f_col.position.y = -0.1
	floor_body.add_child(f_col)

	parent.add_child(floor_body)

	# Потолок
	var c_mesh = MeshInstance3D.new()
	var c_box = BoxMesh.new()
	c_box.size = Vector3(CELL_SIZE + 0.02, 0.1, CELL_SIZE + 0.02)
	c_mesh.mesh = c_box
	c_mesh.material_override = ceil_mat
	c_mesh.position = Vector3(cx, L_FUN_HEIGHT + 0.05, cz)
	parent.add_child(c_mesh)

func _spawn_wall_segment(parent: Node3D, center_pos: Vector3, size: Vector3, mat: StandardMaterial3D):
	var body = StaticBody3D.new()
	body.position = center_pos + Vector3(0, size.y * 0.5, 0)

	var m = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	m.mesh = box
	m.material_override = mat
	body.add_child(m)

	var col = CollisionShape3D.new()
	var b_shape = BoxShape3D.new()
	b_shape.size = size
	col.shape = b_shape
	body.add_child(col)

	# Плинтус черный снизу
	var base_m = MeshInstance3D.new()
	var base_box = BoxMesh.new()
	base_box.size = Vector3(size.x + 0.02, 0.16, size.z + 0.02)
	base_m.mesh = base_box
	base_m.material_override = baseboard_mat
	base_m.position.y = -size.y * 0.5 + 0.08
	body.add_child(base_m)

	parent.add_child(body)

func _spawn_fun_pillar(parent: Node3D, pos: Vector3):
	var p_body = StaticBody3D.new()
	var p_size = Vector3(1.3, L_FUN_HEIGHT, 1.3)
	p_body.position = pos + Vector3(0, L_FUN_HEIGHT * 0.5, 0)

	var m = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = p_size
	m.mesh = box
	m.material_override = pillar_mat
	p_body.add_child(m)

	var col = CollisionShape3D.new()
	var b_col = BoxShape3D.new()
	b_col.size = p_size
	col.shape = b_col
	p_body.add_child(col)

	# Молдинг снизу
	var base_m = MeshInstance3D.new()
	var base_box = BoxMesh.new()
	base_box.size = Vector3(p_size.x + 0.04, 0.22, p_size.z + 0.04)
	base_m.mesh = base_box
	base_m.material_override = baseboard_mat
	base_m.position.y = -p_size.y * 0.5 + 0.11
	p_body.add_child(base_m)

	# Молдинг сверху
	var top_m = MeshInstance3D.new()
	var top_box = BoxMesh.new()
	top_box.size = Vector3(p_size.x + 0.04, 0.14, p_size.z + 0.04)
	top_m.mesh = top_box
	top_m.material_override = baseboard_mat
	top_m.position.y = p_size.y * 0.5 - 0.07
	p_body.add_child(top_m)

	parent.add_child(p_body)

func _spawn_fun_table(parent: Node3D, pos: Vector3):
	if not table_scene:
		return
	var inst = table_scene.instantiate()
	inst.position = pos
	inst.scale = Vector3(0.45, 0.45, 0.45)
	inst.rotation_degrees.y = (randi() % 4) * 90.0

	var body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(1.7, 1.1, 2.5)
	col.shape = box
	col.position.y = 0.55
	body.add_child(col)
	body.position = pos
	body.rotation_degrees.y = inst.rotation_degrees.y
	parent.add_child(body)

	parent.add_child(inst)

func _spawn_partygoer(parent: Node3D, pos: Vector3):
	if not partygoer_enemy_script:
		return
	var monster = partygoer_enemy_script.new()
	monster.position = pos
	monster.target_player = player
	monster.is_frozen_in_darkness = blackout_active
	parent.add_child(monster)
	spawned_partygoers.append(monster)

func _spawn_fun_balloons(parent: Node3D, pos: Vector3):
	if not balloon_scene:
		return
	var inst = balloon_scene.instantiate()
	var root_b = Node3D.new()
	root_b.position = pos
	root_b.rotation_degrees.y = randf_range(0.0, 360.0)

	inst.scale = Vector3(0.55, 0.55, 0.55)
	inst.position = Vector3(0.0, 0.0, 0.8)
	root_b.add_child(inst)
	parent.add_child(root_b)

# --- Логика блэкаута и хорового Daisy Bell с эхом ---

func _ensure_fun_echo_bus() -> String:
	var bus_name = "LevelFunEchoBus"
	var idx = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")

		# Глубокое эхо лабиринта
		var reverb = AudioEffectReverb.new()
		reverb.room_size = 0.92
		reverb.damping = 0.3
		reverb.spread = 1.0
		reverb.wet = 0.75
		reverb.dry = 0.45
		AudioServer.add_bus_effect(idx, reverb)

		# Эффект старого радио/громкоговорителя
		var bandpass = AudioEffectBandPassFilter.new()
		bandpass.cutoff_hz = 1750.0
		bandpass.resonance = 0.4
		AudioServer.add_bus_effect(idx, bandpass)

		var dist = AudioEffectDistortion.new()
		dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
		dist.drive = 0.22
		dist.post_gain = 0.0
		AudioServer.add_bus_effect(idx, dist)
	return bus_name

func trigger_blackout_event():
	if blackout_active or blackout_disabled_permanently:
		return
	blackout_active = true
	blackout_duration = randf_range(45.0, 75.0) # Длительность блэкаута
	music_scheduled = true
	music_timer = randf_range(2.0, 3.5) # Через пару секунд в темноте включается повсеместное эхо Daisy Bell

	print("[LEVEL FUN] Blackout triggered! Lights out, partygoers freeze.")

	# Погружаем WorldEnvironment в кромешную тьму
	var env_node = get_tree().current_scene.get_node_or_null("WorldEnvironment") if get_tree() and get_tree().current_scene else null
	if not env_node:
		env_node = get_parent().get_node_or_null("WorldEnvironment") if get_parent() else null
	if env_node and env_node.environment:
		env_node.environment.ambient_light_energy = 0.0
		env_node.environment.ambient_light_color = Color(0.0, 0.0, 0.0)

	# Выключаем лампы и свечение плафонов
	if lamp_material:
		lamp_material.emission_enabled = false
	for l in active_lights:
		if is_instance_valid(l):
			l.light_energy = 0.0

	# Звук отключения питания (глубокий гул блэкаута)
	if blackout_sound_stream:
		var sfx = AudioStreamPlayer.new()
		sfx.stream = blackout_sound_stream
		sfx.volume_db = 8.0
		add_child(sfx)
		sfx.play()
		sfx.finished.connect(func(): if is_instance_valid(sfx): sfx.queue_free())

	# Все тусовщики замолкают и замирают!
	for p in spawned_partygoers:
		if is_instance_valid(p) and p.has_method("on_blackout_start"):
			p.on_blackout_start()

func _end_blackout_event():
	blackout_active = false
	music_scheduled = false
	next_blackout_time = randf_range(100.0, 220.0)

	print("[LEVEL FUN] Blackout ended! Lights restored.")

	# Восстанавливаем свет окружения
	var env_node = get_tree().current_scene.get_node_or_null("WorldEnvironment") if get_tree() and get_tree().current_scene else null
	if not env_node:
		env_node = get_parent().get_node_or_null("WorldEnvironment") if get_parent() else null
	if env_node and env_node.environment:
		env_node.environment.ambient_light_energy = 0.35
		env_node.environment.ambient_light_color = Color(0.35, 0.32, 0.30)

	# Включаем лампы и плафоны
	if lamp_material:
		lamp_material.emission_enabled = true
	for l in active_lights:
		if is_instance_valid(l):
			l.light_energy = 2.2

	# Останавливаем повсеместное эхо
	_stop_echo_speakers()

	# Все тусовщики снова включают свою песню
	for p in spawned_partygoers:
		if is_instance_valid(p) and p.has_method("on_blackout_end"):
			p.on_blackout_end()

func _process_blackout(delta: float):
	if not blackout_active:
		next_blackout_time -= delta
		if next_blackout_time <= 0.0:
			trigger_blackout_event()
		return

	# Во время блэкаута
	if music_scheduled:
		music_timer -= delta
		if music_timer <= 0.0:
			music_scheduled = false
			_start_echo_speakers()

	blackout_duration -= delta
	if blackout_duration <= 0.0:
		_end_blackout_event()
	else:
		_update_echo_speakers(delta)

func _start_echo_speakers():
	if not player or not daisy_bell_stream:
		return
	print("[LEVEL FUN] Daisy Bell echo starts playing from all around in darkness...")
	var bus_name = _ensure_fun_echo_bus()
	_stop_echo_speakers()

	# Размещаем 4 удалённых источника вокруг игрока в разных направлениях (север, юг, запад, восток)
	# чтобы музыка звучала отовсюду и обволакивала лабиринт эхом
	var angles = [0.0, PI * 0.5, PI, PI * 1.5]
	for a in angles:
		var dist = randf_range(28.0, 45.0)
		var sp = AudioStreamPlayer3D.new()
		sp.stream = daisy_bell_stream
		sp.bus = bus_name
		sp.unit_size = 25.0
		sp.max_distance = 120.0
		sp.volume_db = 6.0
		sp.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(sp)
		sp.global_position = player.global_position + Vector3(cos(a) * dist, L_FUN_HEIGHT - 0.2, sin(a) * dist)
		sp.finished.connect(func(): if sp and sp.playing: sp.play())
		sp.play()
		echo_speakers.append(sp)

func _update_echo_speakers(delta: float):
	if not player or echo_speakers.is_empty():
		return
	var p_pos = player.global_position
	for sp in echo_speakers:
		if is_instance_valid(sp):
			var to_sp = sp.global_position - p_pos
			to_sp.y = 0.0
			var dist = to_sp.length()
			# Источники следуют за игроком на атмосферной дистанции 30-50м
			if dist > 60.0:
				var target_pos = p_pos + to_sp.normalized() * 40.0
				target_pos.y = L_FUN_HEIGHT - 0.2
				sp.global_position = sp.global_position.lerp(target_pos, 2.0 * delta)

func _stop_echo_speakers():
	for sp in echo_speakers:
		if is_instance_valid(sp):
			sp.stop()
			sp.queue_free()
	echo_speakers.clear()

func _spawn_light(parent: Node3D, pos: Vector3, light_range: float = 10.0, energy: float = 2.2):
	var light = OmniLight3D.new()
	light.position = pos
	light.light_color = Color(1.0, 0.96, 0.90)
	light.light_energy = 0.0 if blackout_active else energy
	light.omni_range = light_range
	light.omni_attenuation = 1.2
	# Без динамических теней от десятков omni-источников (именно тени вызывают дроп FPS)
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 24.0
	light.distance_fade_length = 8.0
	parent.add_child(light)
	active_lights.append(light)

	var lamp_mesh = MeshInstance3D.new()
	var box_m = BoxMesh.new()
	box_m.size = Vector3(1.2, 0.06, 0.6)
	lamp_mesh.mesh = box_m
	lamp_mesh.material_override = lamp_material
	lamp_mesh.position = pos + Vector3(0, 0.1, 0)
	parent.add_child(lamp_mesh)
	active_lamp_meshes.append(lamp_mesh)
