class_name ModernTheatre
extends Theatre
## Afghanistan and Iraq, 2004-2010: the Coalition (team 0, from the west) against insurgents (team 1) in the
## compounds and fields of Helmand or the streets of an Iraqi town. Lopsided like Vietnam: a few Coalition
## soldiers in body armour with air support on the radio and an MRAP, against many lightly armed insurgents
## with RPGs, machine guns and IEDs they can set off from cover. The Coalition scores for ground, the
## insurgents for every Coalition soldier they kill.

const M4_RANGE := [0, 14, 12, 10, 8, 7, 5, 3, 1, 0, -2, -5, -8, -12, -16, -20]
const AK_RANGE := [0, 25, 20, 15, 10, 6, 3, 0, -4, -8, -12, -18, -24]
const MG_RANGE := [0, 0, 5, 5, 5, 5, 5, 5, 5, 5, 0, 0, -5, -5, -10, -10, -15]
const SNIPER_RANGE := [0, -20, -15, -10, -5, 0, 5, 8, 10, 12, 14, 15, 15, 15, 15, 15, 12, 10]

const WEAPONS := {
	"m4": {"name": "M4", "kind": "rifle", "damage": [3, 5], "crit": 12, "crit_damage": 2, "clip": 10, "suppression": 22, "range": M4_RANGE},
	## A light machine gun: no setting up.
	"m249": {"name": "M249 SAW", "kind": "mg", "damage": [4, 5], "crit": 5, "crit_damage": 2, "clip": 8, "suppression": 40, "range": MG_RANGE},
	"m110": {"name": "M110", "kind": "sniper", "damage": [5, 7], "crit": 25, "crit_damage": 3, "clip": 6, "suppression": 12, "range": SNIPER_RANGE},
	"m2": {"name": "M2 .50 cal", "kind": "mg", "damage": [4, 6], "crit": 10, "crit_damage": 2, "clip": 10, "suppression": 55, "range": MG_RANGE},
	"ak47": {"name": "AK-47", "kind": "assault", "damage": [3, 5], "crit": 10, "crit_damage": 2, "clip": 8, "suppression": 25, "range": AK_RANGE},
	"pkm": {"name": "PKM", "kind": "mg", "damage": [4, 6], "crit": 5, "crit_damage": 2, "clip": 6, "suppression": 40, "range": MG_RANGE},
	"svd": {"name": "SVD Dragunov", "kind": "sniper", "damage": [5, 7], "crit": 20, "crit_damage": 3, "clip": 5, "suppression": 10, "range": SNIPER_RANGE},
	## The RPG-7's warhead bursts on the target: deadly to the MRAP's sides, and it tears cover apart.
	"rpg7": {"name": "RPG-7", "kind": "at", "damage": [8, 11], "crit": 0, "crit_damage": 0, "clip": 1, "suppression": 30,
		"range": [0, 20, 18, 14, 10, 5, 0, -5, -12, -20, -30, -40], "anti_tank": true, "blast": 0.5},
}
const MRAP_ARMOR := {"front": 2, "side": 1, "rear": 0}
## The JTAC talks a jet onto a target he can see: precise and heavy, two bombs and one smoke screen.
const AIR_STRIKE := {"name": "air strike", "min": 6.0, "max": 999.0, "radius": 2.0, "damage": [4, 7], "scatter": 0.0, "scatter_flat": 0.7,
	"kinds": ["he", "smoke"], "still": false, "spotter": "self"}

