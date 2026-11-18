extends Node3D

# Level -44: бесконечный монументальный бетонный комплекс.
# Порт карты "Project 546" из проекта NewGame: гигантские бетонные залы с монолитными стенами
# высотой 180 м, светлый бетонный пол, редкие подвесные световые панели на разной высоте
# и полный мрак вдалеке. Случайный спавн промышленных объектов (карго, гаражи, вышки,
# резервуары) убран: уровень должен оставаться пустым и монументальным.
#
# Генерация по секторам 60x60 м, бесконечно во все стороны, как в оригинальной карте.

signal player_fell_in_hole

const CHUNK_SIZE := 60.0
const WALL_HEIGHT := 180.0
# Дыра-провал в полу: крайне редкая (1 открытый сектор из HOLE_CHANCE_DIVISOR)
const HOLE_SIZE := 2.0
const HOLE_CHANCE_DIVISOR := 60
const LIGHT_HEIGHT := 12.0
# Радиус подгрузки секторов. В оригинале было 3; здесь 2 — туман всё равно скрывает дальше ~65 м.
const VIEW_RADIUS := 2

var player: Node3D = null
var active_chunks := {}
# Кеш дыр по секторам: при перезагрузке сектора дыра должна остаться на том же месте
var hole_cache := {}
var hole_triggered := false
var current_chunk := Vector2i(-9999, -9999)

var floor_mat: StandardMaterial3D
var wall_mat: StandardMaterial3D
var ceiling_mat: StandardMaterial3D
var cable_mat: StandardMaterial3D
var panel_frame_mat: StandardMaterial3D
var panel_light_mat: StandardMaterial3D

# --- Редкий эвент блэкаута и громкоговорителя (Roblox 3008 OST - Friday Theme) ---
var blackout_active: bool = false
var blackout_event_timer: float = 0.0
var next_blackout_time: float = 120.0 # Первый блэкаут через 120-200 сек
var music_scheduled: bool = false
var music_timer: float = 0.0
var music_speakers: Array[AudioStreamPlayer3D] = []

var friday_theme_stream = preload("res://audio/friday_theme.mp3")
var blackout_sound_stream = preload("res://audio/soundreality-sub-down-222742.mp3")

# Вызывается из backrooms_builder.gd после добавления узла в сцену
func setup(player_node: Node3D) -> void:
	player = player_node
	setup_materials()
	if player:
		current_chunk = _chunk_of(player.global_position)
	update_chunks(true)

func _process(dt: float) -> void:
	if not player or not is_instance_valid(player):
		return
	var key = _chunk_of(player.global_position)
	if key != current_chunk:
		current_chunk = key
		update_chunks(false)

	_process_blackout_event(dt)

func _chunk_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / CHUNK_SIZE)), int(floor(pos.z / CHUNK_SIZE)))

func setup_materials() -> void:
	floor_mat = StandardMaterial3D.new()
	var f_tex = load("res://level44_assets/concrete_floor.png")
	if f_tex:
		floor_mat.albedo_texture = f_tex
		floor_mat.uv1_scale = Vector3(0.2, 0.2, 0.2)
		floor_mat.uv1_triplanar = true
	else:
		floor_mat.albedo_color = Color(0.65, 0.65, 0.67)
	floor_mat.roughness = 0.8

	wall_mat = StandardMaterial3D.new()
	var w_tex = load("res://level44_assets/concrete_wall.png")
	if w_tex:
		wall_mat.albedo_texture = w_tex
		wall_mat.uv1_scale = Vector3(0.15, 0.15, 0.15)
		wall_mat.uv1_triplanar = true
	else:
		wall_mat.albedo_color = Color(0.3, 0.3, 0.32)
	wall_mat.roughness = 0.95

	ceiling_mat = StandardMaterial3D.new()
	ceiling_mat.albedo_color = Color(0.005, 0.005, 0.008)
	ceiling_mat.roughness = 1.0

	cable_mat = StandardMaterial3D.new()
	cable_mat.albedo_color = Color(0.05, 0.05, 0.06)

	panel_frame_mat = StandardMaterial3D.new()
	panel_frame_mat.albedo_color = Color(0.12, 0.13, 0.16)
	panel_frame_mat.roughness = 0.7

	panel_light_mat = StandardMaterial3D.new()
	panel_light_mat.albedo_color = Color(0.85, 0.9, 1.0)
	panel_light_mat.emission_enabled = true
	panel_light_mat.emission = Color(0.85, 0.92, 1.0)
	panel_light_mat.emission_energy_multiplier = 2.8

