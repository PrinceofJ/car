extends Node

@export var PlayButton: Button = null
@export var QuitButton: Button = null


func _ready() -> void:
	PlayButton.pressed.connect(PlayButtonPressed)
	QuitButton.pressed.connect(QuitButtonPressed)

func PlayButtonPressed() -> void:
	get_tree().change_scene_to_file("res://scenes/GameScene.tscn")
	
func QuitButtonPressed() -> void:
	get_tree().quit()
