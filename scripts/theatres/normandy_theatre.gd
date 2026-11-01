class_name NormandyTheatre
extends Theatre
## Normandy, June 1944: the Allies (team 0, from the west) against Germany (team 1) in the bocage.

## Range modifiers shared by both sides' versions of a weapon.
const SNIPER_RANGE := [0, -20, -15, -10, -5, 0, 5, 8, 10, 12, 14, 15, 15, 15, 15, 15, 12, 10]
const CARBINE_RANGE := [0, 12, 10, 8, 5, 2, 0, -2, -5, -10, -15, -20]
const MG_RANGE := [0, 0, 5, 5, 5, 5, 5, 5, 5, 5, 0, 0, -5, -5, -10, -10, -15]
const ROCKET_RANGE := [0, 20, 15, 10, 5, 0, -5, -10, -20, -30, -40]
const TANK_GUN_RANGE := [0, 0, 5, 5, 5, 5, 5, 5, 5, 5, 5, 0, 0, -5, -5, -10]

## [Allied, German] weapons by kind. The Garand holds more rounds; the Kar98k hits harder and holds its
## accuracy at range. The rocket fires once, then reloads: strong up close, poor at range.
const WEAPONS := {
	"rifle": [
		{"name": "M1 Garand", "kind": "rifle", "damage": [3, 5], "crit": 10, "crit_damage": 2, "clip": 8, "suppression": 20,
			"range": [0, 12, 10, 8, 6, 4, 2, 0, 0, 0, 0, 0, -5, -10, -15, -20]},
		{"name": "Kar98k", "kind": "rifle", "damage": [4, 5], "crit": 12, "crit_damage": 2, "clip": 5, "suppression": 15,
			"range": [0, 8, 7, 6, 5, 4, 3, 2, 2, 2, 0, 0, 0, -5, -10, -15]},
	],
	"smg": [
		{"name": "Thompson", "kind": "smg", "damage": [3, 4], "crit": 10, "crit_damage": 2, "clip": 6, "suppression": 25,
			"range": [0, 35, 28, 20, 12, 5, -5, -15, -25, -35, -45]},
		{"name": "MP 40", "kind": "smg", "damage": [3, 4], "crit": 10, "crit_damage": 2, "clip": 6, "suppression": 25,
			"range": [0, 35, 28, 20, 12, 4, -6, -16, -26, -36, -46]},
	],
	"mg": [
		{"name": "M1919 Browning", "kind": "mg", "damage": [4, 6], "crit": 5, "crit_damage": 2, "clip": 5, "suppression": 45, "range": MG_RANGE, "setup": true},
		{"name": "MG 42", "kind": "mg", "damage": [4, 6], "crit": 5, "crit_damage": 2, "clip": 5, "suppression": 55, "range": MG_RANGE, "setup": true},
	],
	"sniper": [
		{"name": "M1903 Springfield", "kind": "sniper", "damage": [5, 7], "crit": 25, "crit_damage": 3, "clip": 4, "suppression": 10, "range": SNIPER_RANGE},
		{"name": "Kar98k ZF", "kind": "sniper", "damage": [5, 7], "crit": 25, "crit_damage": 3, "clip": 4, "suppression": 10, "range": SNIPER_RANGE},
	],
	"carbine": [
		{"name": "M1 Carbine", "kind": "carbine", "damage": [2, 4], "crit": 8, "crit_damage": 2, "clip": 6, "suppression": 12, "range": CARBINE_RANGE},
		{"name": "Gewehr 33/40", "kind": "carbine", "damage": [2, 4], "crit": 8, "crit_damage": 2, "clip": 5, "suppression": 12, "range": CARBINE_RANGE},
	],
	"at": [
		{"name": "Bazooka", "kind": "at", "damage": [8, 11], "crit": 0, "crit_damage": 0, "clip": 1, "suppression": 30, "range": ROCKET_RANGE, "anti_tank": true},
		{"name": "Panzerschreck", "kind": "at", "damage": [8, 11], "crit": 0, "crit_damage": 0, "clip": 1, "suppression": 30, "range": ROCKET_RANGE, "anti_tank": true},
	],
	"tank": [
		{"name": "75mm M3", "kind": "tank", "damage": [4, 6], "crit": 10, "crit_damage": 2, "clip": 12, "suppression": 60, "range": TANK_GUN_RANGE, "anti_tank": true, "blast": 1.0},
		{"name": "7.5cm KwK 40", "kind": "tank", "damage": [4, 6], "crit": 10, "crit_damage": 2, "clip": 12, "suppression": 60, "range": TANK_GUN_RANGE, "anti_tank": true, "blast": 1.0},
	],
}
## Damage each side of a tank's armour stops.
const TANK_ARMOR := {"front": 3, "side": 1, "rear": 0}

