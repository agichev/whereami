extends Control

@onready var tab_general_btn: Button = $CenterContainer/Panel/MarginContainer/MainVBox/TabsRow/TabGeneralBtn
@onready var tab_keybinds_btn: Button = $CenterContainer/Panel/MarginContainer/MainVBox/TabsRow/TabKeybindsBtn
@onready var general_tab: ScrollContainer = $CenterContainer/Panel/MarginContainer/MainVBox/GeneralTab
@onready var keybinds_tab: ScrollContainer = $CenterContainer/Panel/MarginContainer/MainVBox/KeybindsTab
@onready var keybinds_list: VBoxContainer = $CenterContainer/Panel/MarginContainer/MainVBox/KeybindsTab/VBoxContainer/KeybindsList
@onready var reset_keybinds_btn: Button = $CenterContainer/Panel/MarginContainer/MainVBox/KeybindsTab/VBoxContainer/ResetKeybindsBtn

# Оверлей ожидания нажатия клавиши
@onready var key_listen_overlay: ColorRect = $KeyListenOverlay
@onready var action_prompt_label: Label = $KeyListenOverlay/Center/Panel/Margin/VBox/ActionPromptLabel

# Общие настройки
@onready var volume_slider: HSlider = $CenterContainer/Panel/MarginContainer/MainVBox/GeneralTab/VBoxContainer/VolRow/HSlider
@onready var sens_slider: HSlider = $CenterContainer/Panel/MarginContainer/MainVBox/GeneralTab/VBoxContainer/SensRow/HSlider
@onready var fov_slider: HSlider = $CenterContainer/Panel/MarginContainer/MainVBox/GeneralTab/VBoxContainer/FovRow/HSlider
@onready var fov_val_label: Label = $CenterContainer/Panel/MarginContainer/MainVBox/GeneralTab/VBoxContainer/FovRow/ValueLabel
@onready var vhs_check: CheckBox = $CenterContainer/Panel/MarginContainer/MainVBox/GeneralTab/VBoxContainer/VhsRow/CheckBox
@onready var fs_check: CheckBox = $CenterContainer/Panel/MarginContainer/MainVBox/GeneralTab/VBoxContainer/FsRow/CheckBox
@onready var res_option: OptionButton = $CenterContainer/Panel/MarginContainer/MainVBox/GeneralTab/VBoxContainer/ResRow/OptionButton
@onready var vsync_check: CheckBox = $CenterContainer/Panel/MarginContainer/MainVBox/GeneralTab/VBoxContainer/VsyncRow/CheckBox
@onready var fps_option: OptionButton = $CenterContainer/Panel/MarginContainer/MainVBox/GeneralTab/VBoxContainer/FpsRow/OptionButton
@onready var render_option: OptionButton = $CenterContainer/Panel/MarginContainer/MainVBox/GeneralTab/VBoxContainer/RenderRow/OptionButton
@onready var chunk_slider: HSlider = $CenterContainer/Panel/MarginContainer/MainVBox/GeneralTab/VBoxContainer/ChunkRow/HSlider
@onready var chunk_val_label: Label = $CenterContainer/Panel/MarginContainer/MainVBox/GeneralTab/VBoxContainer/ChunkRow/ValueLabel
@onready var back_btn: Button = $CenterContainer/Panel/MarginContainer/MainVBox/BottomRow/BackButton

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

var game_settings = preload("res://game_settings.gd")
var rebinding_action: String = ""

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	back_btn.pressed.connect(_on_back_pressed)
	
	# Настройка переключения вкладок
	tab_general_btn.pressed.connect(_on_tab_general_pressed)
	tab_keybinds_btn.pressed.connect(_on_tab_keybinds_pressed)
	reset_keybinds_btn.pressed.connect(_on_reset_keybinds_pressed)
	
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
	populate_keybinds_list()

func _on_tab_general_pressed():
	general_tab.visible = true
	keybinds_tab.visible = false
	var active_style = tab_general_btn.get_theme_stylebox("hover")
	var inactive_style = tab_keybinds_btn.get_theme_stylebox("normal")
	tab_general_btn.add_theme_stylebox_override("normal", active_style)
	tab_general_btn.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6, 1.0))
	tab_keybinds_btn.add_theme_stylebox_override("normal", inactive_style)
	tab_keybinds_btn.add_theme_color_override("font_color", Color(0.65, 0.62, 0.5, 1.0))

