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


static func create(p_id: int, p_name: String, p_role: String, p_team: int, p_pos: Vector2i) -> Unit:
	var u := Unit.new()
	u.id = p_id
	u.name = p_name
	u.role = p_role
	u.team = p_team
	u.pos = p_pos
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
		_:
			push_error("Unknown role: %s" % p_role)
	u.weapon = Weapon.for_role(p_role, p_team)
	u.hp = u.max_hp
	u.ammo = u.weapon.clip_size
	return u