# Открытые залы: сеть широких залов, между ними монолитные блоки из закрытых секторов
func is_open_space(wx: float, wz: float) -> bool:
	var gx = int(floor(wx / CHUNK_SIZE))
	var gz = int(floor(wz / CHUNK_SIZE))

	if abs(gx) <= 1 and abs(gz) <= 1:
		return true

	if abs(gx) % 3 == 0 or abs(gz) % 3 == 0:
		return true

	var h = int(abs(sin(gx * 12.9898 + gz * 78.233) * 43758.5453)) % 100
	return h < 70

func update_chunks(force: bool) -> void:
	var needed = {}
	var center = current_chunk

	for cz in range(center.y - VIEW_RADIUS, center.y + VIEW_RADIUS + 1):
		for cx in range(center.x - VIEW_RADIUS, center.x + VIEW_RADIUS + 1):
			var key = Vector2i(cx, cz)
			needed[key] = true
			if not active_chunks.has(key):
				spawn_chunk(cx, cz)

	if not force:
		var to_remove = []
		for key in active_chunks.keys():
			if not needed.has(key):
				to_remove.append(key)
		for k in to_remove:
			if active_chunks[k] and is_instance_valid(active_chunks[k]):
				active_chunks[k].queue_free()
			active_chunks.erase(k)

func spawn_chunk(cx: int, cz: int) -> void:
	var chunk_node = Node3D.new()
	chunk_node.name = "Sector_%d_%d" % [cx, cz]
	chunk_node.position = Vector3(cx * CHUNK_SIZE, 0, cz * CHUNK_SIZE)
	add_child(chunk_node)
	active_chunks[Vector2i(cx, cz)] = chunk_node

	var is_open = is_open_space(cx * CHUNK_SIZE + CHUNK_SIZE * 0.5, cz * CHUNK_SIZE + CHUNK_SIZE * 0.5)

	if is_open:
		# 1. Светлый бетонный пол (с крайне редкой дырой-провалом)
		build_floor(chunk_node, cx, cz)

		# 2. Потолок / небосклон на высоте 180 м
		var ceil_mesh = MeshInstance3D.new()
		var c_pmesh = PlaneMesh.new()
		c_pmesh.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
		c_pmesh.material = ceiling_mat
		ceil_mesh.mesh = c_pmesh
		ceil_mesh.position = Vector3(CHUNK_SIZE * 0.5, WALL_HEIGHT, CHUNK_SIZE * 0.5)
		ceil_mesh.rotation.x = PI
		chunk_node.add_child(ceil_mesh)

		# 3. Граничные монолитные стены (только там, где соседний сектор закрыт)
		var north_open = is_open_space(cx * CHUNK_SIZE + CHUNK_SIZE * 0.5, (cz - 1) * CHUNK_SIZE + CHUNK_SIZE * 0.5)
		if not north_open:
			create_wall(chunk_node, Vector3(CHUNK_SIZE * 0.5, WALL_HEIGHT * 0.5, -2.0), Vector3(CHUNK_SIZE, WALL_HEIGHT, 4.0))

		var south_open = is_open_space(cx * CHUNK_SIZE + CHUNK_SIZE * 0.5, (cz + 1) * CHUNK_SIZE + CHUNK_SIZE * 0.5)
		if not south_open:
			create_wall(chunk_node, Vector3(CHUNK_SIZE * 0.5, WALL_HEIGHT * 0.5, CHUNK_SIZE + 2.0), Vector3(CHUNK_SIZE, WALL_HEIGHT, 4.0))

		var west_open = is_open_space((cx - 1) * CHUNK_SIZE + CHUNK_SIZE * 0.5, cz * CHUNK_SIZE + CHUNK_SIZE * 0.5)
		if not west_open:
			create_wall(chunk_node, Vector3(-2.0, WALL_HEIGHT * 0.5, CHUNK_SIZE * 0.5), Vector3(4.0, WALL_HEIGHT, CHUNK_SIZE))

		var east_open = is_open_space((cx + 1) * CHUNK_SIZE + CHUNK_SIZE * 0.5, cz * CHUNK_SIZE + CHUNK_SIZE * 0.5)
		if not east_open:
			create_wall(chunk_node, Vector3(CHUNK_SIZE + 2.0, WALL_HEIGHT * 0.5, CHUNK_SIZE * 0.5), Vector3(4.0, WALL_HEIGHT, CHUNK_SIZE))

		# 4. Редкие подвесные световые панели
		var rng = RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(cx, cz)) + 546

		if rng.randf() < 0.45:
			var lx = rng.randf_range(14.0, CHUNK_SIZE - 14.0)
			var lz = rng.randf_range(14.0, CHUNK_SIZE - 14.0)
			var ly = LIGHT_HEIGHT + rng.randf_range(0.0, 14.0)
			var lrot = rng.randf_range(-PI * 0.4, PI * 0.4)
			spawn_hanging_panel_light(chunk_node, Vector3(lx, ly, lz), lrot)
	else:
		# Закрытый сектор: монолитная бетонная глыба во всю высоту
		var block_body = StaticBody3D.new()
		var block_mesh = MeshInstance3D.new()
		var bmesh = BoxMesh.new()
		bmesh.size = Vector3(CHUNK_SIZE, WALL_HEIGHT, CHUNK_SIZE)
		bmesh.material = wall_mat
		block_mesh.mesh = bmesh
		block_mesh.position = Vector3(CHUNK_SIZE * 0.5, WALL_HEIGHT * 0.5, CHUNK_SIZE * 0.5)
		block_body.add_child(block_mesh)

		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(CHUNK_SIZE, WALL_HEIGHT, CHUNK_SIZE)
		col.shape = box
		col.position = Vector3(CHUNK_SIZE * 0.5, WALL_HEIGHT * 0.5, CHUNK_SIZE * 0.5)
		block_body.add_child(col)
		chunk_node.add_child(block_body)

