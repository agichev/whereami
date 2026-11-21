extends Node3D

@onready var corridors_root = $Corridors

var wall_tex = preload("res://kane_wallpaper.png")
var carpet_tex = preload("res://kane_carpet.png")
var ceil_tex = preload("res://kane_ceiling.png")
var ambient_stream = preload("res://audio/level0_ambience_new.mp3")

# Каноничные пропорции Kane Pixels Backrooms Level 0:
const CELL_SIZE = 2.0
const BLOCK_CELLS = 8
const CHUNK_SIZE = CELL_SIZE * BLOCK_CELLS # 16.0м
const CEIL_HEIGHT = 3.2
var view_radius: int = 5 # По умолчанию увеличен до 5 чанков (~160 метров дальность)

var wall_mat: StandardMaterial3D
var carpet_mat: StandardMaterial3D
var ceil_mat: StandardMaterial3D
var lamp_mat: StandardMaterial3D
var lamp_off_mat: StandardMaterial3D
var baseboard_mat: StandardMaterial3D

var active_chunks = {}
var spawned_decal_positions: Array[Vector2] = []
var spawned_furniture_positions: Array[Vector2] = []
var active_omni_lights: Array[OmniLight3D] = []
var active_lamp_meshes: Array[MeshInstance3D] = []
var is_blackout: bool = false
var player: Node3D = null
var current_player_chunk = Vector2i(-9999, -9999)
var world_seed: int = 19910704

var start_menu_scene = preload("res://start_menu.tscn")
var npc_hazmat_scene = preload("res://npc_hazmat.tscn")
var npc_bacteria_scene = preload("res://npc_bacteria.tscn")
var hey_audio_stream = preload("res://audio/hey.mp3")
var ambience_player: AudioStreamPlayer = null
var spawned_npc: CharacterBody3D = null
var spawned_bacteria: CharacterBody3D = null

# Механика Уровней и Noclip:
var current_level: int = 0 # 0 = Level 0 (Backrooms), 1 = Level 1 (Habitable Zone), 89 = Level 89 (Urban Evening City)
# Логирование уровней, в которых игрок уже побывал за прохождение:
# при случайной телепортации (через дверь или сквозь пол) шанс попасть на
# НОВЫЙ уровень выше, чем на уже посещённый.
var visited_levels: Array[int] = [0] # Игрок стартует на Уровне 0
const NEW_LEVEL_WEIGHT: float = 10.0 # Вес шанса на непосещённый уровень
const VISITED_LEVEL_WEIGHT: float = 1.0 # Вес шанса на уже посещённый уровень
# Идёт переход между уровнями (видео-катсцена). Второй переход в это время игнорируется:
# иначе запоздавший колбэк старого видео вызывает setup прошлого уровня поверх нового
# (подсовывал чужие чанки и сбрасывал дальность прорисовки).
var is_transitioning: bool = false
var has_escaped_monster_once: bool = false # Флаг успешного побега от монстра (активирует шанс 1%)
var noclip_chunks = {} # Чанки с отсутствующим полом (noclip)
var is_falling_to_level89: bool = false
var fall_timer: float = 0.0
var test_z_timer: float = -1.0 # Таймер активации noclip по читкоду (5 секунд)
var test_level1_timer: float = -1.0 # Таймер читкода "plm" для телепортации на Level 1
var cheat_buffer: String = ""
var flashlight_before_cheat: bool = false
var cheat_clear_timer: float = 0.0
# Ассеты Уровня 89 (Urban Liminal City):
var urban_road_straight = preload("res://urban_level89/road_1_straight.glb")
var urban_road_junction = preload("res://urban_level89/road_1_junction.glb")
var urban_street_light = preload("res://urban_level89/street_light.glb")
var urban_building_brick = preload("res://urban_level89/flat_square_brick.glb")
var urban_building_concrete = preload("res://urban_level89/flat_square_concrete.glb")
var urban_building_lshape = preload("res://urban_level89/flat_Lshape_brick.glb")
var urban_dumpster = preload("res://urban_level89/dumpster_diagonal_closed.glb")
var urban_door_model = preload("res://urban_level89/brick_wall_door.glb")

var grass_mat: StandardMaterial3D = null
var sidewalk_mat: StandardMaterial3D = null
var crowd_ambient_stream = preload("res://audio/zvuk-tolpy-ljudej.mp3")
var level89_audio_player: AudioStreamPlayer = null
var level89_songs: Array = [
	preload("res://audio/burning_memory.mp3"),
	preload("res://audio/the_lobotomy.mp3")
]
var is_level89_playing_music: bool = false
var urban_observer_scene = preload("res://urban_observer.tscn")
var spawned_urban_observer: Node3D = null
var urban_observer_timer: float = 0.0
const URBAN_OBSERVER_INTERVAL: float = 18.0 # Проверка появления каждые 18 секунд

# Уровень -44: бесконечный монументальный бетонный комплекс (порт карты "Project 546")
var level44_script = preload("res://level_minus44.gd")
var level44_generator: Node3D = null
var level44_exit_door: Node3D = null
var level44_audio_player: AudioStreamPlayer = null
var level44_ost_stream = preload("res://audio/level44_night_theme.ogg")

# Уровень "!" (Level Run: Run For Your Life!)
var level_run_script = preload("res://level_run.gd")
var level_run_generator: Node3D = null
var exit_drawing_touch_count: int = 0 # Счетчик касаний рисунка с надписью EXIT (2 касания = переход на Level !)
var last_exit_touch_time: float = -999.0

# Ассеты Уровня 1 (Level 1: Habitable Zone - Бетонный склад/парковка с лужами и мерцающими лампами):
var level1_pillar_model = preload("res://level1_assets/GLB/MOD_21_Pillar_Square.glb")
var level1_lamp_model = preload("res://level1_assets/GLB/PROP_01_FluorescentFixture.glb")
var level1_ambience_stream = preload("res://audio/level1_ambience.mp3")
var level1_audio_player: AudioStreamPlayer = null
var blackout_sound_stream = preload("res://audio/soundreality-sub-down-222742.mp3")
var blackout_audio_player: AudioStreamPlayer = null

# Механика Смайлеров и блэкаута на Уровне 1
var smiler_script = preload("res://smiler_enemy.gd")
var spawned_smilers: Array[CharacterBody3D] = []
var level1_blackout_timer: float = 0.0
var level1_next_blackout_delay: float = 60.0
var level1_is_blackout: bool = false
var level1_blackout_duration: float = 0.0
var level1_smiler_spawn_timer: float = 0.0
var level1_floor_mat: StandardMaterial3D = null
var level1_ceil_mat: StandardMaterial3D = null
var level1_pillar_mat: StandardMaterial3D = null
var level1_wall_mat: StandardMaterial3D = null
var level1_pipe_mat: StandardMaterial3D = null
var level1_pipe_red_mat: StandardMaterial3D = null
var level1_pipe_rusty_mat: StandardMaterial3D = null
var level1_pipe_steel_mat: StandardMaterial3D = null
var level1_pipe_wheel_mat: StandardMaterial3D = null
var level1_puddle_materials: Array[StandardMaterial3D] = []

var level1_prop_elec_box = preload("res://level1_assets/GLB/PROP_02_ElectricalBox.glb")
var level1_prop_cables = preload("res://level1_assets/GLB/PROP_03_CableDetail.glb")
var level1_prop_vent = preload("res://level1_assets/GLB/MOD_27_WallVent.glb")
var level1_road_signs: Array[PackedScene] = [
	preload("res://level1_assets/signs/Sign_01.glb"),
	preload("res://level1_assets/signs/Sign_02.glb"),
	preload("res://level1_assets/signs/Sign_03.glb"),
	preload("res://level1_assets/signs/Sign_04.glb"),
	preload("res://level1_assets/signs/Sign_05.glb"),
	preload("res://level1_assets/signs/Sign_06.glb"),
	preload("res://level1_assets/signs/Sign_07.glb"),
	preload("res://level1_assets/signs/Sign_08.glb"),
	preload("res://level1_assets/signs/Sign_09.glb")
]

# Модульные трубы Modular_Pipes
var level1_pipe_4m_mesh = preload("res://level1_assets/pipes/Pipe_4m.obj")
var level1_pipe_2m_mesh = preload("res://level1_assets/pipes/Pipe_2m.obj")
var level1_pipe_1m_mesh = preload("res://level1_assets/pipes/Pipe_1m.obj")
var level1_pipe_t_mesh = preload("res://level1_assets/pipes/Pipe_1m_T.obj")
var level1_pipe_valve_mesh = preload("res://level1_assets/pipes/Pipe_1m_valve.obj")
var level1_pipe_valve_wheel_mesh = preload("res://level1_assets/pipes/Valve_wheel.obj")
var level1_pipe_bend_mesh = preload("res://level1_assets/pipes/Pipe_1m_bend_90.obj")
var level1_pipe_mat_textured: StandardMaterial3D = null

# PSX материалы мебели
var psx_wood_mat: StandardMaterial3D
var psx_fabric_mat: StandardMaterial3D
var psx_plastic_mat: StandardMaterial3D
var psx_screen_mat: StandardMaterial3D
var psx_metal_mat: StandardMaterial3D

# Прелоад моделей мебели
var fbx_sofa_a = preload("res://furniture/Low Poly Furniture/Sofas/Sofa A.fbx")
var fbx_sofa_b = preload("res://furniture/Low Poly Furniture/Sofas/Sofa B.fbx")
var fbx_drawer_a = preload("res://furniture/Low Poly Furniture/Drawers/Drawer A.fbx")
var fbx_desk = preload("res://furniture/Low Poly Furniture/Tables/Desk.fbx")
var fbx_chair_a = preload("res://furniture/Low Poly Furniture/Chairs/Chair A.fbx")
var fbx_tv_a = preload("res://furniture/Low Poly Furniture/Electronics/TV A.fbx")
var fbx_tv_b = preload("res://furniture/Low Poly Furniture/Electronics/TV B.fbx")
var fbx_lamp_a = preload("res://furniture/Low Poly Furniture/Lights/Lamp A.fbx")
var fbx_clock = preload("res://furniture/Low Poly Furniture/Miscellaneous/Clock.fbx")

# Прелоад интерактивной двери
var interactive_door_script = preload("res://interactive_door.gd")
var spawned_door_positions: Array[Vector2] = []

# Механика случайного спавна Hazmat NPC: раз в минуту с шансом 5% (если не спавнится 5 раз -> шанс растет)
var npc_spawn_timer: float = 0.0
var npc_failed_spawn_checks: int = 0
const CHECK_INTERVAL: float = 60.0 # 1 минута

# Механика каноничного наблюдателя (Bacteria): раз в 80 секунд с редким шансом 18%
var bacteria_peeker_timer: float = 0.0
const BACTERIA_PEEKER_INTERVAL: float = 80.0

# Динамический шанс агра Бактерии на Уровне 0:
# Каждые 5 минут игры на Уровне 0 базовый шанс агра (18%) увеличивается (например, +15% за каждые 5 мин)
# При нападении (переходе в погоню) таймер и шанс сбрасываются обратно к базовому значению.
var level0_bacteria_time: float = 0.0
const BACTERIA_BASE_AGGRO_CHANCE: float = 0.18
const BACTERIA_AGGRO_STEP_INTERVAL: float = 300.0 # 5 минут (300 сек)
const BACTERIA_AGGRO_BONUS_PER_STEP: float = 0.15 # +15% каждые 5 минут

# Механика случайных пугающих звуков Backrooms (вдали, за стеной, в вентиляции)
# Примечание: исключены любые голоса NPC/Бактерии, чтобы они звучали ТОЛЬКО при реальном появлении сущности!
var ambient_spooky_sounds: Array = [
	{
		"stream": preload("res://audio/0008753.mp3"),
		"type": "behind_wall", # Скрежет / шорох прямо за тонкой перегородкой стены
		"min_dist": 3.5,
		"max_dist": 6.5,
		"volume": 4.0
	},
	{
		"stream": preload("res://audio/zvuki-shagi-straydera.mp3"),
		"type": "distant_steps", # Тяжелые шаги страйдера / шагохода вдалеке
		"min_dist": 20.0,
		"max_dist": 35.0,
		"volume": 6.0
	},
	{
		"stream": preload("res://audio/Metal_random tapping.wav"),
		"type": "wall_tap", # Случайные металлические постукивания по трубам
		"min_dist": 4.0,
		"max_dist": 12.0,
		"volume": 1.0
	},
	{
		"stream": preload("res://audio/Mechanical Moan and Creaking.wav"),
		"type": "creak", # Стоны конструкций и протяжный скрип потолка
		"min_dist": 10.0,
		"max_dist": 22.0,
		"volume": 2.0
	},
	{
		"stream": preload("res://audio/Creepy_ambience_3.wav"),
		"type": "drone_wave", # Жуткая волна гула из глубины коридоров
		"min_dist": 15.0,
		"max_dist": 30.0,
		"volume": 2.5
	},
	{
		"stream": preload("res://audio/Piano_drone_low_sustained_2.wav"),
		"type": "piano_sting", # Глубокий диссонирующий фортепианный дроун
		"min_dist": 12.0,
		"max_dist": 25.0,
		"volume": 3.0
	},
	{
		"stream": preload("res://audio/Child laugh_6.wav"),
		"type": "distant_laugh", # Едва различимый эхо-смех где-то вдалеке
		"min_dist": 18.0,
		"max_dist": 32.0,
		"volume": 1.0
	}
]

# Уникальные атмосферные звуки для Уровня 1 (Habitable Zone - бетонный индустриальный комплекс / парковка):
# Ни один звук не пересекается с Уровнем 0! Грузим через load(), а не preload, чтобы не тянуть их в память сразу
var level1_ambient_spooky_sounds: Array = []

func _init_level1_audio_pool():
	var paths_and_data = [
		{"path": "res://audio/level1/Screech_metalic_dragging_3.mp3", "type": "distant", "min": 16.0, "max": 32.0, "vol": 3.0},
		{"path": "res://audio/level1/Metal scrape_scratch.mp3", "type": "behind_wall", "min": 4.0, "max": 9.0, "vol": 3.5},
		{"path": "res://audio/level1/Door_handle_jiggle_checking if locked.mp3", "type": "behind_wall", "min": 5.0, "max": 11.0, "vol": 4.0},
		{"path": "res://audio/level1/Vent_airflow.mp3", "type": "ceiling", "min": 6.0, "max": 16.0, "vol": 2.0},
		{"path": "res://audio/level1/Drone_doom.mp3", "type": "distant", "min": 18.0, "max": 35.0, "vol": 3.0},
		{"path": "res://audio/level1/Mechanical Randomness_Spooky_4.mp3", "type": "distant", "min": 14.0, "max": 28.0, "vol": 2.5},
		{"path": "res://audio/level1/Air conditioner_Ambient.mp3", "type": "ceiling", "min": 8.0, "max": 18.0, "vol": 1.5},
		{"path": "res://audio/level1/Old House_creeky metal and wood_ambiance_7.mp3", "type": "behind_wall", "min": 6.0, "max": 14.0, "vol": 2.5},
		{"path": "res://audio/level1/Ghost_moan_2.mp3", "type": "distant", "min": 20.0, "max": 38.0, "vol": 2.0},
		{"path": "res://audio/level1/robotic_groan_3.mp3", "type": "distant", "min": 22.0, "max": 40.0, "vol": 2.5}
	]
	for item in paths_and_data:
		var st = load(item["path"]) as AudioStream
		if st:
			level1_ambient_spooky_sounds.append({
				"stream": st,
				"type": item["type"],
				"min_dist": item["min"],
				"max_dist": item["max"],
				"volume": item["vol"]
			})

var spooky_sound_timer: float = 0.0
var next_spooky_sound_delay: float = 18.0 # Интервал между атмосферными звуками (15-35 сек)

# Текстуры авторских рисунков игрока (вырезанный белый фон, прозрачный альфа-канал)
var vert_drawings: Array = [
	preload("res://decals/user_drawing_vert_1.png"),
	preload("res://decals/user_drawing_vert_2.png"),
	preload("res://decals/user_drawing_vert_3.png"),
	preload("res://decals/user_drawing_vert_4.png"),
	preload("res://decals/user_drawing_vert_5.png")
]

var horiz_drawings: Array = [
	preload("res://decals/user_drawing_horiz_1.png"),
	preload("res://decals/user_drawing_horiz_2.png"),
	preload("res://decals/user_drawing_horiz_3.png"),
	preload("res://decals/user_drawing_horiz_4.png")
]

func _ready():
	# Случайный сид мира и случайная стартовая позиция игрока при каждом запуске
	randomize()
	world_seed = randi() & 0x7FFFFFFF

	# Инициализация пула эмбиентных звуков Уровня 1
	_init_level1_audio_pool()

	# Синхронизация радиуса прорисовки чанков из настроек
	var gs = preload("res://game_settings.gd").instance
	if gs:
		view_radius = gs.chunk_render_distance
		gs.settings_changed.connect(_on_settings_changed)

	setup_materials()
	player = get_node_or_null("HazmatPlayer")
	if not player:
		player = find_child("HazmatPlayer", true, false)

	if player:
		# Случайный чанк в пределах от -30 до 30 (огромная неизведанная область)
		var rand_cx = randi_range(-30, 30)
		var rand_cz = randi_range(-30, 30)
		# В чанке гарантированный сквозной проход находится в ячейках (3, 3) и (4, 4)
		# Координаты внутри чанка: (3.5 * CELL_SIZE, 3.5 * CELL_SIZE) = (7.0, 7.0)
		var spawn_x = rand_cx * CHUNK_SIZE + 7.0
		var spawn_z = rand_cz * CHUNK_SIZE + 7.0
		player.global_position = Vector3(spawn_x, 0.1, spawn_z)
		# Случайный начальный поворот игрока по горизонтали
		var init_yaw = randf_range(0.0, TAU)
		player.rotation.y = init_yaw
		if "player_yaw" in player:
			player.player_yaw = init_yaw
	
	# До нажатия Play игра находится в абсолютной темноте меню:
	# Фоновый эмбиент НЕ играет, звуков нет, моделька отключена
	setup_start_menu()

