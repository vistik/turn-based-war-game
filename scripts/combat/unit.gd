class_name Unit
extends RefCounted
## One soldier (or vehicle) on the battlefield. Which side a team is, and what a role can do, comes from the
## battle's theatre (Theatres): team 0 is the Allies in Normandy, the US Army in Vietnam.

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
## Stances. Crouched and prone soldiers are harder to hit but move slower; tanks always count as standing.
enum Stance { STAND, CROUCH, PRONE }
const STANCE_NAMES := ["Standing", "Crouched", "Prone"]
## Path cost is multiplied by this in each stance (crouched walking, crawling).
const STANCE_MOVE_COST := [1.0, 1.5, 3.0]
## Sight lost in each stance: the lower the eyes, the less they see over grass and walls.
const STANCE_SIGHT := [0.0, 1.0, 2.0]
## A crawling soldier always gets at least this far per action.
const MIN_CRAWL := 1.0
## Fields written to save files only when they differ from these defaults (newer abilities, so that units
## without them save, and checksum, as they always have).
const OPTIONAL_FIELDS := {"traps": 0}
## Fields written to save files.
const SAVED_FIELDS := [
	"id", "name", "role", "team", "pos", "max_hp", "hp", "armor", "aim", "defense", "mobility", "sight", "ammo",
	"grenades", "smoke_grenades", "medkits", "mortar_rounds", "mortar_smoke", "actions", "overwatch", "hunkered",
	"deployed", "suppression", "wounded_turns", "vehicle", "facing", "kills", "rank", "record_id", "stance", "fired",
	"under_fire",
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
## Indirect fire rounds: high explosive, and the unit's second kind (smoke for a mortar; see Unit.rounds_left).
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
## Standing, crouched or prone (Stance). Kept until the soldier changes it, which costs an action.
var stance := Stance.STAND
## Fired since the start of its own last turn. The muzzle flash gives away a soldier hidden in the wheat.
var fired := false
## Caught by suppressive fire: keeps its head down and doesn't recover suppression at the start of its next turn.
var under_fire := false
## Punji traps left to lay (Vietnam sappers).
var traps := 0
## Not saved: rebuilt from the theatre, team and role when a unit is created or loaded.
## The theatre id, and the role's definition (see Theatre.role).
var theatre := Theatres.DEFAULT
var def: Dictionary = {}
## Rallies and steadies those around it; its death shakes the side.
var leader := false
## Indirect fire (mortar, artillery), as in Theatre.INDIRECT_DEFAULTS; {} if the unit has none.
var indirect: Dictionary = {}
## Vehicles: the damage each side of the armour stops {"front", "side", "rear"}.
var hull_armor: Dictionary = {}


func has_trait(trait_name: String) -> bool:
	return def.get("traits", []).has(trait_name)


## Rounds left for indirect fire of this kind: high explosive, or the second kind it fires (smoke, napalm).
func rounds_left(kind: String) -> int:
	return mortar_rounds if kind == "he" else mortar_smoke


func is_alive() -> bool:
	return hp > 0


func is_suppressed() -> bool:
	return suppression >= SUPPRESSED_AT


func is_pinned() -> bool:
	return suppression >= PINNED_AT


func is_wounded() -> bool:
	return wounded_turns > 0


## Mobility after wounds, suppression and stance. Pinned units can't move at all.
func current_mobility() -> float:
	if is_pinned():
		return 0.0
	var result := mobility
	if is_wounded():
		result -= WOUND_MOBILITY_PENALTY
	if is_suppressed():
		result -= SUPPRESSED_MOBILITY_PENALTY
	result = maxf(MIN_MOBILITY, result)
	if stance != Stance.STAND:
		result = maxf(MIN_CRAWL, result / STANCE_MOVE_COST[stance])
	return result


## Sight range in the current stance.
func current_sight() -> float:
	return sight - STANCE_SIGHT[stance]


func to_dict() -> Dictionary:
	var data := {}
	for field: String in SAVED_FIELDS:
		data[field] = get(field)
	for field: String in OPTIONAL_FIELDS:
		if get(field) != OPTIONAL_FIELDS[field]:
			data[field] = get(field)
	return data


static func from_dict(data: Dictionary, p_theatre := Theatres.DEFAULT) -> Unit:
	var u := Unit.create(data["id"], data["name"], data["role"], data["team"], data["pos"], 0, p_theatre)
	for field: String in SAVED_FIELDS:
		# Saves from before a field existed keep its default.
		if data.has(field):
			u.set(field, data[field])
	for field: String in OPTIONAL_FIELDS:
		u.set(field, data.get(field, OPTIONAL_FIELDS[field]))
	return u


## A fresh unit of the role, as its theatre defines it for that team.
static func create(p_id: int, p_name: String, p_role: String, p_team: int, p_pos: Vector2i, p_rank := 0, p_theatre := Theatres.DEFAULT) -> Unit:
	var u := Unit.new()
	u.id = p_id
	u.name = p_name
	u.role = p_role
	u.team = p_team
	u.pos = p_pos
	u.theatre = p_theatre
	u.facing = Vector2i(1, 0) if p_team == 0 else Vector2i(-1, 0)
	var theatre_def := Theatres.get_theatre(p_theatre)
	u.def = theatre_def.role_def(p_team, p_role)
	if u.def.is_empty():
		push_error("Unknown role for %s: %s" % [theatre_def.team_name(p_team), p_role])
		u.def = theatre_def.role_def(p_team, theatre_def.role_ids(p_team)[0])
	var d := u.def
	u.max_hp = d["hp"]
	u.aim = d["aim"]
	u.mobility = d["mobility"]
	u.sight = d["sight"]
	u.grenades = d["grenades"]
	u.smoke_grenades = d["smoke"]
	u.medkits = d["medkits"]
	u.mortar_rounds = d["mortar_rounds"]
	u.mortar_smoke = d["mortar_smoke"]
	u.vehicle = d["vehicle"]
	u.hull_armor = d["hull_armor"]
	u.leader = d["leader"]
	u.indirect = d["indirect"]
	u.traps = d.get("traps", 0)
	u.armor = d.get("body_armor", 0)
	u.weapon = Weapon.from_spec(d["weapon"])
	if not u.vehicle:
		u.rank = p_rank
		u.aim += RANK_AIM * p_rank
		u.max_hp += p_rank
	u.hp = u.max_hp
	u.ammo = u.weapon.clip_size
	return u