const MISSIONS := [
	{
		"name": "Green Zone Patrol",
		"briefing": "Helmand, 2009. Clear the compound, the bazaar and the mosque on the main road. The road is a favourite place for IEDs: let the EOD tech lead.",
		"map": {"seed": 8100, "size": Vector2i(36, 36)},
		"enemy": ["Commander", "Fighter", "Fighter", "Fighter", "Fighter", "PKM Gunner", "Bomb Maker"],
		"vp_to_win": 8, "max_rounds": 14,
	},
	{
		"name": "House to House",
		"briefing": "An Iraqi town, 2004. Insurgents hold the mosque, the market and the police station. Clear them street by street; air support is on call.",
		"map": {"seed": 8201, "size": Vector2i(40, 40)},
		"enemy": ["Commander", "Fighter", "Fighter", "Fighter", "Fighter", "Fighter", "PKM Gunner", "RPG", "Sniper", "Bomb Maker"],
		"enemy_reinforcements": [{"round": 3, "roster": ["Fighter", "Fighter", "RPG"]}],
		"vp_to_win": 10, "max_rounds": 16,
	},
	{
		"name": "Hold the District Centre",
		"briefing": "An MRAP is with us and a quick reaction force flies in on round 4. Everything they have is coming. Hold all three.",
		"map": {"seed": 8302, "size": Vector2i(44, 44)},
		"enemy": ["Commander", "Commander", "Fighter", "Fighter", "Fighter", "Fighter", "Fighter", "Fighter", "PKM Gunner", "PKM Gunner",
			"RPG", "RPG", "Sniper", "Bomb Maker", "Mortar"],
		"enemy_reinforcements": [{"round": 3, "roster": ["Fighter", "Fighter", "Fighter"]}, {"round": 6, "roster": ["Fighter", "RPG", "PKM Gunner"]}],
		"support": ["MRAP"],
		"reinforcements": [{"round": 4, "team": 0, "roster": ["Rifleman", "Rifleman", "SAW Gunner"], "air": true}],
		"vp_to_win": 12, "max_rounds": 16,
	},
]


func _init() -> void:
	id = "modern"
	title = "Afghanistan & Iraq"
	tagline = "Compounds, poppy fields and city streets, 2004-2010. The Coalition against insurgents and their IEDs."
	factions = [
		{
			"name": "Coalition", "adjective": "Coalition", "color": Color("c9b37e"),
			# Multicam combat shirts under plate carriers, desert boots, the MICH helmet.
			"look": {"jacket": Color("8a8261"), "trousers": Color("7d7556"), "helmet": Color("6f6a4e"), "webbing": Color("6b6248"),
				"boots": Color("8d7653"), "leggings": null, "pack": Color("776e50"), "headgear": "mich", "officer_headgear": "mich",
				"skin": Color("cf9f78"), "wood_stock": false, "black_rifles": true, "body_armor": true},
			"vehicle": {"hull": Color("a08f68"), "turret": "none", "marking": "none"},
			"surnames": ["Anderson", "Bennett", "Castillo", "Doyle", "Ellison", "Ford", "Grant", "Harris", "Ibarra", "Jensen",
				"Khan", "Lambert", "Morgan", "Nash", "Ortiz", "Price", "Reid", "Shaw", "Turner", "Webb"],
			"vehicle_names": ["MRAP \"Rhino\"", "MRAP \"Mad Max\"", "MRAP \"Sandman\""],
			"roles": _coalition_roles(),
			"max_units": 12,
			"ai_wishes": ["Team Leader", "Rifleman", "Rifleman", "SAW Gunner", "EOD Tech", "Medic", "JTAC", "Rifleman", "Marksman", "Rifleman",
				"Rifleman", "Rifleman"],
			"ai_heavy": "MRAP",
			"fill_roles": ["Rifleman", "Medic", "Team Leader", "EOD Tech"],
		},
		{
			"name": "Insurgents", "adjective": "insurgent", "color": Color("b07a5a"),
			# Shalwar kameez or dishdasha, a chest rig, sandals, a turban, a pakol or a shemagh.
			"look": {"jacket": Color("8e8574"), "trousers": Color("847b6b"), "helmet": Color("3a3a36"), "webbing": Color("5d5442"),
				"boots": Color("4a3a2a"), "leggings": null, "pack": Color("5c4d34"), "headgear": "turban", "officer_headgear": "pakol",
				"skin": Color("bf8c66"), "wood_stock": true, "sandals": true, "robe": true, "rpg": true,
				"pakol": Color("7d6c52")},
			"vehicle": {"hull": Color("8a8070"), "turret": "box", "marking": "none"},
			"surnames": ["Abdul", "Ahmad", "Bashir", "Daud", "Farid", "Ghulam", "Habib", "Jamal", "Karim", "Latif",
				"Mahmud", "Nasir", "Omar", "Qasim", "Rahim", "Saleh", "Tariq", "Wahid", "Yusuf", "Zahir", "Hamid", "Rashid"],
			"vehicle_names": ["Technical"],
			"roles": _insurgent_roles(),
			"max_units": 20,
			"ai_wishes": ["Commander", "Fighter", "Fighter", "PKM Gunner", "Fighter", "RPG", "Bomb Maker", "Fighter", "Sniper", "Fighter",
				"Mortar", "Fighter", "RPG", "Fighter", "Fighter", "PKM Gunner", "Fighter", "Bomb Maker", "Fighter", "Fighter"],
			"ai_heavy": "",
			"fill_roles": ["Fighter", "Commander", "RPG", "Bomb Maker"],
		},
	]


