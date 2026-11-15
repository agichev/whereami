extends Control

@onready var resume_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/ResumeButton
@onready var settings_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/SettingsButton
@onready var menu_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/MenuButton
@onready var quit_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/QuitButton

var settings_dialog_scene = preload("res://settings_dialog.tscn")
var active_settings_dialog: Control = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	resume_btn.pressed.connect(_on_resume_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	menu_btn.pressed.connect(_on_menu_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

	# Запуск музыки Warm Nights на громкости 10% (0.10) с того места, где она остановилась
	var gs = preload("res://game_settings.gd").instance
	if gs:
		gs.play_menu_music(0.10)

func _input(event: InputEvent):
	if event.is_action_pressed("pause"):
		if active_settings_dialog and is_instance_valid(active_settings_dialog):
			close_settings()
			get_viewport().set_input_as_handled()
		else:
			resume_game()
			get_viewport().set_input_as_handled()

func resume_game():
	# При снятии с паузы останавливаем музыку и запоминаем позицию
	var gs = preload("res://game_settings.gd").instance
	if gs:
		gs.pause_menu_music()

	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()

func _on_resume_pressed():
	resume_game()

func _on_settings_pressed():
	if active_settings_dialog and is_instance_valid(active_settings_dialog):
		return
	active_settings_dialog = settings_dialog_scene.instantiate()
	add_child(active_settings_dialog)
	active_settings_dialog.back_pressed.connect(close_settings)

func close_settings():
	if active_settings_dialog and is_instance_valid(active_settings_dialog):
		active_settings_dialog.queue_free()
		active_settings_dialog = null

func _on_menu_pressed():
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()

func _on_quit_pressed():
	get_tree().quit()
