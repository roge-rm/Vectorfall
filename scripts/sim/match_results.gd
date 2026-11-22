class_name MatchResults
extends RefCounted

enum Stat { KILLS, ASSISTS, GRABS, CAPTURES, RETURNS, STOPS, REPAIRS, ESCORTS }
const HEADINGS := ["Kills", "Assists", "Grabs", "Captures", "Returns", "Stops", "Repairs", "Escorts"]
const ASSIST_TICKS := 8 * 60
const ESCORT_RANGE := 35.0
const MAX_FORMER := 64

var counts := {}
var former: Array[Dictionary] = []
var hits := {}


func damage(game: Match, victim: Soldier, attacker: int, amount: float) -> void:
	if game.over or amount <= 0.0 or game.soldier(attacker) == null or attacker == victim.entity_id:
		return
	if not hits.has(victim.entity_id):
		hits[victim.entity_id] = {}
	hits[victim.entity_id][attacker] = game.tick


func kill(game: Match, victim: int, killer: int) -> void:
	if killer != victim:
		add(game, killer, Stat.KILLS)
	var enemy_team := 1 - game.soldier(victim).team
	if game.team_of(killer) == enemy_team:
		for id: int in hits.get(victim, {}):
			if id != killer and game.tick - hits[victim][id] <= ASSIST_TICKS:
				add(game, id, Stat.ASSISTS)
	hits.erase(victim)


func capture(game: Match, carrier: Soldier) -> void:
	add(game, carrier.entity_id, Stat.CAPTURES)
	for mate: Soldier in game.entities.values():
		if mate != carrier and mate.team == carrier.team and not mate.dead and mate.at().distance_to(carrier.at()) <= ESCORT_RANGE:
			add(game, mate.entity_id, Stat.ESCORTS)


func add(game: Match, id: int, stat: Stat) -> void:
	if game.over or game.soldier(id) == null:
		return
	if not counts.has(id):
		counts[id] = empty_row()
	counts[id][stat] += 1


static func empty_row() -> Array:
	var row := []
	row.resize(HEADINGS.size())
	row.fill(0)
	return row


func change_occupant(who: Soldier) -> void:
	var id := who.entity_id
	if counts.has(id):
		former.append({"name": who.display_name, "team": who.team, "counts": counts[id]})
		counts.erase(id)
		if former.size() > MAX_FORMER:
			former.pop_front()
	hits.erase(id)
	for attackers: Dictionary in hits.values():
		attackers.erase(id)


func get_state(include_hits: bool) -> Dictionary:
	return {"counts": counts.duplicate(true), "former": former.duplicate(true),
		"hits": hits.duplicate(true) if include_hits else {}}


func set_state(state: Dictionary) -> void:
	counts = state.get("counts", {}).duplicate(true)
	former.assign(state.get("former", []).duplicate(true))
	hits = state.get("hits", {}).duplicate(true)