func create_wall(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var wall_body = StaticBody3D.new()
	var wall_mesh = MeshInstance3D.new()
	var bmesh = BoxMesh.new()
	bmesh.size = size
	bmesh.material = wall_mat
	wall_mesh.mesh = bmesh
	wall_body.add_child(wall_mesh)

	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	col.shape = box
	wall_body.add_child(col)

	wall_body.position = pos
	parent.add_child(wall_body)

func spawn_hanging_panel_light(parent: Node3D, pos: Vector3, rot_y: float) -> void:
	var root_obj = Node3D.new()
	root_obj.name = "HangingPanelLight"
	root_obj.position = pos
	root_obj.rotation.y = rot_y
	parent.add_child(root_obj)

	var panel_width = 3.8
	var panel_height = 1.3
	var panel_depth = 0.12
	var cable_len = WALL_HEIGHT - pos.y

	var cable_offset = panel_width * 0.35
	for side in [-1.0, 1.0]:
		var cable = MeshInstance3D.new()
		var cmesh = CylinderMesh.new()
		cmesh.top_radius = 0.02
		cmesh.bottom_radius = 0.02
		cmesh.height = cable_len
		cmesh.material = cable_mat
		cable.mesh = cmesh
		cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cable.position = Vector3(side * cable_offset, cable_len * 0.5, 0.0)
		root_obj.add_child(cable)

	var frame = MeshInstance3D.new()
	var fmesh = BoxMesh.new()
	fmesh.size = Vector3(panel_width, panel_height, panel_depth)
	fmesh.material = panel_frame_mat
	frame.mesh = fmesh
	root_obj.add_child(frame)

	for side_z in [-1.0, 1.0]:
		var face = MeshInstance3D.new()
		var face_mesh = BoxMesh.new()
		face_mesh.size = Vector3(panel_width * 0.92, panel_height * 0.85, 0.02)
		face_mesh.material = panel_light_mat
		face.mesh = face_mesh
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		face.position = Vector3(0.0, 0.0, side_z * (panel_depth * 0.5 + 0.01))
		root_obj.add_child(face)

	var light = OmniLight3D.new()
	light.light_color = Color(0.88, 0.93, 1.0)
	# Затухание мягче физического (1.0 = inverse-square): панели висят в 12–26 м над полом,
	# при физическом затухании до бетона долетает почти ноль света и зал утопает в черноте.
	light.light_energy = 0.0 if blackout_active else 2.4
	light.omni_range = 60.0
	light.omni_attenuation = 0.55
	light.shadow_enabled = true
	light.shadow_bias = 0.15
	light.shadow_normal_bias = 2.0
	light.shadow_blur = 1.5
	light.position = Vector3(0.0, -0.6, 0.0)
	root_obj.add_child(light)

# --- Дыры-провалы в полу ---

# Есть ли в секторе дыра и где она (в локальных координатах сектора).
# Кешируется, чтобы при выгрузке/повторной подгрузке сектора дыра осталась на месте.
func hole_local_position(cx: int, cz: int) -> Vector2:
	var key = Vector2i(cx, cz)
	if hole_cache.has(key):
		return hole_cache[key]

	var result := Vector2(-1.0, -1.0)
	# В стартовом зале дыр нет: игрок не должен провалиться сразу после появления
	if not (cx == 0 and cz == 0):
		var rng = RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(cx, cz)) + 44044
		if rng.randi_range(0, HOLE_CHANCE_DIVISOR - 1) == 0:
			result = Vector2(
				rng.randf_range(HOLE_SIZE, CHUNK_SIZE - HOLE_SIZE),
				rng.randf_range(HOLE_SIZE, CHUNK_SIZE - HOLE_SIZE)
			)
	hole_cache[key] = result
	return result