func setup_start_menu():
	if not player:
		return
	
	player.is_active = false
	player.visual_root.visible = false
	if player.head_shadow_mesh:
		player.head_shadow_mesh.visible = false
	
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	var ui = get_node_or_null("UI")
	if not ui:
		ui = find_child("UI", true, false)
	if ui:
		var menu = start_menu_scene.instantiate()
		ui.add_child(menu)
		menu.start_cutscene_video.connect(_on_start_cutscene_video)
		menu.video_finished.connect(_on_video_finished)

func _on_start_cutscene_video():
	# Обновляем координаты текущего чанка игрока перед первой подгрузкой
	if player:
		var chunk_x = int(floor(player.global_position.x / CHUNK_SIZE))
		var chunk_z = int(floor(player.global_position.z / CHUNK_SIZE))
		current_player_chunk = Vector2i(chunk_x, chunk_z)
	# Во время видео мир подгружается в фоне!
	update_chunks_around_player()

func _on_video_finished():
	# Видео закончилось -> запускаем катсцену подъема игрока с пола!
	if player:
		player.play_getup_cutscene()
	
	# И плавно запускаем фоновый эмбиент Backrooms
	setup_ambience()

func spawn_test_npc_near_player():
	if not player or spawned_npc:
		return
	
	# Ищем свободное гарантированное место для спавна NPC рядом с игроком в коридоре
	var look_dir = -player.global_transform.basis.z.normalized()
	if look_dir.length_squared() < 0.1:
		look_dir = Vector3(0, 0, -1)
	
	var candidate_offsets = [
		look_dir * 3.0,
		look_dir * 2.5,
		look_dir * 3.5,
		Vector3(0, 0, -3.0),
		Vector3(0, 0, 3.0),
		Vector3(-2.5, 0, 0),
		Vector3(2.5, 0, 0)
	]

	var chosen_pos = player.global_position + look_dir * 3.0
	for off in candidate_offsets:
		var test_p = player.global_position + off
		test_p.y = 0.0
		if is_world_position_passable(test_p, 0.45):
			chosen_pos = test_p
			break

	chosen_pos.y = 0.0
	var npc = npc_hazmat_scene.instantiate()
	add_child(npc)
	spawned_npc = npc
	npc.global_position = chosen_pos
	npc.rotation.y = 0.0
	npc.target_player = player

func setup_materials():
	wall_mat = StandardMaterial3D.new()
	wall_mat.albedo_texture = wall_tex
	wall_mat.uv1_triplanar = true
	wall_mat.uv1_scale = Vector3(1.6, 1.6, 1.6) # Реалистичный масштаб обоев (~0.6м на полотно)
	wall_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	wall_mat.roughness = 0.95

	carpet_mat = StandardMaterial3D.new()
	carpet_mat.albedo_texture = carpet_tex
	carpet_mat.uv1_scale = Vector3(16.0, 16.0, 16.0)
	carpet_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	carpet_mat.roughness = 0.98

	ceil_mat = StandardMaterial3D.new()
	ceil_mat.albedo_texture = ceil_tex
	ceil_mat.uv1_scale = Vector3(16.0, 16.0, 16.0)
	ceil_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ceil_mat.roughness = 0.92

	lamp_mat = StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 1.0, 0.95)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.98, 0.85)
	lamp_mat.emission_energy_multiplier = 4.0

	lamp_off_mat = StandardMaterial3D.new()
	lamp_off_mat.albedo_color = Color(0.22, 0.20, 0.10)
	lamp_off_mat.roughness = 0.95

	baseboard_mat = StandardMaterial3D.new()
	baseboard_mat.albedo_color = Color(0.85, 0.78, 0.45)
	baseboard_mat.roughness = 0.7

	# Материал травы для Уровня 89
	grass_mat = StandardMaterial3D.new()
	var g_tex = load("res://grass_psx.png")
	if g_tex:
		grass_mat.albedo_texture = g_tex
	grass_mat.albedo_color = Color(0.9, 1.0, 0.85)
	grass_mat.uv1_triplanar = true
	grass_mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	grass_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	grass_mat.roughness = 0.85

	# Тротуарная плитка для кварталов Level 89
	sidewalk_mat = StandardMaterial3D.new()
	var sw_tex = load("res://urban_level89/textures/sidewalk.jpg")
	if sw_tex:
		sidewalk_mat.albedo_texture = sw_tex
	sidewalk_mat.uv1_triplanar = true
	sidewalk_mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	sidewalk_mat.roughness = 0.85

	# PSX материалы для мебели с пиксельной фильтрацией NEAREST
	psx_wood_mat = StandardMaterial3D.new()
	psx_wood_mat.albedo_texture = load("res://psx_wood.png")
	psx_wood_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	psx_wood_mat.uv1_triplanar = true
	psx_wood_mat.uv1_scale = Vector3(1.5, 1.5, 1.5)
	psx_wood_mat.roughness = 0.8

	psx_fabric_mat = StandardMaterial3D.new()
	psx_fabric_mat.albedo_texture = load("res://psx_fabric.png")
	psx_fabric_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	psx_fabric_mat.uv1_triplanar = true
	psx_fabric_mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
	psx_fabric_mat.roughness = 0.95

	psx_plastic_mat = StandardMaterial3D.new()
	psx_plastic_mat.albedo_texture = load("res://psx_plastic.png")
	psx_plastic_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	psx_plastic_mat.uv1_triplanar = true
	psx_plastic_mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
	psx_plastic_mat.roughness = 0.7

	psx_screen_mat = StandardMaterial3D.new()
	psx_screen_mat.albedo_texture = load("res://psx_screen.png")
	psx_screen_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	psx_screen_mat.uv1_triplanar = true
	psx_screen_mat.uv1_scale = Vector3(2.5, 2.5, 2.5)
	psx_screen_mat.roughness = 0.2
	psx_screen_mat.metallic = 0.1

	psx_metal_mat = StandardMaterial3D.new()
	psx_metal_mat.albedo_texture = load("res://psx_metal.png")
	psx_metal_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	psx_metal_mat.uv1_triplanar = true
	psx_metal_mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
	psx_metal_mat.roughness = 0.5
	psx_metal_mat.metallic = 0.4

	# Материалы Уровня 1 (Бетонный склад/парковка, лужи конденсата, трубы)
	level1_floor_mat = StandardMaterial3D.new()
	var l1_conc_tex = load("res://level1_assets/Models pack psx/Texture/Concrete.png")
	if l1_conc_tex:
		level1_floor_mat.albedo_texture = l1_conc_tex
	level1_floor_mat.albedo_color = Color(0.75, 0.75, 0.73)
	level1_floor_mat.uv1_triplanar = true
	level1_floor_mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	level1_floor_mat.roughness = 0.65

	level1_ceil_mat = StandardMaterial3D.new()
	var l1_ceil_tex = load("res://level1_assets/Models pack psx/Texture/ceiling.png")
	if l1_ceil_tex:
		level1_ceil_mat.albedo_texture = l1_ceil_tex
	level1_ceil_mat.albedo_color = Color(0.55, 0.55, 0.55)
	level1_ceil_mat.uv1_triplanar = true
	level1_ceil_mat.uv1_scale = Vector3(0.4, 0.4, 0.4)
	level1_ceil_mat.roughness = 0.9

	level1_pillar_mat = StandardMaterial3D.new()
	var l1_pil_tex = load("res://level1_assets/Models pack psx/Texture/Concrete_01.jpg")
	if l1_pil_tex:
		level1_pillar_mat.albedo_texture = l1_pil_tex
	level1_pillar_mat.albedo_color = Color(0.8, 0.8, 0.78)
	level1_pillar_mat.uv1_triplanar = true
	level1_pillar_mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	level1_pillar_mat.roughness = 0.8

	# Материал бетонных стен для технических коридоров
	level1_wall_mat = StandardMaterial3D.new()
	var l1_wall_tex = load("res://level1_assets/Models pack psx/Texture/Concrete_02.png")
	if not l1_wall_tex:
		l1_wall_tex = load("res://level1_assets/Models pack psx/Texture/Concrete_03.jpg")
	if l1_wall_tex:
		level1_wall_mat.albedo_texture = l1_wall_tex
	level1_wall_mat.albedo_color = Color(0.82, 0.82, 0.80)
	level1_wall_mat.uv1_triplanar = true
	level1_wall_mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
	level1_wall_mat.roughness = 0.85

	# Вариации материалов для труб Уровня 1:
	# 1. Красная труба (противопожарная магистраль)
	level1_pipe_red_mat = StandardMaterial3D.new()
	level1_pipe_red_mat.albedo_color = Color(0.72, 0.16, 0.14)
	level1_pipe_red_mat.roughness = 0.4
	level1_pipe_red_mat.metallic = 0.55

	# 2. Ржавая труба (коррозия)
	level1_pipe_rusty_mat = StandardMaterial3D.new()
	var pipe_tex = load("res://level1_assets/pipes/1k_Modular_Pipes_Tex0.png")
	if pipe_tex:
		level1_pipe_rusty_mat.albedo_texture = pipe_tex
	else:
		level1_pipe_rusty_mat.albedo_color = Color(0.38, 0.22, 0.14)
	level1_pipe_rusty_mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	level1_pipe_rusty_mat.roughness = 0.85
	level1_pipe_rusty_mat.metallic = 0.25

	# 3. Просто железная труба (гальванизированная сталь/металл)
	level1_pipe_steel_mat = StandardMaterial3D.new()
	level1_pipe_steel_mat.albedo_color = Color(0.68, 0.70, 0.72)
	level1_pipe_steel_mat.roughness = 0.35
	level1_pipe_steel_mat.metallic = 0.85

	# Ярко-красный маховик вентиля
	level1_pipe_wheel_mat = StandardMaterial3D.new()
	level1_pipe_wheel_mat.albedo_color = Color(0.85, 0.14, 0.12)
	level1_pipe_wheel_mat.roughness = 0.5
	level1_pipe_wheel_mat.metallic = 0.4

	level1_pipe_mat = level1_pipe_red_mat

	level1_puddle_materials.clear()
	for p_idx in range(3):
		var p_mat = StandardMaterial3D.new()
		var p_tex = load("res://level1_assets/puddle_shape_%d.png" % p_idx)
		if p_tex:
			p_mat.albedo_texture = p_tex
		# Прозрачная вода с легким отражением света пола: НЕ черная смола, а прозрачная влага
		p_mat.albedo_color = Color(0.85, 0.88, 0.90, 0.22)
		p_mat.roughness = 0.02 # Идеальный зеркальный блеск воды и отражение ламп
		p_mat.metallic = 0.0
		p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		p_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		p_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		level1_puddle_materials.append(p_mat)

func setup_ambience():
	if ambience_player:
		return
	ambience_player = AudioStreamPlayer.new()
	ambience_player.name = "LevelAmbience"
	ambience_player.stream = ambient_stream
	ambience_player.volume_db = -4.0
	ambience_player.autoplay = true
	add_child(ambience_player)
	ambience_player.play()

func _process(delta):
	# Сброс буфера ввода читов по таймауту
	if cheat_clear_timer > 0.0:
		cheat_clear_timer -= delta
		if cheat_clear_timer <= 0.0:
			cheat_buffer = ""

	# Обработка таймера читкода "ui" (создание noclip чанка под игроком через 5 секунд)
	if test_z_timer > 0.0:
		test_z_timer -= delta
		if test_z_timer <= 0.0:
			test_z_timer = -1.0
			_make_current_chunk_noclip()

	# Обработка таймера читкода "plm" (телепорт на Level 1 через noclip через 5 секунд)
	if test_level1_timer > 0.0:
		test_level1_timer -= delta
		if test_level1_timer <= 0.0:
			test_level1_timer = -1.0
			_transition_to_level_1()

	if player:
		# Проверка падения сквозь noclip или провалы ниже пола (на всех уровнях с полом)
		if player.global_position.y < -0.6 and not is_falling_to_level89:
			is_falling_to_level89 = true
			fall_timer = 0.0

		if is_falling_to_level89:
			fall_timer += delta
			if fall_timer >= 2.5: # Падал 2.5 секунды
				is_falling_to_level89 = false
				_transition_to_random_level()
				return

		var px = player.global_position.x
		var pz = player.global_position.z
		var chunk_x = int(floor(px / CHUNK_SIZE))
		var chunk_z = int(floor(pz / CHUNK_SIZE))
		var p_chunk = Vector2i(chunk_x, chunk_z)

		# На Уровне -44 своя генерация секторов: стриминг чанков других уровней только мешает
		# (иначе поверх бетонного комплекса достраивались стены Уровня 0 и игрок стоял внутри них)
		if p_chunk != current_player_chunk and current_level != -44:
			current_player_chunk = p_chunk
			update_chunks_around_player()

		if current_level == 0:
			# Накопление времени нахождения на Уровне 0 (увеличивает шанс агра Бактерии каждые 5 минут)
			if player and player.is_active and not is_blackout:
				level0_bacteria_time += delta

			# Проверка случайного спавна Hazmat NPC раз в минуту
			_process_npc_random_spawner(delta)

			# Проверка появления наблюдателя Bacteria (раз в 1 мин с шансом 30%)
			_process_bacteria_peeker_spawner(delta)

			# Процесс генерации случайных звуков Backrooms (вдали, за стеной, шаги)
			_process_spooky_ambient_sounds(delta)
		elif current_level == 1:
			# Процесс блэкаута и спавна Смайлеров на Уровне 1
			_process_level1_smilers_and_blackout(delta)
			# Процесс генерации уникальных звуков Уровня 1 (вентиляция, скрежет металла, дергание ручек)
			_process_spooky_ambient_sounds(delta)
		elif current_level == 89:
			# Появление темного наблюдателя вдалеке за спиной
			_process_urban_observer_spawner(delta)

func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		# Считываем символ латинской раскладки как по unicode, так и по физическому коду клавиши
		var char_typed = ""
		var key_to_char = {
			KEY_J: "j", KEY_I: "i", KEY_L: "l", KEY_K: "k",
			KEY_Y: "y", KEY_O: "o", KEY_U: "u", KEY_P: "p",
			KEY_M: "m", KEY_S: "s", KEY_G: "g", KEY_H: "h",
			KEY_E: "e", KEY_W: "w", KEY_F: "f", KEY_R: "r", KEY_N: "n",
			KEY_X: "x", KEY_T: "t"
		}

		if key_to_char.has(event.keycode):
			char_typed = key_to_char[event.keycode]
		elif key_to_char.has(event.physical_keycode):
			char_typed = key_to_char[event.physical_keycode]
		elif event.unicode > 0:
			var c = char(event.unicode).to_lower()
			# Поддержка русской раскладки на клавиатуре (ЙЦУКЕН)
			var ru_to_en = {
				"о": "j", "ш": "i", "д": "l", "л": "k",
				"н": "y", "щ": "o", "г": "u", "з": "p",
				"ь": "m", "ы": "s", "п": "g", "р": "h",
				"у": "e", "ц": "w", "а": "f", "к": "r", "т": "n", "х": "x"
			}
			if ru_to_en.has(c):
				char_typed = ru_to_en[c]
			elif c >= "a" and c <= "z":
				char_typed = c

		if char_typed != "":
			if cheat_buffer == "" and player and player.get("flashlight_light"):
				flashlight_before_cheat = player.flashlight_light.visible
			cheat_buffer += char_typed
			cheat_clear_timer = 3.0 # Сброс буфера если не печатали 3 сек
			_check_cheat_codes()

func _check_cheat_codes():
	# Читкод "opl" - на уровне 89 включает рандомную песню вместо эмбиента
	if cheat_buffer.ends_with("opl"):
		cheat_buffer = ""
		print("[CHEAT] Play random song on Level 89 (opl)")
		play_random_level89_song()
		return

	# Читкод "lhm" (или "lfm") - телепорт на Уровень -44 (монументальный бетонный комплекс)
	if cheat_buffer.ends_with("lhm") or cheat_buffer.ends_with("lfm"):
		var typed_f := cheat_buffer.ends_with("lfm")
		cheat_buffer = ""
		# Клавиша F в игре переключает фонарик, поэтому при наборе "lfm" он переключается.
		# Возвращаем фонарь в то состояние, что было до набора чита.
		if typed_f and player and player.has_method("_set_flashlight_enabled"):
			player._set_flashlight_enabled(flashlight_before_cheat)
		print("[CHEAT] Go to Level -44 (lhm)")
		_transition_to_level_minus44()
		return

	# Читкод "run" - телепорт на Уровень "!" (Level Run)
	if cheat_buffer.ends_with("run"):
		cheat_buffer = ""
		print("[CHEAT] Go to Level ! (run)")
		_transition_to_level_run()
		return

	# 6. Читкод "klm" - спавнит дверь по направлению взгляда на ближайшей стене
	if cheat_buffer.ends_with("klm"):
		cheat_buffer = ""
		print("[CHEAT] Spawn Door on Looked Wall (klm)")
		_cheat_spawn_door_on_wall()
		return

	# Читкод "exit" - спавнит рисунок EXIT (user_drawing_vert_5) на стене перед игроком
	if cheat_buffer.ends_with("exit"):
		cheat_buffer = ""
		print("[CHEAT] Spawn EXIT drawing on Looked Wall (exit)")
		_cheat_spawn_exit_drawing_on_wall()
		return

	# Читкод "ghi" (или "sml") - вызывает отключение света (на Уровне 1 запускает блэкаут со Смайлерами, на Уровне 0 — блэкаут комнат, на Уровне -44 — блэкаут с оповещением)
	if cheat_buffer.ends_with("ghi") or cheat_buffer.ends_with("sml"):
		cheat_buffer = ""
		print("[CHEAT] Trigger Blackout (ghi)")
		if current_level == 1:
			_trigger_level1_blackout()
		elif current_level == 0:
			trigger_global_blackout()
		elif current_level == -44:
			if level44_generator and is_instance_valid(level44_generator) and level44_generator.has_method("trigger_blackout_event"):
				level44_generator.trigger_blackout_event()
		return

	if current_level == 0:
		# 1. Читкод "jil" - спавнит бактерию стандартно
		if cheat_buffer.ends_with("jil"):
			cheat_buffer = ""
			print("[CHEAT] Spawn Bacteria Peeker (jil)")
			spawn_bacteria_peeker(false)
			return

		# 2. Читкод "jkl" - спавнит бактерию и гарантированно начинает погоню
		if cheat_buffer.ends_with("jkl"):
			cheat_buffer = ""
			print("[CHEAT] Spawn Bacteria Aggro Chase (jkl)")
			spawn_bacteria_peeker(true)
			return

		# 3. Читкод "you" - спавнит Hazmat монстра
		if cheat_buffer.ends_with("you"):
			cheat_buffer = ""
			print("[CHEAT] Spawn Hazmat (you)")
			spawn_hazmat_behind_player()
			return

		# 4. Читкод "ui" отключен по требованию (провалиться через читкод нельзя, только через дверь klm)
		# 5. Читкод "plm" отключен по требованию (провалиться через читкод нельзя, только через дверь klm)

