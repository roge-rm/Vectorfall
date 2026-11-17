extends Node

## Takes pictures of the enemy flag on its stand from across the test map, with
## the HUD, and quits. It needs a screen:
##   DISPLAY=:0 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/flag_shot.tscn
## flag.png is from your own base, flag-near.png from the middle ridge near the enemy base, and
## flag-dropped.png with the flag dropped and carried. In /srv/downloads/temp/debug/Vectorfall.

const FOLDER := "/srv/downloads/temp/debug/Vectorfall"


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var map: TestMap = main.map
	main.dummy.fire_enabled = false
	var deck := TestMap.BASE_HEIGHT + 2.0
	main.input.source.yaw = -PI * 0.5
	main.input.source.pitch = 0.02
	main.player.global_position = Vector3(map.base_x(0) + 8.0, deck + 0.3, 0.0)
	await _ticks(60)
	await _save("flag.png")
	var x := 67.0
	main.player.global_position = Vector3(x, map.height_at(x, 0.0) + 0.5, 0.0)
	await _ticks(40)
	await _save("flag-near.png")
	# The enemy takes our flag and drops it mid map.
	var game: Match = main.game
	main.enemy.global_position = game.flags[0].global_position
	await _ticks(3)
	main.enemy.global_position = Vector3(20.0, map.height_at(20.0, 0.0) + 30.0, 10.0)
	main.enemy.velocity = Vector3(10.0, 0.0, 0.0)
	await _ticks(2)
	game.damage(main.enemy, 1000.0, main.player.entity_id, Weapon.DISC, Vector3.ZERO)
	main.player.global_position = Vector3(-67.0, map.height_at(-67.0, 0.0) + 0.5, 0.0)
	main.input.source.yaw = -PI * 0.5 - 0.3
	await _ticks(90)
	await _save("flag-dropped.png")
	get_tree().quit()


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
	for i in 10:
		await get_tree().process_frame


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(FOLDER)
	get_viewport().get_texture().get_image().save_png(FOLDER + "/" + file)
	print("Saved ", file)