func build_floor(chunk_node: Node3D, cx: int, cz: int) -> void:
	var hole := hole_local_position(cx, cz)
	if hole.x < 0.0:
		create_floor_piece(chunk_node, Vector2(CHUNK_SIZE * 0.5, CHUNK_SIZE * 0.5), Vector2(CHUNK_SIZE, CHUNK_SIZE))
		return

	var half := HOLE_SIZE * 0.5
	var north_depth := hole.y - half
	var south_depth := CHUNK_SIZE - hole.y - half
	var west_width := hole.x - half
	var east_width := CHUNK_SIZE - hole.x - half

	create_floor_piece(chunk_node, Vector2(CHUNK_SIZE * 0.5, north_depth * 0.5), Vector2(CHUNK_SIZE, north_depth))
	create_floor_piece(chunk_node, Vector2(CHUNK_SIZE * 0.5, hole.y + half + south_depth * 0.5), Vector2(CHUNK_SIZE, south_depth))
	create_floor_piece(chunk_node, Vector2(west_width * 0.5, hole.y), Vector2(west_width, HOLE_SIZE))
	create_floor_piece(chunk_node, Vector2(hole.x + half + east_width * 0.5, hole.y), Vector2(east_width, HOLE_SIZE))

	create_hole_trigger(chunk_node, hole)
	print("[LEVEL -44] Hole in sector ", cx, ", ", cz, " at ", Vector2(cx * CHUNK_SIZE, cz * CHUNK_SIZE) + hole)

func create_floor_piece(parent: Node3D, center: Vector2, size: Vector2) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var floor_body = StaticBody3D.new()
	var floor_mesh = MeshInstance3D.new()
	var pmesh = PlaneMesh.new()
	pmesh.size = size
	pmesh.material = floor_mat
	floor_mesh.mesh = pmesh
	floor_mesh.position = Vector3(center.x, 0.0, center.y)
	floor_body.add_child(floor_mesh)

	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(size.x, 0.2, size.y)
	col.shape = box
	col.position = Vector3(center.x, -0.1, center.y)
	floor_body.add_child(col)
	parent.add_child(floor_body)

func create_hole_trigger(parent: Node3D, hole: Vector2) -> void:
	var area = Area3D.new()
	area.name = "HoleTrigger"
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(HOLE_SIZE, 2.0, HOLE_SIZE)
	col.shape = shape
	area.add_child(col)
	# Ниже уровня пола: игрок входит в зону только когда уже провалился
	area.position = Vector3(hole.x, -1.1, hole.y)
	area.body_entered.connect(_on_hole_body_entered)
	parent.add_child(area)

func _on_hole_body_entered(body: Node) -> void:
	if hole_triggered:
		return
	if body.is_in_group("player") or body.name.to_lower().contains("player") or (body is CharacterBody3D and body.has_method("interact_with_door")):
		hole_triggered = true
		print("[LEVEL -44] Player fell into a hole")
		player_fell_in_hole.emit()

# --- Логика редкого блэкаута и громкоговорителя ---

