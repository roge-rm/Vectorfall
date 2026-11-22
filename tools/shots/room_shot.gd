extends Node

## Takes pictures of team 0's base on Ochre Fold and quits. It needs a
## screen:
##   DISPLAY=:0 ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/room_shot.tscn
## base-outside.png looks at the base from in front and above, with its
## turrets, sensor and force fields, turret.png is close to the turret by
## the flag, room-inside.png is from the front of the
## generator room towards the generator and an opening,
## hud-power-down.png is up on the deck just after the generator is
## destroyed, with the notice, and generator-destroyed.png is the room again
## a few seconds later. In
## /srv/downloads/temp/debug/skifrei/m10.

const FOLDER := "/srv/downloads/temp/debug/skifrei/m10"

var main: Node


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	GameMap.chosen = "ochre_fold"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var map: GameMap = main.map
	var game: Match = main.game
	var deck := map.deck_height()
	await _hold(map.base_place(0, 12.0, -12.0, deck + 13.0), PI * 0.5 + 0.62, -0.42, 60)
	await _save("base-outside.png")
	await _hold(map.base_place(0, 5.0, -9.0, deck + 1.0), 2.25, -0.12, 30)
	await _save("turret.png")
	await _hold(map.base_place(0, 0.0, 3.5, map.room_floor()), 0.85, -0.12, 40)
	await _save("room-inside.png")
	game.damage_asset(game.generator(0), 1000.0, 0, 1, Vector3.ZERO)
	await _hold(map.base_place(0, 9.0, 3.0, deck), PI * 0.5 + 0.25, -0.2, 20)
	await _save("hud-power-down.png")
	# After the notice has gone.
	await _hold(map.base_place(0, 0.0, 3.5, map.room_floor()), 0.85, 0.05, 240)
	await _save("generator-destroyed.png")
	get_tree().quit()


## Keeps the player still at a point looking along a yaw and pitch for n
## ticks.
func _hold(at: Vector3, yaw: float, pitch: float, n: int) -> void:
	main.input.source.yaw = yaw
	main.input.source.pitch = pitch
	for i in n:
		main.player.global_position = at
		main.player.velocity = Vector3.ZERO
		await get_tree().physics_frame
	for i in 10:
		await get_tree().process_frame


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(FOLDER)
	get_viewport().get_texture().get_image().save_png(FOLDER + "/" + file)
	print("Saved ", file)
