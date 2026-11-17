class_name MovementTuning
extends Resource

## Every number that sets how a soldier moves, in metres, seconds and radians.
## One of these per armour later on.

@export_group("Running")
## Top speed from running on flat ground.
@export var run_speed := 8.0
@export var ground_accel := 60.0
## How fast you slow down with no input, below run speed.
@export var ground_friction := 40.0
## How fast speed above run speed fades on the ground, so a fast landing
## carries on for a while.
@export var overspeed_decay := 2.5
@export var jump_speed := 6.5
@export var gravity := 20.0

@export_group("Air")
## Speed you can add in the air towards where you're steering, on top of the
## momentum you already have.
@export var air_control_speed := 3.0
@export var air_accel := 6.0

@export_group("Jetpack")
## Upward thrust, so 30 against gravity's 20 climbs at a net 10 m/s².
@export var jet_up_accel := 30.0
## Sideways thrust while jetting, towards where you're steering.
@export var jet_side_accel := 8.0
## Horizontal speed the side thrust can push you to.
@export var jet_side_speed := 14.0
## Fastest upward speed the jet will push you to.
@export var jet_max_rise := 12.0
@export var energy_max := 100.0
## Energy per second while jetting, so a full tank lasts 2.5 s.
@export var energy_drain := 40.0
## Energy per second once refilling starts.
@export var energy_refill := 25.0
## Seconds after letting go of the jet before energy starts to refill.
@export var refill_delay := 0.8

@export_group("Body")
@export var height := 1.8
@export var radius := 0.4
@export var eye_height := 1.6
