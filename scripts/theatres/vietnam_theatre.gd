class_name VietnamTheatre
extends Theatre
## Vietnam, 1967: the US Army (team 0, from the west) against the Viet Cong (team 1) among jungle, paddies
## and hamlets. Lopsided on purpose: a few heavily armed, slower Americans with artillery on the radio and
## armour, against many light, fast, poorly armed guerrillas who know the ground (see the "tunnels" and
## "traps" traits), and who win by bleeding the Americans (kill points) as much as by holding ground.

const M16_RANGE := [0, 15, 12, 10, 8, 6, 3, 0, -2, -5, -8, -12, -16, -20]
const AK_RANGE := [0, 25, 20, 15, 10, 6, 3, 0, -4, -8, -12, -18, -24]
const MG_RANGE := [0, 0, 5, 5, 5, 5, 5, 5, 5, 5, 0, 0, -5, -5, -10, -10, -15]
const SNIPER_RANGE := [0, -20, -15, -10, -5, 0, 5, 8, 10, 12, 14, 15, 15, 15, 15, 15, 12, 10]
const ROCKET_RANGE := [0, 20, 15, 10, 5, 0, -5, -10, -20, -30, -40]

const WEAPONS := {
	"m16": {"name": "M16", "kind": "rifle", "damage": [3, 5], "crit": 10, "crit_damage": 2, "clip": 10, "suppression": 22, "range": M16_RANGE},
	"m60": {"name": "M60", "kind": "mg", "damage": [3, 5], "crit": 5, "crit_damage": 2, "clip": 6, "suppression": 50, "range": MG_RANGE, "setup": true},
	## The grenadier's M79 fires buckshot at close quarters; its grenades are lobbed (long throw range).
	"m79": {"name": "M79 (buckshot)", "kind": "launcher", "damage": [2, 5], "crit": 5, "crit_damage": 2, "clip": 1, "suppression": 20,
		"range": [0, 30, 20, 10, 0, -10, -25, -40]},
	"m21": {"name": "M21", "kind": "sniper", "damage": [5, 7], "crit": 25, "crit_damage": 3, "clip": 5, "suppression": 10, "range": SNIPER_RANGE},
	"m2": {"name": "M2 .50 cal", "kind": "mg", "damage": [4, 6], "crit": 10, "crit_damage": 2, "clip": 10, "suppression": 55, "range": MG_RANGE},
	"ak47": {"name": "AK-47", "kind": "assault", "damage": [3, 5], "crit": 10, "crit_damage": 2, "clip": 8, "suppression": 25, "range": AK_RANGE},
	"sks": {"name": "SKS", "kind": "rifle", "damage": [3, 4], "crit": 10, "crit_damage": 2, "clip": 6, "suppression": 15,
		"range": [0, 10, 9, 8, 6, 4, 2, 1, 0, 0, -3, -6, -10, -15]},
	## A light machine gun on a bipod: no setting up, less suppression than a heavy one.
	"rpd": {"name": "RPD", "kind": "mg", "damage": [3, 4], "crit": 5, "crit_damage": 2, "clip": 5, "suppression": 35,
		"range": [0, 10, 10, 8, 6, 5, 4, 3, 2, 0, -3, -6, -10, -15]},
	## Its warhead bursts on the target, tearing away the cover beside it.
	"rpg": {"name": "RPG-2", "kind": "at", "damage": [5, 8], "crit": 0, "crit_damage": 0, "clip": 1, "suppression": 30, "range": ROCKET_RANGE,
		"anti_tank": true, "blast": 0.5},
	"type50": {"name": "Type 50", "kind": "smg", "damage": [3, 4], "crit": 10, "crit_damage": 2, "clip": 6, "suppression": 25,
		"range": [0, 35, 28, 20, 12, 5, -5, -15, -25, -35, -45]},
}
## The M113's aluminium armour stops less than a tank's.
const APC_ARMOR := {"front": 2, "side": 1, "rear": 0}
## The radio operator calls in a 105mm battery: anywhere he can see, no setting up, a big blast, but scattered.
const ARTILLERY := {"name": "artillery", "min": 4.0, "max": 999.0, "radius": 2.0, "damage": [3, 6], "scatter": 0.0, "scatter_flat": 1.5,
	"kinds": ["he", "napalm"], "still": false, "spotter": "self"}