const MISSIONS := [
	{
		"name": "Hedgerow Country",
		"briefing": "D+1. We push inland through the bocage. A thin German screen holds the church, the crossroads and the farm. Take them.",
		"map": {"seed": 1101, "size": Vector2i(36, 36)},
		"enemy": ["Officer", "Rifleman", "Rifleman", "SMG", "MG"],
		"vp_to_win": 8, "max_rounds": 14,
	},
	{
		"name": "The Village",
		"briefing": "D+3. A full German platoon is dug in around the village crossroads, with a mortar behind the church.",
		"map": "village",
		"enemy": ["Officer", "Rifleman", "Rifleman", "Medic", "SMG", "MG", "Sniper", "Mortar"],
		"vp_to_win": 10, "max_rounds": 16,
	},
	{
		"name": "Panzers in the Orchard",
		"briefing": "D+6. Recon spotted a Panzer IV among the orchards. Rifles won't scratch it: get the bazooka round its side or rear.",
		"map": {"seed": 3303, "size": Vector2i(40, 40)},
		"enemy": ["Officer", "Rifleman", "Rifleman", "SMG", "MG", "Tank"],
		"vp_to_win": 10, "max_rounds": 16,
	},
	{
		"name": "Counterattack",
		"briefing": "D+9. The Germans are coming back with armour. A Sherman has joined us. Hold the ground we took.",
		"map": {"seed": 4404, "size": Vector2i(40, 40)},
		"enemy": ["Officer", "Rifleman", "Rifleman", "SMG", "MG", "AT"],
		"enemy_reinforcements": [{"round": 3, "roster": ["Tank", "Rifleman", "Rifleman"]}, {"round": 6, "roster": ["Rifleman", "SMG"]}],
		"support": ["Tank"],
		"vp_to_win": 10, "max_rounds": 14,
	},
	{
		"name": "The Road to Caen",
		"briefing": "D+14. The last ridge before Caen. Everything they have left is waiting for us. This is it.",
		"map": {"seed": 5505, "size": Vector2i(46, 46)},
		"enemy": ["Officer", "Rifleman", "Rifleman", "Rifleman", "Medic", "SMG", "MG", "Sniper", "Mortar", "AT", "Tank"],
		"enemy_reinforcements": [{"round": 4, "roster": ["Tank", "Rifleman"]}],
		"support": ["Tank"],
		"vp_to_win": 12, "max_rounds": 18,
	},
]


