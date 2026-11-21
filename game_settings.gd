class_name GameSettingsNode
extends Node

static var instance: GameSettingsNode = null

# Флаг, показывалась ли уже заставка разработчика в этой сессии
var splash_already_shown: bool = false
var launch_count: int = 0 # Количество запусков игры (первые 5 нельзя пропускать заставку)
var mouse_sensitivity: float = 0.0025
var master_volume: float = 1.0 # 0.0 to 1.0
var fov: float = 70.0
var vhs_enabled: bool = true
var fullscreen: bool = true
var window_resolution: Vector2i = Vector2i(1920, 1080)
var vsync_enabled: bool = true
var max_fps: int = 60 # 0 = Unlimited, 30, 60, 120, 144, 240
var chunk_render_distance: int = 5 # Радиус чанков (от 2 до 8, по умолчанию 5)
var graphics_backend: String = "Vulkan" # "Vulkan" или "OpenGL"
var graphics_backend_changed: bool = false # Смена бэкенда требует перезапуска приложения

# Настраиваемые действия управления (клавиши)
const REBINDABLE_ACTIONS: Array[String] = [
	"move_forward",
	"move_backward",
	"move_left",
	"move_right",
	"sprint",
	"interact",
	"flashlight",
	"pause"
]

const ACTION_DISPLAY_NAMES = {
	"move_forward": "Move Forward",
	"move_backward": "Move Backward",
	"move_left": "Move Left",
	"move_right": "Move Right",
	"sprint": "Sprint",
	"interact": "Interact / Open Door",
	"flashlight": "Flashlight",
	"pause": "Pause / Menu"
}

# Дефолтные клавиши (physical_keycode или keycode)
const DEFAULT_KEYBINDS = {
	"move_forward": KEY_W,
	"move_backward": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"sprint": KEY_SHIFT,
	"interact": KEY_E,
	"flashlight": KEY_F,
	"pause": KEY_ESCAPE
}

var keybinds: Dictionary = {}

# Музыка меню (выбирается случайно между Warm Nights и Hey Kids при запуске, сохраняет позицию)
var menu_music_player: AudioStreamPlayer = null
var warm_nights_stream = preload("res://audio/Warm_Nights.mp3")
var hey_kids_stream = preload("res://audio/hey_kids.mp3")
var active_menu_stream: AudioStream = null
var menu_music_playback_pos: float = 0.0

signal settings_changed

static func get_singleton() -> GameSettingsNode:
	return instance

func _enter_tree():
	instance = self

func _ready():
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	setup_menu_music_player()

func setup_menu_music_player():
	if menu_music_player:
		return

	# Случайный выбор одного из двух треков меню
	if randf() < 0.5:
		active_menu_stream = warm_nights_stream
	else:
		active_menu_stream = hey_kids_stream

	menu_music_player = AudioStreamPlayer.new()
	menu_music_player.name = "MenuMusicPlayer"
	menu_music_player.stream = active_menu_stream
	menu_music_player.process_mode = Node.PROCESS_MODE_ALWAYS # Играет даже когда дерево на паузе!
	add_child(menu_music_player)

# Воспроизведение музыки меню (vol_linear: 1.0 = 100% в главном меню, 0.10 = 10% в меню паузы Esc)
func play_menu_music(vol_linear: float = 1.0):
	if not menu_music_player:
		setup_menu_music_player()

	# Переводим линейную громкость в dB (1.0 -> -1.0 dB, 0.10 -> -20.0 dB)
	var target_db = linear_to_db(clamp(vol_linear, 0.001, 1.0))
	menu_music_player.volume_db = target_db

	if not menu_music_player.is_playing():
		var stream_len = active_menu_stream.get_length() if active_menu_stream else 0.0
		var seek_pos = fmod(menu_music_playback_pos, stream_len) if stream_len > 0.0 else 0.0
		menu_music_player.play(seek_pos)

func pause_menu_music():
	if menu_music_player and menu_music_player.is_playing():
		menu_music_playback_pos = menu_music_player.get_playback_position()
		menu_music_player.stop()

func apply_settings():
	# Звук: Master bus
	var bus_idx = AudioServer.get_bus_index("Master")
	if bus_idx != -1:
		if master_volume <= 0.001:
			AudioServer.set_bus_mute(bus_idx, true)
		else:
			AudioServer.set_bus_mute(bus_idx, false)
			# linear_to_db: 1.0 -> 0dB, 0.5 -> -6dB
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(master_volume))
	
	# Полноэкранный режим
	# Вызываем с задержкой или напрямую, чтобы окно движка успело инициализироваться
	call_deferred("_apply_window_settings")

	settings_changed.emit()
	save_settings()