const MISSIONS := [
	{
		"name": "Search and Destroy",
		"briefing": "Quang Ngai province, 1967. A VC cell is using the hamlet, the trail crossing and the old landing zone. Sweep through and clear them. Watch where you step.",
		"map": {"seed": 7101, "size": Vector2i(36, 36)},
		"enemy": ["Cadre", "Guerrilla", "Guerrilla", "Guerrilla", "Guerrilla", "Assault", "Assault", "Sapper"],
		"vp_to_win": 8, "max_rounds": 14,
	},
	{
		"name": "Ambush on the Trail",
		"briefing": "Intelligence says a VC company moves supplies down the trail at night. They know we're coming. Expect them to come up out of the ground.",
		"map": {"seed": 7202, "size": Vector2i(40, 40)},
		"enemy": ["Cadre", "Guerrilla", "Guerrilla", "Guerrilla", "Guerrilla", "Assault", "Assault", "RPD Gunner", "RPG", "Mortar"],
		"enemy_reinforcements": [{"round": 3, "roster": ["Guerrilla", "Guerrilla", "Assault", "Assault"], "tunnels": true}],
		"vp_to_win": 10, "max_rounds": 16,
	},
	{
		"name": "Hold the LZ",
		"briefing": "We're the blocking force. An M113 is with us and more men are coming in by Huey in round 4. Hold the landing zone, the crossing and the hamlet against everything they throw.",
		"map": {"seed": 7303, "size": Vector2i(44, 44)},
		"enemy": ["Cadre", "Cadre", "Guerrilla", "Guerrilla", "Guerrilla", "Guerrilla", "Guerrilla", "Assault", "Assault", "Assault",
			"RPD Gunner", "RPG", "RPG", "Mortar", "Sapper"],
		"enemy_reinforcements": [{"round": 3, "roster": ["Guerrilla", "Guerrilla", "Assault"], "tunnels": true},
			{"round": 6, "roster": ["Guerrilla", "Guerrilla", "RPG"], "tunnels": true}],
		"support": ["M113"],
		"reinforcements": [{"round": 4, "team": 0, "roster": ["Rifleman", "Rifleman", "M60 Gunner"], "air": true}],
		"vp_to_win": 12, "max_rounds": 16,
	},
]


func _init() -> void:
	id = "vietnam"
	title = "Vietnam 1967"
	tagline = "Jungle, paddies and tunnels, 1967. A few heavily armed Americans against many Viet Cong."
	factions = [
		{
			"name": "US Army", "adjective": "American", "color": Color("a6c86b"),
			# Olive drab jungle fatigues, black jungle boots, the M1 helmet in its camouflage cover.
			"look": {"jacket": Color("566338"), "trousers": Color("4b5631"), "helmet": Color("55613a"), "webbing": Color("6e6c4a"),
				"boots": Color("1f1c19"), "leggings": null, "pack": Color("4a5233"), "headgear": "m1_covered",
				"officer_headgear": "m1_covered", "skin": Color("cf9f78"), "wood_stock": false, "black_rifles": true},
			"vehicle": {"hull": Color("4d5934"), "turret": "none", "marking": "star"},
			"surnames": ["Alvarez", "Brooks", "Carter", "Delgado", "Evans", "Fowler", "Greene", "Hayes", "Jackson", "Kowalski",
				"Lopez", "Mitchell", "Novak", "O'Neill", "Perez", "Rossi", "Simmons", "Taylor", "Washington", "Young"],
			"vehicle_names": ["M113 \"Iron Horse\"", "M113 \"Lucky Lady\"", "M113 \"Hellbox\""],
			"roles": _us_roles(),
			"max_units": 12,
			"ai_wishes": ["Squad Leader", "Rifleman", "Rifleman", "M60 Gunner", "Rifleman", "Grenadier", "Medic", "RTO", "Rifleman",
				"Sniper", "Rifleman", "Rifleman"],
			"ai_heavy": "M113",
			"fill_roles": ["Rifleman", "Grenadier", "Squad Leader", "Medic"],
		},
		{
			"name": "Viet Cong", "adjective": "VC", "color": Color("d98a63"),
			# Black cotton "pyjamas", sandals, the conical straw hat; cadres in the green pith helmet.
			"look": {"jacket": Color("2c2b2e"), "trousers": Color("29282b"), "helmet": Color("c8b178"), "webbing": Color("74643f"),
				"boots": Color("4a3a2a"), "leggings": null, "pack": Color("5c4d34"), "headgear": "conical",
				"officer_headgear": "pith", "pith": Color("67733f"), "skin": Color("c4916a"), "wood_stock": true, "sandals": true},
			"vehicle": {"hull": Color("555a4a"), "turret": "box", "marking": "none"},
			"surnames": ["Minh", "Tuan", "Hai", "Hung", "Dung", "Thanh", "Son", "Quang", "Binh", "Long",
				"Phuc", "Khanh", "Tam", "Vinh", "Bao", "Cuong", "Dat", "Hieu", "Nam", "Loc", "Trung", "Kien", "Hoa", "Lan"],
			"vehicle_names": ["Captured truck"],
			"roles": _vc_roles(),
			"max_units": 20,
			"ai_wishes": ["Cadre", "Guerrilla", "Guerrilla", "Assault", "Guerrilla", "RPD Gunner", "RPG", "Assault", "Sapper", "Guerrilla",
				"Mortar", "Guerrilla", "Assault", "Guerrilla", "Guerrilla", "RPG", "Assault", "Guerrilla", "Sapper", "Guerrilla"],
			"ai_heavy": "",
			"fill_roles": ["Guerrilla", "Assault", "Cadre", "Sapper"],
		},
	]


