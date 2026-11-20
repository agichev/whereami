extends Control

@onready var volume_slider: HSlider = $CenterContainer/Panel/MarginContainer/ScrollContainer/VBoxContainer/VolRow/HSlider
@onready var sens_slider: HSlider = $CenterContainer/Panel/MarginContainer/ScrollContainer/VBoxContainer/SensRow/HSlider
@onready var fov_slider: HSlider = $CenterContainer/Panel/MarginContainer/ScrollContainer/VBoxContainer/FovRow/HSlider
@onready var fov_val_label: Label = $CenterContainer/Panel/MarginContainer/ScrollContainer/VBoxContainer/FovRow/ValueLabel
@onready var vhs_check: CheckBox = $CenterContainer/Panel/MarginContainer/ScrollContainer/VBoxContainer/VhsRow/CheckBox
@onready var fs_check: CheckBox = $CenterContainer/Panel/MarginContainer/ScrollContainer/VBoxContainer/FsRow/CheckBox
@onready var res_option: OptionButton = $CenterContainer/Panel/MarginContainer/ScrollContainer/VBoxContainer/ResRow/OptionButton
@onready var vsync_check: CheckBox = $CenterContainer/Panel/MarginContainer/ScrollContainer/VBoxContainer/VsyncRow/CheckBox
@onready var fps_option: OptionButton = $CenterContainer/Panel/MarginContainer/ScrollContainer/VBoxContainer/FpsRow/OptionButton
@onready var render_option: OptionButton = $CenterContainer/Panel/MarginContainer/ScrollContainer/VBoxContainer/RenderRow/OptionButton
@onready var chunk_slider: HSlider = $CenterContainer/Panel/MarginContainer/ScrollContainer/VBoxContainer/ChunkRow/HSlider
@onready var chunk_val_label: Label = $CenterContainer/Panel/MarginContainer/ScrollContainer/VBoxContainer/ChunkRow/ValueLabel
@onready var back_btn: Button = $CenterContainer/Panel/MarginContainer/ScrollContainer/VBoxContainer/BackButton

signal back_pressed

const FPS_OPTIONS = [0, 30, 60, 90, 120, 144, 240]
const RESOLUTION_OPTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160)
]

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	back_btn.pressed.connect(_on_back_pressed)
	
	setup_fps_dropdown()
	setup_resolution_dropdown()
	setup_render_dropdown()
	
	volume_slider.value_changed.connect(_on_volume_changed)
	sens_slider.value_changed.connect(_on_sens_changed)
	fov_slider.value_changed.connect(_on_fov_changed)
	vhs_check.toggled.connect(_on_vhs_toggled)
	fs_check.toggled.connect(_on_fs_toggled)
	res_option.item_selected.connect(_on_res_selected)
	vsync_check.toggled.connect(_on_vsync_toggled)
	fps_option.item_selected.connect(_on_fps_selected)
	render_option.item_selected.connect(_on_render_selected)
	chunk_slider.value_changed.connect(_on_chunk_slider_changed)
	
	sync_from_settings()

func setup_resolution_dropdown():
	res_option.clear()
	for res in RESOLUTION_OPTIONS:
		res_option.add_item("%d x %d" % [res.x, res.y])

func setup_fps_dropdown():
	fps_option.clear()
	for val in FPS_OPTIONS:
		if val == 0:
			fps_option.add_item("Unlimited")
		else:
			fps_option.add_item(str(val) + " FPS")

func setup_render_dropdown():
	render_option.clear()
	render_option.add_item("Forward+ (Vulkan / D3D12)")
	render_option.add_item("Compatibility (OpenGL 3.3)")

var game_settings = preload("res://game_settings.gd")

func sync_from_settings():
	var gs = game_settings.instance
	if not gs:
		return
	volume_slider.value = gs.master_volume * 100.0
	# sens default 0.0025 -> 2.5
	sens_slider.value = gs.mouse_sensitivity * 1000.0
	fov_slider.value = gs.fov
	fov_val_label.text = "%d°" % int(round(gs.fov))
	vhs_check.button_pressed = gs.vhs_enabled
	fs_check.button_pressed = gs.fullscreen
	res_option.disabled = gs.fullscreen # При Fullscreen разрешение зафиксировано разрешением монитора
	
	var res_idx = RESOLUTION_OPTIONS.find(gs.window_resolution)
	if res_idx != -1:
		res_option.selected = res_idx
	else:
		res_option.selected = 3 # 1920x1080 default
		
	vsync_check.button_pressed = gs.vsync_enabled
	chunk_slider.value = gs.chunk_render_distance
	chunk_val_label.text = "%d Chunks" % int(gs.chunk_render_distance)
	
	var fps_idx = FPS_OPTIONS.find(gs.max_fps)
	if fps_idx != -1:
		fps_option.selected = fps_idx
	else:
		fps_option.selected = 2 # default 60 FPS

	# Опция рендеринга
	if gs.graphics_backend == "OpenGL":
		render_option.selected = 1
	else:
		render_option.selected = 0

func _on_render_selected(index: int):
	var gs = game_settings.instance
	if not gs:
		return
	var new_backend = "Vulkan" if index == 0 else "OpenGL"
	if new_backend == gs.graphics_backend:
		return
	# Применяем с перезапуском
	gs.restart_with_backend(new_backend)
func _on_vsync_toggled(toggled: bool):
	var gs = game_settings.instance
	if gs:
		gs.vsync_enabled = toggled
		gs.apply_settings()

func _on_fps_selected(index: int):
	if index >= 0 and index < FPS_OPTIONS.size():
		var gs = game_settings.instance
		if gs:
			gs.max_fps = FPS_OPTIONS[index]
			gs.apply_settings()

func _on_volume_changed(val: float):
	var gs = game_settings.instance
	if gs:
		gs.master_volume = val / 100.0
		gs.apply_settings()

func _on_sens_changed(val: float):
	var gs = game_settings.instance
	if gs:
		gs.mouse_sensitivity = val / 1000.0
		gs.apply_settings()

func _on_fov_changed(val: float):
	fov_val_label.text = "%d°" % int(round(val))
	var gs = game_settings.instance
	if gs:
		gs.fov = val
		gs.apply_settings()

func _on_vhs_toggled(toggled: bool):
	var gs = game_settings.instance
	if gs:
		gs.vhs_enabled = toggled
		gs.apply_settings()

func _on_fs_toggled(toggled: bool):
	res_option.disabled = toggled
	var gs = game_settings.instance
	if gs:
		gs.fullscreen = toggled
		gs.apply_settings()

func _on_res_selected(index: int):
	if index >= 0 and index < RESOLUTION_OPTIONS.size():
		var gs = game_settings.instance
		if gs:
			gs.window_resolution = RESOLUTION_OPTIONS[index]
			gs.apply_settings()

func _on_chunk_slider_changed(val: float):
	var int_val = int(round(val))
	chunk_val_label.text = "%d Chunks" % int_val
	var gs = game_settings.instance
	if gs:
		gs.chunk_render_distance = int_val
		gs.apply_settings()

func _on_back_pressed():
	back_pressed.emit()