# Читкод "klm": спавн двери прямо перед взглядом игрока на ближайшей стене
func _cheat_spawn_door_on_wall():
	if not player:
		return
	var cam = player.find_child("Camera3D", true, false)
	if not cam:
		return

	var space_state = get_world_3d().direct_space_state
	var from = cam.global_position
	var dir = -cam.global_transform.basis.z.normalized()
	var to = from + dir * 18.0

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player]
	var hit = space_state.intersect_ray(query)
	if hit.is_empty():
		print("[CHEAT DOOR] No wall found in line of sight")
		return

	var hit_pos = hit.position
	var hit_norm = hit.normal
	# Игнорируем пол и потолок
	if abs(hit_norm.y) > 0.5:
		print("[CHEAT DOOR] Hit floor or ceiling, skipping")
		return

	hit_pos.y = 0.0 # Ставим на пол
	var door_inst = interactive_door_script.new()
	door_inst.level_type = 0 if current_level == 0 else 1
	door_inst.player_entered_black_void.connect(_on_door_void_entered)
	add_child(door_inst)

	door_inst.global_position = hit_pos
	# Поворачиваем дверь лицом наружу от стены
	door_inst.rotation.y = atan2(hit_norm.x, hit_norm.z)
	print("[CHEAT DOOR] Successfully spawned door at: ", hit_pos)

# Читкод "exit": спавнит рисунок EXIT (user_drawing_vert_5) прямо на стене перед взглядом игрока
func _cheat_spawn_exit_drawing_on_wall():
	if not player:
		return
	var cam = player.find_child("Camera3D", true, false)
	if not cam:
		return

	var space_state = get_world_3d().direct_space_state
	var from = cam.global_position
	var dir = -cam.global_transform.basis.z.normalized()
	var to = from + dir * 18.0

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player]
	var hit = space_state.intersect_ray(query)
	if hit.is_empty():
		print("[CHEAT EXIT] No wall found in line of sight")
		return

	var hit_pos = hit.position
	var hit_norm = hit.normal
	if abs(hit_norm.y) > 0.5:
		print("[CHEAT EXIT] Hit floor or ceiling, skipping")
		return

	# Создаем QuadMesh с рисунком EXIT (vert_drawings[4])
	var quad = MeshInstance3D.new()
	quad.name = "CheatExitDrawing"
	var p_mesh = QuadMesh.new()
	p_mesh.size = Vector2(1.62, 2.88)
	quad.mesh = p_mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_texture = vert_drawings[4]
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness = 0.95
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	quad.material_override = mat

	# Смещаем на 5 мм наружу от стены по нормали
	quad.global_position = hit_pos + hit_norm * 0.008
	quad.global_position.y = 1.56 # Центр по высоте
	quad.rotation.y = atan2(hit_norm.x, hit_norm.z)

	add_child(quad)
	# Добавляем интерактивную зону касания для перехода на Level !
	_setup_exit_drawing_interaction(self, quad)
	print("[CHEAT EXIT] Successfully spawned EXIT drawing at: ", hit_pos)

func _on_door_void_entered(_door):
	_transition_to_random_level()

func _make_current_chunk_noclip():
	if not player or current_level != 0:
		return
	var c = current_player_chunk
	noclip_chunks[c] = true
	# Если чанк уже загружен — убираем коллизию, но оставляем видимый ковер!
	if active_chunks.has(c):
		var chunk_node = active_chunks[c]
		var floor_b = chunk_node.find_child("FloorBody", true, false)
		if floor_b:
			var old_pos = floor_b.position
			floor_b.queue_free()
			
			var visual_floor = Node3D.new()
			visual_floor.name = "FloorNoclip"
			visual_floor.position = old_pos
			var floor_mesh = MeshInstance3D.new()
			var p_mesh = PlaneMesh.new()
			p_mesh.size = Vector2(CHUNK_SIZE + 0.05, CHUNK_SIZE + 0.05)
			floor_mesh.mesh = p_mesh
			floor_mesh.material_override = carpet_mat
			visual_floor.add_child(floor_mesh)
			chunk_node.add_child(visual_floor)

func _process_spooky_ambient_sounds(delta: float):
	if not player or not player.is_active or is_blackout:
		return

	spooky_sound_timer += delta
	if spooky_sound_timer >= next_spooky_sound_delay:
		spooky_sound_timer = 0.0

		# С шансом 10% наступает "мертвая тишина": в течение 90 секунд играет ТОЛЬКО эмбиент ламп
		if randf() < 0.10:
			next_spooky_sound_delay = 90.0 # Ровно 90 секунд тишины без шорохов и криков
		else:
			next_spooky_sound_delay = randf_range(16.0, 36.0) # Обычный интервал
			play_random_spooky_ambient_sound()

func play_random_spooky_ambient_sound():
	if not player:
		return

	# Выбираем пул звуков строго в соответствии с текущим уровнем
	var sound_pool = level1_ambient_spooky_sounds if current_level == 1 else ambient_spooky_sounds
	if sound_pool.is_empty():
		return

	var s_data = sound_pool[randi() % sound_pool.size()]
	var stream = s_data["stream"]
	var sound_type = s_data["type"]
	var min_dist = s_data.get("min_dist", 8.0)
	var max_dist = s_data.get("max_dist", 20.0)
	var vol = s_data.get("volume", 3.0)

	var p_pos = player.global_position
	var sound_pos = p_pos

	# В зависимости от типа звука генерируем его источник в пространстве:
	if sound_type == "behind_wall":
		# Звук за стенкой: выбираем перпендикулярный вектор на короткой дистанции (3.5 - 6м)
		var right_dir = player.global_transform.basis.x.normalized()
		var sign_dir = 1.0 if randf() > 0.5 else -1.0
		sound_pos = p_pos + right_dir * (randf_range(min_dist, max_dist) * sign_dir)
		sound_pos += player.global_transform.basis.z.normalized() * randf_range(-2.0, 2.0)
		sound_pos.y = randf_range(0.8, 1.8)
	elif sound_type == "ceiling":
		# Звук вентиляции или кондиционера под потолком
		var rand_angle = randf() * TAU
		var dir = Vector3(cos(rand_angle), 0, sin(rand_angle)).normalized()
		sound_pos = p_pos + dir * randf_range(min_dist, max_dist)
		sound_pos.y = CEIL_HEIGHT - 0.2
	else:
		# Звук где-то вдалеке по коридорам: случайное круговое направление
		var rand_angle = randf() * TAU
		var dir = Vector3(cos(rand_angle), 0, sin(rand_angle)).normalized()
		sound_pos = p_pos + dir * randf_range(min_dist, max_dist)
		sound_pos.y = randf_range(0.8, 2.8)

	# Создаем динамический 3D источник звука
	var p3d = AudioStreamPlayer3D.new()
	p3d.stream = stream
	p3d.volume_db = vol
	p3d.unit_size = 4.0
	p3d.max_distance = max_dist * 2.2
	p3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p3d.global_position = sound_pos
	add_child(p3d)

	p3d.finished.connect(func(): p3d.queue_free())
	p3d.play()

func _process_bacteria_peeker_spawner(delta: float):
	if not player or not player.is_active or is_blackout:
		return

	# Если наблюдатель уже активен — ждем пока он уйдет
	if spawned_bacteria and is_instance_valid(spawned_bacteria):
		return

	bacteria_peeker_timer += delta
	if bacteria_peeker_timer >= BACTERIA_PEEKER_INTERVAL:
		bacteria_peeker_timer = 0.0

		# Редкий спавн: проверка раз в 80 сек с вероятностью 18%
		if randf() < 0.18:
			spawn_bacteria_peeker()

func _process_npc_random_spawner(delta: float):
	# Не спавним, пока игрок в меню или в катсцене
	if not player or not player.is_active:
		return

	# Если NPC уже на уровне и жив — таймер ждет
	if spawned_npc and is_instance_valid(spawned_npc):
		return

	npc_spawn_timer += delta
	if npc_spawn_timer >= CHECK_INTERVAL:
		npc_spawn_timer = 0.0

		# Расчет шанса: базовый 5%, каждые 5 неудачных попыток добавляется +5% (5 попыток -> 10%, 10 -> 15%...)
		var current_chance = 0.05 + float(int(npc_failed_spawn_checks / 5)) * 0.05
		current_chance = min(current_chance, 1.0) # максимум 100%

		var roll = randf()
		if roll < current_chance:
			# Успешный спавн сзади игрока со звуком hey.mp3
			if spawn_hazmat_behind_player():
				npc_failed_spawn_checks = 0
		else:
			npc_failed_spawn_checks += 1

func get_current_bacteria_aggro_chance() -> float:
	var steps = int(level0_bacteria_time / BACTERIA_AGGRO_STEP_INTERVAL)
	var chance = BACTERIA_BASE_AGGRO_CHANCE + float(steps) * BACTERIA_AGGRO_BONUS_PER_STEP
	return clamp(chance, 0.0, 1.0)

func reset_bacteria_aggro_timer():
	level0_bacteria_time = 0.0
	print("[BACTERIA] Aggro triggered! Level 0 aggro timer reset to base.")

func spawn_bacteria_peeker(force_aggro: bool = false):
	if not player:
		return

	# Если наблюдатель уже существует и живой — удаляем старого перед читом или спавном
	if spawned_bacteria and is_instance_valid(spawned_bacteria):
		spawned_bacteria.queue_free()
		spawned_bacteria = null

	# Получаем точную позицию и направление камеры игрока
	var cam: Camera3D = player.get_viewport().get_camera_3d()
	if not cam:
		return

	var cam_pos = cam.global_position
	var cam_fwd = -cam.global_transform.basis.z.normalized()
	var cam_right = cam.global_transform.basis.x.normalized()
	cam_fwd.y = 0.0
	cam_right.y = 0.0
	cam_fwd = cam_fwd.normalized()
	cam_right = cam_right.normalized()

	var space_state = get_world_3d().direct_space_state

	# Ищем реальные углы стен впереди и по бокам на расстоянии 12..25 метров.
	# Сущность стоит ЗА СТЕНОЙ (её центр скрыт препятствием),
	# но край её силуэта (рука/плечо/голова) выглядывает из-за угла буквально на 25-35 см!
	var found_pos = Vector3.ZERO
	var hide_dir = Vector3.ZERO
	var found = false

	# Перебираем дистанции и углы смещения относительно направления взгляда камеры
	var angles = [
		deg_to_rad(30.0), deg_to_rad(-30.0),
		deg_to_rad(45.0), deg_to_rad(-45.0),
		deg_to_rad(20.0), deg_to_rad(-20.0),
		deg_to_rad(55.0), deg_to_rad(-55.0)
	]
	var distances = [14.0, 18.0, 22.0, 12.0, 25.0]

	for d in distances:
		for a in angles:
			var dir = cam_fwd.rotated(Vector3.UP, a).normalized()
			var target_point = cam_pos + dir * d
			target_point.y = 0.0

			# Пускаем луч от глаз игрока в эту точку на высоте 1.5м
			var ray_test = PhysicsRayQueryParameters3D.create(cam_pos, target_point + Vector3(0, 1.5, 0))
			var hit = space_state.intersect_ray(ray_test)

			# Если луч врезался в стену — у нас есть препятствие!
			if not hit.is_empty():
				var hit_point = hit.position
				hit_point.y = 0.0
				var hit_dist = cam_pos.distance_to(hit_point)

				# Препятствие должно быть на хорошем расстоянии (от 10 до 25 метров)
				if hit_dist >= 10.0 and hit_dist <= 25.0:
					# Проверяем точку прямо ЗА этим углом стены (в 0.8м за гранью)
					var normal = hit.normal
					normal.y = 0.0
					normal = normal.normalized()

					# Тангенс стены
					var tangent = normal.rotated(Vector3.UP, PI * 0.5)

					# Проверяем две стороны угла: прячется за стеной
					for sign_dir in [1.0, -1.0]:
						var edge_tangent = tangent * sign_dir
						# Точка прямо за ребром угла
						var corner_edge = hit_point + edge_tangent * 0.9
						# Точка, где стоит само тело (утоплено за угол в укрытие на 0.7м)
						var body_pos = corner_edge - normal * 0.6
						body_pos.y = 0.0

						# Точка выглядывания (край тела/рука, смещенная на 0.3м к ребру)
						var peek_offset_pos = body_pos + edge_tangent * 0.4 + Vector3(0, 1.6, 0)
						# Проверяем, что точка тела проходима для коллизии
						if is_world_position_passable(body_pos, 0.4):
							# 1. Центр тела ДОЛЖЕН БЫТЬ СКРЫТ стеной от игрока (он не на открытом месте!)
							var ray_body = space_state.intersect_ray(PhysicsRayQueryParameters3D.create(cam_pos, body_pos + Vector3(0, 1.5, 0)))
							if not ray_body.is_empty():
								# 2. А выглядывающий край (peek_offset_pos) ДОЛЖЕН просматриваться игроком!
								var ray_peek = space_state.intersect_ray(PhysicsRayQueryParameters3D.create(cam_pos, peek_offset_pos))
								if ray_peek.is_empty():
									# Идеально! Тело за стеной, а часть видна краешком глаза!
									found_pos = body_pos
									# Направление отхода: глубже за стену (вглубь укрытия от игрока)
									hide_dir = (-edge_tangent - normal * 0.3).normalized()
									found = true
									break
					if found:
						break
		if found:
			break

	if not found:
		# Если игрок стоит посреди пустого зала или смотрит в тупик без углов — берем гарантированную точку в коридоре
		if force_aggro:
			# Для погони гарантированно спавним в 12-16 метрах впереди или сбоку
			for test_dist in [12.0, 15.0, 18.0, 9.0]:
				for test_ang in [0.0, deg_to_rad(30), deg_to_rad(-30), deg_to_rad(60), deg_to_rad(-60), PI]:
					var cand_pos = player.global_position + cam_fwd.rotated(Vector3.UP, test_ang).normalized() * test_dist
					cand_pos.y = 0.0
					if is_world_position_passable(cand_pos, 0.45):
						found_pos = cand_pos
						hide_dir = -cam_fwd
						found = true
						break
				if found:
					break
		else:
			# Для наблюдения: ищем позицию сбоку у ближайшей стены
			for test_dist in [14.0, 18.0, 11.0]:
				for test_ang in [deg_to_rad(45), deg_to_rad(-45), deg_to_rad(70), deg_to_rad(-70)]:
					var cand_pos = player.global_position + cam_fwd.rotated(Vector3.UP, test_ang).normalized() * test_dist
					cand_pos.y = 0.0
					if is_world_position_passable(cand_pos, 0.45):
						found_pos = cand_pos
						hide_dir = -cam_fwd.rotated(Vector3.UP, test_ang)
						found = true
						break
				if found:
					break

	if not found:
		return

	var b = npc_bacteria_scene.instantiate()
	add_child(b)
	spawned_bacteria = b
	b.global_position = found_pos
	b.target_player = player
	b.aggro_chance = get_current_bacteria_aggro_chance()
	b.start_peeker_sequence(hide_dir)
	if force_aggro:
		b.trigger_aggro_chase()

func spawn_hazmat_behind_player() -> bool:
	if not player:
		return false

	# Вектор назад от взгляда игрока (+Z в локальном пространстве персонажа)
	var back_dir = player.global_transform.basis.z.normalized()
	if back_dir.length_squared() < 0.1:
		back_dir = Vector3(0, 0, 1)

	# Ищем свободное гарантированное место не в стене на расстоянии от 4.0 до 8.0 метров сзади
	var distances = [5.5, 4.5, 6.5, 7.5, 3.8]
	var angle_offsets = [0.0, deg_to_rad(20.0), deg_to_rad(-20.0), deg_to_rad(40.0), deg_to_rad(-40.0)]

	var chosen_pos = Vector3.ZERO
	var found = false

	for dist in distances:
		for ang in angle_offsets:
			var test_dir = back_dir.rotated(Vector3.UP, ang).normalized()
			var test_pos = player.global_position + test_dir * dist
			test_pos.y = 0.0

			# Проверяем, свободна ли точка в процедурном лабиринте
			if is_world_position_passable(test_pos, 0.45):
				chosen_pos = test_pos
				found = true
				break
		if found:
			break

	if not found:
		return false

	var npc = npc_hazmat_scene.instantiate()
	add_child(npc)
	spawned_npc = npc
	npc.global_position = chosen_pos

	# Поворачиваем NPC лицом к игроку
	var to_player = (player.global_position - chosen_pos).normalized()
	npc.rotation.y = atan2(-to_player.x, -to_player.z)
	npc.target_player = player

	# Проигрываем характерный звук hey.mp3 на месте появления NPC
	var hey_player = AudioStreamPlayer3D.new()
	hey_player.stream = hey_audio_stream
	hey_player.unit_size = 6.0
	hey_player.max_distance = 45.0
	hey_player.volume_db = 8.0 # Отчетливый, реалистичный окрик сзади
	hey_player.position = chosen_pos + Vector3(0, 1.5, 0)
	add_child(hey_player)
	hey_player.finished.connect(func(): hey_player.queue_free())
	hey_player.play()

	return true

# Дальность прорисовки берём из настройки игрока, а не жёстко зашитым числом:
# иначе при повторном заходе на уровень она падала до минимума (5 -> 2).
func _render_distance_from_settings() -> int:
	var gs = preload("res://game_settings.gd").instance
	if gs:
		return gs.chunk_render_distance
	return view_radius

func _on_settings_changed():
	var gs = preload("res://game_settings.gd").instance
	if gs and gs.chunk_render_distance != view_radius:
		view_radius = gs.chunk_render_distance
		if current_player_chunk != Vector2i(-9999, -9999):
			update_chunks_around_player()