## Few, tough and slow: every American carries a heavy load.
static func _us_roles() -> Dictionary:
	return {
		"Squad Leader": Theatre.role({"name": "Squad Leader", "hp": 8, "aim": 70, "mobility": 6.5, "grenades": 1, "smoke": 2, "weapon": WEAPONS["m16"],
			"leader": true, "name_prefix": "Sgt. ", "range": 6.0, "cost": 6, "note": "Rallies and steadies the squad", "kit": "Officer", "icon": "Officer"}),
		"Rifleman": Theatre.role({"name": "Rifleman", "hp": 8, "aim": 68, "mobility": 6.5, "sight": 11.0, "grenades": 2, "weapon": WEAPONS["m16"],
			"range": 6.0, "cost": 4, "note": "M16 and two grenades"}),
		"Grenadier": Theatre.role({"name": "Grenadier", "hp": 8, "aim": 62, "mobility": 6.5, "grenades": 5, "throw_range": 15.0, "weapon": WEAPONS["m79"],
			"range": 7.0, "cost": 5, "note": "M79: lobs grenades a long way", "kit": "Grenadier", "icon": "Grenadier"}),
		"M60 Gunner": Theatre.role({"name": "M60 Gunner", "hp": 9, "aim": 62, "mobility": 6.0, "weapon": WEAPONS["m60"], "range": 9.0, "cost": 7,
			"note": "Heavy suppression once set up", "kit": "MG", "icon": "MG"}),
		"Medic": Theatre.role({"name": "Medic", "hp": 7, "aim": 58, "mobility": 6.5, "medkits": 4, "smoke": 1, "weapon": WEAPONS["m16"],
			"range": 6.0, "cost": 5, "note": "\"Doc\": heals and treats wounds"}),
		"RTO": Theatre.role({"name": "RTO", "hp": 8, "aim": 62, "mobility": 6.5, "mortar_rounds": 2, "mortar_smoke": 1, "weapon": WEAPONS["m16"],
			"indirect": ARTILLERY, "range": 8.0, "holds_back": true, "cost": 9,
			"note": "Radio: calls artillery or napalm on what he sees", "kit": "RTO", "icon": "RTO"}),
		"Sniper": Theatre.role({"name": "Sniper", "hp": 7, "aim": 75, "mobility": 6.0, "sight": 15.0, "weapon": WEAPONS["m21"], "range": 12.0,
			"holds_back": true, "cost": 7, "note": "Long sight, best at range"}),
		"M113": Theatre.role({"name": "M113", "vehicle": true, "hull_armor": APC_ARMOR, "hp": 14, "aim": 60, "sight": 10.0, "mobility": 7.0,
			"weapon": WEAPONS["m2"], "range": 8.0, "cost": 14, "note": "Armoured carrier with a .50 cal", "model": "m113", "icon": "APC"}),
	}