func _init() -> void:
	id = "normandy"
	title = "Normandy 1944"
	tagline = "Squad tactics in the bocage, June 1944. Allies against Germany."
	# Allies: M1941 khaki field jacket, olive trousers, canvas leggings, brown boots and the round M1 helmet.
	# Germany: field grey tunic and trousers, black jackboots and the flared Stahlhelm.
	factions = [
		{
			"name": "Allies", "adjective": "Allied", "color": Color("9cc45a"),
			"look": {"jacket": Color("857c4f"), "trousers": Color("5a5a3a"), "helmet": Color("535a33"), "webbing": Color("a0976a"),
				"boots": Color("5b412a"), "leggings": Color("aaa07a"), "pack": Color("6d6a45"), "headgear": "m1",
				"officer_headgear": "m1_striped", "skin": Color("d3a37b"), "wood_stock": true},
			"vehicle": {"hull": Color("5d6838"), "turret": "round", "marking": "star"},
			"surnames": ["Adams", "Baker", "Collins", "Dawson", "Ellis", "Fisher", "Garcia", "Hughes", "Kowalski", "Lewis",
				"Murphy", "Novak", "O'Brien", "Parker", "Reyes", "Sullivan", "Turner", "Walsh", "Young", "Zimmer"],
			"vehicle_names": ["Sherman \"Lucky\"", "Sherman \"Bulldog\"", "Sherman \"Ironside\""],
			"roles": _roles(0),
			"ai_wishes": ["Officer", "Rifleman", "Rifleman", "MG", "Rifleman", "AT", "Medic", "SMG", "Sniper", "Rifleman",
				"Mortar", "Rifleman", "SMG", "Rifleman"],
			"ai_heavy": "Tank",
			"fill_roles": ["Rifleman", "SMG", "Officer", "MG", "Mortar"],
		},
		{
			"name": "Germany", "adjective": "German", "color": Color("b8c0c8"),
			"look": {"jacket": Color("5c6459"), "trousers": Color("50564f"), "helmet": Color("474c48"), "webbing": Color("2b2723"),
				"boots": Color("1c1a18"), "leggings": null, "pack": Color("5d5141"), "headgear": "stahlhelm",
				"officer_headgear": "peaked_cap", "skin": Color("d3a37b")},
			"vehicle": {"hull": Color("5b6262"), "turret": "box", "marking": "cross"},
			"surnames": ["Bauer", "Braun", "Frank", "Hartmann", "Huber", "Jung", "Keller", "Koch", "Krause", "Lehmann",
				"Maier", "Neumann", "Otto", "Peters", "Richter", "Schulz", "Schwarz", "Vogt", "Weber", "Wolff"],
			"vehicle_names": ["Panzer IV 412", "Panzer IV 427", "Panzer IV 433"],
			"roles": _roles(1),
			"ai_wishes": ["Officer", "Rifleman", "Rifleman", "MG", "Rifleman", "AT", "Medic", "SMG", "Sniper", "Rifleman",
				"Mortar", "Rifleman", "SMG", "Rifleman"],
			"ai_heavy": "Tank",
			"fill_roles": ["Rifleman", "SMG", "Officer", "MG", "Mortar"],
		},
	]


## Both sides field the same roles; only the weapons and the look differ.
static func _roles(side: int) -> Dictionary:
	var w := func(kind: String) -> Dictionary: return WEAPONS[kind][side]
	return {
		"Officer": Theatre.role({"name": "Officer", "sight": 19.0, "grenades": 1, "smoke": 2, "weapon": w.call("smg"), "leader": true,
			"name_prefix": "Lt. ", "range": 5.0, "cost": 5, "note": "Rallies and steadies nearby soldiers"}),
		"Rifleman": Theatre.role({"name": "Rifleman", "grenades": 1, "weapon": w.call("rifle"), "range": 7.0, "cost": 3,
			"note": "Reliable all-rounder with a grenade"}),
		"SMG": Theatre.role({"name": "SMG", "aim": 60, "mobility": 8.0, "grenades": 2, "weapon": w.call("smg"), "range": 3.0, "cost": 4,
			"note": "Fast, deadly up close"}),
		"MG": Theatre.role({"name": "MG", "hp": 8, "aim": 70, "mobility": 6.0, "weapon": w.call("mg"), "range": 9.0, "cost": 6,
			"note": "Heavy suppression once set up"}),
		"AT": Theatre.role({"name": "AT", "aim": 60, "weapon": w.call("at"), "range": 4.0, "cost": 6,
			"note": "Bazooka: the answer to tanks" if side == 0 else "Panzerschreck: the answer to tanks"}),
		"Medic": Theatre.role({"name": "Medic", "hp": 6, "aim": 55, "medkits": 3, "smoke": 1, "weapon": w.call("carbine"), "range": 6.0,
			"cost": 4, "note": "Heals and treats wounds"}),
		"Sniper": Theatre.role({"name": "Sniper", "hp": 6, "aim": 75, "mobility": 6.0, "sight": 24.0, "weapon": w.call("sniper"),
			"range": 12.0, "holds_back": true, "cost": 6, "note": "Long sight, best at range"}),
		"Mortar": Theatre.role({"name": "Mortar", "hp": 6, "aim": 55, "mobility": 6.0, "mortar_rounds": 4, "mortar_smoke": 2,
			"weapon": w.call("carbine"), "indirect": {"name": "mortar"}, "range": 14.0, "holds_back": true, "cost": 5,
			"note": "Indirect fire over cover"}),
		"Tank": Theatre.role({"name": "Tank", "vehicle": true, "hull_armor": TANK_ARMOR, "hp": 18, "aim": 60, "sight": 16.0,
			"weapon": w.call("tank"), "range": 8.0, "cost": 15, "note": "Armoured, rifles can't hurt it",
			"model": "sherman" if side == 0 else "panzer4"}),
	}