func update_chunks_around_player():
	var target_chunks = {}
	var cx0 = current_player_chunk.x
	var cz0 = current_player_chunk.y

	for dz in range(-view_radius, view_radius + 1):
		for dx in range(-view_radius, view_radius + 1):
			var c = Vector2i(cx0 + dx, cz0 + dz)
			target_chunks[c] = true
			if not active_chunks.has(c):
				load_chunk(c)

	var to_remove = []
	for c in active_chunks.keys():
		if not target_chunks.has(c):
			to_remove.append(c)

	for c in to_remove:
		unload_chunk(c)

func get_hash(v1: int, v2: int, salt: int) -> int:
	var n = (v1 * 73856093) ^ (v2 * 19349663) ^ (salt * 83492791) ^ world_seed
	n = (n ^ (n >> 13)) * 1274126177
	return (n ^ (n >> 16)) & 0x7FFFFFFF

func load_chunk(c: Vector2i):
	var chunk_node = Node3D.new()
	chunk_node.name = "Chunk_%d_%d" % [c.x, c.y]
	corridors_root.add_child(chunk_node)
	active_chunks[c] = chunk_node

	var x0 = c.x * CHUNK_SIZE
	var z0 = c.y * CHUNK_SIZE

	if current_level == 89:
		# Генерация бесконечного вечернего города Level 89
		build_level89_urban_chunk(chunk_node, c, x0, z0)
		return
	elif current_level == 1:
		# Генерация бесконечного пустого бетонного склада/парковки Level 1
		build_level1_chunk(chunk_node, c, x0, z0)
		return
	# Решаем, является ли этот чанк чанком с noclip (провал сквозь пол):
	# 1) Либо отмечен кнопкой Z
	# 2) Либо после побега от монстра с шансом 1%
	var is_noclip = false
	if noclip_chunks.has(c):
		is_noclip = true
	elif has_escaped_monster_once and (c != Vector2i.ZERO):
		var noclip_seed = get_hash(c.x, c.y, 777)
		if (noclip_seed % 100) == 0: # Шанс 1%
			is_noclip = true
			noclip_chunks[c] = true

	# 1. ПОЛ (визуально ковер есть ВСЕГДА, но в noclip-чанках у него нет коллизии — игрок сквозь него проваливается!)
	var floor_node: Node3D
	if is_noclip:
		floor_node = Node3D.new() # Без коллизии!
		floor_node.name = "FloorNoclip"
	else:
		var floor_body = StaticBody3D.new()
		floor_body.name = "FloorBody"
		var floor_col = CollisionShape3D.new()
		var floor_shape = BoxShape3D.new()
		floor_shape.size = Vector3(CHUNK_SIZE, 0.2, CHUNK_SIZE)
		floor_col.shape = floor_shape
		floor_body.add_child(floor_col)
		floor_node = floor_body

	var floor_mesh = MeshInstance3D.new()
	var p_mesh = PlaneMesh.new()
	p_mesh.size = Vector2(CHUNK_SIZE + 0.05, CHUNK_SIZE + 0.05)
	floor_mesh.mesh = p_mesh
	floor_mesh.material_override = carpet_mat
	floor_mesh.name = "FloorMesh"
	floor_node.add_child(floor_mesh)

	floor_node.position = Vector3(x0 + CHUNK_SIZE * 0.5, 0, z0 + CHUNK_SIZE * 0.5)
	chunk_node.add_child(floor_node)

	# 2. ПОТОЛОК
	var ceil_mesh = MeshInstance3D.new()
	var cp_mesh = PlaneMesh.new()
	cp_mesh.size = Vector2(CHUNK_SIZE + 0.05, CHUNK_SIZE + 0.05)
	ceil_mesh.mesh = cp_mesh
	ceil_mesh.material_override = ceil_mat
	ceil_mesh.position = Vector3(x0 + CHUNK_SIZE * 0.5, CEIL_HEIGHT, z0 + CHUNK_SIZE * 0.5)
	ceil_mesh.rotation.x = PI
	chunk_node.add_child(ceil_mesh)

	# 3. БЕСКОНЕЧНО ВАРИАТИВНАЯ ГЕНЕРАЦИЯ ПОМЕЩЕНИЙ
	build_procedural_chunky_chunk(chunk_node, c, x0, z0)

func is_world_position_passable(pos: Vector3, radius: float = 0.4) -> bool:
	# Проверяем, свободна ли точка в процедурной сетке (с учетом радиуса)
	var offsets = [
		Vector2(0, 0),
		Vector2(radius, 0),
		Vector2(-radius, 0),
		Vector2(0, radius),
		Vector2(0, -radius)
	]
	for off in offsets:
		var p = pos + Vector3(off.x, 0, off.y)
		var cx = int(floor(p.x / CHUNK_SIZE))
		var cz = int(floor(p.z / CHUNK_SIZE))
		var c = Vector2i(cx, cz)
		
		var lx = p.x - cx * CHUNK_SIZE
		var lz = p.z - cz * CHUNK_SIZE
		var col = clamp(int(floor(lx / CELL_SIZE)), 0, BLOCK_CELLS - 1)
		var r = clamp(int(floor(lz / CELL_SIZE)), 0, BLOCK_CELLS - 1)

		var grid = get_chunk_grid(c)
		if grid.is_empty() or grid[r][col] == 0:
			return false
	return true

var chunk_grid_cache = {}

func get_chunk_grid(c: Vector2i) -> Array:
	if chunk_grid_cache.has(c):
		return chunk_grid_cache[c]

	var grid = []
	for r in range(BLOCK_CELLS):
		var row = []
		for col in range(BLOCK_CELLS):
			row.append(0)
		grid.append(row)

	grid[0][3] = 1; grid[0][4] = 1
	grid[7][3] = 1; grid[7][4] = 1
	grid[3][0] = 1; grid[4][0] = 1
	grid[3][7] = 1; grid[4][7] = 1

	var h_type = get_hash(c.x, c.y, 100)
	var h_sub = get_hash(c.x, c.y, 200)
	var h_rooms = get_hash(c.x, c.y, 300)

	var theme = h_type % 10
	if c == Vector2i(int(floor(player.global_position.x / CHUNK_SIZE)), int(floor(player.global_position.z / CHUNK_SIZE))) if player else c == Vector2i.ZERO:
		theme = 1

	match theme:
		0:
			for r in range(1, 7):
				for col in range(1, 7):
					grid[r][col] = 1
			var p_cfg = h_sub % 5
			if p_cfg == 0 or p_cfg >= 2: grid[2][2] = 0
			if p_cfg == 1 or p_cfg >= 2: grid[2][5] = 0
			if p_cfg >= 3: grid[5][2] = 0
			if p_cfg >= 4: grid[5][5] = 0
		1:
			for r in range(8):
				grid[r][3] = 1; grid[r][4] = 1
			grid[3][0] = 1; grid[4][0] = 1
			grid[3][7] = 1; grid[4][7] = 1
			if (h_sub & 1) != 0:
				for r in range(1, 4):
					grid[r][1] = 1; grid[r][2] = 1
			if (h_sub & 2) != 0:
				for r in range(4, 7):
					grid[r][1] = 1; grid[r][2] = 1
			if (h_sub & 4) != 0:
				for r in range(1, 6):
					grid[r][5] = 1; grid[r][6] = 1
		2:
			for r in range(1, 7):
				for col in range(1, 7):
					grid[r][col] = 1
			for r in range(1, 7):
				grid[r][3] = 0
				grid[3][r] = 0
			grid[2][3] = 1; grid[5][3] = 1
			grid[3][2] = 1; grid[3][5] = 1
			grid[3][0] = 1; grid[4][0] = 1; grid[3][7] = 1; grid[4][7] = 1
			grid[0][3] = 1; grid[0][4] = 1; grid[7][3] = 1; grid[7][4] = 1
		3:
			for col in range(8):
				grid[3][col] = 1; grid[4][col] = 1
			for r in range(0, 5):
				grid[r][3] = 1; grid[r][4] = 1
			if (h_sub & 1) != 0:
				for r in range(4, 8):
					grid[r][3] = 1; grid[r][4] = 1
			var rx = 1 if (h_sub & 2) != 0 else 5
			for r in range(1, 7):
				grid[r][rx] = 1; grid[r][rx + 1] = 1
		4:
			for r in range(0, 4):
				grid[r][3] = 1; grid[r][4] = 1
			for col in range(1, 6):
				grid[3][col] = 1; grid[4][col] = 1
			for r in range(4, 8):
				grid[r][4] = 1; grid[r][5] = 1
			grid[3][0] = 1; grid[4][0] = 1; grid[3][7] = 1; grid[4][7] = 1
			grid[7][3] = 1
		_:
			for r in range(8):
				grid[r][3] = 1; grid[r][4] = 1
			for col in range(8):
				grid[3][col] = 1; grid[4][col] = 1
			var num_rooms = (h_rooms % 3) + 1
			for i in range(num_rooms):
				var hr = get_hash(c.x, c.y, 500 + i)
				var rw = 2 + (hr % 3)
				var rh = 2 + ((hr >> 4) % 3)
				var rx = 1 + ((hr >> 8) % max(1, 7 - rw))
				var rz = 1 + ((hr >> 12) % max(1, 7 - rh))
				for r in range(rz, min(7, rz + rh)):
					for col in range(rx, min(7, rx + rw)):
						grid[r][col] = 1
				if rw >= 3 and rh >= 3 and (hr & 8) != 0:
					grid[rz + 1][rx + 1] = 0

	chunk_grid_cache[c] = grid
	return grid

func build_procedural_chunky_chunk(chunk_node: Node3D, c: Vector2i, x0: float, z0: float):
	var grid = get_chunk_grid(c)

	var h_type = get_hash(c.x, c.y, 100)
	var h_sub = get_hash(c.x, c.y, 200)
	var h_rooms = get_hash(c.x, c.y, 300)

	var lamp_candidates = []
	var is_dark_zone = (h_type % 12 == 0) and (c != Vector2i.ZERO)

	var theme = h_type % 10
	if c == Vector2i(int(floor(player.global_position.x / CHUNK_SIZE)), int(floor(player.global_position.z / CHUNK_SIZE))) if player else c == Vector2i.ZERO:
		theme = 1

	match theme:
		0:
			lamp_candidates.append(Vector2(3.5, 2.5))
			lamp_candidates.append(Vector2(3.5, 5.0))
		1:
			lamp_candidates.append(Vector2(3.5, 1.5))
			lamp_candidates.append(Vector2(3.5, 4.0))
			lamp_candidates.append(Vector2(3.5, 6.5))
		2:
			lamp_candidates.append(Vector2(1.5, 1.5))
			lamp_candidates.append(Vector2(5.5, 1.5))
			lamp_candidates.append(Vector2(1.5, 5.5))
			lamp_candidates.append(Vector2(5.5, 5.5))
		3:
			var rx = 1 if (h_sub & 2) != 0 else 5
			lamp_candidates.append(Vector2(3.5, 3.5))
			lamp_candidates.append(Vector2(rx + 0.5, 3.5))
		4:
			lamp_candidates.append(Vector2(3.5, 2.0))
			lamp_candidates.append(Vector2(4.5, 5.5))
		_:
			var num_rooms = (h_rooms % 3) + 1
			for i in range(num_rooms):
				var hr = get_hash(c.x, c.y, 500 + i)
				var rw = 2 + (hr % 3)
				var rh = 2 + ((hr >> 4) % 3)
				var rx = 1 + ((hr >> 8) % max(1, 7 - rw))
				var rz = 1 + ((hr >> 12) % max(1, 7 - rh))
				lamp_candidates.append(Vector2(rx + rw * 0.5 - 0.5, rz + rh * 0.5 - 0.5))
			lamp_candidates.append(Vector2(3.5, 3.5))

	# Спавним монолитные массивные блоки стен с жадным горизонтальным объединением
	for r in range(BLOCK_CELLS):
		var c_start = -1
		for col in range(BLOCK_CELLS):
			if grid[r][col] == 0:
				if c_start == -1:
					c_start = col
			else:
				if c_start != -1:
					spawn_monolithic_block(chunk_node, x0, z0, r, c_start, col - 1)
					c_start = -1
		if c_start != -1:
			spawn_monolithic_block(chunk_node, x0, z0, r, c_start, BLOCK_CELLS - 1)

	# Спавним светильники
	var placed_lamps = {}
	for l_pos in lamp_candidates:
		var key = Vector2i(int(round(l_pos.x)), int(round(l_pos.y)))
		if not placed_lamps.has(key):
			placed_lamps[key] = true
			var lx = x0 + (l_pos.x + 0.5) * CELL_SIZE
			var lz = z0 + (l_pos.y + 0.5) * CELL_SIZE
			spawn_kane_light(chunk_node, lx, lz, is_dark_zone)

	# Редкий спавн аномальных инсталляций мебели (максимум 2 на 120 метров)
	maybe_spawn_furniture_in_chunk(chunk_node, c, grid, x0, z0)

	# Редкий спавн интерактивной двери в стене (1 на 200 метров)
	maybe_spawn_door_in_chunk(chunk_node, c, grid, x0, z0, 0)

func spawn_monolithic_block(parent: Node3D, x0: float, z0: float, r: int, c1: int, c2: int):
	var count = c2 - c1 + 1
	var sx = count * CELL_SIZE
	var sz = CELL_SIZE
	var px = x0 + (float(c1) + float(count) * 0.5) * CELL_SIZE
	var pz = z0 + (float(r) + 0.5) * CELL_SIZE

	var wall = StaticBody3D.new()
	wall.position = Vector3(px, CEIL_HEIGHT * 0.5, pz)

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(sx, CEIL_HEIGHT, sz)
	mesh.mesh = box
	mesh.material_override = wall_mat
	wall.add_child(mesh)

	var shape = CollisionShape3D.new()
	var b_shape = BoxShape3D.new()
	b_shape.size = Vector3(sx, CEIL_HEIGHT, sz)
	shape.shape = b_shape
	wall.add_child(shape)

	var bb_mesh = MeshInstance3D.new()
	var bb_box = BoxMesh.new()
	bb_box.size = Vector3(sx + 0.04, 0.12, sz + 0.04)
	bb_mesh.mesh = bb_box
	bb_mesh.material_override = baseboard_mat
	bb_mesh.position.y = -CEIL_HEIGHT * 0.5 + 0.06
	wall.add_child(bb_mesh)

	parent.add_child(wall)

	# Очень редкая генерация стрелочек и рисунков из вселенной Backrooms на стенах
	maybe_spawn_decal_on_block(parent, px, pz, sx, sz, r, c1)

func maybe_spawn_decal_on_block(parent: Node3D, px: float, pz: float, sx: float, sz: float, r: int, c1: int):
	# Детерминированный хэш для блока
	var block_seed = get_hash(int(px * 10), int(pz * 10), 9192 + r * 17 + c1)
	
	# Шанс для блока: 1 на 10 блоков (в сочетании с радиусом 20м гарантирует регулярное появление)
	if (block_seed % 10) != 0:
		return
	if vert_drawings.is_empty() and horiz_drawings.is_empty():
		return

	# Дистанционный фильтр: максимум один рисунок на 40 метров
	# Если ближе 40 метров уже есть любой рисунок — не спавним
	var cur_pos_2d = Vector2(px, pz)
	for prev_pos in spawned_decal_positions:
		if cur_pos_2d.distance_to(prev_pos) < 40.0:
			return

	# Случайная грань блока:
	# 0 = Юг (+Z, длина стены sx), 1 = Север (-Z, длина стены sx), 2 = Восток (+X, длина стены sz), 3 = Запад (-X, длина стены sz)
	var face = (block_seed >> 5) % 4
	var wall_length = sx if (face == 0 or face == 1) else sz

	# Решаем, какой рисунок ставить: вертикальный или горизонтальный
	# Вертикальный рисунок: высота 90% стены (3.2 * 0.9 = 2.88м), ширина (2.88 * 1080 / 1920 = 1.62м)
	# Горизонтальный рисунок: ширина 2.88м, высота (2.88 * 1080 / 1920 = 1.62м)
	# Если длина стены меньше ширины горизонтального рисунка (2.88м), ставим вертикальный (ширина 1.62м помещается на стене 2.0м)
	var is_vert: bool = true
	if wall_length >= 3.0 and not horiz_drawings.is_empty() and not vert_drawings.is_empty():
		is_vert = ((block_seed >> 7) % 2) == 0
	elif not vert_drawings.is_empty():
		is_vert = true
	else:
		is_vert = false

	var tex: Texture2D
	var quad_size: Vector2
	var y_pos: float

	if is_vert:
		var tex_idx = (block_seed >> 10) % vert_drawings.size()
		tex = vert_drawings[tex_idx]
		# 90% высоты стены: 3.2 * 0.9 = 2.88м. Пропорция 9:16 -> ширина 1.62м
		quad_size = Vector2(1.62, 2.88)
		# Упирается в плинтус (высота плинтуса 0.12м):
		# Нижний край на y = 0.12, значит центр y = 0.12 + 2.88 / 2 = 1.56м
		y_pos = 1.56
	else:
		var tex_idx = (block_seed >> 10) % horiz_drawings.size()
		tex = horiz_drawings[tex_idx]
		# Такой же огромный как вертикальный, но по горизонтали (ширина 2.88м, высота 1.62м)
		# Если стена чуть короче (например 2.8м), аккуратно масштабируем под 90% длины стены
		var max_w = min(2.88, wall_length * 0.9)
		var max_h = max_w * (1080.0 / 1920.0)
		quad_size = Vector2(max_w, max_h)
		# Посередине стены
		y_pos = CEIL_HEIGHT * 0.5 # 1.60м

	var quad = MeshInstance3D.new()
	var p_mesh = QuadMesh.new()
	p_mesh.size = quad_size
	quad.mesh = p_mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness = 0.95
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	quad.material_override = mat

	var eps = 0.005 # Смещение на 5 мм от стены наружу

	match face:
		0: # Южная стена (нормаль смотрит в +Z)
			quad.position = Vector3(px, y_pos, pz + sz * 0.5 + eps)
			quad.rotation_degrees = Vector3(0, 0, 0)
		1: # Северная стена (нормаль смотрит в -Z)
			quad.position = Vector3(px, y_pos, pz - sz * 0.5 - eps)
			quad.rotation_degrees = Vector3(0, 180, 0)
		2: # Восточная стена (нормаль смотрит в +X)
			quad.position = Vector3(px + sx * 0.5 + eps, y_pos, pz)
			quad.rotation_degrees = Vector3(0, 90, 0)
		3: # Западная стена (нормаль смотрит в -X)
			quad.position = Vector3(px - sx * 0.5 - eps, y_pos, pz)
			quad.rotation_degrees = Vector3(0, -90, 0)

	parent.add_child(quad)
	spawned_decal_positions.append(cur_pos_2d)

	# Если это рисунок с надписью EXIT (user_drawing_vert_5) — добавляем интерактивную триггерную зону касания
	if tex == vert_drawings[4]:
		_setup_exit_drawing_interaction(parent, quad)

