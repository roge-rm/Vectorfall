class_name StationLook
extends RefCounted

## The look of an inventory station, in two draw calls: one merged ink mesh
## (a bevelled round plinth with a team coloured top, dark trim blocks round
## its rim and a team coloured diamond floating over it) and a glowing ring
## round the pad's top. Its origin is the bottom of the plinth. Without power
## its team colour darkens and the ring goes out.

const PLINTH := Color(0.86, 0.84, 0.94, 0.0)
const TRIM := Color(0.15, 0.14, 0.18, 0.0)
const TEAM_PART := Color(1.0, 1.0, 1.0, 1.0)
const PAD_FACE := Color(0.71, 0.70, 0.78, 0.56)
## Height of the diamond's middle over the pad.
const MARKER_HEIGHT := 2.4
const RING_OFF := Color(0.2, 0.19, 0.23)


static func build(parent: Node3D, team: int) -> void:
	var colour := Palette.team(team)
	var r := InventoryStation.PAD_RADIUS
	var top := InventoryStation.PAD_TOP
	var parts := []
	# The plinth, a little wider than the pad so the whole pad reads as one.
	parts.append([Cel.bevel_cylinder(r + 0.2, top - 0.04, 0.04, 12), Transform3D(Basis.IDENTITY, Vector3.UP * (top - 0.04) * 0.5), PLINTH])
	parts.append([Cel.bevel_cylinder(r - 0.15, 0.06, 0.015, 12), Transform3D(Basis.IDENTITY, Vector3.UP * (top - 0.03)), PAD_FACE])
	# Six trim blocks round the rim, like the stand's ring but solid.
	for k in 6:
		var angle := TAU * k / 6.0
		var at := Vector3(sin(angle), 0.0, cos(angle)) * (r + 0.05)
		parts.append([Cel.bevel_box(Vector3(0.45, top + 0.03, 0.19), 0.04), Transform3D(Basis(Vector3.UP, angle), at + Vector3.UP * (top + 0.03) * 0.5), TRIM if k % 2 else TEAM_PART])
	# A four sided diamond over the pad, point down, with a dark band round
	# its middle.
	var marker := Vector3.UP * (top + MARKER_HEIGHT)
	parts.append([Cel.cylinder(0.32, 0.0, 0.5, 4), Transform3D(Basis.IDENTITY, marker - Vector3.UP * 0.25), TEAM_PART])
	parts.append([Cel.cylinder(0.0, 0.32, 0.3, 4), Transform3D(Basis.IDENTITY, marker + Vector3.UP * 0.15), TEAM_PART])
	parts.append([Cel.cylinder(0.34, 0.34, 0.06, 4), Transform3D(Basis.IDENTITY, marker), TRIM])
	var view := MeshInstance3D.new()
	view.name = "Look"
	view.mesh = Cel.merged(parts)
	view.material_override = Cel.material(Color.WHITE, 1.0, true, true, false, true)
	parent.add_child(view)
	Cel.set_team(view, colour)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var torus := TorusMesh.new()
	torus.inner_radius = r - 0.12
	torus.outer_radius = r
	torus.rings = 24
	torus.ring_segments = 4
	ring.mesh = torus
	ring.material_override = Cel.glow(colour.lightened(0.3))
	ring.scale = Vector3(1.0, 0.25, 1.0)
	ring.position = Vector3.UP * (top + 0.01)
	parent.add_child(ring)


## Shows a station's look powered or not.
static func set_powered(parent: Node3D, team: int, powered: bool) -> void:
	var colour := Palette.team(team)
	var look := parent.get_node_or_null("Look") as MeshInstance3D
	if look != null:
		Cel.set_team(look, colour if powered else colour.darkened(0.6))
	var ring := parent.get_node_or_null("Ring") as MeshInstance3D
	if ring != null:
		ring.material_override = Cel.glow(colour.lightened(0.3)) if powered else Cel.material(RING_OFF)
