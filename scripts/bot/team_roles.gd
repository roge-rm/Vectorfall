class_name TeamRoles
extends RefCounted

## A simple fixed rule for each team's roles until the team commander takes
## over: one defence for every 6 or so, a quarter midfield and the rest offence,
## with people counted as offence first. Bots get roles in order of their id.


static func assign(game: Match, brains: Array[BotBrain]) -> void:
	for team in 2:
		var people := 0
		var team_brains: Array[BotBrain] = []
		var ids := game.entities.keys()
		ids.sort()
		for id: int in ids:
			var s := game.soldier(id)
			if s == null or s.team != team:
				continue
			var brain := game.sources.get(id) as BotBrain
			if brain != null and brains.has(brain):
				team_brains.append(brain)
			else:
				people += 1
		var size := team_brains.size() + people
		if size == 0:
			continue
		var defence := maxi(roundi(size * 0.15), 1) if size > 1 else 0
		var midfield := roundi(size * 0.25) if size > 2 else 0
		# People take offence places, so the bots fill the rest.
		var offence := maxi(size - defence - midfield - people, 0)
		var k := 0
		for brain in team_brains:
			if k < defence:
				brain.role = BotBrain.Role.DEFENCE
				brain.role_slot = k
			elif k < defence + midfield:
				brain.role = BotBrain.Role.MIDFIELD
				brain.role_slot = k - defence
			else:
				brain.role = BotBrain.Role.OFFENCE
				brain.role_slot = k - defence - midfield
			k += 1
		if offence == 0 and not team_brains.is_empty() and people == 0:
			team_brains[team_brains.size() - 1].role = BotBrain.Role.OFFENCE