func _setup_exit_drawing_interaction(parent: Node3D, quad: MeshInstance3D):
	var area = Area3D.new()
	area.name = "ExitDrawingTouchArea"
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(1.8, 2.8, 1.4)
	col.shape = box
	area.add_child(col)
	area.global_transform = quad.global_transform
	parent.add_child(area)

	area.body_entered.connect(func(body):
		if body == player or (body is CharacterBody3D and body.has_method("interact_with_door")):
			_on_exit_drawing_touched()
	)

# Редкий спавн интерактивной двери в стене (1 на 200 метров)
func maybe_spawn_door_in_chunk(parent: Node3D, c: Vector2i, grid: Array, x0: float, z0: float, lvl_type: int):
	if c == Vector2i.ZERO:
		return

	var d_seed = get_hash(c.x, c.y, 90210)
	# Спавн редкий: 1 чанк из 13 (в среднем ~200м с учетом дистанционного фильтра)
	if (d_seed % 13) != 0:
		return

	var center_chunk_world = Vector2(x0 + CHUNK_SIZE * 0.5, z0 + CHUNK_SIZE * 0.5)
	# Дистанционный фильтр: строго не ближе 180-200 метров друг от друга
	for prev in spawned_door_positions:
		if center_chunk_world.distance_to(prev) < 180.0:
			return

	# Ищем стену с открытым проходом рядом для врезки двери
	var candidates = []
	for r in range(1, BLOCK_CELLS - 1):
		for col in range(1, BLOCK_CELLS - 1):
			if grid[r][col] == 0: # Стена
				# Проверяем, есть ли рядом проход
				if grid[r][col + 1] == 1:
					candidates.append({"r": r, "col": col, "norm": Vector3(1, 0, 0), "rot": PI * 0.5})
				elif grid[r][col - 1] == 1:
					candidates.append({"r": r, "col": col, "norm": Vector3(-1, 0, 0), "rot": -PI * 0.5})
				elif grid[r + 1][col] == 1:
					candidates.append({"r": r, "col": col, "norm": Vector3(0, 0, 1), "rot": 0.0})
				elif grid[r - 1][col] == 1:
					candidates.append({"r": r, "col": col, "norm": Vector3(0, 0, -1), "rot": PI})

	if candidates.is_empty():
		return

	var cand = candidates[d_seed % candidates.size()]
	var door_inst = interactive_door_script.new()
	door_inst.level_type = lvl_type
	door_inst.player_entered_black_void.connect(_on_door_void_entered)

	var door_x = x0 + (cand["col"] + 0.5) * CELL_SIZE + cand["norm"].x * (CELL_SIZE * 0.49)
	var door_z = z0 + (cand["r"] + 0.5) * CELL_SIZE + cand["norm"].z * (CELL_SIZE * 0.49)
	door_inst.position = Vector3(door_x, 0.0, door_z)
	door_inst.rotation.y = cand["rot"]

	parent.add_child(door_inst)
	spawned_door_positions.append(center_chunk_world)

# Редкий спавн аномальных инсталляций мебели из Backrooms (максимум 2 на 120 метров, т.е. дистанция >= 60м)
func maybe_spawn_furniture_in_chunk(parent: Node3D, c: Vector2i, grid: Array, x0: float, z0: float):
	if c == Vector2i.ZERO:
		return

	# Детерминированный хэш для чанка
	var f_seed = get_hash(c.x, c.y, 481516)
	
	# Очень редкий шанс: 1 чанк из 14 (~7%)
	if (f_seed % 14) != 0:
		return

	var center_chunk_world = Vector2(x0 + CHUNK_SIZE * 0.5, z0 + CHUNK_SIZE * 0.5)
	
	# Дистанционный фильтр: максимум 2 инсталляции на 120 метров -> расстояние между любыми инсталляциями >= 60.0м
	for prev in spawned_furniture_positions:
		if center_chunk_world.distance_to(prev) < 60.0:
			return

	# Выбираем тип инсталляции мебели:
	# 0 = Диван, наполовину застрявший в стене (классический noclip Backrooms)
	# 1 = Одинокая тумбочка посреди глухого коридора с ретро-телевизором/часами
	# 2 = Заброшенный офисный стол со стулом и работающей лампой у стены
	# 3 = Одинокий диван лицом в угол/стену
	# 4 = Тумбочка, наполовину вросшая в стену боком
	var scenario = f_seed % 5

	# Ищем подходящую клетку в сетке чанка
	var candidate_cells = []
	for r in range(1, BLOCK_CELLS - 1):
		for col in range(1, BLOCK_CELLS - 1):
			var is_wall = (grid[r][col] == 0)
			# Проверяем соседей
			var neighbor_walls = 0
			if grid[r-1][col] == 0: neighbor_walls += 1
			if grid[r+1][col] == 0: neighbor_walls += 1
			if grid[r][col-1] == 0: neighbor_walls += 1
			if grid[r][col+1] == 0: neighbor_walls += 1

			match scenario:
				0, 4: # В стене: ищем границу между стеной и проходом
					if is_wall and neighbor_walls < 4:
						candidate_cells.append(Vector2i(col, r))
					elif not is_wall and neighbor_walls > 0:
						candidate_cells.append(Vector2i(col, r))
				1: # В коридоре: свободная клетка между двумя стенами
					if not is_wall and neighbor_walls >= 2:
						candidate_cells.append(Vector2i(col, r))
				2, 3: # У стены: свободная клетка, прилегающая к стене
					if not is_wall and neighbor_walls >= 1:
						candidate_cells.append(Vector2i(col, r))

	if candidate_cells.is_empty():
		return

	var pick_idx = (f_seed >> 4) % candidate_cells.size()
	var pick = candidate_cells[pick_idx]
	var cell_x = x0 + (pick.x + 0.5) * CELL_SIZE
	var cell_z = z0 + (pick.y + 0.5) * CELL_SIZE

	var inst_node = Node3D.new()
	inst_node.name = "FurnitureInstallation_%d" % scenario

	match scenario:
		0:
			# Диван наполовину в стене (длина дивана ~2.0м, глубина ~0.8м, высота ~0.8м)
			var sofa = fbx_sofa_a.instantiate()
			apply_psx_materials_to_furniture(sofa, "sofa")
			sofa.scale = Vector3(0.20, 0.20, 0.20)
			var wall_rot = ((f_seed >> 8) % 4) * (PI * 0.5)
			sofa.rotation.y = wall_rot
			sofa.position = Vector3(cell_x, 0.36, cell_z)
			inst_node.add_child(sofa)

		1:
			# Одинокая тумбочка в коридоре с телевизором
			var drawer = fbx_drawer_a.instantiate()
			apply_psx_materials_to_furniture(drawer, "wood")
			drawer.scale = Vector3(0.18, 0.18, 0.18)
			drawer.position = Vector3(cell_x, 0.38, cell_z)
			var d_rot = ((f_seed >> 7) % 4) * (PI * 0.5)
			drawer.rotation.y = d_rot
			inst_node.add_child(drawer)

			var tv = fbx_tv_a.instantiate()
			apply_psx_materials_to_furniture(tv, "tv")
			tv.scale = Vector3(0.14, 0.14, 0.14)
			tv.position = Vector3(cell_x, 0.72 + 0.28, cell_z)
			tv.rotation.y = d_rot
			inst_node.add_child(tv)

		2:
			# Офисный стол со стулом и настольной лампой
			# Пивот стола смещен: центр столешницы по X смещен на -0.31м, по Y на +0.485м от пола
			var rot_y = ((f_seed >> 6) % 4) * (PI * 0.5)

			var desk = fbx_desk.instantiate()
			apply_psx_materials_to_furniture(desk, "wood")
			desk.scale = Vector3(0.18, 0.18, 0.18)
			desk.rotation.y = rot_y
			# Компенсируем смещение пивота, чтобы стол стоял ровно по центру клетки
			var desk_pivot_offset = Vector3(-0.312, 0.485, -0.113).rotated(Vector3.UP, rot_y)
			desk.position = Vector3(cell_x, 0.0, cell_z) - desk_pivot_offset
			inst_node.add_child(desk)

			# Стул ставим со стороны сидящего за столом (+Z в локальных координатах стола)
			var chair = fbx_chair_a.instantiate()
			apply_psx_materials_to_furniture(chair, "wood")
			chair.scale = Vector3(0.18, 0.18, 0.18)
			var chair_offset = Vector3(0.0, 0.351, 0.55).rotated(Vector3.UP, rot_y)
			chair.position = Vector3(cell_x, 0.0, cell_z) + chair_offset
			chair.rotation.y = rot_y + deg_to_rad(float((f_seed >> 10) % 20 - 10))
			inst_node.add_child(chair)

			# Настольная лампа: стоит прямо на поверхности стола (Y = 0.77м)
			var lamp = fbx_lamp_a.instantiate()
			apply_psx_materials_to_furniture(lamp, "lamp")
			lamp.scale = Vector3(0.09, 0.09, 0.09)
			lamp.rotation.y = rot_y
			var lamp_offset = Vector3(-0.35, 0.77 + 0.44, -0.05).rotated(Vector3.UP, rot_y)
			lamp.position = Vector3(cell_x, 0.0, cell_z) + lamp_offset
			inst_node.add_child(lamp)

			# Лампочка дает реальный локальный свет на столешницу
			var desk_light = OmniLight3D.new()
			desk_light.light_color = Color(1.0, 0.95, 0.75)
			desk_light.light_energy = 1.2
			desk_light.omni_range = 3.5
			desk_light.omni_attenuation = 1.4
			desk_light.position = lamp.position + Vector3(0, 0.25, 0)
			inst_node.add_child(desk_light)

		3:
			# Одинокий диван, развернутый лицом в угол или стену
			var sofa = fbx_sofa_b.instantiate()
			apply_psx_materials_to_furniture(sofa, "sofa")
			sofa.scale = Vector3(0.20, 0.20, 0.20)
			sofa.position = Vector3(cell_x, 0.36, cell_z)
			sofa.rotation.y = ((f_seed >> 8) % 8) * (PI * 0.25) # Нестандартный разворот
			inst_node.add_child(sofa)

		4:
			# Тумбочка, наполовину вросшая в стену боком
			var drawer = fbx_drawer_a.instantiate()
			apply_psx_materials_to_furniture(drawer, "wood")
			drawer.scale = Vector3(0.18, 0.18, 0.18)
			drawer.position = Vector3(cell_x, 0.38, cell_z)
			var dr_rot = ((f_seed >> 9) % 4) * (PI * 0.5)
			drawer.rotation.y = dr_rot
			inst_node.add_child(drawer)

			var clock = fbx_clock.instantiate()
			apply_psx_materials_to_furniture(clock, "wood")
			clock.scale = Vector3(0.15, 0.15, 0.15)
			clock.position = Vector3(cell_x, 0.72 + 0.05, cell_z)
			clock.rotation.y = dr_rot
			inst_node.add_child(clock)

	parent.add_child(inst_node)
	spawned_furniture_positions.append(center_chunk_world)

# Наложение аутентичных PSX текстур и материалов на узлы FBX моделей
func apply_psx_materials_to_furniture(node: Node, model_type: String):
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				match model_type:
					"sofa":
						if s == 0:
							mi.set_surface_override_material(s, psx_fabric_mat)
						else:
							mi.set_surface_override_material(s, psx_wood_mat)
					"wood":
						mi.set_surface_override_material(s, psx_wood_mat)
					"tv":
						if s == 2:
							mi.set_surface_override_material(s, psx_screen_mat)
						elif s == 1:
							mi.set_surface_override_material(s, psx_metal_mat)
						else:
							mi.set_surface_override_material(s, psx_plastic_mat)
					"lamp":
						if s == 1:
							mi.set_surface_override_material(s, lamp_mat)
						else:
							mi.set_surface_override_material(s, psx_metal_mat)
					_:
						mi.set_surface_override_material(s, psx_wood_mat)
	for child in node.get_children():
		apply_psx_materials_to_furniture(child, model_type)

func spawn_kane_light(parent: Node3D, px: float, pz: float, is_dark: bool):
	var lamp_mesh = MeshInstance3D.new()
	var l_box = BoxMesh.new()
	l_box.size = Vector3(0.8, 0.03, 1.6)
	lamp_mesh.mesh = l_box
	lamp_mesh.material_override = lamp_mat if (not is_dark and not is_blackout) else lamp_off_mat
	lamp_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp_mesh.position = Vector3(px, CEIL_HEIGHT - 0.015, pz)
	parent.add_child(lamp_mesh)
	active_lamp_meshes.append(lamp_mesh)

	if not is_dark:
		var light = OmniLight3D.new()
		light.position = Vector3(px, CEIL_HEIGHT - 0.25, pz)
		light.light_color = Color(1.0, 0.96, 0.82)
		light.light_energy = 0.0 if is_blackout else 1.8
		light.omni_range = 10.0
		light.omni_attenuation = 1.3
		light.shadow_enabled = true
		light.shadow_bias = 0.08
		light.shadow_normal_bias = 1.0
		light.distance_fade_enabled = true
		light.distance_fade_begin = 24.0
		light.distance_fade_length = 8.0
		parent.add_child(light)
		active_omni_lights.append(light)

# Функция полного отключения света на всей карте
func trigger_global_blackout():
	is_blackout = true
	# Моментально гасим все лампы и источники света
	for light in active_omni_lights:
		if is_instance_valid(light):
			light.light_energy = 0.0
			light.visible = false
	for mesh in active_lamp_meshes:
		if is_instance_valid(mesh):
			mesh.material_override = lamp_off_mat
	
	# Отключаем фоновый шум/гул (эмбиент) ламп
	if ambience_player and is_instance_valid(ambience_player):
		var tw_amb = create_tween()
		tw_amb.tween_property(ambience_player, "volume_db", -80.0, 0.4)
		tw_amb.finished.connect(func(): if is_instance_valid(ambience_player): ambience_player.stop())

	# Приглушаем WorldEnvironment до глубокой темной атмосферы, но оставляем легкую видимость силуэтов до фонарика
	var env_node = get_node_or_null("WorldEnvironment")
	if env_node and env_node.environment:
		env_node.environment.ambient_light_energy = 0.08
		env_node.environment.ambient_light_color = Color(0.22, 0.22, 0.25)
		env_node.environment.fog_enabled = false

# Функция восстановления света, тумана и эмбиента (когда игрок оторвался от сущности)
func restore_global_lighting():
	is_blackout = false
	# Включаем все лампы и их свечение
	for light in active_omni_lights:
		if is_instance_valid(light):
			light.light_energy = 1.8
			light.visible = true
	for mesh in active_lamp_meshes:
		if is_instance_valid(mesh):
			mesh.material_override = lamp_mat

	# Включаем назад гул ламп (эмбиент)
	if ambience_player and is_instance_valid(ambience_player):
		ambience_player.volume_db = -4.0
		if not ambience_player.is_playing():
			ambience_player.play()

	# Возвращаем каноничный желтый туман и параметры WorldEnvironment
	var env_node = get_node_or_null("WorldEnvironment")
	if env_node and env_node.environment:
		env_node.environment.ambient_light_energy = 0.22
		env_node.environment.ambient_light_color = Color(0.42, 0.38, 0.12)
		env_node.environment.fog_enabled = true

# ==================== МЕХАНИКА СМАЙЛЕРОВ И БЛЭКАУТА НА УРОВНЕ 1 ====================
func _process_level1_smilers_and_blackout(delta: float):
	if not player or not player.is_active:
		return

	# Очищаем мертвых смайлеров из массива
	var live_smilers: Array[CharacterBody3D] = []
	for s in spawned_smilers:
		if is_instance_valid(s):
			live_smilers.append(s)
	spawned_smilers = live_smilers

	if not level1_is_blackout:
		# Ожидаем наступления случайного блэкаута (каждые 45-80 секунд)
		level1_blackout_timer += delta
		if level1_blackout_timer >= level1_next_blackout_delay:
			level1_blackout_timer = 0.0
			_trigger_level1_blackout()
	else:
		# Идет блэкаут: таймер длительности темноты (35 - 50 секунд)
		level1_blackout_duration -= delta

		# Спавним адекватное количество Смайлеров (максимум 2-3 активных одновременно)
		level1_smiler_spawn_timer += delta
		if level1_smiler_spawn_timer >= 6.0:
			level1_smiler_spawn_timer = 0.0
			if spawned_smilers.size() < 3:
				_spawn_one_smiler()

		if level1_blackout_duration <= 0.0:
			# Время блэкаута вышло: восстанавливаем свет
			_restore_level1_lighting()

func _trigger_level1_blackout():
	level1_is_blackout = true
	level1_blackout_duration = randf_range(35.0, 50.0) # Длительность темноты
	level1_next_blackout_delay = randf_range(50.0, 90.0) # Следующий блэкаут
	level1_smiler_spawn_timer = 2.0 # Первый смайлер появится почти сразу

	# 1. Громкий резкий звук вырубания света
	if not blackout_audio_player:
		blackout_audio_player = AudioStreamPlayer.new()
		blackout_audio_player.name = "Level1BlackoutSound"
		blackout_audio_player.stream = blackout_sound_stream
		blackout_audio_player.volume_db = 12.0
		add_child(blackout_audio_player)
	blackout_audio_player.play()

	# 2. Вырубаем все лампы парковки и коридоров
	for light in active_omni_lights:
		if is_instance_valid(light):
			light.light_energy = 0.0
			light.visible = false
	for mesh in active_lamp_meshes:
		if is_instance_valid(mesh):
			mesh.material_override = lamp_off_mat

	# 3. Приглушаем эмбиент парковки
	if level1_audio_player and is_instance_valid(level1_audio_player):
		var tw = create_tween()
		tw.tween_property(level1_audio_player, "volume_db", -28.0, 0.5)

	# 4. Погружаем WorldEnvironment в кромешную тьму
	var env_node = get_node_or_null("WorldEnvironment")
	if env_node and env_node.environment:
		env_node.environment.ambient_light_energy = 0.02
		env_node.environment.ambient_light_color = Color(0.05, 0.05, 0.06)
		env_node.environment.fog_enabled = false

	# 5. Сразу спавним первого Смайлера неподалеку в темноте
	_spawn_one_smiler()