## Few, armoured and well supported.
static func _coalition_roles() -> Dictionary:
	return {
		"Team Leader": Theatre.role({"name": "Team Leader", "hp": 8, "aim": 72, "mobility": 6.5, "body_armor": 1, "grenades": 2, "smoke": 2,
			"weapon": WEAPONS["m4"], "leader": true, "name_prefix": "Sgt. ", "range": 6.0, "cost": 6, "note": "Leads the fire team",
			"kit": "Officer", "icon": "Officer"}),
		"Rifleman": Theatre.role({"name": "Rifleman", "hp": 8, "aim": 70, "mobility": 6.5, "body_armor": 1, "grenades": 2, "weapon": WEAPONS["m4"],
			"range": 6.0, "cost": 5, "note": "M4 and body armour"}),
		"SAW Gunner": Theatre.role({"name": "SAW Gunner", "hp": 8, "aim": 74, "mobility": 6.0, "body_armor": 1, "grenades": 1, "weapon": WEAPONS["m249"],
			"range": 8.0, "cost": 6, "note": "Light machine gun, no setting up", "kit": "MG", "icon": "MG"}),
		"Marksman": Theatre.role({"name": "Marksman", "hp": 7, "aim": 76, "mobility": 6.0, "body_armor": 1, "sight": 22.0, "weapon": WEAPONS["m110"],
			"range": 12.0, "holds_back": true, "cost": 7, "note": "Long sight, best at range", "kit": "Sniper", "icon": "Sniper"}),
		"Medic": Theatre.role({"name": "Medic", "hp": 7, "aim": 60, "mobility": 6.5, "body_armor": 1, "medkits": 4, "smoke": 1, "weapon": WEAPONS["m4"],
			"range": 6.0, "cost": 5, "note": "Heals and treats wounds"}),
		"JTAC": Theatre.role({"name": "JTAC", "hp": 8, "aim": 64, "mobility": 6.5, "body_armor": 1, "mortar_rounds": 2, "mortar_smoke": 1,
			"weapon": WEAPONS["m4"], "indirect": AIR_STRIKE, "range": 9.0, "holds_back": true, "cost": 9,
			"note": "Calls air strikes on what he sees", "kit": "RTO", "icon": "RTO"}),
		"EOD Tech": Theatre.role({"name": "EOD Tech", "hp": 7, "aim": 62, "mobility": 6.5, "body_armor": 1, "spot_chance": 90, "weapon": WEAPONS["m4"],
			"range": 6.0, "cost": 5, "note": "Finds IEDs and mines almost every time", "kit": "EOD", "icon": "EOD"}),
		"MRAP": Theatre.role({"name": "MRAP", "vehicle": true, "hull_armor": MRAP_ARMOR, "hp": 13, "aim": 60, "sight": 15.0, "mobility": 7.0,
			"weapon": WEAPONS["m2"], "range": 8.0, "cost": 14, "note": "Armoured truck with a .50 cal, built to survive IEDs", "model": "mrap", "icon": "APC"}),
	}


## Many and light; they know where their IEDs are.
static func _insurgent_roles() -> Dictionary:
	return {
		"Commander": Theatre.role({"name": "Commander", "hp": 6, "aim": 60, "mobility": 7.5, "grenades": 1, "smoke": 1, "weapon": WEAPONS["ak47"],
			"leader": true, "range": 6.0, "cost": 4, "note": "Leads and steadies the fighters", "kit": "Officer", "icon": "Officer"}),
		"Fighter": Theatre.role({"name": "Fighter", "hp": 6, "aim": 55, "mobility": 7.5, "grenades": 1, "weapon": WEAPONS["ak47"], "range": 5.0,
			"cost": 2, "note": "AK-47, cheap and quick", "kit": "Assault", "icon": "SMG"}),
		"PKM Gunner": Theatre.role({"name": "PKM Gunner", "hp": 6, "aim": 64, "mobility": 6.5, "weapon": WEAPONS["pkm"], "range": 8.0, "cost": 4,
			"note": "Machine gun, no setting up", "kit": "MG", "icon": "MG"}),
		"RPG": Theatre.role({"name": "RPG", "hp": 6, "aim": 54, "mobility": 7.0, "weapon": WEAPONS["rpg7"], "range": 5.0, "cost": 4,
			"note": "RPG-7: stops the MRAP, blows cover apart", "kit": "AT", "icon": "AT"}),
		"Sniper": Theatre.role({"name": "Sniper", "hp": 5, "aim": 70, "mobility": 6.5, "sight": 22.0, "weapon": WEAPONS["svd"], "range": 12.0,
			"holds_back": true, "cost": 5, "note": "Dragunov, best at range"}),
		"Bomb Maker": Theatre.role({"name": "Bomb Maker", "hp": 5, "aim": 50, "mobility": 7.0, "weapon": WEAPONS["ak47"], "range": 9.0,
			"holds_back": true, "cost": 4, "note": "Plants IEDs and sets them off from cover", "traits": ["traps", "detonator"], "traps": 2,
			"trap_kind": "ied", "kit": "Sapper", "icon": "Sapper"}),
		"Mortar": Theatre.role({"name": "Mortar", "hp": 5, "aim": 50, "mobility": 6.0, "mortar_rounds": 3, "mortar_smoke": 1, "weapon": WEAPONS["ak47"],
			"indirect": {"name": "mortar", "max": 24.0}, "range": 14.0, "holds_back": true, "cost": 4, "note": "82mm mortar"}),
	}


