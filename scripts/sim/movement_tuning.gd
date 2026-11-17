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

## How far down the ground is looked for each tick to keep you on it.
@export var floor_snap := 0.35

@export_group("Skiing")
## Slowing on the ground while skiing, in m/s².
@export var ski_friction := 0.4
## Steering while skiing, towards where you push.
@export var ski_steer_accel := 6.0
## Pushing only adds speed in a direction while you're slower than this in it.
@export var ski_steer_speed := 8.0
## Above this speed the ground is barely held on to, so a crest throws you
## into the air.
@export var ski_launch_speed := 12.0
## Floor snap while skiing above ski_launch_speed. Each tick at 60 m/s covers
## 1 m, so this keeps you on a slope that bends by about 3° per metre.
@export var ski_snap := 0.05
## How hard you're pressed into the slope while skiing, in m/s, so the floor
## stays in touch on a straight slope without snapping.
@export var ski_press := 0.5

@export_group("Drag")
## Speed with no drag. Above it drag is drag * (speed - drag_free_speed)²,
## which tops out at about 59 m/s on a 30° slope and 73 m/s falling or
## skiing downhill with the jet.
@export var drag_free_speed := 25.0
@export var drag := 0.009
## Hard limit on speed, in case something adds more than drag can take off.
@export var max_speed := 80.0

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
## Forward thrust while jetting when skiing or faster than jet_side_speed,
## along where you steer, or where you look if you don't.
@export var jet_forward_accel := 10.0
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