func generate_map(seed: int, size: Vector2i) -> Dictionary:
	return MapGenerator.generate(seed, size)


func is_playable(layout: Dictionary) -> bool:
	return MapGenerator.is_playable(layout)


func village_layout() -> Dictionary:
	return NormandyScenario.layout()


func village_title() -> String:
	return "Normandy village"


func village_forces() -> Dictionary:
	var waves := []
	for team in 2:
		waves.append({"round": NormandyScenario.REINFORCEMENT_ROUND, "team": team, "roster": NormandyScenario.REINFORCEMENTS})
	return {"rosters": [NormandyScenario.ROSTER, NormandyScenario.ROSTER], "waves": waves, "max_rounds": 20, "vp_to_win": 12}


## Bigger maps bring bigger forces, need more points to win and allow more rounds.
func skirmish_forces(size: int) -> Dictionary:
	var roster := NormandyScenario.ROSTER.duplicate()
	var wave := NormandyScenario.REINFORCEMENTS.duplicate()
	var rounds := 20
	var points := 12
	if size >= 60:
		roster.append_array(["Rifleman", "Rifleman", "SMG", "AT"])
		wave.append("Rifleman")
		rounds = 24
		points = 16
	if size >= 80:
		roster.append_array(["Tank", "MG", "Medic"])
		wave.append_array(["Tank", "SMG"])
		rounds = 28
		points = 20
	var waves := []
	for team in 2:
		waves.append({"round": NormandyScenario.REINFORCEMENT_ROUND, "team": team, "roster": wave})
	return {"rosters": [roster, roster], "waves": waves, "max_rounds": rounds, "vp_to_win": points}


func campaign_title() -> String:
	return "Normandy campaign"


func campaign_blurb() -> String:
	return "Five missions from the beaches to Caen with one squad. Soldiers gain rank, get hurt and die for good."


func campaign_victory() -> Array:
	return ["Victory in Normandy", "Your squad fought its way to Caen. The campaign is won."]


func campaign_missions() -> Array:
	return MISSIONS


func campaign_starting_roles() -> Array:
	return ["Officer", "Rifleman", "Rifleman", "AT", "Medic", "SMG", "MG", "Sniper"]


func campaign_recruit_roles() -> Array:
	return ["Rifleman", "AT", "Medic", "SMG", "MG", "Sniper", "Mortar", "Officer"]


func places() -> Array:
	return ["Carentan", "Sainte-Mère-Église", "Villers-Bocage", "Hill 112", "Saint-Lô", "Tilly-sur-Seulles",
		"Cheux", "Caumont", "Le Mesnil", "Hottot"]