func _restore_level1_lighting():
	level1_is_blackout = false

	# 1. Возвращаем свет всем лампам
	for light in active_omni_lights:
		if is_instance_valid(light):
			light.light_energy = 1.7
			light.visible = true
	for mesh in active_lamp_meshes:
		if is_instance_valid(mesh):
			mesh.material_override = lamp_mat

	# 2. Восстанавливаем громкость эмбиента Уровня 1
	if level1_audio_player and is_instance_valid(level1_audio_player):
		var tw = create_tween()
		tw.tween_property(level1_audio_player, "volume_db", linear_to_db(0.35), 1.0)

	# 3. Возвращаем атмосферное освещение WorldEnvironment Уровня 1
	var env_node = get_node_or_null("WorldEnvironment")
	if env_node and env_node.environment:
		env_node.environment.ambient_light_energy = 0.4
		env_node.environment.ambient_light_color = Color(0.12, 0.13, 0.15)
		env_node.environment.fog_enabled = true

	# 4. "После включения света рассеяться сами"
	for s in spawned_smilers:
		if is_instance_valid(s) and s.has_method("start_dissolve"):
			s.start_dissolve()
	spawned_smilers.clear()

func _spawn_one_smiler():
	if not player:
		return

	# Ищем подходящую позицию на расстоянии 14-22м от игрока
	# Игрок должен иметь возможность заметить его светящиеся в темноте зубы и глаза
	var p_pos = player.global_position
	var found_pos = Vector3.ZERO
	var found = false

	for attempt in range(12):
		var ang = randf() * TAU
		var dist = randf_range(13.0, 22.0)
		var test_p = p_pos + Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		test_p.y = 0.0

		# Проверяем, свободна ли клетка
		if is_world_position_passable(test_p, 0.6):
			found_pos = test_p
			found = true
			break

	if not found:
		return

	var smiler = smiler_script.new()
	add_child(smiler)
	smiler.global_position = found_pos
	smiler.target_player = player
	spawned_smilers.append(smiler)


# Переход на Уровень 0 (The Lobby / Желтые комнаты Backrooms)
func _transition_to_level_0():
	if is_transitioning:
		return
	is_transitioning = true
	current_level = 0
	has_escaped_monster_once = false
	_teardown_level_minus44()
	_teardown_level_run()

	# Замораживаем игрока на время перехода
	if player:
		player.is_active = false
		player.velocity = Vector3.ZERO
		if player.visual_root:
			player.visual_root.visible = false
		if player.head_shadow_mesh:
			player.head_shadow_mesh.visible = false

	# Удаляем NPC/монстров
	if spawned_npc and is_instance_valid(spawned_npc):
		spawned_npc.queue_free()
		spawned_npc = null
	if spawned_bacteria and is_instance_valid(spawned_bacteria):
		spawned_bacteria.queue_free()
		spawned_bacteria = null
	if spawned_urban_observer and is_instance_valid(spawned_urban_observer):
		spawned_urban_observer.queue_free()
		spawned_urban_observer = null
	for s in spawned_smilers:
		if is_instance_valid(s):
			s.queue_free()
	spawned_smilers.clear()
	level1_is_blackout = false
	level1_blackout_timer = 0.0
	level1_next_blackout_delay = randf_range(40.0, 75.0)

	# Останавливаем звуки предыдущих уровней
	if ambience_player:
		ambience_player.stop()
	if level89_audio_player and is_instance_valid(level89_audio_player):
		level89_audio_player.stop()
	if level1_audio_player and is_instance_valid(level1_audio_player):
		level1_audio_player.stop()

	# Очищаем активные чанки
	for c in active_chunks.keys():
		var cn = active_chunks[c]
		if is_instance_valid(cn):
			cn.queue_free()
	active_chunks.clear()
	active_omni_lights.clear()
	active_lamp_meshes.clear()

	# Проигрываем jumpscare noclip видео
	var ui = find_child("UI", true, false)
	if not ui:
		_setup_level_0()
		return

	var vp = VideoStreamPlayer.new()
	vp.name = "NoclipTransitionPlayer"
	vp.expand = true
	vp.anchor_right = 1.0
	vp.anchor_bottom = 1.0
	vp.stream = load("res://death_jumpscare.ogv")
	vp.volume_db = 8.0
	vp.z_index = 100
	ui.add_child(vp)

	vp.finished.connect(func():
		vp.queue_free()
		_setup_level_0()
	)
	vp.play()

func _setup_level_0():
	is_transitioning = false
	_mark_level_visited(0)
	view_radius = _render_distance_from_settings()
	var env_node = get_node_or_null("WorldEnvironment")
	if env_node:
		var env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.02, 0.02, 0.02)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.42, 0.38, 0.12)
		env.ambient_light_energy = 0.22
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.0
		env.glow_enabled = true
		env.glow_intensity = 0.5
		env.glow_bloom = 0.15
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = Color(0.40, 0.36, 0.14)
		env.fog_light_energy = 0.45
		env.fog_density = 0.03
		env.fog_depth_begin = 6.0
		env.fog_depth_end = 35.0
		env_node.environment = env

	var old_moon = get_node_or_null("EveningCityLight")
	if old_moon:
		old_moon.queue_free()

	# Запускаем эмбиент Level 0
	if ambience_player:
		ambience_player.volume_db = -4.0
		ambience_player.play()

	# Случайный стартовый чанк для разнообразия
	var rand_cx = randi_range(-20, 20)
	var rand_cz = randi_range(-20, 20)
	current_player_chunk = Vector2i(rand_cx, rand_cz)
	update_chunks_around_player()

	if player:
		player.global_position = Vector3(rand_cx * CHUNK_SIZE + 8.0, 0.2, rand_cz * CHUNK_SIZE + 8.0)
		player.velocity = Vector3.ZERO
		player.play_getup_cutscene()

# Отмечаем уровень как посещённый за прохождение (влияет на веса случайной телепортации)
func _mark_level_visited(lvl: int):
	if not visited_levels.has(lvl):
		visited_levels.append(lvl)

# Переход на случайный уровень кроме текущего (при провале в дверь/пустоту)
# Шанс попасть на НОВЫЙ (ещё не посещённый) уровень выше, чем на уже посещённый:
# веса NEW_LEVEL_WEIGHT / VISITED_LEVEL_WEIGHT (по умолчанию 10 к 1).
func _transition_to_random_level():
	var available_levels: Array[int] = [0, 1, 89, -44]
	available_levels.erase(current_level)
	if available_levels.is_empty():
		return

	var total_weight = 0.0
	for l in available_levels:
		total_weight += NEW_LEVEL_WEIGHT if not visited_levels.has(l) else VISITED_LEVEL_WEIGHT

	var roll = randf() * total_weight
	var chosen = available_levels[0]
	for l in available_levels:
		roll -= NEW_LEVEL_WEIGHT if not visited_levels.has(l) else VISITED_LEVEL_WEIGHT
		if roll <= 0.0:
			chosen = l
			break

	print("[DOOR TELEPORT] From Level %d to Level %d" % [current_level, chosen])
	match chosen:
		0: _transition_to_level_0()
		1: _transition_to_level_1()
		89: _transition_to_level_89()
		-44: _transition_to_level_minus44()

# Переход на Уровень 89 через видео-катсцену (как при смерти от монстра)
# Переход на Уровень 1 (Habitable Zone / Пустой паркинг/склад)
func _transition_to_level_1():
	if is_transitioning:
		return
	is_transitioning = true
	current_level = 1
	has_escaped_monster_once = false
	_teardown_level_minus44()
	_teardown_level_run()

	# Замораживаем игрока на время перехода
	if player:
		player.is_active = false
		player.velocity = Vector3.ZERO
		if player.visual_root:
			player.visual_root.visible = false
		if player.head_shadow_mesh:
			player.head_shadow_mesh.visible = false

	# Удаляем NPC/монстров
	if spawned_npc and is_instance_valid(spawned_npc):
		spawned_npc.queue_free()
		spawned_npc = null
	if spawned_bacteria and is_instance_valid(spawned_bacteria):
		spawned_bacteria.queue_free()
		spawned_bacteria = null
	if spawned_urban_observer and is_instance_valid(spawned_urban_observer):
		spawned_urban_observer.queue_free()
		spawned_urban_observer = null
	for s in spawned_smilers:
		if is_instance_valid(s):
			s.queue_free()
	spawned_smilers.clear()
	level1_is_blackout = false
	level1_blackout_timer = 0.0
	level1_next_blackout_delay = randf_range(40.0, 75.0)

	# Останавливаем звуки предыдущих уровней
	if ambience_player:
		ambience_player.stop()
	if level89_audio_player and is_instance_valid(level89_audio_player):
		level89_audio_player.stop()

	# Очищаем активные чанки
	for c in active_chunks.keys():
		var cn = active_chunks[c]
		if is_instance_valid(cn):
			cn.queue_free()
	active_chunks.clear()
	active_omni_lights.clear()
	active_lamp_meshes.clear()

	# Проигрываем jumpscare noclip видео
	var ui = find_child("UI", true, false)
	if not ui:
		_setup_level_1()
		return

	var vp = VideoStreamPlayer.new()
	vp.name = "NoclipTransitionPlayer"
	vp.expand = true
	vp.anchor_right = 1.0
	vp.anchor_bottom = 1.0
	vp.stream = load("res://death_jumpscare.ogv")
	vp.volume_db = 8.0
	vp.z_index = 100
	ui.add_child(vp)

	vp.finished.connect(func():
		vp.queue_free()
		_setup_level_1()
	)
	vp.play()

func _setup_level_1():
	# Настройка Уровня 1 (Бесконечная пустая парковка / склад)
	is_transitioning = false
	_mark_level_visited(1)
	view_radius = _render_distance_from_settings()
	var env_node = get_node_or_null("WorldEnvironment")
	if env_node:
		var env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.04, 0.04, 0.05) # Черная пустота за пределами

		# Очень тусклый заполняющий рассеянный холодный бетонный свет
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.12, 0.13, 0.15)
		env.ambient_light_energy = 0.4

		# Тонмаппинг
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.0

		# Легкий блум от ламп
		env.glow_enabled = true
		env.glow_intensity = 0.5
		env.glow_bloom = 0.15

		# Сырой, холодный полумрак с туманом на дистанции (как на фотографиях парковки)
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = Color(0.08, 0.09, 0.10)
		env.fog_light_energy = 0.5
		env.fog_density = 0.025
		env.fog_depth_begin = 8.0
		env.fog_depth_end = 55.0
		env_node.environment = env

	# Удаляем уличный свет moon, если остался
	var old_moon = get_node_or_null("EveningCityLight")
	if old_moon:
		old_moon.queue_free()

	# Эмбиент Уровня 1: низкий гул огромного пустого бетонного помещения, эхо и сквозняк
	if level1_audio_player and is_instance_valid(level1_audio_player):
		level1_audio_player.queue_free()

	level1_audio_player = AudioStreamPlayer.new()
	level1_audio_player.name = "Level1Ambience"
	level1_audio_player.stream = level1_ambience_stream
	level1_audio_player.volume_db = linear_to_db(0.35) # Атмосферный отчетливый гул
	level1_audio_player.finished.connect(func(): if current_level == 1: level1_audio_player.play())
	add_child(level1_audio_player)
	level1_audio_player.play()

	# Перемещаем игрока на парковку (четные координаты чанков) и запускаем анимацию подъема
	# Гарантируем, что спавн происходит в открытом зале парковки с колоннами
	var rand_cx = randi_range(-10, 10) * 2
	var rand_cz = randi_range(-10, 10) * 2
	current_player_chunk = Vector2i(rand_cx, rand_cz)
	update_chunks_around_player()

	if player:
		# Позиция по центру между колоннами в открытом пролете
		player.global_position = Vector3(rand_cx * CHUNK_SIZE + 8.0, 0.2, rand_cz * CHUNK_SIZE + 8.0)
		player.velocity = Vector3.ZERO
		player.play_getup_cutscene()

func _transition_to_level_89():
	if is_transitioning:
		return
	is_transitioning = true
	current_level = 89
	has_escaped_monster_once = false
	_teardown_level_minus44()
	_teardown_level_run()

	# Замораживаем игрока на время видео
	if player:
		player.is_active = false
		player.velocity = Vector3.ZERO
		if player.visual_root:
			player.visual_root.visible = false
		if player.head_shadow_mesh:
			player.head_shadow_mesh.visible = false

	# Удаляем NPC, если он есть
	if spawned_npc and is_instance_valid(spawned_npc):
		spawned_npc.queue_free()
		spawned_npc = null

	# Останавливаем эмбиент Level 0
	if ambience_player:
		ambience_player.stop()

	# Очищаем все чанки Level 0
	for c in active_chunks.keys():
		var cn = active_chunks[c]
		if is_instance_valid(cn):
			cn.queue_free()
	active_chunks.clear()
	active_omni_lights.clear()
	active_lamp_meshes.clear()

	# Проигрываем видео jumpscare (death_jumpscare.ogv)
	var ui = find_child("UI", true, false)
	if not ui:
		_setup_level_89()
		return

	var vp = VideoStreamPlayer.new()
	vp.name = "NoclipTransitionPlayer"
	vp.expand = true
	vp.anchor_right = 1.0
	vp.anchor_bottom = 1.0
	vp.stream = load("res://death_jumpscare.ogv")
	vp.volume_db = 8.0
	vp.z_index = 100
	ui.add_child(vp)

	vp.finished.connect(func():
		vp.queue_free()
		_setup_level_89()
	)
	vp.play()

func _setup_level_89():
	# Настройка бесконечного лиминального вечернего города Level 89
	is_transitioning = false
	_mark_level_visited(89)
	view_radius = _render_distance_from_settings()
	var env_node = get_node_or_null("WorldEnvironment")
	if env_node:
		var env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		# Около вечернее (почти темное) сумрачное небо, как на референсе
		env.background_color = Color(0.11, 0.12, 0.14)

		# Тусклый вечерний рассеянный свет
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.18, 0.19, 0.22)
		env.ambient_light_energy = 0.55

		# Тонмаппинг
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.05

		# Уличный вечерний блум от фонарей
		env.glow_enabled = true
		env.glow_intensity = 0.6
		env.glow_bloom = 0.18

		# Атмосферный вечерний густой туман (хорошо заметный, с красивым рассеиванием вокруг фонарей)
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = Color(0.12, 0.13, 0.16)
		env.fog_light_energy = 0.8
		env.fog_density = 0.035
		env.fog_depth_begin = 5.0
		env.fog_depth_end = 65.0
		env_node.environment = env

	# Слабый лунный / поздний вечерний свет под углом
	var moon = DirectionalLight3D.new()
	moon.name = "EveningCityLight"
	moon.light_color = Color(0.35, 0.40, 0.50)
	moon.light_energy = 0.45
	moon.rotation_degrees = Vector3(-65.0, 40.0, 0.0)
	moon.shadow_enabled = true
	moon.shadow_bias = 0.04
	add_child(moon)

	# 2. Единый аудиоплеер Уровня 89: сначала строго играет эмбиент толпы людей на громкости 5%
	is_level89_playing_music = false
	if level89_audio_player and is_instance_valid(level89_audio_player):
		level89_audio_player.queue_free()

	level89_audio_player = AudioStreamPlayer.new()
	level89_audio_player.name = "Level89AudioPlayer"
	level89_audio_player.finished.connect(_on_level89_audio_finished)
	add_child(level89_audio_player)

	# Запускаем строго эмбиент
	_play_level89_crowd_ambience()

	# 3. Перемещаем игрока на случайный перекресток города и запускаем анимацию подъема с асфальта
	var rand_cx = randi_range(-10, 10) * 2 # Четные координаты = улицы и перекрестки
	var rand_cz = randi_range(-10, 10) * 2
	current_player_chunk = Vector2i(rand_cx, rand_cz)
	update_chunks_around_player()

	if player:
		# Позиция игрока: на тротуаре перекрестка (Y = 0.35m)
		player.global_position = Vector3(rand_cx * CHUNK_SIZE + 4.5, 0.35, rand_cz * CHUNK_SIZE + 4.5)
		player.velocity = Vector3.ZERO
		player.play_getup_cutscene()

# Полная уборка Уровня -44 при переходе на любой другой уровень
func _teardown_level_minus44():
	if level44_generator and is_instance_valid(level44_generator):
		level44_generator.queue_free()
	level44_generator = null
	if level44_exit_door and is_instance_valid(level44_exit_door):
		level44_exit_door.queue_free()
	level44_exit_door = null
	if level44_audio_player and is_instance_valid(level44_audio_player):
		level44_audio_player.stop()