func _apply_window_settings():
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(window_resolution)
		# Центрируем окно на экране при смене разрешения в оконном режиме
		var screen_idx = DisplayServer.window_get_current_screen()
		var screen_rect = DisplayServer.screen_get_usable_rect(screen_idx)
		var win_pos = screen_rect.position + (screen_rect.size - window_resolution) / 2
		DisplayServer.window_set_position(win_pos)

	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	Engine.max_fps = max_fps

	settings_changed.emit()
	save_settings()

func save_settings():
	var cfg = ConfigFile.new()
	cfg.set_value("settings", "launch_count", launch_count)
	cfg.set_value("settings", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("settings", "master_volume", master_volume)
	cfg.set_value("settings", "fov", fov)
	cfg.set_value("settings", "vhs_enabled", vhs_enabled)
	cfg.set_value("settings", "fullscreen", fullscreen)
	cfg.set_value("settings", "res_x", window_resolution.x)
	cfg.set_value("settings", "res_y", window_resolution.y)
	cfg.set_value("settings", "vsync_enabled", vsync_enabled)
	cfg.set_value("settings", "max_fps", max_fps)
	cfg.set_value("settings", "chunk_render_distance", chunk_render_distance)
	cfg.set_value("settings", "graphics_backend", graphics_backend)
	
	for action in REBINDABLE_ACTIONS:
		if keybinds.has(action):
			cfg.set_value("keybinds", action, keybinds[action])

	cfg.save("user://settings.cfg")

func load_settings():
	# Инициализация дефолтных биндов
	keybinds = DEFAULT_KEYBINDS.duplicate()

	var cfg = ConfigFile.new()
	var err = cfg.load("user://settings.cfg")
	if err == OK:
		launch_count = cfg.get_value("settings", "launch_count", 0)
		mouse_sensitivity = cfg.get_value("settings", "mouse_sensitivity", 0.0025)
		master_volume = cfg.get_value("settings", "master_volume", 1.0)
		fov = cfg.get_value("settings", "fov", 70.0)
		vhs_enabled = cfg.get_value("settings", "vhs_enabled", true)
		fullscreen = cfg.get_value("settings", "fullscreen", true)
		var rx = cfg.get_value("settings", "res_x", 1920)
		var ry = cfg.get_value("settings", "res_y", 1080)
		window_resolution = Vector2i(rx, ry)
		vsync_enabled = cfg.get_value("settings", "vsync_enabled", true)
		max_fps = cfg.get_value("settings", "max_fps", 60)
		chunk_render_distance = cfg.get_value("settings", "chunk_render_distance", 5)
		graphics_backend = cfg.get_value("settings", "graphics_backend", "Vulkan")
		
		for action in REBINDABLE_ACTIONS:
			if cfg.has_section_key("keybinds", action):
				keybinds[action] = cfg.get_value("keybinds", action)

	apply_keybinds_to_input_map()
	apply_settings()

func apply_keybinds_to_input_map():
	for action in REBINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		
		# Очищаем только старые InputEventKey для этого действия, оставляя другие (если есть)
		var old_events = InputMap.action_get_events(action)
		for ev in old_events:
			if ev is InputEventKey:
				InputMap.action_erase_event(action, ev)

		var keycode: int = keybinds.get(action, DEFAULT_KEYBINDS.get(action, KEY_NONE))
		if keycode != KEY_NONE:
			var new_key = InputEventKey.new()
			new_key.physical_keycode = keycode as Key
			InputMap.action_add_event(action, new_key)

func set_keybind(action: String, keycode: int):
	keybinds[action] = keycode
	apply_keybinds_to_input_map()
	save_settings()
	settings_changed.emit()

func reset_keybinds_to_defaults():
	keybinds = DEFAULT_KEYBINDS.duplicate()
	apply_keybinds_to_input_map()
	save_settings()
	settings_changed.emit()

func get_action_key_name(action: String) -> String:
	var code: int = keybinds.get(action, DEFAULT_KEYBINDS.get(action, KEY_NONE))
	if code == KEY_NONE:
		return "None"
	return OS.get_keycode_string(code as Key)

# Перезапуск приложения с выбранным рендером (Forward+/Vulkan или Compatibility/OpenGL).
# Смена бэкенда невозможна на живом рендере, поэтому нужен новый процесс.
func restart_with_backend(backend: String):
	graphics_backend = backend
	graphics_backend_changed = true
	save_settings()
	print("Restarting with rendering backend: ", backend)

	var args := ["--path", ProjectSettings.globalize_path("res://")]
	if backend == "OpenGL":
		args.append("--rendering-method")
		args.append("gl_compatibility")
		args.append("--rendering-driver")
		args.append("opengl3")
	else:
		args.append("--rendering-method")
		args.append("forward_plus")
		args.append("--rendering-driver")
		args.append("vulkan")

	var exe := OS.get_executable_path()
	var pid := OS.create_process(exe, args)
	if pid == 0:
		push_error("Не удалось перезапустить игру с бэкендом " + backend)
		graphics_backend_changed = false
	else:
		# Новый процесс запущен — закрываем текущий
		get_tree().quit()