func generate_map(seed: int, size: Vector2i) -> Dictionary:
	return ModernMapGenerator.generate(seed, size)


func is_playable(layout: Dictionary) -> bool:
	return MapGenerator.is_playable(layout)


func skirmish_forces(size: int) -> Dictionary:
	var coalition := ["Team Leader", "Rifleman", "Rifleman", "SAW Gunner", "Medic", "JTAC", "EOD Tech"]
	var insurgents := ["Commander", "Fighter", "Fighter", "Fighter", "Fighter", "Fighter", "PKM Gunner", "RPG", "Sniper", "Bomb Maker", "Mortar"]
	var coalition_wave := ["MRAP", "Rifleman"]
	var insurgent_wave := ["Fighter", "Fighter", "Fighter"]
	var rounds := 20
	var points := 12
	if size >= 60:
		coalition.append_array(["Rifleman", "Rifleman", "Marksman", "SAW Gunner"])
		insurgents.append_array(["Fighter", "Fighter", "Fighter", "RPG", "PKM Gunner", "Bomb Maker"])
		coalition_wave.append("Rifleman")
		insurgent_wave.append_array(["Fighter", "RPG"])
		rounds = 24
		points = 16
	if size >= 80:
		coalition.append_array(["MRAP", "Team Leader", "Rifleman"])
		insurgents.append_array(["Commander", "Fighter", "Fighter", "Sniper", "RPG"])
		coalition_wave.append_array(["Rifleman", "Medic"])
		insurgent_wave.append_array(["Fighter", "Fighter", "PKM Gunner"])
		rounds = 28
		points = 20
	return {
		"rosters": [coalition, insurgents],
		"waves": [{"round": 4, "team": 0, "roster": coalition_wave}, {"round": 3, "team": 1, "roster": insurgent_wave}],
		"max_rounds": rounds, "vp_to_win": points,
	}


## The Coalition scores for the ground it holds; the insurgents for every Coalition soldier they kill (a
## vehicle counts double), each kill worth 1.75 objective-rounds. Points are multiplied by 4 to stay whole:
## 4 per objective per round, 7 per kill, four times the usual points to win.
func battle_options() -> Dictionary:
	return {"kill_points": [0, 7], "objective_points": [4, 0], "points_scale": 4}


func campaign_title() -> String:
	return "Afghanistan & Iraq campaign"


func campaign_blurb() -> String:
	return "Three missions, Helmand and an Iraqi town, with one fire team. Soldiers gain rank, get hurt and die for good."


func campaign_victory() -> Array:
	return ["Mission accomplished", "The district centre held. Your team is going home. The campaign is won."]


func campaign_missions() -> Array:
	return MISSIONS


func campaign_starting_roles() -> Array:
	return ["Team Leader", "Rifleman", "Rifleman", "SAW Gunner", "EOD Tech", "Medic", "JTAC", "Marksman"]


func campaign_recruit_roles() -> Array:
	return ["Rifleman", "SAW Gunner", "EOD Tech", "Medic", "JTAC", "Marksman", "Team Leader"]


func places() -> Array:
	return ["Marjah", "Sangin", "Musa Qala", "Garmsir", "Nad-e Ali", "Fallujah", "Ramadi", "Haditha", "Tal Afar", "Baqubah"]