func _on_tab_keybinds_pressed():
	general_tab.visible = false
	keybinds_tab.visible = true
	var active_style = tab_general_btn.get_theme_stylebox("hover")
	var inactive_style = tab_keybinds_btn.get_theme_stylebox("normal")
	tab_general_btn.add_theme_stylebox_override("normal", inactive_style)
	tab_general_btn.add_theme_color_override("font_color", Color(0.65, 0.62, 0.5, 1.0))
	tab_keybinds_btn.add_theme_stylebox_override("normal", active_style)
	tab_keybinds_btn.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6, 1.0))

func populate_keybinds_list():
	for child in keybinds_list.get_children():
		child.queue_free()

	var gs = game_settings.instance
	if not gs:
		return

	# Создаем стили кнопок биндов без размытия/смещения границ (expand_margin = 0)
	var key_normal = StyleBoxFlat.new()
	key_normal.bg_color = Color(0.12, 0.11, 0.05, 0.85)
	key_normal.border_color = Color(0.65, 0.60, 0.25, 0.6)
	key_normal.set_border_width_all(1)
	key_normal.set_corner_radius_all(3)

	var key_hover = StyleBoxFlat.new()
	key_hover.bg_color = Color(0.24, 0.21, 0.08, 0.95)
	key_hover.border_color = Color(0.95, 0.88, 0.45, 0.9)
	key_hover.set_border_width_all(1)
	key_hover.set_corner_radius_all(3)

	for action in gs.REBINDABLE_ACTIONS:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 16)

		var label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = gs.ACTION_DISPLAY_NAMES.get(action, action)
		label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7, 1.0))
		label.add_theme_font_size_override("font_size", 14)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)

		var btn = Button.new()
		btn.custom_minimum_size = Vector2(160, 32)
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = gs.get_action_key_name(action)
		btn.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.75, 1.0))
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_stylebox_override("normal", key_normal)
		btn.add_theme_stylebox_override("hover", key_hover)
		btn.add_theme_stylebox_override("pressed", key_hover)

		var captured_action = action
		btn.pressed.connect(func(): _start_rebinding(captured_action))
		row.add_child(btn)

		keybinds_list.add_child(row)

func _start_rebinding(action: String):
	var gs = game_settings.instance
	rebinding_action = action
	var display_name = gs.ACTION_DISPLAY_NAMES.get(action, action) if gs else action
	action_prompt_label.text = "Press any key for:\n[%s]" % display_name
	key_listen_overlay.visible = true

func _cancel_rebinding():
	rebinding_action = ""
	key_listen_overlay.visible = false

func _input(event: InputEvent):
	if rebinding_action != "":
		if event is InputEventKey and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			var key_to_set = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
			
			if key_to_set == KEY_ESCAPE and rebinding_action != "pause":
				# Esc отменяет переназначение для любого действия, кроме самого действия pause
				_cancel_rebinding()
				return
			
			var gs = game_settings.instance
			if gs:
				gs.set_keybind(rebinding_action, key_to_set)
			
			_cancel_rebinding()
			populate_keybinds_list()

func _on_reset_keybinds_pressed():
	var gs = game_settings.instance
	if gs:
		gs.reset_keybinds_to_defaults()
	populate_keybinds_list()

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

func sync_from_settings():
	var gs = game_settings.instance
	if not gs:
		return
	volume_slider.value = gs.master_volume * 100.0
	sens_slider.value = gs.mouse_sensitivity * 1000.0
	fov_slider.value = gs.fov
	fov_val_label.text = "%d°" % int(round(gs.fov))
	vhs_check.button_pressed = gs.vhs_enabled
	fs_check.button_pressed = gs.fullscreen
	res_option.disabled = gs.fullscreen
	
	var res_idx = RESOLUTION_OPTIONS.find(gs.window_resolution)
	if res_idx != -1:
		res_option.selected = res_idx
	else:
		res_option.selected = 3
		
	vsync_check.button_pressed = gs.vsync_enabled
	chunk_slider.value = gs.chunk_render_distance
	chunk_val_label.text = "%d Chunks" % int(gs.chunk_render_distance)
	
	var fps_idx = FPS_OPTIONS.find(gs.max_fps)
	if fps_idx != -1:
		fps_option.selected = fps_idx
	else:
		fps_option.selected = 2

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