# Переход на Уровень -44 (монументальный бетонный комплекс)
func _transition_to_level_minus44():
	if is_transitioning:
		return
	is_transitioning = true
	current_level = -44
	has_escaped_monster_once = false

	# Замораживаем игрока на время перехода
	if player:
		player.is_active = false
		player.velocity = Vector3.ZERO
		if player.visual_root:
			player.visual_root.visible = false
		if player.head_shadow_mesh:
			player.head_shadow_mesh.visible = false

	# Удаляем NPC/монстров предыдущего уровня
	if spawned_npc and is_instance_valid(spawned_npc):
		spawned_npc.queue_free()
		spawned_npc = null
	if spawned_bacteria and is_instance_valid(spawned_bacteria):
		spawned_bacteria.queue_free()
		spawned_bacteria = null
	if spawned_urban_observer and is_instance_valid(spawned_urban_observer):
		spawned_urban_observer.queue_free()
		spawned_urban_observer = null
	for s in spawned_smilers:
		if is_instance_valid(s):
			s.queue_free()
	spawned_smilers.clear()

	# Останавливаем звуки предыдущих уровней
	if ambience_player:
		ambience_player.stop()
	if level1_audio_player and is_instance_valid(level1_audio_player):
		level1_audio_player.stop()
	if level89_audio_player and is_instance_valid(level89_audio_player):
		level89_audio_player.stop()

	# Очищаем чанки предыдущего уровня
	for c in active_chunks.keys():
		var cn = active_chunks[c]
		if is_instance_valid(cn):
			cn.queue_free()
	active_chunks.clear()
	active_omni_lights.clear()
	active_lamp_meshes.clear()
	# И всё, что осталось под корневым узлом чанков
	if corridors_root:
		for ch in corridors_root.get_children():
			ch.queue_free()

	# Видео-переход, как и на остальных уровнях
	var ui = find_child("UI", true, false)
	if not ui:
		_setup_level_minus44()
		return

	var vp = VideoStreamPlayer.new()
	vp.name = "NoclipTransitionPlayer"
	vp.expand = true
	vp.anchor_right = 1.0
	vp.anchor_bottom = 1.0
	vp.stream = load("res://death_jumpscare.ogv")
	vp.volume_db = 8.0
	vp.z_index = 100
	ui.add_child(vp)

	vp.finished.connect(func():
		vp.queue_free()
		_setup_level_minus44()
	)
	vp.play()

# Провал в дыру на Уровне -44: выбрасывает на случайный другой уровень
func _on_level44_hole():
	print("[LEVEL -44] Hole transition")
	_transition_to_random_level()

func _setup_level_minus44():
	# Настройка Уровня -44: бесконечный монументальный бетонный комплекс
	is_transitioning = false
	_mark_level_visited(-44)
	current_level = -44
	var env_node = get_node_or_null("WorldEnvironment")
	if env_node:
		var env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.01, 0.01, 0.011)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		# Мягкая общая засветка: слегка приглушена для давящей атмосферы полумрака
		env.ambient_light_color = Color(0.12, 0.12, 0.12)
		env.ambient_light_energy = 0.18
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 0.95
		env.ssao_enabled = true
		env.ssao_radius = 2.0
		env.ssao_intensity = 3.0
		env.glow_enabled = true
		env.glow_intensity = 0.7
		env.glow_bloom = 0.15
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = Color(0.022, 0.022, 0.021)
		env.fog_light_energy = 0.45
		env.fog_density = 0.017
		env.fog_depth_begin = 5.0
		env.fog_depth_end = 80.0
		env_node.environment = env

	var old_moon = get_node_or_null("EveningCityLight")
	if old_moon:
		old_moon.queue_free()

	# Генератор карты: сам подгружает и выгружает сектора вокруг игрока
	if level44_generator and is_instance_valid(level44_generator):
		level44_generator.queue_free()
	level44_generator = level44_script.new()
	level44_generator.name = "Level44Complex"
	add_child(level44_generator)

	# Гул огромного пустого бетонного зала
	if level44_audio_player and is_instance_valid(level44_audio_player):
		level44_audio_player.queue_free()
	level44_audio_player = AudioStreamPlayer.new()
	level44_audio_player.name = "Level44Ambience"
	level44_audio_player.stream = level44_ost_stream
	level44_audio_player.volume_db = linear_to_db(0.3)
	level44_audio_player.finished.connect(func(): if current_level == -44: level44_audio_player.play())
	add_child(level44_audio_player)
	level44_audio_player.play()

	if player:
		# Случайный сектор комплекса (с шагом 3 секторов, где гарантированно открытый коридор)
		var rand_gx = (randi_range(-8, 8)) * 3
		var rand_gz = (randi_range(-8, 8)) * 3
		var spawn_pos = Vector3(rand_gx * 60.0 + 30.0, 0.4, rand_gz * 60.0 + 30.0)
		player.global_position = spawn_pos
		player.velocity = Vector3.ZERO

	level44_generator.player_fell_in_hole.connect(_on_level44_hole)
	level44_generator.setup(player)

	# Выход с уровня: одинокая дверь в открытом зале неподалёку от случайной точки появления игрока
	if level44_exit_door and is_instance_valid(level44_exit_door):
		level44_exit_door.queue_free()
	level44_exit_door = interactive_door_script.new()
	level44_exit_door.name = "Level44ExitDoor"
	level44_exit_door.level_type = 1
	level44_exit_door.player_entered_black_void.connect(_on_door_void_entered)
	add_child(level44_exit_door)
	var door_base_pos = player.global_position if player else Vector3(30.0, 0.0, 30.0)
	level44_exit_door.global_position = Vector3(door_base_pos.x + 9.0, 0.0, door_base_pos.z)
	level44_exit_door.rotation.y = PI * 0.5

	if player:
		player.play_getup_cutscene()

# Обработчик касания рисунка с надписью EXIT
func _on_exit_drawing_touched():
	if current_level != 0 and current_level != 1:
		return
	if is_transitioning:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	# Защита от спама триггера в один и тот же момент (интервал минимум 0.8с между касаниями)
	if current_time - last_exit_touch_time < 0.8:
		return
	last_exit_touch_time = current_time

	exit_drawing_touch_count += 1
	print("[EXIT DRAWING] Touched %d time(s)" % exit_drawing_touch_count)

	if exit_drawing_touch_count >= 2:
		exit_drawing_touch_count = 0
		print("[LEVEL !] Double touch on EXIT drawing -> Transporting to Level ! (Run For Your Life)")
		_transition_to_level_run()

# Полная уборка Уровня ! (Run For Your Life)
func _teardown_level_run():
	if level_run_generator and is_instance_valid(level_run_generator):
		level_run_generator.queue_free()
	level_run_generator = null

# Переход на Уровень "!" (Level Run)
func _transition_to_level_run():
	if is_transitioning:
		return
	is_transitioning = true
	current_level = 99 # 99 = Level ! (Run For Your Life)
	has_escaped_monster_once = false
	_teardown_level_minus44()
	_teardown_level_run()
	_teardown_level_run()

	# Замораживаем игрока на время перехода
	if player:
		player.is_active = false
		player.velocity = Vector3.ZERO
		if player.visual_root:
			player.visual_root.visible = false
		if player.head_shadow_mesh:
			player.head_shadow_mesh.visible = false

	# Удаляем NPC/монстров предыдущего уровня
	if spawned_npc and is_instance_valid(spawned_npc):
		spawned_npc.queue_free()
		spawned_npc = null
	if spawned_bacteria and is_instance_valid(spawned_bacteria):
		spawned_bacteria.queue_free()
		spawned_bacteria = null
	if spawned_urban_observer and is_instance_valid(spawned_urban_observer):
		spawned_urban_observer.queue_free()
		spawned_urban_observer = null
	for s in spawned_smilers:
		if is_instance_valid(s):
			s.queue_free()
	spawned_smilers.clear()

	# Останавливаем фоновые звуки
	if ambience_player:
		ambience_player.stop()
	if level1_audio_player and is_instance_valid(level1_audio_player):
		level1_audio_player.stop()
	if level89_audio_player and is_instance_valid(level89_audio_player):
		level89_audio_player.stop()

	# Очищаем чанки
	for c in active_chunks.keys():
		var cn = active_chunks[c]
		if is_instance_valid(cn):
			cn.queue_free()
	active_chunks.clear()
	active_omni_lights.clear()
	active_lamp_meshes.clear()
	if corridors_root:
		for ch in corridors_root.get_children():
			ch.queue_free()

	# Видео-переход
	var ui = find_child("UI", true, false)
	if not ui:
		_setup_level_run()
		return

	var vp = VideoStreamPlayer.new()
	vp.name = "LevelRunTransitionPlayer"
	vp.expand = true
	vp.anchor_right = 1.0
	vp.anchor_bottom = 1.0
	vp.stream = load("res://death_jumpscare.ogv")
	vp.volume_db = 8.0
	vp.z_index = 100
	ui.add_child(vp)

	vp.finished.connect(func():
		vp.queue_free()
		_setup_level_run()
	)
	vp.play()

func _setup_level_run():
	is_transitioning = false
	current_level = 99
	_mark_level_visited(99)

	# Красное тревожное окружение
	var env_node = get_node_or_null("WorldEnvironment")
	if env_node:
		var env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.04, 0.0, 0.0)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.4, 0.02, 0.02)
		env.ambient_light_energy = 0.5
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.05
		env.glow_enabled = true
		env.glow_intensity = 0.8
		env.glow_bloom = 0.3
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = Color(0.3, 0.01, 0.01)
		env.fog_light_energy = 0.8
		env.fog_density = 0.015
		env.fog_depth_begin = 4.0
		env.fog_depth_end = 65.0
		env_node.environment = env

	var old_moon = get_node_or_null("EveningCityLight")
	if old_moon:
		old_moon.queue_free()

	# Создаем генератор коридора Level Run
	level_run_generator = level_run_script.new()
	level_run_generator.name = "LevelRunManager"
	level_run_generator.player_reached_exit.connect(func():
		print("[LEVEL !] Player survived and entered exit door!")
		_transition_to_random_level()
	)
	add_child(level_run_generator)

	if player:
		player.global_position = Vector3(0.0, 0.1, 0.0)
		player.velocity = Vector3.ZERO
		# Бесконечная стамина и повышенный адреналин (сердцебиение)
		if player.has_method("enable_infinite_stamina_only"):
			player.enable_infinite_stamina_only()

	level_run_generator.start_level(player)

	if player and player.has_method("play_level_run_intro_cutscene"):
		player.play_level_run_intro_cutscene()

# Генерация бесконечного вечернего города Level 89
# Каждый чанк ровно 16.0м х 16.0м состыкован по сетке:
# Чанки с четными координатами — улицы и перекрестки.
# Чанки с нечетными координатами — городские кварталы со зданиями.
func build_level89_urban_chunk(parent: Node3D, c: Vector2i, x0: float, z0: float):
	var h = get_hash(c.x, c.y, 8989)
	var is_road_x = (c.y % 2 == 0)
	var is_road_z = (c.x % 2 == 0)

	var center_pos = Vector3(x0 + CHUNK_SIZE * 0.5, 0.0, z0 + CHUNK_SIZE * 0.5)

	# 1. Перекресток 4 сторон
	if is_road_x and is_road_z:
		if urban_road_junction:
			var road = urban_road_junction.instantiate()
			road.position = center_pos
			parent.add_child(road)
			_add_collision_to_urban_model(road)

			# Уличные фонари на углах перекрестка с теплым вечерним светом
			for corner_offset in [Vector3(6.5, 0, 6.5), Vector3(-6.5, 0, -6.5)]:
				_spawn_street_lamp(parent, center_pos + corner_offset, atan2(corner_offset.x, corner_offset.z))

	# 2. Прямая улица по оси X
	elif is_road_x and not is_road_z:
		if urban_road_straight:
			var road = urban_road_straight.instantiate()
			road.position = center_pos
			road.rotation.y = PI * 0.5 # Вдоль оси X
			parent.add_child(road)
			_add_collision_to_urban_model(road)

			# Фонарный столб на тротуаре
			_spawn_street_lamp(parent, center_pos + Vector3(0.0, 0, 6.5), 0.0)

			# Мусорный бак у обочины
			if (h % 3) == 0 and urban_dumpster:
				var d = urban_dumpster.instantiate()
				d.position = center_pos + Vector3(3.5, 0, -6.2)
				d.rotation.y = PI * 0.5
				parent.add_child(d)
				_add_collision_to_urban_model(d)

	# 3. Прямая улица по оси Z
	elif not is_road_x and is_road_z:
		if urban_road_straight:
			var road = urban_road_straight.instantiate()
			road.position = center_pos
			parent.add_child(road)
			_add_collision_to_urban_model(road)

			# Фонарный столб на тротуаре
			_spawn_street_lamp(parent, center_pos + Vector3(6.5, 0, 0.0), PI * 0.5)

			# Мусорный бак у обочины
			if (h % 3) == 0 and urban_dumpster:
				var d = urban_dumpster.instantiate()
				d.position = center_pos + Vector3(-6.2, 0, 2.5)
				parent.add_child(d)
				_add_collision_to_urban_model(d)

	# 4. Городской квартал (здания)
	else:
		# Базовый тротуар / фундамент под зданием (визуальный меш + коллизия)
		var base_body = StaticBody3D.new()
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(CHUNK_SIZE, 0.32, CHUNK_SIZE)
		col.shape = box
		base_body.add_child(col)

		var base_mesh_inst = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(CHUNK_SIZE, 0.32, CHUNK_SIZE)
		base_mesh_inst.mesh = box_mesh
		if sidewalk_mat:
			base_mesh_inst.material_override = sidewalk_mat
		base_body.add_child(base_mesh_inst)

		base_body.position = center_pos + Vector3(0, 0.16, 0)
		parent.add_child(base_body)

		# Различные типы зданий: кирпичные, бетонные и Г-образные
		var building_type = h % 3
		var b_scene: PackedScene = null
		match building_type:
			0: b_scene = urban_building_brick
			1: b_scene = urban_building_concrete
			2: b_scene = urban_building_lshape

		if b_scene:
			var building = b_scene.instantiate()
			building.position = center_pos
			# Случайный поворот здания на 90 градусов для разнообразия силуэтов
			var b_rot = float((h >> 4) % 4) * (PI * 0.5)
			building.rotation.y = b_rot
			parent.add_child(building)
			_add_collision_to_urban_model(building)

			# Встроенные двери в модели каждого дома:
			# На каждой из 4 сторон здания размещаем проходную зону у встроенных дверей входа.
			# Игрок может просто подойти к фасаду дома и шагнуть сквозь дверь — срабатывает телепортация
			for side_idx in range(4):
				var side_angle = b_rot + float(side_idx) * (PI * 0.5)
				var side_dir = Vector3(0, 0, 1).rotated(Vector3.UP, side_angle)
				var door_zone_pos = center_pos + side_dir * 8.2 + Vector3(0, 1.4, 0)

				var pass_area = Area3D.new()
				pass_area.name = "HouseDoorTeleportArea_%d" % side_idx
				var a_col = CollisionShape3D.new()
				var a_box = BoxShape3D.new()
				a_box.size = Vector3(2.6, 2.8, 1.8)
				a_col.shape = a_box
				pass_area.add_child(a_col)
				pass_area.position = door_zone_pos
				pass_area.rotation.y = side_angle
				pass_area.body_entered.connect(func(body):
					if body.is_in_group("player") or body.name.to_lower().contains("player") or (body is CharacterBody3D and body.has_method("interact_with_door")):
						_transition_to_random_level()
				)
				parent.add_child(pass_area)

# Спавн уличного фонарного столба с точечным вечерним светом
func _spawn_street_lamp(parent: Node3D, pos: Vector3, rot_y: float):
	if not urban_street_light:
		return
	var lamp = urban_street_light.instantiate()
	lamp.position = pos
	lamp.rotation.y = rot_y
	parent.add_child(lamp)
	_add_collision_to_urban_model(lamp)

	# Реалистичный теплый желтый свет уличного фонаря
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.88, 0.65) # Теплый натриевый/лампа свет
	light.light_energy = 2.4
	light.omni_range = 14.0
	light.omni_attenuation = 1.3
	light.shadow_enabled = true
	light.shadow_bias = 0.05
	light.position = pos + Vector3(0, 5.8, 0)
	parent.add_child(light)

# Добавление точной физической коллизии к частям городских ассетов
func _add_collision_to_urban_model(root: Node3D):
	for m in root.find_children("*", "MeshInstance3D"):
		var mi = m as MeshInstance3D
		if mi.mesh:
			var sb = StaticBody3D.new()
			var col = CollisionShape3D.new()
			col.shape = mi.mesh.create_trimesh_shape()
			sb.add_child(col)
			mi.add_child(sb)

func unload_chunk(c: Vector2i):
	if active_chunks.has(c):
		var chunk_node = active_chunks[c]
		# Очищаем списки ламп
		active_omni_lights = active_omni_lights.filter(func(l): return is_instance_valid(l) and not chunk_node.is_ancestor_of(l))
		active_lamp_meshes = active_lamp_meshes.filter(func(m): return is_instance_valid(m) and not chunk_node.is_ancestor_of(m))
		active_chunks.erase(c)
		chunk_node.queue_free()

# Логика воспроизведения звуков Level 89:
# Строго один трек в один момент времени.
# 1) Сначала всегда играет эмбиент (звук толпы).
# 2) Когда трек заканчивается: с шансом 20% играет случайная песня на 10%, в остальных 80% — снова эмбиент на 5%.
# 3) После окончания песни — снова включается эмбиент.
func _play_level89_crowd_ambience():
	if current_level != 89 or not level89_audio_player:
		return
	is_level89_playing_music = false
	level89_audio_player.stop()
	level89_audio_player.stream = crowd_ambient_stream
	level89_audio_player.volume_db = linear_to_db(0.05) # Громкость 5%
	level89_audio_player.play()

func play_random_level89_song():
	if current_level != 89 or level89_songs.is_empty():
		return
	if not level89_audio_player or not is_instance_valid(level89_audio_player):
		level89_audio_player = AudioStreamPlayer.new()
		level89_audio_player.name = "Level89AudioPlayer"
		level89_audio_player.finished.connect(_on_level89_audio_finished)
		add_child(level89_audio_player)

	is_level89_playing_music = true
	var random_song = level89_songs.pick_random()
	level89_audio_player.stop()
	level89_audio_player.stream = random_song
	level89_audio_player.volume_db = linear_to_db(0.10) # Громкость 10%
	level89_audio_player.play()

func _on_level89_audio_finished():
	if current_level != 89:
		return

	# Если только что играла песня — после нее строго возвращается эмбиент
	if is_level89_playing_music:
		_play_level89_crowd_ambience()
	else:
		# Если только что играл эмбиент — с шансом 20% включается случайная песня, иначе снова эмбиент
		if randf() < 0.20:
			play_random_level89_song()
		else:
			_play_level89_crowd_ambience()

