extends SceneTree

## Exercises the HUD and shield shell from match events.

const STAND_0 := Vector3(-100, 0, 0)
const STAND_1 := Vector3(100, 0, 0)

var checks := TestWorld.Checks.new()
var game: Match
var a: Soldier
var b: Soldier
var hud: Hud


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TestWorld.flat_ground(root)
	game = Match.new(1)
	game.running = false
	game.add_flag(0, STAND_0, STAND_0 + Vector3.UP * 2.0)
	game.add_flag(1, STAND_1, STAND_1 + Vector3.UP * 2.0)
	root.add_child(game)
	a = game.add_soldier(0, Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 20)))
	b = game.add_soldier(1, Transform3D(Basis.IDENTITY, Vector3(0, 10, 0)))
	hud = Hud.new()
	hud.soldier = a
	root.add_child(hud)
	hud.watch(game)
	var effects := Effects.new()
	root.add_child(effects)
	effects.watch(game)
	await physics_frame
	_check_shield()
	_check_air_hit()
	_check_carrier()
	_check_impact_feed()
	_check_marker_clearance()
	_check_impact_feedback()
	checks.finish(self)


func _check_shield() -> void:
	a.set_loadout(Loadout.make(SoldierBody.Armour.MEDIUM, [Weapon.DISC, Weapon.CHAINGUN], Pack.SHIELD))
	a.switch_pack(true)
	var before := a.body.shell.material_override as ShaderMaterial
	game.damage(a, 10.0, b.entity_id, Weapon.DISC, b.global_position)
	var flashed := a.body.shell.material_override as ShaderMaterial
	checks.check(flashed != before and flashed.get_shader_parameter("flash") > 0.0 and hud._shield_flash_left > 0.0 and hud._flash == 0.0,
		"an absorbed shot flashes the struck shell and local shield cue without a health flash")
	a.energy = 2.0
	game.damage(a, 10.0, b.entity_id, Weapon.DISC, b.global_position)
	a.body._process(0.01)
	checks.check(not a.shielded() and a.body.shell.visible and hud._flash > 0.0, "a broken shield still shows its final impact and the health hit")
	a.body._process(1.0)
	checks.check(not a.body.shell.visible and a.body.shell.material_override == before, "the shield flash ends and restores its idle material")


func _check_air_hit() -> void:
	var shot := Projectile.new()
	shot.weapon = Weapon.DISC
	shot.shooter = a.entity_id
	shot.team = a.team
	shot.damage = Weapon.all[Weapon.DISC].damage
	shot.velocity = Vector3.FORWARD * Weapon.all[Weapon.DISC].speed
	b.grounded = true
	game._impact(shot, b.centre() - Vector3.UP, Vector3.UP, b)
	checks.check(not b.grounded and hud._air_hit_left == 0.0, "a direct hit that launches a grounded target does not count as an air hit")
	b.health = b.tuning.health_max
	game.explode(b.centre() + Vector3.RIGHT * 2.0, Weapon.DISC, a.entity_id)
	checks.check(b.health < b.tuning.health_max and hud._air_hit_left == 0.0, "splash damage on an airborne target is not a direct air hit")
	b.health = b.tuning.health_max
	game._impact(shot, b.centre() + Vector3.BACK * 0.2, Vector3.BACK, b)
	checks.check(hud._air_hit_left > 0.0, "a direct disc hit on an airborne enemy shows the air hit cue")