## Many, light and fast, poorly armed, and at home in the jungle: they move through tunnels and lay traps.
static func _vc_roles() -> Dictionary:
	var vc := func(fields: Dictionary) -> Dictionary:
		var traits: Array = fields.get("traits", []).duplicate()
		traits.append("tunnels")
		fields["traits"] = traits
		return Theatre.role(fields)
	return {
		"Cadre": vc.call({"name": "Cadre", "hp": 6, "aim": 58, "mobility": 7.5, "grenades": 1, "smoke": 1, "weapon": WEAPONS["ak47"], "leader": true,
			"range": 5.0, "cost": 4, "note": "Leads and steadies the cell", "kit": "Officer", "icon": "Officer"}),
		"Guerrilla": vc.call({"name": "Guerrilla", "hp": 5, "aim": 50, "mobility": 7.5, "grenades": 1, "weapon": WEAPONS["sks"], "range": 7.0,
			"cost": 2, "note": "Cheap and quick, an old rifle", "kit": "Guerrilla", "icon": "Rifleman"}),
		"Assault": vc.call({"name": "Assault", "hp": 5, "aim": 55, "mobility": 8.0, "grenades": 2, "weapon": WEAPONS["ak47"], "range": 4.0,
			"cost": 3, "note": "AK-47: deadly up close", "kit": "Assault", "icon": "SMG"}),
		"RPD Gunner": vc.call({"name": "RPD Gunner", "hp": 6, "aim": 52, "mobility": 7.0, "weapon": WEAPONS["rpd"], "range": 8.0, "cost": 4,
			"note": "Light machine gun, no setting up", "kit": "MG", "icon": "MG"}),
		"RPG": vc.call({"name": "RPG", "hp": 5, "aim": 52, "mobility": 7.5, "weapon": WEAPONS["rpg"], "range": 5.0, "cost": 4,
			"note": "RPG-2: stops armour, blows cover apart", "kit": "AT", "icon": "AT"}),
		"Sapper": vc.call({"name": "Sapper", "hp": 5, "aim": 50, "mobility": 8.5, "grenades": 3, "weapon": WEAPONS["type50"], "range": 3.0,
			"cost": 3, "note": "Satchel charges; lays punji traps", "kit": "Sapper", "icon": "Sapper", "traits": ["traps"], "traps": 2}),
		"Mortar": vc.call({"name": "Mortar", "hp": 5, "aim": 50, "mobility": 6.5, "mortar_rounds": 3, "mortar_smoke": 1, "weapon": WEAPONS["sks"],
			"indirect": {"name": "mortar", "max": 20.0}, "range": 14.0, "holds_back": true, "cost": 5, "note": "60mm mortar over the treeline"}),
	}


func generate_map(seed: int, size: Vector2i) -> Dictionary:
	return VietnamMapGenerator.generate(seed, size)


func is_playable(layout: Dictionary) -> bool:
	return MapGenerator.is_playable(layout)


## More Viet Cong than Americans, and more of them the bigger the map. The Americans get men flown in.
func skirmish_forces(size: int) -> Dictionary:
	var us := ["Squad Leader", "Rifleman", "Rifleman", "Rifleman", "M60 Gunner", "Grenadier", "Medic", "RTO"]
	var vc := ["Cadre", "Guerrilla", "Guerrilla", "Guerrilla", "Assault", "Assault", "Assault", "RPD Gunner", "RPG", "Sapper", "Mortar"]
	var us_wave := ["Rifleman", "Rifleman"]
	var vc_wave := ["Guerrilla", "Guerrilla", "Assault"]
	var rounds := 20
	var points := 12
	if size >= 60:
		us.append_array(["Rifleman", "Rifleman", "M60 Gunner", "Sniper"])
		vc.append_array(["Guerrilla", "Guerrilla", "Assault", "Assault", "RPG", "Sapper"])
		us_wave.append("M113")
		vc_wave.append_array(["Guerrilla", "RPG"])
		rounds = 24
		points = 16
	if size >= 80:
		us.append_array(["M113", "Squad Leader", "Grenadier"])
		vc.append_array(["Cadre", "Guerrilla", "Guerrilla", "RPD Gunner", "Mortar"])
		us_wave.append_array(["Rifleman", "Medic"])
		vc_wave.append_array(["Assault", "Assault", "Guerrilla"])
		rounds = 28
		points = 20
	return {
		"rosters": [us, vc],
		"waves": [{"round": 4, "team": 0, "roster": us_wave, "air": true}, {"round": 3, "team": 1, "roster": vc_wave, "tunnels": true}],
		"max_rounds": rounds, "vp_to_win": points,
	}


## The Americans score for the ground they hold; the Viet Cong score for every American they kill (a vehicle
## counts double) and hold ground only to deny it.
func battle_options() -> Dictionary:
	return {"kill_points": [0, 1], "objective_points": [1, 0]}


func campaign_title() -> String:
	return "Vietnam campaign"


func campaign_blurb() -> String:
	return "Three missions in Quang Ngai province with one rifle squad. Soldiers gain rank, get hurt and die for good."


func campaign_victory() -> Array:
	return ["Tour completed", "Your squad held the landing zone. The campaign is won."]


func campaign_missions() -> Array:
	return MISSIONS


func campaign_starting_roles() -> Array:
	return ["Squad Leader", "Rifleman", "Rifleman", "Rifleman", "M60 Gunner", "Grenadier", "Medic", "RTO"]


func campaign_recruit_roles() -> Array:
	return ["Rifleman", "Grenadier", "M60 Gunner", "Medic", "RTO", "Sniper", "Squad Leader"]


func places() -> Array:
	return ["Ben Suc", "Cu Chi", "Bong Son", "Duc Pho", "Song Be", "Loc Ninh", "Dak To", "Tam Ky", "An Lao", "Phu Cat"]
