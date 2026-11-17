class_name InteractiveDoor
extends Node3D

signal player_entered_black_void(door: InteractiveDoor)

@export var is_open: bool = false
@export var level_type: int = 0 # 0 = Level 0 (Door3 style / Cenji), 1 = Level 1 (Door6 style)

var door_pivot: Node3D
var door_mesh_instance: MeshInstance3D
var void_area: Area3D
var audio_player: AudioStreamPlayer3D
var door_sfx_open = preload("res://audio/Door_squeeky_2.wav")
var door_sfx_close: AudioStream = null

var target_angle: float = 0.0
var current_angle: float = 0.0

func _ready():
	door_sfx_close = load("res://audio/door_close.mp3") as AudioStream
	_setup_door()

func _setup_door():
	# 1. Звук двери
	audio_player = AudioStreamPlayer3D.new()
	audio_player.name = "DoorAudio"
	audio_player.max_distance = 18.0
	audio_player.unit_size = 4.0
	audio_player.volume_db = 1.0
	add_child(audio_player)

	# 2. Дверная коробка / наличники вокруг проема
	var frame_mat = StandardMaterial3D.new()
	if level_type == 0:
		frame_mat.albedo_color = Color(0.32, 0.20, 0.11) # Темное дерево
		frame_mat.roughness = 0.7
	else:
		frame_mat.albedo_color = Color(0.24, 0.25, 0.26) # Индустриальный серый металл
		frame_mat.roughness = 0.5
		frame_mat.metallic = 0.6

	# Толщина наличника 0.05м, глубина 0.08м, ширина двери 0.90м, высота 2.05м
	var frame_left = _create_box(Vector3(0.05, 2.05, 0.08), Vector3(-0.47, 1.025, 0.0), frame_mat)
	var frame_right = _create_box(Vector3(0.05, 2.05, 0.08), Vector3(0.47, 1.025, 0.0), frame_mat)
	var frame_top = _create_box(Vector3(0.99, 0.05, 0.08), Vector3(0.0, 2.05, 0.0), frame_mat)
	add_child(frame_left)
	add_child(frame_right)
	add_child(frame_top)

	# 3. Чернота за дверью (нематериальная пустота)
	# Располагаем тонкий черный экран прямо внутри рамы (z = 0.015),
	# чтобы он находился ПЕРЕД стеной и скрывал обои/бетон без Z-fighting'а,
	# но оставался утоплен внутри дверного проема относительно наличников
	var void_mat = StandardMaterial3D.new()
	void_mat.albedo_color = Color(0.0, 0.0, 0.0)
	void_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # Чистая 100% черная пустота
	void_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	void_mat.render_priority = 2
	void_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS

	var void_box = _create_box(Vector3(0.89, 2.03, 0.02), Vector3(0.0, 1.015, 0.015), void_mat)
	add_child(void_box)

	# Триггер входа в пустоту
	# Выдвинут вперед перед дверью на 0.5м (z = 0.35, глубина 0.9м),
	# чтобы при открытой двери игрок моментально касался триггера пустоты при шаге в проем,
	# еще до того, как упрется в физическую стену!
	void_area = Area3D.new()
	void_area.name = "VoidTrigger"
	var v_col = CollisionShape3D.new()
	var v_shape = BoxShape3D.new()
	v_shape.size = Vector3(0.88, 2.0, 0.9)
	v_col.shape = v_shape
	void_area.add_child(v_col)
	void_area.position = Vector3(0.0, 1.0, 0.35)
	void_area.body_entered.connect(_on_void_body_entered)
	add_child(void_area)

	# 4. Пивот дверного полотна (петли слева: X = -0.42)
	door_pivot = Node3D.new()
	door_pivot.name = "DoorPivot"
	door_pivot.position = Vector3(-0.42, 0.0, 0.0)
	add_child(door_pivot)

	# Дверное полотно (StaticBody для коллизии и клика)
	var door_body = StaticBody3D.new()
	door_body.name = "DoorLeafBody"
	door_body.set_meta("is_interactive_door", true)
	door_body.set_meta("door_parent", self)

	var leaf_col = CollisionShape3D.new()
	var leaf_box = BoxShape3D.new()
	leaf_box.size = Vector3(0.84, 2.0, 0.08)
	leaf_col.shape = leaf_box
	leaf_col.position = Vector3(0.42, 1.0, 0.0) # Смещено от петли
	door_body.add_child(leaf_col)

	# Модель двери FBX:
	# При повороте на -90 градусов (270 град) петли (бывший Z=+0.4) совмещаются с пивотом (X=-0.42),
	# а ручка (бывший Z=-0.35) оказывается на свободном крае двери (X=+0.42)
	var loaded_model: Node3D = null
	if level_type == 0:
		var d3_res = load("res://doors/Door3.fbx")
		if d3_res:
			loaded_model = d3_res.instantiate()
	else:
		var d6_res = load("res://doors/Door6.fbx")
		if d6_res:
			loaded_model = d6_res.instantiate()

	if loaded_model:
		loaded_model.rotation_degrees = Vector3(0, -90, 0)
		loaded_model.position = Vector3(0.42, 0.0, 0.0)
		door_body.add_child(loaded_model)

		# Во FBX дверей указана внешняя текстура (TextureLowPoly.png), которой нет в репозитории:
		# без переопределения дверь на свежем клоне выглядит белой. Назначаем свой материал,
		# чтобы полотно двери выглядело одинаково на любой машине.
		var leaf_door_mat = StandardMaterial3D.new()
		leaf_door_mat.albedo_color = Color(0.36, 0.22, 0.12) if level_type == 0 else Color(0.34, 0.36, 0.38)
		leaf_door_mat.roughness = 0.72
		leaf_door_mat.metallic = 0.0 if level_type == 0 else 0.55
		for mi in loaded_model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = leaf_door_mat
	else:
		var leaf_mesh = MeshInstance3D.new()
		var b = BoxMesh.new()
		b.size = Vector3(0.84, 2.0, 0.06)
		leaf_mesh.mesh = b
		var leaf_mat = StandardMaterial3D.new()
		leaf_mat.albedo_color = Color(0.45, 0.28, 0.16) if level_type == 0 else Color(0.4, 0.42, 0.44)
		leaf_mesh.material_override = leaf_mat
		leaf_mesh.position = Vector3(0.42, 1.0, 0.0)
		door_body.add_child(leaf_mesh)

	door_pivot.add_child(door_body)

func _create_box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var b = BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	return mi

func toggle():
	is_open = not is_open
	# Открывается наружу на игрока (-105 градусов по часовой стрелке), освобождая проем
	target_angle = deg_to_rad(-105.0) if is_open else 0.0

	if audio_player:
		audio_player.stream = door_sfx_open if is_open else door_sfx_close
		audio_player.pitch_scale = randf_range(0.95, 1.05)
		audio_player.play()

func _process(delta: float):
	if abs(current_angle - target_angle) > 0.005:
		current_angle = lerp_angle(current_angle, target_angle, delta * 6.0)
		if door_pivot:
			door_pivot.rotation.y = current_angle

func _on_void_body_entered(body: Node):
	# Если дверь открыта и игрок шагает в пустоту — переносим на случайный уровень
	if is_open:
		if body.is_in_group("player") or body.name.to_lower().contains("player") or (body is CharacterBody3D and body.has_method("interact_with_door")):
			player_entered_black_void.emit(self)
