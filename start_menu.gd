extends Control

@onready var menu_container = $MenuContainer
@onready var play_btn = $MenuContainer/CenterContainer/VBoxContainer/PlayButton
@onready var settings_btn = $MenuContainer/CenterContainer/VBoxContainer/SettingsButton
@onready var quit_btn = $MenuContainer/CenterContainer/VBoxContainer/QuitButton
@onready var video_player = $VideoPlayer
@onready var splash_player = $SplashPlayer
@onready var black_cover = $BlackCover
@onready var cutscene_cover = $CutsceneCover

var settings_dialog_scene = preload("res://settings_dialog.tscn")
var active_settings_dialog: Control = null
var splash_done: bool = false

signal start_cutscene_video
signal video_finished

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	play_btn.pressed.connect(_on_play_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	video_player.finished.connect(_on_video_finished)
	splash_player.finished.connect(_on_splash_finished)
	
	# Сразу гарантируем, что черный экран полностью непрозрачен и надежно перекрывает весь мир
	black_cover.visible = true
	black_cover.modulate.a = 1.0
	menu_container.modulate.a = 0.0
	menu_container.visible = false

	# Если заставка разработчика уже была показана ранее (при первом запуске игры),
	# сразу переходим в главное меню без повторного видео разработчика
	var gs = preload("res://game_settings.gd").instance
	if gs and gs.splash_already_shown:
		splash_done = true
		menu_container.visible = true
		menu_container.modulate.a = 1.0
		gs.play_menu_music(1.0) # В главном меню музыка играет на 100% громкости
	else:
		if gs:
			gs.splash_already_shown = true
			gs.launch_count += 1
			gs.save_settings()
		play_developer_splash()

func play_developer_splash():
	splash_player.visible = true
	splash_player.play()

func _input(event: InputEvent):
	# Пропуск заставки разработчика кликом ЛКМ, пробелом или Enter (разрешен ТОЛЬКО после 5 запусков игры!)
	if not splash_done and splash_player.is_playing():
		var gs = preload("res://game_settings.gd").instance
		var can_skip = gs != null and gs.launch_count > 5
		if can_skip:
			if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
				_on_splash_finished()
				get_viewport().set_input_as_handled()

func _on_splash_finished():
	if splash_done:
		return
	splash_done = true
	splash_player.stop()
	splash_player.visible = false
	
	# Плавное появление меню из абсолютной темноты после заставки
	menu_container.visible = true
	var tween = create_tween()
	tween.tween_property(menu_container, "modulate:a", 1.0, 1.2)

	# Запуск музыки Warm Nights в главном меню на 100% громкости
	var gs = preload("res://game_settings.gd").instance
	if gs:
		gs.play_menu_music(1.0)

func _on_settings_pressed():
	if active_settings_dialog and is_instance_valid(active_settings_dialog):
		return
	active_settings_dialog = settings_dialog_scene.instantiate()
	add_child(active_settings_dialog)
	active_settings_dialog.back_pressed.connect(_on_settings_closed)

func _on_settings_closed():
	if active_settings_dialog and is_instance_valid(active_settings_dialog):
		active_settings_dialog.queue_free()
		active_settings_dialog = null

func _on_quit_pressed():
	get_tree().quit()

func _on_play_pressed():
	play_btn.disabled = true
	# Скрываем курсор сразу при нажатии Play, чтобы он не висел поверх видео и катсцены подъема
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	start_cutscene_video.emit()

	# Останавливаем музыку с запоминанием позиции при старте игры
	var gs = preload("res://game_settings.gd").instance
	if gs:
		gs.pause_menu_music()
	
	# Плавно скрываем элементы меню, оставляя сплошной черный фон
	var tween = create_tween()
	tween.tween_property(menu_container, "modulate:a", 0.0, 0.4)
	await tween.finished
	menu_container.visible = false
	
	# Запускаем вступительное видео падения
	video_player.visible = true
	video_player.play()

func _on_video_finished():
	# После завершения видео накрываем экран черным цветом и передаем управление катсцене подъема
	cutscene_cover.visible = true
	cutscene_cover.modulate.a = 1.0
	video_player.stop()
	video_player.visible = false
	
	# Мгновенно удаляем меню, чтобы черные шторы UI не перебивали шейдерное затемнение
	video_finished.emit()
	queue_free()
