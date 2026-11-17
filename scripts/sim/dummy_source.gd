class_name DummySource
extends CommandSource

## A stand-in enemy until the real bots: it walks back to its post when it's
## away from it, strafes from side to side there, faces a target and fires a
## disc at its feet every few seconds with a rough aim. Its timing comes from
## the match tick and its aim error from the match's random numbers, so a
## seeded match plays out the same.

var game: Match
var soldier: Soldier
var target: Soldier
## Where it stands and strafes.
var post := Vector3.ZERO
var fire_enabled := true
## Ticks between shots, and the first tick it may fire on.
var fire_every := 200
var first_shot_tick := 240
## Ticks spent strafing each way.
var strafe_ticks := 80
## Largest aim error in radians.
var aim_error := 0.07


func make_command(_delta: float) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = yaw
	command.pitch = pitch
	if game == null or soldier == null or soldier.dead:
		return command
	var tick := game.tick
	var to_post := post - soldier.global_position
	to_post.y = 0.0
	if to_post.length() > 15.0:
		# Head back, hopping and jetting over anything in the way.
		yaw = atan2(-to_post.x, -to_post.z)
		pitch = 0.0
		command.move = Vector2(0.0, 1.0)
		if soldier.grounded and tick % 90 == 0:
			command.buttons |= PlayerCommand.JUMP
		if soldier.energy > 60.0 and post.y > soldier.global_position.y + 3.0:
			command.buttons |= PlayerCommand.JET
	else:
		command.move = Vector2(1.0 if (tick / strafe_ticks) % 2 == 0 else -1.0, 0.0)
		if target != null and not target.dead:
			_aim_at(target)
			var due := tick >= first_shot_tick and (tick - first_shot_tick) % fire_every == 0
			var near := soldier.global_position.distance_to(target.global_position) < 150.0
			if fire_enabled and due and near:
				command.buttons |= PlayerCommand.FIRE
				yaw += game.rng.randf_range(-aim_error, aim_error)
				pitch += game.rng.randf_range(-aim_error, aim_error)
	command.yaw = yaw
	command.pitch = pitch
	command.weapon = Weapon.DISC
	return command


## Looks at the target's feet, half led for the disc's flight time.
func _aim_at(other: Soldier) -> void:
	var eye := soldier.eye_transform().origin
	var flight := eye.distance_to(other.global_position) / Weapon.all[Weapon.DISC].speed
	var point := other.global_position + other.velocity * flight * 0.5
	var to := point - eye
	yaw = atan2(-to.x, -to.z)
	pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -Soldier.PITCH_LIMIT, Soldier.PITCH_LIMIT)