# Спавнер черного силуэта-наблюдателя Уровня 89
func _process_urban_observer_spawner(delta: float):
	if not player or not player.is_active:
		return

	# Если наблюдатель уже в мире и жив — ждем пока пропадет
	if spawned_urban_observer and is_instance_valid(spawned_urban_observer):
		return

	urban_observer_timer += delta
	if urban_observer_timer >= URBAN_OBSERVER_INTERVAL:
		urban_observer_timer = 0.0

		# Частое появление: проверка каждые 18 сек с высоким шансом 70%
		if randf() < 0.70:
			spawn_urban_observer()

func spawn_urban_observer():
	if not player or not urban_observer_scene:
		return

	# Игрок смотрит в определенную сторону:
	var forward_dir = -player.global_transform.basis.z
	forward_dir.y = 0.0
	forward_dir = forward_dir.normalized()
	if forward_dir.length_squared() < 0.1:
		forward_dir = Vector3(0, 0, -1)

	# Спавним строго СЗАДИ игрока вдалеке (дистанция 35-50 метров в тумане)
	# с небольшим случайным боковым смещением (-15 до +15 градусов)
	var spawn_dist = randf_range(35.0, 48.0)
	var side_offset = randf_range(-10.0, 10.0)
	var right_dir = player.global_transform.basis.x
	right_dir.y = 0.0
	right_dir = right_dir.normalized()

	var behind_dir = -forward_dir
	var spawn_pos = player.global_position + behind_dir * spawn_dist + right_dir * side_offset

	# Корректируем высоту Y по поверхности пола (проверяем лучом вниз)
	var space_state = get_world_3d().direct_space_state
	var ray_query = PhysicsRayQueryParameters3D.create(spawn_pos + Vector3(0, 10.0, 0), spawn_pos + Vector3(0, -10.0, 0))
	var hit = space_state.intersect_ray(ray_query)
	if not hit.is_empty():
		spawn_pos.y = hit.position.y
	else:
		spawn_pos.y = 0.35 # Стандартный уровень тротуара

	var observer = urban_observer_scene.instantiate()
	observer.global_position = spawn_pos
	add_child(observer)
	spawned_urban_observer = observer

# ==============================================================================
# Генерация бесконечного Уровня 1 (Habitable Zone):
# Крупные кластеры:
# - Огромные открытые залы парковки с ритмичными рядами колонн, подвесными трубами и лужами
# - Массивные бетонные лабиринты служебных коридоров с настенными щитками, вентиляцией и проходами
# ==============================================================================
const L1_CEIL_HEIGHT: float = 3.6 # Реалистичная высота потолка парковки/тех. помещений (3.6 метра)

func build_level1_chunk(parent: Node3D, c: Vector2i, x0: float, z0: float):
	var h = get_hash(c.x, c.y, 1011)

	# 1. Бетонный монолитный пол (16х16м)
	var floor_body = StaticBody3D.new()
	floor_body.name = "FloorBody"
	var floor_col = CollisionShape3D.new()
	var floor_box = BoxShape3D.new()
	floor_box.size = Vector3(CHUNK_SIZE, 0.4, CHUNK_SIZE)
	floor_col.shape = floor_box
	floor_body.add_child(floor_col)

	var floor_mesh = MeshInstance3D.new()
	var p_mesh = PlaneMesh.new()
	p_mesh.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
	floor_mesh.mesh = p_mesh
	floor_mesh.material_override = level1_floor_mat
	floor_body.add_child(floor_mesh)
	floor_body.position = Vector3(x0 + CHUNK_SIZE * 0.5, 0.0, z0 + CHUNK_SIZE * 0.5)
	parent.add_child(floor_body)

	# 2. Бетонный потолок
	var ceil_mesh = MeshInstance3D.new()
	var c_mesh = PlaneMesh.new()
	c_mesh.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
	ceil_mesh.mesh = c_mesh
	ceil_mesh.material_override = level1_ceil_mat
	ceil_mesh.position = Vector3(x0 + CHUNK_SIZE * 0.5, L1_CEIL_HEIGHT, z0 + CHUNK_SIZE * 0.5)
	ceil_mesh.rotation_degrees = Vector3(180, 0, 0)
	parent.add_child(ceil_mesh)

	# Крупное зонирование 50/50:
	# Используем детерминированную группировку чанков блоками 2х2 или шумной сеткой,
	# чтобы образовывались настоящие большие зоны парковки (по 30-50 метров) и протяженные коридоры
	var zone_hash = get_hash(int(floor(float(c.x) / 2.0)), int(floor(float(c.y) / 2.0)), 555)
	var is_corridor_chunk = (zone_hash % 2 == 1)

	# 3. Подвесные магистральные ржавые трубы под потолком в залах парковки
	if not is_corridor_chunk:
		_spawn_level1_ceiling_pipes(parent, c, x0, z0, h)

	if is_corridor_chunk:
		# ТЕХНИЧЕСКИЕ БЕТОННЫЕ КОРИДОРЫ (лабиринт с декорациями кабелей, щитков и вентиляции)
		_build_level1_technical_corridors(parent, c, x0, z0, h)
	else:
		# ПАРКОВКА / СКЛАДСКОЙ ЗАЛ (ритмичные ряды колонн, открытое пространство, лужи)
		_build_level1_open_pillars(parent, c, x0, z0, h)

# Подвесные магистральные трубы под потолком (в залах парковки)
func _spawn_level1_ceiling_pipes(parent: Node3D, c: Vector2i, x0: float, z0: float, h: int):
	var pipe_root = Node3D.new()
	pipe_root.name = "CeilingPipes"
	parent.add_child(pipe_root)

	var pipe_y = L1_CEIL_HEIGHT - 0.22
	var lane_offsets = [4.0, 12.0]

	for lane_x in lane_offsets:
		# Выбираем материал для всей магистрали на основе хеша линии (lane_x):
		# Линия труб тянется непрерывно одного цвета (красная, ржавая или стальная)
		var lane_hash = get_hash(int(lane_x), 0, 9371)
		var mat_type = lane_hash % 3
		var current_pipe_mat: StandardMaterial3D
		match mat_type:
			0:
				current_pipe_mat = level1_pipe_red_mat
			1:
				current_pipe_mat = level1_pipe_rusty_mat
			_:
				current_pipe_mat = level1_pipe_steel_mat

		# 1. Основное монолитное тело трубы (протянуто ровно через весь чанк 16м)
		var pipe = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.08
		cyl.bottom_radius = 0.08
		cyl.height = CHUNK_SIZE # 16.0 метров
		pipe.mesh = cyl
		pipe.material_override = current_pipe_mat
		pipe.rotation_degrees = Vector3(90, 0, 0) # Ориентируем вдоль Z
		pipe.position = Vector3(x0 + lane_x, pipe_y, z0 + CHUNK_SIZE * 0.5)
		pipe_root.add_child(pipe)

		# 2. Некоторым трубам добавляем вентиль снизу
		var chunk_pipe_hash = get_hash(c.x * 7 + int(lane_x), c.y * 11, 4411)
		if (chunk_pipe_hash % 3) == 0: # 33% шанс вентиля на трубе в чанке
			var valve_z = z0 + 4.0 + float((chunk_pipe_hash >> 3) % 9) # В пролёте
			var v_node = Node3D.new()
			v_node.position = Vector3(x0 + lane_x, pipe_y, valve_z)

			# Муфта/шток вентиля, направленный строго вниз
			var stem = MeshInstance3D.new()
			var stem_m = CylinderMesh.new()
			stem_m.top_radius = 0.03
			stem_m.bottom_radius = 0.03
			stem_m.height = 0.22
			stem.mesh = stem_m
			stem.material_override = current_pipe_mat
			stem.position = Vector3(0.0, -0.11, 0.0)
			v_node.add_child(stem)

			# Маховик/колесо вентиля снизу (горизонтальное колесо)
			if level1_pipe_valve_wheel_mesh:
				var wheel = MeshInstance3D.new()
				wheel.mesh = level1_pipe_valve_wheel_mesh
				wheel.material_override = level1_pipe_wheel_mat
				wheel.scale = Vector3(0.45, -0.45, 0.45) # Переворачиваем правильной лицевой стороной вниз
				wheel.position = Vector3(0.0, -0.22, 0.0)
				v_node.add_child(wheel)
			else:
				var torus = MeshInstance3D.new()
				var tm = TorusMesh.new()
				tm.inner_radius = 0.08
				tm.outer_radius = 0.14
				torus.mesh = tm
				torus.material_override = level1_pipe_wheel_mat
				torus.position = Vector3(0.0, -0.22, 0.0)
				v_node.add_child(torus)

			pipe_root.add_child(v_node)

# Тип 1: Открытые складские залы с колоннами, лужами и лампами
func _build_level1_open_pillars(parent: Node3D, c: Vector2i, x0: float, z0: float, h: int):
	# Ряды колонн: располагаются по сетке 4м и 12м, образуя бесконечные аллеи как на подземной парковке
	var pillar_offsets = [
		Vector3(4.0, 0, 4.0),
		Vector3(12.0, 0, 4.0),
		Vector3(4.0, 0, 12.0),
		Vector3(12.0, 0, 12.0)
	]

	for p_off in pillar_offsets:
		var p_pos = Vector3(x0 + p_off.x, 0.0, z0 + p_off.z)
		_spawn_level1_pillar(parent, p_pos)

	# Светильники расположены строго по центру проездов/аллей (X = 8.0м),
	# чтобы они висели в воздухе посреди зала и никогда не пересекались с трубами (X = 4.0м и 12.0м)
	var lamp_positions = [
		Vector3(x0 + 8.0, L1_CEIL_HEIGHT - 0.08, z0 + 4.0),
		Vector3(x0 + 8.0, L1_CEIL_HEIGHT - 0.08, z0 + 12.0)
	]

	for i in range(lamp_positions.size()):
		var l_pos = lamp_positions[i]
		var is_burned_out = ((h + i * 7) % 5) == 0 # 20% перегоревших
		_spawn_level1_lamp(parent, l_pos, is_burned_out)

	# Дорожные знаки в открытом зале парковки (хаотично прикреплены или стоят)
	if not level1_road_signs.is_empty() and (h % 2) == 0:
		var sign_sub_h = get_hash(c.x, c.y, 4421)
		var sign_idx = sign_sub_h % level1_road_signs.size()
		var sign_res = level1_road_signs[sign_idx]
		if sign_res:
			var sign_node = sign_res.instantiate()
			# Хаотичное случайное размещение в пролёте между колоннами
			var sx = x0 + 2.5 + float((sign_sub_h >> 3) % 110) * 0.1
			var sz = z0 + 2.5 + float((sign_sub_h >> 7) % 110) * 0.1
			sign_node.position = Vector3(sx, 0.0, sz)
			# Хаотичный угол поворота и легкий реалистичный наклон
			var base_yaw = float(sign_sub_h % 360) * (PI / 180.0)
			var tilt_pitch = deg_to_rad(float(((sign_sub_h >> 2) % 15) - 7))
			var tilt_roll = deg_to_rad(float(((sign_sub_h >> 5) % 15) - 7))
			sign_node.rotation = Vector3(tilt_pitch, base_yaw, tilt_roll)
			# По лору Backrooms все объекты из реального мира копируются зеркально
			sign_node.scale = Vector3(-1.0, 1.0, 1.0)
			parent.add_child(sign_node)
	# Спавн редких, широких и реалистичных луж конденсата
	# Реже (только в 1 из 3 чанков) и максимум 1 большая лужа на чанк, чтобы не было скоплений
	if (h % 3) == 0 and not level1_puddle_materials.is_empty():
		var sub_h = get_hash(c.x, c.y, 9123)
		var puddle_mesh = MeshInstance3D.new()
		var pud_p = PlaneMesh.new()
		# Широкие, разнообразные размеры лужи (от 4.5м до 8м в длину/ширину)
		var pud_w = 4.5 + float((sub_h >> 2) % 5) * 0.9
		var pud_h_size = 3.6 + float((sub_h >> 5) % 4) * 1.1
		pud_p.size = Vector2(pud_w, pud_h_size)
		puddle_mesh.mesh = pud_p

		var mat_idx = sub_h % level1_puddle_materials.size()
		puddle_mesh.material_override = level1_puddle_materials[mat_idx]
		puddle_mesh.rotation.y = float(sub_h % 360) * (PI / 180.0)

		# Располагаем ближе к середине пролета между колоннами
		var puddle_x = x0 + 6.0 + float((sub_h >> 1) % 5)
		var puddle_z = z0 + 6.0 + float((sub_h >> 3) % 5)
		puddle_mesh.position = Vector3(puddle_x, 0.003, puddle_z)
		parent.add_child(puddle_mesh)

# Тип 2: Технические коридоры (настоящий лабиринт из бетона, щитков и труб)
func _build_level1_technical_corridors(parent: Node3D, c: Vector2i, x0: float, z0: float, h: int):
	# Получаем процедурную сетку проходов и стен
	var grid = get_chunk_grid(c)

	# Строим бетонные монолитные стены коридоров
	for r in range(BLOCK_CELLS):
		var c_start = -1
		for col in range(BLOCK_CELLS):
			if grid[r][col] == 0:
				if c_start == -1:
					c_start = col
			else:
				if c_start != -1:
					_spawn_level1_wall_block(parent, x0, z0, r, c_start, col - 1)
					c_start = -1
		if c_start != -1:
			_spawn_level1_wall_block(parent, x0, z0, r, c_start, BLOCK_CELLS - 1)

	# Освещение коридоров (лампы в проходах)
	var lamp_coords = [
		Vector2(3.5, 3.5),
		Vector2(1.5, 3.5) if (h & 2) != 0 else Vector2(5.5, 3.5)
	]
	for lc in lamp_coords:
		var lx = x0 + (lc.x + 0.5) * CELL_SIZE
		var lz = z0 + (lc.y + 0.5) * CELL_SIZE
		var is_burned = (h % 4) == 0
		_spawn_level1_lamp(parent, Vector3(lx, L1_CEIL_HEIGHT - 0.08, lz), is_burned)

	# Хаотично размещенные дорожные знаки в технических коридорах (на полу у стен или посреди проходов)
	if not level1_road_signs.is_empty() and (h % 2) == 0:
		var sign_placed = false
		var sign_sub_h = get_hash(c.x, c.y, 8819)
		for r in range(1, BLOCK_CELLS - 1):
			if sign_placed:
				break
			for col in range(1, BLOCK_CELLS - 1):
				if grid[r][col] == 1: # Свободная клетка прохода
					var sign_idx = (sign_sub_h + r + col) % level1_road_signs.size()
					var sign_res = level1_road_signs[sign_idx]
					if sign_res:
						var sign_node = sign_res.instantiate()
						var sx = x0 + (col + 0.5) * CELL_SIZE + float((sign_sub_h >> 2) % 7 - 3) * 0.1
						var sz = z0 + (r + 0.5) * CELL_SIZE + float((sign_sub_h >> 4) % 7 - 3) * 0.1
						sign_node.position = Vector3(sx, 0.0, sz)
						var base_yaw = float((sign_sub_h + col * 45) % 360) * (PI / 180.0)
						var tilt_pitch = deg_to_rad(float(((sign_sub_h >> 3) % 17) - 8))
						var tilt_roll = deg_to_rad(float(((sign_sub_h >> 6) % 17) - 8))
						sign_node.rotation = Vector3(tilt_pitch, base_yaw, tilt_roll)
						# По лору Backrooms все объекты из реального мира копируются зеркально
						sign_node.scale = Vector3(-1.0, 1.0, 1.0)
						parent.add_child(sign_node)
						sign_placed = true
						break

	# Редкий спавн интерактивной двери в стене технического коридора (1 на 200 метров)
	maybe_spawn_door_in_chunk(parent, c, grid, x0, z0, 1)

func _spawn_level1_wall_block(parent: Node3D, x0: float, z0: float, r: int, c1: int, c2: int):
	var count = c2 - c1 + 1
	var sx = count * CELL_SIZE
	var sz = CELL_SIZE
	var px = x0 + (float(c1) + float(count) * 0.5) * CELL_SIZE
	var pz = z0 + (float(r) + 0.5) * CELL_SIZE

	var wall = StaticBody3D.new()
	wall.position = Vector3(px, L1_CEIL_HEIGHT * 0.5, pz)

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(sx, L1_CEIL_HEIGHT, sz)
	mesh.mesh = box
	mesh.material_override = level1_wall_mat # Чистая грубая бетонная текстура стен
	wall.add_child(mesh)

	var shape = CollisionShape3D.new()
	var b_shape = BoxShape3D.new()
	b_shape.size = Vector3(sx, L1_CEIL_HEIGHT, sz)
	shape.shape = b_shape
	wall.add_child(shape)

	parent.add_child(wall)

func _spawn_level1_pillar(parent: Node3D, pos: Vector3):
	var pillar_body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(1.2, L1_CEIL_HEIGHT, 1.2)
	col.shape = box
	pillar_body.add_child(col)

	var p_mesh = MeshInstance3D.new()
	var b_mesh = BoxMesh.new()
	b_mesh.size = Vector3(1.2, L1_CEIL_HEIGHT, 1.2)
	p_mesh.mesh = b_mesh
	p_mesh.material_override = level1_pillar_mat
	pillar_body.add_child(p_mesh)

	pillar_body.position = pos + Vector3(0, L1_CEIL_HEIGHT * 0.5, 0)
	parent.add_child(pillar_body)

func _spawn_level1_lamp(parent: Node3D, pos: Vector3, is_burned_out: bool):
	var lamp_mesh = MeshInstance3D.new()
	var box_m = BoxMesh.new()
	box_m.size = Vector3(2.0, 0.08, 0.25)
	lamp_mesh.mesh = box_m
	lamp_mesh.material_override = lamp_off_mat if is_burned_out else lamp_mat
	lamp_mesh.position = pos
	parent.add_child(lamp_mesh)
	active_lamp_meshes.append(lamp_mesh)

	if not is_burned_out:
		var light = OmniLight3D.new()
		light.position = pos - Vector3(0, 0.25, 0)
		light.light_color = Color(0.92, 0.95, 1.0) # Холодный белый люминесцентный свет
		light.light_energy = 1.7
		light.omni_range = 12.0
		light.omni_attenuation = 1.2
		light.shadow_enabled = true
		light.shadow_bias = 0.05
		light.distance_fade_enabled = true
		light.distance_fade_begin = 26.0
		light.distance_fade_length = 8.0
		parent.add_child(light)
		active_omni_lights.append(light)
