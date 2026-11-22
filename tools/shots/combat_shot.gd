extends Node

## Takes two pictures on the player's base deck and quits. It needs a screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/combat_shot.tscn
## soldier.png: the enemy close up, jetting, with a disc blast beside it.
## soldier-run.png: the enemy running past, and a disc in flight.
## Both go in /srv/downloads/temp/debug/skifrei.

const FOLDER := "/srv/downloads/temp/debug/skifrei"


## Drives the enemy for the pictures.
class Pose:
	extends CommandSource
	var buttons := 0
	var move := Vector2.ZERO

	func make_command(_delta: float) -> PlayerCommand:
		var command := PlayerCommand.new()
		command.yaw = yaw
		command.pitch = pitch
		command.buttons = buttons
		command.move = move
		return command


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	# These pictures are of the test map.
	GameMap.chosen = "test"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var enemy: Soldier = main.enemy
	var pose := Pose.new()
	main.game.sources[enemy.entity_id] = pose
	var deck := TestMap.BASE_HEIGHT + 2.0
	var x: float = main.player.global_position.x
	var z: float = main.player.global_position.z
	enemy.global_position = Vector3(x + 4.5, deck, z + 1.2)
	pose.yaw = PI * 0.5 + 0.7
	pose.pitch = 0.1
	main.input.source.pitch = 0.05
	await _ticks(60)
	pose.buttons = PlayerCommand.JET
	await _ticks(22)
	main.effects.blast(Vector3(x + 13.0, deck + 0.05, z - 4.0), Vector3.UP, Weapon.all[Weapon.DISC].splash_radius)
	await _ticks(6)
	await _save("soldier.png")

	# Running across the view, with the player firing a disc past it.
	pose.buttons = 0
	await _ticks(60)
	enemy.global_position = Vector3(x + 7.0, deck, z + 3.0)
	pose.yaw = 0.0
	pose.pitch = 0.0
	pose.move = Vector2(0.0, 1.0)
	main.input.source.yaw = -PI * 0.5 + 0.08
	main.input.source.pitch = -0.02
	await _ticks(40)
	Input.action_press("fire")
	await _ticks(2)
	Input.action_release("fire")
	await _ticks(6)
	await _save("soldier-run.png")
	get_tree().quit()


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(FOLDER)
	get_viewport().get_texture().get_image().save_png(FOLDER + "/" + file)
	print("Saved ", FOLDER + "/" + file)
