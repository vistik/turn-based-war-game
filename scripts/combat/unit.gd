class_name Unit
extends RefCounted
## One soldier on the battlefield. Team 0 is the Allies, team 1 is Germany.

const ACTIONS_PER_TURN := 2
## Suppression levels (0-100) at which a unit is suppressed or pinned down.
const SUPPRESSED_AT := 30
const PINNED_AT := 70
## A hit unit is slowed for its next this-many turns.
const WOUND_TURNS := 2
const WOUND_MOBILITY_PENALTY := 3.0
const SUPPRESSED_MOBILITY_PENALTY := 2.0
const MIN_MOBILITY := 2.0
const RANK_NAMES := ["Pvt.", "Cpl.", "Sgt."]
## Each rank above private adds this much aim and one hit point.
const RANK_AIM := 5
## Fields written to save files.
const SAVED_FIELDS := [
	"id", "name", "role", "team", "pos", "max_hp", "hp", "armor", "aim", "defense", "mobility", "sight", "ammo",
	"grenades", "smoke_grenades", "medkits", "mortar_rounds", "mortar_smoke", "actions", "overwatch", "hunkered",
	"deployed", "suppression", "wounded_turns", "vehicle", "facing", "kills", "rank", "record_id",
]

var id: int
var name: String
var role: String
var team: int
var pos: Vector2i
var max_hp: int
var hp: int
var armor := 0
var aim: int
var defense := 0
## Movement budget per action, in path cost (1 = one open tile).
var mobility: float
var sight := 12.0
var weapon: Weapon
var ammo: int
var grenades := 0
var smoke_grenades := 0
var medkits := 0
var mortar_rounds := 0
var mortar_smoke := 0
var actions := 0
var overwatch := false
var hunkered := false
## Machine gun set up and ready to fire.
var deployed := false
var suppression := 0
var wounded_turns := 0
## Tanks: immune to small arms and suppression, armour depends on which side is hit.
var vehicle := false
## The way the unit last moved or turned, in grid steps. Decides which armour a shot hits.
var facing := Vector2i(1, 0)
var kills := 0
var rank := 0
## The campaign soldier this unit represents, or -1.
var record_id := -1


func is_alive() -> bool:
	return hp > 0


func is_suppressed() -> bool:
	return suppression >= SUPPRESSED_AT


func is_pinned() -> bool:
	return suppression >= PINNED_AT


func is_wounded() -> bool:
	return wounded_turns > 0


## Mobility after wounds and suppression. Pinned units can't move at all.
func current_mobility() -> float:
	if is_pinned():
		return 0.0
	var result := mobility
	if is_wounded():
		result -= WOUND_MOBILITY_PENALTY
	if is_suppressed():
		result -= SUPPRESSED_MOBILITY_PENALTY
	return maxf(MIN_MOBILITY, result)


func to_dict() -> Dictionary:
	var data := {}
	for field: String in SAVED_FIELDS:
		data[field] = get(field)
	return data


static func from_dict(data: Dictionary) -> Unit:
	var u := Unit.create(data["id"], data["name"], data["role"], data["team"], data["pos"])
	for field: String in SAVED_FIELDS:
		u.set(field, data[field])
	return u


static func create(p_id: int, p_name: String, p_role: String, p_team: int, p_pos: Vector2i, p_rank := 0) -> Unit:
	var u := Unit.new()
	u.id = p_id
	u.name = p_name
	u.role = p_role
	u.team = p_team
	u.pos = p_pos
	u.facing = Vector2i(1, 0) if p_team == 0 else Vector2i(-1, 0)
	u.max_hp = 7
	u.aim = 65
	u.mobility = 7.0
	match p_role:
		"Officer":
			u.sight = 13.0
			u.grenades = 1
			u.smoke_grenades = 2
		"Rifleman":
			u.grenades = 1
		"Medic":
			u.max_hp = 6
			u.aim = 55
			u.medkits = 3
			u.smoke_grenades = 1
		"SMG":
			u.aim = 60
			u.mobility = 8.0
			u.grenades = 2
		"MG":
			u.max_hp = 8
			u.aim = 60
			u.mobility = 6.0
		"Sniper":
			u.max_hp = 6
			u.aim = 75
			u.mobility = 6.0
			u.sight = 16.0
		"Mortar":
			u.max_hp = 6
			u.aim = 55
			u.mobility = 6.0
			u.mortar_rounds = 4
			u.mortar_smoke = 2
		"AT":
			u.aim = 60
		"Tank":
			u.vehicle = true
			u.max_hp = 18
			u.aim = 60
			u.sight = 11.0
		_:
			push_error("Unknown role: %s" % p_role)
	u.weapon = Weapon.for_role(p_role, p_team)
	if not u.vehicle:
		u.rank = p_rank
		u.aim += RANK_AIM * p_rank
		u.max_hp += p_rank
	u.hp = u.max_hp
	u.ammo = u.weapon.clip_size
	return u
