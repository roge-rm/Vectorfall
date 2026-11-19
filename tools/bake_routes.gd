extends SceneTree

## Builds Ochre Fold's route graph from scratch and saves its links to
## res://maps/ochre_fold.routes. Run it with tools/bake-routes.sh.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OchreFold.use_baked_routes = false
	var map := OchreFold.new()
	var ok := RouteBake.save(OchreFold.ROUTES_FILE, map.route_key, map.route_graph, map.route_first_link, map.route_end_link)
	print("baked %d links to %s: %s" % [map.route_end_link - map.route_first_link, OchreFold.ROUTES_FILE, "ok" if ok else "FAILED"])
	map.free()
	quit(0 if ok else 1)
