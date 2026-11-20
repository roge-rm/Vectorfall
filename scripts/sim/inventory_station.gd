class_name InventoryStation
extends Node3D

## An inventory station: a round pad in a team's base. A living soldier of
## that team stepping onto it gets its wanted loadout (Soldier.next_loadout)
## at once, with full ammo, hand grenades and mines and health and energy kept
## as shares. Stepping on again only restocks after COOLDOWN seconds, so
## standing about on it doesn't loop, but a new wanted loadout sent while on
## the pad goes on straight away. The match steps it once per physics tick,
## and its look is made in _ready(). It has no collision.

## Pad radius, and how far above and below the pad's top feet still count,
## in metres.
const PAD_RADIUS := 1.3
const REACH_UP := 1.0
const REACH_DOWN := 0.4
## Height of the pad's top above the station's position.
const PAD_TOP := 0.2
## Seconds after a station restocks a soldier before stepping on again does.
const COOLDOWN := 4.0

var entity_id := 0
var team := 0
var asset_id := 0
## Soldiers on the pad after the last tick, by id, lowest first.
var on: Array[int] = []
## Soldier id to seconds until stepping on restocks it again.
var cooldowns: Dictionary[int, float] = {}


## Whether the look shows it powered, for the look only.
var _shown_powered := true


func _ready() -> void:
	name = "Station%d" % entity_id
	StationLook.build(self, team)


## Its look goes dark while its team has no power.
func _process(_delta: float) -> void:
	var game := get_parent() as Match
	var powered := game == null or game.station_working(self)
	if powered != _shown_powered:
		_shown_powered = powered
		StationLook.set_powered(self, team, powered)


## True if a soldier counts as on the pad: alive, on this team and with its
## feet over the pad.
func holds(who: Soldier) -> bool:
	if who.dead or who.team != team:
		return false
	var d := who.at() - global_position
	var up := d.y - PAD_TOP
	return Vector2(d.x, d.z).length() <= PAD_RADIUS and up >= -REACH_DOWN and up <= REACH_UP


func get_state() -> Dictionary:
	return {
		"kind": "station",
		"id": entity_id,
		"team": team,
		"asset_id": asset_id,
		"position": position,
		"on": on.duplicate(),
		"cooldowns": cooldowns.duplicate(),
	}


func set_state(state: Dictionary) -> void:
	entity_id = state.id
	team = state.team
	asset_id = state.get("asset_id", 0)
	position = state.position
	on.assign(state.get("on", []))
	cooldowns.assign(state.get("cooldowns", {}))
