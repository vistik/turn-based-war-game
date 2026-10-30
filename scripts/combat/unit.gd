class_name Unit
extends RefCounted
## One soldier on the battlefield.

const ACTIONS_PER_TURN := 2

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
var medkits := 0
var actions := 0
var overwatch := false
var hunkered := false


func is_alive() -> bool:
	return hp > 0


static func create(p_id: int, p_name: String, p_role: String, p_team: int, p_pos: Vector2i) -> Unit:
	var u := Unit.new()
	u.id = p_id
	u.name = p_name
	u.role = p_role
	u.team = p_team
	u.pos = p_pos
	match p_role:
		"Rifleman":
			u.max_hp = 7
			u.aim = 65
			u.mobility = 7.0
			u.weapon = Weapon.rifle()
			u.grenades = 1
		"Assault":
			u.max_hp = 7
			u.aim = 60
			u.mobility = 8.0
			u.weapon = Weapon.shotgun()
			u.grenades = 1
		"Heavy":
			u.max_hp = 9
			u.armor = 1
			u.aim = 60
			u.mobility = 6.0
			u.weapon = Weapon.rifle()
			u.grenades = 2
		"Medic":
			u.max_hp = 6
			u.aim = 65
			u.mobility = 7.0
			u.weapon = Weapon.rifle()
			u.medkits = 2
		_:
			push_error("Unknown role: %s" % p_role)
	u.hp = u.max_hp
	u.ammo = u.weapon.clip_size
	return u
