extends SceneTree

## Checks what bots see and hear on the test map: an enemy in the open in
## front is seen once the reaction time has passed, one behind a hill isn't,
## one behind the bot is heard when it fires, and a seen enemy is remembered
## for a while once it's out of sight and then forgotten. The ray cast budget
## is shared by every bot each tick.
##   tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --fixed-fps 60 --path . -s tests/perception_test.gd

var checks := TestWorld.Checks.new()
var map: TestMap
var game: Match
var director: BotDirector


func _initialize() -> void:
	map = TestMap.new()
	root.add_child(map)
	game = Match.new(4)
	root.add_child(game)
	director = BotDirector.new(game, map.route_graph)
	_run.call_deferred()


func _on_ground(x: float, z: float) -> Transform3D:
	# Facing +x, towards team 1's base.
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x, map.height_at(x, z) + 0.3, z))


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	# The bot stands in the first valley looking along the map. The next ridge
	# is at x = -67, and the valley past it at x = 0.
	var me := game.add_soldier(0, _on_ground(-133.0, 0.0))
	var open := game.add_soldier(1, _on_ground(-105.0, 4.0))
	var hidden := game.add_soldier(1, _on_ground(0.0, 0.0))
	var behind := game.add_soldier(1, _on_ground(-165.0, -5.0))
	var eyes := BotPerception.new()
	eyes.reaction_time = 0.3
	await ticks(10)
	eyes.update(me, game, director)
	checks.check(not eyes.knows(open.entity_id) and eyes.contacts.has(open.entity_id), "an enemy in the open is in view but not noticed straight away")
	await ticks(20)
	eyes.update(me, game, director)
	checks.check(eyes.can_see(open.entity_id), "and seen after the reaction time")
	checks.check(not eyes.knows(hidden.entity_id), "an enemy behind the hill isn't seen")
	checks.check(not eyes.knows(behind.entity_id), "nor one behind the bot")
	game.fire(behind)
	await ticks(1)
	eyes.update(me, game, director)
	checks.check(eyes.knows(behind.entity_id) and not eyes.can_see(behind.entity_id), "the one behind is heard when it fires")
	checks.check(eyes.guess_position(behind.entity_id, game.tick).distance_to(behind.global_position) < 3.0, "and placed where it fired from")

	# Out of sight, the seen one is remembered, fading, then forgotten.
	open.global_position = _on_ground(0.0, 20.0).origin
	await ticks(2)
	eyes.update(me, game, director)
	var faded := eyes.confidence(open.entity_id, game.tick + 300)
	checks.check(eyes.knows(open.entity_id) and not eyes.can_see(open.entity_id), "an enemy gone behind the hill is remembered")
	checks.check(faded > 0.0 and faded < 1.0, "and fades (%.2f after 5 s)" % faded)
	await ticks(int(BotPerception.SEEN_MEMORY * 60.0) + 10)
	eyes.update(me, game, director)
	checks.check(not eyes.knows(open.entity_id), "and is forgotten after %.0f s" % BotPerception.SEEN_MEMORY)

	# The ray budget runs out part way and the rest are checked next time.
	for k in BotDirector.RAYS_PER_TICK + 4:
		game.add_soldier(1, _on_ground(-110.0, -20.0 + k * 3.0))
	await ticks(2)
	var crowd := BotPerception.new()
	crowd.update(me, game, director)
	var looked := crowd.contacts.size()
	await ticks(1)
	crowd.update(me, game, director)
	checks.check(looked <= BotDirector.RAYS_PER_TICK, "one tick's ray budget checks %d enemies" % looked)
	checks.check(crowd.contacts.size() > looked, "and the rest are checked on the next look (%d)" % crowd.contacts.size())
	checks.finish(self)