func _ensure_pa_bus() -> String:
	var bus_name = "Level44PABus"
	var idx = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")

		# Эффект реверберации (эхо огромного монументального бетонного комплекса)
		var reverb = AudioEffectReverb.new()
		reverb.room_size = 0.95
		reverb.damping = 0.25
		reverb.spread = 1.0
		reverb.wet = 0.7
		reverb.dry = 0.55
		AudioServer.add_bus_effect(idx, reverb)

		# Эффект радио/мегафона/громкоговорителя (BandPass / BandLimit фильтр)
		var bandpass = AudioEffectBandPassFilter.new()
		bandpass.cutoff_hz = 1650.0
		bandpass.resonance = 0.5
		AudioServer.add_bus_effect(idx, bandpass)

		# Легкий дисторшн старых громкоговорителей
		var dist = AudioEffectDistortion.new()
		dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
		dist.drive = 0.2
		dist.post_gain = 0.0
		AudioServer.add_bus_effect(idx, dist)
	return bus_name

func trigger_blackout_event() -> void:
	if blackout_active:
		return
	blackout_active = true
	blackout_event_timer = randf_range(70.0, 110.0) # Длительность блэкаута (более минуты чисто в темноте)
	music_scheduled = true
	music_timer = randf_range(18.0, 24.0) # Примерно через 20 секунд включится музыка

	print("[LEVEL -44] Blackout event triggered! Lights OUT.")

	# Гасим свечение материала панелей
	if panel_light_mat:
		panel_light_mat.emission_enabled = false

	# Гасим все физические источники света в панелях
	_set_all_panel_lights(false)

	# Звук отключения питания (глубокий гул / вырубание подстанции)
	if blackout_sound_stream:
		var sfx = AudioStreamPlayer.new()
		sfx.stream = blackout_sound_stream
		sfx.volume_db = 10.0
		add_child(sfx)
		sfx.play()
		sfx.finished.connect(func(): if is_instance_valid(sfx): sfx.queue_free())

func _set_all_panel_lights(on: bool) -> void:
	for chunk in active_chunks.values():
		if is_instance_valid(chunk):
			var lights = chunk.find_children("*", "OmniLight3D", true, false)
			for l in lights:
				l.light_energy = 2.4 if on else 0.0

func _process_blackout_event(dt: float) -> void:
	if not blackout_active:
		next_blackout_time -= dt
		if next_blackout_time <= 0.0:
			trigger_blackout_event()
			next_blackout_time = randf_range(160.0, 300.0) # Следующий редкий блэкаут
		return

	# Если блэкаут активен:
	if music_scheduled:
		music_timer -= dt
		if music_timer <= 0.0:
			music_scheduled = false
			_start_pa_broadcast()

	blackout_event_timer -= dt
	if blackout_event_timer <= 0.0:
		_end_blackout_event()

func _start_pa_broadcast() -> void:
	if not friday_theme_stream or not player:
		return
	print("[LEVEL -44] PA Announcement: Friday Theme starting in the distance with echo...")

	var bus_name = _ensure_pa_bus()
	_stop_pa_broadcast()

	# Размещаем удаленные источники звука на оптимальном расстоянии (60-90м)
	var angles = [0.15, -PI * 0.7]
	for a in angles:
		var dist = randf_range(60.0, 90.0)
		var sp_pos = player.global_position + Vector3(cos(a) * dist, randf_range(20.0, 32.0), sin(a) * dist)

		var sp = AudioStreamPlayer3D.new()
		sp.stream = friday_theme_stream
		sp.bus = bus_name
		sp.unit_size = 30.0
		sp.max_distance = 350.0
		sp.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		sp.volume_db = 4.0 # Оптимальная громкость: отчётливо слышно, но всё ещё отдалённо
		sp.max_db = 2.0
		sp.global_position = sp_pos
		add_child(sp)
		sp.play()
		music_speakers.append(sp)

func _stop_pa_broadcast() -> void:
	for sp in music_speakers:
		if is_instance_valid(sp):
			sp.stop()
			sp.queue_free()
	music_speakers.clear()

func _end_blackout_event() -> void:
	blackout_active = false
	music_scheduled = false
	print("[LEVEL -44] Power restored! Lights ON.")

	if panel_light_mat:
		panel_light_mat.emission_enabled = true

	_set_all_panel_lights(true)

	# Плавное угасание трансляции
	var tween = create_tween()
	for sp in music_speakers:
		if is_instance_valid(sp):
			tween.tween_property(sp, "volume_db", -80.0, 4.0)
	tween.tween_callback(Callable(self, "_stop_pa_broadcast"))

func _exit_tree() -> void:
	_stop_pa_broadcast()