func _check_carrier() -> void:
	var ours: Flag = game.flags[0]
	var theirs: Flag = game.flags[1]
	var stops: Array[Vector2i] = []
	game.carrier_stopped.connect(func(victim: int, killer: int) -> void: stops.append(Vector2i(victim, killer)))
	game._take_flag(ours, b)
	game.damage(b, 1000.0, a.entity_id, Weapon.DISC, a.global_position)
	checks.check(ours.mode == Flag.Mode.DROPPED and stops == [Vector2i(b.entity_id, a.entity_id)] and hud.notice() == "You stopped the carrier",
		"killing the enemy carrier drops the flag and draws the stop notice")
	game.respawn(b)
	game._take_flag(ours, b)
	game._take_flag(theirs, a)
	a.position = STAND_0
	game._step_flags(1.0 / 60.0)
	checks.check(game.scores[0] == 0 and hud.notice() == "Return your flag to score", "a carrier at home sees why it cannot score")
	game._return_flag(ours, 0)
	game._step_flags(1.0 / 60.0)
	checks.check(game.scores[0] == 1 and hud.notice() == "%s team captured the flag" % Soldier.TEAM_NAMES[0], "returning the flag clears the waiting cue and allows the capture")
	game._take_flag(ours, b)
	game.damage(b, 1000.0, b.entity_id, Weapon.DISC, b.global_position)
	checks.check(ours.mode == Flag.Mode.DROPPED and stops.size() == 1, "a carrier who dies to their own shot only drops the flag")


func _check_marker_clearance() -> void:
	hud._top_edge = 90.0
	var notice_area := Rect2(480, 210, 320, 40)
	var respawn_area := Rect2(500, 265, 280, 45)
	hud._marker_banners = [notice_area, respawn_area]
	var radius := 14.0
	var above_compass := Vector2(640, 82)
	var above_notice := Vector2(640, 202)
	var clear := Vector2(120, 220)
	checks.check(hud._below_hud(above_compass, radius) == Vector2(640, 104),
		"the whole marker is kept below the scoreboard and compass")
	checks.check(hud._below_hud(above_notice, radius) == Vector2(640, 324),
		"the whole marker clears both active banners")
	checks.check(hud._below_hud(clear, radius) == clear, "a clear marker stays where it was projected")


func _check_impact_feed() -> void:
	game.respawn(b)
	game.damage(b, 1000.0, a.entity_id, Weapon.VEHICLE_IMPACT, a.global_position)
	checks.check(hud.feed_text().back() == "You vehicle impact " + b.display_name, "vehicle impact credits the driver in the feed")
	game.respawn(b)
	game.damage(b, 1000.0, 0, Weapon.FALL_IMPACT, b.global_position)
	checks.check(hud.feed_text().back() == b.display_name + " fell", "a fatal fall appears in the feed")


func _check_impact_feedback() -> void:
	var camera := FirstPersonCamera.new()
	camera.soldier = a
	root.add_child(camera)
	var audio := GameAudio.new()
	root.add_child(audio)
	audio.watch(game, a)
	game.landed.emit(a.entity_id, Soldier.FALL_SAFE_SPEED)
	checks.check(audio._next_flat == 0, "an ordinary landing does not play the hard landing sound")
	game.landed.emit(a.entity_id, Soldier.FALL_SAFE_SPEED + 1.0)
	checks.check(audio._flat[0].stream == SoundBank.get_stream("hard_land"), "a hard landing plays its own thud")

	game.vehicle_crashed.emit(b.entity_id, b.position, 20.0)
	checks.check(camera.v_offset == 0.0 and hud._hull_damage_left == 0.0, "another driver's crash does not jolt the camera or show hull loss")
	var pad := game.fleet.add_pad(0, Vehicle.Kind.BIKE, Vector3(0.0, 0.0, 40.0), 0.0)
	var hull := game.fleet._make_hull(game.next_id, pad, pad.position + Vector3.UP)
	hull.crew[0] = a.entity_id
	a.mount(hull.entity_id, 0)
	hull.health = 12.5
	game.fleet.damage(hull, 80.0, 0, -1, Weapon.VEHICLE_IMPACT)
	checks.check(camera.v_offset < 0.0 and hud._hull_damage == 12.5 and hud._hull_damage_left > 0.0
		and audio._flat[1].stream == SoundBank.get_stream("vehicle_crash"),
		"a wreck jolts its driver and reports the actual hull health lost with the crash sound")
	camera._process(0.4)
	hud._process(2.0)
	checks.check(camera.v_offset == 0.0 and hud._hull_damage_left == 0.0, "the crash jolt and damage readout fade")
