class_name Weapon
extends RefCounted

var name: String
## rifle, smg, mg, sniper or carbine. Drives AI range preferences and the soldier art.
var kind: String
var damage_min: int
var damage_max: int
var crit_chance: int
var crit_damage: int
var clip_size: int
## Suppression every shot adds to its target, hit or miss.
var suppression: int
## Aim modifier indexed by distance in tiles; the last entry applies to anything further.
var range_mods: PackedInt32Array
## Machine guns must be set up before firing, and suppress everyone around the target.
var needs_setup := false


func _init(p_name: String, p_kind: String, p_damage: Vector2i, p_crit_chance: int, p_crit_damage: int, p_clip_size: int, p_suppression: int, p_range_mods: Array, p_needs_setup := false) -> void:
	name = p_name
	kind = p_kind
	damage_min = p_damage.x
	damage_max = p_damage.y
	crit_chance = p_crit_chance
	crit_damage = p_crit_damage
	clip_size = p_clip_size
	suppression = p_suppression
	range_mods = PackedInt32Array(p_range_mods)
	needs_setup = p_needs_setup


func range_modifier(distance: float) -> int:
	return range_mods[clampi(roundi(distance), 0, range_mods.size() - 1)]


## The weapon a role carries in a faction (0 = Allies, 1 = Germany).
static func for_role(role: String, faction: int) -> Weapon:
	var allied := faction == 0
	match role:
		"Officer", "SMG":
			return smg(allied)
		"MG":
			return machine_gun(allied)
		"Sniper":
			return sniper(allied)
		"Medic", "Mortar":
			return carbine(allied)
	return rifle(allied)


## The Garand holds more rounds; the Kar98k hits harder and holds its accuracy at range.
static func rifle(allied: bool) -> Weapon:
	if allied:
		return Weapon.new("M1 Garand", "rifle", Vector2i(3, 5), 10, 2, 8, 20, [0, 12, 10, 8, 6, 4, 2, 0, 0, 0, 0, 0, -5, -10, -15, -20])
	return Weapon.new("Kar98k", "rifle", Vector2i(4, 5), 12, 2, 5, 15, [0, 8, 7, 6, 5, 4, 3, 2, 2, 2, 0, 0, 0, -5, -10, -15])


static func smg(allied: bool) -> Weapon:
	if allied:
		return Weapon.new("Thompson", "smg", Vector2i(3, 4), 10, 2, 6, 25, [0, 35, 28, 20, 12, 5, -5, -15, -25, -35, -45])
	return Weapon.new("MP 40", "smg", Vector2i(3, 4), 10, 2, 6, 25, [0, 35, 28, 20, 12, 4, -6, -16, -26, -36, -46])


static func machine_gun(allied: bool) -> Weapon:
	if allied:
		return Weapon.new("M1919 Browning", "mg", Vector2i(3, 5), 5, 2, 5, 45, [0, 0, 5, 5, 5, 5, 5, 5, 5, 5, 0, 0, -5, -5, -10, -10, -15], true)
	return Weapon.new("MG 42", "mg", Vector2i(3, 5), 5, 2, 5, 55, [0, 0, 5, 5, 5, 5, 5, 5, 5, 5, 0, 0, -5, -5, -10, -10, -15], true)


static func sniper(allied: bool) -> Weapon:
	var mods := [0, -20, -15, -10, -5, 0, 5, 8, 10, 12, 14, 15, 15, 15, 15, 15, 12, 10]
	if allied:
		return Weapon.new("M1903 Springfield", "sniper", Vector2i(5, 7), 25, 3, 4, 10, mods)
	return Weapon.new("Kar98k ZF", "sniper", Vector2i(5, 7), 25, 3, 4, 10, mods)


static func carbine(allied: bool) -> Weapon:
	var mods := [0, 12, 10, 8, 5, 2, 0, -2, -5, -10, -15, -20]
	if allied:
		return Weapon.new("M1 Carbine", "carbine", Vector2i(2, 4), 8, 2, 6, 12, mods)
	return Weapon.new("Gewehr 33/40", "carbine", Vector2i(2, 4), 8, 2, 5, 12, mods)
